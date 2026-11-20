import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/medicines_catalog_service.dart';

/// Boîte de dialogue de recherche et sélection dans la base de données des 5 112 médicaments
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
                const Icon(Icons.menu_book_rounded, color: AppColors.primaryBlue, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Base de Données Médicaments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slateDark,
                        ),
                      ),
                      Text(
                        'Sélectionnez le médicament à assigner au code scanné',
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

            // Champ de recherche dynamique
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, DCI ou laboratoire (ex: Doliprane, Amox)...',
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
            const SizedBox(height: 12),

            // Compteur de résultats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isLoading
                      ? 'Recherche en cours...'
                      : '${_results.length} résultat(s) affiché(s) sur ${MedicinesCatalogService.instance.count} médicaments',
                  style: const TextStyle(fontSize: 12, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),

            // Liste des résultats
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun médicament trouvé.\nEssayez un autre terme de recherche.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.slateMedium),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (context, idx) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final med = _results[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.medication_rounded, color: AppColors.primaryBlue, size: 24),
                              ),
                              title: Text(
                                med.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (med.dci.isNotEmpty)
                                    Text(
                                      'DCI : ${med.dci}',
                                      style: const TextStyle(color: AppColors.primaryDark, fontSize: 12.5),
                                    ),
                                  Text(
                                    '${med.form}${med.dosage.isNotEmpty ? " • ${med.dosage}" : ""}${med.laboratory.isNotEmpty ? " • ${med.laboratory}" : ""}',
                                    style: const TextStyle(color: AppColors.slateMedium, fontSize: 11.5),
                                  ),
                                  if (med.therapeuticClass.isNotEmpty)
                                    Text(
                                      med.therapeuticClass,
                                      style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => Navigator.of(context).pop(med),
                                child: const Text('Assigner'),
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
