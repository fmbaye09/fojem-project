import { Trash2 } from "lucide-react";
import { Badge } from "../../components/ui/Badge";
import { cn } from "../../lib/utils";
import { driverLeft, leftEarly } from "../geo";
import { useSimStore } from "../store";
import { ago, clock, clockSec, countdown, minutesBetween, useNow } from "../time";
import type { LogKind, SimNotification, SimTrip } from "../types";

/**
 * Heures de passage de chaque arrêt : prévue, estimée par le serveur
 * (position du chauffeur et OSRM, ou horaire publié), atteinte, et
 * l'attente du chauffeur avant de pouvoir déclarer une absence.
 */
export function TimesTable({ trip }: { trip: SimTrip | null }) {
  const now = useNow(1000);
  if (!trip) return <p className="p-4 text-sm text-ink-muted">Chargement du trajet…</p>;
  const live = trip.live;
  const etas = new Map((live?.etas ?? []).map((e) => [e.stop_id, e.eta]));
  const passed = trip.last_passed_stop_position ?? 0;
  const stops = [...trip.stops].sort((a, b) => a.position - b.position);

  return (
    <div className="flex flex-col gap-2 p-4">
      <div className="flex flex-wrap items-center gap-2 text-xs text-ink-secondary">
        {trip.status === "in_progress" ? (
          <>
            <Badge tone={live?.eta_source === "live" ? "success" : "neutral"}>
              {live?.eta_source === "live" ? "Estimées d'après la position du chauffeur" : "D'après l'horaire publié"}
            </Badge>
            {live?.delay_minutes != null && (
              <span>
                Prochain arrêt : {live.delay_minutes > 0 ? `${live.delay_minutes} min de retard` : live.delay_minutes < 0 ? `${-live.delay_minutes} min d'avance` : "à l'heure"}
              </span>
            )}
          </>
        ) : (
          <span>Les heures estimées apparaissent une fois le trajet démarré.</span>
        )}
        <span>· position reçue {ago(trip.location_updated_at, now)}</span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-ink-muted border-b border-line">
              <th className="py-2 pr-3 font-medium">Arrêt</th>
              <th className="py-2 pr-3 font-medium">Prévu</th>
              <th className="py-2 pr-3 font-medium">Estimé</th>
              <th className="py-2 pr-3 font-medium">Écart</th>
              <th className="py-2 pr-3 font-medium">Atteint</th>
              <th className="py-2 font-medium">Attente du chauffeur</th>
            </tr>
          </thead>
          <tbody>
            {stops.map((s, i) => {
              const eta = etas.get(s.id) ?? null;
              const gap = eta && s.scheduled_at ? minutesBetween(s.scheduled_at, eta) : null;
              const isPassed = trip.status === "in_progress" && s.position <= passed;
              const isNext = live?.next_stop_id === s.id;
              const wait = s.wait_until ? new Date(s.wait_until).getTime() : null;
              const left = driverLeft(trip, s);
              return (
                <tr key={s.id} className={cn("border-b border-line/60", isNext && "bg-primary-surface/50")}>
                  <td className="py-2 pr-3">
                    <span className="text-ink-muted mr-1.5 tabular-nums">{i + 1}.</span>
                    <span className={cn("font-medium", isPassed ? "text-ink-muted" : "text-ink-primary")}>{s.name}</span>
                    {isNext && <span className="ml-1.5 text-xs text-primary">prochain</span>}
                  </td>
                  <td className="py-2 pr-3 tabular-nums">{clock(s.scheduled_at)}</td>
                  <td className="py-2 pr-3 tabular-nums">{isPassed ? "—" : eta ? `vers ${clock(eta)}` : "—"}</td>
                  <td className={cn("py-2 pr-3 tabular-nums", gap !== null && gap > 0 && "text-danger", gap !== null && gap < 0 && "text-success")}>
                    {isPassed || gap === null ? "—" : gap === 0 ? "à l'heure" : gap > 0 ? `+${gap} min` : `${gap} min`}
                  </td>
                  <td className="py-2 pr-3 tabular-nums">{s.reached_at ? clockSec(s.reached_at) : "—"}</td>
                  <td className={cn("py-2 tabular-nums", leftEarly(s) && "text-danger")}>
                    {wait === null
                      ? "—"
                      : left && s.left_at
                        ? leftEarly(s)
                          ? `reparti à ${clock(s.left_at)}, avant ${clock(s.wait_until)}`
                          : `reparti à ${clock(s.left_at)}`
                        : wait > now
                          ? `jusqu'à ${clock(s.wait_until)} · ${countdown(wait - now)}`
                          : `terminée à ${clock(s.wait_until)}`}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function NotificationsFeed({ notifications }: { notifications: SimNotification[] }) {
  if (notifications.length === 0) {
    return <p className="p-4 text-sm text-ink-muted">Aucune notification envoyée pour l'instant.</p>;
  }
  return (
    <ul className="divide-y divide-line">
      {notifications.map((n) => (
        <li key={n.id} className="px-4 py-2.5 flex gap-3">
          <span className="text-xs text-ink-muted tabular-nums w-16 shrink-0 pt-0.5">{clockSec(n.created_at)}</span>
          <div className="min-w-0">
            <div className="text-sm">
              <span className="font-medium text-ink-primary">{n.user_name ?? "?"}</span>
              {!n.simulated && <span className="ml-1.5 text-xs text-primary">vrai compte</span>}
              <span className="text-ink-secondary"> · {n.title}</span>
            </div>
            {n.body && <div className="text-xs text-ink-secondary mt-0.5">{n.body}</div>}
          </div>
        </li>
      ))}
    </ul>
  );
}

const KIND_CLASS: Record<LogKind, string> = {
  action: "text-ink-primary",
  ok: "text-success",
  error: "text-danger",
  event: "text-primary",
  notification: "text-ink-secondary",
};

const KIND_LABEL: Record<LogKind, string> = {
  action: "Action",
  ok: "OK",
  error: "Refus",
  event: "Serveur",
  notification: "Notif.",
};

export function EventLog() {
  const log = useSimStore((s) => s.log);
  const clearLog = useSimStore((s) => s.clearLog);
  return (
    <div className="flex flex-col">
      <div className="flex justify-end px-4 pt-2">
        <button type="button" onClick={clearLog} className="inline-flex items-center gap-1 text-xs text-ink-muted hover:text-ink-primary">
          <Trash2 size={13} /> Effacer
        </button>
      </div>
      {log.length === 0 ? (
        <p className="p-4 text-sm text-ink-muted">Le journal est vide.</p>
      ) : (
        <ul className="divide-y divide-line">
          {log.map((e) => (
            <li key={e.id} className="px-4 py-2 flex gap-3 text-sm">
              <span className="text-xs text-ink-muted tabular-nums w-16 shrink-0 pt-0.5">{clockSec(e.at)}</span>
              <span className={cn("text-xs font-semibold w-14 shrink-0 pt-0.5", KIND_CLASS[e.kind])}>{KIND_LABEL[e.kind]}</span>
              <span className="text-ink-primary min-w-0 break-words">{e.text}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
