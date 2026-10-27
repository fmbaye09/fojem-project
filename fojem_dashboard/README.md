# FOJËM Admin — tableau de bord

Tableau de bord d'administration pour FOJËM, plateforme de covoiturage
interurbain sénégalaise. Consomme l'API admin (`/api/admin/*`) du backend
Laravel `fojem_backend` — aucune donnée mockée, aucun endpoint recréé côté
frontend.

## Stack

React 18 + TypeScript + Vite, Tailwind CSS (tokens de la charte FOJËM),
`react-router-dom`, Zustand (état global + auth persistée), `recharts`
(graphiques), `framer-motion` (transitions discrètes), `lucide-react`
(icônes), `react-leaflet` + OpenStreetMap (cartographie, cohérent avec les
apps mobiles Passager/Chauffeur qui utilisent déjà OSM/Nominatim).

## Lancer en local

### 1. Backend

Le dashboard consomme l'API réelle : le backend `fojem_backend` doit tourner.

```bash
cd ../fojem_backend
# Option 1 (100% Docker recommandée) :
docker compose up -d   # lance PostgreSQL et l'API Laravel sur le port 8000

# Option 2 (PHP local) :
docker compose up -d db
php artisan serve      # sert l'API sur http://127.0.0.1:8000
```

Comptes de démonstration créés par le seeder backend :
`super_admin@fojem.sn` / `support@fojem.sn` / `finance@fojem.sn`, mot de
passe `password`.

CORS : `fojem_backend/config/cors.php` autorise explicitement
`http://localhost:5173` et `http://127.0.0.1:5173` (origine par défaut de
Vite en dev). Si vous changez le port du dashboard, ajoutez la nouvelle
origine à `allowed_origins` dans ce fichier.

### 2. Dashboard

```bash
npm install
cp .env.example .env   # ajuster VITE_API_BASE_URL si besoin
npm run dev
```

Ouvre `http://localhost:5173`. Se connecter avec un des comptes ci-dessus.

### Variables d'environnement

| Variable | Description | Défaut |
|---|---|---|
| `VITE_API_BASE_URL` | URL de base du backend Laravel, sans `/api` final | `http://127.0.0.1:8000` |

## Écrans

- `/login` — connexion admin (Bearer token Sanctum, guard `admin` séparé du guard utilisateur mobile).
- `/` — vue d'ensemble : chiffres clés, courbes trajets/revenu, répartition
  des trajets par statut, des chauffeurs par statut de vérification et des
  réservations de la semaine par statut (barres horizontales, palette
  catégorielle validée — voir `src/lib/chartColors.ts`). Contient aussi
  l'emplacement UI pour les téléchargements par app (Passager/Chauffeur),
  volontairement en état vide honnête — voir « Téléchargements par
  application » ci-dessous.
- `/map` — cartographie (contexte OSM + agrégats par statut ; voir limite documentée dans l'écran : pas de liste de trajets géolocalisés côté API admin actuelle).
- `/users` — utilisateurs et chauffeurs (statut de compte, documents, vérification).
- `/finance` — transactions et demandes de retrait.
- `/moderation` — alertes SOS et litiges.
- `/stats` — évolution, taux d'acceptation (avec jauge et dénominateur visible), note moyenne.
- `/administration` — comptes admin, rôles (lecture seule), tarifs plateforme.

## RBAC frontend

La sidebar et les actions d'écriture sont filtrées par les permissions
réelles de l'admin connecté (`GET /admin/auth/me`), pas seulement laissées
au backend : un admin sans `users.edit` ne voit pas les boutons d'action sur
la page Utilisateurs, même si le backend les refuserait de toute façon.

## Build & déploiement

```bash
npm run build
```

Produit un export statique dans `dist/`. Le déploiement cible est un build
statique servi par Nginx sur le même serveur que le backend Laravel (reverse
proxy Nginx : `/` → fichiers statiques de `dist/`, `/api` → PHP-FPM/Laravel),
avec `VITE_API_BASE_URL` pointant vers l'URL publique de l'API en
production. Ce choix de déploiement est à valider avec l'équipe
infrastructure ; aucune configuration Nginx n'est incluse dans ce dépôt à ce
stade.

## Limites connues à valider

- **Cartographie** : pas de tracking GPS en temps réel — le backend n'expose
  pas d'endpoint de liste de trajets individuels avec coordonnées. La page
  `/map` le documente explicitement plutôt que de simuler un suivi live.
- **Paramètres tarifaires** : aucune zone n'est configurée par défaut dans
  les données de seed locales — l'écran affiche un état vide honnête tant
  qu'aucune zone n'a été créée côté backend.
- **Téléchargements par application** : FOJËM ne contrôle aucune source de
  cette donnée (ni la base Laravel, ni aucun autre système interne) — elle
  viendrait de l'API Google Play Console Developer Reporting, et les apps
  Passager/Chauffeur ne sont pas encore publiées sur le Play Store.
  L'écran `/` prévoit l'emplacement (une carte par app) avec un état vide
  explicite ; aucun appel réseau vers Google Play n'est fait dans cette
  passe, et aucun chiffre (y compris 0) n'est affiché tant que la source
  réelle n'est pas branchée.
- **Répartitions qui ne peuvent pas être calculées côté frontend sans
  fausser les chiffres** : certaines vues suggérées (transactions par
  méthode de paiement/par type, nouveaux comptes passagers/chauffeurs dans
  le temps) ne sont **pas** implémentées, faute d'agrégat backend adapté —
  les endpoints `GET /admin/transactions` et `GET /admin/users` sont
  paginés et ne renvoient qu'une page à la fois : les recalculer côté
  frontend à partir d'une page donnerait des proportions fausses dès que
  plus d'une page de données existe. Endpoints backend manquants pour aller
  plus loin honnêtement :
  - `GET /admin/stats/transactions-breakdown?from?&to?` — agrégat complet
    des transactions par `payment_method` et par `type` (comptages, pas de
    liste), sur le modèle de `/admin/stats/timeseries`.
  - `GET /admin/stats/new-accounts-timeseries?from?&to?` — nouveaux comptes
    par jour, groupés passager/chauffeur (`is_driver`), sur `created_at` —
    `GET /admin/users` n'a aujourd'hui aucun filtre de date exploitable pour
    ça.
