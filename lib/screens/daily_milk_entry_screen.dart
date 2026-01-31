import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/theme/app_theme.dart';
import 'package:gg/utils/date_utils.dart' as app_date;
import 'package:gg/widgets/custom_button.dart';
import 'package:gg/utils/date_formatters.dart';

class DailyMilkEntryScreen extends StatefulWidget {
  const DailyMilkEntryScreen({super.key});

  @override
  State<DailyMilkEntryScreen> createState() => _DailyMilkEntryScreenState();
}

class _DailyMilkEntryScreenState extends State<DailyMilkEntryScreen> {
  // [NEW] Track the selected date for entry
  DateTime _selectedDate = DateTime.now();

  String? _selectedSession;
  List<Map<String, dynamic>> _currentCustomerList = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  final _quantityController = TextEditingController();
  final FocusNode _quantityFocusNode = FocusNode();
  /// When non-null, show "Saved for [name]" on the button and do not advance until delay completes.
  String? _saveSuccessCustomerName;

  // [NEW] Method to pick a date
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(), // Prevent selecting future dates
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _selectSession(String session) {
    setState(() {
      _selectedSession = session;
    });
    _loadDataForSession();
  }

  Future<void> _loadDataForSession() async {
    if (_selectedSession == null) return;

    setState(() {
      _isLoading = true;
    });

    final dbHelper = DatabaseHelper.instance;
    final allCustomers = await dbHelper.getCustomers();

    // [CHANGED] Use the _selectedDate instead of DateTime.now()
    final selectedDateString = app_date.AppDateUtils.formatDate(_selectedDate);
    final entriesForDate = await dbHelper.getMilkEntries(selectedDateString);

    // Filter out customers who already have an entry for THIS session on THIS date
    final savedCustomerIdsForSession = entriesForDate
        .where((entry) => entry['session'] == _selectedSession)
        .map((entry) => entry['customerId'])
        .toSet();

    List<Map<String, dynamic>> filteredCustomers;
    if (_selectedSession == 'Morning') {
      filteredCustomers = allCustomers
          .where((c) => (c['session'] == 'Morning' || c['session'] == 'Both'))
          .toList();
    } else {
      filteredCustomers = allCustomers
          .where((c) => (c['session'] == 'Evening' || c['session'] == 'Both'))
          .toList();
    }

    // Only show customers who DON'T have an entry yet
    final pendingCustomers = filteredCustomers
        .where((c) => !savedCustomerIdsForSession.contains(c['id']))
        .toList();

    if (!mounted) return;
    setState(() {
      _currentCustomerList = pendingCustomers;
      _currentIndex = 0;
      _quantityController.clear();
      _isLoading = false;
    });
  }

  Future<void> _saveAndNext() async {
    if (_currentCustomerList.isEmpty || _quantityController.text.isEmpty) return;

    if (_selectedSession == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a session first.'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    final customer = _currentCustomerList[_currentIndex];
    final quantity = double.tryParse(_quantityController.text);

    if (quantity == null || quantity <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity.'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    // [CHANGED] Use _selectedDate for saving
    final selectedDateString = app_date.AppDateUtils.formatDate(_selectedDate);

    final exists = await DatabaseHelper.instance.entryExists(
      customer['id'],
      selectedDateString,
      _selectedSession!,
    );

    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An entry for ${customer['name']} already exists in this session.'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    final entry = {
      'customerId': customer['id'],
      'quantity': quantity,
      'session': _selectedSession!,
      'date': selectedDateString, // Saving with the chosen date
    };

    try {
      await DatabaseHelper.instance.addMilkEntry(entry);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving entry: $e'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    if (!mounted) return;
    final savedName = customer['name'] as String;
    setState(() {
      _saveSuccessCustomerName = savedName;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _saveSuccessCustomerName = null;
        _currentCustomerList.removeAt(_currentIndex);
        _quantityController.clear();
        if (_currentCustomerList.isEmpty) {
          _currentIndex = 0;
        } else if (_currentIndex >= _currentCustomerList.length) {
          _currentIndex = _currentCustomerList.length - 1;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quantityFocusNode.requestFocus();
      });
    });
  }

  void _nextCustomer() {
    if (_currentIndex < _currentCustomerList.length - 1) {
      setState(() {
        _currentIndex++;
        _quantityController.clear();
      });
    }
  }

  void _previousCustomer() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _quantityController.clear();
      });
    }
  }

  void _resetSelection() {
    setState(() {
      _selectedSession = null;
      _currentCustomerList = [];
      _currentIndex = 0;
      _saveSuccessCustomerName = null;
      // Note: We do NOT reset the date here, in case they want to do
      // Morning AND Evening for the same past date.
    });
  }

  @override
  void dispose() {
    _quantityFocusNode.dispose();
    _quantityController.dispose();
    super.dispose();
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
          child: _selectedSession == null ? _buildSessionSelection() : _buildDataEntry(),
        ),
      ),
    );
  }

  Widget _buildSessionSelection() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              if (Navigator.canPop(context))
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Daily Milk Entry',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Date selection (prominent, above session)
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingXl,
            vertical: AppTheme.spacingXs,
          ),
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        DateFormatters.fullDate.format(_selectedDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.edit, size: 16, color: Colors.grey[400]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppTheme.spacingXl),

        // Session Buttons
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSessionButton(
                    context,
                    title: 'Morning Entry',
                    subtitle: 'Record morning deliveries',
                    icon: Icons.wb_sunny_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () => _selectSession('Morning'),
                  ),
                  const SizedBox(height: 24),
                  _buildSessionButton(
                    context,
                    title: 'Evening Entry',
                    subtitle: 'Record evening deliveries',
                    icon: Icons.nightlight_round,
                    color: const Color(0xFF6366F1),
                    onTap: () => _selectSession('Evening'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionButton(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.9),
                      color.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icon, size: 30, color: Colors.white),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataEntry() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // [CHANGED] Add date display to the "Complete" screen so user knows which date they finished
    final dateStr = DateFormatters.shortDate.format(_selectedDate);

    if (_currentCustomerList.isEmpty) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _resetSelection,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_selectedSession Entry',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 64,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'All entries complete!',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All customers for $_selectedSession ($dateStr) have been entered.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add customers in Manage Customers to record new entries.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            CustomButton(
                              text: 'Back to Session Selection',
                              icon: Icons.arrow_back,
                              onPressed: _resetSelection,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _resetSelection,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_selectedSession ($dateStr)', // Show date here too
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    Text(
                      '${_currentIndex + 1} of ${_currentCustomerList.length} customers',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: (_currentIndex + 1) / _currentCustomerList.length,
              minHeight: 6,
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        // Entry Form
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Customer Card
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                            Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Customer',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _currentCustomerList[_currentIndex]['name'],
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _quantityController,
                            focusNode: _quantityFocusNode,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Milk Quantity (KG)',
                              prefixIcon: Icon(
                                Icons.local_drink,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              suffixText: 'KG',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Navigation Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _currentIndex > 0 ? _previousCustomer : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _currentIndex < _currentCustomerList.length - 1
                            ? _nextCustomer
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Save Button or success state
                _saveSuccessCustomerName != null
                    ? CustomButton(
                        text: 'Saved for $_saveSuccessCustomerName',
                        icon: Icons.check_circle,
                        onPressed: null,
                        backgroundColor: Colors.green,
                        width: double.infinity,
                      )
                    : CustomButton(
                        text: 'Save & Next',
                        icon: Icons.save,
                        onPressed: _saveAndNext,
                        width: double.infinity,
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}