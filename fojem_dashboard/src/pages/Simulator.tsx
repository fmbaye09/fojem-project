import { useState } from "react";
import { FlaskConical, Loader2, RotateCcw, Trash2 } from "lucide-react";
import { Card } from "../components/ui/Card";
import { Button } from "../components/ui/Button";
import { Badge } from "../components/ui/Badge";
import { apiFetch } from "../lib/api";
import { useApi } from "../lib/useApi";
import { errorMessage } from "../simulator/api";
import { ScenarioRunner } from "../simulator/components/ScenarioRunner";
import { ScenarioSetup } from "../simulator/components/ScenarioSetup";
import { useSimStore } from "../simulator/store";
import type { SimulatorStatus } from "../simulator/types";

/**
 * Simulateur : des scénarios joués sur le backend local, avec un chauffeur
 * et des passagers simulés qui passent par l'API des applis. Règles,
 * heures de passage et notifications sont les vraies ; de vrais téléphones
 * peuvent rejoindre le scénario.
 */
export function Simulator() {
  const status = useApi<SimulatorStatus>("/admin/simulator", { pollInterval: false });
  const scenario = useSimStore((s) => s.scenario);
  const [resetting, setResetting] = useState(false);

  const leave = () => {
    if (window.confirm("Quitter ce scénario ? Ses comptes et son trajet restent en base jusqu'à « Tout effacer ».")) {
      useSimStore.getState().setScenario(null);
    }
  };

  const reset = async () => {
    if (!window.confirm("Supprimer tous les comptes simulés, avec leurs trajets, réservations et notifications ?")) return;
    setResetting(true);
    try {
      const res = await apiFetch<{ users: number; trips: number }>("/admin/simulator", { method: "DELETE" });
      const store = useSimStore.getState();
      store.clear();
      store.addLog("ok", `Simulateur réinitialisé : ${res.users} comptes et ${res.trips} trajets supprimés.`);
      status.reload();
    } catch (err) {
      window.alert(errorMessage(err));
    } finally {
      setResetting(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-ink-primary flex items-center gap-2">
            <FlaskConical size={20} className="text-primary" /> Simulateur
            <Badge tone="primary">backend local</Badge>
          </h1>
          <p className="text-sm text-ink-secondary mt-0.5 max-w-3xl">
            {scenario
              ? scenario.label
              : "Jouez un trajet avec un chauffeur et des passagers simulés. Ils passent par l'API des applis : règles, heures de passage et notifications sont les vraies."}
          </p>
        </div>
        <div className="flex gap-2">
          {scenario && (
            <Button variant="secondary" onClick={leave}>
              <RotateCcw size={15} /> Nouveau scénario
            </Button>
          )}
          {status.data && (
            <Button variant="secondary" onClick={reset} disabled={resetting}>
              {resetting ? <Loader2 size={15} className="animate-spin" /> : <Trash2 size={15} />}
              Tout effacer
            </Button>
          )}
        </div>
      </div>

      {status.loading && !status.data ? (
        <Card className="p-6 text-sm text-ink-muted">Connexion au simulateur…</Card>
      ) : status.error ? (
        <Card className="p-6 flex flex-col gap-2 text-sm">
          <div className="font-semibold text-ink-primary">Simulateur indisponible</div>
          <p className="text-ink-secondary">
            Il ne fonctionne qu'avec le backend local : ajoutez <code className="px-1 bg-bg rounded">SIMULATOR_ENABLED=true</code>{" "}
            dans <code className="px-1 bg-bg rounded">fojem_backend/.env</code> (avec <code className="px-1 bg-bg rounded">APP_ENV=local</code>),
            puis <code className="px-1 bg-bg rounded">php artisan config:clear</code>. Il faut aussi la permission « simulator ».
          </p>
          <p className="text-ink-muted">Réponse du serveur : {status.error}</p>
        </Card>
      ) : (
        <>
          <Card className="px-4 py-3 text-xs text-ink-secondary flex flex-wrap gap-x-6 gap-y-1">
            <span>
              <b className="text-ink-primary">Horloge réelle :</b> le serveur compte les vraies minutes (rappels, 5 min
              d'attente avant une absence).
            </span>
            <span>
              <b className="text-ink-primary">Vrais téléphones :</b> le trajet simulé apparaît dans la recherche de l'appli
              passager.
            </span>
            <span>
              <b className="text-ink-primary">Gardez cet onglet ouvert :</b> c'est lui qui fait rouler le chauffeur.
            </span>
            {status.data && !status.data.osrm && <span className="text-danger">OSRM désactivé : routes en lignes droites.</span>}
          </Card>
          {scenario ? <ScenarioRunner key={scenario.tripId} scenario={scenario} /> : <ScenarioSetup />}
        </>
      )}
    </div>
  );
}
