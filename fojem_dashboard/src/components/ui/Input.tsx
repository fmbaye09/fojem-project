import type { InputHTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "h-9 px-3 rounded-sm border border-line bg-surface text-sm text-ink-primary outline-none focus:border-primary transition-colors placeholder:text-ink-muted",
        className,
      )}
      {...props}
    />
  );
}
