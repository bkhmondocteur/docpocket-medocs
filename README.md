# DocPocket Medocs
### Application Médicale Complète de Gestion des Échantillons Médicaux

[![PWA](https://img.shields.io/badge/PWA-Ready-1565C0?style=for-the-badge&logo=pwa)](https://bkhmondocteur.github.io/docpocket-medocs/)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-Proprietary-263238?style=for-the-badge)]()

**DocPocket Medocs** est une solution logicielle locale, ultra-rapide et ergonomique développée spécialement pour les cabinets médicaux. Elle permet de gérer avec précision les réceptions d'échantillons médicaux auprès des délégués pharmaceutiques, et leur remise aux patients lors des consultations médicales.

---

## Fonctionnalités Principales

1. **Scan Optique Intelligent & Multi-Matériel** :
   - Support des douchettes code-barres USB en mode émulation clavier physique (sans nécessiter de clic préalable).
   - Scanner optique caméra intégré pour smartphones et tablettes (`mobile_scanner`).
   - Parseur GS1 DataMatrix complet extrayant automatiquement :
     - `(01)` : Identifiant GTIN / CIP-13.
     - `(17)` : Date de péremption au format `jj/mm/aaaa` (avec gestion du jour `00` en fin de mois).
     - `(10)` : Numéro de lot (gestion FNC1 / ASCII 29).
     - `(21)` : Numéro de série unitaire.
   - Détection EAN-13 classique avec bascule automatique de focus sur la saisie manuelle de péremption.

2. **Règles Strictes de Saisie des Dates (`jj/mm/aaaa`)** :
   - Clavier restreint aux chiffres.
   - Insertion automatique des barres obliques `/` après le 2e et le 4e chiffre.
   - Contrôle de validité calendaire (années bissextiles, limites par mois).

3. **Moteur FEFO (*First Expired, First Out*)** :
   - Décrémentation automatique sur le lot à échéance la plus proche pour éviter le gaspillage.
   - Traçabilité sanitaire par patient (nom/initiales) pour rappel de lot.

4. **Tableau de Bord & Alertes Sémantiques** :
   - 🔴 **Périmé** : Alerte critique pour retrait immédiat.
   - 🟠 **Péremption < 90 jours** : Alerte préventive pour dispensation prioritaire.
   - 🟢 **Valide** : Produit conforme.

5. **Sauvegarde & Rapports Documentaires** :
   - Sauvegarde et restauration complète au format JSON.
   - Export de l'inventaire en CSV.
   - Impression et export de rapports PDF médicaux officiels (état du stock, alertes de péremption).

---

## Déploiement PWA
L'application est déployée en Progressive Web App (PWA) installable sur tout ordinateur, tablette ou smartphone à l'adresse suivante :
👉 **[https://bkhmondocteur.github.io/docpocket-medocs/](https://bkhmondocteur.github.io/docpocket-medocs/)**
