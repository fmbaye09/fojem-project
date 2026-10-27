import { useEffect, useState } from "react";
import { Route as RouteIcon, ArrowRight, Users, Luggage, Car } from "lucide-react";
import { useApi } from "../lib/useApi";
import { apiFetch, ApiError } from "../lib/api";
import type { AdminTrip, AdminTripDetail, Paginated } from "../types/api";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Select } from "../components/ui/Select";
import { Skeleton } from "../components/ui/Skeleton";
import { EmptyState } from "../components/ui/EmptyState";
import { ErrorState } from "../components/ui/ErrorState";
import { Pagination } from "../components/ui/Pagination";
import { Modal } from "../components/ui/Modal";
import { formatDateTime, formatXof } from "../lib/utils";
import { useAuthStore } from "../store/useAuthStore";
import {
  BOOKING_STATUS_LABEL,
  BOOKING_STATUS_TONE,
  CLOSED_BY_LABEL,
  TRIP_STATUS_LABEL,
  TRIP_STATUS_TONE,
  isTripCancellable,
} from "../components/trips/tripLabels";

/** Valeur recopiée après une pause de frappe, pour ne pas requêter à chaque touche. */
function useDebounced<T>(value: T, delayMs = 350): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}

/** Date de départ affichée : horaire prévu, ou création pour un départ immédiat. */
function departureLabel(trip: AdminTrip): string {
  const iso = trip.scheduled_at ?? trip.created_at;
  if (!iso) return "—";
  return trip.departure_type === "now" ? `Immédiat · ${formatDateTime(iso)}` : formatDateTime(iso);
}

function routeLabel(trip: AdminTrip) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span>{trip.origin_name ?? "Départ"}</span>
      <ArrowRight size={13} className="text-ink-muted shrink-0" />
      <span>{trip.destination_name ?? "Arrivée"}</span>
    </span>
  );
}

