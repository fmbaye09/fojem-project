import { useState } from "react";
import { LogOut, ChevronDown } from "lucide-react";
import { useAuthStore } from "../../store/useAuthStore";

const ROLE_LABELS: Record<string, string> = {
  super_admin: "Super administrateur",
  support: "Support",
  finance: "Finance",
};

export function Topbar() {
  const admin = useAuthStore((s) => s.admin);
  const logout = useAuthStore((s) => s.logout);
  const [open, setOpen] = useState(false);

  if (!admin) return null;
  const roleName = admin.role?.name ?? "";

  return (
    <header className="h-16 border-b border-line bg-surface flex items-center justify-between px-6 shrink-0">
      <div className="flex items-center gap-2 text-xs">
        <span className="relative flex h-2 w-2">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75"></span>
          <span className="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
        </span>
        <span className="font-medium text-ink-secondary">En direct</span>
        <span className="text-ink-muted hidden sm:inline">· Actualisation auto active (15s)</span>
      </div>
      <div className="relative">
        <button
          onClick={() => setOpen((v) => !v)}
          className="flex items-center gap-2.5 h-9 pl-2 pr-2.5 rounded-sm hover:bg-bg transition-colors"
        >
          <div className="w-7 h-7 rounded-full bg-primary-surface text-primary flex items-center justify-center text-xs font-semibold">
            {admin.full_name.slice(0, 1).toUpperCase()}
          </div>
          <div className="text-left leading-tight">
            <div className="text-sm font-medium text-ink-primary">{admin.full_name}</div>
            <div className="text-[11px] text-ink-muted">{ROLE_LABELS[roleName] ?? roleName}</div>
          </div>
          <ChevronDown size={14} className="text-ink-muted" />
        </button>
        {open && (
          <div className="absolute right-0 mt-1 w-44 bg-surface border border-line rounded-sm shadow-card py-1 z-30">
            <button
              onClick={logout}
              className="w-full flex items-center gap-2 px-3 h-9 text-sm text-danger hover:bg-danger-surface transition-colors"
            >
              <LogOut size={15} />
              Se déconnecter
            </button>
          </div>
        )}
      </div>
    </header>
  );
}
