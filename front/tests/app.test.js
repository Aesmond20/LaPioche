import { assertEqual, assertIncludes, assertTrue, test, waitFor } from "./runner.js";
import { mountApp } from "./helpers.js";

const catan = { id: "g1", title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90, isAvailable: true };
const dixit = { id: "g2", title: "Dixit", minPlayers: 3, maxPlayers: 6, durationMinutes: 30, isAvailable: false };
const camille = { id: "m1", name: "Camille", email: "camille@example.com" };

const cardOf = (app, title) => app.$$("#games-list .card").find((card) => card.querySelector("h3").textContent === title);
const rowOf = (app, name) => app.$$("#members-list .row").find((row) => row.querySelector("strong").textContent === name);

// --- Jeux

test("games list shows one card per game with its availability", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });
  await waitFor(() => app.$$("#games-list .card").length === 2, "deux cartes de jeu");
  assertIncludes(cardOf(app, "Catan").textContent, "Disponible");
  assertIncludes(cardOf(app, "Dixit").textContent, "Emprunté");
  assertIncludes(cardOf(app, "Catan").textContent, "3 à 4 joueur·ses · 90 min");
});

test("only an available game offers Borrow", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });
  await waitFor(() => app.$$("#games-list .card").length === 2);
  const labels = (title) => [...cardOf(app, title).querySelectorAll("button")].map((button) => button.textContent);
  assertTrue(labels("Catan").includes("Emprunter"), "Catan devrait proposer Emprunter");
  assertTrue(!labels("Dixit").includes("Emprunter"), "Dixit est emprunté, il ne doit pas proposer Emprunter");
});

test("with no game, a message invites to add one", async () => {
  const app = await mountApp({ "GET /games": [] });
  await waitFor(() => !app.$("#games-empty").hidden);
  assertIncludes(app.$("#games-empty").textContent, "ne contient aucun jeu");
  assertIncludes(app.$("#games-empty").textContent, "Ajouter un jeu");
});

test("adding a game posts the form then reloads the list", async () => {
  const app = await mountApp({ "GET /games": [catan], "POST /games": [201, { ...catan, id: "g3", title: "Dixit" }] });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Ajouter un jeu");
  const form = app.$("#game-form");
  form.elements.title.value = "  Dixit ";
  form.elements.minPlayers.value = "3";
  form.elements.maxPlayers.value = "6";
  form.elements.durationMinutes.value = "30";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/games"), "l'appel POST /games");
  assertEqual(app.calls.find((call) => call.method === "POST").body, {
    title: "Dixit",
    minPlayers: 3,
    maxPlayers: 6,
    durationMinutes: 30,
  });
  await waitFor(() => !app.$("#game-dialog").open, "la boîte se ferme");
});

test("a validation error is shown in French and the dialog stays open", async () => {
  const app = await mountApp({
    "GET /games": [],
    "POST /games": [400, { error: true, reason: "title is empty, durationMinutes is less than minimum of 1" }],
  });
  await waitFor(() => !app.$("#games-empty").hidden, "la page est chargée");
  app.click("Ajouter un jeu");
  app.$("#game-form").requestSubmit();
  await waitFor(() => !app.$("#game-dialog .form-error").hidden, "le message d'erreur");
  assertEqual(app.$("#game-dialog .form-error").textContent, "Le titre est obligatoire. La durée doit être d'au moins 1.");
  assertTrue(app.$("#game-dialog").open, "la boîte devrait rester ouverte");
});

test("editing a game opens a prefilled form, sends a PUT and refreshes the list", async () => {
  let games = [catan];
  const app = await mountApp({
    "GET /games": () => games,
    "PUT /games/g1": ({ body }) => {
      games = [{ ...catan, ...body }];
      return [200, games[0]];
    },
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Modifier", cardOf(app, "Catan"));
  await waitFor(() => app.$("#game-dialog").open, "le formulaire de modification");

  const form = app.$("#game-form");
  assertEqual(form.elements.title.value, "Catan");
  assertEqual(form.elements.minPlayers.value, "3");
  assertEqual(form.elements.maxPlayers.value, "4");
  assertEqual(form.elements.durationMinutes.value, "90");

  form.elements.title.value = "Catan Junior";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "PUT"), "l'appel PUT");
  const put = app.calls.find((call) => call.method === "PUT");
  assertEqual(put.path, "/games/g1");
  assertEqual(put.body, { title: "Catan Junior", minPlayers: 3, maxPlayers: 4, durationMinutes: 90 });
  await waitFor(() => cardOf(app, "Catan Junior"), "la liste affiche le nouveau titre");
  assertTrue(!app.$("#game-dialog").open, "la boîte devrait se fermer");
});

