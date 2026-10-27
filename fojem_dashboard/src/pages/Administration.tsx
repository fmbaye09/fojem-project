import { useState } from "react";
import { UserPlus, Shield, Settings2, Lock } from "lucide-react";
import { useApi } from "../lib/useApi";
import { apiFetch, ApiError } from "../lib/api";
import type { AdminUser, AdminRole, PlatformSetting } from "../types/api";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Select } from "../components/ui/Select";
import { Skeleton } from "../components/ui/Skeleton";
import { EmptyState } from "../components/ui/EmptyState";
import { ErrorState } from "../components/ui/ErrorState";
import { Modal } from "../components/ui/Modal";
import { formatDate } from "../lib/utils";
import { useAuthStore } from "../store/useAuthStore";

function AdminUsersSection() {
  const isSuperAdmin = useAuthStore((s) => s.isSuperAdmin());
  const roles = useApi<{ data: AdminRole[] }>("/admin/admin-roles");
  const { data, loading, error, reload } = useApi<{ data: AdminUser[] }>("/admin/admin-users");
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ full_name: "", email: "", password: "", role_id: "" });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setFormError(null);
    try {
      await apiFetch("/admin/admin-users", { method: "POST", body: form });
      setOpen(false);
      setForm({ full_name: "", email: "", password: "", role_id: "" });
      reload();
    } catch (err) {
      setFormError(err instanceof ApiError ? err.message : "Création impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 p-4 border-b border-line">
        <h2 className="text-sm font-semibold text-ink-primary flex items-center gap-2">
          <Shield size={16} /> Comptes admin
        </h2>
        {isSuperAdmin ? (
          <Button onClick={() => setOpen(true)}>
            <UserPlus size={14} /> Nouveau compte
          </Button>
        ) : (
          <span className="text-xs text-ink-muted flex items-center gap-1.5">
            <Lock size={12} /> Réservé aux super administrateurs
          </span>
        )}
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
        <EmptyState icon={Shield} title="Aucun compte admin" />
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-xs text-ink-muted">
              <th className="px-4 py-2.5 font-medium">Nom</th>
              <th className="px-4 py-2.5 font-medium">E-mail</th>
              <th className="px-4 py-2.5 font-medium">Rôle</th>
              <th className="px-4 py-2.5 font-medium">Statut</th>
              <th className="px-4 py-2.5 font-medium">Créé le</th>
            </tr>
          </thead>
          <tbody>
            {data.data.map((a) => (
              <tr key={a.id} className="border-b border-line last:border-0 hover:bg-bg/60">
                <td className="px-4 py-2.5 font-medium text-ink-primary">{a.full_name}</td>
                <td className="px-4 py-2.5 text-ink-secondary">{a.email}</td>
                <td className="px-4 py-2.5 text-ink-secondary">{a.role?.name ?? "—"}</td>
                <td className="px-4 py-2.5">
                  <Badge tone={a.is_active ? "success" : "danger"}>{a.is_active ? "actif" : "inactif"}</Badge>
                </td>
                <td className="px-4 py-2.5 text-ink-secondary">{formatDate(a.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title="Nouveau compte admin">
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-ink-primary">Nom complet</label>
            <Input value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-ink-primary">E-mail</label>
            <Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-ink-primary">Mot de passe</label>
            <Input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-ink-primary">Rôle</label>
            <Select value={form.role_id} onChange={(e) => setForm({ ...form, role_id: e.target.value })}>
              <option value="">Sélectionner un rôle</option>
              {roles.data?.data.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </Select>
          </div>
          {formError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2">{formError}</div>}
          <div className="flex justify-end gap-2 mt-1">
            <Button variant="secondary" onClick={() => setOpen(false)} disabled={busy}>
              Annuler
            </Button>
            <Button onClick={submit} disabled={busy || !form.full_name || !form.email || !form.password || !form.role_id}>
              Créer
            </Button>
          </div>
        </div>
      </Modal>
    </Card>
  );
}

function RolesSection() {
  const { data, loading, error } = useApi<{ data: AdminRole[] }>("/admin/admin-roles");

  return (
    <Card className="overflow-hidden">
      <div className="p-4 border-b border-line">
        <h2 className="text-sm font-semibold text-ink-primary flex items-center gap-2">
          <Shield size={16} /> Rôles & permissions
        </h2>
        <p className="text-xs text-ink-secondary mt-0.5">Lecture seule — la gestion des rôles se fait côté backend.</p>
      </div>
      {loading ? (
        <div className="p-4 flex flex-col gap-2">
          <Skeleton className="h-24 rounded-sm" />
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : !data || data.data.length === 0 ? (
        <EmptyState icon={Shield} title="Aucun rôle" />
      ) : (
        <div className="divide-y divide-line">
          {data.data.map((r) => (
            <div key={r.id} className="p-4">
              <div className="text-sm font-medium text-ink-primary mb-1.5">{r.name}</div>
              <div className="flex flex-wrap gap-1.5">
                {r.permissions.map((p) => (
                  <Badge key={p.id} tone="neutral">
                    {p.resource}.{p.action}
                  </Badge>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

function PlatformSettingsSection() {
  const canEdit = useAuthStore((s) => s.hasPermission("platform_settings", "edit"));
  const { data, loading, error, reload } = useApi<{ data: PlatformSetting[] }>("/admin/platform-settings");
  const [editing, setEditing] = useState<PlatformSetting | null>(null);
  const [form, setForm] = useState({ price_per_km: "", commission_pct: "" });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  function startEdit(s: PlatformSetting) {
    setEditing(s);
    setForm({ price_per_km: s.price_per_km, commission_pct: s.commission_pct });
  }

  async function submit() {
    if (!editing) return;
    setBusy(true);
    setFormError(null);
    try {
      await apiFetch(`/admin/platform-settings/${editing.id}`, { method: "PATCH", body: form });
      setEditing(null);
      reload();
    } catch (err) {
      setFormError(err instanceof ApiError ? err.message : "Mise à jour impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="overflow-hidden">
      <div className="p-4 border-b border-line">
        <h2 className="text-sm font-semibold text-ink-primary flex items-center gap-2">
          <Settings2 size={16} /> Paramètres tarifaires
        </h2>
        <p className="text-xs text-ink-secondary mt-0.5">Tarif par kilomètre et commission plateforme, par zone.</p>
      </div>
      {loading ? (
        <div className="p-4">
          <Skeleton className="h-16 rounded-sm" />
        </div>
      ) : error ? (
        <ErrorState message={error} />
      ) : !data || data.data.length === 0 ? (
        <EmptyState icon={Settings2} title="Aucune zone tarifaire configurée" description="Aucun paramètre n'a encore été créé côté backend." />
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-xs text-ink-muted">
              <th className="px-4 py-2.5 font-medium">Zone</th>
              <th className="px-4 py-2.5 font-medium">Prix / km</th>
              <th className="px-4 py-2.5 font-medium">Commission</th>
              {canEdit && <th className="px-4 py-2.5 font-medium text-right">Action</th>}
            </tr>
          </thead>
          <tbody>
            {data.data.map((s) => (
              <tr key={s.id} className="border-b border-line last:border-0">
                <td className="px-4 py-2.5 font-medium text-ink-primary">{s.zone_name}</td>
                <td className="px-4 py-2.5 text-ink-secondary tabular-nums">{s.price_per_km} FCFA</td>
                <td className="px-4 py-2.5 text-ink-secondary tabular-nums">{s.commission_pct}%</td>
                {canEdit && (
                  <td className="px-4 py-2.5 text-right">
                    <Button variant="secondary" onClick={() => startEdit(s)}>
                      Modifier
                    </Button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <Modal open={!!editing} onClose={() => setEditing(null)} title={`Zone : ${editing?.zone_name ?? ""}`}>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-ink-primary">Prix par km (FCFA)</label>
            <Input
              type="number"
              value={form.price_per_km}
              onChange={(e) => setForm({ ...form, price_per_km: e.target.value })}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-ink-primary">Commission (%)</label>
            <Input
              type="number"
              value={form.commission_pct}
              onChange={(e) => setForm({ ...form, commission_pct: e.target.value })}
            />
          </div>
          {formError && <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2">{formError}</div>}
          <div className="flex justify-end gap-2 mt-1">
            <Button variant="secondary" onClick={() => setEditing(null)} disabled={busy}>
              Annuler
            </Button>
            <Button onClick={submit} disabled={busy}>
              Enregistrer
            </Button>
          </div>
        </div>
      </Modal>
    </Card>
  );
}

export function Administration() {
  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-ink-primary">Administration</h1>
        <p className="text-sm text-ink-secondary mt-0.5">Comptes admin, rôles et paramètres tarifaires de la plateforme.</p>
      </div>
      <AdminUsersSection />
      <RolesSection />
      <PlatformSettingsSection />
    </div>
  );
}
