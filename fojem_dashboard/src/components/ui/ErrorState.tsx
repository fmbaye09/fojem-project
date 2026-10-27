import { AlertTriangle } from "lucide-react";

/** Message d'erreur honnête et lisible — jamais de stack trace technique affichée. */
export function ErrorState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 py-16 text-center">
      <AlertTriangle size={26} strokeWidth={1.5} className="text-danger mb-1" />
      <p className="text-sm font-medium text-ink-primary">Une erreur est survenue</p>
      <p className="text-sm text-ink-secondary max-w-sm">{message}</p>
    </div>
  );
}
