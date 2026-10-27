import type { LucideIcon } from "lucide-react";

export function EmptyState({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description?: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 py-16 text-center">
      <Icon size={28} strokeWidth={1.5} className="text-ink-muted mb-1" />
      <p className="text-sm font-medium text-ink-primary">{title}</p>
      {description && <p className="text-sm text-ink-secondary max-w-sm">{description}</p>}
    </div>
  );
}
