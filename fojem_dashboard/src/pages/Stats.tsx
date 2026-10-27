import { Star, CheckCircle2 } from "lucide-react";
import { useApi } from "../lib/useApi";
import type {
  TimeseriesResponse,
  AcceptanceRateResponse,
  AverageRatingResponse,
  TransactionsBreakdownResponse,
  NewAccountsTimeseriesResponse,
} from "../types/api";
import { Card } from "../components/ui/Card";
import { Skeleton } from "../components/ui/Skeleton";
import { ErrorState } from "../components/ui/ErrorState";
import { TimeseriesChart } from "../components/charts/TimeseriesChart";
import { StatTile } from "../components/ui/StatTile";
import { Meter } from "../components/charts/Meter";
import { CategoryBarChart, type CategoryDatum } from "../components/charts/CategoryBarChart";
import { colorForCategory } from "../lib/chartColors";

const PAYMENT_METHOD_LABELS: Record<string, string> = {
  cash: "Espèces",
  wave: "Wave",
  orange_money: "Orange Money",
  free_money: "Free Money",
  card: "Carte",
  wallet: "Portefeuille FOJËM",
};
const PAYMENT_METHOD_ORDER = Object.keys(PAYMENT_METHOD_LABELS);

const TRANSACTION_TYPE_LABELS: Record<string, string> = {
  payment: "Paiement trajet",
  payout: "Retrait chauffeur",
  commission: "Commission plateforme",
  refund: "Remboursement",
  referral_bonus: "Bonus parrainage",
};
const TRANSACTION_TYPE_ORDER = Object.keys(TRANSACTION_TYPE_LABELS);

function toCategoryData(
  raw: Record<string, { count: number }> | undefined,
  labels: Record<string, string>,
  order: string[],
): CategoryDatum[] {
  if (!raw) return [];
  return Object.entries(raw)
    .map(([key, v]) => ({
      key,
      label: labels[key] ?? key,
      value: v.count,
      color: colorForCategory(order, key),
    }))
    .sort((a, b) => b.value - a.value);
}

function toTimeseries(
  raw: Record<string, number | string> | { date: string; count?: number; value?: number; total?: string }[] | undefined,
) {
  if (!raw) return [];
  if (Array.isArray(raw)) {
    return raw
      .slice()
      .sort((a, b) => a.date.localeCompare(b.date))
      .map((r) => ({
        date: r.date.slice(5),
        value: typeof r.count === "number" ? r.count : parseFloat(String(r.total ?? r.value ?? 0)) || 0,
      }));
  }
  return Object.entries(raw)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, value]) => ({ date: date.slice(5), value: Number(value) || 0 }));
}

