// Types calqués sur les réponses réelles de l'API /api/admin/* (backend
// Laravel FOJEM), vérifiées en local — pas de champ inventé.

export interface AdminPermission {
  id: string;
  role_id: string;
  resource: string;
  action: "view" | "edit" | "delete";
}

export interface AdminRole {
  id: string;
  name: string;
  permissions: AdminPermission[];
}

export interface AdminUser {
  id: string;
  full_name: string;
  email: string;
  role_id: string;
  is_active: boolean;
  created_at: string;
  role?: AdminRole;
}

export interface AdminMeResponse {
  admin: AdminUser;
  /** Nom du rôle (chaîne simple) — le détail complet est dans admin.role. */
  role: string;
  permissions: AdminPermission[];
}

export interface LoginResponse {
  admin: AdminUser;
  token: string;
}

export interface Paginated<T> {
  current_page: number;
  data: T[];
  last_page: number;
  per_page: number;
  total: number;
  from: number | null;
  to: number | null;
}

export type VerificationStatus = "pending" | "approved" | "rejected";
export type AccountStatus = "active" | "disabled" | "deleted";

export interface Driver {
  id: string;
  user_id: string;
  verification_status: VerificationStatus;
  verified_at: string | null;
  average_rating: string | null;
  total_trips_completed: number;
  created_at: string;
  updated_at: string;
  user?: PlatformUser;
}

export type IdentityStatus = "none" | "pending" | "approved" | "rejected";
export type IdentityDocumentType = "id_card" | "driver_license";

export interface PlatformUser {
  id: string;
  full_name: string;
  email: string;
  phone_number: string;
  profile_photo_url: string | null;
  gender: string;
  account_status: AccountStatus;
  is_driver: boolean;
  language: string;
  created_at: string;
  driver?: Driver | null;
  identity_status?: IdentityStatus;
  identity_document_type?: IdentityDocumentType | null;
  identity_document_number?: string | null;
  identity_front_url?: string | null;
  identity_back_url?: string | null;
  identity_rejection_reason?: string | null;
  identity_submitted_at?: string | null;
  identity_reviewed_at?: string | null;
  identity_verified?: boolean;
}

/**
 * Les 9 pièces exigées (DriverDocument::REQUIRED_TYPES côté backend) — il
 * n'existe aucune autre valeur. Le chauffeur passe "approved" seulement
 * quand les 9 sont approuvées.
 */
export type DriverDocumentType =
  | "cni_recto"
  | "cni_verso"
  | "permis_recto"
  | "permis_verso"
  | "carte_grise"
  | "vehicule_avant"
  | "vehicule_arriere"
  | "vehicule_gauche"
  | "vehicule_droite"
  | "selfie_carte_grise"
  | "selfie_permis";

