import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/services/license_service.dart';
import '../core/services/supabase_sync_service.dart';
import 'dashboard_view.dart';

/// Écran d'accueil et d'authentification par rôle (Médecin ou Secrétaire)
class WelcomeAuthView extends StatefulWidget {
  const WelcomeAuthView({super.key});

  @override
  State<WelcomeAuthView> createState() => _WelcomeAuthViewState();
}

class _WelcomeAuthViewState extends State<WelcomeAuthView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Contrôleurs Médecin
  final _doctorNomController = TextEditingController();
  final _doctorPrenomController = TextEditingController();
  final _doctorOrderController = TextEditingController();
  final _doctorKeyController = TextEditingController();

  // Contrôleurs Secrétaire
  final _secNameController = TextEditingController();
  final _secCodeController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Pré-remplir si un profil docteur a déjà été enregistré sur cet appareil
    final savedDoctor = LicenseService.instance.doctorProfile;
    if (savedDoctor != null) {
      _doctorNomController.text = savedDoctor.nom;
      _doctorPrenomController.text = savedDoctor.prenom;
      _doctorOrderController.text = savedDoctor.orderNumber;
      _doctorKeyController.text = savedDoctor.licenseKey;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _doctorNomController.dispose();
    _doctorPrenomController.dispose();
    _doctorOrderController.dispose();
    _doctorKeyController.dispose();
    _secNameController.dispose();
    _secCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleDoctorSubmit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final nom = _doctorNomController.text.trim();
      final prenom = _doctorPrenomController.text.trim();
      final order = _doctorOrderController.text.trim();
      final key = _doctorKeyController.text.trim();

      if (nom.isEmpty || prenom.isEmpty || order.isEmpty) {
        throw Exception('Veuillez renseigner votre Nom, Prénom et Numéro d\'Ordre.');
      }
      if (key.isEmpty) {
        throw Exception('Veuillez saisir votre clé de licence officielle (DOC-XXXX-YYYY-ZZZZ-WWWW).');
      }

      await LicenseService.instance.verifyAndActivateDoctor(
        nom: nom,
        prenom: prenom,
        orderNumber: order,
        licenseKey: key,
      );

      // Synchroniser immédiatement avec Supabase Cloud
      await SupabaseSyncService.instance.syncStock(actionDescription: 'Activation Médecin');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardView()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSecretarySubmit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = _secNameController.text.trim();
      final code = _secCodeController.text.trim().toUpperCase();

      if (name.isEmpty) {
        throw Exception('Veuillez introduire votre Nom et Prénom.');
      }
      if (code.isEmpty) {
        throw Exception('Veuillez introduire le Code d\'Accès fourni par le Médecin.');
      }

      // 1. Tenter d'abord la validation locale ou distante Supabase
      String? remoteCabinetId;
      try {
        final remoteDel = await SupabaseSyncService.instance.findRemoteDelegation(code);
        if (remoteDel != null) {
          remoteCabinetId = (remoteDel['cabinet_id'] ?? remoteDel['cabinetId']) as String?;
          debugPrint('[WelcomeAuth] Délégation distante validée pour le cabinet : $remoteCabinetId');
        }
      } catch (_) {}

      final session = await LicenseService.instance.activateSecretary(
        secretaryName: name,
        accessCode: code,
        cabinetId: remoteCabinetId,
      );

      if (session == null) {
        throw Exception('Code d\'accès introuvable ou révoqué par le médecin.');
      }

      // Synchroniser le stock du cabinet depuis Supabase
      await SupabaseSyncService.instance.syncStock(actionDescription: 'Connexion Secrétaire : $name');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardView()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo & En-tête
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: AppColors.primaryLight,
                          child: const Icon(Icons.medication_rounded, color: AppColors.primaryBlue, size: 40),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'DocPocket Medocs',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.slateDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Gestion d\'échantillons médicaux & synchronisation multiplateforme',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.slateMedium),
                  ),
                  const SizedBox(height: 24),

                  // Message d'erreur éventuel
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Sélecteur de Rôle : Médecin ou Secrétaire
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      labelColor: AppColors.primaryDark,
                      unselectedLabelColor: AppColors.slateMedium,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.medical_services_rounded, size: 20),
                          text: 'Je suis Médecin',
                        ),
                        Tab(
                          icon: Icon(Icons.badge_rounded, size: 20),
                          text: 'Je suis Secrétaire',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Contenu des onglets
                  SizedBox(
                    height: 460,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDoctorCard(),
                        _buildSecretaryCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Activation Cabinet Médecin',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.slateDark),
            ),
            const SizedBox(height: 3),
            const Text(
              'Renseignez votre identité et la clé de licence délivrée par l\'éditeur :',
              style: TextStyle(fontSize: 12, color: AppColors.slateMedium),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _doctorNomController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Nom du Médecin *',
                hintText: 'Ex: BEN KHALIFA',
                prefixIcon: const Icon(Icons.person_rounded, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _doctorPrenomController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Prénom du Médecin *',
                hintText: 'Ex: Mohamed',
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _doctorOrderController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Numéro d\'Ordre des Médecins *',
                hintText: 'Ex: 12345',
                prefixIcon: const Icon(Icons.numbers_rounded, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _doctorKeyController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Clé de Licence officielle *',
                hintText: 'DOC-XXXX-YYYY-ZZZZ-WWWW',
                prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                filled: true,
                fillColor: Colors.blue.shade50.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _handleDoctorSubmit,
              icon: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.lock_open_rounded),
              label: Text(
                _isLoading ? 'Vérification...' : 'Activer et Déverrouiller le Cabinet',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecretaryCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Gestion déléguée du stock cabinet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.slateDark),
            ),
            const SizedBox(height: 4),
            const Text(
              'Introduisez votre nom et le code d\'accès que le médecin vous a généré depuis son application.',
              style: TextStyle(fontSize: 12.5, color: AppColors.slateMedium),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _secNameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Votre Nom et Prénom *',
                hintText: 'Ex: Sonia Ben Ali',
                prefixIcon: const Icon(Icons.person_rounded, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Code d\'accès fourni par le Médecin *',
                hintText: 'Ex: SEC-4891-2048',
                prefixIcon: const Icon(Icons.key_rounded, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _handleSecretarySubmit,
              icon: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.login_rounded),
              label: Text(
                _isLoading ? 'Vérification...' : 'Valider et Accéder au Stock',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
