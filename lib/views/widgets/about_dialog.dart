import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_update_service.dart';

/// Boîte de dialogue "À propos de DocPocket Medocs" avec vérification et téléchargement direct de l'APK
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
            Expanded(child: Text('Lancement du téléchargement APK dans le navigateur...')),
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
        width: 520,
        constraints: const BoxConstraints(maxHeight: 700),
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
                    _FeatureRow(icon: Icons.picture_as_pdf_rounded, text: 'Rapports PDF & exports CSV pour inventaires'),
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

                    if (_isCheckingUpdate)
                      const Text(
                        'Recherche de nouvelles versions sur GitHub...',
                        style: TextStyle(fontSize: 12, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
                      )
                    else if (_releaseInfo != null) ...[
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
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('Télécharger la mise à jour (APK)'),
                                onPressed: () {
                                  final url = _releaseInfo!.apkDownloadUrl ?? _releaseInfo!.htmlUrl;
                                  _downloadApk(url);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue),
                              tooltip: 'Copier le lien de téléchargement',
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
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                                label: const Text('Télécharger l\'APK Android'),
                                onPressed: () {
                                  final url = _releaseInfo?.apkDownloadUrl ?? AppUpdateService.directApkDownloadUrl;
                                  _downloadApk(url);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
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
                      // Lien de téléchargement direct affiché
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
                    ] else ...[
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
                              onPressed: () => _downloadApk(AppUpdateService.directApkDownloadUrl),
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
