import { Pause, Play, Radio, RotateCcw, SkipForward, Square, StepForward, Navigation } from "lucide-react";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Badge } from "../../components/ui/Badge";
import { Select } from "../../components/ui/Select";
import { TRIP_STATUS_LABEL, TRIP_STATUS_TONE } from "../../components/trips/tripLabels";
import { actorFetch } from "../api";
import { run } from "../actions";
import type { StopMark } from "../engine";
import { formatKm, type Path } from "../geo";
import { useSimStore, type Scenario } from "../store";
import { ago, clock, countdown, useNow } from "../time";
import type { SimTrip } from "../types";

const MULTIPLIERS = [1, 2, 5, 10, 30];
const DWELLS = [0, 15, 30, 60, 120, 300, 600];

/** S'arrêter juste avant un arrêt : on voit le chauffeur y entrer. */
const APPROACH_M = 600;

interface Props {
  scenario: Scenario;
  trip: SimTrip | null;
  path: Path;
  marks: StopMark[];
  sendNow: () => Promise<boolean>;
  jumpTo: (distance: number) => Promise<boolean>;
}

export function DriverPanel({ scenario, trip, path, marks, sendNow, jumpTo }: Props) {
  const engine = useSimStore((s) => s.engine);
  const setEngine = useSimStore((s) => s.setEngine);
  const lastFixAt = useSimStore((s) => s.lastFixAt);
  const dwellUntil = useSimStore((s) => s.dwellUntil);
  const now = useNow(1000);

  if (!scenario.driver) return <RealDriverCard trip={trip} now={now} />;
  const driver = scenario.driver;
  const status = trip?.status;
  const next = marks.find((m) => m.distance > engine.distance + 1);
  const atEnd = engine.distance >= path.length - 1;
  const departure = trip?.scheduled_at ? new Date(trip.scheduled_at).getTime() : null;

  const tripAction = (label: string, endpoint: string, success: string) =>
    run(label, () => actorFetch(driver.token, endpoint, { method: "POST" }), success);

  return (
    <Card className="p-4 flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-xs text-ink-muted">Chauffeur simulé</div>
          <div className="font-semibold text-ink-primary truncate">{driver.full_name}</div>
        </div>
        {status && <Badge tone={TRIP_STATUS_TONE[status]}>{TRIP_STATUS_LABEL[status]}</Badge>}
      </div>

      {trip && (
        <div className="text-sm text-ink-secondary">
          Départ prévu à <span className="font-medium text-ink-primary">{clock(trip.scheduled_at)}</span>
          {departure !== null && status !== "in_progress" && status !== "completed" && (
            <> · {departure > now ? `dans ${countdown(departure - now)}` : `il y a ${countdown(now - departure)}`}</>
          )}
          {" · "}
          {trip.seats_available} place{trip.seats_available > 1 ? "s" : ""} libre{trip.seats_available > 1 ? "s" : ""}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {(status === "open" || status === "full") && (
          <>
            <Button onClick={() => tripAction("Démarrer le trajet", `/trips/${scenario.tripId}/start`, "Trajet démarré.")}>
              <Play size={15} /> Démarrer le trajet
            </Button>
            <Button
              variant="secondary"
              onClick={() => tripAction("Annuler le trajet", `/trips/${scenario.tripId}/cancel`, "Trajet annulé.")}
            >
              Annuler
            </Button>
          </>
        )}
        {status === "in_progress" && (
          <Button onClick={() => tripAction("Terminer le trajet", `/trips/${scenario.tripId}/complete`, "Trajet terminé.")}>
            <Square size={14} /> Terminer le trajet
          </Button>
        )}
      </div>

      {trip && (
        <label className="flex items-center gap-2 text-sm text-ink-primary">
          <input
            type="checkbox"
            checked={trip.accepts_en_route}
            onChange={(e) =>
              run(
                e.target.checked ? "Accepter les passagers en route" : "Refuser les passagers en route",
                () =>
                  actorFetch(driver.token, `/trips/${scenario.tripId}/en-route`, {
                    method: "PATCH",
                    body: { accepts_en_route: e.target.checked },
                  }),
              )
            }
          />
          Accepte des passagers en route
        </label>
      )}

      <div className="border-t border-line pt-3 flex flex-col gap-3">
        <div className="text-xs font-semibold uppercase tracking-wide text-ink-muted">Conduite</div>
        <div className="flex flex-wrap gap-2">
          {engine.playing ? (
            <Button variant="secondary" onClick={() => setEngine({ playing: false })}>
              <Pause size={15} /> Pause
            </Button>
          ) : (
            <Button disabled={atEnd} onClick={() => setEngine({ playing: true })}>
              <Navigation size={15} /> Rouler
            </Button>
          )}
          <Button
            variant="secondary"
            disabled={!next}
            title="Place le chauffeur à 600 m du prochain arrêt"
            onClick={() => next && jumpTo(Math.max(engine.distance, next.distance - APPROACH_M))}
          >
            <StepForward size={15} /> Approcher
          </Button>
          <Button
            variant="secondary"
            disabled={!next}
            title="Place le chauffeur au prochain arrêt"
            onClick={() => next && jumpTo(next.distance)}
          >
            <SkipForward size={15} /> Prochain arrêt
          </Button>
          <Button variant="ghost" title="Ramène le chauffeur au départ" onClick={() => jumpTo(0)}>
            <RotateCcw size={15} />
          </Button>
        </div>

        <div className="grid grid-cols-[auto_1fr_auto] items-center gap-x-3 gap-y-2 text-sm">
          <span className="text-ink-secondary">Vitesse</span>
          <input
            type="range"
            min={10}
            max={130}
            step={5}
            value={engine.speedKmh}
            onChange={(e) => setEngine({ speedKmh: Number(e.target.value) })}
            className="accent-primary"
          />
          <span className="tabular-nums text-ink-primary w-16 text-right">{engine.speedKmh} km/h</span>

          <span className="text-ink-secondary">Accéléré</span>
          <Select value={engine.multiplier} onChange={(e) => setEngine({ multiplier: Number(e.target.value) })}>
            {MULTIPLIERS.map((m) => (
              <option key={m} value={m}>
                {m === 1 ? "Temps réel (×1)" : `×${m}`}
              </option>
            ))}
          </Select>
          <span />

          <span className="text-ink-secondary">Pause aux arrêts</span>
          <Select value={engine.dwellSec} onChange={(e) => setEngine({ dwellSec: Number(e.target.value) })}>
            {DWELLS.map((d) => (
              <option key={d} value={d}>
                {d === 0 ? "Aucune" : d < 60 ? `${d} s` : `${d / 60} min`}
              </option>
            ))}
          </Select>
          <span />
        </div>
        {engine.multiplier > 1 && (
          <p className="text-xs text-ink-muted">
            Le chauffeur roule {engine.multiplier} fois plus vite, mais l'horloge du serveur reste réelle : il arrive en
            avance sur les heures estimées.
          </p>
        )}

        <div className="flex flex-wrap items-center gap-3 text-sm">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={engine.gps} onChange={(e) => setEngine({ gps: e.target.checked })} />
            GPS actif
          </label>
          <Button variant="secondary" disabled={!engine.gps} onClick={() => sendNow()}>
            <Radio size={15} /> Envoyer la position
          </Button>
        </div>
        {!engine.gps && (
          <p className="text-xs text-danger">
            Plus aucune position n'est envoyée. Après 3 min, le serveur revient aux horaires publiés.
          </p>
        )}

        <div className="rounded-sm bg-bg p-2.5 text-xs text-ink-secondary flex flex-col gap-1">
          <div className="h-1.5 rounded-full bg-line overflow-hidden">
            <div
              className="h-full bg-primary"
              style={{ width: `${path.length > 0 ? Math.min(100, (engine.distance / path.length) * 100) : 0}%` }}
            />
          </div>
          <div>
            Parcouru {formatKm(engine.distance)} sur {formatKm(path.length)}
            {next && ` · prochain arrêt : ${next.name}, dans ${formatKm(next.distance - engine.distance)}`}
          </div>
          {dwellUntil > now && <div>En pause, reprise dans {countdown(dwellUntil - now)}.</div>}
          <div>Dernière position acceptée par le serveur : {ago(lastFixAt, now)}.</div>
          {scenario.routeSource === "straight" && <div className="text-danger">Route en lignes droites (OSRM indisponible).</div>}
        </div>
      </div>
    </Card>
  );
}

function RealDriverCard({ trip, now }: { trip: SimTrip | null; now: number }) {
  return (
    <Card className="p-4 flex flex-col gap-2">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-xs text-ink-muted">Vrai chauffeur</div>
          <div className="font-semibold text-ink-primary truncate">
            {trip?.driver_profile?.user?.full_name ?? "Chauffeur"}
          </div>
        </div>
        {trip && <Badge tone={TRIP_STATUS_TONE[trip.status]}>{TRIP_STATUS_LABEL[trip.status]}</Badge>}
      </div>
      <p className="text-sm text-ink-secondary">
        Ce trajet se pilote depuis l'appli chauffeur (téléphone ou émulateur) : démarrage, acceptation des demandes,
        absences. Pour déplacer l'émulateur, utilisez Location › Routes dans Android Studio.
      </p>
      {trip && (
        <div className="text-xs text-ink-secondary">
          Départ prévu à {clock(trip.scheduled_at)} · dernière position reçue {ago(trip.location_updated_at, now)}.
        </div>
      )}
    </Card>
  );
}
