import type { ReactNode } from "react";
import { X } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";

export function Modal({
  open,
  onClose,
  title,
  size = "md",
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  /** "lg" pour les contenus riches (ex. revue de documents avec aperçus). */
  size?: "md" | "lg";
  children: ReactNode;
}) {
  return (
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center px-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
            className="absolute inset-0 bg-ink-primary/40"
            onClick={onClose}
          />
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            transition={{ duration: 0.15 }}
            className={`relative bg-surface rounded-md shadow-card border border-line w-full ${
              size === "lg" ? "max-w-3xl" : "max-w-lg"
            } max-h-[85vh] overflow-y-auto`}
          >
            <div className="flex items-center justify-between px-5 h-14 border-b border-line shrink-0">
              <h2 className="text-sm font-semibold text-ink-primary">{title}</h2>
              <button onClick={onClose} className="text-ink-muted hover:text-ink-primary">
                <X size={18} />
              </button>
            </div>
            <div className="p-5">{children}</div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}
