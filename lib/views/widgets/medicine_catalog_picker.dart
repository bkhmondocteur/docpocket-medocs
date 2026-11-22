import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/medicines_catalog_service.dart';
import 'create_custom_medicine_dialog.dart';

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

            // Compteur de résultats & Bouton d'ajout manuel
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isLoading
                      ? 'Recherche en cours...'
                      : '${_results.length} médicament(s) affiché(s)',
                  style: const TextStyle(fontSize: 12, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primaryBlue,
                  ),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final query = _searchController.text.trim();
                    final created = await CreateCustomMedicineDialog.show(
                      context,
                      initialName: query.isNotEmpty ? query : null,
                    );
                    if (created != null) {
                      nav.pop(created);
                    }
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: const Text('+ Ajouter un médicament', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Bouton dynamique pour ajouter directement le nom saisi s'il n'est pas répertorié
            if (_searchController.text.trim().isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    'Ajouter "${_searchController.text.trim()}"',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.primaryDark),
                  ),
                  subtitle: const Text(
                    'Introuvable dans la base ? Saisir Nom, DCI, Forme, Boîte/Flacon et Labo',
                    style: TextStyle(fontSize: 11, color: AppColors.slateMedium),
                  ),
                  trailing: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final query = _searchController.text.trim();
                      final created = await CreateCustomMedicineDialog.show(
                        context,
                        initialName: query,
                      );
                      if (created != null) {
                        nav.pop(created);
                      }
                    },
                  ),
                ),
              ),
            ],
            const Divider(),

            // Liste épurée : SEULEMENT Nom Commercial, Forme, et Boîte ou Flacon
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  _searchController.text.trim().isEmpty
                                      ? 'Aucun médicament trouvé.'
                                      : 'Aucun résultat pour "${_searchController.text.trim()}"',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Ce médicament ne figure pas dans la base de données ?\nAjoutez-le avec son Nom, sa DCI, sa Forme, sa Boîte/Flacon et son Laboratoire.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.slateMedium, fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () async {
                                    final nav = Navigator.of(context);
                                    final query = _searchController.text.trim();
                                    final created = await CreateCustomMedicineDialog.show(
                                      context,
                                      initialName: query.isNotEmpty ? query : null,
                                    );
                                    if (created != null) {
                                      nav.pop(created);
                                    }
                                  },
                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                  label: Text(
                                    _searchController.text.trim().isNotEmpty
                                        ? 'Ajouter "${_searchController.text.trim()}"'
                                        : 'Ajouter ce médicament',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
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
