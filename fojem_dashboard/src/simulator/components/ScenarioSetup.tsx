import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Car, Loader2, Play, Plus, Smartphone, Trash2 } from "lucide-react";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Input } from "../../components/ui/Input";
import { Select } from "../../components/ui/Select";
import { apiFetch } from "../../lib/api";
import { cn } from "../../lib/utils";
import type { AdminTrip, AdminTripDetail, Paginated } from "../../types/api";
import { createScenario, createScenarioOnTrip, type PassengerPlan } from "../actions";
import { errorMessage } from "../api";
import { ROUTE_PRESETS } from "../presets";
import { useSimStore } from "../store";
import { clock, clockSec } from "../time";
import type { LatLng, PlannedPoint } from "../types";
import { SimMap } from "./SimMap";

type Mode = "simulated" | "real";

const DEPARTURES = [2, 5, 10, 20, 35, 60, 120];

function defaultPlans(stopCount: number): PassengerPlan[] {
  const last = stopCount - 1;
  return stopCount >= 3
    ? [
        { name: "", board: 0, alight: last, accept: true },
        { name: "", board: 1, alight: last, accept: true },
      ]
    : [{ name: "", board: 0, alight: last, accept: true }];
}

export function ScenarioSetup() {
  const [mode, setMode] = useState<Mode>("simulated");
  const [presetId, setPresetId] = useState<string>(ROUTE_PRESETS[0].id);
  const [custom, setCustom] = useState<PlannedPoint[]>([]);
  const [departureIn, setDepartureIn] = useState(10);
  const [seats, setSeats] = useState(4);
  const [price, setPrice] = useState(3000);
  const [enRoute, setEnRoute] = useState(true);
  const [earlier, setEarlier] = useState(true);
  const [plans, setPlans] = useState<PassengerPlan[]>(() => defaultPlans(ROUTE_PRESETS[0].points.length));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const log = useSimStore((s) => s.log);

  // Trajet d'un vrai chauffeur.
  const [trips, setTrips] = useState<AdminTrip[] | null>(null);
  const [tripId, setTripId] = useState("");
  const [detail, setDetail] = useState<AdminTripDetail | null>(null);

  const isCustom = presetId === "custom";
  const preset = ROUTE_PRESETS.find((p) => p.id === presetId);
  const points: PlannedPoint[] = isCustom ? custom : (preset?.points ?? []);
  const stopNames =
    mode === "simulated"
      ? points.map((p) => p.name)
      : [...(detail?.stops ?? [])].sort((a, b) => a.position - b.position).map((s) => s.name);

  useEffect(() => {
    if (mode !== "real" || trips !== null) return;
    Promise.all(
      (["open", "full", "in_progress"] as const).map((status) =>
        apiFetch<Paginated<AdminTrip>>("/admin/trips", { query: { status, per_page: 50 } }).then((p) => p.data),
      ),
    )
      .then((lists) => setTrips(lists.flat()))
      .catch((err) => setError(errorMessage(err)));
  }, [mode, trips]);

  useEffect(() => {
    if (!tripId) return;
    let cancelled = false;
    apiFetch<{ trip: AdminTripDetail }>(`/admin/trips/${tripId}`)
      .then((r) => {
        if (cancelled) return;
        setDetail(r.trip);
        setPlans(defaultPlans(r.trip.stops.length).map((p) => ({ ...p, accept: false })));
      })
      .catch((err) => setError(errorMessage(err)));
    return () => {
      cancelled = true;
    };
  }, [tripId]);

  const choosePreset = (id: string) => {
    setPresetId(id);
    const count = id === "custom" ? Math.max(custom.length, 2) : (ROUTE_PRESETS.find((p) => p.id === id)?.points.length ?? 2);
    setPlans(defaultPlans(count));
  };

  const addCustomPoint = (p: LatLng) => {
    const next = [
      ...custom,
      { name: `Point ${custom.length + 1}`, address: `Point choisi sur la carte (${p[0].toFixed(4)}, ${p[1].toFixed(4)})`, lat: p[0], lng: p[1] },
    ];
    setCustom(next);
    setPlans(defaultPlans(Math.max(next.length, 2)));
  };

  const removeCustomPoint = (index: number) => {
    const next = custom.filter((_, j) => j !== index);
    setCustom(next);
    setPlans(defaultPlans(Math.max(next.length, 2)));
  };

  const problem = useMemo(() => {
    if (mode === "real") return tripId ? null : "Choisissez un trajet.";
    if (points.length < 2) return "Il faut au moins deux points (cliquez sur la carte).";
    if (points.length > 12) return "Douze points au plus.";
    if (plans.length > seats) return "Plus de passagers que de places.";
    if (plans.some((p) => p.alight <= p.board)) return "Chaque passager doit descendre après être monté.";
    return null;
  }, [mode, tripId, points.length, plans, seats]);

  const launch = async () => {
    setBusy(true);
    setError(null);
    try {
      const scenario =
        mode === "simulated"
          ? await createScenario({
              label: isCustom ? "Itinéraire personnalisé" : (preset?.label ?? "Scénario"),
              points,
              departureInMin: departureIn,
              seats,
              price,
              acceptsEnRoute: enRoute,
              publishedEarlier: earlier,
              passengers: plans,
            })
          : await createScenarioOnTrip(tripId, plans);
      useSimStore.getState().setScenario(scenario);
    } catch (err) {
      const message = errorMessage(err);
      setError(message);
      useSimStore.getState().addLog("error", `Création du scénario interrompue : ${message}`);
    } finally {
      setBusy(false);
    }
  };

  const mapPoints: LatLng[] =
    mode === "simulated"
      ? points.map((p) => [p.lat, p.lng])
      : detail
        ? [
            [detail.origin_lat, detail.origin_lng],
            [detail.destination_lat, detail.destination_lng],
          ]
        : [];

  return (
    <div className="grid grid-cols-1 lg:grid-cols-[420px_minmax(0,1fr)] gap-4">
      <Card className="p-4 flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-2">
          <ModeButton active={mode === "simulated"} onClick={() => setMode("simulated")} icon={<Car size={16} />} title="Chauffeur simulé" hint="Le simulateur conduit" />
          <ModeButton active={mode === "real"} onClick={() => setMode("real")} icon={<Smartphone size={16} />} title="Vrai chauffeur" hint="Un trajet publié depuis l'appli" />
        </div>

        {mode === "simulated" ? (
          <>
            <Field label="Itinéraire">
              <Select value={presetId} onChange={(e) => choosePreset(e.target.value)}>
                {ROUTE_PRESETS.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.label}
                  </option>
                ))}
                <option value="custom">Personnalisé (cliquez sur la carte)</option>
              </Select>
              <span className="text-xs text-ink-muted">{isCustom ? "Cliquez sur la carte pour ajouter les points, dans l'ordre." : preset?.hint}</span>
            </Field>

            {isCustom && custom.length > 0 && (
              <div className="flex flex-col gap-1.5">
                {custom.map((p, i) => (
                  <div key={i} className="flex items-center gap-2">
                    <span className="text-xs text-ink-muted w-4">{i + 1}.</span>
                    <Input
                      className="flex-1"
                      value={p.name}
                      onChange={(e) => setCustom((list) => list.map((q, j) => (j === i ? { ...q, name: e.target.value } : q)))}
                    />
                    <button
                      type="button"
                      className="text-ink-muted hover:text-danger"
                      aria-label="Retirer"
                      onClick={() => removeCustomPoint(i)}
                    >
                      <Trash2 size={15} />
                    </button>
                  </div>
                ))}
              </div>
            )}

            <div className="grid grid-cols-3 gap-2">
              <Field label="Départ dans">
                <Select value={departureIn} onChange={(e) => setDepartureIn(Number(e.target.value))}>
                  {DEPARTURES.map((m) => (
                    <option key={m} value={m}>
                      {m < 60 ? `${m} min` : `${m / 60} h`}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Places">
                <Input type="number" min={1} max={8} value={seats} onChange={(e) => setSeats(Math.max(1, Math.min(8, Number(e.target.value) || 1)))} />
              </Field>
              <Field label="Prix (FCFA)">
                <Input type="number" min={500} step={500} value={price} onChange={(e) => setPrice(Math.max(500, Number(e.target.value) || 500))} />
              </Field>
            </div>

            <div className="flex flex-col gap-1.5 text-sm text-ink-primary">
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={enRoute} onChange={(e) => setEnRoute(e.target.checked)} />
                Accepte des passagers en route
              </label>
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={earlier} onChange={(e) => setEarlier(e.target.checked)} />
                Publié il y a 1 h (pour les rappels « 30 min avant »)
              </label>
            </div>
          </>
        ) : (
          <Field label="Trajet publié depuis l'appli chauffeur">
            {trips === null ? (
              <span className="text-sm text-ink-muted">Chargement…</span>
            ) : trips.length === 0 ? (
              <span className="text-sm text-ink-muted">Aucun trajet ouvert ou en cours : publiez-en un depuis l'appli chauffeur.</span>
            ) : (
              <Select
                value={tripId}
                onChange={(e) => {
                  setDetail(null);
                  setTripId(e.target.value);
                }}
              >
                <option value="">Choisir…</option>
                {trips.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.origin_name} → {t.destination_name} · {clock(t.scheduled_at)} · {t.driver?.full_name ?? "?"}
                  </option>
                ))}
              </Select>
            )}
            <span className="text-xs text-ink-muted">Des passagers simulés réservent ce trajet ; le vrai chauffeur les accepte dans son appli.</span>
          </Field>
        )}

        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-ink-primary">Passagers simulés</span>
            <button
              type="button"
              className="inline-flex items-center gap-1 text-xs font-medium text-primary disabled:opacity-40"
              disabled={stopNames.length < 2}
              onClick={() => setPlans((list) => [...list, { name: "", board: 0, alight: stopNames.length - 1, accept: mode === "simulated" }])}
            >
              <Plus size={14} /> Ajouter
            </button>
          </div>
          {plans.length === 0 && <span className="text-xs text-ink-muted">Aucun : vous pourrez en ajouter pendant le scénario.</span>}
          {plans.map((plan, i) => (
            <div key={i} className="rounded-sm border border-line p-2 flex flex-col gap-1.5">
              <div className="flex items-center gap-2">
                <Input
                  className="flex-1"
                  placeholder="Nom au hasard"
                  value={plan.name}
                  onChange={(e) => setPlans((list) => list.map((p, j) => (j === i ? { ...p, name: e.target.value } : p)))}
                />
                <button type="button" aria-label="Retirer" className="text-ink-muted hover:text-danger" onClick={() => setPlans((list) => list.filter((_, j) => j !== i))}>
                  <Trash2 size={15} />
                </button>
              </div>
              <div className="grid grid-cols-2 gap-1.5">
                <Select value={plan.board} onChange={(e) => setPlans((list) => list.map((p, j) => (j === i ? { ...p, board: Number(e.target.value) } : p)))}>
                  {stopNames.slice(0, -1).map((n, k) => (
                    <option key={k} value={k}>
                      Monte à {n}
                    </option>
                  ))}
                </Select>
                <Select value={plan.alight} onChange={(e) => setPlans((list) => list.map((p, j) => (j === i ? { ...p, alight: Number(e.target.value) } : p)))}>
                  {stopNames.map((n, k) =>
                    k > 0 ? (
                      <option key={k} value={k}>
                        Descend à {n}
                      </option>
                    ) : null,
                  )}
                </Select>
              </div>
              {mode === "simulated" && (
                <label className="flex items-center gap-2 text-xs text-ink-secondary">
                  <input type="checkbox" checked={plan.accept} onChange={(e) => setPlans((list) => list.map((p, j) => (j === i ? { ...p, accept: e.target.checked } : p)))} />
                  Acceptée par le chauffeur
                </label>
              )}
            </div>
          ))}
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}
        <Button disabled={busy || problem !== null} onClick={launch} title={problem ?? undefined}>
          {busy ? <Loader2 size={15} className="animate-spin" /> : <Play size={15} />}
          Lancer le scénario
        </Button>
        {problem && <p className="text-xs text-ink-muted -mt-2">{problem}</p>}

        {busy && (
          <ul className="text-xs text-ink-secondary flex flex-col gap-0.5">
            {log.slice(0, 6).map((e) => (
              <li key={e.id} className={cn(e.kind === "error" && "text-danger")}>
                {clockSec(e.at)} · {e.text}
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card className="overflow-hidden p-0 lg:self-start">
        <SimMap
          route={mapPoints}
          stops={mapPoints.map((p, i) => ({
            id: `p${i}`,
            name: (mode === "simulated" ? points[i]?.name : i === 0 ? detail?.origin_name : detail?.destination_name) ?? "",
            lat: p[0],
            lng: p[1],
            state: "upcoming" as const,
            index: i,
            detail: mode === "simulated" ? points[i]?.address : undefined,
          }))}
          picking={mode === "simulated" && isCustom}
          onPick={addCustomPoint}
          fitKey={`${mode}-${presetId}-${tripId}-${isCustom ? 0 : points.length}`}
          height={620}
        />
      </Card>
    </div>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-xs font-medium text-ink-secondary">{label}</span>
      {children}
    </label>
  );
}

function ModeButton({
  active,
  onClick,
  icon,
  title,
  hint,
}: {
  active: boolean;
  onClick: () => void;
  icon: ReactNode;
  title: string;
  hint: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-sm border p-2.5 text-left transition-colors",
        active ? "border-primary bg-primary-surface" : "border-line hover:bg-bg",
      )}
    >
      <div className={cn("flex items-center gap-1.5 text-sm font-medium", active ? "text-primary" : "text-ink-primary")}>
        {icon} {title}
      </div>
      <div className="text-xs text-ink-muted mt-0.5">{hint}</div>
    </button>
  );
}
