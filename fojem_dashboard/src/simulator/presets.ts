import type { PlannedPoint } from "./types";

// Itinéraires de test, avec de vrais points de rendez-vous (coordonnées
// des gares routières et péages importés d'OpenStreetMap).

const COLOBANE: PlannedPoint = { name: "Dakar", address: "Gare routière de Colobane", lat: 14.69793, lng: -17.44303 };
const THIES: PlannedPoint = { name: "Thiès", address: "Gare routière de Thiès", lat: 14.791, lng: -16.926 };

export interface RoutePreset {
  id: string;
  label: string;
  hint: string;
  points: PlannedPoint[];
}

export const ROUTE_PRESETS: RoutePreset[] = [
  {
    id: "dakar-thies",
    label: "Dakar → Rufisque → Thiès",
    hint: "≈ 70 km, le trajet de référence des tests",
    points: [COLOBANE, { name: "Rufisque", address: "Péage de Rufisque", lat: 14.716, lng: -17.273 }, THIES],
  },
  {
    id: "ville",
    label: "Trajet court en ville",
    hint: "≈ 20 km : Colobane → Patte d'Oie → Pikine → Keur Massar",
    points: [
      COLOBANE,
      { name: "Patte d'Oie", address: "Niokolo Transport, Patte d'Oie", lat: 14.74642, lng: -17.42445 },
      { name: "Pikine", address: "Gare routière de Pikine", lat: 14.74361, lng: -17.40238 },
      { name: "Keur Massar", address: "Gare routière de Keur Massar", lat: 14.76984, lng: -17.3184 },
    ],
  },
  {
    id: "dakar-mbour",
    label: "Dakar → Diamniadio → Mbour",
    hint: "≈ 85 km par l'autoroute à péage",
    points: [
      COLOBANE,
      { name: "Diamniadio", address: "Gare routière de Diamniadio", lat: 14.72038, lng: -17.18271 },
      { name: "Mbour", address: "Gare routière de Mbour", lat: 14.42591, lng: -16.97173 },
    ],
  },
  {
    id: "dakar-touba",
    label: "Dakar → Thiès → Touba",
    hint: "≈ 190 km",
    points: [COLOBANE, THIES, { name: "Touba", address: "Gare routière de Touba", lat: 14.82108, lng: -15.90538 }],
  },
  {
    id: "dakar-saint-louis",
    label: "Dakar → Tivaouane → Kébémer → Saint-Louis",
    hint: "≈ 260 km, quatre points de rendez-vous",
    points: [
      COLOBANE,
      { name: "Tivaouane", address: "Gare routière de Tivaouane", lat: 14.9424, lng: -16.82466 },
      { name: "Kébémer", address: "Gare routière de Kébémer", lat: 15.36266, lng: -16.45653 },
      { name: "Saint-Louis", address: "Gare routière de Saint-Louis", lat: 16.0239, lng: -16.49406 },
    ],
  },
];
