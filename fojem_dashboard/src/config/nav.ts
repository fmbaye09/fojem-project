import {
  LayoutDashboard,
  Map,
  Route,
  Users,
  Wallet,
  ShieldAlert,
  BarChart3,
  Settings,
  FlaskConical,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  end?: boolean;
  /** Ressource RBAC à posséder (action "view") pour voir cet item. undefined = toujours visible. */
  resource?: string;
  /** Outil de développement : absent du dashboard de production. */
  devOnly?: boolean;
}

export const NAV_ITEMS: NavItem[] = [
  { to: "/", label: "Vue d'ensemble", icon: LayoutDashboard, end: true },
  { to: "/map", label: "Cartographie", icon: Map },
  { to: "/trips", label: "Trajets", icon: Route, resource: "trips" },
  { to: "/users", label: "Utilisateurs", icon: Users, resource: "users" },
  { to: "/finance", label: "Finance", icon: Wallet, resource: "transactions" },
  { to: "/moderation", label: "Modération & SOS", icon: ShieldAlert, resource: "sos_alerts" },
  { to: "/stats", label: "Statistiques", icon: BarChart3 },
  { to: "/administration", label: "Administration", icon: Settings, resource: "admin_users" },
  { to: "/simulator", label: "Simulateur", icon: FlaskConical, resource: "simulator", devOnly: true },
];

/** Le simulateur ne sert qu'avec le backend local (npm run dev), sauf VITE_ENABLE_SIMULATOR=true. */
export const SIMULATOR_UI = import.meta.env.DEV || import.meta.env.VITE_ENABLE_SIMULATOR === "true";
