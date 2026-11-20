import '../formatters/strict_date_formatter.dart';

enum BarcodeType {
  gs1DataMatrix,
  ean13,
  unknown,
}

/// Résultat détaillé de l'analyse d'un code-barres médical scanné
class ParsedMedicalBarcode {
  final BarcodeType type;
  final String rawInput;
  final String? gtin;                // Code GTIN / CIP-13
  final String? lotNumber;           // AI (10)
  final String? expiryDateFormatted; // Format jj/mm/aaaa issu de AI (17)
  final DateTime? expiryDateTime;
  final String? serialNumber;        // AI (21)
  final bool requiresManualExpiry;   // Vrai si EAN-13 sans données de péremption

  ParsedMedicalBarcode({
    required this.type,
    required this.rawInput,
    this.gtin,
    this.lotNumber,
    this.expiryDateFormatted,
    this.expiryDateTime,
    this.serialNumber,
    required this.requiresManualExpiry,
  });

  bool get isGs1 => type == BarcodeType.gs1DataMatrix;
  bool get isEan13 => type == BarcodeType.ean13;

  @override
  String toString() {
    return 'ParsedMedicalBarcode(type: $type, gtin: $gtin, lot: $lotNumber, '
        'expiry: $expiryDateFormatted, serial: $serialNumber, manualExp: $requiresManualExpiry)';
  }
}

/// Parseur médical spécialisé GS1 DataMatrix (pharmaceutique) & EAN-13
class Gs1DataMatrixParser {
  static const String groupSeparator = '\x1D'; // FNC1 ou ASCII 29

  /// Analyse une chaîne brute issue de la douchette USB ou de la caméra mobile
  static ParsedMedicalBarcode parse(String rawInput) {
    final cleaned = rawInput.trim();

    if (cleaned.isEmpty) {
      return ParsedMedicalBarcode(
        type: BarcodeType.unknown,
        rawInput: rawInput,
        requiresManualExpiry: true,
      );
    }

    // 1. Détection EAN-13 classique / CIP-13 (13 chiffres consécutifs stricts)
    if (RegExp(r'^\d{13}$').hasMatch(cleaned)) {
      return ParsedMedicalBarcode(
        type: BarcodeType.ean13,
        rawInput: cleaned,
        gtin: cleaned,
        lotNumber: null,
        expiryDateFormatted: null,
        expiryDateTime: null,
        serialNumber: null,
        requiresManualExpiry: true,
      );
    }

    // Détection EAN-8 (8 chiffres)
    if (RegExp(r'^\d{8}$').hasMatch(cleaned)) {
      return ParsedMedicalBarcode(
        type: BarcodeType.ean13,
        rawInput: cleaned,
        gtin: cleaned,
        lotNumber: null,
        expiryDateFormatted: null,
        expiryDateTime: null,
        serialNumber: null,
        requiresManualExpiry: true,
      );
    }

    // 2. Détection GS1 avec Application Identifiers entre parenthèses
    // Ex: (01)03400930000014(17)260531(10)LOT123(21)SN456
    if (cleaned.contains('(') && cleaned.contains(')')) {
      return _parseParenthesized(cleaned);
    }

    // 3. Détection DataMatrix GS1 au format brut continu standard
    return _parseRawStream(cleaned);
  }

  /// Traitement du format lisible parenthésé
  static ParsedMedicalBarcode _parseParenthesized(String input) {
    String? gtin;
    String? lot;
    String? expiryStr;
    DateTime? expiryDate;
    String? serial;

    final regex = RegExp(r'\((01|17|10|21)\)([^()]+)');
    final matches = regex.allMatches(input);

    for (final match in matches) {
      final ai = match.group(1);
      final value = match.group(2)?.trim();

      if (ai == '01' && value != null) {
        gtin = _normalizeGtin(value);
      } else if (ai == '17' && value != null) {
        final parsed = _parseGs1Date(value);
        if (parsed != null) {
          expiryDate = parsed;
          expiryStr = StrictDateValidator.format(parsed);
        }
      } else if (ai == '10' && value != null) {
        lot = value;
      } else if (ai == '21' && value != null) {
        serial = value;
      }
    }

    final hasData = gtin != null || lot != null || expiryStr != null;
    return ParsedMedicalBarcode(
      type: hasData ? BarcodeType.gs1DataMatrix : BarcodeType.unknown,
      rawInput: input,
      gtin: gtin,
      lotNumber: lot,
      expiryDateFormatted: expiryStr,
      expiryDateTime: expiryDate,
      serialNumber: serial,
      requiresManualExpiry: expiryStr == null,
    );
  }

