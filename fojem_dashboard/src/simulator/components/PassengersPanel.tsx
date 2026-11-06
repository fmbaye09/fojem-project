import { useMemo, useState, type ReactNode } from "react";
import { History, MapPinPlus, UserPlus, X } from "lucide-react";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Badge } from "../../components/ui/Badge";
import { Input } from "../../components/ui/Input";
import { Select } from "../../components/ui/Select";
import { BOOKING_STATUS_LABEL, BOOKING_STATUS_TONE } from "../../components/trips/tripLabels";
import { apiFetch } from "../../lib/api";
import { formatXof } from "../../lib/utils";
import type { AdminTripBooking } from "../../types/api";
import { actorFetch, errorMessage } from "../api";
import { addPassenger, bookWithProposal, createActor, passengerSpot, previewProposal, run } from "../actions";
import { driverLeft } from "../geo";
import { useSimStore, type Scenario } from "../store";
import { clock, countdown, useNow } from "../time";
import type { Actor, LatLng, SimBooking, SimProposedStop, SimStop, SimTrip } from "../types";

interface Props {
  scenario: Scenario;
  trip: SimTrip | null;
  bookings: SimBooking[];
  otherBookings: AdminTripBooking[];
  picking: boolean;
  onStartPicking: () => void;
  draft: LatLng | null;
  onClearDraft: () => void;
  sendNow: () => Promise<boolean>;
  refresh: () => void;
}

const ORDER: Record<string, number> = { pending_driver: 0, confirmed: 1, completed: 2 };

export function PassengersPanel(props: Props) {
  const { scenario, trip, bookings, otherBookings, picking, onStartPicking, draft } = props;
  const [adding, setAdding] = useState(false);
  const stops = useMemo(() => [...(trip?.stops ?? [])].sort((a, b) => a.position - b.position), [trip]);
  const sorted = useMemo(
    () => [...bookings].sort((a, b) => (ORDER[a.status] ?? 3) - (ORDER[b.status] ?? 3)),
    [bookings],
  );
  const canPropose = trip?.status === "open";

  const age = () =>
    run(
      "Dater le scénario d'il y a 1 h",
      () =>
        apiFetch("/admin/simulator/backdate", {
          method: "POST",
          body: {
            trip_id: scenario.driver ? scenario.tripId : undefined,
            booking_ids: Object.keys(scenario.bookings),
            minutes: 60,
          },
        }),
      "Trajet et réservations datés d'il y a 1 h : les rappels « 30 min avant » peuvent partir.",
    );

  return (
    <Card className="p-4 flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <div className="font-semibold text-ink-primary">Passagers</div>
        <div className="flex gap-1.5">
          <Button variant="secondary" className="h-8 px-2.5 text-xs" onClick={() => setAdding((v) => !v)} disabled={!trip}>
            <UserPlus size={14} /> Ajouter
          </Button>
          <Button
            variant="secondary"
            className="h-8 px-2.5 text-xs"
            onClick={onStartPicking}
            disabled={!canPropose || picking}
            title={canPropose ? "Cliquez ensuite sur la carte" : "Seulement avant le départ, sur un trajet qui a des places"}
          >
            <MapPinPlus size={14} /> Proposer un arrêt
          </Button>
        </div>
      </div>

      {picking && !draft && (
        <p className="rounded-sm bg-primary-surface px-3 py-2 text-xs text-ink-primary">
          Cliquez sur la carte, là où le passager veut monter ou descendre.
        </p>
      )}
      {adding && trip && <AddPassengerForm scenario={scenario} trip={trip} stops={stops} onDone={() => { setAdding(false); props.refresh(); }} />}
      {draft && trip && <ProposalDraft scenario={scenario} trip={trip} stops={stops} point={draft} onClose={props.onClearDraft} refresh={props.refresh} />}

      {sorted.length === 0 && otherBookings.length === 0 && (
        <p className="text-sm text-ink-muted">Aucune réservation pour l'instant.</p>
      )}
      <div className="flex flex-col divide-y divide-line">
        {sorted.map((b) => (
          <BookingRow key={b.id} booking={b} scenario={scenario} trip={trip} sendNow={props.sendNow} />
        ))}
        {otherBookings.map((b) => (
          <div key={b.id} className="py-2.5 flex items-center justify-between gap-2 text-sm">
            <div className="min-w-0">
              <div className="font-medium text-ink-primary truncate">{b.passenger?.full_name ?? "Passager"}</div>
              <div className="text-xs text-ink-secondary">
                {b.boarding_stop ?? "?"} → {b.alighting_stop ?? "?"} · vrai compte
              </div>
            </div>
            <Badge tone={BOOKING_STATUS_TONE[b.status]}>{BOOKING_STATUS_LABEL[b.status]}</Badge>
          </div>
        ))}
      </div>

      <Button variant="ghost" className="h-8 text-xs self-start" onClick={age}>
        <History size={14} /> Dater le scénario d'il y a 1 h (rappels)
      </Button>
    </Card>
  );
}

