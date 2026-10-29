import { useState } from "react";
import { ShieldAlert, Gavel } from "lucide-react";
import { useApi } from "../lib/useApi";
import { apiFetch, ApiError } from "../lib/api";
import type { Paginated, SosAlert, Dispute } from "../types/api";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { Select } from "../components/ui/Select";
import { Skeleton } from "../components/ui/Skeleton";
import { EmptyState } from "../components/ui/EmptyState";
import { ErrorState } from "../components/ui/ErrorState";
import { Pagination } from "../components/ui/Pagination";
import { Modal } from "../components/ui/Modal";
import { formatDateTime, cn } from "../lib/utils";
import { useAuthStore } from "../store/useAuthStore";
import { useSosWatch } from "../store/useSosWatch";
import { SosAlertDetail } from "../components/sos/SosAlertDetail";

function SosSection() {
  const canEdit = useAuthStore((s) => s.hasPermission("sos_alerts", "edit"));
  const refreshWatch = useSosWatch((s) => s.refresh);
  const openCount = useSosWatch((s) => s.openCount);
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);
  const [viewing, setViewing] = useState<SosAlert | null>(null);
  const [target, setTarget] = useState<SosAlert | null>(null);
  const [notes, setNotes] = useState("");
  const [nextStatus, setNextStatus] = useState<"in_progress" | "resolved">("in_progress");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<SosAlert>>(
    "/admin/sos-alerts",
    { query: { status: status || undefined, page } },
    // Recharge aussi quand la surveillance voit arriver une alerte.
    [status, page, openCount],
  );

  function askStatus(a: SosAlert) {
    setNextStatus(a.status === "open" ? "in_progress" : "resolved");
    setTarget(a);
  }

  async function confirm() {
    if (!target) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/admin/sos-alerts/${target.id}`, {
        method: "PATCH",
        body: { status: nextStatus, ...(notes.trim() ? { resolution_notes: notes.trim() } : {}) },
      });
      setTarget(null);
      setViewing(null);
      setNotes("");
      reload();
      void refreshWatch();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : "Action impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-2 p-4 border-b border-line">
        <h2 className="text-sm font-semibold text-ink-primary flex items-center gap-2">
          <ShieldAlert size={16} className="text-danger" /> Alertes SOS
        </h2>
        <Select value={status} onChange={(e) => { setPage(1); setStatus(e.target.value); }}>
          <option value="">Tous les statuts</option>
          <option value="open">Ouverte</option>
          <option value="in_progress">En cours</option>
          <option value="resolved">Résolue</option>
        </Select>
      </div>

      {loading && !data ? (
        <div className="p-4 flex flex-col gap-2">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-14 rounded-sm" />
          ))}
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : !data || data.data.length === 0 ? (
        <EmptyState icon={ShieldAlert} title="Aucune alerte SOS" description="Aucune alerte ne correspond à ce filtre." />
      ) : (
        <div className="flex flex-col">
          {data.data.map((a) => (
            <div
              key={a.id}
              className={cn(
                "flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-line last:border-0",
                a.status === "open" && "bg-danger-surface/50",
              )}
            >
              <div className="flex items-center gap-3 min-w-0">
                {a.status === "open" && <span className="w-2 h-2 rounded-full bg-danger shrink-0 animate-pulse" />}
                <div className="min-w-0">
                  <div className="text-sm font-medium text-ink-primary">
                    {a.user?.full_name ?? "Utilisateur inconnu"}{" "}
                    <span className="text-ink-muted font-normal">· {a.role === "driver" ? "chauffeur" : "passager"}</span>
                  </div>
                  <div className="text-xs text-ink-muted truncate">
                    {formatDateTime(a.triggered_at)}
                    {a.trip && ` · ${a.trip.origin_name ?? "?"} → ${a.trip.destination_name ?? "?"}`}
                    {a.trip?.vehicle && ` · ${a.trip.vehicle.plate_number}`}
                    {` · ${a.recordings.length} enregistrement${a.recordings.length > 1 ? "s" : ""}`}
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-2">
                {a.ended_at ? <Badge tone="success">En sécurité</Badge> : <Badge tone="danger">En cours</Badge>}
                <Badge tone={a.status === "open" ? "danger" : a.status === "resolved" ? "success" : "neutral"}>
                  {a.status === "open" ? "Ouverte" : a.status === "resolved" ? "Résolue" : "Prise en charge"}
                </Badge>
                <Button variant="secondary" onClick={() => setViewing(a)}>
                  Voir la fiche
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
      {data && (
        <div className="px-4 pb-3">
          <Pagination page={data.current_page} lastPage={data.last_page} total={data.total} onChange={setPage} />
        </div>
      )}

      <Modal open={!!viewing} onClose={() => setViewing(null)} title="Alerte SOS" size="lg">
        {viewing && (
          <>
            <SosAlertDetail alertId={viewing.id} />
            {canEdit && viewing.status !== "resolved" && (
              <div className="flex justify-end mt-4">
                <Button onClick={() => askStatus(viewing)}>
                  {viewing.status === "open" ? "Prendre en charge" : "Marquer comme résolue"}
                </Button>
              </div>
            )}
          </>
        )}
      </Modal>

      <Modal open={!!target} onClose={() => setTarget(null)} title="Mettre à jour l'alerte SOS">
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="Notes de résolution (optionnel)"
          className="w-full h-20 px-2.5 py-1.5 rounded-sm border border-line text-sm outline-none focus:border-primary mb-3"
        />
        {actionError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2 mb-3">{actionError}</div>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => setTarget(null)} disabled={busy}>
            Annuler
          </Button>
          <Button onClick={confirm} disabled={busy}>
            Confirmer
          </Button>
        </div>
      </Modal>
    </Card>
  );
}

function DisputesSection() {
  const canEdit = useAuthStore((s) => s.hasPermission("disputes", "edit"));
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);
  const [target, setTarget] = useState<Dispute | null>(null);
  const [nextStatus, setNextStatus] = useState<"investigating" | "resolved" | "dismissed">("investigating");
  const [resolution, setResolution] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<Dispute>>(
    "/admin/disputes",
    { query: { status: status || undefined, page } },
    [status, page],
  );

  async function confirm() {
    if (!target) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/admin/disputes/${target.id}`, {
        method: "PATCH",
        body: { status: nextStatus, ...(resolution.trim() ? { resolution: resolution.trim() } : {}) },
      });
      setTarget(null);
      setResolution("");
      reload();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : "Action impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-2 p-4 border-b border-line">
        <h2 className="text-sm font-semibold text-ink-primary flex items-center gap-2">
          <Gavel size={16} /> Litiges
        </h2>
        <Select value={status} onChange={(e) => { setPage(1); setStatus(e.target.value); }}>
          <option value="">Tous les statuts</option>
          <option value="open">Ouvert</option>
          <option value="investigating">En instruction</option>
          <option value="resolved">Résolu</option>
          <option value="dismissed">Classé sans suite</option>
        </Select>
      </div>

      {loading ? (
        <div className="p-4 flex flex-col gap-2">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-14 rounded-sm" />
          ))}
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : !data || data.data.length === 0 ? (
        <EmptyState icon={Gavel} title="Aucun litige" description="Aucun litige ne correspond à ce filtre." />
      ) : (
        <div className="flex flex-col">
          {data.data.map((d) => (
            <div key={d.id} className="flex items-center justify-between gap-3 px-4 py-3 border-b border-line last:border-0">
              <div>
                <div className="text-sm font-medium text-ink-primary">{d.reason}</div>
                <div className="text-xs text-ink-muted">{formatDateTime(d.created_at)}</div>
              </div>
              <div className="flex items-center gap-3">
                <Badge tone={d.status === "open" ? "danger" : d.status === "resolved" ? "success" : "neutral"}>
                  {d.status}
                </Badge>
                {canEdit && (d.status === "open" || d.status === "investigating") && (
                  <Button
                    variant="secondary"
                    onClick={() => {
                      setNextStatus(d.status === "open" ? "investigating" : "resolved");
                      setTarget(d);
                    }}
                  >
                    {d.status === "open" ? "Instruire" : "Résoudre"}
                  </Button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
      {data && (
        <div className="px-4 pb-3">
          <Pagination page={data.current_page} lastPage={data.last_page} total={data.total} onChange={setPage} />
        </div>
      )}

      <Modal open={!!target} onClose={() => setTarget(null)} title="Mettre à jour le litige">
        <textarea
          value={resolution}
          onChange={(e) => setResolution(e.target.value)}
          placeholder="Résolution (optionnel)"
          className="w-full h-20 px-2.5 py-1.5 rounded-sm border border-line text-sm outline-none focus:border-primary mb-3"
        />
        {actionError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2 mb-3">{actionError}</div>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => setTarget(null)} disabled={busy}>
            Annuler
          </Button>
          <Button onClick={confirm} disabled={busy}>
            Confirmer
          </Button>
        </div>
      </Modal>
    </Card>
  );
}

export function Moderation() {
  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Modération & SOS</h1>
        <p className="text-sm text-ink-secondary mt-0.5">Alertes de sécurité et litiges signalés par les utilisateurs.</p>
      </div>
      <SosSection />
      <DisputesSection />
    </div>
  );
}
