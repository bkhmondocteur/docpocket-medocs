import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/license_service.dart';
import '../../core/services/supabase_sync_service.dart';
import '../../models/cabinet_auth.dart';

/// Boîte de dialogue permettant au Médecin de générer et gérer les codes d'accès de sa Secrétaire
class SecretaryManagementDialog extends StatefulWidget {
  const SecretaryManagementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SecretaryManagementDialog(),
    );
  }

  @override
  State<SecretaryManagementDialog> createState() => _SecretaryManagementDialogState();
}

class _SecretaryManagementDialogState extends State<SecretaryManagementDialog> {
  final _nameController = TextEditingController();
  SecretaryDelegation? _justGeneratedDelegation;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez saisir le Nom et Prénom de la secrétaire.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final delegation = await LicenseService.instance.createSecretaryDelegation(secretaryName: name);

      // Pousser immédiatement vers Supabase Cloud
      await SupabaseSyncService.instance.pushDelegation(delegation);

      setState(() {
        _justGeneratedDelegation = delegation;
        _nameController.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la génération : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delegations = LicenseService.instance.delegations;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.badge_rounded, color: AppColors.primaryBlue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gestion Accès Secrétaire',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Déléguez la gestion du stock de votre cabinet à votre secrétaire. Elle pourra effectuer les entrées et sorties en parfaite synchronisation avec votre appareil.',
                style: TextStyle(fontSize: 13, color: AppColors.slateMedium),
              ),
              const SizedBox(height: 16),

              // Formulaire de génération
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Créer un nouvel accès pour votre secrétaire :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.slateDark),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Nom et Prénom de la secrétaire *',
                        hintText: 'Ex: Sonia Ben Ali',
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isLoading ? null : _generateCode,
                      icon: _isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.key_rounded, size: 18),
                      label: Text(
                        _isLoading ? 'Génération...' : 'Générer le Code d\'Accès Secrétaire',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Code tout juste généré
              if (_justGeneratedDelegation != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Code d\'accès pour ${_justGeneratedDelegation!.secretaryName} :',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _justGeneratedDelegation!.accessCode,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  fontFamily: 'monospace',
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue, size: 20),
                              tooltip: 'Copier le code',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _justGeneratedDelegation!.accessCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Code secrétaire copié !')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Transmettez ce code à votre secrétaire. À l\'ouverture de son application (APK ou PWA), elle choisit "Je suis Secrétaire" et introduit ce code.',
                        style: TextStyle(fontSize: 11.5, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                ),
              ],

              // Historique des codes générés
              if (delegations.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Accès secrétaires actifs :',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.slateDark),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: delegations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (ctx, index) {
                      final del = delegations[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              del.isActive ? Icons.verified_user_rounded : Icons.block_rounded,
                              size: 18,
                              color: del.isActive ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(del.secretaryName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(del.accessCode, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.primaryBlue)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              tooltip: 'Copier',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: del.accessCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Code copié !')),
                                );
                              },
                            ),
                            if (del.isActive)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                tooltip: 'Révoquer l\'accès',
                                onPressed: () async {
                                  await LicenseService.instance.revokeDelegation(del.id);
                                  setState(() {});
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
