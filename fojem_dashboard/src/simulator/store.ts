import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Actor, LatLng, LogEntry, LogKind } from "./types";

/** Le scénario en cours : ses acteurs (avec leurs jetons), son trajet et sa route. */
export interface Scenario {
  label: string;
  tripId: string;
  /** Null : le trajet est celui d'un vrai chauffeur (appli sur un téléphone). */
  driver: Actor | null;
  passengers: Actor[];
  /** Réservations faites par le simulateur : id de réservation → id du passager simulé. */
  bookings: Record<string, string>;
  geometry: LatLng[];
  routeSource: "osrm" | "straight";
  /** Arrêts par lesquels passe [geometry] : la route est recalculée s'ils changent. */
  routeKey: string;
  createdAt: string;
}

export interface EngineSettings {
  /** Distance parcourue sur la route, en mètres. */
  distance: number;
  playing: boolean;
  speedKmh: number;
  /** Avance rapide : le chauffeur roule N fois plus vite (l'horloge du serveur, elle, reste réelle). */
  multiplier: number;
  /** Coupé : plus aucune position n'est envoyée, comme un téléphone sans réseau. */
  gps: boolean;
  /** Pause à chaque point de rendez-vous, en secondes (0 : il ne s'arrête pas). */
  dwellSec: number;
}

const DEFAULT_ENGINE: EngineSettings = {
  distance: 0,
  playing: false,
  speedKmh: 60,
  multiplier: 1,
  gps: true,
  dwellSec: 30,
};

const MAX_LOG = 300;

interface SimState {
  scenario: Scenario | null;
  engine: EngineSettings;
  log: LogEntry[];
  /** Dernière position acceptée par le serveur. */
  lastFixAt: string | null;
  /** Fin de la pause en cours à un arrêt (horodatage ms), 0 sinon. */
  dwellUntil: number;
  /** Réservations dont le passager partage sa position. */
  sharing: Record<string, boolean>;
  setScenario: (scenario: Scenario | null) => void;
  updateScenario: (patch: Partial<Scenario>) => void;
  addPassenger: (actor: Actor, bookingId?: string) => void;
  linkBooking: (bookingId: string, passengerId: string) => void;
  setEngine: (patch: Partial<EngineSettings>) => void;
  setDwellUntil: (at: number) => void;
  setLastFix: (at: string | null) => void;
  setSharing: (bookingId: string, on: boolean) => void;
  addLog: (kind: LogKind, text: string) => void;
  clearLog: () => void;
  clear: () => void;
}

let nextLogId = Date.now();

export const useSimStore = create<SimState>()(
  persist(
    (set) => ({
      scenario: null,
      engine: DEFAULT_ENGINE,
      log: [],
      lastFixAt: null,
      dwellUntil: 0,
      sharing: {},

      setScenario: (scenario) =>
        set({ scenario, engine: { ...DEFAULT_ENGINE }, lastFixAt: null, dwellUntil: 0, sharing: {} }),

      updateScenario: (patch) => set((s) => (s.scenario ? { scenario: { ...s.scenario, ...patch } } : {})),

      addPassenger: (actor, bookingId) =>
        set((s) =>
          s.scenario
            ? {
                scenario: {
                  ...s.scenario,
                  passengers: [...s.scenario.passengers, actor],
                  bookings: bookingId ? { ...s.scenario.bookings, [bookingId]: actor.id } : s.scenario.bookings,
                },
              }
            : {},
        ),

      linkBooking: (bookingId, passengerId) =>
        set((s) =>
          s.scenario ? { scenario: { ...s.scenario, bookings: { ...s.scenario.bookings, [bookingId]: passengerId } } } : {},
        ),

      setEngine: (patch) => set((s) => ({ engine: { ...s.engine, ...patch } })),
      setDwellUntil: (dwellUntil) => set({ dwellUntil }),
      setLastFix: (lastFixAt) => set({ lastFixAt }),
      setSharing: (bookingId, on) => set((s) => ({ sharing: { ...s.sharing, [bookingId]: on } })),

      addLog: (kind, text) =>
        set((s) => ({
          log: [{ id: ++nextLogId, at: new Date().toISOString(), kind, text }, ...s.log].slice(0, MAX_LOG),
        })),
      clearLog: () => set({ log: [] }),

      clear: () => set({ scenario: null, engine: { ...DEFAULT_ENGINE }, log: [], lastFixAt: null, dwellUntil: 0, sharing: {} }),
    }),
    {
      name: "fojem-simulator",
      // Après un rechargement de la page, le chauffeur reste à l'arrêt.
      partialize: (s) => ({
        scenario: s.scenario,
        engine: { ...s.engine, playing: false },
        log: s.log.slice(0, 100),
        sharing: s.sharing,
      }),
    },
  ),
);

/** Clé des arrêts d'une route : leurs coordonnées, dans l'ordre. */
export function routeKeyOf(points: { lat: number; lng: number }[]): string {
  return points.map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join("|");
}
