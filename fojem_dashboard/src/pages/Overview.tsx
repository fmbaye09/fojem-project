import { Users, Car, Route, CalendarClock, ShieldAlert, Gavel } from "lucide-react";
import { useApi } from "../lib/useApi";
import type { OverviewResponse, TimeseriesResponse } from "../types/api";
import { StatTile } from "../components/ui/StatTile";
import { Card } from "../components/ui/Card";
import { Skeleton } from "../components/ui/Skeleton";
import { ErrorState } from "../components/ui/ErrorState";
import { TimeseriesChart } from "../components/charts/TimeseriesChart";
import { CategoryBarChart, type CategoryDatum } from "../components/charts/CategoryBarChart";
import { CATEGORICAL_COLORS } from "../lib/chartColors";

function bookingsCount(rows: { status: string; count: number }[]): number {
  return rows.reduce((sum, r) => sum + r.count, 0);
}

// Ordre fixe (jamais par rang de valeur) — chaque statut garde toujours la
// même couleur, y compris absent (compte 0) ou présent seul.
const TRIP_STATUS_ORDER = ["open", "full", "in_progress", "completed", "cancelled"] as const;
const TRIP_STATUS_LABELS: Record<string, string> = {
  open: "Ouverts",
  full: "Complets",
  in_progress: "En cours",
  completed: "Terminés",
  cancelled: "Annulés",
};

// Statuts de réservation canoniques (6, la taille de la palette catégorielle
// validée) — `no_show`, plus rare, est replié dans "Autres" plutôt que de
// forcer une 7e teinte non validée.
const BOOKING_STATUS_ORDER = [
  "pending_driver",
  "confirmed",
  "completed",
  "rejected",
  "cancelled_driver",
  "cancelled_passenger",
] as const;
const BOOKING_STATUS_LABELS: Record<string, string> = {
  pending_driver: "En attente chauffeur",
  confirmed: "Confirmées",
  completed: "Terminées",
  rejected: "Refusées",
  cancelled_driver: "Annulées (chauffeur)",
  cancelled_passenger: "Annulées (passager)",
};
const OTHER_BOOKING_COLOR = "#A0A09A"; // ink.muted — statuts repliés, pas une identité propre

function tripStatusData(byStatus: Record<string, number> | undefined): CategoryDatum[] {
  if (!byStatus) return [];
  return TRIP_STATUS_ORDER.filter((k) => (byStatus[k] ?? 0) > 0).map((k, i) => ({
    key: k,
    label: TRIP_STATUS_LABELS[k],
    value: byStatus[k] ?? 0,
    color: CATEGORICAL_COLORS[i % CATEGORICAL_COLORS.length],
  }));
}

function bookingStatusData(rows: { status: string; count: number }[]): CategoryDatum[] {
  const known: CategoryDatum[] = [];
  let otherTotal = 0;
  for (const status of BOOKING_STATUS_ORDER) {
    const row = rows.find((r) => r.status === status);
    if (row && row.count > 0) {
      known.push({
        key: status,
        label: BOOKING_STATUS_LABELS[status],
        value: row.count,
        color: CATEGORICAL_COLORS[BOOKING_STATUS_ORDER.indexOf(status) % CATEGORICAL_COLORS.length],
      });
    }
  }
  for (const row of rows) {
    if (!(BOOKING_STATUS_ORDER as readonly string[]).includes(row.status)) otherTotal += row.count;
  }
  if (otherTotal > 0) {
    known.push({ key: "other", label: "Autres statuts", value: otherTotal, color: OTHER_BOOKING_COLOR });
  }
  return known;
}

/**
 * Répartition des chauffeurs par statut de vérification — couleurs de
 * statut (success/neutral/danger), pas la palette catégorielle : ce sont de
 * vrais jugements bon/mauvais (approuvé/en attente/rejeté), donc les mêmes
 * tons que les badges `VERIFICATION_TONE` de la page Utilisateurs, jamais
 * une nouvelle teinte.
 */
function driverVerificationData(o: OverviewResponse | null): CategoryDatum[] {
  if (!o) return [];
  const rejected = Math.max(0, o.drivers.total - o.drivers.pending_verification - o.drivers.approved);
  const rows: CategoryDatum[] = [
    { key: "approved", label: "Approuvés", value: o.drivers.approved, color: "#32963C" },
    { key: "pending", label: "En attente", value: o.drivers.pending_verification, color: "#A0A09A" },
    { key: "rejected", label: "Rejetés", value: rejected, color: "#BE4947" },
  ];
  return rows.filter((r) => r.value > 0);
}

