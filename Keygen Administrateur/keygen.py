#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DocPocket Medocs - Keygen Éditeur Officiel (Ligne de commande)
Générateur de clés de licence pour le médecin titulaire.
Usage:
    python keygen.py "BEN KHALIFA" "Mohamed" "12345"
"""

import sys
import hashlib
import re

SALT = "DOCPOCKET_MEDOCS_TUNISIE_2026_SECURE_SALT"

def normalize_text(text: str) -> str:
    return re.sub(r'\s+', ' ', text.strip().upper())

def generate_license(nom: str, prenom: str, order_number: str):
    clean_nom = normalize_text(nom)
    clean_prenom = normalize_text(prenom)
    clean_order = order_number.strip()

    raw_key = f"{clean_nom}|{clean_prenom}|{clean_order}|{SALT}"
    digest = hashlib.sha256(raw_key.encode('utf-8')).hexdigest().upper()

    b1 = digest[0:4]
    b2 = digest[4:8]
    b3 = digest[8:12]
    b4 = digest[12:16]
    license_key = f"DOC-{b1}-{b2}-{b3}-{b4}"

    raw_cab = f"{clean_order}|{clean_nom}|{SALT}"
    cab_digest = hashlib.sha256(raw_cab.encode('utf-8')).hexdigest().upper()
    cabinet_id = f"CAB-{clean_order.zfill(5)}-{cab_digest[0:6]}"

    return license_key, cabinet_id, clean_nom, prenom.strip(), clean_order

def main():
    if len(sys.argv) >= 4:
        nom = sys.argv[1]
        prenom = sys.argv[2]
        order = sys.argv[3]
    else:
        print("=" * 60)
        print("DOCPOCKET MEDOCS - GÉNÉRATEUR DE LICENCES (KEYGEN ÉDITEUR)")
        print("=" * 60)
        nom = input("Nom du Médecin (ex: BEN KHALIFA) : ").strip()
        prenom = input("Prénom du Médecin (ex: Mohamed) : ").strip()
        order = input("Numéro d'Ordre des Médecins (ex: 12345) : ").strip()

    if not nom or not prenom or not order:
        print("Erreur: Tous les champs sont obligatoires.")
        sys.exit(1)

    key, cab_id, c_nom, c_prenom, c_order = generate_license(nom, prenom, order)

    print("\n" + "=" * 60)
    print(f"Dr. {c_nom} {c_prenom} (Ordre N° {c_order})")
    print(f"Cabinet ID : {cab_id}")
    print(f"Clé de Licence Officielle : {key}")
    print("=" * 60)
    print("\nMessage prêt à transmettre :")
    print(f"Cher Dr. {c_nom} {c_prenom},")
    print("Voici votre clé d'activation officielle pour DocPocket Medocs :")
    print(f"🔑 Clé : {key}")
    print(f"📋 N° Ordre : {c_order}\n")

if __name__ == "__main__":
    main()
