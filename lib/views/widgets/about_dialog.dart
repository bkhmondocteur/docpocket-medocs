import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_update_service.dart';

/// Boîte de dialogue "À propos de DocPocket Medocs" avec téléchargement direct et installation in-app
class AboutDocPocketDialog extends StatefulWidget {
  const AboutDocPocketDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const AboutDocPocketDialog(),
    );
  }

  @override
  State<AboutDocPocketDialog> createState() => _AboutDocPocketDialogState();
}

class _AboutDocPocketDialogState extends State<AboutDocPocketDialog> {
  bool _isCheckingUpdate = false;
  AppReleaseInfo? _releaseInfo;
  String? _updateError;

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';
  String? _downloadedFilePath;

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateError = null;
    });

    final info = await AppUpdateService.instance.checkForUpdate();

    if (mounted) {
      setState(() {
        _isCheckingUpdate = false;
        _releaseInfo = info;
        if (info == null) {
          _updateError = 'Impossible de joindre le serveur GitHub.';
        }
      });
    }
  }

  Future<void> _startInAppDownload(String url) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Connexion au serveur GitHub...';
    });

    await AppUpdateService.instance.downloadAndInstallApk(
      url: url,
      onProgress: (progress, received, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = total > 0 ? (total / (1024 * 1024)).toStringAsFixed(1) : '75.3';
            final pct = (progress * 100).toInt();
            _downloadStatusText = 'Téléchargement : $pct% ($receivedMb Mo / $totalMb Mo)';
          });
        }
      },
      onDownloaded: (filePath) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloadProgress = 1.0;
            _downloadedFilePath = filePath;
            _downloadStatusText = 'Téléchargement terminé ! Installation en cours...';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Téléchargement terminé ! Ouverture de l\'installateur Android...'),
              backgroundColor: AppColors.alertValid,
              duration: Duration(seconds: 4),
            ),
          );
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloadStatusText = '';
          });
          // Fallback : ouverture dans le navigateur
          _downloadApk(url);
        }
      },
    );
  }

  Future<void> _downloadApk(String url) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Lancement du téléchargement dans le navigateur...')),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.primaryBlue,
      ),
    );

    final success = await AppUpdateService.instance.openUrl(url);

    if (!success && mounted) {
      await AppUpdateService.instance.copyToClipboard(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lien de téléchargement copié dans le presse-papiers !',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Collez le lien dans Google Chrome ou votre navigateur pour installer l\'APK.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _copyUrl(String url) async {
    await AppUpdateService.instance.copyToClipboard(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lien APK copié dans le presse-papiers ! Collez-le dans votre navigateur.'),
          backgroundColor: AppColors.alertValid,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const version = AppUpdateService.currentVersion;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 740),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête avec Logo et Nom
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.primaryLight,
                        child: const Icon(Icons.medication_liquid_rounded, color: AppColors.primaryBlue, size: 32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DocPocket Medocs',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slateDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Version $version (Android & Web)',
                          style: TextStyle(fontSize: 13, color: AppColors.primaryBlue, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Description et finalité médicale
              const Text(
                'DocPocket Medocs est une application professionnelle conçue pour les cabinets médicaux, assurant la traçabilité complète des échantillons médicaux offerts par les délégués pharmaceutiques.',
                style: TextStyle(fontSize: 13, color: AppColors.slateDark, height: 1.4),
              ),
              const SizedBox(height: 14),

              // Fonctionnalités clés
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.slateLight.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    _FeatureRow(icon: Icons.auto_awesome_rounded, text: 'Traçabilité FEFO stricte (anti-périmés)'),
                    SizedBox(height: 6),
                    _FeatureRow(icon: Icons.qr_code_scanner_rounded, text: 'Scan direct Douchette USB & Caméra mobile'),
                    SizedBox(height: 6),
                    _FeatureRow(icon: Icons.menu_book_rounded, text: 'Dictionnaire officiel de 5 063 médicaments'),
                    SizedBox(height: 6),
                    _FeatureRow(icon: Icons.notifications_active_rounded, text: 'Notifications péremptions (<3m, <1m, périmés)'),
                    SizedBox(height: 6),
                    _FeatureRow(icon: Icons.security_rounded, text: 'Sauvegardes automatiques rotatives & 100% hors-ligne'),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Section Mises à jour
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.system_update_rounded, color: AppColors.primaryBlue, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Mise à jour de l\'application',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slateDark),
                            ),
                          ],
                        ),
                        if (_isCheckingUpdate)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.primaryBlue),
                            tooltip: 'Rechercher',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _checkUpdate,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Barre de progression du téléchargement direct in-app
                    if (_isDownloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _downloadProgress > 0 ? _downloadProgress : null,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _downloadStatusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                      ),
                      const SizedBox(height: 10),
                    ] else if (_downloadedFilePath != null) ...[
                      // Si l'APK a été téléchargé avec succès
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: AppColors.alertValid, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'APK téléchargé avec succès !',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.alertValid),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.install_mobile_rounded),
                                label: const Text('Installer maintenant la mise à jour'),
                                onPressed: () => AppUpdateService.instance.installApk(_downloadedFilePath!),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (!_isDownloading && _releaseInfo != null) ...[
                      if (_releaseInfo!.isNewer) ...[
                        Row(
                          children: [
                            const Icon(Icons.new_releases_rounded, color: Colors.orange, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Nouvelle version disponible : ${_releaseInfo!.tagName}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('Télécharger & Installer (Direct)'),
                                onPressed: () {
                                  final url = _releaseInfo!.apkDownloadUrl ?? _releaseInfo!.htmlUrl;
                                  _startInAppDownload(url);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.open_in_browser_rounded, color: AppColors.primaryBlue),
                              tooltip: 'Télécharger via le navigateur',
                              onPressed: () {
                                final url = _releaseInfo!.apkDownloadUrl ?? _releaseInfo!.htmlUrl;
                                _downloadApk(url);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue),
                              tooltip: 'Copier le lien direct',
                              onPressed: () {
                                final url = _releaseInfo!.apkDownloadUrl ?? _releaseInfo!.htmlUrl;
                                _copyUrl(url);
                              },
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.alertValid, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Vous utilisez la version v$version.',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.alertValid, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.download_rounded, size: 18),
                                label: const Text('Télécharger & Réinstaller l\'APK'),
                                onPressed: () {
                                  final url = _releaseInfo?.apkDownloadUrl ?? AppUpdateService.directApkDownloadUrl;
                                  _startInAppDownload(url);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.open_in_browser_rounded, color: AppColors.primaryBlue),
                              tooltip: 'Ouvrir dans le navigateur',
                              onPressed: () {
                                final url = _releaseInfo?.apkDownloadUrl ?? AppUpdateService.directApkDownloadUrl;
                                _downloadApk(url);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue),
                              tooltip: 'Copier le lien APK',
                              onPressed: () {
                                final url = _releaseInfo?.apkDownloadUrl ?? AppUpdateService.directApkDownloadUrl;
                                _copyUrl(url);
                              },
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Lien direct affiché
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link_rounded, size: 16, color: AppColors.slateMedium),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _releaseInfo?.apkDownloadUrl ?? AppUpdateService.directApkDownloadUrl,
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.slateDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                final url = _releaseInfo?.apkDownloadUrl ?? AppUpdateService.directApkDownloadUrl;
                                _copyUrl(url);
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Text('Copier', style: TextStyle(fontSize: 11, color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Bouton d'ouverture directe de la page Releases sur GitHub
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryDark,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.language_rounded, size: 16),
                          label: const Text('Ouvrir la page des versions sur GitHub (Navigateur)', style: TextStyle(fontSize: 12)),
                          onPressed: () => AppUpdateService.instance.openReleasesPage(),
                        ),
                      ),
                    ] else if (!_isDownloading) ...[
                      Text(
                        _updateError ?? 'Vérification terminée.',
                        style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white),
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Télécharger l\'APK direct'),
                              onPressed: () => _startInAppDownload(AppUpdateService.directApkDownloadUrl),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue),
                            tooltip: 'Copier le lien direct',
                            onPressed: () => _copyUrl(AppUpdateService.directApkDownloadUrl),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Bouton Fermer
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.slateDark, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
