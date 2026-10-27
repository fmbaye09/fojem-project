import {
  LayoutDashboard,
  Map,
  Route,
  Users,
  Wallet,
  ShieldAlert,
  BarChart3,
  Settings,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  end?: boolean;
  /** Ressource RBAC à posséder (action "view") pour voir cet item. undefined = toujours visible. */
  resource?: string;
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
];