function stopLabel(stops: SimStop[], i: number) {
  const s = stops[i];
  return s ? `${i + 1}. ${s.name}${s.scheduled_at ? ` (${clock(s.scheduled_at)})` : ""}` : "";
}

function AddPassengerForm({ scenario, trip, stops, onDone }: { scenario: Scenario; trip: SimTrip; stops: SimStop[]; onDone: () => void }) {
  const [name, setName] = useState("");
  const [board, setBoard] = useState(trip.status === "in_progress" ? Math.min((trip.last_passed_stop_position ?? 0) + 1, stops.length - 2) : 0);
  const [alight, setAlight] = useState(stops.length - 1);
  const [accept, setAccept] = useState(true);
  const [busy, setBusy] = useState(false);
  const enRoute = trip.status === "in_progress";

  const submit = async () => {
    setBusy(true);
    const ok = await run(`Ajouter un passager ${enRoute ? "en route " : ""}(${stops[board]?.name} → ${stops[alight]?.name})`, () =>
      addPassenger(scenario, trip, { name, board, alight, accept: accept && !enRoute }),
    );
    setBusy(false);
    if (ok) onDone();
  };

  return (
    <div className="rounded-sm border border-line p-3 flex flex-col gap-2 text-sm">
      <Input placeholder="Nom (au hasard si vide)" value={name} onChange={(e) => setName(e.target.value)} />
      <div className="grid grid-cols-2 gap-2">
        <label className="flex flex-col gap-1 text-xs text-ink-secondary">
          Monte à
          <Select
            value={board}
            onChange={(e) => {
              const next = Number(e.target.value);
              setBoard(next);
              if (alight <= next) setAlight(stops.length - 1);
            }}
          >
            {stops.slice(0, -1).map((_, i) => (
              <option key={i} value={i}>
                {stopLabel(stops, i)}
              </option>
            ))}
          </Select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-ink-secondary">
          Descend à
          <Select value={alight} onChange={(e) => setAlight(Number(e.target.value))}>
            {stops.map((_, i) =>
              i > board ? (
                <option key={i} value={i}>
                  {stopLabel(stops, i)}
                </option>
              ) : null,
            )}
          </Select>
        </label>
      </div>
      {enRoute ? (
        <p className="text-xs text-ink-muted">
          Trajet parti : réservation en route, confirmée d'office si le trajet l'accepte et que le chauffeur passe à cet
          arrêt dans 15 min ou plus.
        </p>
      ) : (
        scenario.driver && (
          <label className="flex items-center gap-2 text-xs text-ink-primary">
            <input type="checkbox" checked={accept} onChange={(e) => setAccept(e.target.checked)} />
            Le chauffeur accepte aussitôt
          </label>
        )
      )}
      <Button disabled={busy || alight <= board} onClick={submit}>
        Réserver
      </Button>
    </div>
  );
}

