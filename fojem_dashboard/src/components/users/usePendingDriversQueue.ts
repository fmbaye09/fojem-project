import { useCallback, useEffect, useRef, useState } from "react";
import { apiFetch, ApiError } from "../../lib/api";
import type { Driver, DriverDocumentsResponse, Paginated } from "../../types/api";
import { DOCUMENT_TYPES_ORDERED, latestDocumentByType } from "./statusLabels";

export interface PendingQueueEntry {
  driver: Driver;
  /** Nombre de types de pièces fournis (sur 9). */
  provided: number;
  /** Pièces au statut "pending", donc actionnables par l'admin. */
  toReview: number;
  approved: number;
  rejected: number;
  /** Date d'envoi de la plus ancienne pièce encore en attente (ou de la 1re pièce). */
  waitingSince: string;
}

const PAGE_SIZE = 100;
/** Garde-fou : au-delà, on signale que la file est tronquée plutôt que de boucler sans fin. */
const MAX_PAGES = 5;
const DOCS_CONCURRENCY = 4;

async function summarize(driver: Driver): Promise<PendingQueueEntry | null> {
  const res = await apiFetch<DriverDocumentsResponse>(`/admin/drivers/${driver.id}/documents`);
  const byType = latestDocumentByType(res.documents);
  const docs = DOCUMENT_TYPES_ORDERED.map((t) => byType[t]).filter((d) => d !== undefined);
  if (docs.length === 0) return null; // rien à examiner : pas dans la file

  const pendingDocs = docs.filter((d) => d.status === "pending");
  const reference = pendingDocs.length > 0 ? pendingDocs : docs;
  const waitingSince = reference.reduce(
    (min, d) => (new Date(d.created_at).getTime() < new Date(min).getTime() ? d.created_at : min),
    reference[0].created_at,
  );

  return {
    driver,
    provided: docs.length,
    toReview: pendingDocs.length,
    approved: docs.filter((d) => d.status === "approved").length,
    rejected: docs.filter((d) => d.status === "rejected").length,
    waitingSince,
  };
}

function byOldestFirst(a: PendingQueueEntry, b: PendingQueueEntry) {
  return new Date(a.waitingSince).getTime() - new Date(b.waitingSince).getTime();
}

async function fetchPendingQueue(): Promise<{ entries: PendingQueueEntry[]; truncated: boolean }> {
  const drivers: Driver[] = [];
  let page = 1;
  let lastPage = 1;
  do {
    const res = await apiFetch<Paginated<Driver>>("/admin/drivers", {
      query: { verification_status: "pending", per_page: PAGE_SIZE, page },
    });
    drivers.push(...res.data);
    lastPage = res.last_page;
    page++;
  } while (page <= lastPage && page <= MAX_PAGES);

  const entries: PendingQueueEntry[] = [];
  let cursor = 0;
  const worker = async () => {
    while (cursor < drivers.length) {
      const entry = await summarize(drivers[cursor++]);
      if (entry) entries.push(entry);
    }
  };
  await Promise.all(Array.from({ length: Math.min(DOCS_CONCURRENCY, drivers.length) }, worker));

  return { entries: entries.sort(byOldestFirst), truncated: lastPage > MAX_PAGES };
}

/**
 * File "À valider" : chauffeurs en verification_status=pending ayant envoyé
 * au moins une pièce, du plus ancien au plus récent.
 *
 * GET /admin/drivers ne sait ni filtrer "a au moins un document", ni trier
 * du plus ancien au plus récent : on charge donc tous les chauffeurs en
 * attente puis leurs documents (concurrence limitée) et on filtre/trie côté
 * client. Acceptable tant que la file reste de taille raisonnable ; un
 * filtre/tri serveur serait la suite logique si elle grossit.
 */
export function usePendingDriversQueue(enabled: boolean) {
  const [entries, setEntries] = useState<PendingQueueEntry[] | null>(null);
  const [loading, setLoading] = useState(enabled);
  const [error, setError] = useState<string | null>(null);
  const [truncated, setTruncated] = useState(false);
  const generation = useRef(0);

  // Aucun setState synchrone ici : tout passe par les callbacks de la promesse.
  const fetchQueue = useCallback(() => {
    const gen = ++generation.current;
    fetchPendingQueue().then(
      (res) => {
        if (gen !== generation.current) return;
        setEntries(res.entries);
        setTruncated(res.truncated);
        setError(null);
        setLoading(false);
      },
      (err: unknown) => {
        if (gen !== generation.current) return;
        setError(err instanceof ApiError ? err.message : "Impossible de charger la file de validation.");
        setLoading(false);
      },
    );
  }, []);

  useEffect(() => {
    if (!enabled) return;
    fetchQueue();

    const interval = setInterval(() => {
      if (document.visibilityState === "visible") {
        fetchQueue();
      }
    }, 20000);

    const onFocus = () => {
      if (document.visibilityState === "visible") {
        fetchQueue();
      }
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onFocus);

    return () => {
      clearInterval(interval);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onFocus);
    };
  }, [enabled, fetchQueue]);

  const reload = useCallback(() => {
    setLoading(true);
    setError(null);
    fetchQueue();
  }, [fetchQueue]);

  /**
   * Après une revue : on ne recharge que le chauffeur concerné. S'il n'est
   * plus "pending" (tout approuvé, ou rejeté), il sort de la file.
   */
  const refreshDriver = useCallback(async (updated: Driver) => {
    if (updated.verification_status !== "pending") {
      setEntries((prev) => prev?.filter((e) => e.driver.id !== updated.id) ?? prev);
      return;
    }
    try {
      const entry = await summarize(updated);
      setEntries((prev) => {
        if (!prev) return prev;
        const rest = prev.filter((e) => e.driver.id !== updated.id);
        return entry ? [...rest, entry].sort(byOldestFirst) : rest;
      });
    } catch {
      // l'échec de ce rafraîchissement ponctuel n'invalide pas le reste de la file
    }
  }, []);

  return { entries, loading, error, truncated, reload, refreshDriver };
}
