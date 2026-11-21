import 'dart:convert';
import 'package:http/http.dart' as http;
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

/// Service de vérification des mises à jour depuis GitHub Releases
class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const String currentVersion = '1.0.1';
  static const int currentBuildNumber = 2;

  static const String githubOwner = 'bkhmondocteur';
  static const String githubRepo = 'docpocket-medocs';

  static const String releasesUrl = 'https://github.com/$githubOwner/$githubRepo/releases';
  static const String latestReleaseApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Vérifie s'il existe une mise à jour sur GitHub
  Future<AppReleaseInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(latestReleaseApi),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name']?.toString() ?? 'v1.0.0';
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
    } catch (_) {
      return null;
    }
  }

  /// Ouvre l'URL de téléchargement direct ou la page de la release
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Ouvre la page générale des releases sur GitHub
  Future<void> openReleasesPage() async {
    await openUrl(releasesUrl);
  }

  /// Compare deux tags de version (ex: 'v1.0.1' vs '1.0.0')
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
