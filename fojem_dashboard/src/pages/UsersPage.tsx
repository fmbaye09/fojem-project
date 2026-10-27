import { useState } from "react";
import { Search, UserCheck, UserX, Car, ClipboardCheck, RotateCw } from "lucide-react";
import { useApi } from "../lib/useApi";
import { apiFetch, ApiError } from "../lib/api";
import type { Paginated, PlatformUser, Driver } from "../types/api";
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
import { formatDate } from "../lib/utils";
import { useAuthStore } from "../store/useAuthStore";
import { DriverDocumentsPanel } from "../components/users/DriverDocumentsPanel";
import { PassengerIdentityPanel } from "../components/users/PassengerIdentityPanel";
import { usePendingDriversQueue } from "../components/users/usePendingDriversQueue";
import {
  ACCOUNT_STATUS_LABEL,
  ACCOUNT_STATUS_TONE,
  DOCUMENT_TYPES_ORDERED,
  VERIFICATION_LABEL,
  VERIFICATION_TONE,
  IDENTITY_STATUS_LABEL,
  IDENTITY_STATUS_TONE,
  IDENTITY_DOC_TYPE_LABEL,
} from "../components/users/statusLabels";

function UsersTab() {
  const canEdit = useAuthStore((s) => s.hasPermission("users", "edit"));
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [identityStatus, setIdentityStatus] = useState("");
  const [page, setPage] = useState(1);
  const [confirmTarget, setConfirmTarget] = useState<PlatformUser | null>(null);
  const [nextStatus, setNextStatus] = useState<"active" | "disabled">("disabled");
  const [selectedForIdentity, setSelectedForIdentity] = useState<PlatformUser | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<PlatformUser>>(
    "/admin/users",
    {
      query: {
        search: search || undefined,
        account_status: status || undefined,
        identity_status: identityStatus || undefined,
        page,
      },
    },
    [search, status, identityStatus, page],
  );

  async function confirmStatusChange() {
    if (!confirmTarget) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/admin/users/${confirmTarget.id}/status`, {
        method: "PATCH",
        body: { account_status: nextStatus },
      });
      setConfirmTarget(null);
      reload();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : "Action impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-2">
        <div className="relative">
          <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-muted" />
          <Input
            placeholder="Nom, e-mail, téléphone…"
            value={search}
            onChange={(e) => {
              setPage(1);
              setSearch(e.target.value);
            }}
            className="pl-8 w-64"
          />
        </div>
        <Select
          value={status}
          onChange={(e) => {
            setPage(1);
            setStatus(e.target.value);
          }}
        >
          <option value="">Tous les statuts</option>
          <option value="active">Actif</option>
          <option value="disabled">Désactivé</option>
          <option value="deleted">Supprimé</option>
        </Select>
        <Select
          value={identityStatus}
          onChange={(e) => {
            setPage(1);
            setIdentityStatus(e.target.value);
          }}
        >
          <option value="">Toutes les pièces d'identité</option>
          <option value="pending">Identité en attente</option>
          <option value="approved">Identité validée</option>
          <option value="rejected">Identité rejetée</option>
          <option value="none">Sans pièce d'identité</option>
        </Select>
      </div>

      <Card className="overflow-hidden">
        {loading ? (
          <div className="p-4 flex flex-col gap-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-11 rounded-sm" />
            ))}
          </div>
        ) : error ? (
          <ErrorState message={error} />
        ) : !data || data.data.length === 0 ? (
          <EmptyState icon={Search} title="Aucun utilisateur trouvé" description="Essayez d'élargir votre recherche ou vos filtres." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left text-xs text-ink-muted">
                <th className="px-4 py-2.5 font-medium">Nom</th>
                <th className="px-4 py-2.5 font-medium">Contact</th>
                <th className="px-4 py-2.5 font-medium">Statut</th>
                <th className="px-4 py-2.5 font-medium">Chauffeur</th>
                <th className="px-4 py-2.5 font-medium">Identité</th>
                <th className="px-4 py-2.5 font-medium">Inscrit le</th>
                {canEdit && <th className="px-4 py-2.5 font-medium text-right">Action</th>}
              </tr>
            </thead>
            <tbody>
              {data.data.map((u) => (
                <tr key={u.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                  <td className="px-4 py-2.5 font-medium text-ink-primary">{u.full_name}</td>
                  <td className="px-4 py-2.5 text-ink-secondary">
                    <div>{u.email}</div>
                    <div className="text-xs text-ink-muted">{u.phone_number}</div>
                  </td>
                  <td className="px-4 py-2.5">
                    <Badge tone={ACCOUNT_STATUS_TONE[u.account_status]}>{ACCOUNT_STATUS_LABEL[u.account_status]}</Badge>
                  </td>
                  <td className="px-4 py-2.5 text-ink-secondary">{u.is_driver ? "Oui" : "Non"}</td>
                  <td className="px-4 py-2.5">
                    {u.identity_status && u.identity_status !== "none" ? (
                      <div className="flex items-center gap-1.5">
                        <Badge tone={IDENTITY_STATUS_TONE[u.identity_status]}>
                          {IDENTITY_STATUS_LABEL[u.identity_status]}
                        </Badge>
                        <button
                          type="button"
                          onClick={() => setSelectedForIdentity(u)}
                          className="text-xs text-primary hover:underline font-medium"
                        >
                          {u.identity_status === "pending" ? "Examiner" : "Voir"}
                        </button>
                      </div>
                    ) : (
                      <span className="text-xs text-ink-muted">Non fournie</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-ink-secondary">{formatDate(u.created_at)}</td>
                  {canEdit && (
                    <td className="px-4 py-2.5 text-right">
                      {u.account_status === "active" ? (
                        <Button
                          variant="secondary"
                          onClick={() => {
                            setNextStatus("disabled");
                            setConfirmTarget(u);
                          }}
                        >
                          <UserX size={14} /> Désactiver
                        </Button>
                      ) : u.account_status === "disabled" ? (
                        <Button
                          variant="secondary"
                          onClick={() => {
                            setNextStatus("active");
                            setConfirmTarget(u);
                          }}
                        >
                          <UserCheck size={14} /> Réactiver
                        </Button>
                      ) : null}
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
      </Card>

      <Modal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title={nextStatus === "disabled" ? "Désactiver ce compte ?" : "Réactiver ce compte ?"}
      >
        <p className="text-sm text-ink-secondary mb-4">
          {nextStatus === "disabled" ? (
            <>
              <strong className="text-ink-primary">{confirmTarget?.full_name}</strong> ne pourra plus se connecter
              tant que son compte reste désactivé.
            </>
          ) : (
            <>
              <strong className="text-ink-primary">{confirmTarget?.full_name}</strong> retrouvera l'accès à son
              compte.
            </>
          )}
        </p>
        {actionError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2 mb-3">{actionError}</div>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => setConfirmTarget(null)} disabled={busy}>
            Annuler
          </Button>
          <Button variant={nextStatus === "disabled" ? "danger" : "primary"} onClick={confirmStatusChange} disabled={busy}>
            Confirmer
          </Button>
        </div>
      </Modal>

      <Modal
        open={!!selectedForIdentity}
        onClose={() => setSelectedForIdentity(null)}
        title={`Vérification d'identité · ${selectedForIdentity?.full_name ?? ""}`}
        size="lg"
      >
        {selectedForIdentity && (
          <PassengerIdentityPanel
            user={selectedForIdentity}
            onReviewed={(updated) => {
              reload();
              setSelectedForIdentity(updated);
            }}
          />
        )}
      </Modal>
    </div>
  );
}

