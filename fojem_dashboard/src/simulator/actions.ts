import { apiFetch } from "../lib/api";
import type { AdminTripDetail } from "../types/api";
import { actorFetch, errorMessage } from "./api";
import { formatKm, nudge } from "./geo";
import { routeKeyOf, useSimStore, type Scenario } from "./store";
import type { Actor, LatLng, LogKind, PlannedPoint, SimBooking, SimProposedStop, SimRoute, SimTrip } from "./types";

// Tout ce que fait le simulateur passe par l'API publique avec le jeton de
// l'acteur concerné, comme les applis : seuls la création des comptes, la
// route et le « vieillissement » d'un scénario utilisent /admin/simulator.

const log = (kind: LogKind, text: string) => useSimStore.getState().addLog(kind, text);

export interface PassengerPlan {
  name: string;
  board: number;
  alight: number;
  accept: boolean;
}

export interface ScenarioInput {
  label: string;
  points: PlannedPoint[];
  departureInMin: number;
  seats: number;
  price: number;
  acceptsEnRoute: boolean;
  /** Daté d'il y a 1 h : les rappels « 30 min avant » partent comme pour un vrai trajet. */
  publishedEarlier: boolean;
  passengers: PassengerPlan[];
}

/** Arrondi des prix d'arrêt, comme l'appli chauffeur. */
const PRICE_ROUNDING = 50;
const AGE_MINUTES = 60;

export async function createActor(role: Actor["role"], name?: string, seats?: number): Promise<Actor> {
  const res = await apiFetch<{ actor: Actor }>("/admin/simulator/actors", {
    method: "POST",
    body: { role, name: name?.trim() || undefined, seats },
  });
  return res.actor;
}

export async function fetchRoute(points: { lat: number; lng: number }[]): Promise<SimRoute> {
  return apiFetch<SimRoute>("/admin/simulator/route", {
    query: { points: points.map((p) => `${p.lat.toFixed(6)},${p.lng.toFixed(6)}`).join(";") },
  });
}

function describeRoute(route: SimRoute) {
  const meters = route.legs.reduce((sum, l) => sum + l.distance, 0);
  const minutes = Math.round(route.legs.reduce((sum, l) => sum + l.duration, 0) / 60);
  if (route.source === "osrm") log("ok", `Route OSRM : ${formatKm(meters)}, environ ${minutes} min de conduite.`);
  else log("error", `OSRM indisponible : le chauffeur roulera en ligne droite (${formatKm(meters)}).`);
}

/** Publie un trajet avec un chauffeur simulé, puis réserve les places prévues. */
export async function createScenario(input: ScenarioInput): Promise<Scenario> {
  const { points, passengers } = input;
  log("action", `Nouveau scénario : ${input.label}.`);
  const route = await fetchRoute(points);
  describeRoute(route);

  const driver = await createActor("driver", undefined, Math.max(input.seats, passengers.length, 1) + 2);
  log("ok", `Chauffeur simulé : ${driver.full_name}.`);

  // Heures et prix de chaque arrêt d'après la route, comme l'appli chauffeur.
  const departure = new Date(Date.now() + input.departureInMin * 60_000);
  departure.setSeconds(0, 0);
  const totalKm = Math.max(route.legs.reduce((sum, l) => sum + l.distance, 0), 1);
  let seconds = 0;
  let meters = 0;
  const last = points.length - 1;
  const stops = points.map((p, i) => {
    if (i > 0) {
      seconds += route.legs[i - 1]?.duration ?? 0;
      meters += route.legs[i - 1]?.distance ?? 0;
    }
    return {
      name: p.name,
      address: p.address,
      lat: p.lat,
      lng: p.lng,
      scheduled_at: new Date(departure.getTime() + seconds * 1000).toISOString(),
      price_from_origin:
        i === 0 ? 0 : i === last ? input.price : Math.round((input.price * meters) / totalKm / PRICE_ROUNDING) * PRICE_ROUNDING,
    };
  });

  const published = await actorFetch<{ trip: { id: string } }>(driver.token, "/trips", {
    method: "POST",
    body: {
      vehicle_id: driver.vehicle_id,
      departure_type: "scheduled",
      scheduled_at: departure.toISOString(),
      price_per_seat: input.price,
      seats_available: input.seats,
      accepts_en_route: input.acceptsEnRoute,
      stops,
    },
  });
  const trip = (await actorFetch<{ trip: SimTrip }>(driver.token, `/trips/${published.trip.id}`)).trip;
  log("ok", `Trajet publié par l'API : départ à ${hhmm(departure)}, ${input.seats} places.`);

  const scenario: Scenario = {
    label: input.label,
    tripId: trip.id,
    driver,
    passengers: [],
    bookings: {},
    geometry: route.geometry,
    routeSource: route.source,
    routeKey: routeKeyOf(trip.stops),
    createdAt: new Date().toISOString(),
  };

  for (const plan of passengers) {
    const actor = await createActor("passenger", plan.name);
    scenario.passengers.push(actor);
    const booking = await book(actor, trip, plan.board, plan.alight);
    scenario.bookings[booking.id] = actor.id;
    if (plan.accept) {
      await actorFetch(driver.token, `/bookings/${booking.id}/accept`, { method: "POST" });
      log("ok", `Le chauffeur accepte ${actor.full_name}.`);
    }
  }

  if (input.publishedEarlier) {
    await apiFetch("/admin/simulator/backdate", { method: "POST", body: { trip_id: trip.id, minutes: AGE_MINUTES } });
    log("ok", "Trajet et réservations datés d'il y a 1 h : les rappels « 30 min avant » partiront comme pour un vrai trajet.");
  }

  return scenario;
}

