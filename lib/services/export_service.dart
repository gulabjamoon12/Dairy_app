import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

/// Data class for passing PDF parameters to isolate
class _PdfParams {
  final List<Map<String, dynamic>> data;
  final String startDateStr;
  final String endDateStr;
  
  _PdfParams({
    required this.data,
    required this.startDateStr,
    required this.endDateStr,
  });
}

class ExportService {
  // OPTIMIZATION: Static DateFormat instances (avoid creating on every call)
  static final _dateFormat = DateFormat('dd MMM, yyyy');
  
  /// Generate PDF bytes in an isolate to avoid blocking UI
  static Future<Uint8List> _generatePdfBytes(_PdfParams params) async {
    final pdf = pw.Document();
    
    // Pre-calculate totals
    double totalMilkQty = 0.0;
    double totalDahi = 0.0;
    double totalGhee = 0.0;
    double totalBill = 0.0;
    double totalReceived = 0.0;
    double totalDue = 0.0;
    
    for (var row in params.data) {
      totalMilkQty += (row['milk_qty'] as num?)?.toDouble() ?? 0.0;
      totalDahi += (row['dahi_total'] as num?)?.toDouble() ?? 0.0;
      totalGhee += (row['ghee_total'] as num?)?.toDouble() ?? 0.0;
      totalBill += (row['total_bill'] as num?)?.toDouble() ?? 0.0;
      totalReceived += (row['received'] as num?)?.toDouble() ?? 0.0;
      totalDue += (row['global_due'] as num?)?.toDouble() ?? 0.0;
    }
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(
            children: [
              pw.Text(
                'Business Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${params.startDateStr} - ${params.endDateStr}',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: const {
              0: pw.FixedColumnWidth(30),
              1: pw.FlexColumnWidth(2.5),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(1),
              5: pw.FlexColumnWidth(1.2),
              6: pw.FlexColumnWidth(1.2),
              7: pw.FlexColumnWidth(1.2),
              8: pw.FlexColumnWidth(1),
            },
            children: [
              // Header row
              _buildHeaderRow(),
              // Data rows
              ...params.data.asMap().entries.map((entry) => _buildDataRow(entry.key, entry.value)),
              // Footer row with totals
              _buildTotalRow(totalMilkQty, totalDahi, totalGhee, totalBill, totalReceived, totalDue),
            ],
          ),
        ],
      ),
    );
    
