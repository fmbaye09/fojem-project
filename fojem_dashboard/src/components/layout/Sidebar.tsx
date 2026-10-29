import { NavLink } from "react-router-dom";
import { motion } from "framer-motion";
import { cn } from "../../lib/utils";
import { useAuthStore } from "../../store/useAuthStore";
import { NAV_ITEMS } from "../../config/nav";
import { useSosWatch } from "../../store/useSosWatch";

export function Sidebar() {
  // Sélectionne `permissions` (pas la méthode `hasPermission`, dont la
  // référence ne change jamais) pour que ce composant se re-rende bien
  // quand les permissions arrivent après coup (ex. juste après le login),
  // sans quoi les rubriques restreintes restaient invisibles jusqu'au
  // prochain rechargement complet de la page.
  const permissions = useAuthStore((s) => s.permissions);
  const sosOpen = useSosWatch((s) => s.openCount);
  const items = NAV_ITEMS.filter(
    (item) =>
      !item.resource ||
      permissions.some((p) => (p.resource === item.resource || p.resource === "*") && p.action === "view"),
  );

  return (
    <aside className="h-screen sticky top-0 shrink-0 w-60 bg-surface border-r border-line flex flex-col z-20">
      <div className="h-16 flex items-center px-5 shrink-0 gap-2 border-b border-line">
        <div className="w-7 h-7 rounded-sm bg-primary flex items-center justify-center text-white text-sm font-semibold">
          F
        </div>
        <span className="font-semibold text-ink-primary tracking-tight">FOJËM Admin</span>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4 flex flex-col gap-0.5">
        {items.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              cn(
                "group relative flex items-center gap-3 h-10 rounded-sm px-3 text-sm transition-colors duration-150",
                isActive
                  ? "bg-primary-surface text-primary font-medium"
                  : "text-ink-secondary hover:bg-bg hover:text-ink-primary",
              )
            }
          >
            {({ isActive }) => (
              <>
                {isActive && (
                  <motion.span
                    layoutId="active-nav-bar"
                    className="absolute left-0 top-1.5 bottom-1.5 w-[3px] rounded-full bg-primary"
                    transition={{ duration: 0.18 }}
                  />
                )}
                <item.icon size={18} strokeWidth={2} className="shrink-0" />
                <span className="truncate">{item.label}</span>
                {item.to === "/moderation" && sosOpen > 0 && (
                  <span className="ml-auto min-w-5 h-5 px-1.5 rounded-full bg-danger text-white text-xs font-semibold flex items-center justify-center">
                    {sosOpen}
                  </span>
                )}
              </>
            )}
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
