# FOJEM Backend

Backend Laravel pour FOJEM, plateforme de covoiturage interurbain senegalaise.
Heberge la base de donnees reelle, l'algorithme de matching (FOJEM Match) et
sert de socle a un futur tableau de bord admin. Les deux applications Flutter
(Passager, Chauffeur) consomment cette API a la place de Firebase Firestore
pour tout sauf le **chat** et les **appels vocaux WebRTC**, qui restent geres
cote Firebase/Firestore et sont hors perimetre de ce backend.

## Stack

- PHP 8.3, Laravel 12
- PostgreSQL 16 + PostGIS 3.4 (donnees geospatiales : positions, itineraires)
- Laravel Sanctum (auth API par token Bearer)
- `kreait/firebase-php` (SDK Firebase Admin) : génère les tokens personnalisés pour la synchronisation du chat Firestore et gère les notifications push Firebase Cloud Messaging (FCM HTTP v1).
- Docker & Docker Compose (API Laravel + Base de données PostgreSQL/PostGIS conteneurisées).

## Démarrage Local

### Méthode 1 : 100% Docker (Recommandée)

Aucune installation locale de PHP ou Composer n'est requise, tout tourne dans des conteneurs isolés.

#### 1. Prérequis
- **Docker Desktop** démarré.

#### 2. Démarrage des conteneurs
À la racine de `fojem_backend` :

```bash
# Lance PostgreSQL/PostGIS (port 55432) et l'API Laravel (port 8000)
docker compose up -d
```

Vérifier que les conteneurs sont sains :
```bash
docker ps
# Vous devez voir 'fojem_backend' (port 8000->8000) et 'fojem_db' (port 55432->5432)
```

#### 3. Initialisation de la Base de Données (Premier lancement)

```bash
# Générer la clé d'application si nécessaire
docker exec fojem_backend php artisan key:generate

# Exécuter les migrations et le jeu de données démo
docker exec fojem_backend php artisan migrate --seed
```

L'API est immédiatement active et joignable sur `http://localhost:8000/api` (et sur votre réseau local).

---

### Méthode 2 : PHP Local + Base de données Docker

Si vous préférez exécuter le serveur PHP directement sur votre système d'exploitation hôte :

#### 1. Prérequis
- PHP 8.3+ avec extensions `pdo_pgsql` et `pgsql`.
- Docker Desktop pour la base PostGIS.
- Composer.

#### 2. Lancer la base de données
```bash
docker compose up -d db
docker compose exec db pg_isready -U fojem -d fojem
```

Le service `db` expose Postgres sur le port **55432** de votre machine hôte.
Credentials : `host: 127.0.0.1`, `port: 55432`, `database: fojem`, `user: fojem`, `password: fojem_local_dev`.

#### 3. Installation et lancement local
```bash
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan serve
```

---

### Jeu de données initial (Seeder)

Le seeder crée automatiquement :
- 3 rôles admin (`super_admin`, `support`, `finance`) avec un compte par rôle :
  - `super_admin@fojem.sn` / `password`
  - `support@fojem.sn` / `password`
  - `finance@fojem.sn` / `password`
- Un chauffeur de test vérifié : `demo.driver@fojem.sn` / `password` (avec véhicule Renault Logan et trajet ouvert Dakar Plateau → Ouakam).
- Une passagère de test : `demo.passenger@fojem.sn` / `password` (avec un portefeuille crédité de 5 000 FCFA).
  `support@fojem.sn` / `finance@fojem.sn`, mot de passe `password`).
- Un chauffeur demo approuve (`demo.driver@fojem.sn` / `password`) avec un
  vehicule et un trajet ouvert (Plateau -> Ouakam, Dakar).
- Une passagere demo (`demo.passenger@fojem.sn` / `password`).

### 3bis. Firebase (chat) — cle de service

Le chat (et les appels vocaux WebRTC) restent geres par Firebase/Firestore,
hors perimetre de ce backend — voir l'introduction. Pour que les 2 apps
Flutter puissent se connecter a Firebase Auth avec le **meme identifiant**
que leur compte Laravel (`users.id`, un UUID) et donc continuer a satisfaire
les regles de securite Firestore basees sur `request.auth.uid`, ce backend
mine un jeton Firebase personnalise ("custom token") a chaque
login/register, via le SDK Firebase Admin (`kreait/firebase-php`,
`app/Services/FirebaseTokenService.php`).

