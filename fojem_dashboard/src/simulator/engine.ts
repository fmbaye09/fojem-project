import { useCallback, useEffect, useLayoutEffect, useRef } from "react";
import { actorFetch, errorMessage } from "./api";
import { pointAt, type Path } from "./geo";
import { useSimStore } from "./store";

/** Un arrêt du trajet, situé sur la route du simulateur. */
export interface StopMark {
  id: string;
  name: string;
  position: number;
  /** Distance depuis le départ de la route, en mètres. */
  distance: number;
}

// Comme l'appli chauffeur (TripLocationTracker) : une position au plus
// toutes les 8 s, et seulement après 20 m de déplacement. À l'arrêt, plus
// rien ne part : la position finit par vieillir, comme en vrai.
const SEND_EVERY_MS = 8000;
const MIN_MOVE_M = 20;
const TICK_MS = 250;
/** Un onglet en arrière-plan ralentit les minuteries : on borne le saut. */
const MAX_STEP_S = 10;

/**
 * Fait rouler le chauffeur simulé sur la route et envoie ses positions par
 * l'API publique. À chaque point de rendez-vous franchi, une position est
 * envoyée exactement à l'arrêt (le serveur doit le voir passer), puis le
 * chauffeur marque la pause demandée.
 */
export function useDriverEngine(path: Path | null, marks: StopMark[]) {
  const pathRef = useRef(path);
  const marksRef = useRef(marks);
  useLayoutEffect(() => {
    pathRef.current = path;
    marksRef.current = marks;
  }, [path, marks]);

  const lastTick = useRef(0);
  const lastSent = useRef<{ at: number; distance: number } | null>(null);
  const inFlight = useRef(false);
  const lastError = useRef<string | null>(null);

  /** Envoie la position du chauffeur à [distance] ; vrai si le serveur l'accepte. */
  const send = useCallback(async (distance: number): Promise<boolean> => {
    const s = useSimStore.getState();
    const scenario = s.scenario;
    const p = pathRef.current;
    if (!scenario?.driver || !p || p.points.length === 0) return false;
    const { point, heading } = pointAt(p, distance);
    try {
      await actorFetch(scenario.driver.token, `/trips/${scenario.tripId}/location`, {
        method: "POST",
        body: { lat: point[0], lng: point[1], heading: Math.round(heading) },
      });
      lastSent.current = { at: Date.now(), distance };
      s.setLastFix(new Date().toISOString());
      if (lastError.current) {
        s.addLog("ok", "Le serveur accepte de nouveau les positions du chauffeur.");
        lastError.current = null;
      }
      return true;
    } catch (err) {
      const message = errorMessage(err);
      if (message !== lastError.current) {
        s.addLog("error", `Position refusée par le serveur : ${message}`);
        lastError.current = message;
      }
      return false;
    }
  }, []);

  useEffect(() => {
    lastTick.current = Date.now();
    const id = window.setInterval(() => {
      const now = Date.now();
      const dt = Math.min((now - lastTick.current) / 1000, MAX_STEP_S);
      lastTick.current = now;

      const s = useSimStore.getState();
      const p = pathRef.current;
      if (!s.scenario?.driver || !p || p.length === 0) return;
      const engine = s.engine;
      let distance = engine.distance;
      let atStop = false;

      if (engine.playing && now >= s.dwellUntil) {
        if (s.dwellUntil > 0) s.setDwellUntil(0);
        let next = Math.min(p.length, distance + (engine.speedKmh / 3.6) * engine.multiplier * dt);
        let playing = next < p.length;
        const all = marksRef.current;
        const crossed = all.find((m) => m.distance > distance + 1 && m.distance <= next);
        if (crossed) {
          next = crossed.distance;
          atStop = true;
          const isLast = crossed.position === Math.max(...all.map((m) => m.position));
          if (isLast) {
            playing = false;
            s.addLog("event", `Le chauffeur arrive au terminus, ${crossed.name}.`);
          } else if (engine.dwellSec > 0) {
            s.setDwellUntil(now + engine.dwellSec * 1000);
            s.addLog("event", `Le chauffeur s'arrête à ${crossed.name} (${engine.dwellSec} s).`);
          } else {
            s.addLog("event", `Le chauffeur passe à ${crossed.name} sans s'arrêter.`);
          }
        }
        distance = next;
        s.setEngine({ distance, playing });
      }

      if (!engine.gps) return;
      const last = lastSent.current;
      const due =
        atStop ||
        (!inFlight.current &&
          (last === null ? distance : Math.abs(distance - last.distance)) >= MIN_MOVE_M &&
          (last === null || now - last.at >= SEND_EVERY_MS));
      if (due) {
        inFlight.current = true;
        void send(distance).finally(() => {
          inFlight.current = false;
        });
      }
    }, TICK_MS);
    return () => window.clearInterval(id);
  }, [send]);

  /** Envoie tout de suite la position actuelle (comme l'appli avant une absence). */
  const sendNow = useCallback(() => send(useSimStore.getState().engine.distance), [send]);

  /** Déplace le chauffeur sans rouler (raccourci de test) et envoie sa position. */
  const jumpTo = useCallback(
    async (distance: number) => {
      const p = pathRef.current;
      if (!p) return false;
      const s = useSimStore.getState();
      const target = Math.max(0, Math.min(p.length, distance));
      s.setDwellUntil(0);
      s.setEngine({ distance: target });
      return s.engine.gps ? send(target) : false;
    },
    [send],
  );

  return { sendNow, jumpTo };
}