export function Overview() {
  const overview = useApi<OverviewResponse>("/admin/overview");
  const timeseries = useApi<TimeseriesResponse>("/admin/stats/timeseries");

  if (overview.error) return <ErrorState message={overview.error} />;

  const o = overview.data;
  const tripsOpen = o?.trips_by_status?.["open"] ?? 0;
  const tripsInProgress = o?.trips_by_status?.["in_progress"] ?? 0;

  const tripsSeries =
    timeseries.data &&
    (Array.isArray(timeseries.data.trips_per_day)
      ? timeseries.data.trips_per_day
          .slice()
          .sort((a, b) => a.date.localeCompare(b.date))
          .map((r) => ({ date: r.date.slice(5), value: r.count }))
      : Object.entries(timeseries.data.trips_per_day || {})
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([date, value]) => ({ date: date.slice(5), value: Number(value) || 0 })));

  const revenueSeries =
    timeseries.data &&
    (Array.isArray(timeseries.data.revenue_per_day)
      ? timeseries.data.revenue_per_day
          .slice()
          .sort((a, b) => a.date.localeCompare(b.date))
          .map((r) => ({ date: r.date.slice(5), value: parseFloat(r.total) || 0 }))
      : Object.entries(timeseries.data.revenue_per_day || {})
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([date, total]) => ({ date: date.slice(5), value: parseFloat(String(total)) || 0 })));

  const tripStatusChart = tripStatusData(o?.trips_by_status);
  const driverVerificationChart = driverVerificationData(o);
  const bookingWeekChart = bookingStatusData(o?.bookings_this_week_by_status ?? []);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Vue d'ensemble</h1>
        <p className="text-sm text-ink-secondary mt-0.5">
          Chiffres clés de la plateforme, agrégés en temps réel depuis le backend.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {overview.loading ? (
          Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} className="h-[92px] rounded-md" />)
        ) : (
          <>
            <StatTile label="Utilisateurs actifs" value={o?.users_active ?? 0} icon={Users} />
            <StatTile
              label="Chauffeurs approuvés"
              value={o?.drivers.approved ?? 0}
              icon={Car}
              tone="success"
              hint={`${o?.drivers.pending_verification ?? 0} en attente de vérification`}
            />
            <StatTile
              label="Trajets ouverts"
              value={tripsOpen}
              icon={Route}
              hint={tripsInProgress ? `${tripsInProgress} en cours` : "Aucun en cours"}
            />
            <StatTile
              label="Réservations aujourd'hui"
              value={bookingsCount(o?.bookings_today_by_status ?? [])}
              icon={CalendarClock}
              hint={`${bookingsCount(o?.bookings_this_week_by_status ?? [])} cette semaine`}
            />
            <StatTile
              label="Chauffeurs en attente"
              value={o?.drivers.pending_verification ?? 0}
              icon={Car}
              tone={o && o.drivers.pending_verification > 0 ? "danger" : "default"}
            />
            <StatTile label="Chauffeurs (total)" value={o?.drivers.total ?? 0} icon={Car} />
            <StatTile
              label="Alertes SOS ouvertes"
              value={o?.sos_alerts_open ?? 0}
              icon={ShieldAlert}
              tone={o && o.sos_alerts_open > 0 ? "danger" : "success"}
            />
            <StatTile
              label="Litiges ouverts"
              value={o?.disputes_open ?? 0}
              icon={Gavel}
              tone={o && o.disputes_open > 0 ? "danger" : "success"}
            />
          </>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-1">Trajets publiés / jour</h2>
          <p className="text-xs text-ink-secondary mb-3">30 derniers jours</p>
          {timeseries.loading ? (
            <Skeleton className="h-[200px] rounded-sm" />
          ) : timeseries.error ? (
            <ErrorState message={timeseries.error} />
          ) : tripsSeries && tripsSeries.length > 0 ? (
            <TimeseriesChart data={tripsSeries} color="#EA671A" name="Trajets" />
          ) : (
            <p className="text-sm text-ink-muted py-16 text-center">Aucun trajet sur la période.</p>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-1">Revenu plateforme / jour</h2>
          <p className="text-xs text-ink-secondary mb-3">Transactions complétées, 30 derniers jours</p>
          {timeseries.loading ? (
            <Skeleton className="h-[200px] rounded-sm" />
          ) : timeseries.error ? (
            <ErrorState message={timeseries.error} />
          ) : revenueSeries && revenueSeries.length > 0 ? (
            <TimeseriesChart
              data={revenueSeries}
              color="#3D6FA8"
              name="Revenu"
              valueFormatter={(v) => (v >= 1000 ? `${Math.round(v / 1000)}k` : String(v))}
            />
          ) : (
            <p className="text-sm text-ink-muted py-16 text-center">
              Aucune transaction complétée sur la période.
            </p>
          )}
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-3">Trajets par statut</h2>
          {overview.loading ? (
            <Skeleton className="h-[140px] rounded-sm" />
          ) : tripStatusChart.length > 0 ? (
            <CategoryBarChart data={tripStatusChart} />
          ) : (
            <p className="text-sm text-ink-muted py-8 text-center">Aucun trajet enregistré.</p>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-3">Chauffeurs par statut de vérification</h2>
          {overview.loading ? (
            <Skeleton className="h-[100px] rounded-sm" />
          ) : driverVerificationChart.length > 0 ? (
            <CategoryBarChart data={driverVerificationChart} />
          ) : (
            <p className="text-sm text-ink-muted py-8 text-center">Aucun chauffeur enregistré.</p>
          )}
        </Card>
      </div>

      {!overview.loading && o && (
        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-3">Réservations de la semaine, par statut</h2>
          {bookingWeekChart.length === 0 ? (
            <p className="text-sm text-ink-muted py-4">Aucune réservation cette semaine.</p>
          ) : (
            <CategoryBarChart data={bookingWeekChart} />
          )}
        </Card>
      )}
    </div>
  );
}
