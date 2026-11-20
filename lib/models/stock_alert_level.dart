import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// Niveaux d'alertes visuelles et sémantiques pour les dates de péremption
enum StockAlertLevel {
  valid,    // Conforme : Péremption dans plus de 90 jours (Vert)
  warning,  // Attention : Péremption dans 90 jours ou moins (Orange)
  expired,  // Alerte critique : Produit déjà périmé (Rouge)
}

extension StockAlertLevelExt on StockAlertLevel {
  String get label {
    switch (this) {
      case StockAlertLevel.expired:
        return 'Périmé';
      case StockAlertLevel.warning:
        return 'Périme < 90j';
      case StockAlertLevel.valid:
        return 'Valide';
    }
  }

  Color get color {
    switch (this) {
      case StockAlertLevel.expired:
        return AppColors.alertExpired;
      case StockAlertLevel.warning:
        return AppColors.alertWarning;
      case StockAlertLevel.valid:
        return AppColors.alertValid;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case StockAlertLevel.expired:
        return AppColors.alertExpiredLight;
      case StockAlertLevel.warning:
        return AppColors.alertWarningLight;
      case StockAlertLevel.valid:
        return AppColors.alertValidLight;
    }
  }

  IconData get icon {
    switch (this) {
      case StockAlertLevel.expired:
        return Icons.error_outline_rounded;
      case StockAlertLevel.warning:
        return Icons.warning_amber_rounded;
      case StockAlertLevel.valid:
        return Icons.check_circle_outline_rounded;
    }
  }
}
