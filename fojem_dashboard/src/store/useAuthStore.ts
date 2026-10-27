import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { AdminMeResponse, AdminPermission, AdminUser, LoginResponse } from "../types/api";

export type AuthStatus = "idle" | "authenticated" | "unauthenticated";

interface AuthState {
  status: AuthStatus;
  token: string | null;
  admin: AdminUser | null;
  permissions: AdminPermission[];
  error: string | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  /** Appelé par le client API sur une réponse 401 : coupe la session côté client. */
  handleUnauthorized: () => void;
  /** Vérifie que le token stocké est toujours valide au chargement de l'app. */
  restoreSession: () => Promise<void>;
  clearError: () => void;
  hasPermission: (resource: string, action: "view" | "edit" | "delete") => boolean;
  isSuperAdmin: () => boolean;
}

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? "http://127.0.0.1:8000";

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      status: "idle",
      token: null,
      admin: null,
      permissions: [],
      error: null,

      login: async (email, password) => {
        set({ error: null });
        const res = await fetch(`${API_BASE_URL}/api/admin/auth/login`, {
          method: "POST",
          headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify({ email, password }),
        });
        const payload = await res.json().catch(() => undefined);
        if (!res.ok) {
          const message =
            payload?.message ??
            (res.status === 422 ? "Identifiants invalides." : "Connexion impossible pour le moment.");
          set({ error: message });
          throw new Error(message);
        }
        const data = payload as LoginResponse;
        set({ status: "authenticated", token: data.token, admin: data.admin, error: null });
        // Récupère les permissions effectives du rôle (nécessaires au RBAC frontend).
        try {
          const meRes = await fetch(`${API_BASE_URL}/api/admin/auth/me`, {
            headers: { Accept: "application/json", Authorization: `Bearer ${data.token}` },
          });
          if (meRes.ok) {
            const me = (await meRes.json()) as AdminMeResponse;
            set({ permissions: me.permissions, admin: me.admin });
          }
        } catch {
          // les permissions resteront vides ; le RBAC frontend masquera tout
          // par prudence plutôt que de risquer un accès non autorisé.
        }
      },

      logout: () => {
        const token = get().token;
        if (token) {
          fetch(`${API_BASE_URL}/api/admin/auth/logout`, {
            method: "POST",
            headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
          }).catch(() => {});
        }
        set({ status: "unauthenticated", token: null, admin: null, permissions: [] });
      },

      handleUnauthorized: () => {
        set({ status: "unauthenticated", token: null, admin: null, permissions: [] });
      },

      restoreSession: async () => {
        const token = get().token;
        if (!token) {
          set({ status: "unauthenticated" });
          return;
        }
        try {
          const res = await fetch(`${API_BASE_URL}/api/admin/auth/me`, {
            headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
          });
          if (!res.ok) throw new Error("invalid session");
          const me = (await res.json()) as AdminMeResponse;
          set({ status: "authenticated", admin: me.admin, permissions: me.permissions });
        } catch {
          set({ status: "unauthenticated", token: null, admin: null, permissions: [] });
        }
      },

      clearError: () => set({ error: null }),

      hasPermission: (resource, action) => {
        const perms = get().permissions;
        return perms.some((p) => (p.resource === resource || p.resource === "*") && p.action === action);
      },

      isSuperAdmin: () => get().admin?.role?.name === "super_admin",
    }),
    {
      name: "fojem-admin-auth",
      partialize: (s) => ({ token: s.token }),
    },
  ),
);
