import { useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker, Polyline, Popup, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { Car, Loader2, Mic, Phone, Siren, User } from "lucide-react";
import { useApi } from "../../lib/useApi";
import { apiFetchBlob } from "../../lib/api";
import { formatDateTime } from "../../lib/utils";
import type { SosAlert, SosPerson } from "../../types/api";
import { Badge } from "../ui/Badge";
import { ErrorState } from "../ui/ErrorState";
import { Skeleton } from "../ui/Skeleton";

/** Rafraîchissement de la fiche pendant qu'elle est ouverte. */
const REFRESH_MS = 10_000;

const sosIcon = L.divIcon({
  className: "",
  html: '<div style="width:22px;height:22px;border-radius:50%;background:#EA3C3F;border:3px solid #fff;box-shadow:0 0 0 6px rgba(234,60,63,.3)"></div>',
  iconSize: [22, 22],
  iconAnchor: [11, 11],
});

const carIcon = L.divIcon({
  className: "",
  html: '<div style="width:16px;height:16px;border-radius:50%;background:#00A58C;border:3px solid #fff"></div>',
  iconSize: [16, 16],
  iconAnchor: [8, 8],
});

function Recenter({ lat, lng }: { lat: number; lng: number }) {
  const map = useMap();
  useEffect(() => {
    map.setView([lat, lng], Math.max(map.getZoom(), 14));
  }, [lat, lng, map]);
  return null;
}

function phoneHref(phone: string) {
  return `tel:${phone.replace(/\s/g, "")}`;
}

function PersonLine({ label, person }: { label: string; person: SosPerson | null }) {
  if (!person) return null;
  return (
    <div className="flex flex-col gap-1 py-2 border-b border-line last:border-0">
      <span className="text-xs text-ink-muted">{label}</span>
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-medium text-ink-primary flex items-center gap-1.5">
          <User size={14} /> {person.full_name}
        </span>
        {person.phone_number && (
          <a href={phoneHref(person.phone_number)} className="text-sm text-primary hover:underline flex items-center gap-1">
            <Phone size={13} /> {person.phone_number}
          </a>
        )}
      </div>
      {person.emergency_contact && (
        <div className="flex items-center justify-between gap-2 text-xs">
          <span className="text-ink-secondary flex items-center gap-1">
            <Siren size={12} className="text-danger" /> Contact d'urgence : {person.emergency_contact.name}
          </span>
          <a href={phoneHref(person.emergency_contact.phone)} className="text-primary hover:underline">
            {person.emergency_contact.phone}
          </a>
        </div>
      )}
    </div>
  );
}

/** Lecteur d'un morceau : le fichier exige le token admin, d'où le blob. */
function Recording({ url, index, durationMs, at }: { url: string; index: number; durationMs: number; at: string }) {
  const [src, setSrc] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const controller = new AbortController();
    let objectUrl: string | null = null;
    apiFetchBlob(url, { signal: controller.signal })
      .then((blob) => {
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
      })
      .catch((err) => {
        if (!(err instanceof DOMException && err.name === "AbortError")) setFailed(true);
      });
    return () => {
      controller.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [url]);

  return (
    <div className="flex items-center gap-3 py-1.5">
      <span className="text-xs text-ink-muted w-28 shrink-0">
        #{index + 1} · {new Date(at).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" })} ·{" "}
        {Math.round(durationMs / 1000)} s
      </span>
      {failed ? (
        <span className="text-xs text-danger">Lecture impossible</span>
      ) : src ? (
        <audio controls preload="none" src={src} className="h-8 flex-1 min-w-0" />
      ) : (
        <Loader2 size={14} className="animate-spin text-ink-muted" />
      )}
    </div>
  );
}

export function SosAlertDetail({ alertId }: { alertId: string }) {
  const { data, loading, error, reload } = useApi<{ sos_alert: SosAlert }>(`/admin/sos-alerts/${alertId}`);

  useEffect(() => {
    const timer = window.setInterval(reload, REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [reload]);

  if (loading && !data) return <Skeleton className="h-96 rounded-sm" />;
  if (error && !data) return <ErrorState message={error} />;
  const alert = data!.sos_alert;
  const trip = alert.trip;
  const hasPosition = alert.last_lat != null && alert.last_lng != null;
  const path = alert.path.map(([lat, lng]) => [lat, lng] as [number, number]);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <Badge tone={alert.status === "open" ? "danger" : alert.status === "resolved" ? "success" : "neutral"}>
          {alert.status === "open" ? "Ouverte" : alert.status === "resolved" ? "Résolue" : "En cours"}
        </Badge>
        <span className="text-ink-secondary">
          Déclenchée par le {alert.role === "driver" ? "chauffeur" : "passager"} le {formatDateTime(alert.triggered_at)}
        </span>
        {alert.ended_at ? (
          <Badge tone="success">« En sécurité » à {formatDateTime(alert.ended_at)}</Badge>
        ) : (
          <Badge tone="danger">Alerte en cours</Badge>
        )}
      </div>

      <div className="h-72 rounded-sm overflow-hidden border border-line">
        {hasPosition ? (
          <MapContainer center={[alert.last_lat!, alert.last_lng!]} zoom={15} style={{ height: "100%" }}>
            <TileLayer
              attribution="© OpenStreetMap"
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <Recenter lat={alert.last_lat!} lng={alert.last_lng!} />
            {path.length > 1 && <Polyline positions={path} pathOptions={{ color: "#EA3C3F", weight: 4 }} />}
            <Marker position={[alert.last_lat!, alert.last_lng!]} icon={sosIcon}>
              <Popup>
                Dernière position
                {alert.last_location_at && <> · {formatDateTime(alert.last_location_at)}</>}
              </Popup>
            </Marker>
            {trip?.current_lat != null && trip.current_lng != null && (
              <Marker position={[trip.current_lat, trip.current_lng]} icon={carIcon}>
                <Popup>Position du véhicule</Popup>
              </Marker>
            )}
          </MapContainer>
        ) : (
          <div className="h-full flex items-center justify-center text-sm text-ink-muted">Position non disponible</div>
        )}
      </div>
      {hasPosition && (
        <a
          className="text-sm text-primary hover:underline -mt-2"
          href={`https://www.google.com/maps?q=${alert.last_lat},${alert.last_lng}`}
          target="_blank"
          rel="noreferrer"
        >
          Ouvrir la position dans Google Maps
          {alert.last_location_at && <> (mise à jour {formatDateTime(alert.last_location_at)})</>}
        </a>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <h3 className="text-sm font-semibold text-ink-primary mb-1">Personnes</h3>
          <PersonLine label="Auteur de l'alerte" person={alert.user} />
          {trip?.driver && trip.driver.id !== alert.user?.id && <PersonLine label="Chauffeur" person={trip.driver} />}
          {trip?.passengers
            .filter((p) => p.id !== alert.user?.id)
            .map((p) => <PersonLine key={p.id} label="Passager" person={p} />)}
        </div>
        <div>
          <h3 className="text-sm font-semibold text-ink-primary mb-1">Trajet</h3>
          {trip ? (
            <div className="text-sm text-ink-secondary flex flex-col gap-1">
              <span>
                {trip.origin_name ?? "Départ"} → {trip.destination_name ?? "Arrivée"}
              </span>
              {trip.scheduled_at && <span>Départ prévu : {formatDateTime(trip.scheduled_at)}</span>}
              {trip.vehicle && (
                <span className="flex items-center gap-1.5">
                  <Car size={14} /> {trip.vehicle.label} · <strong className="text-ink-primary">{trip.vehicle.plate_number}</strong>
                </span>
              )}
            </div>
          ) : (
            <p className="text-sm text-ink-muted">Aucun trajet associé.</p>
          )}
        </div>
      </div>

      <div>
        <h3 className="text-sm font-semibold text-ink-primary mb-1 flex items-center gap-1.5">
          <Mic size={14} /> Enregistrements ({alert.recordings.length})
        </h3>
        {alert.recordings.length === 0 ? (
          <p className="text-sm text-ink-muted">Aucun enregistrement reçu pour l'instant.</p>
        ) : (
          alert.recordings.map((r, i) => (
            <Recording key={r.id} url={r.file_endpoint} index={i} durationMs={r.duration_ms} at={r.created_at} />
          ))
        )}
      </div>
    </div>
  );
}
