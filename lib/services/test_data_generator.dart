import 'dart:math';
import 'package:gg/services/database_helper.dart';

/// Service for generating test data
class TestDataGenerator {
  static final Random _random = Random();
  
  // Common Indian names for test customers
  static final List<String> _firstNames = [
    'Raj', 'Priya', 'Amit', 'Sunita', 'Vikram', 'Kavita', 'Rahul', 'Anjali',
    'Suresh', 'Meera', 'Deepak', 'Pooja', 'Manoj', 'Rekha', 'Nitin', 'Swati',
    'Arjun', 'Neha', 'Kiran', 'Divya', 'Ravi', 'Shilpa', 'Ajay', 'Sneha',
    'Vishal', 'Anita', 'Gaurav', 'Ritu', 'Pankaj', 'Jyoti', 'Harsh', 'Pallavi',
    'Sachin', 'Monika', 'Yash', 'Richa', 'Kunal', 'Shweta', 'Rohit', 'Nidhi',
    'Abhishek', 'Shruti', 'Tarun', 'Aditi', 'Vivek', 'Kritika', 'Siddharth', 'Isha',
    'Ankit', 'Tanvi', 'Mohit', 'Aishwarya', 'Rishabh', 'Sakshi', 'Varun', 'Preeti',
    'Karan', 'Muskan', 'Shubham', 'Riya', 'Aditya', 'Tanya', 'Nikhil', 'Diksha',
    'Akash', 'Vaishali', 'Ritesh', 'Shreya', 'Saurabh', 'Komal', 'Prateek', 'Manisha',
    'Vikash', 'Surbhi', 'Ashish', 'Nisha', 'Mayank', 'Pooja', 'Himanshu', 'Radha',
  ];
  
  static final List<String> _lastNames = [
    'Sharma', 'Patel', 'Kumar', 'Singh', 'Gupta', 'Verma', 'Yadav', 'Jain',
    'Mehta', 'Shah', 'Reddy', 'Rao', 'Pandey', 'Mishra', 'Chauhan', 'Agarwal',
    'Malhotra', 'Kapoor', 'Bansal', 'Joshi', 'Arora', 'Saxena', 'Tiwari', 'Dubey',
    'Nair', 'Iyer', 'Menon', 'Nair', 'Krishnan', 'Raman', 'Sundaram', 'Venkatesh',
  ];

  /// Generate 70 test customers
  static Future<List<int>> generateCustomers() async {
    final customerIds = <int>[];
    final sessions = ['Morning', 'Evening', 'Both'];
    
    for (int i = 0; i < 70; i++) {
      final firstName = _firstNames[_random.nextInt(_firstNames.length)];
      final lastName = _lastNames[_random.nextInt(_lastNames.length)];
      final name = '$firstName $lastName';
      final phoneNumber = '9${_random.nextInt(9)}${_random.nextInt(100000000).toString().padLeft(9, '0')}';
      final session = sessions[_random.nextInt(sessions.length)];
      
      final customerId = await DatabaseHelper.instance.addCustomer({
        'name': name,
        'contactNumber': phoneNumber,
        'session': session,
        'isActive': 1,
      });
      
      customerIds.add(customerId);
    }
    
    return customerIds;
  }

  /// Generate 2 months of milk entries with some holidays
  static Future<void> generateMilkEntries(List<int> customerIds, {DateTime? startDate}) async {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month - 2, 1);
    final end = DateTime(now.year, now.month, 0); // Last day of previous month
    
    // Get all customers once to avoid repeated queries
    final customers = await DatabaseHelper.instance.getCustomers();
    final customerMap = <int, Map<String, dynamic>>{};
    for (final customer in customers) {
      customerMap[customer['id'] as int] = customer;
    }
    
    // Define some holidays (Sundays and a few random days)
    final holidays = <DateTime>{};
    