function ProposalDraft({
  scenario,
  trip,
  stops,
  point,
  onClose,
  refresh,
}: {
  scenario: Scenario;
  trip: SimTrip;
  stops: SimStop[];
  point: LatLng;
  onClose: () => void;
  refresh: () => void;
}) {
  const [role, setRole] = useState<SimProposedStop["role"]>("boarding");
  const [other, setOther] = useState(stops.length - 1);
  const [name, setName] = useState("Point proposé");
  const [actor, setActor] = useState<Actor | null>(null);
  const [proposal, setProposal] = useState<SimProposedStop | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const changeRole = (next: SimProposedStop["role"]) => {
    setRole(next);
    setOther(next === "boarding" ? stops.length - 1 : 0);
    setProposal(null);
  };

  const evaluate = async () => {
    setBusy(true);
    setError(null);
    try {
      let passenger = actor;
      if (!passenger) {
        passenger = await createActor("passenger");
        useSimStore.getState().addPassenger(passenger);
        setActor(passenger);
      }
      setProposal(await previewProposal(passenger, trip.id, role, point, name));
    } catch (err) {
      setProposal(null);
      setError(errorMessage(err));
      useSimStore.getState().addLog("error", `Point proposé refusé : ${errorMessage(err)}`);
    } finally {
      setBusy(false);
    }
  };

  const book = async () => {
    if (!actor || !proposal) return;
    setBusy(true);
    const ok = await run(
      `${actor.full_name} propose de ${role === "boarding" ? "monter" : "descendre"} à ${proposal.name}`,
      () => bookWithProposal(actor, trip.id, proposal, stops[other].id),
      "Demande envoyée au chauffeur, avec le détour.",
    );
    setBusy(false);
    if (ok) {
      refresh();
      onClose();
    }
  };

  return (
    <div className="rounded-sm border border-primary/40 bg-primary-surface/40 p-3 flex flex-col gap-2 text-sm">
      <div className="flex items-center justify-between">
        <span className="font-medium text-ink-primary">Point proposé par un passager</span>
        <button type="button" onClick={onClose} className="text-ink-muted hover:text-ink-primary" aria-label="Fermer">
          <X size={16} />
        </button>
      </div>
      <Input value={name} onChange={(e) => { setName(e.target.value); setProposal(null); }} />
      <div className="grid grid-cols-2 gap-2">
        <Select value={role} onChange={(e) => changeRole(e.target.value as SimProposedStop["role"])}>
          <option value="boarding">Il monte ici</option>
          <option value="alighting">Il descend ici</option>
        </Select>
        <Select value={other} onChange={(e) => { setOther(Number(e.target.value)); setProposal(null); }}>
          {stops.map((_, i) => (
            <option key={i} value={i}>
              {role === "boarding" ? "Descend à " : "Monte à "}
              {stopLabel(stops, i)}
            </option>
          ))}
        </Select>
      </div>
      {proposal && (
        <div className="rounded-sm bg-surface p-2 text-xs text-ink-primary">
          Entre les arrêts {stops.find((s) => s.id === proposal.after_stop_id)?.name ?? "?"} et le suivant · détour d'environ{" "}
          <b>{proposal.detour_minutes} min</b> · passage vers {clock(proposal.scheduled_at)} · prix depuis le départ{" "}
          {formatXof(proposal.price_from_origin)}
        </div>
      )}
      {error && <div className="text-xs text-danger">{error}</div>}
      <div className="flex gap-2">
        <Button variant="secondary" disabled={busy} onClick={evaluate}>
          Évaluer le détour
        </Button>
        <Button disabled={busy || !proposal} onClick={book}>
          Réserver avec ce point
        </Button>
      </div>
      {!scenario.driver && <p className="text-xs text-ink-muted">Le vrai chauffeur verra la demande dans son appli.</p>}
    </div>
  );
}

