import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Modèle d'une release GitHub
class AppReleaseInfo {
  final String tagName;
  final String title;
  final String notes;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final DateTime? publishedAt;
  final bool isNewer;

  const AppReleaseInfo({
    required this.tagName,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.publishedAt,
    required this.isNewer,
  });
}

/// Service de vérification, de téléchargement direct et d'installation des mises à jour
class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const String currentVersion = '1.0.8';
  static const int currentBuildNumber = 9;

  static const String githubOwner = 'bkhmondocteur';
  static const String githubRepo = 'docpocket-medocs';

  static const String releasesUrl = 'https://github.com/$githubOwner/$githubRepo/releases';
  static const String directApkDownloadUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest/download/app-release.apk';
  static const String latestReleaseApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Vérifie s'il existe une mise à jour sur GitHub avec fallback résilient
  Future<AppReleaseInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(latestReleaseApi),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final tagName = data['tag_name']?.toString() ?? 'v1.0.8';
        final title = data['name']?.toString() ?? tagName;
        final notes = data['body']?.toString() ?? '';
        final htmlUrl = data['html_url']?.toString() ?? releasesUrl;
        final publishedStr = data['published_at']?.toString();
        final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

        // Chercher l'asset APK dans la release
        String? apkUrl;
        final assets = data['assets'] as List<dynamic>? ?? [];
        for (final asset in assets) {
          final name = asset['name']?.toString() ?? '';
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url']?.toString();
            break;
          }
        }

        // Si pas d'apk spécifique, fallback vers l'URL de téléchargement direct de la release
        apkUrl ??= 'https://github.com/$githubOwner/$githubRepo/releases/download/$tagName/app-release.apk';

        final isNewer = _compareVersions(tagName, currentVersion) > 0;

        return AppReleaseInfo(
          tagName: tagName,
          title: title,
          notes: notes,
          htmlUrl: htmlUrl,
          apkDownloadUrl: apkUrl,
          publishedAt: publishedAt,
          isNewer: isNewer,
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] CheckForUpdate API error: $e');
    }

    // Fallback résilient si GitHub API est indisponible ou rate-limité (60 req/h)
    return const AppReleaseInfo(
      tagName: 'Dernière version',
      title: 'DocPocket Medocs APK',
      notes: 'Téléchargement direct de la version la plus récente depuis GitHub.',
      htmlUrl: releasesUrl,
      apkDownloadUrl: directApkDownloadUrl,
      publishedAt: null,
      isNewer: false,
    );
  }

  /// Télécharge le fichier APK directement dans l'application avec progression en temps réel,
  /// puis déclenche automatiquement l'installateur de paquets Android.
  Future<void> downloadAndInstallApk({
    required String url,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
    required void Function(String filePath) onDownloaded,
    required void Function(String error) onError,
  }) async {
    if (kIsWeb) {
      // Sur le web, ouvrir directement le lien dans un nouvel onglet
      await openUrl(url);
      return;
    }

    http.Client? client;
    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode >= 400) {
        onError('Erreur de téléchargement serveur (Code HTTP ${response.statusCode})');
        return;
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final file = File(p.join(tempDir.path, 'DocPocket-Medocs-Update.apk'));
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final progress = contentLength > 0 ? (received / contentLength).clamp(0.0, 1.0) : 0.0;
        onProgress(progress, received, contentLength);
      }

      await sink.flush();
      await sink.close();
      client.close();

      onDownloaded(file.path);

      // Lancer automatiquement l'installateur Android
      await installApk(file.path);
    } catch (e) {
      client?.close();
      debugPrint('[AppUpdateService] Erreur downloadAndInstallApk: $e');
      onError('Échec du téléchargement direct : $e');
    }
  }

  /// Déclenche l'installateur d'application Android via open_filex
  Future<bool> installApk(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[AppUpdateService] Le fichier APK n\'existe pas : $filePath');
        return false;
      }

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('[AppUpdateService] Erreur installApk: $e');
      return false;
    }
  }

  /// Ouvre l'URL dans le navigateur externe avec gestion multi-niveaux et tolérance aux pannes
  Future<bool> openUrl(String url) async {
    try {
      final uri = Uri.parse(url);

      // Niveau 1 : Tenter d'ouvrir l'application externe (navigateur Chrome, Samsung Internet, Firefox...)
      final launchedExternal = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launchedExternal) return true;

      // Niveau 2 : Tenter avec le mode platformDefault
      final launchedDefault = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
      if (launchedDefault) return true;

      // Niveau 3 : Tenter avec inAppBrowserView si externe échoue
      return await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Erreur launchUrl pour $url : $e');
      try {
        // Ultime tentative directe sans mode spécifié
        return await launchUrl(Uri.parse(url));
      } catch (_) {
        return false;
      }
    }
  }

  /// Copie l'URL dans le presse-papiers du smartphone/PC
  Future<void> copyToClipboard(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
  }

  /// Ouvre la page générale des releases sur GitHub
  Future<bool> openReleasesPage() async {
    return await openUrl(releasesUrl);
  }

  /// Compare deux tags de version (ex: 'v1.0.8' vs '1.0.7')
  /// Renvoie > 0 si v1 > v2, 0 si égal, < 0 si v1 < v2
  int _compareVersions(String v1, String v2) {
    final clean1 = v1.replaceAll(RegExp(r'[^0-9.]'), '');
    final clean2 = v2.replaceAll(RegExp(r'[^0-9.]'), '');

    final parts1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  }
}
