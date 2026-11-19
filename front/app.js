import { API_URL } from "./config.js";
import { api } from "./api.js";

const $ = (selector, root = document) => root.querySelector(selector);

$("#docs-link").href = API_URL;

const dateFormat = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long" });
const formatDate = (iso) => dateFormat.format(new Date(iso));

// Construit un élément sans jamais passer par innerHTML : les données de
// l'API (titres, noms) sont insérées comme du texte.
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

function button(label, onClick, className = "") {
  return el("button", { type: "button", class: className, onclick: onClick }, label);
}

function toast(message, isError = false) {
  const node = el("p", { class: isError ? "toast error" : "toast" }, message);
  $("#toasts").append(node);
  setTimeout(() => node.remove(), 5000);
}

// Exécute une action déclenchée par un bouton et affiche l'erreur de l'API.
async function run(action) {
  try {
    await action();
  } catch (error) {
    toast(error.message, true);
  }
}

function showFormError(dialog, error) {
  const target = $(".form-error", dialog);
  target.textContent = error ? error.message : "";
  target.hidden = !error;
}

for (const cancel of document.querySelectorAll("[data-cancel]")) {
  cancel.addEventListener("click", () => cancel.closest("dialog").close());
}

// Branche un formulaire de boîte de dialogue sur un appel à l'API.
// L'erreur renvoyée par l'API reste affichée dans la boîte, qui ne se ferme
// qu'en cas de succès.
function bindSubmit(dialog, form, handler) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    showFormError(dialog, null);
    try {
      await handler(new FormData(form));
      dialog.close();
      await refresh();
    } catch (error) {
      showFormError(dialog, error);
    }
  });
}

// --- Confirmation -----------------------------------------------------------

// Demande une confirmation avant une action irréversible. L'action n'est lancée
// qu'au clic sur le bouton de validation ; si l'API la refuse, l'erreur reste
// affichée dans la boîte.
const confirmDialog = $("#confirm-dialog");
const confirmForm = $("#confirm-form");
let confirmAction = null;

function askConfirmation(message, action) {
  confirmAction = action;
  $("#confirm-message").textContent = message;
  showFormError(confirmDialog, null);
  confirmDialog.showModal();
}

bindSubmit(confirmDialog, confirmForm, () => confirmAction());

// --- Onglets ---------------------------------------------------------------

const tabs = ["games", "members", "overdue"];
const loaders = { games: loadGames, members: loadMembers, overdue: loadOverdue };

function currentTab() {
  const name = location.hash.slice(1);
  return tabs.includes(name) ? name : "games";
}

async function refresh() {
  const tab = currentTab();
  for (const name of tabs) {
    $(`#${name}`).hidden = name !== tab;
    $(`[data-tab="${name}"]`).toggleAttribute("aria-current", name === tab);
  }
  await run(loaders[tab]);
  await updateOverdueCount();
}

window.addEventListener("hashchange", refresh);

// --- Jeux ------------------------------------------------------------------

const filtersForm = $("#games-filters");

function positiveInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : undefined;
}

function currentFilters() {
  const data = new FormData(filtersForm);
  return {
    q: data.get("q").trim() || undefined,
    players: positiveInteger(data.get("players")),
    maxDuration: positiveInteger(data.get("maxDuration")),
    available: data.get("available") ? true : undefined,
  };
}

async function loadGames() {
  const filters = currentFilters();
  const games = await api.listGames(filters);
  const searching = Object.values(filters).some((value) => value !== undefined);
  $("#games-empty").hidden = games.length > 0 || searching;
  $("#games-no-result").hidden = games.length > 0 || !searching;
  $("#games-list").replaceChildren(...games.map(gameCard));
}

filtersForm.addEventListener("input", () => run(loadGames));
filtersForm.addEventListener("submit", (event) => event.preventDefault());
$("#reset-filters").addEventListener("click", () => {
  filtersForm.reset();
  run(loadGames);
});

