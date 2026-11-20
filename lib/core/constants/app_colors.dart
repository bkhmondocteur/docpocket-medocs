import 'package:flutter/material.dart';

/// Palette médicale épurée, moderne et contrastée pour DocPocket Medocs
class AppColors {
  // Bleus médicaux
  static const Color primaryBlue = Color(0xFF1565C0);       // Bleu médical principal
  static const Color primaryDark = Color(0xFF0D47A1);       // Bleu foncé contrasté
  static const Color primaryLight = Color(0xFFE3F2FD);      // Bleu ciel très clair (arrière-plans)
  static const Color primaryAccent = Color(0xFF0288D1);     // Bleu cyan d'accent

  // Gris ardoise & neutres
  static const Color slateDark = Color(0xFF263238);        // Ardoise sombre (titres & textes forts)
  static const Color slateMedium = Color(0xFF546E7A);      // Ardoise moyenne (sous-titres)
  static const Color slateLight = Color(0xFFECEFF1);       // Gris doux (bordures & séparateurs)
  static const Color background = Color(0xFFF8FAFC);       // Blanc cassé médical très propre
  static const Color cardSurface = Colors.white;

  // Badges d'alertes sémantiques
  // 1. Rouge : Produit périmé
  static const Color alertExpired = Color(0xFFD32F2F);
  static const Color alertExpiredLight = Color(0xFFFFEBEE);

  // 2. Orange : Péremption proche (moins de 90 jours)
  static const Color alertWarning = Color(0xFFEF6C00);
  static const Color alertWarningLight = Color(0xFFFFF3E0);

  // 3. Vert : Produit valide (> 90 jours)
  static const Color alertValid = Color(0xFF2E7D32);
  static const Color alertValidLight = Color(0xFFE8F5E9);

  // Ombres douces
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: slateDark.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ];
}
