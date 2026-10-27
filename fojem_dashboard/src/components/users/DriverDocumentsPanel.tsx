import { useState } from "react";
import { Check, ImageOff, X } from "lucide-react";
import { useApi } from "../../lib/useApi";
import { apiFetch, ApiError } from "../../lib/api";
import type {
  Driver,
  DriverDocument,
  DriverDocumentsResponse,
  DriverDocumentType,
  ReviewDriverDocumentResponse,
  VerificationStatus,
} from "../../types/api";
import { Badge } from "../ui/Badge";
import { Button } from "../ui/Button";
import { Skeleton } from "../ui/Skeleton";
import { ErrorState } from "../ui/ErrorState";
import { useAuthStore } from "../../store/useAuthStore";
import { formatDate } from "../../lib/utils";
import { DocumentPreview } from "./DocumentPreview";
import {
  DOCUMENT_TYPE_LABEL,
  DOCUMENT_TYPES_ORDERED,
  VERIFICATION_LABEL,
  VERIFICATION_TONE,
  latestDocumentByType,
} from "./statusLabels";

/** Longueur max acceptée par le backend (ReviewDriverDocumentRequest). */
const REJECTION_REASON_MAX = 255;

/**
 * Le statut de vérification du chauffeur (approved/pending/rejected) est
 * entièrement RECALCULÉ côté backend après chaque revue de document (voir
 * DriverVerificationService::recompute()). Ce panneau ne propose donc aucun
 * bouton "forcer approuvé" : seules les actions approuver/rejeter par
 * document existent. Le statut affiché en tête est celui renvoyé par la
 * dernière revue, pour rester juste sans attendre le rechargement de la liste.
 */
export function DriverDocumentsPanel({
  driver,
  onReviewed,
}: {
  driver: Driver;
  /** Appelé après chaque revue réussie avec le chauffeur recalculé par le backend. */
  onReviewed: (updated: Driver) => void;
}) {
  const canEdit = useAuthStore((s) => s.hasPermission("driver_documents", "edit"));
  const { data, loading, error, reload } = useApi<DriverDocumentsResponse>(`/admin/drivers/${driver.id}/documents`);
  const [verificationStatus, setVerificationStatus] = useState<VerificationStatus>(driver.verification_status);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [rejectId, setRejectId] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  async function review(docId: string, status: "approved" | "rejected", rejection_reason?: string) {
    setBusyId(docId);
    setActionError(null);
    try {
      const res = await apiFetch<ReviewDriverDocumentResponse>(`/admin/drivers/${driver.id}/documents/${docId}/review`, {
        method: "PATCH",
        body: { status, ...(rejection_reason ? { rejection_reason } : {}) },
      });
      setRejectId(null);
      setReason("");
      if (res?.driver) setVerificationStatus(res.driver.verification_status);
      reload();
      onReviewed({ ...driver, ...(res?.driver ?? {}), user: driver.user });
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : "Action impossible.");
    } finally {
      setBusyId(null);
    }
  }

  const byType = data ? latestDocumentByType(data.documents) : {};
  const provided = DOCUMENT_TYPES_ORDERED.filter((t) => byType[t]).length;
  const approved = DOCUMENT_TYPES_ORDERED.filter((t) => byType[t]?.status === "approved").length;
  const toReview = DOCUMENT_TYPES_ORDERED.filter((t) => byType[t]?.status === "pending").length;
  const total = DOCUMENT_TYPES_ORDERED.length;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between">
          <span className="text-sm text-ink-secondary">Statut de vérification</span>
          <Badge tone={VERIFICATION_TONE[verificationStatus]}>{VERIFICATION_LABEL[verificationStatus]}</Badge>
        </div>
        <p className="text-xs text-ink-muted">
          Recalculé automatiquement : le compte chauffeur n'est activé que lorsque les {total} pièces ci-dessous sont
          approuvées.
        </p>
        {data && (
          <p className="text-xs text-ink-secondary">
            <strong className="text-ink-primary">{approved}</strong> / {total} approuvées ·{" "}
            <strong className="text-ink-primary">{toReview}</strong> à examiner ·{" "}
            <strong className="text-ink-primary">{total - provided}</strong> non fournies
          </p>
        )}
      </div>

      {loading && !data ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-64 rounded-sm" />
          ))}
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {DOCUMENT_TYPES_ORDERED.map((type) => (
            <DocumentCard
              key={type}
              type={type}
              doc={byType[type]}
              canEdit={canEdit}
              busy={busyId !== null && busyId === byType[type]?.id}
              rejecting={rejectId !== null && rejectId === byType[type]?.id}
              reason={reason}
              onReasonChange={setReason}
              onApprove={(id) => review(id, "approved")}
              onStartReject={(id) => {
                setReason("");
                setRejectId(id);
              }}
              onCancelReject={() => setRejectId(null)}
              onConfirmReject={(id) => review(id, "rejected", reason.trim())}
            />
          ))}
        </div>
      )}

      {actionError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2">{actionError}</div>}
    </div>
  );
}