Pour cela, une cle de compte de service Firebase (JSON, telechargeable
depuis la console Firebase > Parametres du projet > Comptes de service >
"Generer une nouvelle cle privee") doit etre placee a :

```
storage/app/secrets/firebase-adminsdk.json
```

Ce fichier est un **secret** : `storage/app/secrets/` est dans
`.gitignore` et ne doit jamais etre committe. Il n'existe pas par defaut
sur une nouvelle installation — c'est normal, il doit etre copie
manuellement par chaque developpeur/environnement.

**Ce champ n'est jamais bloquant.** Si le fichier de cle est absent (ou si
la generation du jeton echoue pour une autre raison), `login`/`register`
continuent de fonctionner normalement pour l'authentification Sanctum :
`FirebaseTokenService::mintCustomToken()` logue un `Log::warning` et
retourne `null`, et la reponse JSON contient simplement
`firebase_custom_token: null` au lieu de faire echouer toute la requete.

### 4. Lancer le serveur

```bash
php artisan serve
```

L'API est servie sur `http://127.0.0.1:8000/api`.

### 5. Tests

Les tests tournent contre une vraie base Postgres/PostGIS (`fojem_test`,
sqlite ne supporte pas `geography`/`ST_*`). Creer la base une fois :

```bash
docker compose exec db psql -U fojem -d fojem -c "CREATE DATABASE fojem_test;"
```

Puis :

```bash
php artisan test
```

