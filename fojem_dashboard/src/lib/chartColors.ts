// Palette catégorielle pour les répartitions par statut/catégorie (3 à 6
// classes). Validée avec le validateur du skill dataviz :
//
//   node scripts/validate_palette.js \
//     "#EA671A,#3D6FA8,#1baf7a,#eda100,#e87ba4,#4a3aa7" --mode light
//
// -> PASS sur les bandes de luminosité, le plancher de chroma, la
// séparation CVD (protan/deutan/tritan, paire adjacente la plus faible
// ΔE 9.1) et le plancher vision normale (ΔE 19.6). Le contraste sur le fond
// clair est en WARN pour 3 des 6 teintes (#1baf7a, #eda100, #e87ba4) —
// c'est légal uniquement si chaque graphique qui les utilise affiche aussi
// des étiquettes de valeur directes (jamais la couleur seule) : tous les
// graphiques de ce fichier le font. Pas de mode sombre : le dashboard n'en
// a pas (voir tailwind.config.js / absence de classes `dark:`), donc pas de
// second run de validation nécessaire.
//
// Slots 1 et 2 réutilisent les deux couleurs de série déjà validées lors de
// la première passe (primary orange, chart.secondary marine) — jamais de
// nouvelle teinte de marque introduite ici, seulement des compléments pour
// aller au-delà de 2 séries.
export const CATEGORICAL_COLORS = [
  "#EA671A", // 1 — orange FOJËM (primary)
  "#3D6FA8", // 2 — marine désaturé (chart.secondary)
  "#1BAF7A", // 3 — aqua
  "#EDA100", // 4 — jaune
  "#E87BA4", // 5 — magenta
  "#4A3AA7", // 6 — violet
] as const;

/**
 * Attribue une couleur à chaque entrée d'une liste de catégories fixes,
 * dans un ordre stable (jamais par rang/valeur) : la même clé de statut
 * obtient toujours la même couleur d'un rendu à l'autre, y compris quand
 * une catégorie a un compte de zéro ou est absente de la réponse API.
 */
export function colorForCategory(orderedKeys: readonly string[], key: string): string {
  const idx = orderedKeys.indexOf(key);
  return CATEGORICAL_COLORS[idx % CATEGORICAL_COLORS.length] ?? CATEGORICAL_COLORS[0];
}
