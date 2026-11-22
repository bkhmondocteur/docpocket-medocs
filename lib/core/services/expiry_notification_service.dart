import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/medicine.dart';
import '../../models/medicine_batch.dart';

/// Catégorie d'alerte de péremption
enum ExpiryAlertCategory {
  /// Déjà périmé (jours restants <= 0)
  expired,

  /// Péremption imminente dans moins d'un mois (1 à 30 jours)
  within1Month,

  /// Péremption dans 1 à 3 mois (31 à 90 jours)
  within3Months,
}

/// Représente un lot spécifique nécessitant une alerte de péremption
class ExpiryAlertItem {
  final Medicine medicine;
  final MedicineBatch batch;
  final int daysRemaining;
  final ExpiryAlertCategory category;

  const ExpiryAlertItem({
    required this.medicine,
    required this.batch,
    required this.daysRemaining,
    required this.category,
  });

  String get categoryLabel {
    switch (category) {
      case ExpiryAlertCategory.expired:
        return 'Périmé';
      case ExpiryAlertCategory.within1Month:
        return '< 1 mois';
      case ExpiryAlertCategory.within3Months:
        return '< 3 mois';
    }
  }

  String get relativeTimeText {
    if (daysRemaining < 0) {
      return 'Périmé depuis ${-daysRemaining} jour${-daysRemaining > 1 ? "s" : ""}';
    } else if (daysRemaining == 0) {
      return 'Périme aujourd\'hui !';
    } else {
      return 'Périme dans $daysRemaining jour${daysRemaining > 1 ? "s" : ""}';
    }
  }
}

/// Synthèse complète des alertes de péremption pour les stocks actifs (> 0)
class ExpirySummary {
  final List<ExpiryAlertItem> expired;
  final List<ExpiryAlertItem> within1Month;
  final List<ExpiryAlertItem> within3Months;

  const ExpirySummary({
    required this.expired,
    required this.within1Month,
    required this.within3Months,
  });

  int get totalCount => expired.length + within1Month.length + within3Months.length;
  bool get hasAlerts => totalCount > 0;

  int get totalBoxesExpired => expired.fold(0, (sum, i) => sum + i.batch.quantity);
  int get totalBoxes1Month => within1Month.fold(0, (sum, i) => sum + i.batch.quantity);
  int get totalBoxes3Months => within3Months.fold(0, (sum, i) => sum + i.batch.quantity);
  int get totalBoxesAlerted => totalBoxesExpired + totalBoxes1Month + totalBoxes3Months;
}

/// Service de gestion et d'envoi des notifications de péremption
class ExpiryNotificationService {
  static final ExpiryNotificationService instance = ExpiryNotificationService._internal();
  ExpiryNotificationService._internal();

