import { API_URL } from "./config.js";

// Client de l'API La Pioche : une fonction par route.
// Une route ajoutée côté Vapor s'ajoute dans l'objet `api`, en bas du fichier.

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const TOKEN_KEY = "lapioche.token";

export function saveToken(token) {
  sessionStorage.setItem(TOKEN_KEY, token);
}

export function clearToken() {
  sessionStorage.removeItem(TOKEN_KEY);
}

export function hasToken() {
  return sessionStorage.getItem(TOKEN_KEY) !== null;
}

let onUnauthorized = () => {};

export function setUnauthorizedHandler(handler) {
  onUnauthorized = handler;
}

// L'API répond avec des messages techniques en anglais : on les traduit ici
// pour que l'interface n'affiche que des phrases claires en français.
const fieldLabels = {
  title: "Le titre",
  minPlayers: "Le nombre minimum de joueur·ses",
  maxPlayers: "Le nombre maximum de joueur·ses",
  durationMinutes: "La durée",
  name: "Le nom",
  email: "L'adresse e-mail",
  players: "Le nombre de joueur·ses",
  maxDuration: "La durée maximale",
  available: "Le filtre de disponibilité",
  password: "Le mot de passe",
};

const knownMessages = {
  "minPlayers must not exceed maxPlayers": "Le nombre minimum de joueur·ses ne peut pas dépasser le maximum.",
  "Game not found": "Ce jeu n'existe pas ou a déjà été supprimé.",
  "Member not found": "Cet·te adhérent·e n'existe pas ou a déjà été supprimé·e.",
  "Loan not found": "Cet emprunt n'existe pas.",
  "Invalid game id": "L'identifiant du jeu n'est pas valide.",
  "Invalid member id": "L'identifiant de l'adhérent·e n'est pas valide.",
  "Invalid loan id": "L'identifiant de l'emprunt n'est pas valide.",
  "Game is already on loan": "Ce jeu est déjà emprunté : il faut d'abord le rendre.",
  "Loan is already returned": "Cet emprunt a déjà été rendu.",
  "A game with loans cannot be deleted":
    "Suppression impossible : ce jeu a un historique d'emprunts, conservé même quand le jeu est rendu.",
  "A member with loans cannot be deleted":
    "Suppression impossible : cet·te adhérent·e a un historique d'emprunts, conservé même quand tout est rendu.",
  "A member with this email already exists": "Un·e autre adhérent·e utilise déjà cette adresse e-mail.",
  "Invalid email or password": "Adresse e-mail ou mot de passe incorrect.",
  "An account with this email already exists": "Un compte existe déjà avec cette adresse e-mail.",
  "Authentication required": "Votre session a expiré ou n'est plus valide : reconnectez-vous.",
};

// Les erreurs de validation de Vapor arrivent regroupées :
// « title is empty, minPlayers is less than minimum of 1 ».
function translateValidation(part) {
  const label = (field) => fieldLabels[field] ?? `Le champ « ${field} »`;
  let match;
  if ((match = part.match(/^(\w+) is (?:empty|required)$/))) {
    return `${label(match[1])} est obligatoire.`;
  }
  if ((match = part.match(/^(\w+) is less than minimum of (\d+) character/))) {
    return `${label(match[1])} doit contenir au moins ${match[2]} caractères.`;
  }
  if ((match = part.match(/^(\w+) is less than minimum of (\d+)/))) {
    return `${label(match[1])} doit être d'au moins ${match[2]}.`;
  }
  if ((match = part.match(/^(\w+) is not a\(n\) Int$/))) {
    return `${label(match[1])} doit être un nombre entier.`;
  }
  if ((match = part.match(/^(\w+) is not a\(n\) Bool$/))) {
    return `${label(match[1])} doit valoir « oui » ou « non ».`;
  }
  if (/^email is not a valid email address$/.test(part)) {
    return "L'adresse e-mail n'est pas valide (exemple : nom@example.com).";
  }
  return null;
}

const statusMessages = {
  400: "Les informations envoyées ne sont pas valides.",
  404: "Cet élément n'existe pas.",
  409: "Cette action est impossible dans l'état actuel des données.",
};

export function translateError(status, reason) {
  if (reason in knownMessages) {
    return knownMessages[reason];
  }
  const parts = (reason ?? "").split(", ").map(translateValidation);
  if (parts.length > 0 && parts.every(Boolean)) {
    return parts.join(" ");
  }
  if (status >= 500) {
    return "Le serveur a rencontré une erreur. Réessayez dans un instant.";
  }
  return statusMessages[status] ?? "Une erreur est survenue. Réessayez.";
}

async function request(method, path, body) {
  const token = sessionStorage.getItem(TOKEN_KEY);
  const headers = {};
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  let response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "Impossible de joindre le serveur. Vérifiez qu'il est bien lancé.");
  }
  if (response.status === 204) {
    return null;
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 401 && token) {
      clearToken();
      onUnauthorized();
    }
    throw new ApiError(response.status, translateError(response.status, data?.reason));
  }
  return data;
}

function queryString(params) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) {
      search.set(key, value);
    }
  }
  const text = search.toString();
  return text ? `?${text}` : "";
}

export const api = {
  register: (credentials) => request("POST", "/auth/register", credentials),
  login: (credentials) => request("POST", "/auth/login", credentials),
  me: () => request("GET", "/auth/me"),
  listGames: (filters = {}) => request("GET", `/games${queryString(filters)}`),
  createGame: (game) => request("POST", "/games", game),
  updateGame: (id, game) => request("PUT", `/games/${encodeURIComponent(id)}`, game),
  deleteGame: (id) => request("DELETE", `/games/${encodeURIComponent(id)}`),

  listMembers: () => request("GET", "/members"),
  createMember: (member) => request("POST", "/members", member),
  updateMember: (id, member) => request("PUT", `/members/${encodeURIComponent(id)}`, member),
  deleteMember: (id) => request("DELETE", `/members/${encodeURIComponent(id)}`),
  listMemberLoans: (id) => request("GET", `/members/${encodeURIComponent(id)}/loans`),

  borrow: (gameID, memberID) => request("POST", "/loans", { gameID, memberID }),
  returnLoan: (id) => request("POST", `/loans/${encodeURIComponent(id)}/return`),
  listOverdueLoans: () => request("GET", "/loans/overdue"),
};
