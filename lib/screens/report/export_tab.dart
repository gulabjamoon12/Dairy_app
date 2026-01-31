import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/services/export_service.dart';
import 'package:intl/intl.dart';

class ExportTab extends StatefulWidget {
  const ExportTab({super.key});

  @override
  State<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<ExportTab> {
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _reportData = [];
  bool _isLoading = false;
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    // Set default to current month
    final now = DateTime.now();
    _selectedDateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
  }

  Future<void> _selectDateRange() async {
    // Fix: Set lastDate to future to prevent crash when current month end is after today
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange,
      helpText: 'Select Date Range',
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _hasData = false;
        _reportData = [];
      });
    }
  }

  Future<void> _generateReport() async {
    if (_selectedDateRange == null) return;

    setState(() {
      _isLoading = true;
      _hasData = false;
    });

    try {
      final data = await DatabaseHelper.instance.getBusinessReportData(
        _selectedDateRange!.start,
        _selectedDateRange!.end,
      );

      if (!mounted) return;

      setState(() {
        _reportData = data;
        _hasData = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating report: $e')),
      );
    }
  }

  Map<String, dynamic> _calculateSummary() {
    double totalMilkQty = 0.0;
    double totalDahi = 0.0;
    double totalGhee = 0.0;
    double totalBill = 0.0;
    double totalReceived = 0.0;
    double totalDue = 0.0;

    for (var row in _reportData) {
      totalMilkQty += (row['milk_qty'] as num?)?.toDouble() ?? 0.0;
      totalDahi += (row['dahi_total'] as num?)?.toDouble() ?? 0.0;
      totalGhee += (row['ghee_total'] as num?)?.toDouble() ?? 0.0;
      totalBill += (row['total_bill'] as num?)?.toDouble() ?? 0.0;
      totalReceived += (row['received'] as num?)?.toDouble() ?? 0.0;
      totalDue += (row['global_due'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'totalMilkQty': totalMilkQty,
      'totalDahi': totalDahi,
      'totalGhee': totalGhee,
      'totalBill': totalBill,
      'totalReceived': totalReceived,
      'totalDue': totalDue,
    };
  }

  Future<void> _exportPDF() async {
    if (!_hasData || _reportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate report first')),
      );
      return;
    }

    try {
      await ExportService.generateAndSharePDF(
        _reportData,
        _selectedDateRange!.start,
        _selectedDateRange!.end,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
    }
  }

  Future<void> _exportCSV() async {
    if (!_hasData || _reportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate report first')),
      );
      return;
    }

    try {
      await ExportService.generateAndShareCSV(
        _reportData,
        _selectedDateRange!.start,
        _selectedDateRange!.end,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting CSV: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM, yyyy');
    final summary = _hasData ? _calculateSummary() : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Date Range Picker Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                          Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedDateRange != null
                                    ? '${dateFormat.format(_selectedDateRange!.start)} - ${dateFormat.format(_selectedDateRange!.end)}'
                                    : 'Select Date Range',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: _selectDateRange,
                              tooltip: 'Change Date Range',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _generateReport,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 18),
                            label: Text(_isLoading ? 'Generating...' : 'Generate Report'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Preview Summary
            if (_hasData && summary != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                            Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Summary',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryItem(
                                  'Total Milk',
                                  '${summary['totalMilkQty'].toStringAsFixed(2)}L',
                                  Icons.local_drink,
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildSummaryItem(
                                  'Total Collection',
                                  '₹${summary['totalReceived'].toStringAsFixed(2)}',
                                  Icons.payment,
                                  Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryItem(
                                  'Total Bill',
                                  '₹${summary['totalBill'].toStringAsFixed(2)}',
                                  Icons.receipt,
                                  Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildSummaryItem(
                                  'Total Due',
                                  '₹${summary['totalDue'].toStringAsFixed(2)}',
                                  Icons.account_balance_wallet,
                                  Colors.red,
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
            const SizedBox(height: 12),
            // Export Buttons
            if (_hasData)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _exportPDF,
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                        label: const Text('Export PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _exportCSV,
                        icon: const Icon(Icons.table_chart, color: Colors.white),
                        label: const Text('Export CSV'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Data Preview List
            if (_hasData)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reportData.length,
                  cacheExtent: 200,
                  itemBuilder: (context, index) {
                    final row = _reportData[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ListTile(
                              title: Text(
                                row['name'] as String,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Milk: ${(row['milk_qty'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}L | Dahi: ₹${(row['dahi_total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'} | Ghee: ₹${(row['ghee_total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Bill: ₹${(row['total_bill'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Due: ₹${(row['global_due'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}',
                                    style: TextStyle(
                                      color: ((row['global_due'] as num?)?.toDouble() ?? 0.0) > 0
                                          ? Colors.red[700]
                                          : Colors.green[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else if (!_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No report generated',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select a date range and click "Generate Report"',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
