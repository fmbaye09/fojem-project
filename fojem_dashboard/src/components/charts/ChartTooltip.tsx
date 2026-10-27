interface TooltipPayloadEntry {
  name?: string;
  value?: number;
  color?: string;
}

interface ChartTooltipProps {
  active?: boolean;
  payload?: TooltipPayloadEntry[];
  label?: string;
}

/** Tooltip sobre partagé par tous les graphiques — texte en tokens ink, jamais dans la couleur de série. */
export function ChartTooltip({ active, payload, label }: ChartTooltipProps) {
  if (!active || !payload || payload.length === 0) return null;
  return (
    <div className="bg-surface border border-line rounded-sm shadow-card px-3 py-2 text-xs">
      <div className="text-ink-muted mb-1">{label}</div>
      {payload.map((entry, i) => (
        <div key={entry.name ?? i} className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full shrink-0" style={{ background: entry.color }} />
          <span className="text-ink-secondary">{entry.name}</span>
          <span className="text-ink-primary font-medium ml-auto">{entry.value?.toLocaleString("fr-FR")}</span>
        </div>
      ))}
    </div>
  );
}
