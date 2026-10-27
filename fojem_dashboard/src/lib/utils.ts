import { clsx, type ClassValue } from "clsx";

export function cn(...inputs: ClassValue[]) {
  return clsx(inputs);
}

export function formatXof(amount: string | number): string {
  const n = typeof amount === "string" ? parseFloat(amount) : amount;
  if (Number.isNaN(n)) return "—";
  return new Intl.NumberFormat("fr-SN", { maximumFractionDigits: 0 }).format(n) + " FCFA";
}

export function formatDate(iso: string): string {
  return new Intl.DateTimeFormat("fr-FR", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(iso));
}

export function formatDateTime(iso: string): string {
  return new Intl.DateTimeFormat("fr-FR", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso));
}

export function formatTime(iso: string): string {
  return new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}
