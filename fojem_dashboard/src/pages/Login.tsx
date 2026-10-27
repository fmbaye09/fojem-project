import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { useAuthStore } from "../store/useAuthStore";
import { Button } from "../components/ui/Button";

export function Login() {
  const login = useAuthStore((s) => s.login);
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      await login(email, password);
      navigate("/", { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Connexion impossible.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-bg flex">
      {/* Panneau de marque — rempli l'espace sur grand écran, masqué sur mobile.
          Couleur pleine plutôt que dégradé/motif : discret, pas décoratif. */}
      <div className="hidden lg:flex lg:w-[46%] xl:w-2/5 bg-primary flex-col justify-between p-16 text-white">
        <div className="w-11 h-11 rounded-md bg-white/15 flex items-center justify-center text-white text-lg font-semibold">
          F
        </div>
        <div>
          <h1 className="text-4xl font-semibold leading-tight">FOJËM Admin</h1>
          <p className="text-white/80 text-base mt-4 max-w-sm">
            Vue d'ensemble, finance, modération et statistiques de la plateforme de
            covoiturage interurbain FOJËM.
          </p>
        </div>
        <p className="text-white/50 text-xs">
          Accès réservé aux comptes administrateurs FOJËM.
        </p>
      </div>

      {/* Formulaire */}
      <div className="flex-1 flex items-center justify-center px-6 py-12">
        <div className="w-full max-w-md">
          <div className="flex flex-col items-center lg:items-start mb-10">
            <div className="w-11 h-11 rounded-md bg-primary flex items-center justify-center text-white text-lg font-semibold mb-4 lg:hidden">
              F
            </div>
            <h1 className="text-2xl font-semibold text-ink-primary">Connexion</h1>
            <p className="text-sm text-ink-secondary mt-1.5">
              Entrez vos identifiants administrateur pour accéder au tableau de bord.
            </p>
          </div>

          <form onSubmit={handleSubmit} className="bg-surface border border-line rounded-md shadow-card p-8 flex flex-col gap-5">
            <div className="flex flex-col gap-1.5">
              <label htmlFor="email" className="text-sm font-medium text-ink-primary">
                Adresse e-mail
              </label>
              <input
                id="email"
                type="email"
                autoComplete="username"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="h-11 px-3.5 rounded-sm border border-line bg-bg text-sm text-ink-primary outline-none focus:border-primary transition-colors"
                placeholder="admin@fojem.sn"
              />
            </div>

            <div className="flex flex-col gap-1.5">
              <label htmlFor="password" className="text-sm font-medium text-ink-primary">
                Mot de passe
              </label>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="h-11 px-3.5 rounded-sm border border-line bg-bg text-sm text-ink-primary outline-none focus:border-primary transition-colors"
                placeholder="••••••••"
              />
            </div>

            {error && (
              <div className="text-sm text-danger bg-danger-surface rounded-sm px-3 py-2">{error}</div>
            )}

            <Button type="submit" disabled={loading} className="w-full mt-1 h-11">
              {loading ? <Loader2 size={16} className="animate-spin" /> : "Se connecter"}
            </Button>
          </form>
        </div>
      </div>
    </div>
  );
}
