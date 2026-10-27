# FOJËM — Prompt d'implémentation complète (à coller dans Cursor)

## CONTEXTE RÉEL DU REPO (ne rien halluciner en dehors de ça)

App Flutter, Android uniquement pour l'instant.
- Navigation : go_router (26 routes déclarées)
- État : provider — `AppProvider` et `SearchProvider` sont déclarés mais actuellement
  **jamais utilisés** nulle part dans le code
- **Aucun backend, aucune persistance.** Toutes les données viennent de
  `lib/core/utils/mock_data.dart`. Tout revient à zéro à chaque lancement.
- Design system sous le préfixe `fojem_*` (composants `FojemButton`, `FojemCard`, `FojemTextField`)
- Auth actuelle : téléphone → OTP avec un code universel `123456` affiché à l'écran
  → création de profil → rien n'est persisté ensuite (l'utilisateur reste affiché
  "Ousmane Mané" en dur partout)
- Écran de sélection de siège existant, câblé en dur sur un plan "Sprinter 9 places"
  en `CustomPaint` (pas d'assets image dans le repo — `assets/` déclaré dans
  `pubspec.yaml` mais n'existe pas)
- Beaucoup de boutons no-op (partage, modifier/annuler trajet, contact support,
  notation d'appli, édition avatar), `rating_screen` et `language_screen` orphelins
- Prix du siège fixe (5000 FCFA) déconnecté du trajet réel

**Avant de coder quoi que ce soit : explore le repo pour localiser précisément
tous les fichiers concernés (écrans, providers, mock_data, routes). Adapte les
noms ci-dessous à ce que tu trouves réellement, ne les invente pas.**

---

## VISION PRODUIT À IMPLÉMENTER (l'idée complète, pas un sous-morceau)

Une app de covoiturage sénégalaise avec un **marketplace à double sens** :

1. **Sens Offre (chauffeur)** : un chauffeur qui a une voiture publie un trajet
   — tel jour, telle heure, je pars de tel endroit, je passe par tel endroit,
   j'arrive à tel endroit. Il précise combien de personnes il veut prendre et
   le coût du trajet par personne.

2. **Sens Demande (passager)** : un passager qui veut aller quelque part et ne
   trouve aucune annonce correspondante peut publier sa propre demande — "je
   veux partir de X vers Y, à telle date". Les chauffeurs dont le trajet passe
   dans cette direction peuvent voir cette demande et y répondre.

3. **Dialogue** : chauffeur et passager peuvent échanger (chat) pour caler les
   détails avant de confirmer — que ce soit sur un trajet déjà publié ou en
   réponse à une demande de passager.

4. **Réservation réelle** : le passager réserve, choisit son siège sur le plan
   du véhicule réel du chauffeur, le chauffeur accepte ou refuse, le siège est
   bloqué pour les autres une fois confirmé.

5. **Carte intelligente** : géolocalisation des trajets, calcul d'itinéraire,
   et surtout un **matching qui ne se limite pas à "ville A = ville B"** — si
   le trajet du chauffeur passe à proximité du départ/arrivée voulu par le
   passager, ça doit remonter dans les résultats même sans correspondance exacte.

Ce prompt couvre l'ensemble, en 9 phases. **Livre phase par phase, résume après
chaque phase avant de passer à la suivante** — ne fais pas tout en un seul bloc.

---

## PHASE 0 — Fondation backend (préalable obligatoire)

Rien de ce qui suit (chat, matching entre utilisateurs, demandes, réservations)
ne peut fonctionner sur `mock_data.dart` statique. Mets en place **Firebase** :

- **Firebase Auth** (téléphone/OTP) pour remplacer le code `123456` en dur
  - Note : vérifie la fiabilité de la livraison SMS Firebase Auth sur les
    numéros sénégalais avant de partir dessus à 100% ; si ce n'est pas fiable,
    prévois une abstraction `AuthProvider` (interface) pour pouvoir brancher
    un fournisseur SMS alternatif (Africa's Talking, Twilio) sans réécrire
    tout le flow d'auth
- **Cloud Firestore** pour toutes les données (trajets, demandes, réservations,
  véhicules, messages, utilisateurs)
- **Firebase Storage** pour les photos (pièce d'identité, permis, avatar)
- **Firebase Cloud Messaging** pour les notifications (nouveau message, demande
  de réservation, réponse à une demande de passager)

Migre `AppProvider` pour qu'il porte réellement l'état de session (utilisateur
connecté, véhicule actif) au lieu d'être déclaré et inutilisé. Idem pour
`SearchProvider` côté recherche/filtres.

---

## PHASE 1 — Modèle de données Firestore

Collections à créer (adapte les noms si le repo a déjà des conventions) :

```
users/{userId}
  - role: 'passenger' | 'driver' | 'both'
  - phone, firstName, lastName, avatarUrl
  - rating, ratingCount
  - identityVerified: bool

vehicles/{vehicleId}
  - driverId
  - brand, model, color, plateNumber
  - type: enum (berline, septPlaces, suv, van9, minibus15)
  - seatLayout: SeatLayoutTemplate (voir Phase 8)

trips/{tripId}                        // trajets publiés par un chauffeur (OFFRE)
  - driverId, vehicleId
  - origin: {lat, lng, address}
  - destination: {lat, lng, address}
  - waypoints: [{lat, lng, address}]  // les endroits par lesquels il passe
  - date, time
  - seatsTotal, seatsAvailable
  - pricePerSeat
  - status: 'active' | 'completed' | 'cancelled'

ride_requests/{requestId}             // demandes publiées par un passager (DEMANDE)
  - passengerId
  - origin: {lat, lng, address}
  - destination: {lat, lng, address}
  - desiredDate, desiredTime
  - status: 'open' | 'matched' | 'closed'

bookings/{bookingId}
  - tripId, passengerId, seatId
  - status: 'pending' | 'confirmed' | 'refused' | 'cancelled'
  - confirmationCode (généré, pas en dur)
  - price

conversations/{conversationId}
  - participants: [userId, userId]
  - relatedTripId or relatedRequestId
  messages/{messageId}
    - senderId, text, timestamp, read
```

---

## PHASE 2 — Publication de trajet côté chauffeur (Offre)

Formulaire complet :
- Point de départ (sélection sur carte ou recherche d'adresse)
- Destination
- Étapes intermédiaires optionnelles (les endroits par lesquels il passe —
  c'est ce qui permettra le matching avec les demandes de passagers en cours
  de route, pas seulement les extrémités)
- Date, heure
- Nombre de places proposées (contraint par le véhicule sélectionné — voir Phase 8)
- Sélection du véhicule
- Prix par place (suggestion pré-remplie basée sur la distance, modifiable
  librement par le chauffeur)

Sauvegarde réelle dans `trips`. Le trajet doit apparaître immédiatement dans
les résultats de recherche passager.

---

## PHASE 3 — Demande de trajet côté passager (Demande inversée)

- Écran de recherche : si aucun trajet ne correspond, proposer clairement
  "Aucun trajet trouvé — publier une demande"
- Formulaire : départ, destination, date/heure souhaitée
- Sauvegarde dans `ride_requests`
- Côté chauffeur : nouvel onglet "Demandes de passagers", filtré par proximité
  géographique avec les trajets habituels ou futurs du chauffeur (même logique
  de matching que Phase 4)
- Le chauffeur peut répondre à une demande → ça ouvre une conversation
  (Phase 6) avant toute réservation formelle

---

## PHASE 4 — Recherche et matching intelligent

Le matching ne doit **pas** se limiter à "même ville de départ, même ville
d'arrivée". Implémente une correspondance par proximité géographique :

- Stocke les coordonnées GPS de `origin`, `destination` et `waypoints` de
  chaque trajet
- Un trajet chauffeur remonte dans les résultats d'un passager si son
  origin/destination souhaité est à moins de X km (seuil configurable, ex 5km)
  de n'importe quel point du trajet du chauffeur (origin, waypoints, ou
  destination), dans le bon ordre de direction
- Implémentation technique suggérée : geohash (package `geoflutterfire2` ou
  équivalent maintenu) pour les requêtes géospatiales Firestore, distance
  calculée en formule haversine
- Tri des résultats par pertinence : distance au point demandé, proximité de
  l'heure de départ, prix, note du chauffeur

Écris au moins quelques tests unitaires sur la fonction de calcul de distance
et sur le filtre de matching — c'est la logique la plus critique de toute l'app.

---

## PHASE 5 — Intégration carte

Recommandation par défaut (budget) : **`flutter_map`** (basé sur OpenStreetMap,
gratuit) + package de géocodage pour convertir adresse ↔ coordonnées + un
service de routing gratuit (OSRM) pour calculer et dessiner l'itinéraire réel.

Alternative si le budget le permet plus tard : **`google_maps_flutter`**
(meilleure précision POI et autocomplétion d'adresse, mais facturé en USD).

**Construis une couche d'abstraction** (interface `MapService` avec une
implémentation `OsmMapService` et, plus tard, `GoogleMapService`) pour pouvoir
changer de fournisseur sans réécrire les écrans qui l'utilisent.

Usages concrets dans l'app :
- Sélection du départ/arrivée/étapes par tap sur la carte ou recherche d'adresse
- Affichage du trajet complet avec ses étapes lors de la publication chauffeur
- Affichage des résultats de recherche passager sous forme de pins sur la carte
- Affichage du trajet en cours pendant le suivi (l'écran "suivi de trajet"
  existant, actuellement figé sur une étape statique, doit refléter une
  position réelle ou au moins une progression cohérente avec les étapes du trajet)

---

## PHASE 6 — Dialogue / chat

- Chat en temps réel (Firestore `snapshots()` stream) entre chauffeur et
  passager, rattaché soit à un trajet réservé soit à une demande de passager
  en discussion
- Notification push (FCM) à la réception d'un message ou d'une nouvelle
  demande/réponse

---

## PHASE 7 — Booking / réservation réelle

- Le passager choisit son siège sur le plan dynamique du véhicule du trajet
  (voir Phase 8)
- Demande de réservation créée en statut `pending`, envoyée au chauffeur
- Le chauffeur accepte ou refuse depuis son dashboard (actuellement en dur —
  à rendre fonctionnel)
- Si accepté : statut `confirmed`, siège marqué indisponible pour les autres,
  notification au passager
- Génère un vrai code de confirmation unique par réservation (fini le code en
  dur) et un vrai QR code (package `qr_flutter`) contenant l'id de réservation,
  au lieu de la simple icône actuelle

---

## PHASE 8 — Véhicule et plan de sièges dynamique

C'est la fonctionnalité que je t'ai déjà détaillée : le chauffeur renseigne son
véhicule dans son profil (rubrique "Ma voiture"), et l'app lui propose
automatiquement une disposition visuelle de sièges adaptée — façon Dakar Dem
Dikk — selon le nombre de places déclaré, au lieu d'un plan Sprinter fixe pour
tout le monde.

```dart
enum VehicleType { berline, septPlaces, suv, van9, minibus15 }

class SeatPosition {
  final String id;        // ex: "A1", "B2"
  final int row;
  final int col;
  final bool isDriverSeat;
}

class SeatLayoutTemplate {
  final VehicleType type;
  final int passengerSeatCount;
  final List<SeatPosition> seats;
}

class Vehicle {
  final String id;
  final String driverId;
  final String brand;
  final String model;
  final String color;
  final String plateNumber;
  final VehicleType type;
  final SeatLayoutTemplate layout;
}
```

Templates prédéfinis minimum :
- `berline` : 4 places passagers
- `septPlaces` : 7 places (référence "sept places" très utilisée au Sénégal)
- `suv` : 6 places
- `van9` : 9 places (généralise le plan Sprinter déjà dessiné en CustomPaint —
  ne le recode pas à zéro, transforme-le en widget paramétrable)
- `minibus15` : 15 places (si le temps le permet)

**Refactor du widget existant** : le `CustomPaint` du plan Sprinter doit
devenir un widget générique `SeatLayoutWidget(template, mode)` avec deux modes :
- `preview` : non interactif, utilisé dans le profil chauffeur pour visualiser
  le plan dès que le type de véhicule est choisi
- `selection` : interactif, utilisé côté passager (Phase 7), avec sièges
  pris/disponibles reflétant l'état réel de `seatsAvailable`

Ce véhicule doit être persisté dans Firestore (collection `vehicles`, Phase 1)
et lié à chaque trajet publié (Phase 2), pas stocké uniquement en mémoire dans
`AppProvider`.

---

## PHASE 9 — Profil, notation, sécurité

- Fin des données en dur : chaque utilisateur affiche ses vraies infos une fois
  connecté
- Branche réellement `rating_screen` (actuellement orphelin) : accessible
  depuis l'écran "mes trajets" une fois un trajet marqué `completed`
- Vérification identité : upload photo pièce d'identité + permis vers Firebase
  Storage, statut `identityVerified` visible sur le profil public du chauffeur

---

## HORS SCOPE DE CE PROMPT (volontairement, à traiter séparément ensuite)

- Paiement mobile (Wave / Orange Money) — nécessite une intégration API
  tierce distincte, à faire dans un prompt dédié une fois le reste stable
- Version iOS
- Passage à Google Maps si vous décidez de payer plus tard (l'abstraction
  `MapService` de la Phase 5 est justement là pour rendre ce changement facile)

---

## MÉTHODE

1. Explore le repo avant de commencer, confirme la structure réelle des
   fichiers concernés par chaque phase avant de coder dessus
2. Implémente dans l'ordre des phases ci-dessus (0 → 9), c'est un ordre de
   dépendance, pas arbitraire
3. Après chaque phase : résume les fichiers créés/modifiés, signale toute
   incohérence trouvée dans `mock_data.dart` ou l'archi existante qui
   bloquerait la suite, avant de passer à la phase suivante