function TripDetailModal({
  tripId,
  onClose,
  onCancelled,
}: {
  tripId: string | null;
  onClose: () => void;
  onCancelled: () => void;
}) {
  const canEdit = useAuthStore((s) => s.hasPermission("trips", "edit"));
  const [confirming, setConfirming] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data, loading, error, reload } = useApi<{ trip: AdminTripDetail }>(
    tripId ? `/admin/trips/${tripId}` : null,
    { pollInterval: false },
    [tripId],
  );
  const trip = data?.trip;

  function close() {
    setConfirming(false);
    setReason("");
    setActionError(null);
    onClose();
  }

  async function cancelTrip() {
    if (!trip) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/admin/trips/${trip.id}/cancel`, { method: "POST", body: { reason: reason.trim() } });
      setConfirming(false);
      setReason("");
      reload();
      onCancelled();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : "Annulation impossible.");
    } finally {
      setBusy(false);
    }
  }

  const activeBookings = trip?.bookings.filter(
    (b) => b.status === "pending_driver" || b.status === "confirmed",
  ).length ?? 0;

  return (
    <Modal open={!!tripId} onClose={close} title="Détail du trajet" size="lg">
      {loading && !trip ? (
        <div className="flex flex-col gap-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-10 rounded-sm" />
          ))}
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : trip ? (
        <div className="flex flex-col gap-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="text-base font-semibold text-ink-primary">{routeLabel(trip)}</div>
              <div className="text-xs text-ink-muted mt-0.5">{departureLabel(trip)}</div>
            </div>
            <div className="flex flex-col items-end gap-1">
              <Badge tone={TRIP_STATUS_TONE[trip.status]}>{TRIP_STATUS_LABEL[trip.status]}</Badge>
              {trip.status === "cancelled" && trip.closed_by && (
                <span className="text-xs text-ink-muted">Annulé {CLOSED_BY_LABEL[trip.closed_by]}</span>
              )}
            </div>
          </div>

          <dl className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
            <div>
              <dt className="text-xs text-ink-muted">Chauffeur</dt>
              <dd className="text-ink-primary font-medium">{trip.driver?.full_name ?? "—"}</dd>
              {trip.driver?.phone_number && <dd className="text-xs text-ink-secondary">{trip.driver.phone_number}</dd>}
            </div>
            <div>
              <dt className="text-xs text-ink-muted">Véhicule</dt>
              <dd className="text-ink-primary font-medium">
                {trip.vehicle ? [trip.vehicle.brand, trip.vehicle.model].filter(Boolean).join(" ") || "—" : "—"}
              </dd>
              {trip.vehicle && <dd className="text-xs text-ink-secondary">{trip.vehicle.plate_number}</dd>}
            </div>
            <div>
              <dt className="text-xs text-ink-muted">Prix par place</dt>
              <dd className="text-ink-primary font-medium">{formatXof(trip.price_per_seat)}</dd>
            </div>
            <div>
              <dt className="text-xs text-ink-muted">Places restantes</dt>
              <dd className="text-ink-primary font-medium">{trip.seats_available}</dd>
              {trip.women_only && <dd className="text-xs text-ink-secondary">Réservé aux femmes</dd>}
            </div>
          </dl>

          <div>
            <h3 className="text-sm font-semibold text-ink-primary flex items-center gap-2 mb-2">
              <Users size={15} /> Passagers ({trip.bookings.length})
            </h3>
            {trip.bookings.length === 0 ? (
              <p className="text-sm text-ink-muted">Aucune réservation sur ce trajet.</p>
            ) : (
              <div className="border border-line rounded-sm overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs text-ink-muted border-b border-line">
                      <th className="px-3 py-2 font-medium">Passager</th>
                      <th className="px-3 py-2 font-medium">Places</th>
                      <th className="px-3 py-2 font-medium">Montant</th>
                      <th className="px-3 py-2 font-medium">Statut</th>
                    </tr>
                  </thead>
                  <tbody>
                    {trip.bookings.map((b) => (
                      <tr key={b.id} className="border-b border-line last:border-0">
                        <td className="px-3 py-2">
                          <div className="text-ink-primary">{b.passenger?.full_name ?? "Passager supprimé"}</div>
                          {b.passenger?.phone_number && (
                            <div className="text-xs text-ink-muted">{b.passenger.phone_number}</div>
                          )}
                        </td>
                        <td className="px-3 py-2 text-ink-secondary">
                          {b.seat_numbers.length > 0 ? `n° ${b.seat_numbers.join(", ")}` : b.seat_count}
                          {b.has_heavy_luggage && (
                            <Luggage size={13} className="inline ml-1.5 text-primary" aria-label="Bagages lourds" />
                          )}
                        </td>
                        <td className="px-3 py-2 text-ink-secondary whitespace-nowrap">{formatXof(b.price_charged)}</td>
                        <td className="px-3 py-2">
                          <Badge tone={BOOKING_STATUS_TONE[b.status]}>
                            {b.status === "confirmed" && b.started_at ? "À bord" : BOOKING_STATUS_LABEL[b.status]}
                          </Badge>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {canEdit && isTripCancellable(trip.status) && (
            <div className="border-t border-line pt-4">
              {!confirming ? (
                <div className="flex justify-end">
                  <Button variant="secondary" className="text-danger" onClick={() => setConfirming(true)}>
                    Annuler ce trajet
                  </Button>
                </div>
              ) : (
                <div className="flex flex-col gap-3">
                  <p className="text-sm text-ink-secondary">
                    {activeBookings > 0
                      ? `${activeBookings} réservation(s) en cours seront annulées et les passagers prévenus.`
                      : "Aucune réservation en cours sur ce trajet."}{" "}
                    Le motif est conservé dans le journal d'audit.
                  </p>
                  <textarea
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="Motif de l'annulation (obligatoire)"
                    className="w-full h-20 px-2.5 py-1.5 rounded-sm border border-line text-sm outline-none focus:border-primary"
                  />
                  {actionError && (
                    <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2">{actionError}</div>
                  )}
                  <div className="flex justify-end gap-2">
                    <Button variant="secondary" onClick={() => setConfirming(false)} disabled={busy}>
                      Retour
                    </Button>
                    <Button onClick={cancelTrip} disabled={busy || reason.trim().length < 3}>
                      Confirmer l'annulation
                    </Button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      ) : null}
    </Modal>
  );
}

export function Trips() {
  const [status, setStatus] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const search = useDebounced(searchInput.trim());
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<AdminTrip>>(
    "/admin/trips",
    {
      query: {
        status: status || undefined,
        search: search || undefined,
        date_from: dateFrom || undefined,
        date_to: dateTo || undefined,
        page,
      },
    },
    [status, search, dateFrom, dateTo, page],
  );

  const hasFilters = !!(status || search || dateFrom || dateTo);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Trajets</h1>
        <p className="text-sm text-ink-secondary mt-0.5">
          Tous les trajets publiés, leurs passagers, et l'annulation en cas de problème.
        </p>
      </div>

      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-end gap-2 p-4 border-b border-line">
          <Input
            value={searchInput}
            onChange={(e) => { setPage(1); setSearchInput(e.target.value); }}
            placeholder="Ville, chauffeur ou téléphone"
            className="w-full sm:w-64"
          />
          <Select value={status} onChange={(e) => { setPage(1); setStatus(e.target.value); }}>
            <option value="">Tous les statuts</option>
            {(Object.keys(TRIP_STATUS_LABEL) as (keyof typeof TRIP_STATUS_LABEL)[]).map((s) => (
              <option key={s} value={s}>{TRIP_STATUS_LABEL[s]}</option>
            ))}
          </Select>
          <label className="flex flex-col text-xs text-ink-muted gap-1">
            Du
            <Input type="date" value={dateFrom} onChange={(e) => { setPage(1); setDateFrom(e.target.value); }} />
          </label>
          <label className="flex flex-col text-xs text-ink-muted gap-1">
            Au
            <Input type="date" value={dateTo} onChange={(e) => { setPage(1); setDateTo(e.target.value); }} />
          </label>
          {hasFilters && (
            <Button
              variant="secondary"
              onClick={() => {
                setStatus("");
                setSearchInput("");
                setDateFrom("");
                setDateTo("");
                setPage(1);
              }}
            >
              Effacer les filtres
            </Button>
          )}
        </div>

        {loading ? (
          <div className="p-4 flex flex-col gap-2">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-14 rounded-sm" />
            ))}
          </div>
        ) : error ? (
          <ErrorState message={error} />
        ) : !data || data.data.length === 0 ? (
          <EmptyState
            icon={RouteIcon}
            title="Aucun trajet"
            description={hasFilters ? "Aucun trajet ne correspond à ces filtres." : "Aucun trajet n'a encore été publié."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-ink-muted border-b border-line">
                  <th className="px-4 py-2.5 font-medium">Trajet</th>
                  <th className="px-4 py-2.5 font-medium">Chauffeur</th>
                  <th className="px-4 py-2.5 font-medium">Places</th>
                  <th className="px-4 py-2.5 font-medium">Prix</th>
                  <th className="px-4 py-2.5 font-medium">Statut</th>
                </tr>
              </thead>
              <tbody>
                {data.data.map((trip) => (
                  <tr
                    key={trip.id}
                    onClick={() => setSelectedId(trip.id)}
                    className="border-b border-line last:border-0 hover:bg-line/20 cursor-pointer"
                  >
                    <td className="px-4 py-3">
                      <div className="text-ink-primary font-medium">{routeLabel(trip)}</div>
                      <div className="text-xs text-ink-muted">{departureLabel(trip)}</div>
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-ink-primary">{trip.driver?.full_name ?? "—"}</div>
                      {trip.vehicle && (
                        <div className="text-xs text-ink-muted flex items-center gap-1">
                          <Car size={12} /> {trip.vehicle.plate_number}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-ink-secondary whitespace-nowrap">
                      {trip.confirmed_bookings_count} réservée(s) · {trip.seats_available} libre(s)
                      {trip.pending_bookings_count > 0 && (
                        <div className="text-xs text-primary">{trip.pending_bookings_count} demande(s) en attente</div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-ink-secondary whitespace-nowrap">{formatXof(trip.price_per_seat)}</td>
                    <td className="px-4 py-3">
                      <Badge tone={TRIP_STATUS_TONE[trip.status]}>{TRIP_STATUS_LABEL[trip.status]}</Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data && (
          <div className="px-4 pb-3">
            <Pagination page={data.current_page} lastPage={data.last_page} total={data.total} onChange={setPage} />
          </div>
        )}
      </Card>

      <TripDetailModal tripId={selectedId} onClose={() => setSelectedId(null)} onCancelled={reload} />
    </div>
  );
}
