import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Card } from "../../components/ui/Card";
import { cn } from "../../lib/utils";
import { fetchRoute, passengerSpot } from "../actions";
import { actorFetch, errorMessage } from "../api";
import { useDriverEngine, type StopMark } from "../engine";
import { buildPath, haversineM, pointAt, projectOnPath, type Path } from "../geo";
import { routeKeyOf, useSimStore, type Scenario } from "../store";
import { clock } from "../time";
import type { LatLng, SimBooking, SimStop, SimTrip } from "../types";
import { useScenarioPolling } from "../usePolling";
import { DriverPanel } from "./DriverPanel";
import { EventLog, NotificationsFeed, TimesTable } from "./Feeds";
import { PassengersPanel } from "./PassengersPanel";
import { SimMap, type MapPoint, type MapStop, type MapStopState } from "./SimMap";

type Tab = "times" | "notifications" | "log";

/** Le scénario en cours : carte, conduite, passagers et ce que le serveur en dit. */
export function ScenarioRunner({ scenario }: { scenario: Scenario }) {
  const data = useScenarioPolling(scenario);
  const path = useMemo(() => buildPath(scenario.geometry), [scenario.geometry]);
  const stops = useMemo(() => [...(data.trip?.stops ?? [])].sort((a, b) => a.position - b.position), [data.trip]);
  const marks = useMemo(() => stopMarks(path, stops), [path, stops]);
  const { sendNow, jumpTo } = useDriverEngine(scenario.driver ? path : null, marks);
  useRouteFollowsStops(scenario, stops, path);
  usePassengerSharing(data.bookings);

  const [tab, setTab] = useState<Tab>("times");
  const [picking, setPicking] = useState(false);
  const [draft, setDraft] = useState<LatLng | null>(null);
  const logCount = useSimStore((s) => s.log.length);

  return (
    <div className="flex flex-col gap-4">
      {data.error && (
        <Card className="p-3 text-sm text-danger">Le serveur ne répond pas comme prévu : {data.error}</Card>
      )}
      <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_400px] gap-4 items-start">
        <div className="flex flex-col gap-4 min-w-0">
          <Card className="overflow-hidden p-0">
            <LiveMap
              scenario={scenario}
              trip={data.trip}
              bookings={data.bookings}
              path={path}
              stops={stops}
              picking={picking}
              draft={draft}
              onPick={(p) => {
                setDraft(p);
                setPicking(false);
              }}
            />
          </Card>
          <Card className="p-0 overflow-hidden">
            <div className="flex border-b border-line text-sm">
              <TabButton active={tab === "times"} onClick={() => setTab("times")}>
                Heures de passage
              </TabButton>
              <TabButton active={tab === "notifications"} onClick={() => setTab("notifications")}>
                Notifications ({data.notifications.length})
              </TabButton>
              <TabButton active={tab === "log"} onClick={() => setTab("log")}>
                Journal ({logCount})
              </TabButton>
            </div>
            <div className="max-h-[440px] overflow-y-auto">
              {tab === "times" ? (
                <TimesTable trip={data.trip} />
              ) : tab === "notifications" ? (
                <NotificationsFeed notifications={data.notifications} />
              ) : (
                <EventLog />
              )}
            </div>
          </Card>
        </div>

        <div className="flex flex-col gap-4">
          <DriverPanel scenario={scenario} trip={data.trip} path={path} marks={marks} sendNow={sendNow} jumpTo={jumpTo} />
          <PassengersPanel
            scenario={scenario}
            trip={data.trip}
            bookings={data.bookings}
            otherBookings={data.otherBookings}
            picking={picking}
            onStartPicking={() => {
              setDraft(null);
              setPicking(true);
            }}
            draft={draft}
            onClearDraft={() => setDraft(null)}
            sendNow={sendNow}
            refresh={data.refresh}
          />
        </div>
      </div>
    </div>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "px-4 py-2.5 -mb-px border-b-2 font-medium transition-colors",
        active ? "border-primary text-primary" : "border-transparent text-ink-secondary hover:text-ink-primary",
      )}
    >
      {children}
    </button>
  );
}

/** La carte suit le chauffeur à chaque pas : elle seule lit sa position en continu. */
function LiveMap({
  scenario,
  trip,
  bookings,
  path,
  stops,
  picking,
  draft,
  onPick,
}: {
  scenario: Scenario;
  trip: SimTrip | null;
  bookings: SimBooking[];
  path: Path;
  stops: SimStop[];
  picking: boolean;
  draft: LatLng | null;
  onPick: (p: LatLng) => void;
}) {
  const distance = useSimStore((s) => s.engine.distance);
  const simulated = scenario.driver ? pointAt(path, distance) : null;
  const server: LatLng | null =
    trip?.current_lat != null && trip.current_lng != null ? [trip.current_lat, trip.current_lng] : null;

  const driver = simulated
    ? { point: simulated.point, heading: simulated.heading, label: `${scenario.driver?.full_name} (simulateur)` }
    : server
      ? { point: server, heading: trip?.current_heading ?? 0, label: trip?.driver_profile?.user?.full_name ?? "Chauffeur" }
      : null;
  // Là où le serveur croit le chauffeur, quand ce n'est plus là où il est.
  const ghost =
    simulated && server && haversineM(simulated.point, server) > 30
      ? { point: server, label: "Dernière position reçue par le serveur" }
      : null;

  const mapStops: MapStop[] = stops.map((s, i) => ({
    id: s.id,
    name: s.name,
    lat: s.lat,
    lng: s.lng,
    index: i,
    state: stopState(trip, s),
    detail: stopDetail(trip, s, bookings),
  }));
  const people: MapPoint[] = bookings
    .filter((b) => b.passenger_location)
    .map((b) => ({
      id: b.id,
      lat: b.passenger_location!.lat,
      lng: b.passenger_location!.lng,
      label: `${b.passenger?.full_name ?? "Passager"} partage sa position`,
    }));
  const proposals: MapPoint[] = bookings
    .filter((b) => b.status === "pending_driver" && b.proposed_stop && !b.proposed_stop.inserted_stop_id)
    .map((b) => ({
      id: b.id,
      lat: b.proposed_stop!.lat,
      lng: b.proposed_stop!.lng,
      label: `${b.proposed_stop!.name} : proposé par ${b.passenger?.full_name ?? "un passager"}`,
    }));

  return (
    <SimMap
      route={scenario.geometry}
      travelled={simulated ? travelledPart(path, distance) : undefined}
      stops={mapStops}
      driver={driver}
      serverDriver={ghost}
      people={people}
      proposals={proposals}
      draft={draft}
      picking={picking}
      onPick={onPick}
      fitKey={scenario.tripId}
    />
  );
}