test("deleting a game asks for confirmation then removes it from the list", async () => {
  let games = [catan, dixit];
  const app = await mountApp({
    "GET /games": () => games,
    "DELETE /games/g1": () => {
      games = [dixit];
      return [204];
    },
  });
  await waitFor(() => app.$$("#games-list .card").length === 2);
  app.click("Supprimer", cardOf(app, "Catan"));
  await waitFor(() => app.$("#confirm-dialog").open, "la demande de confirmation");
  assertIncludes(app.$("#confirm-message").textContent, "Catan");
  assertTrue(!app.calls.some((call) => call.method === "DELETE"), "rien ne doit être supprimé avant la confirmation");

  app.$("#confirm-form").requestSubmit();
  await waitFor(() => app.$$("#games-list .card").length === 1, "le jeu disparaît de la liste");
  assertEqual(app.calls.find((call) => call.method === "DELETE").path, "/games/g1");
  assertTrue(!cardOf(app, "Catan"), "Catan ne devrait plus être affiché");
  await waitFor(() => app.$("#toasts").textContent.includes("supprimé"), "le message de confirmation");
});

test("a refused deletion is shown in French and the confirmation stays open", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "DELETE /games/g1": [409, { error: true, reason: "A game with loans cannot be deleted" }],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Supprimer", cardOf(app, "Catan"));
  await waitFor(() => app.$("#confirm-dialog").open, "la demande de confirmation");
  app.$("#confirm-form").requestSubmit();
  await waitFor(() => !app.$("#confirm-dialog .form-error").hidden, "le message d'erreur");
  assertIncludes(app.$("#confirm-dialog .form-error").textContent, "historique d'emprunts");
  assertTrue(app.$("#confirm-dialog").open, "la confirmation devrait rester ouverte");
});

// --- Emprunts

test("borrowing a game sends the game and the chosen member", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "GET /members": [camille],
    "POST /loans": [201, { id: "l1", gameID: "g1", memberID: "m1", borrowedAt: new Date().toISOString(), dueAt: new Date().toISOString() }],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#borrow-dialog").open, "la boîte d'emprunt");
  app.$("#borrow-form").requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/loans"), "l'appel POST /loans");
  assertEqual(app.calls.find((call) => call.path === "/loans").body, { gameID: "g1", memberID: "m1" });
  await waitFor(() => app.$("#toasts").textContent.includes("emprunté"), "le message de confirmation");
});

test("borrowing without any member explains that one must be added first", async () => {
  const app = await mountApp({ "GET /games": [catan], "GET /members": [] });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#toasts").textContent.includes("Ajoutez d'abord"), "le message d'aide");
  assertTrue(!app.$("#borrow-dialog").open, "la boîte d'emprunt ne doit pas s'ouvrir");
});

test("returning a borrowed game finds its current loan, calls the return route and updates the screen", async () => {
  const alex = { id: "m2", name: "Alex", email: "alex@example.com" };
  let games = [dixit];
  const app = await mountApp({
    "GET /games": () => games,
    "GET /members": [alex, camille],
    "GET /members/m2/loans": [],
    "GET /members/m1/loans": [
      { id: "l0", gameID: "g2", memberID: "m1", borrowedAt: "2026-09-01T10:00:00Z", dueAt: "2026-09-15T10:00:00Z", returnedAt: "2026-09-10T10:00:00Z" },
      { id: "l1", gameID: "g2", memberID: "m1", borrowedAt: "2026-11-10T10:00:00Z", dueAt: "2026-11-24T10:00:00Z" },
    ],
    "POST /loans/l1/return": () => {
      games = [{ ...dixit, isAvailable: true }];
      return [200, { id: "l1", gameID: "g2", memberID: "m1", returnedAt: new Date().toISOString() }];
    },
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  assertIncludes(cardOf(app, "Dixit").textContent, "Rendre");

  app.click("Rendre", cardOf(app, "Dixit"));
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path.endsWith("/return")), "l'appel de retour");
  assertEqual(app.calls.find((call) => call.path.endsWith("/return")).path, "/loans/l1/return");

  await waitFor(() => cardOf(app, "Dixit").textContent.includes("Disponible"), "le jeu redevient disponible à l'écran");
  const labels = [...cardOf(app, "Dixit").querySelectorAll("button")].map((button) => button.textContent);
  assertTrue(labels.includes("Emprunter") && !labels.includes("Rendre"), "le jeu rendu doit proposer Emprunter et non Rendre");
  await waitFor(() => app.$("#toasts").textContent.includes("a bien été rendu"), "le message de confirmation");
});