function BookingRow({
  booking: b,
  scenario,
  trip,
  sendNow,
}: {
  booking: SimBooking;
  scenario: Scenario;
  trip: SimTrip | null;
  sendNow: () => Promise<boolean>;
}) {
  const now = useNow(1000);
  const sharing = useSimStore((s) => s.sharing[b.id] ?? false);
  const actor = scenario.passengers.find((p) => p.id === b.passenger_id) ?? null;
  const driver = scenario.driver;
  const name = b.passenger?.full_name ?? actor?.full_name ?? "Passager";
  const proposal = b.proposed_stop && !b.proposed_stop.inserted_stop_id ? b.proposed_stop : null;
  const from = b.boarding_stop?.name ?? (proposal?.role === "boarding" ? `${proposal.name} (proposé)` : "?");
  const to = b.alighting_stop?.name ?? (proposal?.role === "alighting" ? `${proposal.name} (proposé)` : "?");
  const active = b.status === "confirmed" && !b.started_at;
  // Le compte à rebours d'attente, comme dans les deux applis.
  const stop = trip?.stops.find((s) => s.id === b.boarding_stop_id) ?? null;
  const left = active && trip && stop ? driverLeft(trip, stop) : false;
  const waitUntil = active && !left && stop?.wait_until ? new Date(stop.wait_until).getTime() : null;

  const asDriver = (label: string, path: string, body?: unknown, success?: string) =>
    driver ? run(label, () => actorFetch(driver.token, path, { method: "POST", body }), success) : Promise.resolve(false);
  const asPassenger = (label: string, path: string, method = "POST", body?: unknown, success?: string) =>
    actor ? run(label, () => actorFetch(actor.token, path, { method, body }), success) : Promise.resolve(false);

  const toggleShare = async () => {
    const spot = passengerSpot(b);
    if (!sharing && spot) {
      const ok = await asPassenger(`${name} partage sa position`, `/bookings/${b.id}/location`, "POST", { lat: spot[0], lng: spot[1] });
      if (ok) useSimStore.getState().setSharing(b.id, true);
    } else if (sharing) {
      await asPassenger(`${name} arrête de partager sa position`, `/bookings/${b.id}/location`, "DELETE");
      useSimStore.getState().setSharing(b.id, false);
    }
  };

  const declareAbsent = async () => {
    // Comme l'appli : une position fraîche juste avant la déclaration.
    await sendNow();
    await asDriver(`Déclarer ${name} absent`, `/bookings/${b.id}/no-show`, undefined, `${name} est déclaré absent.`);
  };

  return (
    <div className="py-2.5 flex flex-col gap-1.5">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="font-medium text-sm text-ink-primary truncate">
            {name} {!actor && <span className="text-xs font-normal text-primary">· vrai compte</span>}
          </div>
          <div className="text-xs text-ink-secondary">
            {from} → {to} · {formatXof(b.price_charged)} · code {b.departure_code}
          </div>
        </div>
        <Badge tone={BOOKING_STATUS_TONE[b.status]}>{b.started_at && b.status === "confirmed" ? "À bord" : BOOKING_STATUS_LABEL[b.status]}</Badge>
      </div>

      {proposal && (
        <div className="text-xs text-ink-primary rounded-sm bg-primary-surface px-2 py-1">
          Nouvel arrêt proposé : {proposal.name} · détour d'environ {proposal.detour_minutes} min
        </div>
      )}
      {left && (
        <div className="text-xs text-danger">
          Le chauffeur est reparti de {stop?.name} sans ce passager
          {stop?.wait_until && new Date(stop.wait_until).getTime() > now ? `, avant la fin de l'attente (${clock(stop.wait_until)})` : ""}.
        </div>
      )}
      {waitUntil !== null && (
        <div className={`text-xs ${waitUntil > now ? "text-ink-primary" : "text-danger"}`}>
          {waitUntil > now
            ? `Le chauffeur attend à ${stop?.name} jusqu'à ${clock(stop?.wait_until)} (encore ${countdown(waitUntil - now)}).`
            : `Délai d'attente écoulé à ${stop?.name} : l'absence peut être déclarée.`}
        </div>
      )}
      {b.passenger_reliability && (
        <div className="text-xs text-ink-muted">
          Fiable à {b.passenger_reliability.honored_pct} % · {b.passenger_reliability.no_show_count} absence(s)
        </div>
      )}

      <div className="flex flex-wrap gap-1.5">
        {driver && b.status === "pending_driver" && (
          <>
            <SmallButton onClick={() => asDriver(`Accepter ${name}`, `/bookings/${b.id}/accept`, undefined, `${name} accepté.`)}>
              Accepter
            </SmallButton>
            <SmallButton onClick={() => asDriver(`Refuser ${name}`, `/bookings/${b.id}/reject`, undefined, `${name} refusé.`)}>
              Refuser
            </SmallButton>
          </>
        )}
        {driver && active && (
          <>
            <SmallButton
              onClick={() =>
                asDriver(`Scanner le billet de ${name}`, `/trips/${scenario.tripId}/board-passenger`, { code: b.departure_code }, `${name} validé à bord.`)
              }
            >
              Valider à bord
            </SmallButton>
            <SmallButton onClick={declareAbsent}>Déclarer absent</SmallButton>
          </>
        )}
        {actor && active && (
          <SmallButton onClick={toggleShare}>{sharing ? "Arrêter le partage" : "Partager sa position"}</SmallButton>
        )}
        {actor && (b.status === "pending_driver" || active) && (
          <SmallButton onClick={() => asPassenger(`${name} annule`, `/bookings/${b.id}/cancel`, "POST", undefined, "Réservation annulée par le passager.")}>
            Annuler (passager)
          </SmallButton>
        )}
      </div>
    </div>
  );
}

function SmallButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="h-7 px-2 rounded-sm border border-line bg-surface text-xs font-medium text-ink-primary hover:bg-bg"
    >
      {children}
    </button>
  );
}
