import type { BookingStatus, TripStatus } from "../types/api";

// Réponses de l'API publique (celle des applis) telles que les voient les
// acteurs simulés, et de l'API /admin/simulator. Seuls les champs utilisés
// par le simulateur sont décrits.

export type LatLng = [number, number];

export type ActorRole = "driver" | "passenger";

/** Compte simulé créé par le backend, avec son jeton d'API. */
export interface Actor {
  id: string;
  role: ActorRole;
  full_name: string;
  phone_number: string;
  vehicle_id: string | null;
  token: string;
}

export interface SimStop {
  id: string;
  position: number;
  name: string;
  address: string | null;
  lat: number;
  lng: number;
  scheduled_at: string | null;
  reached_at: string | null;
  wait_until: string | null;
  price_from_origin: string;
}

export interface SimLive {
  state: string;
  location_fresh: boolean;
  location_updated_at: string | null;
  last_passed_stop_position: number | null;
  next_stop_id: string | null;
  eta_source: "live" | "schedule" | null;
  delay_minutes: number | null;
  etas: { stop_id: string; eta: string }[];
}

export interface SimTrip {
  id: string;
  status: TripStatus;
  scheduled_at: string | null;
  seats_available: number;
  accepts_en_route: boolean;
  current_lat: number | null;
  current_lng: number | null;
  current_heading: number | null;
  location_updated_at: string | null;
  last_passed_stop_position: number | null;
  origin_name: string;
  destination_name: string;
  stops: SimStop[];
  live: SimLive | null;
  driver_profile?: { user?: { id: string; full_name: string } | null } | null;
}

export interface SimProposedStop {
  role: "boarding" | "alighting";
  name: string;
  address: string | null;
  lat: number;
  lng: number;
  after_stop_id?: string;
  detour_minutes: number;
  scheduled_at: string | null;
  price_from_origin: string;
  inserted_stop_id?: string | null;
}

export interface SimBooking {
  id: string;
  trip_id: string;
  passenger_id: string;
  status: BookingStatus;
  seat_count: number;
  departure_code: string;
  price_charged: string;
  started_at: string | null;
  confirmed_at: string | null;
  boarding_stop_id: string | null;
  alighting_stop_id: string | null;
  boarding_stop: SimStop | null;
  alighting_stop: SimStop | null;
  proposed_stop: SimProposedStop | null;
  passenger_location: { lat: number; lng: number; updated_at: string } | null;
  passenger?: { id: string; full_name: string } | null;
  passenger_reliability?: { honored_pct: number; no_show_count: number } | null;
}

export interface SimNotification {
  id: string;
  user_id: string;
  user_name: string | null;
  simulated: boolean;
  type: string;
  title: string;
  body: string | null;
  trip_id: string | null;
  booking_id: string | null;
  created_at: string;
}

export interface SimRoute {
  source: "osrm" | "straight";
  geometry: LatLng[];
  legs: { duration: number; distance: number }[];
}

export interface SimulatorStatus {
  enabled: boolean;
  osrm: boolean;
  simulated_users: number;
}

/** Point de rendez-vous du scénario avant publication. */
export interface PlannedPoint {
  name: string;
  address: string;
  lat: number;
  lng: number;
}

export type LogKind = "action" | "ok" | "error" | "event" | "notification";

export interface LogEntry {
  id: number;
  at: string;
  kind: LogKind;
  text: string;
}
