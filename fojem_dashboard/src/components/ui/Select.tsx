import type { SelectHTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        "h-9 px-2.5 rounded-sm border border-line bg-surface text-sm text-ink-primary outline-none focus:border-primary transition-colors",
        className,
      )}
      {...props}
    />
  );
}
