import { create } from "zustand";
import { apiFetch } from "../lib/api";
import type { Paginated, SosAlert } from "../types/api";

/** Fréquence de vérification des alertes SOS ouvertes. */
const POLL_MS = 10_000;

interface SosWatchState {
  openCount: number;
  /** Alertes ouvertes les plus récentes (pour la bannière). */
  latest: SosAlert[];
  /** Ids déjà vus : seule une nouvelle alerte déclenche le son. */
  seen: Set<string>;
  /** Premier chargement fait : les alertes déjà ouvertes ne sonnent pas. */
  loaded: boolean;
  started: boolean;
  start: () => () => void;
  refresh: () => Promise<void>;
}

/** Bip d'alerte généré (pas de fichier son à charger). */
function playAlarm() {
  try {
    const ctx = new AudioContext();
    [0, 0.35, 0.7].forEach((offset) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "square";
      osc.frequency.value = 880;
      gain.gain.setValueAtTime(0.15, ctx.currentTime + offset);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + offset + 0.3);
      osc.connect(gain).connect(ctx.destination);
      osc.start(ctx.currentTime + offset);
      osc.stop(ctx.currentTime + offset + 0.3);
    });
  } catch {
    // Navigateur sans Web Audio ou son bloqué : la bannière suffit.
  }
}

/**
 * Surveillance des alertes SOS ouvertes, partagée par la bannière, le menu
 * et la page Modération. Démarrée une seule fois dans la mise en page.
 */
export const useSosWatch = create<SosWatchState>((set, get) => ({
  openCount: 0,
  latest: [],
  seen: new Set(),
  loaded: false,
  started: false,

  refresh: async () => {
    try {
      const page = await apiFetch<Paginated<SosAlert>>("/admin/sos-alerts", {
        query: { status: "open", per_page: 5 },
      });
      if (!page) return;
      const { seen, loaded } = get();
      const hasNew = page.data.some((a) => !seen.has(a.id));
      if (loaded && hasNew) playAlarm();
      const nextSeen = new Set(seen);
      page.data.forEach((a) => nextSeen.add(a.id));
      set({ openCount: page.total, latest: page.data, seen: nextSeen, loaded: true });
    } catch {
      // Réessayé au prochain tour.
    }
  },

  start: () => {
    if (get().started) return () => {};
    set({ started: true });
    void get().refresh();
    const timer = window.setInterval(() => void get().refresh(), POLL_MS);
    return () => {
      window.clearInterval(timer);
      set({ started: false });
    };
  },
}));