  /// Traitement du format continu avec délimiteurs FNC1 / ASCII 29
  static ParsedMedicalBarcode _parseRawStream(String input) {
    String stream = input;
    stream = stream.replaceAll('<GS>', groupSeparator);
    stream = stream.replaceAll('~29', groupSeparator);

    String? gtin;
    String? lot;
    String? expiryStr;
    DateTime? expiryDate;
    String? serial;

    int idx = 0;
    while (idx < stream.length) {
      // Ignorer séparateurs en début de bloc
      while (idx < stream.length && stream[idx] == groupSeparator) {
        idx++;
      }
      if (idx >= stream.length) break;

      if (idx + 2 <= stream.length) {
        final ai = stream.substring(idx, idx + 2);

        // AI (01) : GTIN (longueur fixe 14 chiffres)
        if (ai == '01') {
          idx += 2;
          if (idx + 14 <= stream.length) {
            gtin = _normalizeGtin(stream.substring(idx, idx + 14));
            idx += 14;
            continue;
          }
        }

        // AI (17) : Date d'expiration (longueur fixe 6 chiffres YYMMDD)
        if (ai == '17') {
          idx += 2;
          if (idx + 6 <= stream.length) {
            final rawDate = stream.substring(idx, idx + 6);
            final parsed = _parseGs1Date(rawDate);
            if (parsed != null) {
              expiryDate = parsed;
              expiryStr = StrictDateValidator.format(parsed);
            }
            idx += 6;
            continue;
          }
        }

        // AI (10) : Numéro de lot (longueur variable jusqu'à 20 car.)
        if (ai == '10') {
          idx += 2;
          final end = stream.indexOf(groupSeparator, idx);
          if (end != -1) {
            lot = stream.substring(idx, end);
            idx = end + 1;
          } else {
            lot = stream.substring(idx);
            idx = stream.length;
          }
          continue;
        }

        // AI (21) : Numéro de série (longueur variable)
        if (ai == '21') {
          idx += 2;
          final end = stream.indexOf(groupSeparator, idx);
          if (end != -1) {
            serial = stream.substring(idx, end);
            idx = end + 1;
          } else {
            serial = stream.substring(idx);
            idx = stream.length;
          }
          continue;
        }
      }

      idx++;
    }

    final hasData = gtin != null || lot != null || expiryStr != null;
    return ParsedMedicalBarcode(
      type: hasData ? BarcodeType.gs1DataMatrix : BarcodeType.unknown,
      rawInput: input,
      gtin: gtin,
      lotNumber: lot,
      expiryDateFormatted: expiryStr,
      expiryDateTime: expiryDate,
      serialNumber: serial,
      requiresManualExpiry: expiryStr == null,
    );
  }

  /// Normalisation GTIN (supprime le 0 de tête du GTIN-14 pour les CIP-13)
  static String _normalizeGtin(String raw) {
    final clean = raw.trim();
    if (clean.length == 14 && clean.startsWith('0')) {
      return clean.substring(1);
    }
    return clean;
  }

  /// Conversion de la date GS1 YYMMDD
  /// Règle GS1 : si le jour est 00, on prend le dernier jour du mois
  static DateTime? _parseGs1Date(String yymmdd) {
    if (yymmdd.length != 6) return null;
    final yy = int.tryParse(yymmdd.substring(0, 2));
    final mm = int.tryParse(yymmdd.substring(2, 4));
    final dd = int.tryParse(yymmdd.substring(4, 6));

    if (yy == null || mm == null || dd == null) return null;
    if (mm < 1 || mm > 12) return null;

    final year = 2000 + yy;

    int day = dd;
    if (day == 0) {
      day = StrictDateValidator.daysInMonth(mm, year);
    } else {
      final maxDays = StrictDateValidator.daysInMonth(mm, year);
      if (day > maxDays) day = maxDays;
    }

    return DateTime(year, mm, day);
  }
}
