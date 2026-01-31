import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/utils/date_utils.dart' as app_date;
import 'package:gg/widgets/custom_button.dart';
import 'package:intl/intl.dart';

class DahiGheeScreen extends StatefulWidget {
  const DahiGheeScreen({super.key});

  @override
  State<DahiGheeScreen> createState() => _DahiGheeScreenState();
}

class _DahiGheeScreenState extends State<DahiGheeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();

  List<Map<String, dynamic>> _customers = [];
  int? _selectedCustomerId;
  String? _selectedProduct;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
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
      });
    }
  }

  Future<void> _saveEntry() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedProduct == null || _selectedCustomerId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a product and a customer.'),
            duration: Duration(milliseconds: 1500),
          ),
        );
        return;
      }

      final dateString = app_date.AppDateUtils.formatDate(_selectedDate);
      final price = double.tryParse(_priceController.text);

      if (price == null || price <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid price.'),
            duration: Duration(milliseconds: 1500),
          ),
        );
        return;
      }

      // Check for duplicate entry
      final exists = await DatabaseHelper.instance.dahiGheeEntryExists(
        _selectedCustomerId!,
        dateString,
        _selectedProduct!,
      );
      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An entry for this customer and product already exists for this date.'),
            duration: Duration(milliseconds: 1500),
          ),
        );
        return;
      }

      final entry = {
        'customerId': _selectedCustomerId!,
        'product': _selectedProduct!,
        'price': price,
        'date': dateString,
      };

      try {
        await DatabaseHelper.instance.addDahiGheeEntry(entry);
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
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('$_selectedProduct entry saved successfully!')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: Duration(milliseconds: 1500),
        ),
      );

      // Clear the form
      setState(() {
        _formKey.currentState?.reset();
        _selectedProduct = null;
        _selectedCustomerId = null;
        _selectedDate = DateTime.now();
        _priceController.clear();
      });
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
                        'Dahi & Ghee Entry',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              // Form
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Product Selection Card
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.inventory_2,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Product Selection',
                                              style: Theme.of(context).textTheme.titleLarge,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(
                                            labelText: 'Select Product',
                                            prefixIcon: Icon(Icons.shopping_bag),
                                          ),
                                          initialValue: _selectedProduct,
                                          items: ['Dahi', 'Ghee'].map((product) {
                                            return DropdownMenuItem(
                                              value: product,
                                              child: Text(product),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedProduct = value;
                                            });
                                          },
                                          validator: (value) =>
                                              value == null ? 'Please select a product' : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Customer Selection Card
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Customer Information',
                                              style: Theme.of(context).textTheme.titleLarge,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        DropdownButtonFormField<int>(
                                          decoration: const InputDecoration(
                                            labelText: 'Select Customer',
                                            prefixIcon: Icon(Icons.person),
                                          ),
                                          initialValue: _selectedCustomerId,
                                          items: _customers.map((customer) {
                                            return DropdownMenuItem(
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
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Date and Price Card
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Date & Price',
                                              style: Theme.of(context).textTheme.titleLarge,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        InkWell(
                                          onTap: () => _selectDate(context),
                                          child: InputDecorator(
                                            decoration: InputDecoration(
                                              labelText: 'Purchase Date',
                                              prefixIcon: Icon(
                                                Icons.calendar_today,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
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
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  DateFormat('dd MMM, yyyy').format(_selectedDate),
                                                  style: Theme.of(context).textTheme.bodyLarge,
                                                ),
                                                const Icon(Icons.arrow_drop_down),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        TextFormField(
                                          controller: _priceController,
                                          decoration: InputDecoration(
                                            labelText: 'Price (₹)',
                                            prefixIcon: Icon(
                                              Icons.currency_rupee,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            suffixText: '₹',
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
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
                                          keyboardType: const TextInputType.numberWithOptions(
                                              decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                                          ],
                                          validator: (value) {
                                            if (value == null || value.isEmpty) {
                                              return 'Please enter a price';
                                            }
                                            final p = double.tryParse(value);
                                            if (p == null || p <= 0) {
                                              return 'Please enter a valid price';
                                            }
                                            return null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              // Save Button
                              CustomButton(
                                text: 'Save Entry',
                                icon: Icons.save,
                                onPressed: _saveEntry,
                                width: double.infinity,
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
    );
  }
}
