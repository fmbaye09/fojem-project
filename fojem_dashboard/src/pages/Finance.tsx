import { useState } from "react";
import { Wallet, Receipt } from "lucide-react";
import { useApi } from "../lib/useApi";
import { apiFetch, ApiError } from "../lib/api";
import type { Paginated, Transaction, PayoutRequest } from "../types/api";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { Select } from "../components/ui/Select";
import { Skeleton } from "../components/ui/Skeleton";
import { EmptyState } from "../components/ui/EmptyState";
import { ErrorState } from "../components/ui/ErrorState";
import { Pagination } from "../components/ui/Pagination";
import { Modal } from "../components/ui/Modal";
import { formatDateTime, formatXof } from "../lib/utils";
import { useAuthStore } from "../store/useAuthStore";

const TX_STATUS_TONE = { completed: "success", pending: "neutral", failed: "danger" } as const;

function TransactionsSection() {
  const [type, setType] = useState("");
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);

  const { data, loading, error } = useApi<Paginated<Transaction>>(
    "/admin/transactions",
    { query: { type: type || undefined, status: status || undefined, page } },
    [type, status, page],
  );

  return (
    <Card className="overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-2 p-4 border-b border-line">
        <h2 className="text-sm font-semibold text-ink-primary">Transactions</h2>
        <div className="flex gap-2">
          <Select value={type} onChange={(e) => { setPage(1); setType(e.target.value); }}>
            <option value="">Tous les types</option>
            <option value="ride_payment">Paiement trajet</option>
            <option value="payout">Retrait</option>
            <option value="refund">Remboursement</option>
          </Select>
          <Select value={status} onChange={(e) => { setPage(1); setStatus(e.target.value); }}>
            <option value="">Tous les statuts</option>
            <option value="completed">Complétée</option>
            <option value="pending">En attente</option>
            <option value="failed">Échouée</option>
          </Select>
        </div>
      </div>

      {loading ? (
        <div className="p-4 flex flex-col gap-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-11 rounded-sm" />
          ))}
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : !data || data.data.length === 0 ? (
        <EmptyState icon={Receipt} title="Aucune transaction" description="Aucune transaction ne correspond à ces filtres." />
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-xs text-ink-muted">
              <th className="px-4 py-2.5 font-medium">Utilisateur</th>
              <th className="px-4 py-2.5 font-medium">Type</th>
              <th className="px-4 py-2.5 font-medium">Montant</th>
              <th className="px-4 py-2.5 font-medium">Statut</th>
              <th className="px-4 py-2.5 font-medium">Date</th>
            </tr>
          </thead>
          <tbody>
            {data.data.map((t) => (
              <tr key={t.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                <td className="px-4 py-2.5 text-ink-primary font-medium">{t.user?.full_name ?? "—"}</td>
                <td className="px-4 py-2.5 text-ink-secondary">{t.type}</td>
                <td className="px-4 py-2.5 text-ink-primary tabular-nums">{formatXof(t.amount)}</td>
                <td className="px-4 py-2.5">
                  <Badge tone={TX_STATUS_TONE[t.status as keyof typeof TX_STATUS_TONE] ?? "neutral"}>{t.status}</Badge>
                </td>
                <td className="px-4 py-2.5 text-ink-secondary">{formatDateTime(t.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {data && (
        <div className="px-4 pb-3">
          <Pagination page={data.current_page} lastPage={data.last_page} total={data.total} onChange={setPage} />
        </div>
      )}
    </Card>
  );
}

function PayoutRequestsSection() {
  const canEdit = useAuthStore((s) => s.hasPermission("payout_requests", "edit"));
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);
  const [target, setTarget] = useState<PayoutRequest | null>(null);
  const [decision, setDecision] = useState<"processed" | "rejected">("processed");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<PayoutRequest>>(
    "/admin/payout-requests",
    { query: { status: status || undefined, page } },
    [status, page],
  );

  async function confirm() {
    if (!target) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/admin/payout-requests/${target.id}/process`, {
        method: "PATCH",
        body: { status: decision },
      });
      setTarget(null);
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
        <h2 className="text-sm font-semibold text-ink-primary">Demandes de retrait</h2>
        <Select value={status} onChange={(e) => { setPage(1); setStatus(e.target.value); }}>
          <option value="">Tous les statuts</option>
          <option value="pending">En attente</option>
          <option value="processed">Traitée</option>
          <option value="rejected">Rejetée</option>
        </Select>
      </div>

      {loading ? (
        <div className="p-4 flex flex-col gap-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-11 rounded-sm" />
          ))}
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : !data || data.data.length === 0 ? (
        <EmptyState icon={Wallet} title="Aucune demande de retrait" />
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-xs text-ink-muted">
              <th className="px-4 py-2.5 font-medium">Chauffeur</th>
              <th className="px-4 py-2.5 font-medium">Montant</th>
              <th className="px-4 py-2.5 font-medium">Statut</th>
              <th className="px-4 py-2.5 font-medium">Demandée le</th>
              {canEdit && <th className="px-4 py-2.5 font-medium text-right">Action</th>}
            </tr>
          </thead>
          <tbody>
            {data.data.map((p) => (
              <tr key={p.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                <td className="px-4 py-2.5 text-ink-primary font-medium">{p.driver?.user?.full_name ?? "—"}</td>
                <td className="px-4 py-2.5 text-ink-primary tabular-nums">{formatXof(p.amount)}</td>
                <td className="px-4 py-2.5">
                  <Badge tone={p.status === "processed" ? "success" : p.status === "rejected" ? "danger" : "neutral"}>
                    {p.status}
                  </Badge>
                </td>
                <td className="px-4 py-2.5 text-ink-secondary">{formatDateTime(p.created_at)}</td>
                {canEdit && (
                  <td className="px-4 py-2.5 text-right">
                    {p.status === "pending" && (
                      <div className="flex justify-end gap-2">
                        <Button
                          variant="secondary"
                          onClick={() => {
                            setDecision("processed");
                            setTarget(p);
                          }}
                        >
                          Traiter
                        </Button>
                        <Button
                          variant="danger"
                          onClick={() => {
                            setDecision("rejected");
                            setTarget(p);
                          }}
                        >
                          Rejeter
                        </Button>
                      </div>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {data && (
        <div className="px-4 pb-3">
          <Pagination page={data.current_page} lastPage={data.last_page} total={data.total} onChange={setPage} />
        </div>
      )}

      <Modal
        open={!!target}
        onClose={() => setTarget(null)}
        title={decision === "processed" ? "Traiter ce retrait ?" : "Rejeter ce retrait ?"}
      >
        <p className="text-sm text-ink-secondary mb-4">
          {decision === "processed" ? (
            <>
              Débite le wallet du chauffeur de <strong className="text-ink-primary">{target ? formatXof(target.amount) : ""}</strong> et
              journalise la transaction. Refusé automatiquement si le solde est insuffisant.
            </>
          ) : (
            <>Le chauffeur sera notifié que sa demande de retrait a été rejetée.</>
          )}
        </p>
        {actionError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2 mb-3">{actionError}</div>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => setTarget(null)} disabled={busy}>
            Annuler
          </Button>
          <Button variant={decision === "rejected" ? "danger" : "primary"} onClick={confirm} disabled={busy}>
            Confirmer
          </Button>
        </div>
      </Modal>
    </Card>
  );
}

export function Finance() {
  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Finance</h1>
        <p className="text-sm text-ink-secondary mt-0.5">Grand livre des transactions et demandes de retrait chauffeur.</p>
      </div>
      <TransactionsSection />
      <PayoutRequestsSection />
    </div>
  );
}
