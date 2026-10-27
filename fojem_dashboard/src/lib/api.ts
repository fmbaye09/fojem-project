import { useAuthStore } from "../store/useAuthStore";

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? "http://127.0.0.1:8000";

export class ApiError extends Error {
  status: number;
  fields?: Record<string, string[]>;

  constructor(message: string, status: number, fields?: Record<string, string[]>) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.fields = fields;
  }
}

/**
 * Client HTTP minimal pour l'API FOJEM.
 * - Le backend ne renvoie PAS d'enveloppe {success,data} : les endpoints
 *   admin répondent directement le JSON de la ressource (vérifié contre le
 *   backend réel en local). On reflète donc ça ici plutôt que de deviner un
 *   format générique.
 * - Auth par Bearer token (pas de cookie SPA Sanctum) : le token vient du
 *   store zustand persisté, jamais géré ici directement.
 * - Sur 401, on déconnecte proprement (le caller reste responsable de la
 *   navigation vers /login via l'état "unauthenticated").
 */
export async function apiFetch<T>(
  path: string,
  options: { method?: string; body?: unknown; query?: Record<string, string | number | boolean | undefined> } = {},
): Promise<T> {
  const token = useAuthStore.getState().token;

  let url = `${API_BASE_URL}/api${path}`;
  if (options.query) {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(options.query)) {
      if (v !== undefined && v !== "") params.set(k, String(v));
    }
    const qs = params.toString();
    if (qs) url += `?${qs}`;
  }

  const headers: Record<string, string> = { Accept: "application/json" };
  if (options.body !== undefined) headers["Content-Type"] = "application/json";
  if (token) headers.Authorization = `Bearer ${token}`;

  let response: Response;
  try {
    response = await fetch(url, {
      method: options.method ?? "GET",
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    });
  } catch {
    throw new ApiError("Impossible de joindre le serveur FOJEM. Vérifiez votre connexion.", 0);
  }

  if (response.status === 401) {
    useAuthStore.getState().handleUnauthorized();
    throw new ApiError("Session expirée, veuillez vous reconnecter.", 401);
  }

  let payload: unknown = undefined;
  try {
    payload = await response.json();
  } catch {
    // pas de corps (ex. 204)
  }

  if (!response.ok) {
    const p = payload as { message?: string; errors?: Record<string, string[]> } | undefined;
    throw new ApiError(p?.message ?? "Une erreur est survenue.", response.status, p?.errors);
  }

  return payload as T;
}

/**
 * Variante binaire d'apiFetch pour les fichiers protégés (ex. documents
 * chauffeur servis par GET /admin/drivers/:id/documents/:docId/file).
 * Ces endpoints exigent le Bearer token : on ne peut donc PAS les mettre
 * directement dans un <img src>. On les récupère en Blob, et c'est à
 * l'appelant de créer puis de révoquer l'object URL (URL.createObjectURL /
 * URL.revokeObjectURL).
 *
 * `url` peut être absolue (le backend renvoie `file_endpoint` en URL
 * complète) ou un chemin relatif à /api, comme pour apiFetch.
 */
export async function apiFetchBlob(url: string, options: { signal?: AbortSignal } = {}): Promise<Blob> {
  const token = useAuthStore.getState().token;
  const fullUrl = /^https?:\/\//i.test(url) ? url : `${API_BASE_URL}/api${url}`;

  const headers: Record<string, string> = { Accept: "*/*" };
  if (token) headers.Authorization = `Bearer ${token}`;

  let response: Response;
  try {
    response = await fetch(fullUrl, { headers, signal: options.signal });
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") throw err;
    throw new ApiError("Impossible de joindre le serveur FOJEM. Vérifiez votre connexion.", 0);
  }

  if (response.status === 401) {
    useAuthStore.getState().handleUnauthorized();
    throw new ApiError("Session expirée, veuillez vous reconnecter.", 401);
  }

  if (!response.ok) {
    let message = response.status === 404 ? "Fichier introuvable." : "Impossible de charger le fichier.";
    try {
      const p = (await response.json()) as { message?: string };
      if (p?.message && response.status !== 404) message = p.message;
    } catch {
      // corps non JSON
    }
    throw new ApiError(message, response.status);
  }

  return response.blob();
}
