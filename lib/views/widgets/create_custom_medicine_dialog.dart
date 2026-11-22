import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/medicines_catalog_service.dart';

/// Boîte de dialogue pour créer et ajouter un médicament non répertorié dans la base officielle
/// Champs : Nom commercial, DCI, Forme galénique, Boîte de combien ou Volume, et Laboratoire
class CreateCustomMedicineDialog extends StatefulWidget {
  final String? initialName;

  const CreateCustomMedicineDialog({super.key, this.initialName});

  static Future<CatalogMedicine?> show(BuildContext context, {String? initialName}) {
    return showDialog<CatalogMedicine>(
      context: context,
      builder: (_) => CreateCustomMedicineDialog(initialName: initialName),
    );
  }

  @override
  State<CreateCustomMedicineDialog> createState() => _CreateCustomMedicineDialogState();
}

class _CreateCustomMedicineDialogState extends State<CreateCustomMedicineDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _dciController = TextEditingController();
  final _formController = TextEditingController();
  final _packagingController = TextEditingController();
  final _labController = TextEditingController();

  bool _isLoading = false;

  final List<String> _commonForms = [
    'Comprimé',
    'Gélule',
    'Sirop',
    'Suspension buvable',
    'Sachet poudre',
    'Solution injectable',
    'Crème',
    'Pommade',
    'Collyre',
    'Suppositoire',
    'Gouttes',
    'Spray',
  ];

  final List<String> _commonPackagings = [
    'Boîte de 7',
    'Boîte de 10',
    'Boîte de 14',
    'Boîte de 15',
    'Boîte de 20',
    'Boîte de 28',
    'Boîte de 30',
    'Boîte de 60',
    'Flacon de 60 ml',
    'Flacon de 100 ml',
    'Flacon de 125 ml',
    'Flacon de 150 ml',
    'Flacon de 200 ml',
    'Tube de 30 g',
    'Tube de 50 g',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
      _nameController.text = widget.initialName!.trim();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dciController.dispose();
    _formController.dispose();
    _packagingController.dispose();
    _labController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final dci = _dciController.text.trim();
      final form = _formController.text.trim();
      final packaging = _packagingController.text.trim();
      final lab = _labController.text.trim();

      final created = await MedicinesCatalogService.instance.addCustomMedicine(
        commercialName: name,
        dci: dci,
        form: form,
        packagingOrVolume: packaging,
        laboratory: lab,
      );

      if (mounted) {
        Navigator.of(context).pop(created);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Médicament "$name" ajouté au catalogue avec succès !'),
            backgroundColor: AppColors.alertValid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.alertExpired),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En-tête
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.playlist_add_rounded, color: AppColors.primaryBlue, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nouveau Médicament',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Ajouter un médicament non répertorié dans la base',
                              style: TextStyle(fontSize: 12, color: AppColors.slateMedium),
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
                  const SizedBox(height: 18),

                  // 1. Nom commercial
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nom commercial du médicament *',
                      hintText: 'Ex: Esocare 20, Panadol 500 mg, Mag 2...',
                      prefixIcon: const Icon(Icons.medication_rounded, color: AppColors.primaryBlue),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom commercial est obligatoire' : null,
                  ),
                  const SizedBox(height: 14),

                  // 2. DCI (Dénomination Commune Internationale)
                  TextFormField(
                    controller: _dciController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'DCI (Principe actif)',
                      hintText: 'Ex: Esoméprazole, Paracétamol, Magnésium...',
                      prefixIcon: const Icon(Icons.science_rounded, color: AppColors.primaryBlue),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Forme galénique
                  TextFormField(
                    controller: _formController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Forme galénique *',
                      hintText: 'Ex: Comprimé, Gélule, Sirop, Solution injectable...',
                      prefixIcon: const Icon(Icons.category_rounded, color: AppColors.primaryBlue),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'La forme galénique est obligatoire' : null,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _commonForms.map((f) {
                      return ActionChip(
                        label: Text(f, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _formController.text == f ? Colors.blue.shade100 : Colors.grey.shade100,
                        onPressed: () {
                          setState(() => _formController.text = f);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 4. Boîte de combien ou Volume
                  TextFormField(
                    controller: _packagingController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Boîte de combien ou Flacon de combien *',
                      hintText: 'Ex: Boîte de 7, Boîte de 14, Boîte de 28, Flacon de 100 ml, Flacon de 125 ml...',
                      prefixIcon: const Icon(Icons.inventory_2_rounded, color: AppColors.primaryBlue),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Veuillez préciser la boîte ou le flacon (ex: Boîte de 14, Flacon de 100 ml)' : null,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _commonPackagings.map((pkg) {
                      return ActionChip(
                        label: Text(pkg, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _packagingController.text == pkg ? Colors.teal.shade100 : Colors.grey.shade100,
                        onPressed: () {
                          setState(() => _packagingController.text = pkg);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 5. Laboratoire fabricant
                  TextFormField(
                    controller: _labController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Laboratoire fabricant',
                      hintText: 'Ex: Sanofi, Opalia, Unimed, Teriak, Saiph, Medis...',
                      prefixIcon: const Icon(Icons.business_rounded, color: AppColors.primaryBlue),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Boutons d'action
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isLoading ? null : _submit,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_rounded, size: 20),
                          label: Text(
                            _isLoading ? 'Création...' : 'Créer & Assigner',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
