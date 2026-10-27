import { Bar, BarChart, Cell, LabelList, ResponsiveContainer, XAxis, YAxis } from "recharts";

export interface CategoryDatum {
  key: string;
  label: string;
  value: number;
  color: string;
}

/**
 * Barres horizontales pour une répartition par catégorie (statut, méthode,
 * type...) — préférées au camembert : comparaison de longueurs plus honnête
 * que la comparaison d'angles, et les noms de statut FOJËM sont longs.
 * Étiquettes de valeur directes sur chaque barre (obligatoire : 3 des 6
 * couleurs de la palette catégorielle sont sous 3:1 de contraste sur fond
 * clair — voir chartColors.ts — donc jamais la couleur seule comme porteuse
 * d'information).
 */
export function CategoryBarChart({ data }: { data: CategoryDatum[] }) {
  const height = Math.max(data.length * 36 + 8, 60);
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart
        data={data}
        layout="vertical"
        margin={{ top: 4, right: 36, left: 4, bottom: 4 }}
        barCategoryGap={10}
      >
        <XAxis type="number" hide domain={[0, "dataMax"]} />
        <YAxis
          type="category"
          dataKey="label"
          width={140}
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 12, fill: "#5B5B58" }}
        />
        <Bar dataKey="value" radius={[0, 4, 4, 0]} maxBarSize={20} isAnimationActive={false}>
          {data.map((d) => (
            <Cell key={d.key} fill={d.color} />
          ))}
          <LabelList
            dataKey="value"
            position="right"
            formatter={(v: unknown) => (typeof v === "number" ? v.toLocaleString("fr-FR") : String(v ?? ""))}
            style={{ fontSize: 12, fill: "#0B2A47", fontWeight: 500 }}
          />
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