    return pdf.save();
  }

  static pw.TableRow _buildHeaderRow() {
    final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _buildCell('Sr. No.', boldStyle, pw.TextAlign.center),
        _buildCell('Customer Name', boldStyle, pw.TextAlign.left),
        _buildCell('Milk (L)', boldStyle, pw.TextAlign.right),
        _buildCell('Dahi (Rs)', boldStyle, pw.TextAlign.right),
        _buildCell('Ghee (Rs)', boldStyle, pw.TextAlign.right),
        _buildCell('Total Bill (Rs)', boldStyle, pw.TextAlign.right),
        _buildCell('Paid (Rs)', boldStyle, pw.TextAlign.right),
        _buildCell('Global Balance (Rs)', boldStyle, pw.TextAlign.right),
        _buildCell('Avg Rate (Rs)', boldStyle, pw.TextAlign.right),
      ],
    );
  }

  static pw.TableRow _buildDataRow(int index, Map<String, dynamic> row) {
    const style = pw.TextStyle(fontSize: 9);
    return pw.TableRow(
      children: [
        _buildCell('${index + 1}', style, pw.TextAlign.center),
        _buildCell(row['name'] as String, style, pw.TextAlign.left),
        _buildCell((row['milk_qty'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
        _buildCell((row['dahi_total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
        _buildCell((row['ghee_total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
        _buildCell((row['total_bill'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
        _buildCell((row['received'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
        _buildCell((row['global_due'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
        _buildCell((row['avg_rate'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00', style, pw.TextAlign.right),
      ],
    );
  }

  static pw.TableRow _buildTotalRow(double totalMilkQty, double totalDahi, double totalGhee, double totalBill, double totalReceived, double totalDue) {
    final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _buildCell('-', boldStyle, pw.TextAlign.center),
        _buildCell('TOTAL', boldStyle, pw.TextAlign.left),
        _buildCell(totalMilkQty.toStringAsFixed(2), boldStyle, pw.TextAlign.right),
        _buildCell(totalDahi.toStringAsFixed(2), boldStyle, pw.TextAlign.right),
        _buildCell(totalGhee.toStringAsFixed(2), boldStyle, pw.TextAlign.right),
        _buildCell(totalBill.toStringAsFixed(2), boldStyle, pw.TextAlign.right),
        _buildCell(totalReceived.toStringAsFixed(2), boldStyle, pw.TextAlign.right),
        _buildCell(totalDue.toStringAsFixed(2), boldStyle, pw.TextAlign.right),
        _buildCell('-', boldStyle, pw.TextAlign.right),
      ],
    );
  }

  static pw.Widget _buildCell(String text, pw.TextStyle style, pw.TextAlign align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  static Future<void> generateAndSharePDF(
    List<Map<String, dynamic>> data,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startDateStr = _dateFormat.format(startDate);
    final endDateStr = _dateFormat.format(endDate);
    
    // OPTIMIZATION: Generate PDF bytes in isolate to avoid blocking UI
    final pdfBytes = await compute(
      _generatePdfBytes,
      _PdfParams(
        data: data,
        startDateStr: startDateStr,
        endDateStr: endDateStr,
      ),
    );
    
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'business_report_${startDate.year}_${startDate.month}_${startDate.day}_to_${endDate.year}_${endDate.month}_${endDate.day}.pdf',
    );
  }

  static Future<void> generateAndShareCSV(
    List<Map<String, dynamic>> data,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final List<List<dynamic>> csvData = [];
    
    // Add header row
    csvData.add([
      'Customer Name',
      'Milk (L)',
      'Dahi (Rs)',
      'Ghee (Rs)',
      'Total Bill (Rs)',
      'Paid (Rs)',
      'Total Due (Rs)',
      'Avg Rate (Rs)',
    ]);
    
    // Add data rows
    for (var row in data) {
      csvData.add([
        row['name'] as String,
        (row['milk_qty'] as num?)?.toDouble() ?? 0.0,
        (row['dahi_total'] as num?)?.toDouble() ?? 0.0,
        (row['ghee_total'] as num?)?.toDouble() ?? 0.0,
        (row['total_bill'] as num?)?.toDouble() ?? 0.0,
        (row['received'] as num?)?.toDouble() ?? 0.0,
        (row['global_due'] as num?)?.toDouble() ?? 0.0,
        (row['avg_rate'] as num?)?.toDouble() ?? 0.0,
      ]);
    }
    
    // Calculate and add totals row
    double totalMilkQty = 0.0;
    double totalDahi = 0.0;
    double totalGhee = 0.0;
    double totalBill = 0.0;
    double totalReceived = 0.0;
    double totalDue = 0.0;
    
    for (var row in data) {
      totalMilkQty += (row['milk_qty'] as num?)?.toDouble() ?? 0.0;
      totalDahi += (row['dahi_total'] as num?)?.toDouble() ?? 0.0;
      totalGhee += (row['ghee_total'] as num?)?.toDouble() ?? 0.0;
      totalBill += (row['total_bill'] as num?)?.toDouble() ?? 0.0;
      totalReceived += (row['received'] as num?)?.toDouble() ?? 0.0;
      totalDue += (row['global_due'] as num?)?.toDouble() ?? 0.0;
    }
    
    csvData.add([
      'TOTAL',
      totalMilkQty,
      totalDahi,
      totalGhee,
      totalBill,
      totalReceived,
      totalDue,
      '-',
    ]);
    
    // Convert to CSV string
    final csvString = const ListToCsvConverter().convert(csvData);
    
    // Save to temporary directory
    final directory = await getTemporaryDirectory();
    final fileName = 'business_report_${startDate.year}_${startDate.month}_${startDate.day}_to_${endDate.year}_${endDate.month}_${endDate.day}.csv';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvString);
    
    // Share the file
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: 'Business Report',
      text: 'Business Report from ${startDate.day}/${startDate.month}/${startDate.year} to ${endDate.day}/${endDate.month}/${endDate.year}',
    ));
  }
}
