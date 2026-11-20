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

/// Validateur strict des dates médicales au format MM/AAAA (ex: 11/2028)
class StrictDateValidator {
  /// Valide rigoureusement une date saisie en chaîne MM/AAAA (ex: 11/2028)
  /// Accepte prioritairement MM/AAAA, mais tolère aussi MM/AA ou JJ/MM/AAAA
  static DateValidationResult validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return DateValidationResult.invalid('La date de péremption est obligatoire.');
    }

    final trimmed = input.trim();

    // 1. Format médical prioritaire : MM/AAAA (ex: 11/2028)
    final regexMonthYear = RegExp(r'^(\d{2})/(\d{4})$');
    final matchMY = regexMonthYear.firstMatch(trimmed);
    if (matchMY != null) {
      final month = int.tryParse(matchMY.group(1)!);
      final year = int.tryParse(matchMY.group(2)!);

      if (month == null || year == null) {
        return DateValidationResult.invalid('Valeurs numériques invalides.');
      }
      if (month < 1 || month > 12) {
        return DateValidationResult.invalid('Le mois doit être compris entre 01 et 12.');
      }
      if (year < 2020 || year > 2100) {
        return DateValidationResult.invalid("L'année doit être comprise entre 2020 et 2100.");
      }

      // Règle pharmaceutique : expiration à la fin du mois indiqué
      final lastDay = daysInMonth(month, year);
      return DateValidationResult.valid(DateTime(year, month, lastDay, 23, 59, 59));
    }

    // 2. Format court : MM/AA (ex: 11/28 -> 11/2028)
    final regexShort = RegExp(r'^(\d{2})/(\d{2})$');
    final matchShort = regexShort.firstMatch(trimmed);
    if (matchShort != null) {
      final month = int.tryParse(matchShort.group(1)!);
      final shortYear = int.tryParse(matchShort.group(2)!);
      if (month != null && shortYear != null && month >= 1 && month <= 12) {
        final year = 2000 + shortYear;
        final lastDay = daysInMonth(month, year);
        return DateValidationResult.valid(DateTime(year, month, lastDay, 23, 59, 59));
      }
    }

    // 3. Format complet toléré : JJ/MM/AAAA (ex: si importé ou scanné avec jour)
    final regexFull = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
    final matchFull = regexFull.firstMatch(trimmed);
    if (matchFull != null) {
      final day = int.tryParse(matchFull.group(1)!);
      final month = int.tryParse(matchFull.group(2)!);
      final year = int.tryParse(matchFull.group(3)!);

      if (day != null && month != null && year != null) {
        if (month >= 1 && month <= 12 && year >= 2020 && year <= 2100) {
          final maxDays = daysInMonth(month, year);
          if (day >= 1 && day <= maxDays) {
            return DateValidationResult.valid(DateTime(year, month, day, 23, 59, 59));
          }
        }
      }
    }

    return DateValidationResult.invalid('Format attendu : MM/AAAA (ex: 11/2028)');
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

  /// Formate un DateTime strictement en MM/AAAA (ex: 11/2028)
  static String format(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$m/$y';
  }

  /// Formate un DateTime complet en JJ/MM/AAAA (ex: pour date d'impression de rapport)
  static String formatFull(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }
}

/// Formateur de texte automatique pour saisie MM/AAAA :
/// - Ne retient que les chiffres
/// - Insère automatiquement le '/' après le 2e chiffre (MM/AAAA)
/// - Limite à 6 chiffres max
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

    // Limiter à 6 chiffres (MMAAAA)
    final digits = rawDigits.length > 6 ? rawDigits.substring(0, 6) : rawDigits;

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 2) {
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