Etat actuel : **43 tests, 129 assertions, tous verts** (auth (dont la
presence de `firebase_custom_token` dans les reponses), vehicules
(declaration multiple, immuabilite apres creation, unicite de plaque),
publication de trajet + verification de propriete du vehicule + recherche
geo + coordonnees exposees sur `mine`/`show`, reservation + acceptation
chauffeur, visibilite des reservations cote chauffeur, credit automatique
du wallet chauffeur a la completion d'une reservation, profils publics,
calcul du score de matching, auth admin + abilities, gestion
utilisateurs/documents chauffeur, traitement d'un retrait).

## Endpoints API

Base URL : `/api`. Toutes les routes protegees attendent un header
`Authorization: Bearer <token>` (token Sanctum obtenu via login/register) et
`Accept: application/json`.

### Auth (`/api/auth`)

| Methode | URL | Body | Description |
|---|---|---|---|
| POST | `/auth/register` | `full_name, email, password, phone_number, gender, language?` | Cree le compte + son wallet. Throttle 10/min. |
| POST | `/auth/login` | `email, password` | Retourne `{ user, token, firebase_custom_token }`. Throttle 10/min. |
| POST | `/auth/logout` | - | Revoque le token courant. Auth requise. |
| GET | `/auth/me` | - | Profil courant (+ driver, wallet). Auth requise. |
| POST | `/auth/become-driver` | - | Cree le profil `drivers` (pending). Auth requise. |

`register`/`login` renvoient aussi `firebase_custom_token` (string ou
`null` — voir section "Firebase (chat)" plus haut). Cote Flutter, apres un
login/register API reussi, utiliser ce jeton pour connecter le SDK Firebase
Auth avec le meme uid que le compte Laravel, avant d'ouvrir le chat :

```dart
final response = await api.login(email, password); // ou register(...)
final firebaseToken = response['firebase_custom_token'] as String?;
if (firebaseToken != null) {
  await FirebaseAuth.instance.signInWithCustomToken(firebaseToken);
}
// Si firebaseToken est null (cle de service absente cote backend, ou
// erreur ponctuelle), l'app reste authentifiee via Sanctum : seul le chat
// Firestore est indisponible tant que la connexion Firebase n'a pas
// reussi. Ne pas bloquer le reste de l'app sur ce cas.
```

Ce jeton n'est PAS renvoye par `/api/admin/auth/login` : les comptes admin
n'utilisent pas le chat.

### Vehicules (`/api/vehicles`)

Un chauffeur peut declarer **plusieurs vehicules** (ex. il alterne entre sa
propre voiture et celle d'un proche). Chaque vehicule declare rejoint le
processus de verification global du chauffeur (voir "Vehicules et
verification chauffeur" ci-dessous) et devient selectionnable comme
`vehicle_id` sur `POST /trips`.

| Methode | URL | Description |
|---|---|---|
| POST | `/vehicles` | Cree **toujours** un nouveau vehicule (pas d'upsert). Necessite `is_driver=true` + profil `drivers`. Auth requise. |
| GET | `/vehicles` | Liste des vehicules du chauffeur connecte (tableau simple, pas de pagination - volume attendu par chauffeur trop faible pour le justifier). Auth requise. |
| GET | `/vehicles/{id}` | Un vehicule precis, 404 s'il n'appartient pas au chauffeur connecte. Auth requise. |

Body de `POST /vehicles` : `plate_number, brand, model, color, seat_count`.
C'est le prerequis a `POST /trips` (qui exige un `vehicle_id` appartenant
au chauffeur) : sans au moins un vehicule enregistre, un chauffeur ne peut
pas publier de trajet. `POST /trips` verifie que le `vehicle_id` fourni
appartient bien au chauffeur connecte (`Vehicle::where('id', ...)
->where('driver_id', $driver->id)->firstOrFail()` dans
`TripController::store()`) - un vehicule d'un autre chauffeur renvoie 404.

**Immuabilite (anti-fraude)** : une fois cree, un vehicule est
**immuable** - `plate_number, brand, model, color, seat_count` ne peuvent
plus jamais etre modifies. Il n'existe donc volontairement **aucune route
`PATCH /api/vehicles/{id}`**. Cette contrainte est en plus appliquee au
niveau du modele lui-meme (`App\Models\Vehicle::boot()`, evenement
`updating`) : toute tentative de modifier une colonne autre que
`is_active` (desactivation d'un vehicule vendu/retire, pas une correction
de ses caracteristiques), `updated_at` ou `deleted_at` leve une
`LogicException`, meme depuis un service/script/tinker qui contournerait
l'API. Objectif : empecher un chauffeur de faire verifier un beau vehicule
puis de le remplacer discretement par un autre, non verifie, sous la meme
ligne `vehicles`. Une erreur de saisie se corrige en declarant un nouveau
vehicule (et en desactivant l'ancien), pas en editant l'existant.

#### Vehicules et verification chauffeur

La verification (`drivers.verification_status`, voir
`DriverController::recomputeVerificationStatus()` plus bas) porte sur le
**chauffeur dans son ensemble**, pas vehicule par vehicule : le schema de
`driver_documents` n'a pas de colonne `vehicle_id` (documents rattaches a
`driver_id` uniquement), et `REQUIRED_TYPES` inclut deja les pieces
vehicule de la declaration initiale (`vehicle_registration` = carte
grise, `insurance`, `vehicle_photo`) aux cotes des pieces d'identite
(`license`, `national_id`). La verification se fait **une seule fois, a
l'inscription** : c'est elle qui active le compte (`verification_status`
-> `approved`). Declarer un vehicule **supplementaire** apres cette
verification initiale ne redeclenche aucune re-verification - c'est le
comportement voulu, pas un oubli.

### Trips (`/api/trips`)

| Methode | URL | Description |
|---|---|---|
| GET | `/trips/search?origin_lat&origin_lng&destination_lat&destination_lng&radius_m?&women_only?` | Recherche publique (pas d'auth), rayon par defaut 5km. |
| POST | `/trips` | Publier un trajet. Chauffeur `verification_status=approved` requis. Auth requise. |
| GET | `/trips/mine` | Trajets du chauffeur connecte (paginated). Auth requise. |
| GET | `/trips/{trip}` | Detail d'un trajet. Auth requise. |
| POST | `/trips/{trip}/cancel` | Annule un trajet (le chauffeur proprietaire). Auth requise. |
| GET | `/trips/{trip}/nearby-ride-requests?radius_m?` | Demandes passagers ouvertes pres de l'origine du trajet (~15km). Auth requise. |
| GET | `/trips/{trip}/bookings?status?` | Reservations sur ce trajet precis. Uniquement le chauffeur proprietaire du trajet (403 sinon). Auth requise. |

Body de `POST /trips` : `vehicle_id, origin_lat, origin_lng, destination_lat,
destination_lng, departure_type(now|scheduled), scheduled_at?,
price_per_seat, toll_fees?, seats_available, is_recurring?,
recurrence_rule?, women_only?`.

`GET /trips/mine` et `GET /trips/{trip}` appliquent desormais le meme
scope `withLatLng()` que `GET /trips/search` : chaque trajet renvoye porte
`origin_lat/origin_lng/destination_lat/destination_lng` (extraits des
colonnes `geography` via PostGIS `ST_X`/`ST_Y`), pour que les apps
puissent reafficher origine/destination apres publication sans dependre
d'un cache local cote client.

### Ride requests (`/api/ride-requests`)

| Methode | URL | Description |
|---|---|---|
| POST | `/ride-requests` | Cree une demande "Trouve-moi quelqu'un". Body: `origin_lat, origin_lng, destination_lat, destination_lng, women_only?`. |
| GET | `/ride-requests/mine` | Demandes du passager connecte. |
| POST | `/ride-requests/{rideRequest}/cancel` | Annule sa propre demande. |
| GET | `/ride-requests/{rideRequest}/matches?radius_m?&limit?` | Meilleurs trajets matches, tries par score. |

### Bookings (`/api/bookings`)

| Methode | URL | Description |
|---|---|---|
| POST | `/bookings` | Reserve un siege. Body: `trip_id, ride_request_id?, seat_count?, pickup_lat, pickup_lng`. Ne decremente pas les sieges (status `pending_driver`). |
| GET | `/bookings/mine` | Reservations du passager connecte. |
| GET | `/bookings/received?status?` | Toutes les reservations sur tous les trajets du chauffeur connecte (tableau de bord global). Necessite un profil `drivers`. |
| GET | `/bookings/{booking}` | Detail d'une reservation. Uniquement le passager ou le chauffeur du trajet concerne (403 sinon). |
| POST | `/bookings/{booking}/accept` | Le chauffeur accepte : decremente `seats_available` (transaction verrouillee). |
| POST | `/bookings/{booking}/reject` | Le chauffeur refuse. |
| POST | `/bookings/{booking}/cancel` | Passager ou chauffeur annule (restitue le siege si c'etait confirme). |
| POST | `/bookings/{booking}/complete` | Le chauffeur marque le trajet termine. Credite automatiquement le wallet du chauffeur (voir "Credit automatique du wallet chauffeur" ci-dessous). |

Voir aussi `GET /trips/{trip}/bookings` ci-dessus pour les reservations
d'un trajet precis.

#### Credit automatique du wallet chauffeur

Quand `POST /bookings/{booking}/complete` fait passer une reservation a
`completed`, `BookingController::complete()` credite dans la meme
transaction DB le wallet du chauffeur via `WalletService::credit()`
(seul point d'ecriture autorise sur `wallets.balance` — jamais de logique
de credit dupliquee ailleurs). Le montant credite est `price_charged`
moins la commission de zone (`platform_settings.commission_pct`), avec
`idempotency_key = "booking_payment:{booking_id}"` (donc rejouable sans
double credit).

**Simplification documentee** : il n'existe aujourd'hui aucun lien
zone <-> trajet dans le schema (`platform_settings.zone_name` est un
simple libelle texte libre, les trajets ne portent pas de `zone_id`). En
l'absence de ce lien, le backend applique le `commission_pct` de la
**premiere ligne `platform_settings` trouvee**, et **0% de commission par
defaut si aucune ligne `platform_settings` n'existe** (le chauffeur est
alors credite du `price_charged` integral) plutot que de faire echouer la
completion de la reservation. A affiner le jour ou un vrai decoupage par
zone geographique existera.

### Wallet, avis, SOS, litiges

| Methode | URL | Description |
|---|---|---|
| GET | `/wallet` | Solde du wallet de l'utilisateur connecte. |
| GET | `/wallet/transactions` | Historique paginee des transactions. |
| POST | `/reviews` | Note un booking `completed`. Body: `booking_id, punctuality_rating, driving_rating?, communication_rating, safety_rating, comment?`. Recalcule `drivers.average_rating` si la note concerne un chauffeur. |
| POST | `/sos-alerts` | Declenche une alerte SOS. Body: `lat, lng, booking_id?`. |
| POST | `/disputes` | Signale un litige. Body: `reported_against_id, reason, booking_id?, description?`. |
| GET | `/disputes/mine` | Litiges signales par l'utilisateur connecte. |

### Profils publics

| Methode | URL | Description |
|---|---|---|
| GET | `/users/{id}` | Profil public minimal : `id, full_name, profile_photo_url, gender`. Ni email, ni telephone, ni autre champ sensible. Auth requise. |
| GET | `/drivers/{id}` | Profil chauffeur public : identite de base + `average_rating` + `total_trips_completed` + les 5 derniers avis publics (`reviews` non `is_flagged` ou `reviewee_id` est ce chauffeur). Pas de documents, pas de statut de verification, pas de donnees sensibles. `{id}` est l'id de la ligne `drivers` (comme partout ailleurs dans l'API, ex. `/admin/drivers/{id}/documents`), pas l'id `users`. Auth requise. |

### Admin (`/api/admin`)

API du (futur) tableau de bord admin. Authentification **entierement
separee** de `/api/auth/*` : modele `AdminUser`, guard Sanctum `admin`
(`config/auth.php`), token mine avec l'ability `admin`. Toute route
`/api/admin/*` protegee attend `Authorization: Bearer <token-admin>` +
`Accept: application/json`, et est derriere trois couches de middleware
empilees : `auth:admin` (le token doit resoudre vers un `AdminUser` via le
guard `admin`, pas vers un `User` - voir "Decisions techniques" plus bas),
`abilities:admin` (le token doit porter l'ability `admin`), `admin.active`
(le compte doit exister et etre actif). Les actions specifiques ajoutent en
plus `admin.permission:<resource>,<action>`, qui verifie le role RBAC reel
(`admin_roles`/`admin_permissions`).

#### Auth admin (`/api/admin/auth`)

| Methode | URL | Body | Description |
|---|---|---|---|
| POST | `/admin/auth/login` | `email, password, device_id?` | Verifie `is_active=true`. Retourne `{ admin, token }`. Throttle 10/min. |
| POST | `/admin/auth/logout` | - | Revoque le token courant. |
| GET | `/admin/auth/me` | - | `{ admin, role, permissions }` - permissions effectives du role de l'admin connecte. |

#### Vue d'ensemble et statistiques

| Methode | URL | Description |
|---|---|---|
| GET | `/admin/overview` | Chiffres agreges honnetes (vraies requetes, pas d'estimation) : utilisateurs actifs, chauffeurs (total/pending/approved), trajets par statut, reservations aujourd'hui/cette semaine par statut, transactions completees sommees par jour (30 jours), SOS/litiges ouverts. |
| GET | `/admin/stats/timeseries?from?&to?` | Trajets/reservations/revenu (transactions completees) groupes par jour sur `[from, to]` (defaut : 30 derniers jours). |
| GET | `/admin/stats/booking-acceptance-rate?from?&to?` | Ratio reservations acceptees (`confirmed`/`completed`) / reservations ayant recu une decision chauffeur sur la periode. |
| GET | `/admin/stats/average-rating` | Note moyenne plateforme = moyenne de `drivers.average_rating` sur les chauffeurs notes au moins une fois. |
| GET | `/admin/stats/transactions-breakdown?from?&to?` | Volume de transactions completees sur `[from, to]`, regroupe par `payment_method` et separement par `type` (nombre + montant total pour chaque valeur). |
| GET | `/admin/stats/new-accounts-timeseries?from?&to?` | Nouveaux comptes par jour sur `[from, to]`, separes passagers/chauffeurs selon `is_driver` au moment de la requete (pas d'historique de changement de role). |

Ces cinq routes ne sont derriere aucun `admin.permission` specifique (juste
`auth:admin` + `abilities:admin` + `admin.active`) : ce sont des agregats en
lecture seule, sans capacite d'ecriture et sans detail unitaire plus
sensible que ce que chaque endpoint dedie ci-dessous expose deja
integralement a qui a la permission correspondante.

#### Utilisateurs et chauffeurs

| Methode | URL | Permission | Description |
|---|---|---|---|
| GET | `/admin/users?search?&account_status?&is_driver?` | `users.view` | Liste paginee (recherche nom/email/telephone). |
| PATCH | `/admin/users/{id}/status` | `users.edit` | Body `account_status(active\|disabled\|deleted)`. Journalise dans `audit_logs` (ancienne/nouvelle valeur). |
| GET | `/admin/drivers?verification_status?` | `users.view` | Liste paginee des chauffeurs. |
| GET | `/admin/drivers/{id}/documents` | `driver_documents.view` | Metadonnees des `driver_documents` du chauffeur. `file_url` est le chemin de stockage brut - signature d'URL temporaire **TODO prod**, voir le commentaire dans `DriverController::documents()`. |
| PATCH | `/admin/drivers/{id}/documents/{docId}/review` | `driver_documents.edit` | Body `status(approved\|rejected), rejection_reason?`. Journalise, puis recalcule `drivers.verification_status` (voir plus bas). |

**Logique d'approbation chauffeur** (`DriverController::recomputeVerificationStatus()`) :
apres chaque revue de document, le statut du chauffeur est **entierement
recalcule** (jamais modifie manuellement) a partir de l'ensemble de ses
documents `driver_documents` :
- si les 5 types requis (`license, national_id, vehicle_registration,
  insurance, vehicle_photo` - `DriverDocument::REQUIRED_TYPES`) sont tous
  `approved` -> `approved` (et `verified_at` horodate) ;
- sinon, si au moins un document est `rejected` -> `rejected` ;
- sinon (documents manquants et/ou encore `pending`) -> `pending`.

#### Finance

| Methode | URL | Permission | Description |
|---|---|---|---|
| GET | `/admin/transactions?type?&status?&from?&to?` | `transactions.view` | Liste paginee du grand livre `transactions`. |
| GET | `/admin/payout-requests?status?` | `payout_requests.view` | Liste paginee des demandes de retrait chauffeur. |
| PATCH | `/admin/payout-requests/{id}/process` | `payout_requests.edit` | Body `status(processed\|rejected)`. Si `processed` : debite le wallet du chauffeur via `WalletService::debit()` (jamais de logique dupliquee) avec `idempotency_key = "payout_request:{id}"`, ce qui insere la ligne `transactions` de type `payout` correspondante. Refuse (422) si la demande n'est plus `pending` ou si le solde est insuffisant. |

#### Moderation

| Methode | URL | Permission | Description |
|---|---|---|---|
| GET | `/admin/sos-alerts?status?` | `sos_alerts.view` | Liste paginee. |
| PATCH | `/admin/sos-alerts/{id}` | `sos_alerts.edit` | Body `status(in_progress\|resolved), resolution_notes?`. |
| GET | `/admin/disputes?status?` | `disputes.view` | Liste paginee. |
| PATCH | `/admin/disputes/{id}` | `disputes.edit` | Body `status(investigating\|resolved\|dismissed), resolution?`. |

#### Administration

| Methode | URL | Permission | Description |
|---|---|---|---|
| GET | `/admin/admin-users` | `admin_users.view` | Liste paginee des comptes admin. |
| POST | `/admin/admin-users` | `admin_users.edit` **+ role `super_admin`** | Cree un compte admin. La permission RBAC seule ne suffit pas : le controleur verifie explicitement `role->name === 'super_admin'`, meme si un role personnalise obtenait un jour `admin_users.edit` (voir `AdminUserController::store()`). |
| GET | `/admin/admin-roles` | `admin_users.view` | Roles + permissions (pour construire l'UI RBAC du dashboard). |
| GET | `/admin/platform-settings` | `platform_settings.view` | Tarifs par zone (`price_per_km`, `commission_pct`). |
| PATCH | `/admin/platform-settings/{id}` | `platform_settings.edit` | Modifie un tarif de zone, journalise l'ancienne/nouvelle valeur. |

Le seeder (`DatabaseSeeder`) attribue desormais aussi `users.view`/`users.edit`
au role `support`, en plus des permissions deja existantes ; le role
`super_admin` continue de tout couvrir via son wildcard `resource = '*'`.

## Decisions techniques

- **auth_sessions vs Sanctum** : l'authentification API passe par Laravel
  Sanctum (`personal_access_tokens`), qui reste la source de verite pour la
  validite d'un token. La table `auth_sessions` du schema est conservee en
  complement, pas en remplacement : chaque login/register y ecrit une ligne
  (device_id, hash sha256 du token, IP, expiration) pour permettre plus tard
  une vue "mes appareils connectes" / deconnexion a distance / audit des IP —
  des besoins que la table de Sanctum seule ne couvre pas. Voir
  `app/Http/Controllers/Api/AuthController::issueTokenResponse()`.
- **UUID partout** : toutes les tables ont une PK `uuid` (v7, ordonnee dans
  le temps) via `HasUuids`, generee cote application. `personal_access_tokens`
  utilise `uuidMorphs` pour matcher les IDs des modeles `User`/`AdminUser`.
- **Colonnes geospatiales** : Eloquent n'a pas de type PostGIS natif. Les
  colonnes `geography(Point,4326)`/`geography(LineString,4326)` sont ajoutees
  par SQL brut dans les migrations (`DB::statement`) avec un index GiST
  chacune. Cote modele, `app/Concerns/HasGeoPoints.php` ecrit les points via
  `ST_MakePoint` (raw SQL, jamais de parametre non echappe grace a
  `number_format`), et des scopes (`Trip::scopeWithLatLng`,
  `Trip::scopeNear`, `RideRequest::scopeNearPoint`) lisent/filtrent via
  `ST_X`/`ST_Y`/`ST_DWithin`.
- **FOJEM Match** (`app/Services/MatchingService.php`) : score de
  compatibilite 0-100 = 40% distance de detour + 25% duree de detour + 25%
  ecart horaire + 10% alignement de direction (cosinus des vecteurs
  origine->destination), chaque composante decroissant exponentiellement.
  `detour_distance_m`/`detour_duration_s` sont approximes (somme des ecarts
  a vol d'oiseau origine/destination, convertis en duree a 40km/h) en
  l'absence d'un moteur de routage (OSRM/Google Directions/Mapbox) integre
  dans cette passe — remplacer `computeDetour()` suffira le jour ou un vrai
  moteur de routage est branche, sans toucher a la ponderation. Chaque paire
  evaluee est persistee dans `matching_scores`.
- **Wallet/transactions** : `wallets.balance` n'est jamais modifie
  directement. Tout credit/debit passe par `app/Services/WalletService.php`,
  qui verrouille la ligne wallet (`lockForUpdate`) et insere une ligne
  `transactions` (append-only, idempotence via `idempotency_key`) dans la
  meme transaction DB.
- **RBAC admin** : `admin_roles`/`admin_permissions` pilotent l'acces, pas un
  flag booleen. `AdminUser::hasPermission($resource, $action)` et le
  middleware `admin.permission:<resource>,<action>`
  (`app/Http/Middleware/EnsureAdminHasPermission.php`) verifient les
  permissions reelles du role. Le role `super_admin` recoit un jeu de
  permissions `resource = '*'` traite comme un wildcard.
- **Auth admin separee (guard `admin`)** : `/api/admin/*` n'utilise jamais
  le guard/modele `users`. `config/auth.php` declare un guard `admin`
  (`driver: sanctum`, `provider: admins` -> `AdminUser`) ; `AdminAuthController::login()`
  mine le token avec `createToken($deviceId, ['admin'])`. Chaque route
  protegee empile `auth:admin` (le token doit resoudre vers un `AdminUser`
  via ce guard - un token `users` classique echoue ici avec 401, la
  resolution du tokenable passant par le provider du guard) +
  `abilities:admin` (le token doit porter l'ability `admin` ; alias
  enregistres dans `bootstrap/app.php` sur les middlewares Sanctum
  `CheckAbilities`/`CheckForAnyAbility`, non enregistres par defaut en
  Laravel 12) + `admin.active` (`App\Http\Middleware\EnsureIsActiveAdmin`,
  verifie `is_active=true` - applique a **toute** la surface `/api/admin/*`,
  y compris les routes sans `admin.permission` dedie comme `/overview` et
  `/stats/*`, qui sinon ne seraient protegees que par `abilities:admin` -
  insuffisant a lui seul puisque `createToken()` sans ability explicite
  donne par defaut `['*']`, qui satisferait trivialement n'importe quel
  `abilities:x`). `EnsureAdminHasPermission` refait le meme controle
  `instanceof AdminUser` par defense en profondeur avant de verifier la
  permission RBAC.
- **Audit trail** : `app/Services/AuditLogger.php` est l'unique point
  d'ecriture dans `audit_logs` (write-once, pas de soft delete, pas
  d'`updated_at`). A brancher sur chaque action admin sensible ajoutee dans
  le futur dashboard (validation document, suspension compte, remboursement,
  changement tarif...).
- **Champs sensibles chiffres** : `payout_requests.destination_ref` et
  `emergency_contacts.contact_phone` utilisent le cast Laravel `encrypted`
  (colonnes `text` en base, dechiffrees uniquement par l'application via
  `APP_KEY`).
- **Mots de passe** : `Hash::make()` (bcrypt, `BCRYPT_ROUNDS=12` en local/prod
  via `.env`), jamais de stockage en clair. Pas d'OTP : auth email/mot de
  passe classique, comme demande.
- **Port Postgres 55432 au lieu de 5432** : la machine de developpement avait
  deja un service PostgreSQL natif Windows ecoutant sur le port 5432, qui
  interceptait silencieusement les connexions destinees au conteneur Docker
  (meme message d'erreur trompeur "authentification par mot de passe
  echouee"). Le port hote a ete deplace a 55432 dans `docker-compose.yml`
  pour eviter toute collision ; le port interne au conteneur reste 5432.

## Ce qui reste a faire pour la production

- **HTTPS obligatoire** : rien a coder ici, mais le reverse proxy / load
  balancer de production doit terminer TLS avant d'atteindre Laravel (aucune
  route ne doit etre exposee en HTTP clair).
- **Vrai serveur PostgreSQL** : remplacer le conteneur Docker local par
  l'instance PostgreSQL/PostGIS geree du client (RDS, Supabase, serveur dedie
  ...). Mettre a jour `DB_HOST`/`DB_PORT`/`DB_DATABASE`/`DB_USERNAME`/
  `DB_PASSWORD` en production ; verifier que l'extension PostGIS y est
  disponible/activee.
- **Secrets** : `APP_KEY`, credentials DB, et toute cle tierce (SMS/paiement
  mobile money Wave/Orange Money/Free Money une fois integres) doivent venir
  d'un gestionnaire de secrets (pas de `.env` commite), avec rotation.
- **Integration paiement mobile money reelle** : `transactions.payment_method`
  supporte deja `wave/orange_money/free_money/card/cash/wallet`, mais aucun
  connecteur API n'est branche dans cette passe — seul `WalletService` gere
  la comptabilite interne.
- **Moteur de routage reel** pour `MatchingService::computeDetour()` (OSRM
  auto-heberge ou API tierce) afin de remplacer l'approximation a vol
  d'oiseau par une vraie distance/duree de detour routiere.
- **Notifications push** : la table `notifications` existe mais rien
  n'envoie encore de push (FCM/APNs) — a brancher quand les apps Flutter
  seront pretes a les recevoir.
- **Frontend du tableau de bord admin** : hors perimetre de ce backend, sera
  une SPA React separee consommant l'API `/api/admin/*` documentee
  ci-dessus (auth, overview, utilisateurs/chauffeurs, finance, moderation,
  administration, stats). Le RBAC (`admin_roles`/`admin_permissions`/
  `EnsureAdminHasPermission`) et l'audit trail sont en place et branches sur
  chaque action d'ecriture admin.
- **Verification manuelle de documents chauffeur** : `driver_documents`
  bloque `trips.store()` tant que `drivers.verification_status != approved`.
  L'endpoint d'upload cote app chauffeur reste hors perimetre (les apps
  Flutter geraient l'upload ailleurs et ecriraient directement la ligne
  `driver_documents` avec `file_url`) ; l'endpoint de **revue** admin
  (`PATCH /admin/drivers/{id}/documents/{docId}/review`) est implemente.
  La signature d'URL temporaire pour `file_url` reste un TODO prod (voir
  section Admin ci-dessus).
