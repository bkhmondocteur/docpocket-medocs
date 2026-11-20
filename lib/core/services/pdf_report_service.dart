import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/medicine.dart';
import '../../models/medicine_batch.dart';
import '../../models/stock_alert_level.dart';
import '../formatters/strict_date_formatter.dart';

/// Service d'exportation et d'impression de rapports médicaux PDF
class PdfReportService {
  /// Génère et ouvre la boîte de dialogue d'impression / export PDF de l'état du stock
  static Future<void> printInventoryReport(List<Medicine> medicines) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = StrictDateValidator.formatFull(now);

    int totalBoxes = medicines.fold(0, (s, m) => s + m.totalStock);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(
          title: 'RAPPORT GÉNÉRAL DU STOCK D\'ÉCHANTILLONS',
          subtitle: 'Cabinet Médical - DocPocket Medocs',
          dateStr: dateStr,
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.blue200),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Text('Références uniques : ${medicines.length}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text('Total boîtes en stock : $totalBoxes',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          _buildInventoryTable(medicines),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'DocPocket_Stock_Inventaire_$dateStr.pdf',
    );
  }

  /// Génère le rapport spécifique des produits périmés ou proches de la péremption (< 90 jours)
  static Future<void> printAlertsReport(List<Medicine> medicines) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = StrictDateValidator.formatFull(now);

    // Filtrer uniquement les médicaments avec des lots périmés ou proches de péremption
    final alertBatches = <Map<String, dynamic>>[];

    for (final m in medicines) {
      for (final b in m.batches) {
        if (b.quantity > 0 &&
            (b.alertLevel == StockAlertLevel.expired || b.alertLevel == StockAlertLevel.warning)) {
          alertBatches.add({
            'medicine': m,
            'batch': b,
          });
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(
          title: 'RAPPORT D\'ALERTES PÉREMPTIONS & RETRAITS',
          subtitle: 'DocPocket Medocs - Sécurité & Traçabilité Sanitaire',
          dateStr: dateStr,
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange50,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.orange300),
            ),
            child: pw.Text(
              'ATTENTION : Liste des échantillons médicaux périmés (à détruire immédiatement) '
              'ou dont la date de péremption intervient dans moins de 90 jours.',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.orange900, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 16),
          _buildAlertsTable(alertBatches),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'DocPocket_Alertes_Peremptions_$dateStr.pdf',
    );
  }

  static pw.Widget _buildHeader({
    required String title,
    required String subtitle,
    required String dateStr,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.Text('Édité le : $dateStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
        ),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Divider(color: PdfColors.blue800, thickness: 1.5),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('DocPocket Medocs - Usage Professionnel Cabinet Médical',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Page ${context.pageNumber} sur ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    );
  }

  static pw.Widget _buildInventoryTable(List<Medicine> medicines) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Médicament (DCI / Dosage)', isHeader: true),
          _cell('Forme / Classe', isHeader: true),
          _cell('N° Lot', isHeader: true),
          _cell('Péremption', isHeader: true),
          _cell('Stock', isHeader: true, alignRight: true),
          _cell('Statut', isHeader: true),
        ],
      ),
    ];

    for (final m in medicines) {
      if (m.batches.isEmpty) {
        rows.add(
          pw.TableRow(
            children: [
              _cell('${m.commercialName} (${m.dosage})\n${m.dci}'),
              _cell('${m.form}\n${m.therapeuticClass}'),
              _cell('-'),
              _cell('-'),
              _cell('0', alignRight: true),
              _cell('Épuisé'),
            ],
          ),
        );
      } else {
        for (final b in m.batches) {
          final isExpired = b.alertLevel == StockAlertLevel.expired;
          final isWarning = b.alertLevel == StockAlertLevel.warning;

          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: isExpired
                    ? PdfColors.red50
                    : (isWarning ? PdfColors.orange50 : PdfColors.white),
              ),
              children: [
                _cell('${m.commercialName} (${m.dosage})\n${m.dci}'),
                _cell('${m.form}\n${m.therapeuticClass}'),
                _cell(b.batchNumber),
                _cell(b.expiryDateFormatted),
                _cell('${b.quantity}', alignRight: true),
                _cell(b.alertLevel.label),
              ],
            ),
          );
        }
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: rows,
    );
  }

  static pw.Widget _buildAlertsTable(List<Map<String, dynamic>> alertBatches) {
    if (alertBatches.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(20),
        child: pw.Center(
          child: pw.Text(
            'Aucune alerte : aucun échantillon périmé ou proche de la péremption !',
            style: pw.TextStyle(color: PdfColors.green700, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Médicament', isHeader: true),
          _cell('Laboratoire', isHeader: true),
          _cell('N° Lot', isHeader: true),
          _cell('Date Péremption', isHeader: true),
          _cell('Quantité', isHeader: true, alignRight: true),
          _cell('Alerte', isHeader: true),
        ],
      ),
    ];

    for (final item in alertBatches) {
      final m = item['medicine'] as Medicine;
      final b = item['batch'] as MedicineBatch;
      final isExpired = b.alertLevel == StockAlertLevel.expired;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isExpired ? PdfColors.red100 : PdfColors.orange100,
          ),
          children: [
            _cell('${m.commercialName} ${m.dosage}\n(${m.dci})'),
            _cell(m.laboratory),
            _cell(b.batchNumber),
            _cell(b.expiryDateFormatted),
            _cell('${b.quantity}', alignRight: true),
            _cell(
              isExpired
                  ? 'PÉRIMÉ (Rebut)'
                  : 'Périme dans ${b.remainingDays} jours',
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: rows,
    );
  }

  static pw.Widget _cell(String text, {bool isHeader = false, bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