function DriversTab({ onDriverReviewed }: { onDriverReviewed: (driver: Driver) => void }) {
  const [verification, setVerification] = useState("");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Driver | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<Driver>>(
    "/admin/drivers",
    { query: { verification_status: verification || undefined, page } },
    [verification, page],
  );

  return (
    <div className="flex flex-col gap-4">
      <div className="flex gap-2">
        <Select
          value={verification}
          onChange={(e) => {
            setPage(1);
            setVerification(e.target.value);
          }}
        >
          <option value="">Tous les statuts de vérification</option>
          <option value="pending">En attente</option>
          <option value="approved">Approuvé</option>
          <option value="rejected">Rejeté</option>
        </Select>
      </div>

      <Card className="overflow-hidden">
        {loading ? (
          <div className="p-4 flex flex-col gap-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-11 rounded-sm" />
            ))}
          </div>
        ) : error ? (
          <ErrorState message={error} />
        ) : !data || data.data.length === 0 ? (
          <EmptyState icon={Car} title="Aucun chauffeur trouvé" description="Aucun chauffeur ne correspond à ce filtre." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left text-xs text-ink-muted">
                <th className="px-4 py-2.5 font-medium">Chauffeur</th>
                <th className="px-4 py-2.5 font-medium">Compte</th>
                <th className="px-4 py-2.5 font-medium">Vérification</th>
                <th className="px-4 py-2.5 font-medium">Note moyenne</th>
                <th className="px-4 py-2.5 font-medium">Trajets réalisés</th>
                <th className="px-4 py-2.5 font-medium text-right">Documents</th>
              </tr>
            </thead>
            <tbody>
              {data.data.map((d) => (
                <tr key={d.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                  <td className="px-4 py-2.5 font-medium text-ink-primary">{d.user?.full_name ?? "—"}</td>
                  <td className="px-4 py-2.5">
                    {d.user ? (
                      <Badge tone={ACCOUNT_STATUS_TONE[d.user.account_status]}>
                        {ACCOUNT_STATUS_LABEL[d.user.account_status]}
                      </Badge>
                    ) : (
                      <span className="text-ink-muted">—</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5">
                    <Badge tone={VERIFICATION_TONE[d.verification_status]}>{VERIFICATION_LABEL[d.verification_status]}</Badge>
                  </td>
                  <td className="px-4 py-2.5 text-ink-secondary">{d.average_rating ? `${d.average_rating} / 5` : "—"}</td>
                  <td className="px-4 py-2.5 text-ink-secondary">{d.total_trips_completed}</td>
                  <td className="px-4 py-2.5 text-right">
                    <Button variant="secondary" onClick={() => setSelected(d)}>
                      Voir les documents
                    </Button>
                  </td>
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

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title={selected?.user?.full_name ?? "Documents"}
        size="lg"
      >
        {selected && (
          <DriverDocumentsPanel
            driver={selected}
            onReviewed={(updated) => {
              reload();
              onDriverReviewed(updated);
            }}
          />
        )}
      </Modal>
    </div>
  );
}

type PendingQueue = ReturnType<typeof usePendingDriversQueue>;

/**
 * File de travail "À valider" : chauffeurs en attente ayant envoyé au moins
 * une pièce, le plus ancien en premier — l'endroit unique où l'admin
 * active les comptes chauffeurs.
 */
function PendingActivationTab({ queue }: { queue: PendingQueue }) {
  const [selected, setSelected] = useState<Driver | null>(null);
  const { entries, loading, error, truncated, reload, refreshDriver } = queue;
  const total = DOCUMENT_TYPES_ORDERED.length;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-ink-secondary">
          Chauffeurs en attente de validation ayant envoyé au moins une pièce, du plus ancien au plus récent. Le compte
          est activé automatiquement dès que les {total} pièces sont approuvées.
        </p>
        <Button variant="secondary" onClick={reload} disabled={loading}>
          <RotateCw size={14} /> Actualiser
        </Button>
      </div>

      {truncated && (
        <div className="text-sm text-ink-secondary bg-primary-surface rounded-sm px-3 py-2">
          File très longue : seuls les 500 chauffeurs en attente les plus récents ont été analysés.
        </div>
      )}

      <Card className="overflow-hidden">
        {!entries && !error ? (
          <div className="p-4 flex flex-col gap-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-11 rounded-sm" />
            ))}
          </div>
        ) : error ? (
          <ErrorState message={error} />
        ) : !entries || entries.length === 0 ? (
          <EmptyState
            icon={ClipboardCheck}
            title="Aucun compte à valider"
            description="Tous les chauffeurs ayant envoyé des documents ont été traités."
          />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left text-xs text-ink-muted">
                <th className="px-4 py-2.5 font-medium">Chauffeur</th>
                <th className="px-4 py-2.5 font-medium">En attente depuis</th>
                <th className="px-4 py-2.5 font-medium">Pièces fournies</th>
                <th className="px-4 py-2.5 font-medium">À examiner</th>
                <th className="px-4 py-2.5 font-medium text-right">Action</th>
              </tr>
            </thead>
            <tbody>
              {entries.map((e) => (
                <tr key={e.driver.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                  <td className="px-4 py-2.5">
                    <div className="font-medium text-ink-primary">{e.driver.user?.full_name ?? "—"}</div>
                    <div className="text-xs text-ink-muted">{e.driver.user?.phone_number}</div>
                  </td>
                  <td className="px-4 py-2.5 text-ink-secondary">{formatDate(e.waitingSince)}</td>
                  <td className="px-4 py-2.5 text-ink-secondary">
                    {e.provided} / {total}
                    {e.approved > 0 && <span className="text-xs text-ink-muted"> · {e.approved} approuvée(s)</span>}
                    {e.rejected > 0 && <span className="text-xs text-danger"> · {e.rejected} rejetée(s)</span>}
                  </td>
                  <td className="px-4 py-2.5">
                    {e.toReview > 0 ? (
                      <Badge tone="primary">{e.toReview} à examiner</Badge>
                    ) : (
                      <span className="text-xs text-ink-muted">En attente du chauffeur</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <Button variant={e.toReview > 0 ? "primary" : "secondary"} onClick={() => setSelected(e.driver)}>
                      Examiner
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title={selected?.user?.full_name ?? "Documents"}
        size="lg"
      >
        {selected && <DriverDocumentsPanel driver={selected} onReviewed={(updated) => void refreshDriver(updated)} />}
      </Modal>
    </div>
  );
}

function IdentitiesQueueTab({ onIdentityReviewed }: { onIdentityReviewed?: () => void }) {
  const [identityStatus, setIdentityStatus] = useState<string>("pending");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<PlatformUser | null>(null);

  const { data, loading, error, reload } = useApi<Paginated<PlatformUser>>(
    "/admin/users",
    {
      query: {
        identity_status: identityStatus || undefined,
        search: search || undefined,
        page,
      },
    },
    [identityStatus, search, page],
  );

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap gap-2">
          <div className="relative">
            <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-muted" />
            <Input
              placeholder="Nom, téléphone, email…"
              value={search}
              onChange={(e) => {
                setPage(1);
                setSearch(e.target.value);
              }}
              className="pl-8 w-64"
            />
          </div>
          <Select
            value={identityStatus}
            onChange={(e) => {
              setPage(1);
              setIdentityStatus(e.target.value);
            }}
          >
            <option value="pending">En attente de vérification</option>
            <option value="approved">Identités approuvées</option>
            <option value="rejected">Identités rejetées</option>
            <option value="">Tous les dossiers</option>
          </Select>
        </div>
        <Button variant="secondary" onClick={reload} disabled={loading}>
          <RotateCw size={14} /> Actualiser
        </Button>
      </div>

      <Card className="overflow-hidden">
        {loading ? (
          <div className="p-4 flex flex-col gap-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-11 rounded-sm" />
            ))}
          </div>
        ) : error ? (
          <ErrorState message={error} />
        ) : !data || data.data.length === 0 ? (
          <EmptyState
            icon={ClipboardCheck}
            title="Aucun dossier d'identité à traiter"
            description="Aucun voyageur ou chauffeur ne correspond aux critères sélectionnés."
          />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left text-xs text-ink-muted">
                <th className="px-4 py-2.5 font-medium">Utilisateur</th>
                <th className="px-4 py-2.5 font-medium">Type de pièce</th>
                <th className="px-4 py-2.5 font-medium">N° Document</th>
                <th className="px-4 py-2.5 font-medium">Statut</th>
                <th className="px-4 py-2.5 font-medium">Date de soumission</th>
                <th className="px-4 py-2.5 font-medium text-right">Action</th>
              </tr>
            </thead>
            <tbody>
              {data.data.map((u) => (
                <tr key={u.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                  <td className="px-4 py-2.5">
                    <div className="font-medium text-ink-primary flex items-center gap-2">
                      <span>{u.full_name}</span>
                      <Badge tone={u.is_driver ? "primary" : "neutral"} className="text-[11px] py-0 px-1.5">
                        {u.is_driver ? "Chauffeur" : "Passager"}
                      </Badge>
                    </div>
                    <div className="text-xs text-ink-muted">
                      {u.phone_number} · {u.email}
                    </div>
                  </td>
                  <td className="px-4 py-2.5">
                    <span className="font-medium text-ink-primary">
                      {u.identity_document_type ? IDENTITY_DOC_TYPE_LABEL[u.identity_document_type] : "—"}
                    </span>
                  </td>
                  <td className="px-4 py-2.5 text-ink-secondary">
                    {u.identity_document_number || <span className="text-ink-muted">—</span>}
                  </td>
                  <td className="px-4 py-2.5">
                    <Badge tone={IDENTITY_STATUS_TONE[u.identity_status ?? "none"]}>
                      {IDENTITY_STATUS_LABEL[u.identity_status ?? "none"]}
                    </Badge>
                  </td>
                  <td className="px-4 py-2.5 text-ink-secondary">
                    {u.identity_submitted_at ? formatDate(u.identity_submitted_at) : formatDate(u.created_at)}
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <Button
                      variant={u.identity_status === "pending" ? "primary" : "secondary"}
                      onClick={() => setSelected(u)}
                    >
                      {u.identity_status === "pending" ? "Examiner" : "Voir détails"}
                    </Button>
                  </td>
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

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title={`Dossier d'identité · ${selected?.full_name ?? ""}`}
        size="lg"
      >
        {selected && (
          <PassengerIdentityPanel
            user={selected}
            onReviewed={(updated) => {
              reload();
              setSelected(updated);
              onIdentityReviewed?.();
            }}
          />
        )}
      </Modal>
    </div>
  );
}

type Tab = "users" | "identities" | "pending" | "drivers";

export function UsersPage() {
  const [tab, setTab] = useState<Tab>("users");
  // La file de validation lit les documents : réservée aux admins qui en ont le droit.
  const canViewDocuments = useAuthStore((s) => s.hasPermission("driver_documents", "view"));
  // Chargée au niveau de la page pour que le compteur de l'onglet soit visible d'emblée.
  const queue = usePendingDriversQueue(canViewDocuments);
  const pendingCount = queue.entries?.length ?? null;

  // Compteur des identités en attente (auto-actualisé)
  const pendingIdentities = useApi<Paginated<PlatformUser>>("/admin/users", {
    query: { identity_status: "pending", per_page: 1 },
  });
  const pendingIdentitiesCount = pendingIdentities.data?.total ?? 0;

  const tabs: { id: Tab; label: string; badge?: number | null }[] = [
    { id: "users", label: "Tous les utilisateurs" },
    { id: "identities", label: "Identités voyageurs", badge: pendingIdentitiesCount },
    ...(canViewDocuments ? [{ id: "pending" as const, label: "Dossiers véhicules chauffeurs", badge: pendingCount }] : []),
    { id: "drivers", label: "Chauffeurs" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Utilisateurs & Vérifications</h1>
        <p className="text-sm text-ink-secondary mt-0.5">
          Comptes utilisateurs, validation des pièces d'identité voyageurs (CNI / Permis) et dossiers chauffeurs.
        </p>
      </div>

      <div className="flex gap-1 border-b border-line">
        {tabs.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`inline-flex items-center gap-2 px-3 h-9 text-sm font-medium border-b-2 -mb-px transition-colors ${
              tab === t.id ? "border-primary text-primary" : "border-transparent text-ink-secondary hover:text-ink-primary"
            }`}
          >
            {t.label}
            {t.badge !== undefined && t.badge !== null && t.badge > 0 && (
              <span className="min-w-5 h-5 px-1.5 rounded-full bg-primary text-white text-xs font-semibold inline-flex items-center justify-center">
                {t.badge}
              </span>
            )}
          </button>
        ))}
      </div>

      {tab === "users" ? (
        <UsersTab />
      ) : tab === "identities" ? (
        <IdentitiesQueueTab onIdentityReviewed={() => pendingIdentities.reload()} />
      ) : tab === "pending" ? (
        <PendingActivationTab queue={queue} />
      ) : (
        <DriversTab onDriverReviewed={(d) => void queue.refreshDriver(d)} />
      )}
    </div>
  );
}
