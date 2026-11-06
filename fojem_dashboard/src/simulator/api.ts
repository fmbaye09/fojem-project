import { ApiError } from "../lib/api";

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? "http://127.0.0.1:8000";

type Query = Record<string, string | number | boolean | undefined>;

/**
 * Appel de l'API publique (celle des applis) avec le jeton d'un acteur
 * simulé. Contrairement à apiFetch, un 401 ici ne déconnecte pas l'admin :
 * c'est le compte simulé qui n'existe plus (base réinitialisée).
 */
export async function actorFetch<T>(
  token: string,
  path: string,
  options: { method?: string; body?: unknown; query?: Query } = {},
): Promise<T> {
  let url = `${API_BASE_URL}/api${path}`;
  if (options.query) {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(options.query)) {
      if (v !== undefined && v !== "") params.set(k, String(v));
    }
    const qs = params.toString();
    if (qs) url += `${url.includes("?") ? "&" : "?"}${qs}`;
  }

  const headers: Record<string, string> = { Accept: "application/json", Authorization: `Bearer ${token}` };
  if (options.body !== undefined) headers["Content-Type"] = "application/json";

  let response: Response;
  try {
    response = await fetch(url, {
      method: options.method ?? "GET",
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    });
  } catch {
    throw new ApiError("Backend injoignable. Vérifiez que Docker tourne.", 0);
  }

  let payload: unknown = undefined;
  try {
    payload = await response.json();
  } catch {
    // pas de corps
  }

  if (!response.ok) {
    const p = payload as { message?: string; errors?: Record<string, string[]> } | undefined;
    const message =
      response.status === 401
        ? "Compte simulé inconnu du backend (base réinitialisée ?). Réinitialisez le simulateur."
        : (p?.message ?? `Erreur ${response.status}.`);
    throw new ApiError(message, response.status, p?.errors);
  }

  return payload as T;
}

/** Message lisible d'une erreur d'API, avec le premier détail de validation. */
export function errorMessage(err: unknown): string {
  if (err instanceof ApiError) {
    const first = err.fields ? Object.values(err.fields)[0]?.[0] : undefined;
    return first && first !== err.message ? `${err.message} (${first})` : err.message;
  }
  return err instanceof Error ? err.message : "Erreur inconnue.";
}
