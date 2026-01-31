import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('milk_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: _onConfigure,
    );
  }

  // Enable foreign key constraints for data integrity
  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const doubleType = 'REAL NOT NULL';
    const integerType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE customers (
        id $idType,
        name $textType,
        contactNumber $textType,
        session $textType,
        isActive INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE milk_entries (
        id $idType,
        customerId $integerType,
        quantity $doubleType,
        session $textType,
        date $textType,
        FOREIGN KEY (customerId) REFERENCES customers (id)
      )
    ''');
    
    await db.execute('''
      CREATE TABLE dahi_ghee_entries (
        id $idType,
        customerId $integerType,
        product $textType,
        price $doubleType,
        date $textType,
        FOREIGN KEY (customerId) REFERENCES customers (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE milk_prices (
        id $idType,
        price $doubleType,
        effective_date $textType UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE bill_payments (
        id $idType,
        customerId $integerType,
        month $integerType,
        year $integerType,
        amount $doubleType,
        isPaid INTEGER NOT NULL DEFAULT 0,
        paymentDate $textType,
        FOREIGN KEY (customerId) REFERENCES customers (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id $idType,
        customerId $integerType,
        amount $doubleType,
        date $textType,
        note TEXT,
        FOREIGN KEY (customerId) REFERENCES customers (id)
      )
    ''');

    // Create indices for faster queries
    await db.execute('CREATE INDEX idx_milk_date ON milk_entries(date)');
    await db.execute('CREATE INDEX idx_milk_customer ON milk_entries(customerId)');
    await db.execute('CREATE INDEX idx_dahi_date ON dahi_ghee_entries(date)');
    await db.execute('CREATE INDEX idx_dahi_customer ON dahi_ghee_entries(customerId)');
    await db.execute('CREATE INDEX idx_payments_customer ON payments(customerId)');
    await db.execute('CREATE INDEX idx_payments_date ON payments(date)');
    await db.execute('CREATE INDEX idx_customers_active ON customers(isActive)');
  }
  
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE customers ADD COLUMN isActive INTEGER NOT NULL DEFAULT 1");
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE milk_prices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          price REAL NOT NULL,
          effective_date TEXT NOT NULL UNIQUE
        )
      ''');
    }
    if (oldVersion < 4) {
      // Migrate dahi_ghee_entries: rename quantity to price
      await db.execute("ALTER TABLE dahi_ghee_entries RENAME TO dahi_ghee_entries_old");
      await db.execute('''
        CREATE TABLE dahi_ghee_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER NOT NULL,
          product TEXT NOT NULL,
          price REAL NOT NULL,
          date TEXT NOT NULL,
          FOREIGN KEY (customerId) REFERENCES customers (id)
        )
      ''');
      // Copy data from old table, converting quantity to price (assuming 1:1 for now)
      await db.execute('''
        INSERT INTO dahi_ghee_entries (id, customerId, product, price, date)
        SELECT id, customerId, product, quantity, date FROM dahi_ghee_entries_old
      ''');
      await db.execute("DROP TABLE dahi_ghee_entries_old");
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE bill_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER NOT NULL,
          month INTEGER NOT NULL,
          year INTEGER NOT NULL,
          amount REAL NOT NULL,
          isPaid INTEGER NOT NULL DEFAULT 0,
          paymentDate TEXT,
          FOREIGN KEY (customerId) REFERENCES customers (id)
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          note TEXT,
          FOREIGN KEY (customerId) REFERENCES customers (id)
        )
      ''');
    }
    if (oldVersion < 7) {
      // Add indices for performance optimization
      await db.execute('CREATE INDEX IF NOT EXISTS idx_milk_date ON milk_entries(date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_milk_customer ON milk_entries(customerId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dahi_date ON dahi_ghee_entries(date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dahi_customer ON dahi_ghee_entries(customerId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customerId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(isActive)');
    }
  }

  // Methods for customers
  Future<int> addCustomer(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('customers', row);
  }

  Future<List<Map<String, dynamic>>> getCustomers({bool includeInactive = false}) async {
    final db = await instance.database;
    if (includeInactive) {
      return await db.query('customers', orderBy: 'name');
    } else {
      return await db.query('customers', where: 'isActive = 1', orderBy: 'name');
    }
  }

  Future<int> updateCustomer(Map<String, dynamic> row) async {
    final db = await instance.database;
    final id = row['id'];
    return await db.update('customers', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> archiveCustomer(int id, {bool restore = false}) async {
    final db = await instance.database;
    return await db.update('customers', {'isActive': restore ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  // Soft delete: Sets isActive = 0 instead of deleting the record
  // This preserves financial history for reports
  Future<int> deleteCustomer(int id) async {
    return await archiveCustomer(id, restore: false);
  }

  // Get only active customers (isActive = 1)
  // This is an alias for getCustomers(includeInactive: false) for clarity
  Future<List<Map<String, dynamic>>> getActiveCustomers() async {
    return await getCustomers(includeInactive: false);
  }
  
  // Methods for milk entries
  Future<int> addMilkEntry(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('milk_entries', row);
  }

  Future<List<Map<String, dynamic>>> getMilkEntries(String date) async {
    final db = await instance.database;
    return await db.query('milk_entries', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getMilkEntriesForCustomer(int customerId) async {
    final db = await instance.database;
    return await db.query(
      'milk_entries',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
  }

  /// OPTIMIZATION: Get milk entries for customer within a date range (filters at database level)
  Future<List<Map<String, dynamic>>> getMilkEntriesForCustomerInRange(
    int customerId, 
    String fromDate, 
    String toDate,
  ) async {
    final db = await instance.database;
    return await db.query(
      'milk_entries',
      where: 'customerId = ? AND date >= ? AND date <= ?',
      whereArgs: [customerId, fromDate, toDate],
      orderBy: 'date DESC',
    );
  }
  
  Future<int> updateMilkEntry(Map<String, dynamic> row) async {
    final db = await instance.database;
    final id = row['id'];
    return await db.update('milk_entries', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMilkEntry(int id) async {
    final db = await instance.database;
    return await db.delete('milk_entries', where: 'id = ?', whereArgs: [id]);
  }

  // [OPTIMIZATION 3: Duplicate Entry Check]
  // This new method checks if an entry for a given customer, date, and session already exists.
  Future<bool> entryExists(int customerId, String date, String session) async {
    final db = await instance.database;
    final result = await db.query(
      'milk_entries',
      where: 'customerId = ? AND date = ? AND session = ?',
      whereArgs: [customerId, date, session],
      limit: 1,
    );
    return result.isNotEmpty;
  }
  
  // [OPTIMIZATION 4: Batch Database Writes]
  // The `addMissingEntries` function is optimized to use a batch operation, which
  // groups all database writes into a single transaction, making it much faster.
  Future<void> addMissingEntries() async {
    final db = await instance.database;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final dateString =
        "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

    final allCustomers = await getCustomers();
    final yesterdayEntries = await getMilkEntries(dateString);

    final batch = db.batch();
    var operations = 0;

    for (var session in ['Morning', 'Evening']) {
      final customersForSession = allCustomers
          .where((c) => c['session'] == session || c['session'] == 'Both')
          .toList();
      final enteredCustomerIds = yesterdayEntries
          .where((e) => e['session'] == session)
          .map((e) => e['customerId'])
          .toSet();

      for (var customer in customersForSession) {
        if (!enteredCustomerIds.contains(customer['id'])) {
          batch.insert('milk_entries', {
            'customerId': customer['id'],
            'quantity': 0.0,
            'session': session,
            'date': dateString,
          });
          operations++;
        }
      }
    }

    if (operations > 0) {
      await batch.commit(noResult: true);
    }
  }

  // Methods for dahi/ghee entries
  Future<bool> dahiGheeEntryExists(int customerId, String date, String product) async {
    final db = await instance.database;
    final result = await db.query(
      'dahi_ghee_entries',
      where: 'customerId = ? AND date = ? AND product = ?',
      whereArgs: [customerId, date, product],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<int> addDahiGheeEntry(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('dahi_ghee_entries', row);
  }

  Future<List<Map<String, dynamic>>> getDahiGheeEntries(String date) async {
    final db = await instance.database;
    return await db.query('dahi_ghee_entries', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getDahiGheeEntriesForCustomer(int customerId) async {
    final db = await instance.database;
    return await db.query(
      'dahi_ghee_entries',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
  }

  /// OPTIMIZATION: Get dahi/ghee entries for customer within a date range (filters at database level)
  Future<List<Map<String, dynamic>>> getDahiGheeEntriesForCustomerInRange(
    int customerId,
    String fromDate,
    String toDate,
  ) async {
    final db = await instance.database;
    return await db.query(
      'dahi_ghee_entries',
      where: 'customerId = ? AND date >= ? AND date <= ?',
      whereArgs: [customerId, fromDate, toDate],
      orderBy: 'date DESC',
    );
  }

  Future<int> updateDahiGheeEntry(Map<String, dynamic> row) async {
    final db = await instance.database;
    final id = row['id'];
    return await db.update('dahi_ghee_entries', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteDahiGheeEntry(int id) async {
    final db = await instance.database;
    return await db.delete('dahi_ghee_entries', where: 'id = ?', whereArgs: [id]);
  }

  // Methods for Milk Price
  Future<void> setMilkPrice(Map<String, dynamic> row) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('milk_prices', where: 'effective_date = ?', whereArgs: [row['effective_date']]);
      await txn.insert('milk_prices', row);
    });
  }

  Future<List<Map<String, dynamic>>> getPriceHistory() async {
    final db = await instance.database;
    return await db.query('milk_prices', orderBy: 'effective_date DESC');
  }

  /// Gets the current milk price based on today's date.
  /// Returns the price from the most recent effective_date that is <= today.
  /// Returns 0.0 if no price is found.
  Future<double> getCurrentMilkPrice() async {
    final db = await instance.database;
    final today = DateTime.now();
    final todayString = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    
    final result = await db.query(
      'milk_prices',
      where: 'effective_date <= ?',
      whereArgs: [todayString],
      orderBy: 'effective_date DESC',
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      final val = result.first['price'];
      if (val is num) return val.toDouble();
      if (val is String) {
        final parsed = double.tryParse(val);
        return parsed ?? 0.0;
      }
      return 0.0;
    }
    return 0.0;
  }

  Future<double?> getPriceForDate(String date) async {
    final db = await instance.database;
    // First, try to find a price effective on or before the given date
    final result = await db.query(
      'milk_prices',
      where: 'effective_date <= ?',
      whereArgs: [date],
      orderBy: 'effective_date DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      final val = result.first['price'];
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }
    
    // CRITICAL FIX: If no price found before the specific date, fallback to the oldest available price
    // This prevents bills from being ₹0 if data is entered for dates before the app was installed
    final fallbackResult = await db.query(
      'milk_prices',
      orderBy: 'effective_date ASC',
      limit: 1,
    );
    if (fallbackResult.isNotEmpty) {
      final val = fallbackResult.first['price'];
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
    }
    
    return null; 
  }

  /// Gets the effective date for the current price
  Future<String?> getCurrentPriceEffectiveDate() async {
    final db = await instance.database;
    final today = DateTime.now();
    final todayString = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    
    final result = await db.query(
      'milk_prices',
      where: 'effective_date <= ?',
      whereArgs: [todayString],
      orderBy: 'effective_date DESC',
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      return result.first['effective_date'] as String?;
    }
    return null;
  }

  /// Deletes a milk price entry by effective_date
  Future<int> deleteMilkPrice(String effectiveDate) async {
    final db = await instance.database;
    return await db.delete('milk_prices', where: 'effective_date = ?', whereArgs: [effectiveDate]);
  }

  // ============================================================================
  // PERFORMANCE OPTIMIZATION: Batch Price Lookup
  // ============================================================================
  
  /// Cache for prices to avoid repeated queries within the same operation
  Map<String, double>? _priceCache;

  /// Batch fetch all prices and cache them for efficient lookups.
  /// Call this before processing multiple entries that need price lookups.
  Future<void> _loadPriceCache() async {
    final db = await database;
    final results = await db.query('milk_prices', orderBy: 'effective_date ASC');
    
    _priceCache = {};
    for (var row in results) {
      final date = row['effective_date'] as String;
      final price = (row['price'] as num?)?.toDouble() ?? 0.0;
      _priceCache![date] = price;
    }
  }

  /// Get price for a date using cached prices (O(1) lookup after cache load)
  /// Falls back to single query if cache not loaded
  double? _getPriceFromCache(String date) {
    if (_priceCache == null || _priceCache!.isEmpty) return null;
    
    // Find the most recent price on or before the given date
    double? effectivePrice;
    String? effectiveDate;
    
    for (var entry in _priceCache!.entries) {
      if (entry.key.compareTo(date) <= 0) {
        if (effectiveDate == null || entry.key.compareTo(effectiveDate) > 0) {
          effectiveDate = entry.key;
          effectivePrice = entry.value;
        }
      }
    }
    
    // Fallback to oldest price if no price found before the date
    if (effectivePrice == null && _priceCache!.isNotEmpty) {
      effectivePrice = _priceCache!.values.first;
    }
    
    return effectivePrice;
  }

  /// Clear the price cache (call after price updates)
  void clearPriceCache() {
    _priceCache = null;
  }

  // Methods for Bill Payments and Billing
  Future<Map<String, dynamic>> generateBillData(int customerId, int month, int year) async {
    final db = await instance.database;
    
    // Calculate date range for the month
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startDate = "${firstDay.year}-${firstDay.month.toString().padLeft(2, '0')}-${firstDay.day.toString().padLeft(2, '0')}";
    final endDate = "${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}";
    
    // OPTIMIZATION: Load price cache once instead of N queries
    await _loadPriceCache();
    
    // Fetch all milk entries for this customer in this month
    final milkEntries = await db.query(
      'milk_entries',
      where: 'customerId = ? AND date >= ? AND date <= ?',
      whereArgs: [customerId, startDate, endDate],
      orderBy: 'date ASC',
    );
    
    // Calculate total milk quantity and cost day-by-day with effective pricing
    double totalMilkQty = 0.0;
    double totalMilkCost = 0.0;
    Set<String> daysWithEntries = {};
    
    for (var entry in milkEntries) {
      final quantity = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
      final entryDate = entry['date'] as String;
      
      totalMilkQty += quantity;
      daysWithEntries.add(entryDate);
      
      // OPTIMIZATION: Use cached price lookup (O(1) instead of database query)
      final priceForDate = _getPriceFromCache(entryDate);
      if (priceForDate != null && quantity > 0) {
        totalMilkCost += quantity * priceForDate;
      }
    }
    
    // Calculate total days in month and days absent
    final totalDaysInMonth = lastDay.day;
    final daysAbsent = totalDaysInMonth - daysWithEntries.length;
    
    // Fetch all dahi/ghee entries for this customer in this month
    final dahiGheeEntries = await db.query(
      'dahi_ghee_entries',
      where: 'customerId = ? AND date >= ? AND date <= ?',
      whereArgs: [customerId, startDate, endDate],
    );
    
    // Sum up dahi/ghee costs
    double totalDahiGheeCost = 0.0;
    for (var entry in dahiGheeEntries) {
      final price = (entry['price'] as num?)?.toDouble() ?? 0.0;
      totalDahiGheeCost += price;
    }
    
    final grandTotal = totalMilkCost + totalDahiGheeCost;
    
    return {
      'totalMilkQty': totalMilkQty,
      'totalMilkCost': totalMilkCost,
      'totalDahiGheeCost': totalDahiGheeCost,
      'grandTotal': grandTotal,
      'daysAbsent': daysAbsent,
      'totalDaysInMonth': totalDaysInMonth,
      'daysPresent': daysWithEntries.length,
    };
  }

  Future<void> markBillAsPaid(int customerId, int month, int year, double amount) async {
    final db = await instance.database;
    final today = DateTime.now();
    final paymentDate = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    
    // CRITICAL FIX: Use transaction to ensure both operations succeed or fail together
    await db.transaction((txn) async {
      // 1. Update or insert bill_payments record
      final existing = await txn.query(
        'bill_payments',
        where: 'customerId = ? AND month = ? AND year = ?',
        whereArgs: [customerId, month, year],
        limit: 1,
      );
      
      if (existing.isNotEmpty) {
        // Update existing record
        await txn.update(
          'bill_payments',
          {
            'amount': amount,
            'isPaid': 1,
            'paymentDate': paymentDate,
          },
          where: 'customerId = ? AND month = ? AND year = ?',
          whereArgs: [customerId, month, year],
        );
      } else {
        // Insert new record
        await txn.insert(
          'bill_payments',
          {
            'customerId': customerId,
            'month': month,
            'year': year,
            'amount': amount,
            'isPaid': 1,
            'paymentDate': paymentDate,
          },
        );
      }
      
      // 2. Insert into payments table (ledger) to update customer balance
      // This ensures the customer's "Total Due" balance actually goes down
      // Check if a payment for this exact amount and date already exists to avoid duplicates
      final existingPayment = await txn.query(
        'payments',
        where: 'customerId = ? AND amount = ? AND date = ? AND note LIKE ?',
        whereArgs: [customerId, amount, paymentDate, 'Bill Payment%'],
        limit: 1,
      );
      
      if (existingPayment.isEmpty) {
        final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final monthName = monthNames[month];
        await txn.insert(
          'payments',
          {
            'customerId': customerId,
            'amount': amount,
            'date': paymentDate,
            'note': 'Bill Payment $monthName $year',
          },
        );
      }
    });
  }

  Future<Map<String, dynamic>?> getPaymentStatus(int customerId, int month, int year) async {
    final db = await instance.database;
    final result = await db.query(
      'bill_payments',
      where: 'customerId = ? AND month = ? AND year = ?',
      whereArgs: [customerId, month, year],
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<void> markBillAsUnpaid(int customerId, int month, int year) async {
    final db = await instance.database;
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final notePattern = 'Bill Payment ${monthNames[month]} $year';

    await db.transaction((txn) async {
      // 1. Fetch bill_payments before updating (we need amount & paymentDate to find ledger entry)
      final existing = await txn.query(
        'bill_payments',
        where: 'customerId = ? AND month = ? AND year = ? AND isPaid = 1',
        whereArgs: [customerId, month, year],
        limit: 1,
      );

      // 2. Update bill_payments
      await txn.update(
        'bill_payments',
        {'isPaid': 0, 'paymentDate': null},
        where: 'customerId = ? AND month = ? AND year = ?',
        whereArgs: [customerId, month, year],
      );

      // 3. Remove the ledger entry added by markBillAsPaid so balance stays correct
      if (existing.isNotEmpty) {
        final amount = (existing.first['amount'] as num?)?.toDouble();
        final paymentDate = existing.first['paymentDate'] as String?;
        if (amount != null && paymentDate != null && paymentDate.isNotEmpty) {
          await txn.delete(
            'payments',
            where: 'customerId = ? AND amount = ? AND date = ? AND note = ?',
            whereArgs: [customerId, amount, paymentDate, notePattern],
          );
        }
      }
    });
  }

  // Methods for Payments (Ledger-based)
  Future<int> addPayment(Map<String, dynamic> payment) async {
    final db = await instance.database;
    return await db.insert('payments', payment);
  }

  Future<List<Map<String, dynamic>>> getPaymentsForCustomer(int customerId) async {
    final db = await instance.database;
    return await db.query(
      'payments',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
  }

  /// OPTIMIZATION: Get payments for customer within a date range (filters at database level)
  Future<List<Map<String, dynamic>>> getPaymentsForCustomerInRange(
    int customerId,
    String fromDate,
    String toDate,
  ) async {
    final db = await instance.database;
    return await db.query(
      'payments',
      where: 'customerId = ? AND date >= ? AND date <= ?',
      whereArgs: [customerId, fromDate, toDate],
      orderBy: 'date DESC',
    );
  }

  // Update a ledger payment
  Future<int> updatePayment(Map<String, dynamic> row) async {
    final db = await instance.database;
    final id = row['id'];
    return await db.update('payments', row, where: 'id = ?', whereArgs: [id]);
  }

  // Delete a ledger payment
  Future<int> deletePayment(int id) async {
    final db = await instance.database;
    return await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getCustomerBalance(int customerId) async {
    final db = await instance.database;
    
    // OPTIMIZATION: Load price cache once instead of N queries
    await _loadPriceCache();
    
    // 1. Calculate TotalGoodsValue
    // Sum of all milk_entries (quantity * historic_price)
    final milkEntries = await db.query(
      'milk_entries',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    
    double totalMilkCost = 0.0;
    for (var entry in milkEntries) {
      final quantity = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
      final entryDate = entry['date'] as String;
      
      // OPTIMIZATION: Use cached price lookup (O(1) instead of database query)
      final priceForDate = _getPriceFromCache(entryDate);
      if (priceForDate != null && quantity > 0) {
        totalMilkCost += quantity * priceForDate;
      }
    }
    
    // Sum of all dahi_ghee_entries
    final dahiGheeEntries = await db.query(
      'dahi_ghee_entries',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    
    double totalDahiGheeCost = 0.0;
    for (var entry in dahiGheeEntries) {
      final price = (entry['price'] as num?)?.toDouble() ?? 0.0;
      totalDahiGheeCost += price;
    }
    
    final totalGoodsValue = totalMilkCost + totalDahiGheeCost;
    
    // 2. Calculate TotalPayments
    final payments = await db.query(
      'payments',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    
    double totalPayments = 0.0;
    for (var payment in payments) {
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      totalPayments += amount;
    }
    
    // 3. Return TotalGoodsValue - TotalPayments (positive means they owe money)
    return totalGoodsValue - totalPayments;
  }

  Future<Map<String, dynamic>> getMonthlyBillSummary(int customerId, int month, int year) async {
    // 1. Get detailed calculation from existing helper
    final billData = await generateBillData(customerId, month, year);
    
    // 2. Extract specific values needed for the Detailed SMS
    final totalMilkQty = (billData['totalMilkQty'] as num?)?.toDouble() ?? 0.0;
    final totalMilkCost = (billData['totalMilkCost'] as num?)?.toDouble() ?? 0.0;
    final totalDahiGheeCost = (billData['totalDahiGheeCost'] as num?)?.toDouble() ?? 0.0;
    final currentMonthAmount = (billData['grandTotal'] as num?)?.toDouble() ?? 0.0;
    
    // 3. Get Ledger Balance (This returns total Due or Advance)
    final totalDueTillDate = await getCustomerBalance(customerId);
    
    return {
      'totalMilkQty': totalMilkQty,
      'totalMilkCost': totalMilkCost,
      'totalDahiGheeCost': totalDahiGheeCost,
      'currentMonthAmount': currentMonthAmount,
      'totalDueTillDate': totalDueTillDate,
    };
  }

  Future<List<Map<String, dynamic>>> getBusinessReportData(DateTime startDate, DateTime endDate) async {
    final db = await instance.database;
    final startDateStr = "${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
    final endDateStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";
    
    // OPTIMIZATION: Load price cache once for all balance calculations
    await _loadPriceCache();
    
    // SUPERCHARGED OPTIMIZATION: Single Raw SQL Query with Aggregation
    // This uses SQL SUM() and GROUP BY to aggregate all data in one query
    // Price lookup uses a correlated subquery to find the effective price for each date
    
    final query = '''
      SELECT 
        c.id,
        c.name,
        COALESCE(SUM(CASE WHEN m.date >= ? AND m.date <= ? THEN m.quantity ELSE 0 END), 0) as milk_qty,
        COALESCE(SUM(CASE 
          WHEN m.date >= ? AND m.date <= ? AND m.quantity > 0 THEN 
            m.quantity * (
              SELECT COALESCE(
                (SELECT price FROM milk_prices WHERE effective_date <= m.date ORDER BY effective_date DESC LIMIT 1),
                (SELECT price FROM milk_prices ORDER BY effective_date ASC LIMIT 1),
                0
              )
            )
          ELSE 0 
        END), 0) as milk_cost,
        COALESCE(SUM(CASE 
          WHEN d.date >= ? AND d.date <= ? AND LOWER(d.product) NOT LIKE '%ghee%' THEN d.price 
          ELSE 0 
        END), 0) as dahi_total,
        COALESCE(SUM(CASE 
          WHEN d.date >= ? AND d.date <= ? AND LOWER(d.product) LIKE '%ghee%' THEN d.price 
          ELSE 0 
        END), 0) as ghee_total,
        COALESCE(SUM(CASE 
          WHEN p.date >= ? AND p.date <= ? THEN p.amount 
          ELSE 0 
        END), 0) as totalReceived
      FROM customers c
      LEFT JOIN milk_entries m ON c.id = m.customerId
      LEFT JOIN dahi_ghee_entries d ON c.id = d.customerId
      LEFT JOIN payments p ON c.id = p.customerId
      WHERE c.isActive = 1
      GROUP BY c.id, c.name
      ORDER BY c.name
    ''';
    
    final results = await db.rawQuery(query, [
      startDateStr, endDateStr, // For milk_qty
      startDateStr, endDateStr, // For milk_cost
      startDateStr, endDateStr, // For dahi_total
      startDateStr, endDateStr, // For ghee_total
      startDateStr, endDateStr, // For totalReceived
    ]);
    
    // OPTIMIZATION: Batch calculate global balances for all customers
    // Instead of N queries (one per customer), we do this in bulk
    final customerIds = results.map((r) => r['id'] as int).toList();
    final balances = await _batchGetCustomerBalances(customerIds);
    
    // Build final report data with global balance
    final List<Map<String, dynamic>> reportData = [];
    for (var row in results) {
      final customerId = row['id'] as int;
      final milkQty = (row['milk_qty'] as num?)?.toDouble() ?? 0.0;
      final totalMilkCost = (row['milk_cost'] as num?)?.toDouble() ?? 0.0;
      final totalDahi = (row['dahi_total'] as num?)?.toDouble() ?? 0.0;
      final totalGhee = (row['ghee_total'] as num?)?.toDouble() ?? 0.0;
      final totalReceived = (row['totalReceived'] as num?)?.toDouble() ?? 0.0;
      
      // OPTIMIZATION: Use pre-calculated balance from batch query
      final globalDue = balances[customerId] ?? 0.0;
      
      // Calculate average rate
      final avgRate = milkQty > 0 ? (totalMilkCost / milkQty) : 0.0;
      
      // Calculate total bill
      final totalBill = totalMilkCost + totalDahi + totalGhee;
      
      reportData.add({
        'name': row['name'] as String,
        'milk_qty': milkQty,
        'dahi_total': totalDahi,
        'ghee_total': totalGhee,
        'total_bill': totalBill,
        'received': totalReceived,
        'global_due': globalDue,
        'avg_rate': avgRate,
      });
    }
    
    return reportData;
  }

  /// OPTIMIZATION: Batch calculate balances for multiple customers in minimal queries
  Future<Map<int, double>> _batchGetCustomerBalances(List<int> customerIds) async {
    if (customerIds.isEmpty) return {};
    
    final db = await database;
    final Map<int, double> balances = {};
    
    // Initialize all balances to 0
    for (var id in customerIds) {
      balances[id] = 0.0;
    }
    
    // Ensure price cache is loaded
    if (_priceCache == null) {
      await _loadPriceCache();
    }
    
    // Batch fetch all milk entries for all customers
    final placeholders = customerIds.map((_) => '?').join(',');
    final milkEntries = await db.rawQuery(
      'SELECT customerId, quantity, date FROM milk_entries WHERE customerId IN ($placeholders)',
      customerIds,
    );
    
    // Calculate milk costs using cached prices
    final Map<int, double> milkCosts = {};
    for (var entry in milkEntries) {
      final customerId = entry['customerId'] as int;
      final quantity = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
      final entryDate = entry['date'] as String;
      
      if (quantity > 0) {
        final price = _getPriceFromCache(entryDate) ?? 0.0;
        milkCosts[customerId] = (milkCosts[customerId] ?? 0.0) + (quantity * price);
      }
    }
    
    // Batch fetch all dahi/ghee entries
    final dahiGheeEntries = await db.rawQuery(
      'SELECT customerId, price FROM dahi_ghee_entries WHERE customerId IN ($placeholders)',
      customerIds,
    );
    
    final Map<int, double> dahiGheeCosts = {};
    for (var entry in dahiGheeEntries) {
      final customerId = entry['customerId'] as int;
      final price = (entry['price'] as num?)?.toDouble() ?? 0.0;
      dahiGheeCosts[customerId] = (dahiGheeCosts[customerId] ?? 0.0) + price;
    }
    
    // Batch fetch all payments
    final payments = await db.rawQuery(
      'SELECT customerId, amount FROM payments WHERE customerId IN ($placeholders)',
      customerIds,
    );
    
    final Map<int, double> totalPayments = {};
    for (var payment in payments) {
      final customerId = payment['customerId'] as int;
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      totalPayments[customerId] = (totalPayments[customerId] ?? 0.0) + amount;
    }
    
    // Calculate final balances
    for (var id in customerIds) {
      final goodsValue = (milkCosts[id] ?? 0.0) + (dahiGheeCosts[id] ?? 0.0);
      final paid = totalPayments[id] ?? 0.0;
      balances[id] = goodsValue - paid;
    }
    
    return balances;
  }

  Future close() async {
    final db = await instance.database;
    await db.close();
    _database = null; // clear cached reference
  }
}