function gameCard(game) {
  const players =
    game.minPlayers === game.maxPlayers ? `${game.minPlayers}` : `${game.minPlayers} à ${game.maxPlayers}`;
  const status = game.isAvailable
    ? el("span", { class: "badge ok" }, "Disponible")
    : el("span", { class: "badge busy" }, "Emprunté");

  const actions = el("div", { class: "actions" });
  if (game.isAvailable) {
    actions.append(button("Emprunter", () => openBorrowDialog(game), "primary"));
  } else {
    actions.append(button("Rendre", () => returnGame(game), "primary"));
  }

  actions.append(
    button("Modifier", () => openGameDialog(game)),
    button("Supprimer", () => confirmDeleteGame(game), "danger"),
  );

  return el(
    "li",
    { class: "card" },
    el("div", { class: "card-head" }, el("h3", {}, game.title), status),
    el("p", { class: "meta" }, `${players} joueur·ses · ${game.durationMinutes} min`),
    actions,
  );
}

const gameDialog = $("#game-dialog");
const gameForm = $("#game-form");

// `editedGame` vaut null pour une création, ou le jeu en cours de modification.
let editedGame = null;

function openGameDialog(game = null) {
  editedGame = game;
  gameForm.reset();
  $("#game-dialog-title").textContent = game ? `Modifier « ${game.title} »` : "Ajouter un jeu";
  if (game) {
    gameForm.elements.title.value = game.title;
    gameForm.elements.minPlayers.value = game.minPlayers;
    gameForm.elements.maxPlayers.value = game.maxPlayers;
    gameForm.elements.durationMinutes.value = game.durationMinutes;
  }
  showFormError(gameDialog, null);
  gameDialog.showModal();
}

$("#add-game").addEventListener("click", () => openGameDialog());

bindSubmit(gameDialog, gameForm, (data) => {
  const game = {
    title: data.get("title").trim(),
    minPlayers: Number(data.get("minPlayers")),
    maxPlayers: Number(data.get("maxPlayers")),
    durationMinutes: Number(data.get("durationMinutes")),
  };
  return editedGame ? api.updateGame(editedGame.id, game) : api.createGame(game);
});

function confirmDeleteGame(game) {
  askConfirmation(`Supprimer définitivement « ${game.title} » ?`, async () => {
    await api.deleteGame(game.id);
    toast(`« ${game.title} » a été supprimé.`);
  });
}

// --- Emprunts --------------------------------------------------------------

const borrowDialog = $("#borrow-dialog");
const borrowForm = $("#borrow-form");
let borrowedGame = null;

async function openBorrowDialog(game) {
  await run(async () => {
    const members = await api.listMembers();
    if (members.length === 0) {
      toast("Ajoutez d'abord un·e adhérent·e pour pouvoir emprunter.", true);
      return;
    }
    borrowedGame = game;
    $("#borrow-dialog-title").textContent = `Emprunter « ${game.title} »`;
    $("select", borrowForm).replaceChildren(
      ...members.map((member) => el("option", { value: member.id }, `${member.name} (${member.email})`)),
    );
    showFormError(borrowDialog, null);
    borrowDialog.showModal();
  });
}

bindSubmit(borrowDialog, borrowForm, async (data) => {
  const loan = await api.borrow(borrowedGame.id, data.get("memberID"));
  toast(`« ${borrowedGame.title} » emprunté, à rendre avant le ${formatDate(loan.dueAt)}.`);
});

async function findOpenLoan(gameID) {
  const members = await api.listMembers();
  for (const member of members) {
    const loans = await api.listMemberLoans(member.id);
    const openLoan = loans.find((loan) => loan.gameID === gameID && !loan.returnedAt);
    if (openLoan) {
      return openLoan;
    }
  }
  return null;
}

async function returnGame(game) {
  await run(async () => {
    const loan = await findOpenLoan(game.id);
    if (!loan) {
      toast(`Aucun emprunt en cours n'a été trouvé pour « ${game.title} ».`, true);
      await refresh();
      return;
    }
    await api.returnLoan(loan.id);
    toast(`« ${game.title} » a bien été rendu.`);
    await refresh();
  });
}

// --- Adhérent·es -----------------------------------------------------------

async function loadMembers() {
  const members = await api.listMembers();
  $("#members-empty").hidden = members.length > 0;
  $("#members-list").replaceChildren(...members.map(memberRow));
}

function memberRow(member) {
  const actions = el(
    "div",
    { class: "actions" },
    button("Emprunts", () => openMemberLoans(member)),
    button("Modifier", () => openMemberDialog(member)),
    button("Supprimer", () => confirmDeleteMember(member), "danger"),
  );

  return el(
    "li",
    { class: "row" },
    el("div", { class: "row-main" }, el("p", {}, el("strong", {}, member.name)), el("p", { class: "meta" }, member.email)),
    actions,
  );
}

