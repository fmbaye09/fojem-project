import { Navigate, Outlet } from "react-router-dom";
import { useAuthStore } from "../../store/useAuthStore";

/**
 * Garde RBAC côté frontend : redirige vers l'accueil si l'admin connecté n'a
 * pas la permission "view" sur la ressource donnée. Le backend refuse déjà
 * ces requêtes (admin.permission middleware), mais on ne compte pas
 * uniquement sur un 403 silencieux — on masque/bloque aussi côté écran.
 */
export function RequirePermission({ resource }: { resource: string }) {
  // Sélectionne le résultat (booléen), pas la méthode `hasPermission` elle
  // même : sa référence ne change jamais, donc sélectionner la fonction
  // empêchait ce composant de se re-rendre quand les permissions arrivaient
  // après coup (ex. juste après le login) et pouvait rediriger vers "/" à
  // tort pendant cette fenêtre.
  const hasAccess = useAuthStore((s) => s.hasPermission(resource, "view"));
  if (!hasAccess) {
    return <Navigate to="/" replace />;
  }
  return <Outlet />;
}
