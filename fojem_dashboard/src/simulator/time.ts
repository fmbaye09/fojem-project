import { useEffect, useState } from "react";

/** L'heure actuelle, rafraîchie toutes les [ms] (comptes à rebours). */
export function useNow(ms = 1000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), ms);
    return () => window.clearInterval(id);
  }, [ms]);
  return now;
}

const hm = new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit" });
const hms = new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });

export const clock = (iso: string | null | undefined) => (iso ? hm.format(new Date(iso)) : "—");
export const clockSec = (iso: string | null | undefined) => (iso ? hms.format(new Date(iso)) : "—");

/** « il y a 12 s », « il y a 3 min ». */
export function ago(iso: string | null | undefined, now: number): string {
  if (!iso) return "jamais";
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
  if (s < 60) return `il y a ${s} s`;
  const m = Math.floor(s / 60);
  return m < 60 ? `il y a ${m} min` : `il y a ${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}`;
}

/** Temps restant : « 4:05 » sous l'heure, « 1 h 05 » au-delà. */
export function countdown(ms: number): string {
  const total = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0 ? `${h} h ${String(m).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
}

/** Écart en minutes entre deux heures (b − a), arrondi. */
export function minutesBetween(a: string, b: string): number {
  return Math.round((new Date(b).getTime() - new Date(a).getTime()) / 60000);
}
