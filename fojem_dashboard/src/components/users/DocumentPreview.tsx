import { useEffect, useState } from "react";
import { ExternalLink, FileText, RotateCw } from "lucide-react";
import { apiFetchBlob, ApiError } from "../../lib/api";
import { Skeleton } from "../ui/Skeleton";

// `key` identifie la requête à laquelle l'état se rapporte : tant qu'il ne
// correspond pas à la requête courante, on affiche le chargement (évite un
// setState synchrone dans l'effet).
type PreviewState =
  | { key: string; kind: "error"; message: string }
  | { key: string; kind: "ready"; url: string; mime: string };

/**
 * Aperçu d'un document chauffeur. L'endpoint fichier exige le Bearer token
 * admin : on le télécharge en Blob via apiFetchBlob() puis on l'affiche via
 * un object URL, révoqué au démontage (fermeture de la modale) ou quand le
 * fichier change, pour ne pas garder les blobs en mémoire.
 */
export function DocumentPreview({ fileEndpoint, alt }: { fileEndpoint: string; alt: string }) {
  const [state, setState] = useState<PreviewState | null>(null);
  const [attempt, setAttempt] = useState(0);
  const requestKey = `${fileEndpoint}#${attempt}`;

  useEffect(() => {
    const controller = new AbortController();
    let objectUrl: string | null = null;

    apiFetchBlob(fileEndpoint, { signal: controller.signal })
      .then((blob) => {
        if (controller.signal.aborted) return;
        objectUrl = URL.createObjectURL(blob);
        setState({ key: requestKey, kind: "ready", url: objectUrl, mime: blob.type });
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        setState({
          key: requestKey,
          kind: "error",
          message: err instanceof ApiError ? err.message : "Aperçu indisponible.",
        });
      });

    return () => {
      controller.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [fileEndpoint, requestKey]);

  if (!state || state.key !== requestKey) {
    return <Skeleton className="h-44 w-full rounded-sm" />;
  }

  if (state.kind === "error") {
    return (
      <div className="h-44 w-full rounded-sm border border-dashed border-line flex flex-col items-center justify-center gap-2 text-center px-3">
        <span className="text-xs text-danger">{state.message}</span>
        <button
          type="button"
          onClick={() => setAttempt((a) => a + 1)}
          className="inline-flex items-center gap-1 text-xs font-medium text-ink-secondary hover:text-ink-primary"
        >
          <RotateCw size={12} /> Réessayer
        </button>
      </div>
    );
  }

  if (state.mime.startsWith("image/")) {
    return (
      <a href={state.url} target="_blank" rel="noopener noreferrer" title="Ouvrir en taille réelle" className="block">
        <img src={state.url} alt={alt} className="h-44 w-full rounded-sm border border-line bg-bg object-contain" />
      </a>
    );
  }

  const isPdf = state.mime === "application/pdf";
  return (
    <div className="h-44 w-full rounded-sm border border-line bg-bg flex flex-col items-center justify-center gap-2">
      <FileText size={28} strokeWidth={1.5} className="text-ink-muted" />
      <a
        href={state.url}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
      >
        {isPdf ? "Voir le PDF" : "Ouvrir le fichier"} <ExternalLink size={12} />
      </a>
    </div>
  );
}
