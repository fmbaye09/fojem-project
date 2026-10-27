# FOJËM — Application Passager (Niou Dèm)

Application mobile Flutter pour les passagers et voyageurs de la plateforme de covoiturage interurbain **FOJËM** au Sénégal.

---

## Fonctionnalités Principales

- **Recherche intelligente de trajets** :
  - Sélection de l'origine et de la destination (avec géolocalisation OpenStreetMap Nominatim et coordonnées GPS des villes sénégalaises).
  - Filtres avancés : par date, tranche horaire (matin/après-midi/soir), prix maximum par place, nombre de sièges nécessaires.
  - **Suggestions d'itinéraires alternatifs** : si aucun départ exact n'existe pour la date demandée, proposition automatique de trajets alternatifs dans un rayon élargi (35 km) ou sur les prochains créneaux ouverts.
- **Réservation & Choix du siège** :
  - Plan dynamique du véhicule (choix de la place avant, arrière gauche, arrière droit, etc.).
  - Débit sécurisé via le portefeuille virtuel FOJËM.
  - Demande soumise à l'approbation du chauffeur.
- **Billet Numérique & Code QR d'embarquement** :
  - Dès confirmation par le chauffeur, affichage du billet officiel avec son **Code QR d'embarquement unique** et son code à 6 chiffres.
  - Affichage protégé : masqué tant que la réservation est en attente.
- **Suivi en temps réel (`TripTrackingScreen`)** :
  - Carte interactive OpenStreetMap (`flutter_map`) avec départ vert, arrivée rouge et tracé réel OSRM.
  - Position en direct du véhicule et statut dynamique (*"EN ROUTE - Localisation en direct"*).
  - Timeline du voyage et boutons de contact chauffeur (appel et messagerie).
  - Polling silencieux automatique toutes les 10 secondes.
- **Messagerie instantanée en direct** :
  - Chat temps réel sur Cloud Firestore avec le chauffeur du trajet.
  - Pastilles de messages non lus, historique et bouton de reconnexion automatique.
- **Notation & Avis Chauffeur** :
  - Dès la fin du voyage (ou clic sur la notification de fin de trajet), ouverture de l'écran d'évaluation (`/rate/:tripId`) pour noter le conducteur sur 5 étoiles et laisser un commentaire.
- **Demandes de covoiturage ("Trouve-moi quelqu'un")** :
  - Publication d'une demande de trajet personnalisée si aucun chauffeur n'est disponible.
- **Portefeuille virtuel & Historique** :
  - Solde en FCFA, historique des transactions et recharge.

---

## Prérequis

- **Flutter SDK** : version `>= 3.24.0`
- **Dart SDK** : version `>= 3.5.0`
- **Java** : JDK 17
- **Android Studio** ou VS Code avec extensions Flutter & Dart
- Émulateur Android (API 26+) ou appareil physique Android en mode Débogage USB

---

## Configuration & Installation

### 1. Cloner et installer les dépendances

```bash
cd niou_dem
flutter pub get
```

### 2. Configuration Firebase (`nioudem-eecc4`)

Le fichier de configuration Firebase Android est placé à :
```
android/app/google-services.json
```
- Projet Firebase associé : **`nioudem-eecc4`**
- Package name Android : **`com.example.niou_dem`**

> **Important :** Dans la console Firebase, assurez-vous que **Firebase Authentication** est activé avec le fournisseur **Anonyme** (ou Email/Mot de passe) et que les règles **Cloud Firestore** autorisent `/conversations/{id}`.

### 3. Configuration de l'URL Backend Laravel

Le client HTTP est configuré dans [`lib/core/network/api_client.dart`](file:///d:/FOJEM/niou_dem/lib/core/network/api_client.dart).

Par défaut :
- **Sur Émulateur Android :** `http://10.0.2.2:8000/api`
- **Sur Smartphone Android réel :** remplacez `10.0.2.2` par l'adresse IP locale de votre machine sur le même réseau Wi-Fi :
  ```dart
  static const String _defaultBaseUrl = 'http://192.168.1.XX:8000/api';
  ```

---

## Lancement & Compilation

### Mode Développement (Debug)

```bash
# Vérifier la détection de l'appareil
flutter devices

# Lancer sur l'appareil connecté
flutter run
```

### Commandes utiles

```bash
# Analyse statique du code (doit afficher 0 erreur)
flutter analyze

# Nettoyer le cache de build si besoin
flutter clean && flutter pub get

# Générer l'APK de test
flutter build apk --debug
```

---

## Compte de Démonstration Passager

Pour vous connecter immédiatement sans inscription préalable :
- **Email :** `demo.passenger@fojem.sn`
- **Téléphone :** `+221770000002`
- **Mot de passe :** `password`
- **Solde initial :** 5 000 FCFA

---

## Structure du Projet

```
lib/
├── core/
│   ├── geo/               # Coordonnées des villes sénégalaises & OSM
│   ├── network/           # ApiClient Dio (Sanctum Bearer token)
│   ├── storage/           # Stockage sécurisé des tokens
│   ├── theme/             # Charte graphique FOJËM (AppColors, Typography)
│   └── widgets/           # Composants réutilisables (BottomNav, Buttons, Map)
├── features/
│   ├── auth/              # Connexion, inscription, réinitialisation
│   ├── booking/           # Confirmation, Billet QR, Suivi direct en temps réel
│   ├── chat/              # Liste des conversations & écran de chat
│   ├── home/              # Accueil voyageur, raccourcis recherche
│   ├── profile/           # Profil, notifications, wallet, paramètres
│   ├── rating/            # Écran d'évaluation du chauffeur
│   ├── ride_request/      # Publication de demandes "Trouve-moi quelqu'un"
│   └── search/            # Recherche de trajets, filtres, suggestions
├── models/                # Modèles de données (Trip, Booking, User, Conversation)
├── providers/             # État global (AppProvider, SearchProvider)
├── services/              # Repositories (TripRepository, BookingRepository, etc.)
└── app.dart               # Configuration GoRouter et routage des notifications
```