    // Add all Sundays
    var current = start;
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      if (current.weekday == DateTime.sunday) {
        holidays.add(DateTime(current.year, current.month, current.day));
      }
      current = current.add(const Duration(days: 1));
    }
    
    // Add a few random holidays (about 3-4 per month)
    for (int i = 0; i < 8; i++) {
      final randomDay = start.add(Duration(days: _random.nextInt(end.difference(start).inDays)));
      if (randomDay.weekday != DateTime.sunday) {
        holidays.add(DateTime(randomDay.year, randomDay.month, randomDay.day));
      }
    }
    
    // Use batch insert for better performance
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    int batchCount = 0;
    
    // Generate entries for each day
    current = start;
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      final dateStr = _formatDate(current);
      final isHoliday = holidays.contains(DateTime(current.year, current.month, current.day));
      
      if (!isHoliday) {
        // Generate entries for this day
        for (final customerId in customerIds) {
          final customer = customerMap[customerId];
          if (customer == null) continue;
          
          final session = customer['session'] as String;
          
          // Generate entries based on session
          if (session == 'Morning' || session == 'Both') {
            final quantity = _random.nextDouble() * 3 + 1; // 1-4 liters
            batch.insert('milk_entries', {
              'customerId': customerId,
              'quantity': double.parse(quantity.toStringAsFixed(1)),
              'session': 'Morning',
              'date': dateStr,
            });
            batchCount++;
          }
          
          if (session == 'Evening' || session == 'Both') {
            final quantity = _random.nextDouble() * 3 + 1; // 1-4 liters
            batch.insert('milk_entries', {
              'customerId': customerId,
              'quantity': double.parse(quantity.toStringAsFixed(1)),
              'session': 'Evening',
              'date': dateStr,
            });
            batchCount++;
          }
          
          // Commit batch every 500 operations to avoid memory issues
          if (batchCount >= 500) {
            await batch.commit(noResult: true);
            batchCount = 0;
          }
        }
      }
      
      current = current.add(const Duration(days: 1));
    }
    
    // Commit remaining operations
    if (batchCount > 0) {
      await batch.commit(noResult: true);
    }
  }

  /// Generate dahi/ghee entries for a few days
  static Future<void> generateDahiGheeEntries(List<int> customerIds, {DateTime? startDate}) async {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month - 2, 1);
    final end = DateTime(now.year, now.month, 0);
    
    // Generate entries for about 8-10 random days
    final entryDays = <DateTime>{};
    while (entryDays.length < 10) {
      final randomDay = start.add(Duration(days: _random.nextInt(end.difference(start).inDays)));
      entryDays.add(DateTime(randomDay.year, randomDay.month, randomDay.day));
    }
    
    final products = ['Dahi', 'Ghee'];
    final dahiPrices = [50, 60, 70, 80, 90, 100];
    final gheePrices = [500, 550, 600, 650, 700, 750];
    
    // Use batch insert for better performance
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    int batchCount = 0;
    
    for (final day in entryDays) {
      final dateStr = _formatDate(day);
      
      // Select random customers (about 30-40% of customers)
      final selectedCustomers = customerIds.toList()..shuffle(_random);
      final count = (customerIds.length * 0.35).round();
      final customersForDay = selectedCustomers.take(count).toList();
      
      for (final customerId in customersForDay) {
        final product = products[_random.nextInt(products.length)];
        final price = product == 'Dahi' 
            ? dahiPrices[_random.nextInt(dahiPrices.length)].toDouble()
            : gheePrices[_random.nextInt(gheePrices.length)].toDouble();
        
        batch.insert('dahi_ghee_entries', {
          'customerId': customerId,
          'product': product,
          'price': price,
          'date': dateStr,
        });
        batchCount++;
        
        // Commit batch every 100 operations
        if (batchCount >= 100) {
          await batch.commit(noResult: true);
          batchCount = 0;
        }
      }
    }
    
    // Commit remaining operations
    if (batchCount > 0) {
      await batch.commit(noResult: true);
    }
  }

  /// Set some milk prices for the test period
  static Future<void> generateMilkPrices({DateTime? startDate}) async {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month - 2, 1);
    
    // Set prices at the start of each month
    final prices = [200, 210, 220, 230, 240, 250];
    
    // Price for first month
    await DatabaseHelper.instance.setMilkPrice({
      'price': prices[_random.nextInt(prices.length)].toDouble(),
      'effective_date': _formatDate(start),
    });
    
    // Price for second month
    final secondMonthStart = DateTime(start.year, start.month + 1, 1);
    await DatabaseHelper.instance.setMilkPrice({
      'price': prices[_random.nextInt(prices.length)].toDouble(),
      'effective_date': _formatDate(secondMonthStart),
    });
  }

  /// Generate all test data
  static Future<void> generateAllTestData({DateTime? startDate}) async {
    // Generate customers
    final customerIds = await generateCustomers();
    
    // Generate milk prices
    await generateMilkPrices(startDate: startDate);
    
    // Generate milk entries
    await generateMilkEntries(customerIds, startDate: startDate);
    
    // Generate dahi/ghee entries
    await generateDahiGheeEntries(customerIds, startDate: startDate);
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
