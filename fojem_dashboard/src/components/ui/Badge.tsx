import type { ReactNode } from "react";
import { cn } from "../../lib/utils";

type BadgeTone = "neutral" | "success" | "danger" | "primary";

const TONE_CLASSES: Record<BadgeTone, string> = {
  neutral: "bg-line/40 text-ink-secondary",
  success: "bg-success-surface text-success",
  danger: "bg-danger-surface text-danger",
  primary: "bg-primary-surface text-primary",
};

export function Badge({
  tone = "neutral",
  className,
  children,
}: {
  tone?: BadgeTone;
  className?: string;
  children: ReactNode;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-sm px-2 py-0.5 text-xs font-medium",
        TONE_CLASSES[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}
