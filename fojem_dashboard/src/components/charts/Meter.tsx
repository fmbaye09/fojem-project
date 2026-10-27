/**
 * Jauge simple pour un ratio unique contre son total (ex. taux
 * d'acceptation) — piste + remplissage dans la même rampe de couleur,
 * jamais un camembert à 2 tranches pour une seule proportion. Le
 * dénominateur reste toujours visible à côté du pourcentage : un
 * pourcentage nu sans base peut tromper (voir anti-patterns du skill
 * dataviz).
 */
export function Meter({
  ratio,
  color = "#EA671A",
}: {
  /** 0..1, ou null si aucune donnée pour la période. */
  ratio: number | null;
  color?: string;
}) {
  const pct = ratio === null ? 0 : Math.max(0, Math.min(1, ratio)) * 100;
  return (
    <div className="w-full h-2 rounded-sm bg-line overflow-hidden" role="presentation">
      <div
        className="h-full rounded-sm transition-[width]"
        style={{ width: `${pct}%`, backgroundColor: color }}
      />
    </div>
  );
}
