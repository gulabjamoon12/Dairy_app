import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/services/sms_service.dart';
import 'package:gg/utils/debouncer.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class BillingTab extends StatefulWidget {
  const BillingTab({super.key});

  @override
  State<BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends State<BillingTab> {
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _searchDebouncer = Debouncer(duration: const Duration(milliseconds: 300));
  String _searchQuery = '';
  late Future<List<Map<String, dynamic>>> _customersFuture;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchDebouncer.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebouncer.run(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  void _loadCustomers() {
    setState(() {
      _customersFuture = DatabaseHelper.instance.getCustomers(includeInactive: false);
    });
  }

  Future<void> _selectMonthYear() async {
    final DateTime now = DateTime.now();
    final int currentYear = _selectedDate.year;
    final int currentMonth = _selectedDate.month;

    // Show year selection dialog
    final int? selectedYear = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Year'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: (now.year - 2019).clamp(1, 200),
            itemBuilder: (context, index) {
              final year = 2020 + index;
              return ListTile(
                title: Text(year.toString()),
                selected: year == currentYear,
                onTap: () => Navigator.pop(context, year),
              );
            },
          ),
        ),
      ),
    );

    if (!mounted || selectedYear == null) return;

    // Show month selection dialog
    final int? selectedMonth = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Month ($selectedYear)'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final monthName = DateFormat('MMM').format(DateTime(selectedYear, month));
              final isCurrentMonth = month == currentMonth && selectedYear == currentYear;
              return InkWell(
                onTap: () => Navigator.pop(context, month),
                child: Container(
                  decoration: BoxDecoration(
                    color: isCurrentMonth
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: isCurrentMonth
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[300]!,
                      width: isCurrentMonth ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      monthName,
                      style: TextStyle(
                        fontWeight: isCurrentMonth ? FontWeight.bold : FontWeight.normal,
                        color: isCurrentMonth
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    if (!mounted || selectedMonth == null) return;

    setState(() {
      _selectedDate = DateTime(selectedYear, selectedMonth, 1);
    });
  }

  String _formatPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
  }

  String _generateSMSMessage(String name, String month, double milkQty, double milkCost, double dahiCost, double totalDue) {
    // Calculate Average Price
    final avgPrice = milkQty > 0 ? (milkCost / milkQty) : 0.0;

    // Calculate Previous Balance (Arrears or Advance)
    final currentTotal = milkCost + dahiCost;
    final previousBalance = totalDue - currentTotal;

    // CRITICAL FIX: Update message generation for advance customers
    // If totalDue is negative, show "Advance Balance" instead of "Payable"
    final isAdvance = totalDue <= 0;
    final statusText = isAdvance 
        ? "Advance Balance: Rs.${totalDue.abs().toStringAsFixed(0)}" 
        : "TOTAL PAYABLE: Rs.${totalDue.toStringAsFixed(0)}";

    return '''Namaste $name,

Bill for $month:
Milk: ${milkQty.toStringAsFixed(1)}L @ Rs.${avgPrice.toStringAsFixed(0)}/L = Rs.${milkCost.toStringAsFixed(0)}
Dahi/Ghee: Rs.${dahiCost.toStringAsFixed(0)}
Previous Balance: Rs.${previousBalance.toStringAsFixed(0)}

*$statusText*''';
  }

  Future<void> _sendSMS(String phoneNumber, String message) async {
    final formattedPhone = _formatPhoneNumber(phoneNumber);

    if (formattedPhone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid phone number')),
      );
      return;
    }

    try {
      // Try multiple URI formats for maximum compatibility
      List<Uri> uriAttempts = [
        // Format 1: smsto: with query parameter (most compatible)
        Uri.parse('smsto:$formattedPhone?body=${Uri.encodeComponent(message)}'),
        // Format 2: sms: with path and query
        Uri(
          scheme: 'sms',
          path: formattedPhone,
          queryParameters: {'body': message},
        ),
        // Format 3: smsto: with colon separator (some older apps)
        Uri.parse('smsto:$formattedPhone:${Uri.encodeComponent(message)}'),
      ];

      bool launched = false;
      for (final uri in uriAttempts) {
        try {
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (launched) break;
          }
        } catch (e) {
          // Try next format
          continue;
        }
      }

      if (!launched && mounted) {
        // Fallback: Try sending directly if SMS app can't be opened
        final hasPermission = await _requestSMSPermission();
        if (hasPermission) {
          // Automatically send directly as fallback
          final success = await _sendSMSDirect(phoneNumber, message);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success 
                    ? 'SMS sent directly (SMS app not available)' 
                    : 'Failed to send SMS',
                ),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  Platform.isIOS
                      ? 'Could not open Messages app. Please check that Messages is available.'
                      : 'Could not open SMS app and SMS permission not granted. '
                          'Please grant SMS permission in settings to send directly.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Send SMS directly using platform channel (no user interaction needed)
  Future<bool> _sendSMSDirect(String phoneNumber, String message) async {
    final formattedPhone = _formatPhoneNumber(phoneNumber);
    
    try {
      final result = await SmsService.sendSms(formattedPhone, message);
      debugPrint('SMS result for $formattedPhone: $result');
      return result;
    } catch (e) {
      debugPrint('Error sending SMS to $formattedPhone: $e');
      return false;
    }
  }

  /// Request SMS permission (Android only; iOS uses Messages app via url_launcher)
  Future<bool> _requestSMSPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.sms.status;
    if (status.isGranted) return true;
    final result = await Permission.sms.request();
    return result.isGranted;
  }

  Future<void> _sendSingleBill(Map<String, dynamic> customer, double milkQty, double milkCost, double dahiCost, double totalDue) async {
    final monthName = DateFormat('MMMM yyyy').format(_selectedDate);
    final message = _generateSMSMessage(
      customer['name'],
      monthName,
      milkQty,
      milkCost,
      dahiCost,
      totalDue,
    );

    await _sendSMS(customer['contactNumber'], message);
  }

  Future<void> _sendBillsToAll() async {
    // Show options dialog first
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Bills to All'),
        content: const Text('How would you like to send SMS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('Manual (One by One)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'auto'),
            child: const Text('Auto Send All'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    // Auto Send All is Android-only (iOS does not allow programmatic SMS)
    if (choice == 'auto' && Platform.isIOS) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Auto Send All is available on Android only. On iOS, use "Manual (One by One)" to open Messages for each customer.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // For automatic sending on Android, request SMS permission first
    if (choice == 'auto') {
      final hasPermission = await _requestSMSPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS permission is required for automatic sending'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Load all customer bills
    final allCustomers = await DatabaseHelper.instance.getCustomers(includeInactive: false);
    final List<Map<String, dynamic>> customerBills = [];

    for (var customer in allCustomers) {
      try {
        final summary = await DatabaseHelper.instance.getMonthlyBillSummary(
          customer['id'],
          _selectedDate.month,
          _selectedDate.year,
        );

        customerBills.add({
          'customer': customer,
          'summary': summary,
        });
      } catch (e) {
        // Skip customers with errors
      }
    }

    if (!mounted) return;

    if (customerBills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No customers found'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    if (choice == 'auto') {
      await _showAutoBulkSendingDialog(customerBills);
    } else {
      await _showBulkSendingDialog(customerBills);
    }
  }

  /// Automatic bulk SMS sending dialog
  Future<void> _showAutoBulkSendingDialog(List<Map<String, dynamic>> customerBills) async {
    final monthName = DateFormat('MMMM yyyy').format(_selectedDate);
    int successCount = 0;
    int failedCount = 0;
    bool isCancelled = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Start sending if not already started
            if (successCount == 0 && failedCount == 0 && !isCancelled) {
              // Use Future.microtask to avoid calling setState during build
              Future.microtask(() async {
                for (int i = 0; i < customerBills.length; i++) {
                  if (isCancelled) break;

                  final customerData = customerBills[i];
                  final customer = customerData['customer'] as Map<String, dynamic>;
                  final summary = customerData['summary'] as Map<String, dynamic>;
                  
                  final milkQty = (summary['totalMilkQty'] as num?)?.toDouble() ?? 0.0;
                  final milkCost = (summary['totalMilkCost'] as num?)?.toDouble() ?? 0.0;
                  final dahiCost = (summary['totalDahiGheeCost'] as num?)?.toDouble() ?? 0.0;
                  final totalDue = (summary['totalDueTillDate'] as num?)?.toDouble() ?? 0.0;

                  final message = _generateSMSMessage(
                    customer['name'],
                    monthName,
                    milkQty,
                    milkCost,
                    dahiCost,
                    totalDue,
                  );

                  final success = await _sendSMSDirect(
                    customer['contactNumber'],
                    message,
                  );

                  if (context.mounted) {
                    setDialogState(() {
                      if (success) {
                        successCount++;
                      } else {
                        failedCount++;
                      }
                    });
                  }

                  // 2 second delay between messages
                  if (i < customerBills.length - 1) {
                    await Future.delayed(const Duration(seconds: 2));
                  }
                }

                // All done - close dialog after a short delay
                if (context.mounted && !isCancelled) {
                  await Future.delayed(const Duration(seconds: 1));
                  if (context.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                }
              });
            }

            final currentIndex = successCount + failedCount;
            final progress = customerBills.isEmpty ? 0.0 : currentIndex / customerBills.length;
            final isComplete = currentIndex >= customerBills.length;

            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    isComplete ? Icons.check_circle : Icons.send,
                    color: isComplete ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(isComplete ? 'Completed!' : 'Sending SMS...'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress indicator
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isComplete ? Colors.green : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Progress text
                  Text(
                    '$currentIndex / ${customerBills.length}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Success/Failed counts
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 4),
                      Text('$successCount sent'),
                      const SizedBox(width: 16),
                      Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 4),
                      Text('$failedCount failed'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Current customer being processed
                  if (!isComplete && currentIndex < customerBills.length)
                    Text(
                      'Sending to: ${customerBills[currentIndex]['customer']['name']}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  
                  if (isComplete)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'All messages processed!',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                if (!isComplete)
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                if (isComplete)
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Done'),
                  ),
              ],
            );
          },
        );
      },
    );

    // Show final summary
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCancelled
                ? 'Cancelled. Sent: $successCount, Failed: $failedCount'
                : 'Completed! Sent: $successCount, Failed: $failedCount',
          ),
          backgroundColor: failedCount == 0 ? Colors.green : Colors.orange,
          duration: const Duration(milliseconds: 2000),
        ),
      );
    }
  }

  Future<void> _showBulkSendingDialog(List<Map<String, dynamic>> pendingCustomers) async {
    int currentIndex = 0;
    final monthName = DateFormat('MMMM yyyy').format(_selectedDate);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (currentIndex >= pendingCustomers.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Completed sending ${pendingCustomers.length} bills'),
                      backgroundColor: Colors.green,
                      duration: Duration(milliseconds: 1500),
                    ),
                  );
                }
              });
              return const SizedBox.shrink();
            }

            final currentCustomer = pendingCustomers[currentIndex];
            final customer = currentCustomer['customer'] as Map<String, dynamic>;
            final summary = currentCustomer['summary'] as Map<String, dynamic>;
            final customerName = customer['name'] as String;
            final milkQty = (summary['totalMilkQty'] as num?)?.toDouble() ?? 0.0;
            final milkCost = (summary['totalMilkCost'] as num?)?.toDouble() ?? 0.0;
            final dahiCost = (summary['totalDahiGheeCost'] as num?)?.toDouble() ?? 0.0;
            final totalDue = (summary['totalDueTillDate'] as num?)?.toDouble() ?? 0.0;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.sms, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Bulk Sending Mode',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sending to $customerName (${currentIndex + 1}/${pendingCustomers.length})...',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final message = _generateSMSMessage(
                          customerName,
                          monthName,
                          milkQty,
                          milkCost,
                          dahiCost,
                          totalDue,
                        );
                        await _sendSMS(customer['contactNumber'], message);
                        // Add delay to prevent crashing
                        await Future.delayed(const Duration(seconds: 1));
                      },
                      icon: const Icon(Icons.sms, color: Colors.white),
                      label: const Text('Open SMS App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          currentIndex++;
                        });
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Month/Year Picker and SMS Button Row
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: InkWell(
                      onTap: _selectMonthYear,
                      borderRadius: BorderRadius.circular(16),
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
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  DateFormat('MMMM yyyy').format(_selectedDate),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: FloatingActionButton.extended(
                    onPressed: _sendBillsToAll,
                    icon: const Icon(Icons.sms),
                    label: const Text('SMS All'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _searchDebouncer.cancel();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Customer List
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _customersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No active customers',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                );
              }

              final allCustomers = snapshot.data!;
              final filteredCustomers = _searchQuery.isEmpty
                  ? allCustomers
                  : allCustomers.where((customer) {
                      final name = (customer['name'] as String).toLowerCase();
                      return name.contains(_searchQuery);
                    }).toList();

              if (filteredCustomers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No customers found',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredCustomers.length,
                cacheExtent: 200,
                itemBuilder: (context, index) {
                  final customer = filteredCustomers[index];
                  return _CustomerBillCard(
                    customer: customer,
                    month: _selectedDate.month,
                    year: _selectedDate.year,
                    onSMSSend: _sendSingleBill,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomerBillCard extends StatefulWidget {
  final Map<String, dynamic> customer;
  final int month;
  final int year;
  final Function(Map<String, dynamic>, double, double, double, double) onSMSSend;

  const _CustomerBillCard({
    required this.customer,
    required this.month,
    required this.year,
    required this.onSMSSend,
  });

  @override
  State<_CustomerBillCard> createState() => _CustomerBillCardState();
}

class _CustomerBillCardState extends State<_CustomerBillCard> {
  late Future<Map<String, dynamic>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  void _loadSummary() {
    setState(() {
      _summaryFuture = DatabaseHelper.instance.getMonthlyBillSummary(
        widget.customer['id'],
        widget.month,
        widget.year,
      );
    });
  }

  @override
  void didUpdateWidget(_CustomerBillCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month || oldWidget.year != widget.year) {
      _loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 16),
                      Text(widget.customer['name']),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final summary = snapshot.data ?? {
          'totalMilkQty': 0.0,
          'totalMilkCost': 0.0,
          'totalDahiGheeCost': 0.0,
          'currentMonthAmount': 0.0,
          'totalDueTillDate': 0.0,
        };

        final milkQty = (summary['totalMilkQty'] as num?)?.toDouble() ?? 0.0;
        final milkCost = (summary['totalMilkCost'] as num?)?.toDouble() ?? 0.0;
        final dahiCost = (summary['totalDahiGheeCost'] as num?)?.toDouble() ?? 0.0;
        final currentAmount = (summary['currentMonthAmount'] as num?)?.toDouble() ?? 0.0;
        final totalDue = (summary['totalDueTillDate'] as num?)?.toDouble() ?? 0.0;
        final previousArrears = totalDue - currentAmount;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(16),
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
                  children: [
                    // Customer Name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.customer['name'],
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        // SMS Button - Enabled for all customers including Advance
                        IconButton(
                          icon: const Icon(Icons.sms),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: () {
                            widget.onSMSSend(
                              widget.customer,
                              milkQty,
                              milkCost,
                              dahiCost,
                              totalDue,
                            );
                          },
                          tooltip: 'Send SMS',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Milk Quantity and Cost
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Milk:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '${milkQty.toStringAsFixed(1)}L = ₹${milkCost.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Dahi/Ghee Cost
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Dahi/Ghee:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '₹${dahiCost.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Current Month Bill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current Month Bill:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '₹${currentAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Previous Arrears
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Previous Arrears:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '₹${previousArrears.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: previousArrears > 0 ? Colors.orange[700] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    // Total Payable
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Payable:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.8),
                          ),
                        ),
                        Text(
                          '₹${totalDue.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: totalDue > 0 ? Colors.red[700] : Colors.green[700],
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
      },
    );
  }
}
