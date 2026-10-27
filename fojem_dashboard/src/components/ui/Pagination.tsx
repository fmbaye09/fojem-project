import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "./Button";

export function Pagination({
  page,
  lastPage,
  total,
  onChange,
}: {
  page: number;
  lastPage: number;
  total: number;
  onChange: (page: number) => void;
}) {
  if (lastPage <= 1) return null;
  return (
    <div className="flex items-center justify-between pt-3">
      <span className="text-xs text-ink-muted">{total} résultat{total > 1 ? "s" : ""}</span>
      <div className="flex items-center gap-2">
        <Button variant="secondary" disabled={page <= 1} onClick={() => onChange(page - 1)}>
          <ChevronLeft size={15} />
        </Button>
        <span className="text-xs text-ink-secondary">
          Page {page} / {lastPage}
        </span>
        <Button variant="secondary" disabled={page >= lastPage} onClick={() => onChange(page + 1)}>
          <ChevronRight size={15} />
        </Button>
      </div>
    </div>
  );
}
