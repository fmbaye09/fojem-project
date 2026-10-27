import type { BookingStatus, TripStatus } from "../../types/api";

// Libellés français + tons de Badge des statuts trajet/réservation. Ne jamais
// afficher la valeur d'enum telle quelle à l'écran.

export const TRIP_STATUS_LABEL: Record<TripStatus, string> = {
  open: "Ouvert",
  full: "Complet",
  in_progress: "En cours",
  completed: "Terminé",
  cancelled: "Annulé",
};

export const TRIP_STATUS_TONE = {
  open: "primary",
  full: "neutral",
  in_progress: "success",
  completed: "neutral",
  cancelled: "danger",
} as const;

export const CLOSED_BY_LABEL = {
  driver: "par le chauffeur",
  system: "automatiquement",
  admin: "par un administrateur",
} as const;

export const BOOKING_STATUS_LABEL: Record<BookingStatus, string> = {
  pending_driver: "En attente du chauffeur",
  confirmed: "Confirmée",
  rejected: "Refusée",
  cancelled_passenger: "Annulée par le passager",
  cancelled_driver: "Annulée",
  completed: "Terminée",
  no_show: "Absent",
};

export const BOOKING_STATUS_TONE = {
  pending_driver: "primary",
  confirmed: "success",
  rejected: "danger",
  cancelled_passenger: "neutral",
  cancelled_driver: "neutral",
  completed: "neutral",
  no_show: "danger",
} as const;

/** Un trajet peut encore être annulé tant qu'il n'est ni terminé ni annulé. */
export function isTripCancellable(status: TripStatus): boolean {
  return status !== "completed" && status !== "cancelled";
}