/** Élément de GET /admin/drivers/:id/documents. */
export interface DriverDocument {
  id: string;
  document_type: DriverDocumentType;
  status: VerificationStatus;
  /**
   * URL absolue de GET /admin/drivers/:id/documents/:docId/file — protégée
   * par le Bearer token admin : à charger via apiFetchBlob(), jamais en
   * <img src> direct.
   */
  file_endpoint: string;
  rejection_reason: string | null;
  reviewed_by_admin_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface DriverDocumentsResponse {
  driver_id: string;
  documents: DriverDocument[];
  /** Contact d'urgence donné par le chauffeur à l'inscription. */
  emergency_contact: EmergencyContact | null;
}

export interface EmergencyContact {
  name: string;
  phone: string;
}

/** Réponse de PATCH /admin/drivers/:id/documents/:docId/review. */
export interface ReviewDriverDocumentResponse {
  document: Omit<DriverDocument, "file_endpoint">;
  driver: Driver;
}

export interface OverviewResponse {
  users_active: number;
  drivers: { total: number; pending_verification: number; approved: number };
  trips_by_status: Record<string, number>;
  /** `{ statut: nombre }`, ou `[]` quand il n'y a aucune réservation (pluck Laravel). */
  bookings_today_by_status: Record<string, number> | [];
  bookings_this_week_by_status: Record<string, number> | [];
  completed_transactions_last_30_days: { date: string; total: string }[];
  sos_alerts_open: number;
  disputes_open: number;
}

export interface TimeseriesResponse {
  from: string;
  to: string;
  trips_per_day: Record<string, number> | { date: string; count: number }[];
  bookings_per_day: Record<string, number> | { date: string; count: number }[];
  revenue_per_day: Record<string, string | number> | { date: string; total: string }[];
}

export interface AcceptanceRateResponse {
  from: string;
  to: string;
  decided_bookings: number;
  accepted_bookings: number;
  acceptance_rate: number | null;
}

export interface AverageRatingResponse {
  platform_average_rating: number | null;
  rated_drivers_count: number;
}

export interface TransactionsBreakdownResponse {
  from: string;
  to: string;
  by_payment_method: Record<string, { payment_method: string; count: number; total_amount: string }>;
  by_type: Record<string, { type: string; count: number; total_amount: string }>;
}

export interface NewAccountsTimeseriesResponse {
  from: string;
  to: string;
  new_passengers_per_day: Record<string, number>;
  new_drivers_per_day: Record<string, number>;
}

export interface Transaction {
  id: string;
  user_id: string;
  type: string;
  status: string;
  amount: string;
  payment_method: string | null;
  created_at: string;
  user?: PlatformUser;
}

export interface PayoutRequest {
  id: string;
  driver_id: string;
  amount: string;
  status: "pending" | "processed" | "rejected";
  destination_ref: string | null;
  created_at: string;
  driver?: Driver;
}

/** Personne liée à une alerte SOS (auteur, chauffeur, passagers). */
export interface SosPerson {
  id: string;
  full_name: string;
  phone_number: string | null;
  emergency_contact: EmergencyContact | null;
}

/** Fiche d'alerte SOS (GET /admin/sos-alerts, /admin/sos-alerts/:id). */
export interface SosAlert {
  id: string;
  status: "open" | "in_progress" | "resolved";
  role: "passenger" | "driver";
  triggered_at: string;
  ended_at: string | null;
  last_location_at: string | null;
  last_lat: number | null;
  last_lng: number | null;
  /** [lat, lng, horodatage ISO] */
  path: [number, number, string][];
  resolution_notes: string | null;
  handled_by: string | null;
  user: SosPerson | null;
  booking_id: string | null;
  trip: {
    id: string;
    origin_name: string | null;
    destination_name: string | null;
    status: string;
    scheduled_at: string | null;
    current_lat: number | null;
    current_lng: number | null;
    vehicle: { label: string; plate_number: string } | null;
    driver: SosPerson | null;
    passengers: SosPerson[];
  } | null;
  recordings: { id: string; duration_ms: number; created_at: string; file_endpoint: string }[];
}

export interface Dispute {
  id: string;
  reported_by_id: string;
  reported_against_id: string;
  reason: string;
  status: "open" | "investigating" | "resolved" | "dismissed";
  description: string | null;
  resolution: string | null;
  created_at: string;
}

export interface PlatformSetting {
  id: string;
  zone_name: string;
  price_per_km: string;
  commission_pct: string;
}

export interface Trip {
  id: string;
  status: string;
  origin_lat?: number;
  origin_lng?: number;
  destination_lat?: number;
  destination_lng?: number;
  price_per_seat: string;
  seats_available: number;
  driver?: Driver;
}

export interface LuggagePhoto {
  id: string;
  booking_id: string;
  photo_url: string;
  uploaded_at: string;
}

export interface Booking {
  id: string;
  trip_id: string;
  passenger_id: string;
  seat_count: number;
  has_heavy_luggage: boolean;
  status: string;
  departure_code: string;
  price_charged: string;
  passenger?: PlatformUser;
  trip?: Trip;
  luggage_photos?: LuggagePhoto[];
  created_at: string;
}


export interface MapTripItem {
  id: string;
  status: "open" | "full" | "in_progress" | string;
  origin_name: string;
  destination_name: string;
  origin_lat: number;
  origin_lng: number;
  destination_lat: number;
  destination_lng: number;
  current_lat: number;
  current_lng: number;
  current_heading: number | null;
  location_updated_at: string | null;
  scheduled_at: string | null;
  seats_available: number;
  price_per_seat: string;
  waypoints: { name?: string; lat: number; lng: number }[];
  driver: {
    id: string;
    full_name: string;
    phone_number: string;
  } | null;
  vehicle: {
    make: string;
    model: string;
    plate_number: string;
  } | null;
}

export interface MapSosAlertItem {
  id: string;
  status: string;
  lat: number;
  lng: number;
  triggered_at: string | null;
  user_name: string;
  user_phone: string;
}

export interface MapTripsResponse {
  trips: MapTripItem[];
  sos_alerts: MapSosAlertItem[];
}

// ── Supervision des trajets (/admin/trips) ─────────────────────────────────

export type TripStatus = "open" | "full" | "in_progress" | "completed" | "cancelled";

export type BookingStatus =
  | "pending_driver"
  | "confirmed"
  | "rejected"
  | "cancelled_passenger"
  | "cancelled_driver"
  | "completed"
  | "no_show";

export interface AdminTrip {
  id: string;
  status: TripStatus;
  closed_by: "driver" | "system" | "admin" | null;
  departure_type: "now" | "scheduled";
  scheduled_at: string | null;
  created_at: string | null;
  origin_name: string | null;
  destination_name: string | null;
  price_per_seat: string;
  seats_available: number;
  confirmed_bookings_count: number;
  pending_bookings_count: number;
  driver: { id: string; full_name: string; phone_number: string | null } | null;
  vehicle: { brand: string | null; model: string | null; plate_number: string; seat_count: number } | null;
}

export interface AdminTripStop {
  id: string;
  position: number;
  name: string;
  address: string | null;
  scheduled_at: string | null;
  price_from_origin: string;
}

export interface AdminTripBooking {
  id: string;
  status: BookingStatus;
  /** Noms des arrêts de montée / descente du passager. */
  boarding_stop: string | null;
  alighting_stop: string | null;
  seat_count: number;
  seat_numbers: string[];
  price_charged: string;
  has_heavy_luggage: boolean;
  created_at: string | null;
  started_at: string | null;
  passenger: { id: string; full_name: string; phone_number: string | null } | null;
}

export interface AdminTripDetail extends AdminTrip {
  origin_lat: number;
  origin_lng: number;
  destination_lat: number;
  destination_lng: number;
  women_only: boolean;
  toll_fees: string | null;
  location_updated_at: string | null;
  /** Dernier arrêt atteint par le chauffeur pendant le trajet (0 = départ). */
  last_passed_stop_position: number | null;
  stops: AdminTripStop[];
  bookings: AdminTripBooking[];
}