test("a failed return is shown in French", async () => {
  const app = await mountApp({
    "GET /games": [dixit],
    "GET /members": [camille],
    "GET /members/m1/loans": [{ id: "l1", gameID: "g2", memberID: "m1", borrowedAt: "2026-11-10T10:00:00Z", dueAt: "2026-11-24T10:00:00Z" }],
    "POST /loans/l1/return": [409, { error: true, reason: "Loan is already returned" }],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Rendre", cardOf(app, "Dixit"));
  await waitFor(() => app.$("#toasts .error"), "le message d'erreur");
  assertEqual(app.$("#toasts .error").textContent, "Cet emprunt a déjà été rendu.");
});

// --- Adhérent·es

test("members tab lists the members", async () => {
  const app = await mountApp({ "GET /members": [camille] }, { hash: "#members" });
  await waitFor(() => app.$$("#members-list .row").length === 1);
  assertIncludes(app.$("#members-list .row").textContent, "Camille");
  assertIncludes(app.$("#members-list .row").textContent, "camille@example.com");
});

test("with no member, a message invites to add one", async () => {
  const app = await mountApp({ "GET /members": [] }, { hash: "#members" });
  await waitFor(() => !app.$("#members-empty").hidden);
  assertIncludes(app.$("#members-empty").textContent, "Ajouter un·e adhérent·e");
});

test("adding a member posts the form", async () => {
  const app = await mountApp({ "GET /members": [], "POST /members": [201, camille] }, { hash: "#members" });
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  const form = app.$("#member-form");
  form.elements.name.value = " Camille ";
  form.elements.email.value = "camille@example.com";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/members"), "l'appel POST /members");
  assertEqual(app.calls.find((call) => call.method === "POST").body, { name: "Camille", email: "camille@example.com" });
});

test("an email already in use is shown in French", async () => {
  const app = await mountApp(
    { "GET /members": [], "POST /members": [409, { error: true, reason: "A member with this email already exists" }] },
    { hash: "#members" },
  );
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  app.$("#member-form").requestSubmit();
  await waitFor(() => !app.$("#member-dialog .form-error").hidden, "le message d'erreur");
  assertIncludes(app.$("#member-dialog .form-error").textContent, "utilise déjà cette adresse e-mail");
});

test("editing a member opens a prefilled form, sends a PUT and refreshes the list", async () => {
  let members = [camille];
  const app = await mountApp(
    {
      "GET /members": () => members,
      "PUT /members/m1": ({ body }) => {
        members = [{ ...camille, ...body }];
        return [200, members[0]];
      },
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Modifier", rowOf(app, "Camille"));
  await waitFor(() => app.$("#member-dialog").open, "le formulaire de modification");

  const form = app.$("#member-form");
  assertEqual(form.elements.name.value, "Camille");
  assertEqual(form.elements.email.value, "camille@example.com");

  form.elements.name.value = "Camille Martin";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "PUT"), "l'appel PUT");
  const put = app.calls.find((call) => call.method === "PUT");
  assertEqual(put.path, "/members/m1");
  assertEqual(put.body, { name: "Camille Martin", email: "camille@example.com" });
  await waitFor(() => rowOf(app, "Camille Martin"), "la liste affiche le nouveau nom");
  assertTrue(!app.$("#member-dialog").open, "la boîte devrait se fermer");
});

test("editing a member with an email used by someone else shows a French error in the form", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "PUT /members/m1": [409, { error: true, reason: "A member with this email already exists" }],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Modifier", rowOf(app, "Camille"));
  await waitFor(() => app.$("#member-dialog").open, "le formulaire de modification");
  app.$("#member-form").elements.email.value = "alex@example.com";
  app.$("#member-form").requestSubmit();
  await waitFor(() => !app.$("#member-dialog .form-error").hidden, "le message d'erreur");
  assertEqual(app.$("#member-dialog .form-error").textContent, "Un·e autre adhérent·e utilise déjà cette adresse e-mail.");
  assertTrue(app.$("#member-dialog").open, "le formulaire devrait rester ouvert");
  assertEqual(app.$("#member-form").elements.email.value, "alex@example.com");
});

test("deleting a member asks for confirmation then removes them from the list", async () => {
  const alex = { id: "m2", name: "Alex", email: "alex@example.com" };
  let members = [camille, alex];
  const app = await mountApp(
    {
      "GET /members": () => members,
      "DELETE /members/m1": () => {
        members = [alex];
        return [204];
      },
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 2);
  app.click("Supprimer", rowOf(app, "Camille"));
  await waitFor(() => app.$("#confirm-dialog").open, "la demande de confirmation");
  assertIncludes(app.$("#confirm-message").textContent, "Camille");
  assertTrue(!app.calls.some((call) => call.method === "DELETE"), "rien ne doit être supprimé avant la confirmation");

  app.$("#confirm-form").requestSubmit();
  await waitFor(() => app.$$("#members-list .row").length === 1, "la personne disparaît de la liste");
  assertEqual(app.calls.find((call) => call.method === "DELETE").path, "/members/m1");
  assertTrue(!rowOf(app, "Camille"), "Camille ne devrait plus être affiché·e");
});

test("a refused member deletion is shown in French and the confirmation stays open", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "DELETE /members/m1": [409, { error: true, reason: "A member with loans cannot be deleted" }],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Supprimer", rowOf(app, "Camille"));
  await waitFor(() => app.$("#confirm-dialog").open, "la demande de confirmation");
  app.$("#confirm-form").requestSubmit();
  await waitFor(() => !app.$("#confirm-dialog .form-error").hidden, "le message d'erreur");
  assertIncludes(app.$("#confirm-dialog .form-error").textContent, "historique d'emprunts");
  assertTrue(app.$("#confirm-dialog").open, "la confirmation devrait rester ouverte");
});

test("a member's loans show the game title, the dates and each of the three states", async () => {
  const day = 24 * 60 * 60 * 1000;
  const azul = { id: "g3", title: "Azul", minPlayers: 2, maxPlayers: 4, durationMinutes: 45, isAvailable: false };
  const app = await mountApp(
    {
      "GET /members": [camille],
      "GET /games": [catan, dixit, azul],
      "GET /members/m1/loans": [
        { id: "l1", gameID: "g1", memberID: "m1", borrowedAt: "2026-09-01T10:00:00Z", dueAt: "2026-09-15T10:00:00Z", returnedAt: "2026-09-10T10:00:00Z" },
        { id: "l2", gameID: "g2", memberID: "m1", borrowedAt: new Date(Date.now() - 2 * day).toISOString(), dueAt: new Date(Date.now() + 12 * day).toISOString() },
        { id: "l3", gameID: "g3", memberID: "m1", borrowedAt: new Date(Date.now() - 20 * day).toISOString(), dueAt: new Date(Date.now() - 6 * day).toISOString() },
      ],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Emprunts", rowOf(app, "Camille"));
  await waitFor(() => app.$("#loans-dialog").open, "le panneau des emprunts");

  assertIncludes(app.$("#loans-dialog-title").textContent, "Camille");
  const rows = app.$$("#loans-list .row");
  assertEqual(rows.length, 3);
  assertTrue(app.$("#loans-empty").hidden, "le message de liste vide doit être caché");

  assertIncludes(rows[0].textContent, "Catan");
  assertIncludes(rows[0].textContent, "Emprunté le 1 septembre 2026");
  assertIncludes(rows[0].textContent, "retour prévu le 15 septembre 2026");
  assertIncludes(rows[0].textContent, "Rendu");
  assertIncludes(rows[1].textContent, "Dixit");
  assertIncludes(rows[1].textContent, "En cours");
  assertIncludes(rows[2].textContent, "Azul");
  assertIncludes(rows[2].textContent, "En retard");
  assertTrue(!app.$("#loans-list").textContent.includes("g1"), "l'identifiant du jeu ne doit pas être affiché");
});

test("a member without loans sees a clear message", async () => {
  const app = await mountApp(
    { "GET /members": [camille], "GET /games": [catan], "GET /members/m1/loans": [] },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Emprunts", rowOf(app, "Camille"));
  await waitFor(() => app.$("#loans-dialog").open, "le panneau des emprunts");

  assertTrue(!app.$("#loans-empty").hidden, "le message de liste vide doit être visible");
  assertIncludes(app.$("#loans-empty").textContent, "Aucun emprunt");
  assertEqual(app.$$("#loans-list .row").length, 0);
});
