import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/utils/date_formatters.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  final DateTime fromDate;
  final DateTime toDate;

  const CustomerDetailScreen({
    super.key,
    required this.customer,
    required this.fromDate,
    required this.toDate,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<Map<String, dynamic>> _summaryFuture;
  late Future<List<Map<String, dynamic>>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    // Fix: Don't use setState in initState, just assign directly
    _summaryFuture = _calculateSummary();
    _transactionsFuture = _loadTransactions();
  }

  void _loadData() {
    setState(() {
      _summaryFuture = _calculateSummary();
      _transactionsFuture = _loadTransactions();
    });
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<Map<String, dynamic>> _calculateSummary() async {
    final fromDateStr = _formatDate(widget.fromDate);
    final toDateStr = _formatDate(widget.toDate);
    final customerId = widget.customer['id'] as int;

    // OPTIMIZATION: Use database-level filtering instead of fetching all and filtering in memory
    final milkEntries = await DatabaseHelper.instance.getMilkEntriesForCustomerInRange(
      customerId,
      fromDateStr,
      toDateStr,
    );

    final dahiGheeEntries = await DatabaseHelper.instance.getDahiGheeEntriesForCustomerInRange(
      customerId,
      fromDateStr,
      toDateStr,
    );

    final payments = await DatabaseHelper.instance.getPaymentsForCustomerInRange(
      customerId,
      fromDateStr,
      toDateStr,
    );

    // OPTIMIZATION: Get all prices at once and calculate
    // Use generateBillData pattern which has cached price lookups
    final priceHistory = await DatabaseHelper.instance.getPriceHistory();
    
    // Build a simple price lookup map (date -> price, sorted by date DESC)
    double? getEffectivePrice(String date) {
      for (var priceEntry in priceHistory) {
        final effectiveDate = priceEntry['effective_date'] as String;
        if (effectiveDate.compareTo(date) <= 0) {
          return (priceEntry['price'] as num?)?.toDouble();
        }
      }
      // Fallback to oldest price
      if (priceHistory.isNotEmpty) {
        return (priceHistory.last['price'] as num?)?.toDouble();
      }
      return null;
    }

    // Calculate total milk quantity and cost
    double totalMilkQty = 0.0;
    double totalMilkCost = 0.0;

    for (var entry in milkEntries) {
      final quantity = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
      totalMilkQty += quantity;

      if (quantity > 0) {
        final entryDate = entry['date'] as String;
        final priceForDate = getEffectivePrice(entryDate);
        if (priceForDate != null) {
          totalMilkCost += quantity * priceForDate;
        }
      }
    }

    // Calculate dahi/ghee cost
    double totalDahiGheeCost = 0.0;
    for (var entry in dahiGheeEntries) {
      final price = (entry['price'] as num?)?.toDouble() ?? 0.0;
      totalDahiGheeCost += price;
    }

    final totalSales = totalMilkCost + totalDahiGheeCost;

    // Calculate total payments
    double totalPayments = 0.0;
    for (var payment in payments) {
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      totalPayments += amount;
    }

    return {
      'totalMilkQty': totalMilkQty,
      'totalSales': totalSales,
      'totalPayments': totalPayments,
    };
  }

  Future<List<Map<String, dynamic>>> _loadTransactions() async {
    final fromDateStr = _formatDate(widget.fromDate);
    final toDateStr = _formatDate(widget.toDate);
    final customerId = widget.customer['id'] as int;

    // OPTIMIZATION: Use database-level filtering instead of fetching all and filtering in memory
    final milkEntries = await DatabaseHelper.instance.getMilkEntriesForCustomerInRange(
      customerId,
      fromDateStr,
      toDateStr,
    );

    final dahiGheeEntries = await DatabaseHelper.instance.getDahiGheeEntriesForCustomerInRange(
      customerId,
      fromDateStr,
      toDateStr,
    );

    final payments = await DatabaseHelper.instance.getPaymentsForCustomerInRange(
      customerId,
      fromDateStr,
      toDateStr,
    );

    // OPTIMIZATION: Get all prices at once for batch price lookup
    final priceHistory = await DatabaseHelper.instance.getPriceHistory();
    
    double? getEffectivePrice(String date) {
      for (var priceEntry in priceHistory) {
        final effectiveDate = priceEntry['effective_date'] as String;
        if (effectiveDate.compareTo(date) <= 0) {
          return (priceEntry['price'] as num?)?.toDouble();
        }
      }
      if (priceHistory.isNotEmpty) {
        return (priceHistory.last['price'] as num?)?.toDouble();
      }
      return null;
    }

    // Combine and format transactions
    final List<Map<String, dynamic>> transactions = [];

    // Add milk entries as debits (using batch price lookup)
    for (var entry in milkEntries) {
      final quantity = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
      final entryDate = entry['date'] as String;
      final priceForDate = getEffectivePrice(entryDate);
      final amount = priceForDate != null ? quantity * priceForDate : 0.0;

      transactions.add({
        'type': 'milk',
        'id': entry['id'],
        'date': entryDate,
        'description': 'Milk ${quantity.toStringAsFixed(2)}L',
        'amount': amount,
        'isDebit': true,
        'session': entry['session'],
        'quantity': quantity,
      });
    }

    // Add dahi/ghee entries as debits
    for (var entry in dahiGheeEntries) {
      final price = (entry['price'] as num?)?.toDouble() ?? 0.0;
      transactions.add({
        'type': 'dahi_ghee',
        'id': entry['id'],
        'date': entry['date'],
        'description': '${entry['product']}',
        'amount': price,
        'isDebit': true,
        'price': price,
      });
    }

    // Add payments as credits
    for (var payment in payments) {
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      final note = payment['note'] as String?;
      transactions.add({
        'type': 'payment',
        'id': payment['id'],
        'date': payment['date'],
        'description': note != null && note.isNotEmpty ? 'Payment ($note)' : 'Payment',
        'amount': amount,
        'isDebit': false,
        'note': note,
      });
    }

    // Sort by date (newest first)
    transactions.sort((a, b) {
      final dateA = a['date'] as String;
      final dateB = b['date'] as String;
      return dateB.compareTo(dateA); // Descending order
    });

    return transactions;
  }

  Future<void> _deleteTransaction(int id, String type) async {
    try {
      if (type == 'milk') {
        await DatabaseHelper.instance.deleteMilkEntry(id);
      } else if (type == 'dahi_ghee') {
        await DatabaseHelper.instance.deleteDahiGheeEntry(id);
      } else if (type == 'payment') {
        await DatabaseHelper.instance.deletePayment(id);
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction deleted successfully'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting transaction: $e')),
      );
    }
  }

  Future<void> _editTransaction(Map<String, dynamic> transaction) async {
    final type = transaction['type'] as String;
    final id = transaction['id'] as int;
    
    String label = '';
    String currentValue = '';
    
    if (type == 'milk') {
      label = 'Quantity (in KG)';
      currentValue = (transaction['quantity'] as num?)?.toDouble().toString() ?? '0';
    } else if (type == 'dahi_ghee') {
      label = 'Price (₹)';
      currentValue = (transaction['price'] as num?)?.toDouble().toString() ?? '0';
    } else if (type == 'payment') {
      label = 'Amount (₹)';
      currentValue = (transaction['amount'] as num?)?.toDouble().toString() ?? '0';
    }
    
    final double? newValue = await showDialog<double>(
      context: context,
      builder: (context) => EditTransactionDialog(
        type: type,
        label: label,
        currentValue: currentValue,
      ),
    );
    
    if (newValue == null || newValue <= 0) {
      return;
    }
    
    try {
      if (type == 'milk') {
        final entry = await DatabaseHelper.instance.getMilkEntriesForCustomer(widget.customer['id']);
        final milkEntry = entry.firstWhere((e) => e['id'] == id);
        await DatabaseHelper.instance.updateMilkEntry({
          'id': id,
          'quantity': newValue,
          'customerId': milkEntry['customerId'],
          'session': milkEntry['session'],
          'date': milkEntry['date'],
        });
      } else if (type == 'dahi_ghee') {
        final entry = await DatabaseHelper.instance.getDahiGheeEntriesForCustomer(widget.customer['id']);
        final dahiEntry = entry.firstWhere((e) => e['id'] == id);
        await DatabaseHelper.instance.updateDahiGheeEntry({
          'id': id,
          'price': newValue,
          'customerId': dahiEntry['customerId'],
          'product': dahiEntry['product'],
          'date': dahiEntry['date'],
        });
      } else if (type == 'payment') {
        final payment = await DatabaseHelper.instance.getPaymentsForCustomer(widget.customer['id']);
        final paymentEntry = payment.firstWhere((e) => e['id'] == id);
        await DatabaseHelper.instance.updatePayment({
          'id': id,
          'amount': newValue,
          'customerId': paymentEntry['customerId'],
          'date': paymentEntry['date'],
          'note': paymentEntry['note'],
        });
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction updated successfully'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating transaction: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.customer['name'],
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              // Date Range Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.date_range,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                          Text(
                            '${DateFormatters.mediumDate.format(widget.fromDate)} - ${DateFormatters.mediumDate.format(widget.toDate)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Summary Cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _summaryFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      );
                    }

                    final summary = snapshot.data ?? {
                      'totalMilkQty': 0.0,
                      'totalSales': 0.0,
                      'totalPayments': 0.0,
                    };

                    return Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Milk',
                            '${(summary['totalMilkQty'] as double).toStringAsFixed(2)}L',
                            Icons.local_drink,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Sales',
                            '₹${(summary['totalSales'] as double).toStringAsFixed(2)}',
                            Icons.receipt,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'Payments',
                            '₹${(summary['totalPayments'] as double).toStringAsFixed(2)}',
                            Icons.payment,
                            Colors.green,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Transaction History Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Transaction History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Transaction List
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _transactionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No transactions found',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No transactions in the selected date range',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                          ],
                        ),
                      );
                    }

                    final transactions = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final transaction = transactions[index];
                        final isDebit = transaction['isDebit'] as bool;
                        final amount = transaction['amount'] as double;
                        final date = transaction['date'] as String;
                        final description = transaction['description'] as String;

                        // OPTIMIZATION: Add key to prevent unnecessary rebuilds
                        return Padding(
                          key: ValueKey('${transaction['type']}_${transaction['id']}'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withValues(alpha: 0.85),
                                      Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withValues(alpha: 0.6),
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
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 16,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isDebit
                                          ? Colors.red.withValues(alpha: 0.12)
                                          : Colors.green.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isDebit ? Icons.add : Icons.remove,
                                      color: isDebit ? Colors.red[700] : Colors.green[700],
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    description,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  subtitle: Text(
                                    DateFormatters.mediumDate.format(DateTime.parse(date)),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${isDebit ? '+' : '-'}₹${amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDebit ? Colors.red[700] : Colors.green[700],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editTransaction(transaction);
                                          } else if (value == 'delete') {
                                            showDialog(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Delete Transaction'),
                                                content: const Text(
                                                    'Are you sure you want to delete this transaction?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      _deleteTransaction(
                                                        transaction['id'] as int,
                                                        transaction['type'] as String,
                                                      );
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.red,
                                                      foregroundColor: Colors.white,
                                                    ),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit, size: 20),
                                                SizedBox(width: 8),
                                                Text('Edit'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete, size: 20, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Delete', style: TextStyle(color: Colors.red)),
                                              ],
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
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Separate StatefulWidget for Edit Transaction Dialog
// This ensures the TextEditingController is only disposed when the dialog widget is destroyed
class EditTransactionDialog extends StatefulWidget {
  final String type;
  final String label;
  final String currentValue;

  const EditTransactionDialog({
    super.key,
    required this.type,
    required this.label,
    required this.currentValue,
  });

  @override
  State<EditTransactionDialog> createState() => _EditTransactionDialogState();
}

class _EditTransactionDialogState extends State<EditTransactionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit ${widget.type == 'milk' ? 'Milk Entry' : widget.type == 'dahi_ghee' ? 'Dahi/Ghee Entry' : 'Payment'}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: widget.label,
                    prefixText: widget.type != 'milk' ? '₹' : null,
                    suffixText: widget.type == 'milk' ? 'KG' : null,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final newValue = double.tryParse(_controller.text);
                          if (newValue != null && newValue > 0) {
                            Navigator.pop(context, newValue);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid value')),
                            );
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
