# FOJËM — Application Chauffeur (Niou Dèm Chauffeur)

Application mobile Flutter réservée aux conducteurs et chauffeurs partenaires de la plateforme de covoiturage interurbain **FOJËM** au Sénégal.

---

## Fonctionnalités Principales

- **Publication de Trajets** :
  - Définition du trajet (point de départ, destination, étapes intermédiaires sur carte OSM).
  - Date et heure de départ planifiées.
  - Fixation du tarif par place (en FCFA) et sélection du nombre de sièges disponibles dans le véhicule.
  - Options de voyage : bagages volumineux acceptés, climatisation, trajet réservé aux femmes (*women only*).
- **Gestion des Demandes Reçues (`BookingRequestsScreen`)** :
  - Dès qu'un passager réserve une place, notification push et système immédiate.
  - **Un clic sur la notification ouvre directement la page des demandes reçues** (`/trip/:id/requests`).
  - Fiche détaillée pour chaque passager avec actions immédiates : **Accepter** ou **Refuser**.
- **Scanner QR d'Embarquement Intégré (`QrScannerScreen`)** :
  - Scanner caméra haute performance (MobileScanner) avec viseur dynamique.
  - **Détection des doublons et passagers déjà à bord** : alerte spécifique ambrée affichant *"Passager déjà embarqué"* si le passager a déjà été validé, évitant toute confusion.
  - Option de validation par saisie manuelle du code de départ dicté par le voyageur.
- **Gestion du Cycle de Vie du Trajet (`TripManageScreen`)** :
  - Tableau de bord en temps réel du trajet.
  - Démarrage du trajet (*Passer en route*).
  - Clôture du trajet (*Terminer le trajet*) : met à jour automatiquement le statut de tous les passagers à bord et **crédite instantanément les gains nets sur le portefeuille du chauffeur**.
- **Messagerie Instantanée Conducteur-Voyageur** :
  - Discussions en direct avec les passagers confirmés ou intéressés via Cloud Firestore.
- **Espace Véhicule & Vérification des Pièces (KYC)** :
  - Gestion du véhicule actif (marque, modèle, immatriculation, couleur).
  - Soumission du permis de conduire et de la carte grise pour validation par l'équipe administrative FOJËM.
- **Portefeuille Chauffeur & Gains** :
  - Solde des revenus cumulés en FCFA, détail des commissions et historique des trajets effectués.

---

## Prérequis

- **Flutter SDK** : version `>= 3.24.0`
- **Dart SDK** : version `>= 3.5.0`
- **Java** : JDK 17
- **Android Studio** ou VS Code avec extensions Flutter & Dart
- Émulateur Android (API 26+) ou appareil physique Android en mode Débogage USB avec caméra fonctionnelle (pour le scan QR)

---

## Configuration & Installation

### 1. Cloner et installer les dépendances

```bash
cd nioudem_chauffeur
flutter pub get
```

### 2. Configuration Firebase (`nioudem-eecc4`)

Le fichier de configuration Firebase Android est placé à :
```
android/app/google-services.json
```
- Projet Firebase associé : **`nioudem-eecc4`**
- Package name Android : **`com.example.niou_dem_chauffeur`**

> **Important :** Dans la console Firebase, assurez-vous que **Firebase Authentication** est activé avec le fournisseur **Anonyme** (ou Email/Mot de passe) et que les règles **Cloud Firestore** autorisent `/conversations/{id}`.

### 3. Configuration de l'URL Backend Laravel

Le client HTTP est configuré dans [`lib/core/network/api_client.dart`](file:///d:/FOJEM/nioudem_chauffeur/lib/core/network/api_client.dart).

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

## Compte de Démonstration Chauffeur

Pour tester immédiatement avec un profil chauffeur déjà validé disposant d'un véhicule et d'un trajet ouvert :
- **Email :** `demo.driver@fojem.sn`
- **Téléphone :** `+221770000001`
- **Mot de passe :** `password`
- **Véhicule actif :** Renault Logan (DK-1234-AB)
- **Trajet de test existant :** Dakar Plateau → Ouakam

---

## Structure du Projet

```
lib/
├── core/
│   ├── network/           # ApiClient Dio (Sanctum Bearer token)
│   ├── storage/           # Gestion du TokenStorage sécurisé
│   ├── theme/             # Charte graphique FOJËM Chauffeur
│   └── widgets/           # Composants réutilisables (Boutons, Cartes, Dialogs)
├── features/
│   ├── auth/              # Connexion, inscription chauffeur, statut KYC
│   ├── chat/              # Liste des conversations & salon de messagerie
│   ├── profile/           # Profil chauffeur, documents, notifications, véhicule
│   ├── requests/          # Écran des demandes reçues (Accepter / Refuser)
│   └── trips/             # Création de trajet, tableau de bord trajet, Scanner QR
├── models/                # Modèles de données (Trip, Booking, Vehicle, User)
├── providers/             # AppProvider (Session, statut chauffeur, token Firebase)
├── services/              # Repositories (TripRepository, BookingRepository, etc.)
└── app.dart               # Configuration GoRouter et routage direct des notifications
```
