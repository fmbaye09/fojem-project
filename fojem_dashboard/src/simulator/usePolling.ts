import { useEffect, useRef, useState, type MutableRefObject } from "react";
import { apiFetch } from "../lib/api";
import type { AdminTripBooking, AdminTripDetail, Paginated } from "../types/api";
import { BOOKING_STATUS_LABEL, TRIP_STATUS_LABEL } from "../components/trips/tripLabels";
import { actorFetch, errorMessage } from "./api";
import { useSimStore, type Scenario } from "./store";
import type { SimBooking, SimNotification, SimTrip } from "./types";

const POLL_MS = 3000;

export interface ScenarioData {
  trip: SimTrip | null;
  /** Réservations vues par le chauffeur simulé, ou celles des passagers simulés. */
  bookings: SimBooking[];
  /** Avec un vrai chauffeur : les autres réservations du trajet (vue admin). */
  otherBookings: AdminTripBooking[];
  notifications: SimNotification[];
  error: string | null;
  refresh: () => void;
}

const time = (iso: string) =>
  new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date(iso));

/**
 * Relit l'état du scénario toutes les 3 s, par les mêmes routes que les
 * applis, et note dans le journal ce qui a changé : arrêts atteints,
 * statuts, notifications envoyées…
 */
export function useScenarioPolling(scenario: Scenario | null): ScenarioData {
  const [trip, setTrip] = useState<SimTrip | null>(null);
  const [bookings, setBookings] = useState<SimBooking[]>([]);
  const [otherBookings, setOtherBookings] = useState<AdminTripBooking[]>([]);
  const [notifications, setNotifications] = useState<SimNotification[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  // Un nouveau scénario remonte le composant (clé = trajet) : ces
  // références repartent de zéro avec lui.
  const prevTrip = useRef<SimTrip | null>(null);
  const prevBookings = useRef<Map<string, SimBooking> | null>(null);
  const seenNotifications = useRef<Set<string> | null>(null);

  useEffect(() => {
    if (!scenario) return;
    let cancelled = false;
    const observer = scenario.driver ?? scenario.passengers[0];
    if (!observer) return;

    const load = async () => {
      try {
        const [tripRes, bookingList, others, notifRes] = await Promise.all([
          actorFetch<{ trip: SimTrip }>(observer.token, `/trips/${scenario.tripId}`),
          loadBookings(scenario),
          scenario.driver
            ? Promise.resolve<AdminTripBooking[]>([])
            : apiFetch<{ trip: AdminTripDetail }>(`/admin/trips/${scenario.tripId}`).then((r) => r.trip.bookings),
          apiFetch<{ notifications: SimNotification[] }>(
            `/admin/simulator/notifications?trip_ids[]=${encodeURIComponent(scenario.tripId)}`,
          ),
        ]);
        if (cancelled) return;
        const ownIds = new Set(bookingList.map((b) => b.id));
        logTripChanges(prevTrip.current, tripRes.trip);
        logBookingChanges(prevBookings.current, bookingList, scenario);
        logNotifications(seenNotifications, notifRes.notifications);
        prevTrip.current = tripRes.trip;
        prevBookings.current = new Map(bookingList.map((b) => [b.id, b]));
        setTrip(tripRes.trip);
        setBookings(bookingList);
        setOtherBookings(others.filter((b) => !ownIds.has(b.id)));
        setNotifications(notifRes.notifications);
        setError(null);
      } catch (err) {
        if (!cancelled) setError(errorMessage(err));
      }
    };

    void load();
    const id = window.setInterval(() => void load(), POLL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
    // Le scénario change d'identité à chaque passager ajouté : on relance alors.
  }, [scenario, tick]);

  return { trip, bookings, otherBookings, notifications, error, refresh: () => setTick((t) => t + 1) };
}

async function loadBookings(scenario: Scenario): Promise<SimBooking[]> {
  if (scenario.driver) {
    const page = await actorFetch<Paginated<SimBooking>>(scenario.driver.token, `/trips/${scenario.tripId}/bookings`, {
      query: { per_page: 100 },
    });
    return page.data;
  }
  // Vrai chauffeur : chaque passager simulé relit sa propre réservation.
  const tokens = new Map(scenario.passengers.map((p) => [p.id, p.token]));
  const results = await Promise.all(
    Object.entries(scenario.bookings).map(async ([bookingId, passengerId]) => {
      const token = tokens.get(passengerId);
      if (!token) return null;
      try {
        return (await actorFetch<{ booking: SimBooking }>(token, `/bookings/${bookingId}`)).booking;
      } catch {
        return null;
      }
    }),
  );
  return results.filter((b): b is SimBooking => b !== null);
}

function logTripChanges(prev: SimTrip | null, next: SimTrip) {
  if (!prev) return;
  const log = useSimStore.getState().addLog;
  if (prev.status !== next.status) {
    log("event", `Trajet : ${TRIP_STATUS_LABEL[prev.status]} → ${TRIP_STATUS_LABEL[next.status]}.`);
  }
  const before = new Map(prev.stops.map((s) => [s.id, s]));
  for (const stop of next.stops) {
    const old = before.get(stop.id);
    if (!old) {
      log("event", `Arrêt ajouté au trajet : ${stop.name}${stop.scheduled_at ? ` (passage prévu à ${time(stop.scheduled_at).slice(0, 5)})` : ""}.`);
      continue;
    }
    if (!old.reached_at && stop.reached_at) {
      log("event", `Le serveur a détecté l'arrivée à ${stop.name} (${time(stop.reached_at)}).`);
    }
    if (old.scheduled_at && stop.scheduled_at && old.scheduled_at !== stop.scheduled_at) {
      log("event", `Horaire de ${stop.name} décalé à ${time(stop.scheduled_at).slice(0, 5)}.`);
    }
  }
  for (const old of prev.stops) {
    if (!next.stops.some((s) => s.id === old.id)) log("event", `Arrêt retiré du trajet : ${old.name}.`);
  }
  const passed = next.last_passed_stop_position ?? 0;
  if (next.status === "in_progress" && passed > (prev.last_passed_stop_position ?? 0)) {
    const stop = next.stops.find((s) => s.position === passed);
    if (stop) log("event", `Arrêt passé pour le serveur : ${stop.name}.`);
  }
  const prevSource = prev.live?.eta_source ?? null;
  const nextSource = next.live?.eta_source ?? null;
  if (next.status === "in_progress" && prevSource !== nextSource && nextSource) {
    log(
      "event",
      nextSource === "live"
        ? "Heures de passage estimées d'après la position du chauffeur."
        : "Position trop ancienne : les heures de passage reviennent à l'horaire publié.",
    );
  }
  if (prev.accepts_en_route !== next.accepts_en_route) {
    log("event", next.accepts_en_route ? "Le trajet accepte les passagers en route." : "Le trajet n'accepte plus de passagers en route.");
  }
}

function logBookingChanges(prev: Map<string, SimBooking> | null, next: SimBooking[], scenario: Scenario) {
  if (!prev) return;
  const log = useSimStore.getState().addLog;
  const simulated = new Set(scenario.passengers.map((p) => p.id));
  for (const b of next) {
    const name = b.passenger?.full_name ?? scenario.passengers.find((p) => p.id === b.passenger_id)?.full_name ?? "Passager";
    const old = prev.get(b.id);
    if (!old) {
      const from = b.boarding_stop?.name ?? b.proposed_stop?.name ?? "?";
      const to = b.alighting_stop?.name ?? b.proposed_stop?.name ?? "?";
      log("event", `${simulated.has(b.passenger_id) ? "Nouvelle réservation" : "Réservation d'un vrai compte"} : ${name} (${from} → ${to}), ${BOOKING_STATUS_LABEL[b.status].toLowerCase()}.`);
      continue;
    }
    if (old.status !== b.status) {
      log("event", `${name} : ${BOOKING_STATUS_LABEL[old.status]} → ${BOOKING_STATUS_LABEL[b.status]}.`);
    }
    if (!old.started_at && b.started_at) log("event", `${name} est à bord.`);
  }
}

function logNotifications(seen: MutableRefObject<Set<string> | null>, list: SimNotification[]) {
  const log = useSimStore.getState().addLog;
  if (seen.current === null) {
    seen.current = new Set(list.map((n) => n.id));
    return;
  }
  // Du plus ancien au plus récent, pour un journal dans l'ordre.
  for (const n of [...list].reverse()) {
    if (seen.current.has(n.id)) continue;
    seen.current.add(n.id);
    log("notification", `${n.user_name ?? "?"} reçoit « ${n.title} »${n.body ? ` : ${n.body}` : ""}`);
  }
}
