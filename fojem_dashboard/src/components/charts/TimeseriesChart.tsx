import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { ChartTooltip } from "./ChartTooltip";

export interface TimeseriesPoint {
  date: string;
  value: number;
}

/**
 * Courbe d'évolution "soft", une seule série. Trajets/jour et revenu/jour ont
 * des échelles totalement différentes (unités et ordres de grandeur) : les
 * combiner sur un même axe, ou ajouter un second axe, déformerait l'une des
 * deux courbes (anti-pattern classique) — donc deux petits graphiques
 * honnêtes plutôt qu'un seul trompeur. Axe Y toujours ancré à 0.
 */
export function TimeseriesChart({
  data,
  color,
  name,
  valueFormatter,
}: {
  data: TimeseriesPoint[];
  color: string;
  name: string;
  valueFormatter?: (v: number) => string;
}) {
  const gradientId = `fill-${name.replace(/\s+/g, "-")}`;
  return (
    <ResponsiveContainer width="100%" height={200}>
      <AreaChart data={data} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.12} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid vertical={false} stroke="#E8E6E0" />
        <XAxis
          dataKey="date"
          tick={{ fontSize: 11, fill: "#A0A09A" }}
          axisLine={{ stroke: "#E8E6E0" }}
          tickLine={false}
          minTickGap={24}
        />
        <YAxis
          tick={{ fontSize: 11, fill: "#A0A09A" }}
          axisLine={false}
          tickLine={false}
          width={40}
          domain={[0, "auto"]}
          tickFormatter={valueFormatter}
        />
        <Tooltip content={<ChartTooltip />} />
        <Area
          type="monotone"
          dataKey="value"
          name={name}
          stroke={color}
          strokeWidth={2}
          fill={`url(#${gradientId})`}
          dot={false}
          activeDot={{ r: 4, strokeWidth: 2, stroke: "#FFFFFF" }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
