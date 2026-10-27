import type { LucideIcon } from "lucide-react";
import { Card } from "./Card";
import { cn } from "../../lib/utils";

interface Props {
  label: string;
  value: string | number;
  icon: LucideIcon;
  tone?: "default" | "danger" | "success";
  hint?: string;
}

const TONE_ICON: Record<NonNullable<Props["tone"]>, string> = {
  default: "bg-primary-surface text-primary",
  danger: "bg-danger-surface text-danger",
  success: "bg-success-surface text-success",
};

/** Une carte = une question précise, une réponse immédiate. Pas de métrique décorative. */
export function StatTile({ label, value, icon: Icon, tone = "default", hint }: Props) {
  return (
    <Card className="p-4 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-sm text-ink-secondary">{label}</span>
        <div className={cn("w-8 h-8 rounded-sm flex items-center justify-center shrink-0", TONE_ICON[tone])}>
          <Icon size={16} strokeWidth={2} />
        </div>
      </div>
      <div className="text-2xl font-semibold text-ink-primary leading-none">{value}</div>
      {hint && <div className="text-xs text-ink-muted">{hint}</div>}
    </Card>
  );
}
