import { useEffect } from "react";
import { Routes, Route, Navigate, Outlet, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { AppLayout } from "./components/layout/AppLayout";
import { RequirePermission } from "./components/layout/RequirePermission";
import { Login } from "./pages/Login";
import { Overview } from "./pages/Overview";
import { MapView } from "./pages/MapView";
import { UsersPage } from "./pages/UsersPage";
import { Finance } from "./pages/Finance";
import { Moderation } from "./pages/Moderation";
import { Stats } from "./pages/Stats";
import { Administration } from "./pages/Administration";
import { useAuthStore } from "./store/useAuthStore";

function FullScreenLoader() {
  return (
    <div className="min-h-screen bg-bg flex items-center justify-center">
      <Loader2 size={22} className="animate-spin text-primary" />
    </div>
  );
}

function ProtectedRoute() {
  const status = useAuthStore((s) => s.status);
  const location = useLocation();
  if (status === "idle") return <FullScreenLoader />;
  if (status === "unauthenticated") return <Navigate to="/login" replace state={{ from: location }} />;
  return <Outlet />;
}

function PublicOnlyRoute() {
  const status = useAuthStore((s) => s.status);
  if (status === "idle") return <FullScreenLoader />;
  if (status === "authenticated") return <Navigate to="/" replace />;
  return <Outlet />;
}

export default function App() {
  const restoreSession = useAuthStore((s) => s.restoreSession);

  useEffect(() => {
    restoreSession();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Routes>
      <Route element={<PublicOnlyRoute />}>
        <Route path="/login" element={<Login />} />
      </Route>
      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route path="/" element={<Overview />} />
          <Route path="/map" element={<MapView />} />
          <Route element={<RequirePermission resource="users" />}>
            <Route path="/users" element={<UsersPage />} />
          </Route>
          <Route element={<RequirePermission resource="transactions" />}>
            <Route path="/finance" element={<Finance />} />
          </Route>
          <Route element={<RequirePermission resource="sos_alerts" />}>
            <Route path="/moderation" element={<Moderation />} />
          </Route>
          <Route path="/stats" element={<Stats />} />
          <Route element={<RequirePermission resource="admin_users" />}>
            <Route path="/administration" element={<Administration />} />
          </Route>
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
