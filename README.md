# FOJËM — Plateforme de Covoiturage Interurbain au Sénégal

Bienvenue sur le dépôt principal de **FOJËM** (*Niou Dèm*), la solution moderne de covoiturage interurbain conçue spécifiquement pour le Sénégal et l'Afrique de l'Ouest (Dakar, Thiès, Mbour, Saint-Louis, Touba, etc.).

---

## Architecture de la Solution

Ce dépôt est un **monorepo** : les 4 composantes, indépendantes et complémentaires, vivent chacune dans leur sous-dossier :

```
d:/FOJEM/
├── fojem_backend/       # API RESTful Laravel 11 + PostgreSQL/PostGIS (Docker)
├── niou_dem/            # Application Mobile Passager (Flutter Android / iOS)
├── nioudem_chauffeur/   # Application Mobile Chauffeur (Flutter Android / iOS)
└── fojem_dashboard/     # Tableau de bord Administrateur & Modération (React + Vite)
```

| Composante | Technologie | Description | Emplacement |
|---|---|---|---|
| **Backend API** | Laravel 11, PHP 8.3, PostGIS | Authentification Sanctum, calculs géospatiaux, réservations, wallet, notifications push | [`fojem_backend/`](file:///d:/FOJEM/fojem_backend) |
| **App Passager** | Flutter, Dart | Recherche de trajets, carte interactive OSM, réservation, billet QR, chat, wallet | [`niou_dem/`](file:///d:/FOJEM/niou_dem) |
| **App Chauffeur** | Flutter, Dart | Publication de trajets, gestion des demandes reçues, scanner QR d'embarquement, gains | [`nioudem_chauffeur/`](file:///d:/FOJEM/nioudem_chauffeur) |
| **Dashboard Admin** | React 18, TypeScript, Tailwind | Modération KYC des chauffeurs, gestion des trajets, finances, statistiques | [`fojem_dashboard/`](file:///d:/FOJEM/fojem_dashboard) |

---

## Prérequis Généraux

- **Git**
- **Docker Desktop** (pour le backend et la base PostgreSQL/PostGIS)
- **PHP 8.3+** & **Composer**
- **Node.js 18+** & **npm** (pour le dashboard admin)
- **Flutter SDK 3.24+** & **Java 17 / Android Studio** (pour les applications mobiles)
- Un compte **Firebase** (Projet `nioudem-eecc4`) pour la messagerie temps réel et les notifications

---

## Configuration Firebase Partagée (`nioudem-eecc4`)

La messagerie instantanée en direct et le système de notifications push utilisent Firebase.

### 1. Clé de compte de service Backend
- Fichier : `fojem_backend/storage/app/secrets/firebase-adminsdk.json`
- Rôle : Utilisé par Laravel pour générer les *custom tokens* Firebase Auth et pour envoyer les notifications push en FCM HTTP v1.

### 2. Configuration des applications mobiles
- Fichier : `niou_dem/android/app/google-services.json`
- Fichier : `nioudem_chauffeur/android/app/google-services.json`
- Packages déclarés dans Firebase :
  - Client : `com.example.niou_dem`
  - Chauffeur : `com.example.niou_dem_chauffeur`

### 3. Règles de sécurité Cloud Firestore
À copier dans l'onglet **Règles (Rules)** de votre base Cloud Firestore sur la console Firebase :

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // Conversations et messages du chat FOJEM
    match /conversations/{conversationId} {
      allow read, write: if true;

      match /messages/{messageId} {
        allow read, write: if true;
      }
    }

    // Utilisateurs connectés
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

## Démarrage Rapide

### Étape 1 : Lancer le Backend & la Base de Données

```bash
cd fojem_backend

# 1. Démarrer les conteneurs Docker (API Laravel + Base PostGIS)
docker compose up -d

# 2. Exécuter les migrations et le jeu de données démo (si première installation)
docker compose exec fojem_backend php artisan migrate --seed
```

L'API est accessible sur `http://localhost:8000` (ou `http://127.0.0.1:8000`).

### Étape 2 : Lancer le Tableau de Bord Admin

```bash
cd fojem_dashboard
npm install
npm run dev
```

Accessible sur `http://localhost:5173`.

### Étape 3 : Lancer les Applications Mobiles Flutter

Dans deux terminaux séparés :

```bash
# Application Passager
cd niou_dem
flutter pub get
flutter run

# Application Chauffeur
cd nioudem_chauffeur
flutter pub get
flutter run
```

> **Astuce Android physique / émulateur :**
> - **Émulateur Android :** pointe automatiquement sur `http://10.0.2.2:8000`.
> - **Smartphone réel (USB / WiFi) :** remplacez l'IP dans `lib/core/network/api_client.dart` par l'adresse IP locale de votre ordinateur (ex : `http://192.168.1.XX:8000`).

---

## Comptes de Démonstration (Seeder)

Le seeder initial crée automatiquement ces profils de test (mot de passe défini dans `fojem_backend/database/seeders/DatabaseSeeder.php`, à n'utiliser qu'en local) :

| Rôle | Email / Identifiant | Téléphone | Description |
|---|---|---|---|
| **Chauffeur** | `demo.driver@fojem.sn` | `+221770000001` | Chauffeur vérifié avec véhicule Renault Logan et trajet ouvert (Plateau → Ouakam) |
| **Passager** | `demo.passenger@fojem.sn` | `+221770000002` | Passagère avec portefeuille pré-crédité (5 000 FCFA) |
| **Super Admin** | `super_admin@fojem.sn` | `—` | Accès complet au dashboard administrateur |
| **Support Admin** | `support@fojem.sn` | `—` | Modération des trajets et gestion du support client |
| **Finance Admin** | `finance@fojem.sn` | `—` | Supervision des portefeuilles et transactions financières |

---

## Documentation Détaillée par Projet

Consultez les guides spécifiques à chaque composant :
- 📖 [Guide Backend Laravel](file:///d:/FOJEM/fojem_backend/README.md)
- 📱 [Guide Application Passager (Flutter)](file:///d:/FOJEM/niou_dem/README.md)
- 🚗 [Guide Application Chauffeur (Flutter)](file:///d:/FOJEM/nioudem_chauffeur/README.md)
- 💻 [Guide Tableau de Bord Admin (React)](file:///d:/FOJEM/fojem_dashboard/README.md)

---

## Licence

Propriété exclusive de **FOJËM**. Tous droits réservés.
