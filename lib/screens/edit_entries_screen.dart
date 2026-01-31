import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/utils/debouncer.dart';
import 'package:gg/utils/date_formatters.dart';

class EditEntriesScreen extends StatefulWidget {
  const EditEntriesScreen({super.key});

  @override
  State<EditEntriesScreen> createState() => _EditEntriesScreenState();
}

class _EditEntriesScreenState extends State<EditEntriesScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedSessionFilter = 'All';
  String _searchQuery = '';
  late Future<List<Map<String, dynamic>>> _entriesFuture;
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _searchDebouncer = Debouncer(duration: const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    _refreshEntries();
  }

  @override
  void dispose() {
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

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _refreshEntries() {
    setState(() {
      _entriesFuture = _getEntriesForDate(_selectedDate);
    });
  }

  Future<List<Map<String, dynamic>>> _getEntriesForDate(DateTime date) async {
    final dbHelper = DatabaseHelper.instance;
    final dateString = _formatDate(date);

    final entries = await dbHelper.getMilkEntries(dateString);
    final customers = await dbHelper.getCustomers(includeInactive: true);

    final customerMap = {for (var c in customers) c['id']: c};

    final enrichedEntries = entries.map((entry) {
      return {
        ...entry,
        'customerName': customerMap[entry['customerId']]?['name'] ?? 'Unknown Customer',
      };
    }).toList();

    if (_selectedSessionFilter == 'All') {
      return enrichedEntries;
    } else {
      return enrichedEntries
          .where((entry) => entry['session'] == _selectedSessionFilter)
          .toList();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _refreshEntries();
      });
    }
  }

  void _deleteEntry(int entryId) async {
    try {
      await DatabaseHelper.instance.deleteMilkEntry(entryId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting entry: $e'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Entry deleted successfully.'),
        duration: Duration(milliseconds: 1500),
      ),
    );
    _refreshEntries();
  }

  void _editEntry(BuildContext parentContext, Map<String, dynamic> entry) async {
    // 1. Open the detached dialog
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => _EditMilkEntryDialog(entry: entry),
    );

    // 2. Handle the result safely after the dialog is completely gone
    if (result == true) {
      _refreshEntries();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry updated successfully.')),
      );
    }
  }

  void _addPastEntry(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddPastEntryDialog(selectedDate: _selectedDate),
    ).then((_) {
      if (mounted) _refreshEntries();
    });
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
                        'Edit/View Entries',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    FloatingActionButton(
                      mini: true,
                      onPressed: () => _addPastEntry(context),
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              // Filters Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _selectDate(context),
                                  icon: const Icon(Icons.calendar_today, size: 20),
                                  label: Text(
                                    DateFormatters.mediumDate.format(_selectedDate),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: _selectedSessionFilter,
                                items: ['All', 'Morning', 'Evening']
                                    .map((session) =>
                                        DropdownMenuItem(value: session, child: Text(session)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedSessionFilter = value;
                                      _refreshEntries();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by customer name...',
                              prefixIcon: const Icon(Icons.search, size: 22),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear, size: 22),
                                      onPressed: () {
                                        _searchController.clear();
                                        _searchDebouncer.cancel();
                                        setState(() => _searchQuery = '');
                                      },
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.75),
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => _onSearchChanged(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Entries List
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _entriesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No entries found',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No entries found for this filter.',
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

                    final entries = snapshot.data!;
                    final filtered = _searchQuery.isEmpty
                        ? entries
                        : entries.where((e) {
                            final name = ((e['customerName'] as String?) ?? '').toLowerCase();
                            return name.contains(_searchQuery);
                          }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No matching entries',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextButton.icon(
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchDebouncer.cancel();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear search'),
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: filtered.length,
                      cacheExtent: 200,
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        // OPTIMIZATION: Add key to prevent unnecessary rebuilds
                        return Padding(
                          key: ValueKey(entry['id']),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
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
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.local_drink,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  title: Text(
                                    entry['customerName'],
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  subtitle: Text(
                                    'Quantity: ${entry['quantity']} KG\nSession: ${entry['session']}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.7),
                                        ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit_rounded,
                                            color: Theme.of(context).colorScheme.primary),
                                        onPressed: () => _editEntry(context, entry),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_rounded, color: Colors.red[600]),
                                        onPressed: () => _deleteEntry(entry['id']),
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
}

class AddPastEntryDialog extends StatefulWidget {
  final DateTime selectedDate;
  const AddPastEntryDialog({super.key, required this.selectedDate});

  @override
  State<AddPastEntryDialog> createState() => _AddPastEntryDialogState();
}

class _AddPastEntryDialogState extends State<AddPastEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();

  List<Map<String, dynamic>> _customers = [];
  int? _selectedCustomerId;
  String _selectedSession = 'Morning';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final dbHelper = DatabaseHelper.instance;
    final customers = await dbHelper.getCustomers(includeInactive: false);

    if (!mounted) return;

    setState(() {
      _customers = customers;
      _isLoading = false;
    });
  }

  Future<void> _saveEntry() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedCustomerId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a customer.'),
            duration: Duration(milliseconds: 1500),
          ),
        );
        return;
      }

      final dateString =
          "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}";
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

      final entry = {
        'customerId': _selectedCustomerId!,
        'quantity': quantity,
        'session': _selectedSession,
        'date': dateString,
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Past entry saved successfully!'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(
            height: 80, child: Center(child: CircularProgressIndicator())),
      );
    }

    if (_customers.isEmpty) {
      return AlertDialog(
        title: const Text('Cannot Add Entry'),
        content:
        const Text('No active customers found. Please add customers first.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Add Past Entry'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selectedCustomerId,
                decoration: const InputDecoration(labelText: 'Select Customer'),
                items: _customers.map((customer) {
                  return DropdownMenuItem<int>(
                    value: customer['id'] as int,
                    child: Text(customer['name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCustomerId = value;
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select a customer' : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _selectedSession,
                decoration: const InputDecoration(labelText: 'Select Session'),
                items: ['Morning', 'Evening']
                    .map((session) => DropdownMenuItem(value: session, child: Text(session)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedSession = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _quantityController,
                decoration:
                const InputDecoration(labelText: 'Quantity (in KG)'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a quantity';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _saveEntry, child: const Text('Save')),
      ],
    );
  }
}

class _EditMilkEntryDialog extends StatefulWidget {
  final Map<String, dynamic> entry;
  const _EditMilkEntryDialog({required this.entry});

  @override
  State<_EditMilkEntryDialog> createState() => _EditMilkEntryDialogState();
}

class _EditMilkEntryDialogState extends State<_EditMilkEntryDialog> {
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: widget.entry['quantity'].toString());
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newQuantity = double.tryParse(_quantityController.text);
    if (newQuantity == null || newQuantity <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid quantity.')),
      );
      return;
    }

    final updatedEntry = {
      'id': widget.entry['id'],
      'quantity': newQuantity,
      'customerId': widget.entry['customerId'],
      'session': widget.entry['session'],
      'date': widget.entry['date'],
    };

    try {
      await DatabaseHelper.instance.updateMilkEntry(updatedEntry);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating entry: $e'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, true); // Return TRUE to signal success
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Entry for ${widget.entry['customerName']}'),
      content: TextField(
        controller: _quantityController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
        ],
        decoration: const InputDecoration(labelText: 'New Quantity (in KG)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
