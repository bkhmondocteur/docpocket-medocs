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
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 600,
        height: 650,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.medication_rounded, color: AppColors.primaryBlue, size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choisir le Médicament',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slateDark,
                        ),
                      ),
                      Text(
                        'Nom, forme et conditionnement',
                        style: TextStyle(fontSize: 11.5, color: AppColors.slateMedium),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Champ de recherche rapide
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher un médicament (Doliprane, etc.)...',
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                fillColor: AppColors.slateLight.withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: _performSearch,
            ),
            const SizedBox(height: 8),

            // Compteur de résultats & Bouton d'ajout manuel
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isLoading
                        ? 'Recherche en cours...'
                        : '${_results.length} résultat(s)',
                    style: const TextStyle(fontSize: 12, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  label: const Text('Nouveau médicament', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),

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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text(
                    'Introuvable dans la base ? Créer la fiche',
                    style: TextStyle(fontSize: 11, color: AppColors.slateMedium),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

                            return InkWell(
                              onTap: () => Navigator.of(context).pop(med),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        pkg.toLowerCase().contains('flacon')
                                            ? Icons.medication_liquid_rounded
                                            : Icons.medication_rounded,
                                        color: AppColors.primaryBlue,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            med.cleanCommercialName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5,
                                              color: AppColors.slateDark,
                                            ),
                                          ),
                                          if (form.isNotEmpty || pkg.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 3),
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  if (form.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                                                          fontSize: 11.5,
                                                        ),
                                                      ),
                                                    ),
                                                  if (pkg.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                                                          fontSize: 11.5,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primaryBlue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        visualDensity: VisualDensity.compact,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => Navigator.of(context).pop(med),
                                      child: const Text('Choisir', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
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
