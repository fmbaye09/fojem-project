import { useState } from "react";
import { Check, X, ShieldCheck, ShieldAlert, Clock, ExternalLink, ZoomIn } from "lucide-react";
import { apiFetch, ApiError } from "../../lib/api";
import type { PlatformUser, IdentityStatus } from "../../types/api";
import { Badge } from "../ui/Badge";
import { Button } from "../ui/Button";
import { useAuthStore } from "../../store/useAuthStore";
import { formatDate } from "../../lib/utils";

interface PassengerIdentityPanelProps {
  user: PlatformUser;
  onReviewed: (updated: PlatformUser) => void;
}

const REJECTION_REASONS = [
  "Photo floue ou illisible, veuillez renvoyer un document net.",
  "Document incomplet ou bords coupés.",
  "Document expiré ou non reconnu.",
  "Les informations du document ne correspondent pas au compte.",
  "Document d'identité non conforme (fournir CNI biométrique, passeport ou permis).",
];

export function PassengerIdentityPanel({ user, onReviewed }: PassengerIdentityPanelProps) {
  const canEdit = useAuthStore((s) => s.hasPermission("users", "edit"));
  const [currentUser, setCurrentUser] = useState<PlatformUser>(user);
  const [busy, setBusy] = useState(false);
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [zoomUrl, setZoomUrl] = useState<string | null>(null);

  const status: IdentityStatus = currentUser.identity_status ?? "none";
  const docType = currentUser.identity_document_type;
  const docNumber = currentUser.identity_document_number;
  const frontUrl = currentUser.identity_front_url;
  const backUrl = currentUser.identity_back_url;

  async function review(newStatus: "approved" | "rejected", rejectionReason?: string) {
    setBusy(true);
    setActionError(null);
    try {
      const res = await apiFetch<{ message: string; user: PlatformUser }>(
        `/admin/users/${currentUser.id}/identity-review`,
        {
          method: "PATCH",
          body: {
            status: newStatus,
            ...(rejectionReason ? { rejection_reason: rejectionReason } : {}),
          },
        },
      );
      setRejecting(false);
      setReason("");
      const updated = res.user ?? {
        ...currentUser,
        identity_status: newStatus,
        identity_rejection_reason: newStatus === "rejected" ? rejectionReason : null,
        identity_verified: newStatus === "approved",
      };
      setCurrentUser(updated);
      onReviewed(updated);
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : "Action impossible.");
    } finally {
      setBusy(false);
    }
  }

  const statusTone =
    status === "approved"
      ? "success"
      : status === "pending"
      ? "primary"
      : status === "rejected"
      ? "danger"
      : "neutral";

  const statusLabel =
    status === "approved"
      ? "Identité validée"
      : status === "pending"
      ? "En attente de vérification"
      : status === "rejected"
      ? "Demande rejetée"
      : "Non soumis";

  return (
    <div className="flex flex-col gap-6">
      {/* En-tête voyageur & état */}
      <div className="flex flex-wrap items-center justify-between gap-3 p-4 bg-bg rounded-lg border border-line">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-full bg-primary-surface flex items-center justify-center font-bold text-primary text-base">
            {currentUser.full_name.slice(0, 2).toUpperCase()}
          </div>
          <div>
            <div className="font-semibold text-ink-primary flex items-center gap-2">
              <span>{currentUser.full_name}</span>
              <Badge tone={currentUser.is_driver ? "primary" : "neutral"}>
                {currentUser.is_driver ? "Chauffeur" : "Voyageur"}
              </Badge>
            </div>
            <div className="text-xs text-ink-secondary mt-0.5">
              {currentUser.phone_number} · {currentUser.email}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Badge tone={statusTone} className="text-xs px-2.5 py-1">
            {status === "approved" && <ShieldCheck size={13} className="mr-1 inline" />}
            {status === "pending" && <Clock size={13} className="mr-1 inline" />}
            {status === "rejected" && <ShieldAlert size={13} className="mr-1 inline" />}
            {statusLabel}
          </Badge>
        </div>
      </div>

      {/* Détails du document choisi */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="p-3.5 bg-bg/50 rounded-md border border-line">
          <div className="text-xs text-ink-muted">Type de document choisi</div>
          <div className="text-sm font-semibold text-ink-primary mt-1 flex items-center gap-2">
            {docType === "driver_license" ? (
              <>
                <span className="w-2 h-2 rounded-full bg-primary" />
                Permis de conduire sénégalais
              </>
            ) : docType === "id_card" ? (
              <>
                <span className="w-2 h-2 rounded-full bg-success" />
                Pièce d'identité (CNI / Passeport)
              </>
            ) : (
              <span className="text-ink-muted font-normal">Non spécifié</span>
            )}
          </div>
        </div>

        <div className="p-3.5 bg-bg/50 rounded-md border border-line">
          <div className="text-xs text-ink-muted">Numéro du document</div>
          <div className="text-sm font-semibold text-ink-primary mt-1">
            {docNumber ? docNumber : <span className="text-ink-muted font-normal">Non renseigné</span>}
          </div>
        </div>
      </div>

      {currentUser.identity_submitted_at && (
        <div className="text-xs text-ink-muted">
          Dossier soumis le {formatDate(currentUser.identity_submitted_at)}
        </div>
      )}

      {status === "rejected" && currentUser.identity_rejection_reason && (
        <div className="p-3 bg-danger-surface rounded-md border border-danger/30 text-sm text-danger flex flex-col gap-1">
          <div className="font-semibold flex items-center gap-1.5">
            <ShieldAlert size={14} /> Motif du refus communiqué à l'utilisateur :
          </div>
          <div>{currentUser.identity_rejection_reason}</div>
        </div>
      )}

      {/* Photos Recto et Verso */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Photo Recto */}
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-ink-primary">
              Face avant (Recto) <span className="text-danger">*</span>
            </span>
            {frontUrl && (
              <a
                href={frontUrl}
                target="_blank"
                rel="noreferrer"
                className="text-xs text-primary hover:underline inline-flex items-center gap-1"
              >
                Plein écran <ExternalLink size={11} />
              </a>
            )}
          </div>

          <div className="relative aspect-[4/3] rounded-lg border border-line bg-surface overflow-hidden flex items-center justify-center group">
            {frontUrl ? (
              <>
                <img
                  src={frontUrl}
                  alt="Recto pièce d'identité"
                  className="w-full h-full object-contain cursor-pointer transition-transform group-hover:scale-[1.02]"
                  onClick={() => setZoomUrl(frontUrl)}
                />
                <button
                  type="button"
                  onClick={() => setZoomUrl(frontUrl)}
                  className="absolute bottom-2 right-2 p-1.5 rounded-full bg-black/60 text-white hover:bg-black/80 transition-colors"
                  title="Agrandir"
                >
                  <ZoomIn size={14} />
                </button>
              </>
            ) : (
              <div className="text-xs text-ink-muted">Aucune photo recto disponible</div>
            )}
          </div>
        </div>

        {/* Photo Verso */}
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-ink-primary">Face arrière (Verso)</span>
            {backUrl && (
              <a
                href={backUrl}
                target="_blank"
                rel="noreferrer"
                className="text-xs text-primary hover:underline inline-flex items-center gap-1"
              >
                Plein écran <ExternalLink size={11} />
              </a>
            )}
          </div>

          <div className="relative aspect-[4/3] rounded-lg border border-line bg-surface overflow-hidden flex items-center justify-center group">
            {backUrl ? (
              <>
                <img
                  src={backUrl}
                  alt="Verso pièce d'identité"
                  className="w-full h-full object-contain cursor-pointer transition-transform group-hover:scale-[1.02]"
                  onClick={() => setZoomUrl(backUrl)}
                />
                <button
                  type="button"
                  onClick={() => setZoomUrl(backUrl)}
                  className="absolute bottom-2 right-2 p-1.5 rounded-full bg-black/60 text-white hover:bg-black/80 transition-colors"
                  title="Agrandir"
                >
                  <ZoomIn size={14} />
                </button>
              </>
            ) : (
              <div className="text-xs text-ink-muted">Verso non fourni (optionnel)</div>
            )}
          </div>
        </div>
      </div>

      {actionError && (
        <div className="text-sm text-danger bg-danger-surface rounded-md px-3 py-2 border border-danger/20">
          {actionError}
        </div>
      )}

      {/* Formulaire de Rejet */}
      {rejecting && (
        <div className="p-4 bg-danger-surface/40 rounded-lg border border-danger/30 flex flex-col gap-3">
          <div className="text-sm font-semibold text-danger">Motif du rejet du document</div>
          <p className="text-xs text-ink-secondary">
            Choisissez un motif prédéfini ou saisissez une explication claire. Le voyageur recevra cette notification.
          </p>

          <div className="flex flex-wrap gap-1.5">
            {REJECTION_REASONS.map((r) => (
              <button
                key={r}
                type="button"
                onClick={() => setReason(r)}
                className={`text-xs px-2.5 py-1 rounded border text-left transition-colors ${
                  reason === r
                    ? "bg-danger text-white border-danger"
                    : "bg-surface text-ink-secondary border-line hover:border-danger/50"
                }`}
              >
                {r}
              </button>
            ))}
          </div>

          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Précisez le motif du refus..."
            rows={3}
            className="w-full text-xs p-2.5 rounded border border-line bg-surface text-ink-primary focus:outline-none focus:border-danger"
          />

          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setRejecting(false)} disabled={busy}>
              Annuler
            </Button>
            <Button
              variant="danger"
              disabled={busy || !reason.trim()}
              onClick={() => review("rejected", reason.trim())}
            >
              <X size={14} /> Confirmer le rejet
            </Button>
          </div>
        </div>
      )}

      {/* Actions Admin */}
      {canEdit && !rejecting && (
        <div className="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-line">
          <div className="text-xs text-ink-muted">
            {status === "approved"
              ? "Cette identité est actuellement validée."
              : "Vérifiez que le document est lisible et correspond au profil."}
          </div>

          <div className="flex gap-2">
            {status !== "rejected" && (
              <Button variant="danger" onClick={() => setRejecting(true)} disabled={busy}>
                <X size={14} /> Rejeter
              </Button>
            )}
            {status !== "approved" && (
              <Button variant="primary" onClick={() => review("approved")} disabled={busy}>
                <Check size={14} /> Valider l'identité
              </Button>
            )}
          </div>
        </div>
      )}

      {/* Modal Zoom Image */}
      {zoomUrl && (
        <div
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4 backdrop-blur-sm cursor-pointer"
          onClick={() => setZoomUrl(null)}
        >
          <div className="relative max-w-4xl max-h-[90vh]" onClick={(e) => e.stopPropagation()}>
            <img src={zoomUrl} alt="Document grand format" className="max-w-full max-h-[85vh] object-contain rounded-lg" />
            <button
              type="button"
              onClick={() => setZoomUrl(null)}
              className="absolute -top-3 -right-3 p-2 bg-surface text-ink-primary rounded-full shadow-lg hover:bg-bg transition-colors"
            >
              <X size={16} />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