const isLate = (loan) => !loan.returnedAt && new Date(loan.dueAt) < new Date();

function loanStatus(loan) {
  if (loan.returnedAt) {
    return el("span", { class: "badge ok" }, "Rendu");
  }
  if (isLate(loan)) {
    return el("span", { class: "badge late" }, "En retard");
  }
  return el("span", { class: "badge busy" }, "En cours");
}

function memberLoanRow(loan, titles) {
  const dates = [`Emprunté le ${formatDate(loan.borrowedAt)}`, `retour prévu le ${formatDate(loan.dueAt)}`];
  if (loan.returnedAt) {
    dates.push(`rendu le ${formatDate(loan.returnedAt)}`);
  }
  return el(
    "li",
    { class: isLate(loan) ? "row late" : "row" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, titles.get(loan.gameID) ?? "Jeu inconnu")),
      el("p", { class: "meta" }, dates.join(" · ")),
    ),
    loanStatus(loan),
  );
}

const loansDialog = $("#loans-dialog");

async function openMemberLoans(member) {
  await run(async () => {
    const [loans, games] = await Promise.all([api.listMemberLoans(member.id), api.listGames()]);
    const titles = new Map(games.map((game) => [game.id, game.title]));
    $("#loans-dialog-title").textContent = `Emprunts de ${member.name}`;
    $("#loans-empty").hidden = loans.length > 0;
    $("#loans-list").replaceChildren(...loans.map((loan) => memberLoanRow(loan, titles)));
    loansDialog.showModal();
  });
}

const memberDialog = $("#member-dialog");
const memberForm = $("#member-form");

let editedMember = null;

function openMemberDialog(member = null) {
  editedMember = member;
  memberForm.reset();
  $("#member-dialog-title").textContent = member ? `Modifier « ${member.name} »` : "Ajouter un·e adhérent·e";
  if (member) {
    memberForm.elements.name.value = member.name;
    memberForm.elements.email.value = member.email;
  }
  showFormError(memberDialog, null);
  memberDialog.showModal();
}

$("#add-member").addEventListener("click", () => openMemberDialog());

bindSubmit(memberDialog, memberForm, (data) => {
  const member = { name: data.get("name").trim(), email: data.get("email").trim() };
  return editedMember ? api.updateMember(editedMember.id, member) : api.createMember(member);
});

function confirmDeleteMember(member) {
  askConfirmation(`Supprimer définitivement « ${member.name} » ?`, async () => {
    await api.deleteMember(member.id);
    toast(`« ${member.name} » a été supprimé·e.`);
  });
}

// --- Retards ---------------------------------------------------------------

const dayInMs = 24 * 60 * 60 * 1000;

function daysLate(loan) {
  return Math.max(1, Math.floor((Date.now() - new Date(loan.dueAt)) / dayInMs));
}

function overdueRow(loan, titles, names) {
  const days = daysLate(loan);
  return el(
    "li",
    { class: "row late" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, titles.get(loan.gameID) ?? "Jeu inconnu"), ` · ${names.get(loan.memberID) ?? "Adhérent·e inconnu·e"}`),
      el("p", { class: "meta" }, `Retour prévu le ${formatDate(loan.dueAt)} · ${days} jour${days > 1 ? "s" : ""} de retard`),
    ),
    el("span", { class: "badge late" }, "En retard"),
  );
}

async function loadOverdue() {
  const [loans, games, members] = await Promise.all([api.listOverdueLoans(), api.listGames(), api.listMembers()]);
  const titles = new Map(games.map((game) => [game.id, game.title]));
  const names = new Map(members.map((member) => [member.id, member.name]));
  $("#overdue-empty").hidden = loans.length > 0;
  $("#overdue-list").replaceChildren(...loans.map((loan) => overdueRow(loan, titles, names)));
}

async function updateOverdueCount() {
  const counter = $("#overdue-count");
  try {
    const loans = await api.listOverdueLoans();
    counter.textContent = loans.length;
    counter.setAttribute("aria-label", `${loans.length} emprunt${loans.length > 1 ? "s" : ""} en retard`);
    counter.hidden = loans.length === 0;
  } catch {
    counter.hidden = true;
  }
}

refresh();
