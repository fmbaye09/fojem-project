import type { LatLng, SimStop, SimTrip } from "./types";

const EARTH_RADIUS_M = 6371000;
const toRad = (deg: number) => (deg * Math.PI) / 180;

export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = toRad(b[0] - a[0]);
  const dLng = toRad(b[1] - a[1]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Cap en degrés (0 = nord, sens horaire), comme le GPS d'un téléphone. */
export function bearing(a: LatLng, b: LatLng): number {
  const y = Math.sin(toRad(b[1] - a[1])) * Math.cos(toRad(b[0]));
  const x =
    Math.cos(toRad(a[0])) * Math.sin(toRad(b[0])) -
    Math.sin(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.cos(toRad(b[1] - a[1]));
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/** Une route et la distance parcourue à chacun de ses points. */
export interface Path {
  points: LatLng[];
  cumulative: number[];
  length: number;
}

export function buildPath(points: LatLng[]): Path {
  const cumulative = [0];
  for (let i = 1; i < points.length; i++) {
    cumulative.push(cumulative[i - 1] + haversineM(points[i - 1], points[i]));
  }
  return { points, cumulative, length: cumulative[cumulative.length - 1] ?? 0 };
}

/** Le point de la route à [distance] mètres du départ, et le cap à cet endroit. */
export function pointAt(path: Path, distance: number): { point: LatLng; heading: number } {
  const { points, cumulative } = path;
  if (points.length === 0) return { point: [0, 0], heading: 0 };
  if (points.length === 1 || distance <= 0) {
    return { point: points[0], heading: points.length > 1 ? bearing(points[0], points[1]) : 0 };
  }
  if (distance >= path.length) {
    const n = points.length;
    return { point: points[n - 1], heading: bearing(points[n - 2], points[n - 1]) };
  }
  // Recherche dichotomique du segment.
  let lo = 0;
  let hi = cumulative.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (cumulative[mid] <= distance) lo = mid;
    else hi = mid;
  }
  const a = points[lo];
  const b = points[hi];
  const span = cumulative[hi] - cumulative[lo];
  const t = span > 0 ? (distance - cumulative[lo]) / span : 0;
  return { point: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], heading: bearing(a, b) };
}

/**
 * Où un point se projette sur la route : distance depuis le départ (m) et
 * écart à la route (m). [from] ignore ce qui précède (arrêts dans l'ordre).
 */
export function projectOnPath(path: Path, p: LatLng, from = 0): { distance: number; offset: number } {
  let best = { distance: from, offset: Infinity };
  const { points, cumulative } = path;
  for (let i = 0; i < points.length - 1; i++) {
    if (cumulative[i + 1] < from) continue;
    const a = points[i];
    const b = points[i + 1];
    const cos = Math.cos(toRad(a[0]));
    const bx = (b[1] - a[1]) * 111320 * cos;
    const by = (b[0] - a[0]) * 110540;
    const px = (p[1] - a[1]) * 111320 * cos;
    const py = (p[0] - a[0]) * 110540;
    const len2 = bx * bx + by * by;
    const t = len2 > 0 ? Math.max(0, Math.min(1, (px * bx + py * by) / len2)) : 0;
    const offset = Math.hypot(px - t * bx, py - t * by);
    const distance = cumulative[i] + t * (cumulative[i + 1] - cumulative[i]);
    if (offset < best.offset && distance >= from) best = { distance, offset };
  }
  return best;
}

/** Un point à [meters] au nord-est de [p] : position plausible d'un passager qui attend. */
export function nudge(p: LatLng, meters: number): LatLng {
  const d = meters / Math.SQRT2;
  return [p[0] + d / 110540, p[1] + d / (111320 * Math.cos(toRad(p[0])))];
}

export function formatKm(meters: number): string {
  return meters < 1000 ? `${Math.round(meters)} m` : `${(meters / 1000).toFixed(meters < 10000 ? 1 : 0).replace(".", ",")} km`;
}

/** Rayon dans lequel le serveur considère le chauffeur à un arrêt (TripProgressService). */
export const STOP_RADIUS_M = 400;

/**
 * D'après le serveur, le chauffeur a quitté cet arrêt : il l'avait atteint et
 * sa dernière position en est loin (ou le trajet est terminé).
 */
export function driverLeft(trip: SimTrip, stop: SimStop): boolean {
  if (trip.status === "completed") return true;
  if (trip.status !== "in_progress" || !stop.reached_at || trip.current_lat == null || trip.current_lng == null) return false;
  return haversineM([trip.current_lat, trip.current_lng], [stop.lat, stop.lng]) > STOP_RADIUS_M;
}
