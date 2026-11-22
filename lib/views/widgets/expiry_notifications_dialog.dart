import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/expiry_notification_service.dart';
import '../../models/medicine.dart';
import '../medicine_detail_view.dart';
import '../stock_exit_view.dart';

/// Centre des alertes et notifications de péremption
class ExpiryNotificationsDialog extends StatefulWidget {
  final List<Medicine> medicines;
  final VoidCallback onDataChanged;

  const ExpiryNotificationsDialog({
    super.key,
    required this.medicines,
    required this.onDataChanged,
  });

  static Future<void> show(BuildContext context, {required List<Medicine> medicines, required VoidCallback onDataChanged}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ExpiryNotificationsDialog(
        medicines: medicines,
        onDataChanged: onDataChanged,
      ),
    );
  }

  @override
  State<ExpiryNotificationsDialog> createState() => _ExpiryNotificationsDialogState();
}

class _ExpiryNotificationsDialogState extends State<ExpiryNotificationsDialog> {
  bool _autoNotify = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await ExpiryNotificationService.instance.isAutoNotifyEnabled();
    if (mounted) {
      setState(() => _autoNotify = enabled);
    }
  }

  Future<void> _toggleAutoNotify(bool value) async {
    setState(() => _autoNotify = value);
    await ExpiryNotificationService.instance.setAutoNotifyEnabled(value);
  }

  Future<void> _triggerNotification(ExpirySummary summary) async {
    setState(() => _isSending = true);
    final sent = await ExpiryNotificationService.instance.sendSystemNotification(widget.medicines);
    if (!mounted) return;
    setState(() => _isSending = false);

    if (sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text('Notification de péremption envoyée dans la barre d\'état du téléphone !'),
              ),
            ],
          ),
          backgroundColor: AppColors.alertValid,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune alerte à notifier ou notifications non autorisées sur cet appareil.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ExpiryNotificationService.instance.computeSummary(widget.medicines);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 740),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: summary.expired.isNotEmpty
                        ? AppColors.alertExpired.withValues(alpha: 0.12)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: summary.expired.isNotEmpty ? AppColors.alertExpired : Colors.orange.shade800,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Alertes Péremptions en Stock',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.slateDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Uniquement pour les échantillons avec stock > 0',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
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
            const SizedBox(height: 14),

            // Cartes de synthèse
            Row(
              children: [
                _buildSummaryBadge(
                  label: 'Périmés',
                  count: summary.expired.length,
                  boxes: summary.totalBoxesExpired,
                  color: AppColors.alertExpired,
                  bgColor: Colors.red.shade50,
                ),
                const SizedBox(width: 8),
                _buildSummaryBadge(
                  label: '< 1 mois',
                  count: summary.within1Month.length,
                  boxes: summary.totalBoxes1Month,
                  color: Colors.orange.shade800,
                  bgColor: Colors.orange.shade50,
                ),
                const SizedBox(width: 8),
                _buildSummaryBadge(
                  label: '< 3 mois',
                  count: summary.within3Months.length,
                  boxes: summary.totalBoxes3Months,
                  color: Colors.amber.shade900,
                  bgColor: Colors.amber.shade50,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bouton Envoi Notification & Option automatique
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text(
                        'Envoyer la notification sur le téléphone',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: summary.hasAlerts && !_isSending ? () => _triggerNotification(summary) : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Interrupteur notification automatique
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Notifier automatiquement à l\'ouverture si des lots nécessitent attention',
                    style: TextStyle(fontSize: 11.5, color: AppColors.slateMedium),
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _autoNotify,
                    activeThumbColor: AppColors.primaryBlue,
                    onChanged: _toggleAutoNotify,
                  ),
                ),
              ],
            ),
            const Divider(height: 14),

            // Liste détaillée des alertes
            Expanded(
              child: !summary.hasAlerts
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_user_rounded, color: AppColors.alertValid, size: 44),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucune alerte de péremption !',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.slateDark),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tous vos échantillons en stock ont une date de péremption supérieure à 3 mois.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.slateMedium, fontSize: 12.5),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      children: [
                        if (summary.expired.isNotEmpty) ...[
                          _buildSectionHeader('🔴 Médicaments déjà périmés (${summary.expired.length})', AppColors.alertExpired),
                          ...summary.expired.map((item) => _buildAlertCard(item)),
                          const SizedBox(height: 12),
                        ],
                        if (summary.within1Month.isNotEmpty) ...[
                          _buildSectionHeader('🟠 Péremption dans moins d\'un mois (${summary.within1Month.length})', Colors.orange.shade800),
                          ...summary.within1Month.map((item) => _buildAlertCard(item)),
                          const SizedBox(height: 12),
                        ],
                        if (summary.within3Months.isNotEmpty) ...[
                          _buildSectionHeader('🟡 Péremption dans 1 à 3 mois (${summary.within3Months.length})', Colors.amber.shade900),
                          ...summary.within3Months.map((item) => _buildAlertCard(item)),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 10),

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
    );
  }

  Widget _buildSummaryBadge({
    required String label,
    required int count,
    required int boxes,
    required Color color,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              '$boxes bte${boxes > 1 ? "s" : ""}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        title,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildAlertCard(ExpiryAlertItem item) {
    final med = item.medicine;
    final batch = item.batch;

    Color badgeColor;
    Color cardBorder;
    switch (item.category) {
      case ExpiryAlertCategory.expired:
        badgeColor = AppColors.alertExpired;
        cardBorder = Colors.red.shade200;
        break;
      case ExpiryAlertCategory.within1Month:
        badgeColor = Colors.orange.shade800;
        cardBorder = Colors.orange.shade200;
        break;
      case ExpiryAlertCategory.within3Months:
        badgeColor = Colors.amber.shade900;
        cardBorder = Colors.amber.shade200;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorder),
      ),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    med.commercialName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.slateDark),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    item.relativeTimeText,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${med.dci} • ${med.dosage} • ${med.form}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.slateMedium),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lot : ${batch.batchNumber}  •  Exp : ${batch.expiryDateFormatted}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${batch.quantity} boîte${batch.quantity > 1 ? "s" : ""}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 15),
                  label: const Text('Fiche', style: TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MedicineDetailView(medicine: med)),
                    ).then((_) {
                      widget.onDataChanged();
                      if (mounted) setState(() {});
                    });
                  },
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: item.category == ExpiryAlertCategory.expired ? AppColors.alertExpired : AppColors.primaryDark,
                    side: BorderSide(
                      color: item.category == ExpiryAlertCategory.expired ? AppColors.alertExpired : AppColors.primaryDark,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: Icon(
                    item.category == ExpiryAlertCategory.expired ? Icons.delete_sweep_rounded : Icons.output_rounded,
                    size: 15,
                  ),
                  label: Text(
                    item.category == ExpiryAlertCategory.expired ? 'Retirer' : 'Remise FEFO',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StockExitView()),
                    ).then((_) {
                      widget.onDataChanged();
                      if (mounted) setState(() {});
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
