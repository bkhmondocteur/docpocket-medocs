import 'package:flutter/services.dart';

/// Résultat de la validation d'une date médicale
class DateValidationResult {
  final bool isValid;
  final String? errorMessage;
  final DateTime? parsedDate;

  DateValidationResult.valid(this.parsedDate)
      : isValid = true,
        errorMessage = null;

  DateValidationResult.invalid(this.errorMessage)
      : isValid = false,
        parsedDate = null;
}

/// Validateur strict des dates médicales au format jj/mm/aaaa
class StrictDateValidator {
  /// Valide rigoureusement une date saisie en chaîne jj/mm/aaaa
  static DateValidationResult validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return DateValidationResult.invalid('La date est obligatoire.');
    }

    final trimmed = input.trim();
    final regex = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
    final match = regex.firstMatch(trimmed);

    if (match == null) {
      return DateValidationResult.invalid('Format invalide (attendu : jj/mm/aaaa).');
    }

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);

    if (day == null || month == null || year == null) {
      return DateValidationResult.invalid('Valeurs numériques invalides.');
    }

    if (year < 1980 || year > 2100) {
      return DateValidationResult.invalid("L'année doit être comprise entre 1980 et 2100.");
    }

    if (month < 1 || month > 12) {
      return DateValidationResult.invalid('Le mois doit être compris entre 01 et 12.');
    }

    final maxDays = daysInMonth(month, year);
    if (day < 1 || day > maxDays) {
      return DateValidationResult.invalid(
        'Jour invalide : le mois $month/$year compte au maximum $maxDays jours.',
      );
    }

    return DateValidationResult.valid(DateTime(year, month, day));
  }

  /// Retourne le nombre exact de jours dans un mois (avec prise en compte des années bissextiles)
  static int daysInMonth(int month, int year) {
    if (month == 2) {
      final isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return isLeapYear ? 29 : 28;
    }
    const days30 = [4, 6, 9, 11];
    return days30.contains(month) ? 30 : 31;
  }

  /// Formate un DateTime en jj/mm/aaaa
  static String format(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }
}

/// Formateur de texte automatique pour les champs de date :
/// - Ne retient que les chiffres
/// - Insère automatiquement le '/' après le 2e et le 4e chiffre
/// - Gère le curseur pour que la frappe et le retour arrière soient naturels
class StrictDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Si suppression (texte plus court)
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    // Extraire uniquement les chiffres
    final rawDigits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limiter à 8 chiffres (JJMMAAAA)
    final digits = rawDigits.length > 8 ? rawDigits.substring(0, 8) : rawDigits;

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) {
        buffer.write('/');
      }
      buffer.write(digits[i]);
    }

    final formattedText = buffer.toString();
    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
