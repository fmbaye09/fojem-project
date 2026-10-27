import { useEffect, useRef, useState, useCallback } from "react";
import { apiFetch, ApiError } from "./api";

interface UseApiOptions {
  query?: Record<string, string | number | boolean | undefined>;
  /**
   * Intervalle d'actualisation automatique en millisecondes (défaut : 15 000 ms = 15s).
   * Passer 0 ou false pour désactiver le polling.
   */
  pollInterval?: number | false;
}

interface UseApiResult<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
}

/**
 * Hook de fetch avec état chargement/erreur et actualisation automatique continue (polling silencieux).
 * Ne réinitialise pas `loading: true` lors des rafraîchissements d'arrière-plan pour éviter les clignotements.
 */
export function useApi<T>(
  path: string | null,
  options: UseApiOptions = {},
  deps: unknown[] = [],
): UseApiResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  const queryRef = useRef(options.query);
  queryRef.current = options.query;

  const pollInterval = options.pollInterval ?? 15000;

  const fetchData = useCallback(
    async (isBackground = false) => {
      if (!path) return;
      if (!isBackground) {
        setLoading(true);
        setError(null);
      }
      try {
        const res = await apiFetch<T>(path, { query: queryRef.current });
        setData(res);
        setError(null);
      } catch (err) {
        // En arrière-plan, ne pas écraser les données existantes en cas de glitch réseau passager
        if (!isBackground || !data) {
          setError(err instanceof ApiError ? err.message : "Une erreur est survenue.");
        }
      } finally {
        if (!isBackground) {
          setLoading(false);
        }
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [path, data],
  );

  useEffect(() => {
    let cancelled = false;
    if (!path) return;

    fetchData(false);

    // Polling silencieux périodique
    let intervalId: ReturnType<typeof setInterval> | null = null;
    if (pollInterval && pollInterval > 0) {
      intervalId = setInterval(() => {
        if (!cancelled && document.visibilityState === "visible") {
          fetchData(true);
        }
      }, pollInterval);
    }

    // Actualisation immédiate au retour sur l'onglet
    const onVisibilityChange = () => {
      if (!cancelled && document.visibilityState === "visible") {
        fetchData(true);
      }
    };
    document.addEventListener("visibilitychange", onVisibilityChange);
    window.addEventListener("focus", onVisibilityChange);

    return () => {
      cancelled = true;
      if (intervalId) clearInterval(intervalId);
      document.removeEventListener("visibilitychange", onVisibilityChange);
      window.removeEventListener("focus", onVisibilityChange);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, reloadKey, pollInterval, ...deps]);

  return { data, loading, error, reload: () => setReloadKey((k) => k + 1) };
}
