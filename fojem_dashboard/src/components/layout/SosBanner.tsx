import { useEffect } from "react";
import { Link } from "react-router-dom";
import { Siren } from "lucide-react";
import { useAuthStore } from "../../store/useAuthStore";
import { useSosWatch } from "../../store/useSosWatch";

/**
 * Bannière rouge sur toutes les pages tant qu'une alerte SOS est ouverte.
 * Démarre aussi la surveillance (son à chaque nouvelle alerte).
 */
export function SosBanner() {
  const canView = useAuthStore((s) => s.hasPermission("sos_alerts", "view"));
  const start = useSosWatch((s) => s.start);
  const openCount = useSosWatch((s) => s.openCount);
  const latest = useSosWatch((s) => s.latest);

  useEffect(() => (canView ? start() : undefined), [canView, start]);

  if (!canView || openCount === 0) return null;
  const first = latest[0];

  return (
    <Link
      to="/moderation"
      className="flex items-center gap-3 bg-danger text-white px-6 py-2.5 text-sm font-medium animate-pulse hover:animate-none"
    >
      <Siren size={18} className="shrink-0" />
      <span className="flex-1 truncate">
        {openCount === 1 ? "1 alerte SOS ouverte" : `${openCount} alertes SOS ouvertes`}
        {first?.user && ` — ${first.user.full_name} (${first.role === "driver" ? "chauffeur" : "passager"})`}
      </span>
      <span className="underline shrink-0">Voir</span>
    </Link>
  );
}