export function Stats() {
  const timeseries = useApi<TimeseriesResponse>("/admin/stats/timeseries");
  const acceptance = useApi<AcceptanceRateResponse>("/admin/stats/booking-acceptance-rate");
  const rating = useApi<AverageRatingResponse>("/admin/stats/average-rating");
  const txBreakdown = useApi<TransactionsBreakdownResponse>("/admin/stats/transactions-breakdown");
  const newAccounts = useApi<NewAccountsTimeseriesResponse>("/admin/stats/new-accounts-timeseries");

  const byMethod = toCategoryData(txBreakdown.data?.by_payment_method, PAYMENT_METHOD_LABELS, PAYMENT_METHOD_ORDER);
  const byType = toCategoryData(txBreakdown.data?.by_type, TRANSACTION_TYPE_LABELS, TRANSACTION_TYPE_ORDER);
  const newPassengers = toTimeseries(newAccounts.data?.new_passengers_per_day);
  const newDrivers = toTimeseries(newAccounts.data?.new_drivers_per_day);
  const bookingsSeries = toTimeseries(timeseries.data?.bookings_per_day);

  const acceptancePct =
    acceptance.data?.acceptance_rate !== null && acceptance.data?.acceptance_rate !== undefined
      ? `${Math.round(acceptance.data.acceptance_rate * 100)}%`
      : "—";

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Statistiques</h1>
        <p className="text-sm text-ink-secondary mt-0.5">
          Indicateurs de performance de la plateforme, à échelle honnête — aucune valeur extrapolée.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {acceptance.loading ? (
          <Skeleton className="h-[92px] rounded-md" />
        ) : acceptance.error ? (
          <Card className="p-4">
            <ErrorState message={acceptance.error} />
          </Card>
        ) : (
          <Card className="p-4 flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-ink-secondary">Taux d'acceptation des réservations</span>
              <div className="w-8 h-8 rounded-sm flex items-center justify-center shrink-0 bg-primary-surface text-primary">
                <CheckCircle2 size={16} strokeWidth={2} />
              </div>
            </div>
            <div className="text-2xl font-semibold text-ink-primary leading-none">{acceptancePct}</div>
            <Meter ratio={acceptance.data?.acceptance_rate ?? null} />
            <div className="text-xs text-ink-muted">
              {acceptance.data
                ? `${acceptance.data.accepted_bookings} acceptées sur ${acceptance.data.decided_bookings} réservations décidées (30 derniers jours)`
                : "Aucune donnée sur la période."}
            </div>
          </Card>
        )}

        {rating.loading ? (
          <Skeleton className="h-[92px] rounded-md" />
        ) : rating.error ? (
          <Card className="p-4">
            <ErrorState message={rating.error} />
          </Card>
        ) : (
          <StatTile
            label="Note moyenne plateforme"
            value={rating.data?.platform_average_rating != null ? `${rating.data.platform_average_rating.toFixed(1)} / 5` : "—"}
            icon={Star}
            hint={rating.data ? `Basée sur ${rating.data.rated_drivers_count} chauffeur(s) noté(s)` : undefined}
          />
        )}
      </div>

      <Card className="p-4">
        <h2 className="text-sm font-medium text-ink-primary mb-1">Réservations / jour</h2>
        <p className="text-xs text-ink-secondary mb-3">30 derniers jours</p>
        {timeseries.loading ? (
          <Skeleton className="h-[200px] rounded-sm" />
        ) : timeseries.error ? (
          <ErrorState message={timeseries.error} />
        ) : bookingsSeries && bookingsSeries.length > 0 ? (
          <TimeseriesChart data={bookingsSeries} color="#EA671A" name="Réservations" />
        ) : (
          <p className="text-sm text-ink-muted py-16 text-center">Aucune réservation sur la période.</p>
        )}
      </Card>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-1">Transactions par méthode</h2>
          <p className="text-xs text-ink-secondary mb-3">30 derniers jours, transactions complétées</p>
          {txBreakdown.loading ? (
            <Skeleton className="h-[140px] rounded-sm" />
          ) : txBreakdown.error ? (
            <ErrorState message={txBreakdown.error} />
          ) : byMethod.length > 0 ? (
            <CategoryBarChart data={byMethod} />
          ) : (
            <p className="text-sm text-ink-muted py-10 text-center">Aucune transaction sur la période.</p>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-1">Transactions par type</h2>
          <p className="text-xs text-ink-secondary mb-3">30 derniers jours, transactions complétées</p>
          {txBreakdown.loading ? (
            <Skeleton className="h-[140px] rounded-sm" />
          ) : txBreakdown.error ? (
            <ErrorState message={txBreakdown.error} />
          ) : byType.length > 0 ? (
            <CategoryBarChart data={byType} />
          ) : (
            <p className="text-sm text-ink-muted py-10 text-center">Aucune transaction sur la période.</p>
          )}
        </Card>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-1">Nouveaux passagers / jour</h2>
          <p className="text-xs text-ink-secondary mb-3">30 derniers jours</p>
          {newAccounts.loading ? (
            <Skeleton className="h-[200px] rounded-sm" />
          ) : newAccounts.error ? (
            <ErrorState message={newAccounts.error} />
          ) : newPassengers.length > 0 ? (
            <TimeseriesChart data={newPassengers} color="#EA671A" name="Nouveaux passagers" />
          ) : (
            <p className="text-sm text-ink-muted py-16 text-center">Aucune inscription sur la période.</p>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="text-sm font-medium text-ink-primary mb-1">Nouveaux chauffeurs / jour</h2>
          <p className="text-xs text-ink-secondary mb-3">30 derniers jours</p>
          {newAccounts.loading ? (
            <Skeleton className="h-[200px] rounded-sm" />
          ) : newAccounts.error ? (
            <ErrorState message={newAccounts.error} />
          ) : newDrivers.length > 0 ? (
            <TimeseriesChart data={newDrivers} color="#3D6FA8" name="Nouveaux chauffeurs" />
          ) : (
            <p className="text-sm text-ink-muted py-16 text-center">Aucune inscription sur la période.</p>
          )}
        </Card>
      </div>
    </div>
  );
}
