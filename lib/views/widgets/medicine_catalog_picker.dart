import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/medicines_catalog_service.dart';

/// Boîte de dialogue de sélection épurée : affiche SEULEMENT le nom commercial, la forme et boîte/flacon
class MedicineCatalogPickerDialog extends StatefulWidget {
  final String? initialQuery;

  const MedicineCatalogPickerDialog({super.key, this.initialQuery});

  static Future<CatalogMedicine?> show(BuildContext context, {String? initialQuery}) {
    return showDialog<CatalogMedicine>(
      context: context,
      builder: (_) => MedicineCatalogPickerDialog(initialQuery: initialQuery),
    );
  }

  @override
  State<MedicineCatalogPickerDialog> createState() => _MedicineCatalogPickerDialogState();
}

class _MedicineCatalogPickerDialogState extends State<MedicineCatalogPickerDialog> {
  final _searchController = TextEditingController();
  List<CatalogMedicine> _results = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
    }
    _performSearch(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    final results = await MedicinesCatalogService.instance.search(query, limit: 60);
    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.medication_rounded, color: AppColors.primaryBlue, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choisir le Médicament',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slateDark,
                        ),
                      ),
                      Text(
                        'Nom commercial, forme et conditionnement (boîte / flacon)',
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
            const SizedBox(height: 16),

            // Champ de recherche rapide
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher un médicament (ex: Doliprane, Augmentin, Kardegic)...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryBlue),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.slateLight.withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: _performSearch,
            ),
            const SizedBox(height: 10),

            // Compteur de résultats
            Text(
              _isLoading
                  ? 'Recherche en cours...'
                  : '${_results.length} médicament(s) affiché(s)',
              style: const TextStyle(fontSize: 12, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            const Divider(),

            // Liste épurée : SEULEMENT Nom Commercial, Forme, et Boîte ou Flacon
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun médicament correspondant.',
                            style: TextStyle(color: AppColors.slateMedium),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final med = _results[index];
                            final pkg = med.packaging;
                            final form = med.form;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  pkg.toLowerCase().contains('flacon')
                                      ? Icons.medication_liquid_rounded
                                      : Icons.medication_rounded,
                                  color: AppColors.primaryBlue,
                                  size: 24,
                                ),
                              ),
                              // 1. NOM COMMERCIAL
                              title: Text(
                                med.cleanCommercialName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.5,
                                  color: AppColors.slateDark,
                                ),
                              ),
                              // 2. FORME ET BOÎTE / FLACON DE COMBIEN
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (form.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.blue.shade200),
                                        ),
                                        child: Text(
                                          form,
                                          style: TextStyle(
                                            color: Colors.blue.shade900,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    if (pkg.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.teal.shade200),
                                        ),
                                        child: Text(
                                          pkg,
                                          style: TextStyle(
                                            color: Colors.teal.shade900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => Navigator.of(context).pop(med),
                                child: const Text('Choisir'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
