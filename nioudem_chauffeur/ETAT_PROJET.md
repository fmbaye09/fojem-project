# FOJËM — État complet du projet (15/08/2026)

Référence pour la maquette complète. Décrit fidèlement ce qui existe dans le code : chaque écran, ses éléments, ses données, ses actions, et ce qui est réel vs encore mock/manquant. App Flutter, Android uniquement, backend Firebase réel (Auth, Firestore, Storage, FCM).

---

## Sommaire

1. [Stack technique](#1-stack-technique)
2. [Modèle de données Firestore](#2-modèle-de-données-firestore)
3. [Onboarding & authentification](#3-onboarding--authentification)
4. [Voyageur](#4-voyageur)
5. [Chauffeur](#5-chauffeur)
6. [Profil, messages & support](#6-profil-messages--support)
7. [Composants réutilisables](#7-composants-réutilisables)
8. [Ce qui est mock ou incomplet](#8-ce-qui-est-mock-ou-incomplet)
9. [Charte graphique](#9-charte-graphique)

---

## 1. Stack technique

- **Framework** : Flutter 3.35.5, Dart, Android uniquement (pas d'iOS)
- **Navigation** : `go_router`, 30 routes déclarées dans `lib/app.dart`
- **État** : `provider` — `AppProvider` (session utilisateur) et `SearchProvider` (recherche) globaux, providers locaux par écran ailleurs
- **Backend** : Firebase — Auth (téléphone réel), Firestore, Storage, Cloud Messaging
- **Carte/géo** : `flutter_map` (OpenStreetMap) + Nominatim (géocodage) + OSRM (itinéraire) via une interface `MapService`
- **Autres libs** : `qr_flutter` (QR réel), `image_picker` (upload photos), `google_fonts`, `intl`, `pinput`
- **CI/CD** : GitHub Actions — `flutter analyze` + `flutter test` puis `flutter build apk --release` + déploiement Firebase App Distribution. Gradle 8.12 / AGP 8.9.1 / Kotlin 2.1.0.
- **Tests** : 12 tests unitaires sur le matching géographique (`test/core/geo/`)
- **Mode test** : sur l'écran de choix de rôle, deux liens "MODE TEST" créent une session locale sans passer par Firebase (pour naviguer sans OTP), volontairement temporaire

---

## 2. Modèle de données Firestore

### `users/{uid}`
- `name`, `phoneNumber`, `photoUrl`, `role` (`traveler` | `driver`)
- `rating` (moyenne), `ratingCount`, `totalTrips`
- `identityVerified` (bool), `identityVerificationStatus`, `identityIdPhotoUrl`, `identityLicensePhotoUrl`
- `fcmToken`, `createdAt`

### `vehicles/{id}`
- `driverId`, `type` (`berline` | `septPlaces` | `suv` | `van9` | `minibus15`), `brand`, `model`, `color`, `plateNumber`
- Un seul véhicule actif par chauffeur

### `trips/{id}`
- `driverId`, `vehicleId`
- `departure`, `arrival` (noms de ville), `departureAddress`, `arrivalAddress`
- `origin`, `destination` (`{lat, lng, address}`), `waypoints` (liste de mêmes objets)
- `departureTime`, `estimatedDurationMinutes`
- `seatsTotal`, `seatsAvailable`, `occupiedSeatIds`
- `pricePerSeat`, `status` (`upcoming` | `inProgress` | `completed` | `cancelled`), `vehicleType`, `notes`

### `ride_requests/{id}`
- `passengerId`, `passengerName`, `origin`, `destination`, `desiredDateTime`, `status` (`open` | `matched` | `closed`)

### `bookings/{id}`
- `tripId`, `passengerId`, `seatId`, `price`
- `status` (`pending` | `confirmed` | `refused` | `cancelled` | `completed`)
- `confirmationCode` (généré, format `ND-XXXXXX`), `passengerName`, `passengerPhone`, `bookedAt`

### `conversations/{id}` + `messages/{id}` (sous-collection)
- `participants` (2 uid), `relatedTripId` ou `relatedRequestId`, `lastMessageText`, `lastMessageAt`
- Messages : `senderId`, `text`, `timestamp`, `read`

### `reviews/{id}`
- `tripId`, `driverId`, `authorId`, `authorName`, `rating`, `comment`, `date`

---

## 3. Onboarding & authentification

### `/splash` — Écran de démarrage
Animation de logo (~1,6 s), aucune logique métier, redirige automatiquement vers `/onboarding`.

### `/onboarding` — Présentation
3 slides swipables avec icône + texte codés en dur (contenu marketing, pas de données). Boutons "Ignorer" et "Suivant"/"Commencer". Indicateur de page en bas.

### `/role-selection` — Choix du profil
Deux grandes cartes tactiles : **"Je voyage"** (icône valise, vert) → `/auth/phone?role=traveler`, **"Je conduis"** (icône volant, ambre) → `/auth/phone?role=driver`. Sous les cartes : bloc "MODE TEST — sans compte réel" avec deux liens texte (Voyageur / Chauffeur) qui créent une session locale factice (aucun appel Firebase) et vont directement à `/home` ou `/driver/home` — utile pour tester la mise en page sans configurer l'auth.

### `/auth/phone` — Saisie du numéro
Champ téléphone avec préfixe `+221` fixe (drapeau 🇸🇳), formatage automatique par groupes de 2 chiffres, validation locale (9-12 chiffres). Bouton "Envoyer le code" → appelle Firebase Phone Auth (`verifyPhoneNumber`), gère l'auto-vérification Android (si le SMS est lu automatiquement, saute directement à l'écran profil). En cas d'erreur Firebase (numéro invalide, trop de tentatives...), message d'erreur localisé sous le champ.

### `/auth/otp` — Code de vérification
Saisie à 6 chiffres (`pinput`), auto-focus. "Code envoyé au +221 XX XXX XX XX". Countdown de 30 s avant de pouvoir renvoyer le code (le renvoi relance un vrai `sendOtp`). Vérifie le code via Firebase (`signInWithCredential`) — plus de code `123456` en dur, plus de délai simulé. En cas d'échec : message d'erreur Firebase traduit, champ vidé.

### `/auth/profile` — Configuration du profil
Indicateur d'étape (3/3). Avatar factice (icône, tap non fonctionnel — pas d'upload à cette étape). Champs Prénom / Nom (validation non-vide). Note "Votre nom complet sera visible par les autres utilisateurs." Bouton "Terminer la configuration" → écrit le nom dans `users/{uid}` puis redirige vers `/home` ou `/driver/home` selon le rôle.

---

## 4. Voyageur

### `/home` — Accueil
AppBar verte extensible : salutation dynamique selon l'heure ("Bonjour"/"Bon après-midi"/"Bonsoir"), date du jour, barre de recherche cliquable (`FojemSearchBar`), icônes messages (💬 → `/chat`) et notifications (🔔 avec point d'accent → `/notifications`). Section "Trajets populaires" : chips horizontales avec villes + prix (contenu statique, taille cible). Section "Départs aujourd'hui" : trajets **réels** filtrés sur la date du jour et non complets (`TripRepository.fetchActiveUpcoming`), skeleton loader pendant le chargement, état vide si aucun trajet.

### `/search` — Recherche
Sélecteurs ville de départ / ville d'arrivée (bottom sheet `CitySelector`, 15 villes sénégalaises), sélecteur de date, compteur de passagers (1-9). Bouton "Rechercher" → `/search/results`.

### `/search/results` — Résultats
En-tête avec départ → arrivée + nombre de résultats. Barre de filtres horizontale : tri (Heure / Prix / Note / Places) + filtres véhicule (7 places / Minibus). Liste de `TripCard` (avatar + nom + note chauffeur, horaires, durée, prix, badge type de véhicule). **Matching géographique réel** : les trajets ne remontent pas seulement sur correspondance exacte de ville — un trajet est retenu si le point demandé est à moins de 5 km de l'origine, d'une étape intermédiaire ou de la destination du trajet, dans le bon sens de parcours. Si aucun résultat : illustration + texte + bouton principal **"Publier une demande de trajet"** → `/ride-request/create?from=...&to=...`, et bouton secondaire "Modifier la recherche".

### `/trip/:id` — Détail du trajet
AppBar avec bouton retour, icône "Contacter le chauffeur" (💬 — crée/ouvre une conversation réelle) et icône partage (non fonctionnelle). Section chauffeur (avatar, nom, note, badge en ligne). Détails du trajet (horaires, durée, adresses précises, places disponibles sur total réel, notes du chauffeur si présentes). Section prix. Section avis (si le chauffeur en a). Barre de réservation fixe en bas avec prix et bouton "Réserver" → `/seat-selection?tripId=...`.

### `/seat-selection` — Choix de la place
AppBar avec bandeau "X/Y disponibles". Plan de sièges **interactif et dynamique** : la disposition dépend du vrai véhicule du trajet (`SeatLayoutWidget`) — Sprinter réaliste dessiné en `CustomPaint` pour le van 9 places, silhouette générique cohérente visuellement pour berline/7 places/SUV/minibus 15. Sièges occupés (gris, cadenas) reflètent `occupiedSeatIds` du trajet réel. Un seul siège sélectionnable à la fois (cercle vert avec halo + bulle "Place #X - Sélectionnée"). Barre de réservation fixe avec prix réel du trajet. Confirmation → bottom sheet récapitulatif → `/booking/confirm?tripId=...&seatId=...`.

### `/booking/confirm` — Confirmer la réservation
Résumé du trajet (départ → arrivée, durée). Résumé de la place choisie (numéro). Résumé passager (initiales, nom réel ou "Votre profil", téléphone réel — tiré du profil connecté). Total = prix réel du trajet (une place). Bouton **"Envoyer la demande de réservation"** (renommé depuis "Confirmer et payer" — aucun paiement n'est implémenté) → crée une réservation Firestore en statut `pending` avec code de confirmation généré, puis `/booking/success?bookingId=...`.

### `/booking/success` — Demande envoyée
Animation de succès (icône + fondu). Titre "Demande envoyée !" et texte expliquant que la demande est transmise au chauffeur et que l'utilisateur sera notifié à l'acceptation (honnête sur le statut `pending`, pas de fausse confirmation immédiate). Carte code de confirmation réel. **Vrai QR code** (`qr_flutter`, contient l'id de réservation) — plus d'icône statique. Récapitulatif (trajet, date, heure, chauffeur, place, montant à régler au chauffeur en espèces). Boutons "Voir mes trajets" / "Retour à l'accueil".

### `/my-trips` — Mes trajets
Deux onglets : "À venir" (statuts `confirmed`/`pending`) et "Passés" (`completed`/`cancelled`/`refused`), chargés depuis Firestore pour l'utilisateur connecté. Chaque carte : badge de statut (avec variante "Refusé" désormais gérée), code de confirmation, horaires, villes, durée, date, nombre de places, prix, chevron. Tap sur un trajet à venir → suivi (`/trip/:id/tracking`) ; tap sur un trajet **terminé** → notation (`/rate/:tripId`). État vide avec CTA "Rechercher un trajet".

### `/trip/:id/tracking` — Suivi de trajet
Carte contact chauffeur (nom, statut en ligne, véhicule, plaque). Timeline de statut à 4 étapes (Confirmé / Chauffeur confirmé / Départ / Arrivée). **La progression n'est plus figée** : elle est recalculée à partir de l'heure de départ réelle et de la durée estimée (avant J-30min = confirmé, jusqu'au départ = chauffeur confirmé, pendant le trajet = départ, après = arrivée) — pas de GPS live, mais cohérent avec le vrai horaire. Bouton d'aide → `/support`.

### `/ride-request/create` — Publier une demande
Texte d'explication ("Aucun trajet ne correspond ? Publiez votre demande..."). Sélecteurs ville de départ / d'arrivée (pré-remplis si on vient de résultats vides), sélecteur de date, sélecteur d'heure souhaitée. Bouton "Publier la demande" → crée un document `ride_requests` réel, visible par les chauffeurs dont l'itinéraire s'en approche → `/home`.

---

## 5. Chauffeur

### `/driver/home` — Tableau de bord
AppBar verte : "Bonjour, {prénom réel}", icônes messages/notifications/profil. Carte gains : montant du jour réel (somme des réservations confirmées sur des trajets du jour), stats réelles (trajets aujourd'hui, passagers confirmés, note moyenne). Section "Prochain trajet" : le trajet à venir le plus proche du chauffeur (réel) avec label temporel ("Aujourd'hui 07:00"/"Demain..."), villes, nombre de passagers confirmés, bouton "Gérer" → `/driver/requests`. Si aucun trajet : message + CTA. Bouton "Publier un nouveau trajet". Section "Demandes récentes" : 2 dernières réservations `pending` réelles. Bouton "Demandes de passagers sur ma route" → `/driver/passenger-requests`.

### `/driver/post-trip` — Publier un trajet
**Itinéraire** : sélecteurs ville de départ/arrivée (comme la recherche), section "étapes intermédiaires" — ajout via un écran carte+recherche d'adresse réel (`LocationPickerScreen`, Nominatim + tap sur carte OpenStreetMap), chips supprimables. **Date et heure** : sélecteur de date + heure. **Véhicule** : n'est plus un choix libre par trajet — résumé du véhicule réellement enregistré dans "Ma voiture" (marque, modèle, type, nombre de places, plaque) ; si aucun véhicule enregistré, bandeau d'avertissement + bouton "Ajouter" → `/driver/vehicle`, publication bloquée tant que ce n'est pas fait. **Tarif** : prix par place, **pré-suggéré automatiquement** à partir de la distance réelle du trajet (itinéraire OSRM, ~40 FCFA/km arrondi à 500 FCFA près), modifiable librement. **Notes** optionnelles. Bouton "Publier le trajet" → écrit un vrai document `trips` dans Firestore, visible immédiatement en recherche → `/driver/home`.

### `/driver/trips` — Mes trajets publiés
Onglets "À venir" / "Passés", chargés depuis Firestore pour le chauffeur connecté (l'onglet "Passés" n'est plus vide en dur). Chaque carte : statut réel, horaires, villes, date, places restantes réelles. Sur un trajet à venir : bouton "Annuler" avec boîte de dialogue de confirmation → passe le trajet en `cancelled` réellement (le bouton "Modifier" a été retiré plutôt que laissé factice, l'édition d'un trajet publié n'étant pas implémentée).

### `/driver/requests` — Demandes de réservation
Section "En attente de réponse" (avec compteur) et "Confirmées". Chaque demande en attente : avatar/initiales passager, nom, téléphone, prix, place + trajet, boutons **"Refuser"** / **"Accepter"** — réellement fonctionnels : l'acceptation exécute une transaction Firestore qui bloque le siège (`occupiedSeatIds`), décrémente `seatsAvailable` et incrémente le compteur de trajets du chauffeur ; si le siège vient d'être pris entretemps, message d'erreur clair plutôt qu'un état incohérent. État vide avec illustration.

### `/driver/passenger-requests` — Demandes de passagers
Liste des demandes de passagers (`ride_requests` ouvertes) dont l'itinéraire souhaité est à moins de 15 km d'un des trajets à venir du chauffeur (même algorithme de matching que la recherche, seuil élargi). Chaque carte : trajet souhaité, date/heure, nom du passager, distance à l'itinéraire du chauffeur. Bouton "Répondre" → ouvre/crée une conversation réelle avec le passager → `/chat/:id`.

### `/driver/vehicle` — Ma voiture
Sélecteur de type de véhicule (5 puces : Berline, 7 places, SUV, Van 9 places, Minibus 15 places). **Aperçu en direct** du plan de sièges correspondant (`SeatLayoutWidget` en mode `preview`, non interactif) qui se met à jour immédiatement au changement de type. Champs Marque, Modèle, Couleur, Plaque d'immatriculation. Bouton "Enregistrer" → crée ou met à jour le document `vehicles` du chauffeur dans Firestore.

### `/driver/earnings` — Gains *(non rebranché)*
3 onglets (jour/semaine/mois). **Reste sur les données de démonstration** — n'a pas été reconnecté aux vraies réservations dans cette passe (contrairement à la carte gains de l'accueil chauffeur, qui elle est réelle).

---

## 6. Profil, messages & support

### `/profile/settings` — Profil et paramètres
En-tête : initiales calculées + nom réel + téléphone réel + badge de rôle réel (Voyageur/Chauffeur). Section "Mon compte" : numéro de téléphone (lecture seule), toggle notifications (visuel, pas de logique de préférence persistée), lien "Ma voiture" (chauffeurs uniquement) → `/driver/vehicle`, lien "Vérification d'identité" avec statut réel (Vérifié/Non vérifié) → `/profile/identity`. Section "Préférences" : Langue (lien cassé — écran existant mais jamais rattaché au routeur), Thème (visuel uniquement). Section "Aide et support" : Centre d'aide (fonctionnel), CGU/confidentialité/note d'appli (non fonctionnels — inchangés dans cette passe). Bouton **Déconnexion réel** (appelle `AppProvider.signOut()`, déconnecte vraiment de Firebase Auth) avec boîte de dialogue de confirmation.

### `/profile/driver/:id` — Profil public chauffeur
Composé depuis Firestore (`DriverRepository`) : photo/initiales, nom, note et nombre de trajets réels, statistiques, carte véhicule (type, marque/modèle, plaque), liste d'avis réels (`reviews`). État "profil introuvable" géré.

### `/profile/identity` — Vérification d'identité
Texte d'explication. Deux tuiles "Pièce d'identité" et "Permis de conduire" : tap → ouvre l'appareil photo (`image_picker`), aperçu de la photo prise. Bouton "Envoyer pour vérification" (actif une fois les deux photos prises) → upload vers Firebase Storage, statut passé à `pending` sur le profil. **`identityVerified` n'est jamais auto-validé côté client** — nécessite une vérification humaine future.

### `/rate/:tripId` — Noter un trajet
Route/nom du chauffeur réels (chargés via le trajet). Avatar, nom, modèle du véhicule. Étoiles interactives (1-5) avec libellé ("Excellent !", "Correct"...). Tags rapides sélectionnables (Conduite douce, Très ponctuel...). Champ commentaire optionnel (200 caractères). Bouton "Envoyer l'évaluation" → écrit un avis réel et **met à jour la note moyenne du chauffeur en transaction Firestore** (`rating`, `ratingCount`). Accessible désormais depuis "Mes trajets" sur un trajet terminé (auparavant orphelin).

### `/chat` — Messages
Liste des conversations de l'utilisateur connecté, temps réel (`snapshots()`). Chaque ligne : avatar/initiales de l'autre participant (résolu via son profil), dernier message, heure. État vide si aucune conversation.

### `/chat/:id` — Conversation
Fil de messages temps réel, bulles alignées selon l'expéditeur (soi/l'autre). Champ de saisie + bouton d'envoi. Pas de notification push déclenchée à la réception (nécessiterait une Cloud Function côté serveur, hors scope client).

### `/notifications` — Notifications *(non rebranché)*
4 notifications codées en dur, bouton "Tout lire" non fonctionnel. Pas de flux d'événements réel derrière (nouvelle réservation, message, etc.) dans cette passe.

### `/support` — Centre d'aide
FAQ en accordéon (6 questions, contenu cohérent avec le produit). Boutons de contact (Chat/Appeler/Email) non fonctionnels.

### Écran orphelin : Langue
`language_screen.dart` existe (sélection FR/Wolof/EN complète et fonctionnelle visuellement) mais n'est rattaché à aucune route — le lien "Langue" dans les paramètres pointe vers une route qui n'existe pas.

---

## 7. Composants réutilisables

- **`TravelerBottomNavBar` / `DriverBottomNavBar`** — barres de navigation basses contextuelles au rôle
- **`FojemSearchBar`** — barre de recherche intégrée à l'AppBar de l'accueil
- **`TripCard`** — carte trajet (recherche, accueil), avec badge type de véhicule
- **`SeatLayoutWidget`** — plan de sièges générique paramétré par type de véhicule, modes `preview`/`selection` (Phase 8, remplace l'ancien plan Sprinter câblé en dur)
- **`LocationPickerScreen`** — sélection de point (recherche d'adresse OSM + tap carte), réutilisé pour les étapes de trajet
- **`CitySelector`, `DateSelector`** — bottom sheets de sélection ville/date
- **`StatusChip`** — badges de statut (confirmé/en attente/refusé/annulé/terminé/en ligne/hors ligne)
- **`FojemButton`, `FojemCard`, `FojemTextField`** — design system de base (fichiers `fojem_*`)
- **`SkeletonLoader`** — états de chargement animés
- **`PriceDisplay`, `StarRating`, `DriverAvatar`** — affichage prix/note/avatar chauffeur

---

## 8. Ce qui est mock ou incomplet

| Élément | État |
|---|---|
| `/driver/earnings` | Chiffres de démonstration, pas rebranché |
| `/notifications` | 4 notifications en dur, pas de flux réel |
| Écran Langue | Existe mais orphelin, lien cassé depuis Paramètres |
| CGU / confidentialité / note d'appli | Boutons non fonctionnels |
| Contacts support (chat/appel/email) | Non fonctionnels |
| Notifications push | FCM configuré côté client, rien ne déclenche l'envoi (besoin Cloud Functions serveur) |
| Paiement | Hors scope volontairement — cash à la main du chauffeur pour l'instant |
| iOS | Hors scope |
| Suivi de trajet | Progression déduite de l'heure, pas de GPS live |
| Carte (OSM/Nominatim/OSRM) | Serveurs publics limités en volume — à auto-héberger avant un vrai lancement |
| Rôle "les deux" | Un utilisateur reste Voyageur *ou* Chauffeur, pas les deux |
| Firebase Console | Certaines étapes restent manuelles (activer Auth téléphone, créer Firestore, activer Storage, ajouter SHA-1, déployer les règles/index) |

---

## 9. Charte graphique

- **Couleurs** : primaire vert `#0B5E42` (+ clair `#1A8A5E`, surface `#E8F5EE`), accent ambre `#E8A020` (surface `#FFF3DC`), fond `#F8F7F4`, surface `#FFFFFF`, texte primaire `#1A1A18`, secondaire `#6B6B66`, muted `#A0A09A`, bordures `#E8E6E0`/`#C8C6C0`, succès `#1A7A4A`, danger `#C0392B`
- **Typographie** : Google Fonts (Inter), échelle définie dans `AppTextStyles` (display/title1/title2/bodyLarge/body/caption/label)
- **Espacements** : grille 8dp (`AppSpacing.xs`=4 → `xxl`=48), rayons de bordure 6/12/20/999
- **Composants** : cartes avec ombre douce à deux niveaux (`AppColors.cardDecoration`), modales avec coins arrondis en haut (`modalDecoration`)
- Tous les nouveaux écrans de cette passe réutilisent ce système existant plutôt que d'introduire de nouveaux styles.