function stopState(trip: SimTrip | null, s: SimStop): MapStopState {
  if (!trip) return "upcoming";
  if (trip.status === "completed") return "passed";
  if (trip.status === "in_progress") {
    if (s.position <= (trip.last_passed_stop_position ?? 0)) return "passed";
    return trip.live?.next_stop_id === s.id ? "next" : "upcoming";
  }
  return s.position === 0 ? "next" : "upcoming";
}

function stopDetail(trip: SimTrip | null, s: SimStop, bookings: SimBooking[]): string {
  const eta = trip?.live?.etas.find((e) => e.stop_id === s.id)?.eta;
  const boarding = bookings.filter((b) => b.boarding_stop_id === s.id && (b.status === "confirmed" || b.status === "pending_driver")).length;
  return [
    s.scheduled_at && `prévu ${clock(s.scheduled_at)}`,
    eta && `estimé vers ${clock(eta)}`,
    s.reached_at && `atteint ${clock(s.reached_at)}`,
    boarding > 0 && `${boarding} passager${boarding > 1 ? "s montent" : " monte"} ici`,
  ]
    .filter(Boolean)
    .join(" · ");
}

/** Chaque arrêt situé sur la route, dans l'ordre (un arrêt ne se projette pas avant le précédent). */
function stopMarks(path: Path, stops: SimStop[]): StopMark[] {
  let from = 0;
  return stops.map((s) => {
    const { distance } = projectOnPath(path, [s.lat, s.lng], from);
    from = distance;
    return { id: s.id, name: s.name, position: s.position, distance };
  });
}

function travelledPart(path: Path, distance: number): LatLng[] {
  if (distance <= 0 || path.points.length < 2) return [];
  let i = 0;
  while (i + 1 < path.points.length && path.cumulative[i + 1] <= distance) i++;
  return [...path.points.slice(0, i + 1), pointAt(path, distance).point];
}

/**
 * Un arrêt ajouté (ou retiré) change le trajet : la route est recalculée et
 * le chauffeur garde sa place, projetée sur la nouvelle route.
 */
function useRouteFollowsStops(scenario: Scenario, stops: SimStop[], path: Path) {
  const key = stops.length >= 2 ? routeKeyOf(stops) : null;
  const pathRef = useRef(path);
  const stopsRef = useRef(stops);
  useLayoutEffect(() => {
    pathRef.current = path;
    stopsRef.current = stops;
  }, [path, stops]);

  useEffect(() => {
    if (!key || key === scenario.routeKey) return;
    let cancelled = false;
    fetchRoute(stopsRef.current)
      .then((route) => {
        if (cancelled) return;
        const s = useSimStore.getState();
        const here = pointAt(pathRef.current, s.engine.distance).point;
        s.updateScenario({ geometry: route.geometry, routeSource: route.source, routeKey: key });
        if (s.scenario?.driver) s.setEngine({ distance: projectOnPath(buildPath(route.geometry), here).distance });
        s.addLog("event", "Itinéraire recalculé : il passe par les arrêts actuels du trajet.");
      })
      .catch((err) => useSimStore.getState().addLog("error", `Itinéraire non recalculé : ${errorMessage(err)}`));
    return () => {
      cancelled = true;
    };
  }, [key, scenario.routeKey]);
}

/** Un passager qui partage sa position la renvoie chaque minute, comme l'appli. */
function usePassengerSharing(bookings: SimBooking[]) {
  const ref = useRef(bookings);
  useLayoutEffect(() => {
    ref.current = bookings;
  }, [bookings]);
  useEffect(() => {
    const id = window.setInterval(() => {
      const { sharing, scenario } = useSimStore.getState();
      if (!scenario) return;
      for (const b of ref.current) {
        if (!sharing[b.id] || b.status !== "confirmed" || b.started_at) continue;
        const actor = scenario.passengers.find((p) => p.id === b.passenger_id);
        const spot = passengerSpot(b);
        if (actor && spot) {
          void actorFetch(actor.token, `/bookings/${b.id}/location`, {
            method: "POST",
            body: { lat: spot[0], lng: spot[1] },
          }).catch(() => {});
        }
      }
    }, 60_000);
    return () => window.clearInterval(id);
  }, []);
}
