import { useEffect, useMemo, useState } from "react";
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap } from "react-leaflet";
import L from "leaflet";
import { RefreshCw, Navigation, AlertTriangle, Car, MapPin } from "lucide-react";
import "leaflet/dist/leaflet.css";
import { useApi } from "../lib/useApi";
import type { MapTripItem, MapTripsResponse } from "../types/api";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Skeleton } from "../components/ui/Skeleton";
import { ErrorState } from "../components/ui/ErrorState";

const SENEGAL_CENTER: [number, number] = [14.6928, -17.25];

const createBadgeIcon = (bg: string, label: string, pulse = false) =>
  L.divIcon({
    className: "",
    html: `<div style="
      display:flex;align-items:center;justify-content:center;
      width:30px;height:30px;border-radius:9999px;
      background:${bg};color:#fff;font-weight:700;font-size:11px;
      border:2.5px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,0.28);
      ${pulse ? "outline:4px solid rgba(220,38,38,0.28);" : ""}
    ">${label}</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
  });

const iconInProgress = createBadgeIcon("#16a34a", "🚗", true);
const iconOpen = createBadgeIcon("#0ea5e9", "●");
const iconDest = createBadgeIcon("#475569", "⚑");
const iconSos = createBadgeIcon("#dc2626", "SOS", true);

function MapFlyTo({ target }: { target: [number, number] | null }) {
  const map = useMap();
  useEffect(() => {
    if (target) {
      map.flyTo(target, 12, { duration: 0.8 });
    }
  }, [map, target]);
  return null;
}

type FilterMode = "all" | "in_progress" | "open" | "sos";

export function MapView() {
  const { data, loading, error, reload } = useApi<MapTripsResponse>("/admin/map/trips", {
    pollInterval: 8000,
  });
  const [filter, setFilter] = useState<FilterMode>("all");
  const [selectedTripId, setSelectedTripId] = useState<string | null>(null);
  const [flyTarget, setFlyTarget] = useState<[number, number] | null>(null);

  const trips = data?.trips ?? [];
  const sosAlerts = data?.sos_alerts ?? [];

  const filteredTrips = useMemo(() => {
    if (filter === "sos") return [];
    if (filter === "in_progress") return trips.filter((t) => t.status === "in_progress");
    if (filter === "open") return trips.filter((t) => t.status === "open" || t.status === "full");
    return trips;
  }, [trips, filter]);

  const inProgressCount = trips.filter((t) => t.status === "in_progress").length;
  const openCount = trips.filter((t) => t.status === "open" || t.status === "full").length;

  const handleSelectTrip = (trip: MapTripItem) => {
    setSelectedTripId(trip.id);
    setFlyTarget([trip.current_lat || trip.origin_lat, trip.current_lng || trip.origin_lng]);
  };

  return (
    <div className="flex flex-col gap-5 h-full">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-ink-primary">Cartographie & Suivi GPS Live</h1>
          <p className="text-sm text-ink-secondary mt-0.5">
            Supervision en temps réel des trajets actifs, positions GPS des chauffeurs et alertes SOS (actualisation auto 10s).
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex items-center rounded-sm border border-line bg-surface p-0.5 text-xs font-medium">
            <button
              type="button"
              onClick={() => setFilter("all")}
              className={`px-2.5 py-1 rounded-sm transition ${
                filter === "all" ? "bg-primary text-white" : "text-ink-secondary hover:text-ink-primary"
              }`}
            >
              Tous ({trips.length})
            </button>
            <button
              type="button"
              onClick={() => setFilter("in_progress")}
              className={`px-2.5 py-1 rounded-sm transition ${
                filter === "in_progress" ? "bg-emerald-600 text-white" : "text-ink-secondary hover:text-ink-primary"
              }`}
            >
              En route ({inProgressCount})
            </button>
            <button
              type="button"
              onClick={() => setFilter("open")}
              className={`px-2.5 py-1 rounded-sm transition ${
                filter === "open" ? "bg-sky-600 text-white" : "text-ink-secondary hover:text-ink-primary"
              }`}
            >
              Ouverts ({openCount})
            </button>
            <button
              type="button"
              onClick={() => setFilter("sos")}
              className={`px-2.5 py-1 rounded-sm transition ${
                filter === "sos" ? "bg-red-600 text-white" : "text-ink-secondary hover:text-ink-primary"
              }`}
            >
              SOS ({sosAlerts.length})
            </button>
          </div>

          <button
            type="button"
            onClick={() => reload()}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-sm border border-line bg-surface text-xs font-medium text-ink-primary hover:bg-bg"
          >
            <RefreshCw size={14} className={loading ? "animate-spin" : ""} />
            Actualiser
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-4 flex-1 min-h-[480px]">
        <Card className="overflow-hidden p-0 relative">
          <MapContainer center={SENEGAL_CENTER} zoom={9} style={{ height: "100%", minHeight: 480 }}>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <MapFlyTo target={flyTarget} />

            {filteredTrips.map((trip) => {
              const isLive = trip.status === "in_progress";
              const pathPoints: [number, number][] = [
                [trip.origin_lat, trip.origin_lng],
                ...(Array.isArray(trip.waypoints)
                  ? trip.waypoints
                      .filter((w) => typeof w.lat === "number" && typeof w.lng === "number")
                      .map((w) => [w.lat, w.lng] as [number, number])
                  : []),
                [trip.destination_lat, trip.destination_lng],
              ];
              const vehiclePos: [number, number] = [
                trip.current_lat || trip.origin_lat,
                trip.current_lng || trip.origin_lng,
              ];

              return (
                <div key={trip.id}>
                  <Polyline
                    positions={pathPoints}
                    pathOptions={{
                      color: isLive ? "#16a34a" : "#0ea5e9",
                      weight: selectedTripId === trip.id ? 5 : 3,
                      opacity: selectedTripId === trip.id ? 0.95 : 0.65,
                      dashArray: isLive ? undefined : "6 6",
                    }}
                  />
                  <Marker position={vehiclePos} icon={isLive ? iconInProgress : iconOpen}>
                    <Popup>
                      <div className="text-xs space-y-1 min-w-[190px]">
                        <div className="font-semibold text-sm">
                          {trip.origin_name} → {trip.destination_name}
                        </div>
                        <div>
                          Statut :{" "}
                          <span className="font-semibold">
                            {isLive ? "En route (GPS Live)" : trip.status === "full" ? "Complet" : "Ouvert"}
                          </span>
                        </div>
                        {trip.driver && (
                          <div>
                            Chauffeur : <strong>{trip.driver.full_name}</strong> ({trip.driver.phone_number})
                          </div>
                        )}
                        {trip.vehicle && (
                          <div>
                            Véhicule : {trip.vehicle.make} {trip.vehicle.model} ·{" "}
                            <span className="font-mono">{trip.vehicle.plate_number}</span>
                          </div>
                        )}
                        <div>
                          Places dispo : {trip.seats_available} · {Number(trip.price_per_seat).toLocaleString("fr-FR")} FCFA
                        </div>
                        {trip.location_updated_at && (
                          <div className="text-[11px] text-slate-500">
                            Signal GPS : {new Date(trip.location_updated_at).toLocaleTimeString("fr-FR")}
                          </div>
                        )}
                      </div>
                    </Popup>
                  </Marker>
                  <Marker position={[trip.destination_lat, trip.destination_lng]} icon={iconDest}>
                    <Popup>
                      <div className="text-xs">
                        <strong>Arrivée :</strong> {trip.destination_name}
                      </div>
                    </Popup>
                  </Marker>
                </div>
              );
            })}

            {(filter === "all" || filter === "sos") &&
              sosAlerts.map((sos) => (
                <Marker key={sos.id} position={[sos.lat, sos.lng]} icon={iconSos}>
                  <Popup>
                    <div className="text-xs space-y-1">
                      <div className="font-bold text-red-600">ALERTE SOS ACTIVE</div>
                      <div>
                        Utilisateur : <strong>{sos.user_name}</strong> ({sos.user_phone})
                      </div>
                      {sos.triggered_at && (
                        <div>Déclenchée : {new Date(sos.triggered_at).toLocaleString("fr-FR")}</div>
                      )}
                    </div>
                  </Popup>
                </Marker>
              ))}
          </MapContainer>
        </Card>

        <Card className="p-4 flex flex-col max-h-[600px] overflow-hidden">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-sm font-semibold text-ink-primary">Trajets & Signaux actifs</h2>
            <span className="text-xs text-ink-muted">{filteredTrips.length} affiché(s)</span>
          </div>

          {loading && !data ? (
            <div className="flex flex-col gap-2">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-16 rounded-sm" />
              ))}
            </div>
          ) : error ? (
            <ErrorState message={error} />
          ) : (
            <div className="flex-1 overflow-y-auto space-y-2.5 pr-1">
              {sosAlerts.length > 0 && (filter === "all" || filter === "sos") && (
                <div className="space-y-2 mb-3">
                  {sosAlerts.map((sos) => (
                    <button
                      key={sos.id}
                      type="button"
                      onClick={() => setFlyTarget([sos.lat, sos.lng])}
                      className="w-full text-left border border-red-300 bg-red-50 rounded-sm p-2.5 hover:bg-red-100 transition"
                    >
                      <div className="flex items-center justify-between">
                        <span className="inline-flex items-center gap-1 text-xs font-bold text-red-700">
                          <AlertTriangle size={14} /> ALERTE SOS — {sos.user_name}
                        </span>
                        <span className="text-[11px] text-red-600">{sos.user_phone}</span>
                      </div>
                    </button>
                  ))}
                </div>
              )}

              {filteredTrips.length === 0 ? (
                <p className="text-sm text-ink-muted py-6 text-center">
                  Aucun trajet actif pour ce filtre.
                </p>
              ) : (
                filteredTrips.map((trip) => {
                  const isLive = trip.status === "in_progress";
                  const isSelected = selectedTripId === trip.id;
                  return (
                    <button
                      key={trip.id}
                      type="button"
                      onClick={() => handleSelectTrip(trip)}
                      className={`w-full text-left border rounded-sm p-3 transition ${
                        isSelected
                          ? "border-primary bg-primary-surface/40"
                          : "border-line bg-surface hover:border-primary/40"
                      }`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm font-semibold text-ink-primary truncate">
                          {trip.origin_name} → {trip.destination_name}
                        </span>
                        <Badge tone={isLive ? "success" : trip.status === "full" ? "neutral" : "primary"}>
                          {isLive ? "EN ROUTE" : trip.status === "full" ? "Complet" : "Ouvert"}
                        </Badge>
                      </div>

                      {Array.isArray(trip.waypoints) && trip.waypoints.length > 0 && (
                        <div className="text-[11px] text-ink-muted mt-1 flex items-center gap-1 truncate">
                          <MapPin size={11} /> Via{" "}
                          {trip.waypoints.map((w) => w.name || `${w.lat.toFixed(2)},${w.lng.toFixed(2)}`).join(" • ")}
                        </div>
                      )}

                      <div className="mt-2 flex items-center justify-between text-xs text-ink-secondary">
                        <span className="inline-flex items-center gap-1 truncate">
                          <Car size={13} />
                          {trip.driver?.full_name ?? "Chauffeur"}
                          {trip.vehicle ? ` · ${trip.vehicle.plate_number}` : ""}
                        </span>
                        <span className="font-medium text-ink-primary">
                          {trip.seats_available} pl. · {Number(trip.price_per_seat).toLocaleString("fr-FR")} F
                        </span>
                      </div>

                      {isLive && (
                        <div className="mt-1.5 flex items-center gap-1 text-[11px] text-emerald-700 font-medium">
                          <Navigation size={11} />
                          GPS : {trip.current_lat.toFixed(4)}, {trip.current_lng.toFixed(4)}
                          {trip.location_updated_at && (
                            <span className="text-ink-muted ml-auto">
                              {new Date(trip.location_updated_at).toLocaleTimeString("fr-FR")}
                            </span>
                          )}
                        </div>
                      )}
                    </button>
                  );
                })
              )}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
