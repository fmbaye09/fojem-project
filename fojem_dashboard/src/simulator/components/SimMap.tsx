import { useEffect, useMemo } from "react";
import { MapContainer, Marker, Polyline, TileLayer, Tooltip, useMap, useMapEvents } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { LatLng } from "../types";

// Couleurs des marqueurs Leaflet (HTML brut) : mêmes valeurs que les tokens
// Tailwind primary / success / ink / line.
const COLORS = {
  primary: "#EA671A",
  success: "#32963C",
  ink: "#0B2A47",
  muted: "#A0A09A",
  amber: "#D97706",
};

export type MapStopState = "passed" | "next" | "upcoming";

export interface MapStop {
  id: string;
  name: string;
  lat: number;
  lng: number;
  state: MapStopState;
  index: number;
  detail?: string;
}

export interface MapPoint {
  id: string;
  lat: number;
  lng: number;
  label: string;
}

interface Props {
  route: LatLng[];
  travelled?: LatLng[];
  stops: MapStop[];
  driver?: { point: LatLng; heading: number; label: string } | null;
  /** Dernière position reçue par le serveur, si elle diffère de celle du simulateur. */
  serverDriver?: { point: LatLng; label: string } | null;
  people?: MapPoint[];
  proposals?: MapPoint[];
  draft?: LatLng | null;
  picking?: boolean;
  onPick?: (point: LatLng) => void;
  /** Recadre la carte quand cette clé change (nouvelle route). */
  fitKey: string;
  height?: number;
}

const iconCache = new Map<string, L.DivIcon>();

function badgeIcon(key: string, html: string, size: number): L.DivIcon {
  const cached = iconCache.get(key);
  if (cached) return cached;
  const icon = L.divIcon({ className: "", html, iconSize: [size, size], iconAnchor: [size / 2, size / 2] });
  iconCache.set(key, icon);
  return icon;
}

function stopIcon(state: MapStopState, index: number): L.DivIcon {
  const bg = state === "passed" ? COLORS.success : state === "next" ? COLORS.primary : COLORS.ink;
  return badgeIcon(
    `stop-${state}-${index}`,
    `<div style="display:flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:9999px;background:${bg};color:#fff;font:700 12px Inter,sans-serif;border:2.5px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.28)">${index + 1}</div>`,
    26,
  );
}

function driverIcon(heading: number): L.DivIcon {
  const h = Math.round(heading / 5) * 5;
  return badgeIcon(
    `driver-${h}`,
    `<div style="display:flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:9999px;background:${COLORS.primary};border:3px solid #fff;box-shadow:0 2px 8px rgba(0,0,0,.35)"><div style="transform:rotate(${h}deg);color:#fff;font-size:15px;line-height:1">▲</div></div>`,
    34,
  );
}

const serverIcon = () =>
  badgeIcon(
    "server",
    `<div style="width:14px;height:14px;border-radius:9999px;background:${COLORS.muted};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.3)"></div>`,
    14,
  );

const personIcon = () =>
  badgeIcon(
    "person",
    `<div style="display:flex;align-items:center;justify-content:center;width:22px;height:22px;border-radius:9999px;background:${COLORS.success};color:#fff;font-size:12px;border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.3)">●</div>`,
    22,
  );

const proposalIcon = (draft: boolean) =>
  badgeIcon(
    draft ? "draft" : "proposal",
    `<div style="display:flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:6px;background:${COLORS.amber};color:#fff;font:700 16px Inter,sans-serif;border:2.5px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.3);${draft ? "outline:3px solid rgba(217,119,6,.35);" : ""}">+</div>`,
    26,
  );

function FitRoute({ points, fitKey }: { points: LatLng[]; fitKey: string }) {
  const map = useMap();
  useEffect(() => {
    if (points.length >= 2) map.fitBounds(L.latLngBounds(points), { padding: [36, 36] });
    else if (points.length === 1) map.setView(points[0], 13);
    // Seulement quand la route change, pas à chaque position du chauffeur.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, fitKey]);
  return null;
}

function PickPoint({ picking, onPick }: { picking: boolean; onPick?: (p: LatLng) => void }) {
  const map = useMapEvents({
    click(e) {
      if (picking && onPick) onPick([e.latlng.lat, e.latlng.lng]);
    },
  });
  useEffect(() => {
    map.getContainer().style.cursor = picking ? "crosshair" : "";
  }, [map, picking]);
  return null;
}

export function SimMap({
  route,
  travelled,
  stops,
  driver,
  serverDriver,
  people = [],
  proposals = [],
  draft,
  picking = false,
  onPick,
  fitKey,
  height = 560,
}: Props) {
  const fitPoints = useMemo<LatLng[]>(
    () => (route.length >= 2 ? route : stops.map((s) => [s.lat, s.lng] as LatLng)),
    [route, stops],
  );

  return (
    <MapContainer center={[14.7, -17.2]} zoom={10} style={{ height, width: "100%" }} scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitRoute points={fitPoints} fitKey={fitKey} />
      <PickPoint picking={picking} onPick={onPick} />

      {route.length >= 2 && <Polyline positions={route} pathOptions={{ color: COLORS.ink, weight: 4, opacity: 0.35 }} />}
      {travelled && travelled.length >= 2 && (
        <Polyline positions={travelled} pathOptions={{ color: COLORS.primary, weight: 5, opacity: 0.9 }} />
      )}

      {stops.map((s) => (
        <Marker key={s.id} position={[s.lat, s.lng]} icon={stopIcon(s.state, s.index)}>
          <Tooltip direction="top" offset={[0, -12]}>
            <div className="text-xs">
              <div className="font-semibold">{s.name}</div>
              {s.detail && <div>{s.detail}</div>}
            </div>
          </Tooltip>
        </Marker>
      ))}

      {proposals.map((p) => (
        <Marker key={p.id} position={[p.lat, p.lng]} icon={proposalIcon(false)}>
          <Tooltip direction="top" offset={[0, -12]}>
            <span className="text-xs">{p.label}</span>
          </Tooltip>
        </Marker>
      ))}
      {draft && (
        <Marker position={draft} icon={proposalIcon(true)}>
          <Tooltip direction="top" offset={[0, -12]} permanent>
            <span className="text-xs">Point proposé</span>
          </Tooltip>
        </Marker>
      )}

      {people.map((p) => (
        <Marker key={p.id} position={[p.lat, p.lng]} icon={personIcon()}>
          <Tooltip direction="top" offset={[0, -10]}>
            <span className="text-xs">{p.label}</span>
          </Tooltip>
        </Marker>
      ))}

      {serverDriver && (
        <Marker position={serverDriver.point} icon={serverIcon()} zIndexOffset={500}>
          <Tooltip direction="bottom" offset={[0, 8]}>
            <span className="text-xs">{serverDriver.label}</span>
          </Tooltip>
        </Marker>
      )}
      {driver && (
        <Marker position={driver.point} icon={driverIcon(driver.heading)} zIndexOffset={1000}>
          <Tooltip direction="top" offset={[0, -16]}>
            <span className="text-xs">{driver.label}</span>
          </Tooltip>
        </Marker>
      )}
    </MapContainer>
  );
}