  static const String _prefAutoNotifyKey = 'docpocket_auto_notify_expiries';
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialise le plugin de notification sur toutes les plateformes
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Ouvrir');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[ExpiryNotification] Clic sur notification : ${response.payload}');
      },
    );

    _initialized = true;
  }

  /// Demande la permission d'afficher des notifications (Android 13+ et iOS)
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        final androidPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          final granted = await androidPlugin.requestNotificationsPermission();
          return granted ?? false;
        }
      } else if (Platform.isIOS || Platform.isMacOS) {
        final iosPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final granted = await iosPlugin.requestPermissions(alert: true, badge: true, sound: true);
          return granted ?? false;
        }
      }
    } catch (e) {
      debugPrint('[ExpiryNotification] Erreur demande permission: $e');
    }
    return true;
  }

  /// Calcule la synthèse des alertes de péremption
  /// RÈGLE STRICTE : Ne prend en compte QUE les lots dont la quantité en stock est > 0
  ExpirySummary computeSummary(List<Medicine> medicines) {
    final expired = <ExpiryAlertItem>[];
    final within1Month = <ExpiryAlertItem>[];
    final within3Months = <ExpiryAlertItem>[];

    for (final med in medicines) {
      for (final batch in med.batches) {
        // Condition explicite : stock strictement supérieur à zéro
        if (batch.quantity <= 0) continue;

        final days = batch.remainingDays;

        if (days <= 0) {
          expired.add(ExpiryAlertItem(
            medicine: med,
            batch: batch,
            daysRemaining: days,
            category: ExpiryAlertCategory.expired,
          ));
        } else if (days <= 30) {
          within1Month.add(ExpiryAlertItem(
            medicine: med,
            batch: batch,
            daysRemaining: days,
            category: ExpiryAlertCategory.within1Month,
          ));
        } else if (days <= 90) {
          within3Months.add(ExpiryAlertItem(
            medicine: med,
            batch: batch,
            daysRemaining: days,
            category: ExpiryAlertCategory.within3Months,
          ));
        }
      }
    }

    // Trier chaque catégorie par date de péremption la plus urgente
    expired.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    within1Month.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    within3Months.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    return ExpirySummary(
      expired: expired,
      within1Month: within1Month,
      within3Months: within3Months,
    );
  }

  /// Envoie une notification système sur le smartphone (Android / iOS / Desktop)
  Future<bool> sendSystemNotification(List<Medicine> medicines) async {
    final summary = computeSummary(medicines);
    if (!summary.hasAlerts) {
      return false;
    }

    await init();
    await requestPermission();

    // Construction du titre et résumé
    final title = '⚠️ DocPocket : ${summary.totalCount} alerte${summary.totalCount > 1 ? "s" : ""} de péremption';

    final lines = <String>[];
    if (summary.expired.isNotEmpty) {
      lines.add('🔴 ${summary.expired.length} lot(s) périmé(s) (${summary.totalBoxesExpired} boîte(s))');
    }
    if (summary.within1Month.isNotEmpty) {
      lines.add('🟠 ${summary.within1Month.length} lot(s) < 1 mois (${summary.totalBoxes1Month} boîte(s))');
    }
    if (summary.within3Months.isNotEmpty) {
      lines.add('🟡 ${summary.within3Months.length} lot(s) < 3 mois (${summary.totalBoxes3Months} boîte(s))');
    }

    final body = lines.join('  •  ');

    // Détail étendu pour la notification déroulante
    final bigText = StringBuffer();
    bigText.writeln(body);
    bigText.writeln();

    if (summary.expired.isNotEmpty) {
      bigText.writeln('🔴 À retirer immédiatement :');
      for (final item in summary.expired.take(3)) {
        bigText.writeln('  • ${item.medicine.commercialName} (Lot ${item.batch.batchNumber}) : ${item.batch.quantity} boîte(s)');
      }
    }

    if (summary.within1Month.isNotEmpty) {
      bigText.writeln('🟠 Priorité FEFO urgente (< 1 mois) :');
      for (final item in summary.within1Month.take(3)) {
        bigText.writeln('  • ${item.medicine.commercialName} (Lot ${item.batch.batchNumber}, Exp ${item.batch.expiryDateFormatted})');
      }
    }

    if (summary.within3Months.isNotEmpty) {
      bigText.writeln('🟡 À surveiller (< 3 mois) :');
      for (final item in summary.within3Months.take(2)) {
        bigText.writeln('  • ${item.medicine.commercialName} (Lot ${item.batch.batchNumber}, Exp ${item.batch.expiryDateFormatted})');
      }
    }

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'docpocket_expiry_alerts',
        'Alertes de Péremption',
        channelDescription: 'Notifications pour les médicaments périmés ou proches de la péremption',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(
          bigText.toString(),
          contentTitle: title,
          summaryText: '${summary.totalBoxesAlerted} boîte(s) concernée(s)',
        ),
        icon: '@mipmap/ic_launcher',
      ),
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        1001,
        title,
        body,
        notificationDetails,
      );
      return true;
    } catch (e) {
      debugPrint('[ExpiryNotification] Erreur lors de l\'envoi de la notification: $e');
      return false;
    }
  }

  /// Savoir si la notification automatique à l'ouverture est activée
  Future<bool> isAutoNotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoNotifyKey) ?? true;
  }

  /// Activer ou désactiver la notification automatique à l'ouverture
  Future<void> setAutoNotifyEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoNotifyKey, enabled);
  }
}