/** Des passagers simulés réservent le trajet d'un vrai chauffeur (appli sur un téléphone). */
export async function createScenarioOnTrip(tripId: string, passengers: PassengerPlan[]): Promise<Scenario> {
  const detail = (await apiFetch<{ trip: AdminTripDetail }>(`/admin/trips/${tripId}`)).trip;
  const label = `${detail.origin_name ?? "Départ"} → ${detail.destination_name ?? "Arrivée"} (${detail.driver?.full_name ?? "chauffeur"})`;
  log("action", `Nouveau scénario sur un vrai trajet : ${label}.`);

  const actors: Actor[] = [];
  for (const plan of passengers.length > 0 ? passengers : [{ name: "", board: 0, alight: -1, accept: false }]) {
    actors.push(await createActor("passenger", plan.name));
  }
  // Les coordonnées des arrêts viennent de l'API publique, vue par un passager.
  const trip = (await actorFetch<{ trip: SimTrip }>(actors[0].token, `/trips/${tripId}`)).trip;
  const route = await fetchRoute(trip.stops);
  describeRoute(route);

  const scenario: Scenario = {
    label,
    tripId,
    driver: null,
    passengers: actors,
    bookings: {},
    geometry: route.geometry,
    routeSource: route.source,
    routeKey: routeKeyOf(trip.stops),
    createdAt: new Date().toISOString(),
  };
  for (let i = 0; i < passengers.length; i++) {
    const booking = await book(actors[i], trip, passengers[i].board, passengers[i].alight);
    scenario.bookings[booking.id] = actors[i].id;
  }
  return scenario;
}

/** Réservation d'une place par un passager, entre deux arrêts (indices ; -1 = dernier). */
async function book(actor: Actor, trip: SimTrip, board: number, alight: number): Promise<SimBooking> {
  const stops = [...trip.stops].sort((a, b) => a.position - b.position);
  const from = stops[board] ?? stops[0];
  const to = stops[alight < 0 ? stops.length - 1 : alight] ?? stops[stops.length - 1];
  const res = await actorFetch<{ booking: SimBooking }>(actor.token, "/bookings", {
    method: "POST",
    body: { trip_id: trip.id, seat_count: 1, boarding_stop_id: from.id, alighting_stop_id: to.id },
  });
  log(
    "ok",
    `${actor.full_name} réserve ${from.name} → ${to.name} : ${res.booking.status === "confirmed" ? "confirmée d'office (en route)" : "demande envoyée au chauffeur"}.`,
  );
  return res.booking;
}

/** Un passager de plus, à tout moment du scénario (en route si le trajet est parti). */
export async function addPassenger(
  scenario: Scenario,
  trip: SimTrip,
  plan: PassengerPlan,
): Promise<void> {
  const actor = await createActor("passenger", plan.name);
  const store = useSimStore.getState();
  try {
    const booking = await book(actor, trip, plan.board, plan.alight);
    store.addPassenger(actor, booking.id);
    if (plan.accept && scenario.driver && booking.status === "pending_driver") {
      await actorFetch(scenario.driver.token, `/bookings/${booking.id}/accept`, { method: "POST" });
      log("ok", `Le chauffeur accepte ${actor.full_name}.`);
    }
  } catch (err) {
    // Le compte reste dans le scénario : on voit la réservation refusée.
    store.addPassenger(actor);
    throw err;
  }
}

/** Ce que coûterait au chauffeur le point qu'un passager propose. */
export async function previewProposal(
  actor: Actor,
  tripId: string,
  role: SimProposedStop["role"],
  point: LatLng,
  name: string,
): Promise<SimProposedStop> {
  const res = await actorFetch<{ proposal: SimProposedStop }>(actor.token, `/trips/${tripId}/stop-proposal`, {
    query: { role, lat: point[0], lng: point[1], name, address: name },
  });
  return res.proposal;
}

export async function bookWithProposal(
  actor: Actor,
  tripId: string,
  proposal: SimProposedStop,
  otherStopId: string,
): Promise<SimBooking> {
  const res = await actorFetch<{ booking: SimBooking }>(actor.token, "/bookings", {
    method: "POST",
    body: {
      trip_id: tripId,
      seat_count: 1,
      ...(proposal.role === "boarding" ? { alighting_stop_id: otherStopId } : { boarding_stop_id: otherStopId }),
      proposed_stop: { role: proposal.role, name: proposal.name, address: proposal.address, lat: proposal.lat, lng: proposal.lng },
    },
  });
  useSimStore.getState().linkBooking(res.booking.id, actor.id);
  return res.booking;
}

/**
 * Lance une action et note son résultat dans le journal : c'est là qu'on lit
 * les refus du backend (« Attendez encore 3 min… »).
 */
export async function run(label: string, fn: () => Promise<unknown>, success?: string): Promise<boolean> {
  log("action", label);
  try {
    await fn();
    if (success) log("ok", success);
    return true;
  } catch (err) {
    log("error", `${label} — refusé : ${errorMessage(err)}`);
    return false;
  }
}

/** Le passager partage une position à deux pas de son point de montée. */
export function passengerSpot(booking: SimBooking): LatLng | null {
  const stop = booking.boarding_stop;
  if (stop) return nudge([stop.lat, stop.lng], 120);
  return booking.proposed_stop?.role === "boarding" ? nudge([booking.proposed_stop.lat, booking.proposed_stop.lng], 120) : null;
}

export function hhmm(date: Date | string): string {
  return new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit" }).format(new Date(date));
}