function DocumentCard({
  type,
  doc,
  canEdit,
  busy,
  rejecting,
  reason,
  onReasonChange,
  onApprove,
  onStartReject,
  onCancelReject,
  onConfirmReject,
}: {
  type: DriverDocumentType;
  doc: DriverDocument | undefined;
  canEdit: boolean;
  busy: boolean;
  rejecting: boolean;
  reason: string;
  onReasonChange: (value: string) => void;
  onApprove: (docId: string) => void;
  onStartReject: (docId: string) => void;
  onCancelReject: () => void;
  onConfirmReject: (docId: string) => void;
}) {
  const label = DOCUMENT_TYPE_LABEL[type];

  return (
    <div className="border border-line rounded-sm p-3 flex flex-col gap-2">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-sm font-medium text-ink-primary">{label}</div>
          {doc && <div className="text-xs text-ink-muted">Envoyé le {formatDate(doc.created_at)}</div>}
        </div>
        {doc ? (
          <Badge tone={VERIFICATION_TONE[doc.status]}>{VERIFICATION_LABEL[doc.status]}</Badge>
        ) : (
          <Badge tone="neutral">Non fourni</Badge>
        )}
      </div>

      {doc ? (
        <DocumentPreview fileEndpoint={doc.file_endpoint} alt={label} />
      ) : (
        <div className="h-44 w-full rounded-sm border border-dashed border-line-strong flex flex-col items-center justify-center gap-1 text-center px-3">
          <ImageOff size={24} strokeWidth={1.5} className="text-ink-muted" />
          <span className="text-sm font-medium text-ink-secondary">Non fourni</span>
          <span className="text-xs text-ink-muted">Le chauffeur n'a pas encore envoyé cette pièce.</span>
        </div>
      )}

      {doc?.status === "rejected" && doc.rejection_reason && (
        <div className="text-xs text-danger bg-danger-surface rounded-sm px-2 py-1.5">Motif : {doc.rejection_reason}</div>
      )}

      {doc && canEdit && doc.status === "pending" && !rejecting && (
        <div className="flex gap-2">
          <Button variant="secondary" disabled={busy} onClick={() => onApprove(doc.id)}>
            <Check size={14} /> Approuver
          </Button>
          <Button variant="secondary" disabled={busy} onClick={() => onStartReject(doc.id)}>
            <X size={14} /> Rejeter
          </Button>
        </div>
      )}

      {doc && rejecting && (
        <div className="flex flex-col gap-2">
          <textarea
            value={reason}
            onChange={(e) => onReasonChange(e.target.value)}
            maxLength={REJECTION_REASON_MAX}
            autoFocus
            placeholder="Motif du rejet (visible par le chauffeur)"
            className="w-full h-16 px-2.5 py-1.5 rounded-sm border border-line text-sm outline-none focus:border-primary"
          />
          <div className="flex gap-2">
            <Button variant="danger" disabled={busy || !reason.trim()} onClick={() => onConfirmReject(doc.id)}>
              Confirmer le rejet
            </Button>
            <Button variant="ghost" disabled={busy} onClick={onCancelReject}>
              Annuler
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
