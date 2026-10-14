import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!;
    _opening = _open();
    try {
      _db = await _opening!;
      return _db!;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'expense_tracker.db');
    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db);
      },
      onOpen: (db) async {
        await _createSchema(db);
        await _migrate(db);
        await _seed(db);
      },
    );
  }

  Future<void> initialize() async => database;

  Future<void> _createSchema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS transactions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      amount REAL NOT NULL,
      type TEXT NOT NULL,
      category TEXT NOT NULL,
      merchant TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL,
      raw_message TEXT NOT NULL DEFAULT '',
      sender TEXT NOT NULL DEFAULT '',
      payment_method TEXT NOT NULL DEFAULT '',
      account_hint TEXT NOT NULL DEFAULT '',
      upi_reference TEXT NOT NULL DEFAULT '',
      classification_method TEXT NOT NULL DEFAULT 'legacy',
      classification_confidence REAL NOT NULL DEFAULT 1.0,
      occurred_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      fingerprint TEXT NOT NULL UNIQUE,
      is_manual INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rules(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      merchant TEXT NOT NULL,
      keyword TEXT NOT NULL,
      type TEXT NOT NULL,
      category TEXT NOT NULL,
      is_user_rule INTEGER NOT NULL DEFAULT 0,
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS budgets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL UNIQUE,
      amount REAL NOT NULL,
      period TEXT NOT NULL DEFAULT 'monthly'
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS categories(
      name TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      is_system INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''');
  }

  Future<void> _migrate(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(transactions)');
    final columns = rows.map((e) => '${e['name']}').toSet();
    if (!columns.contains('note')) {
      await db.execute("ALTER TABLE transactions ADD COLUMN note TEXT NOT NULL DEFAULT ''");
    }
    if (!columns.contains('upi_reference')) {
      await db.execute("ALTER TABLE transactions ADD COLUMN upi_reference TEXT NOT NULL DEFAULT ''");
    }
    if (!columns.contains('classification_method')) {
      await db.execute("ALTER TABLE transactions ADD COLUMN classification_method TEXT NOT NULL DEFAULT 'legacy'");
    }
    if (!columns.contains('classification_confidence')) {
      await db.execute("ALTER TABLE transactions ADD COLUMN classification_confidence REAL NOT NULL DEFAULT 1.0");
    }
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const categories = <(String, String)>[
      ('Food & Dining', 'expense'),
      ('Groceries', 'expense'),
      ('Transport', 'expense'),
      ('Shopping', 'expense'),
      ('Entertainment', 'expense'),
      ('Bills & Utilities', 'expense'),
      ('Healthcare', 'expense'),
      ('Travel', 'expense'),
      ('Education', 'expense'),
      ('Rent & Housing', 'expense'),
      ('EMI & Loans', 'expense'),
      ('Insurance', 'expense'),
      ('Stocks', 'investment'),
      ('Mutual Funds', 'investment'),
      ('Gold', 'investment'),
      ('Other Investment', 'investment'),
      ('Salary', 'income'),
      ('Refund', 'refund'),
      ('Transfer', 'transfer'),
      ('Uncategorized', 'expense'),
    ];
    for (final item in categories) {
      await db.insert(
        'categories',
        {'name': item.$1, 'kind': item.$2, 'is_system': 1, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    const defaults = <(String, String, String, String)>[
      ('Zomato', 'zomato', 'expense', 'Food & Dining'),
      ('Swiggy', 'swiggy', 'expense', 'Food & Dining'),
      ('Blinkit', 'blinkit', 'expense', 'Groceries'),
      ('Zepto', 'zepto', 'expense', 'Groceries'),
      ('BigBasket', 'bigbasket', 'expense', 'Groceries'),
      ('Uber', 'uber', 'expense', 'Transport'),
      ('Ola', 'ola', 'expense', 'Transport'),
      ('Rapido', 'rapido', 'expense', 'Transport'),
      ('Netflix', 'netflix', 'expense', 'Entertainment'),
      ('Spotify', 'spotify', 'expense', 'Entertainment'),
      ('Amazon', 'amazon', 'expense', 'Shopping'),
      ('Flipkart', 'flipkart', 'expense', 'Shopping'),
      ('Myntra', 'myntra', 'expense', 'Shopping'),
      ('AJIO', 'ajio', 'expense', 'Shopping'),
      ('IRCTC', 'irctc', 'expense', 'Travel'),
      ('MakeMyTrip', 'makemytrip', 'expense', 'Travel'),
      ('Zerodha', 'zerodha', 'investment', 'Stocks'),
      ('Groww', 'groww', 'investment', 'Other Investment'),
      ('Mutual Fund', 'mutual fund', 'investment', 'Mutual Funds'),
      ('SIP', 'sip', 'investment', 'Mutual Funds'),
    ];
    for (final rule in defaults) {
      final exists = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM rules WHERE keyword = ? AND is_user_rule = 0',
            [rule.$2],
          )) ??
          0;
      if (exists == 0) {
        await db.insert('rules', {
          'merchant': rule.$1,
          'keyword': rule.$2,
          'type': rule.$3,
          'category': rule.$4,
          'is_user_rule': 0,
          'enabled': 1,
          'created_at': now,
        });
      }
    }

    await db.insert(
      'budgets',
      {'category': '__overall__', 'amount': 30000.0, 'period': 'monthly'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    const settings = {
      'sms_tracking_enabled': '0',
      'phonepe_notification_enabled': '0',
      'notifications_enabled': '1',
      'daily_summary_enabled': '1',
      'daily_summary_hour': '21',
      'daily_summary_minute': '0',
      'hybrid_classifier_enabled': '1',
      'classifier_confidence_threshold': '0.56',
      'learn_from_corrections': '1',
    };
    for (final e in settings.entries) {
      await db.insert(
        'settings',
        {'key': e.key, 'value': e.value},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  (int, int) _monthRange() {
    final now = DateTime.now();
    return (
      DateTime(now.year, now.month, 1).millisecondsSinceEpoch,
      DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch,
    );
  }

  Future<List<TxRecord>> transactions({String? type, int limit = 300}) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: type == null || type == 'all' ? null : 'type = ?',
      whereArgs: type == null || type == 'all' ? null : [type],
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<List<TxRecord>> recentTransactions([int limit = 6]) async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'occurred_at DESC', limit: limit);
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<int> addManualTransaction({
    required double amount,
    required String merchant,
    required String type,
    required String category,
    String note = '',
    String paymentMethod = 'Manual',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('transactions', {
      'amount': amount,
      'type': type,
      'category': category,
      'merchant': merchant.trim().isEmpty ? 'Manual transaction' : merchant.trim(),
      'note': note.trim(),
      'source': 'manual',
      'raw_message': '',
      'sender': '',
      'payment_method': paymentMethod,
      'account_hint': '',
      'upi_reference': '',
      'classification_method': 'manual',
      'classification_confidence': 1.0,
      'occurred_at': now,
      'created_at': now,
      'fingerprint': 'manual-$now-${DateTime.now().microsecondsSinceEpoch}',
      'is_manual': 1,
    });
  }

  Future<int> addUpiTransaction({
    required double amount,
    required String merchant,
    required String category,
    required String note,
    required String upiReference,
    String rawResponse = '',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = upiReference.trim();
    final fingerprint = ref.isNotEmpty
        ? 'upi-$ref'
        : 'upi-${amount.toStringAsFixed(2)}-${merchant.toLowerCase()}-${now ~/ 60000}';
    return db.insert(
      'transactions',
      {
        'amount': amount,
        'type': 'expense',
        'category': category,
        'merchant': merchant.trim().isEmpty ? 'UPI payment' : merchant.trim(),
        'note': note.trim(),
        'source': 'upi_intent',
        'raw_message': rawResponse,
        'sender': '',
        'payment_method': 'UPI / PhonePe',
        'account_hint': '',
        'upi_reference': ref,
        'classification_method': 'upi_intent',
        'classification_confidence': 1.0,
        'occurred_at': now,
        'created_at': now,
        'fingerprint': fingerprint,
        'is_manual': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateTransaction(
    int id, {
    required String type,
    required String category,
    required String merchant,
    required String note,
  }) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'type': type,
        'category': category,
        'merchant': merchant,
        'note': note,
        'classification_method': 'user_corrected',
        'classification_confidence': 1.0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final learn = await getBoolSetting('learn_from_corrections', fallback: true);
    final keyword = merchant.trim().toLowerCase();
    const generic = {'unknown', 'phonepe', 'upi payment', 'manual transaction'};
    if (learn && keyword.length >= 3 && !generic.contains(keyword)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await db.query(
        'rules',
        columns: ['id'],
        where: 'keyword = ? AND is_user_rule = 1',
        whereArgs: [keyword],
        limit: 1,
      );
      final values = {
        'merchant': merchant.trim(),
        'keyword': keyword,
        'type': type,
        'category': category,
        'is_user_rule': 1,
        'enabled': 1,
        'created_at': now,
      };
      if (existing.isEmpty) {
        await db.insert('rules', values);
      } else {
        await db.update('rules', values, where: 'id = ?', whereArgs: [existing.first['id']]);
      }
    }
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, double>> monthTotalsByType() async {
    final db = await database;
    final range = _monthRange();
    final rows = await db.rawQuery(
      'SELECT type, COALESCE(SUM(amount), 0) AS total FROM transactions '
      'WHERE occurred_at >= ? AND occurred_at < ? GROUP BY type',
      [range.$1, range.$2],
    );
    return {
      for (final row in rows)
        row['type'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> monthExpenseByCategory() async {
    final db = await database;
    final range = _monthRange();
    final rows = await db.rawQuery(
      "SELECT category, COALESCE(SUM(amount), 0) AS total FROM transactions "
      "WHERE occurred_at >= ? AND occurred_at < ? AND type = 'expense' "
      'GROUP BY category ORDER BY total DESC',
      [range.$1, range.$2],
    );
    return {
      for (final row in rows)
        row['category'] as String: (row['total'] as num).toDouble(),
    };
  }


  Future<TxRecord?> transactionById(int id) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : TxRecord.fromMap(rows.first);
  }

  Future<List<int>> availableYears() async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['occurred_at']);
    final years = <int>{DateTime.now().year};
    for (final row in rows) {
      final value = row['occurred_at'];
      if (value is num) {
        years.add(DateTime.fromMillisecondsSinceEpoch(value.toInt()).year);
      }
    }
    final result = years.toList()..sort((a, b) => b.compareTo(a));
    return result;
  }

  Future<Map<String, double>> totalsByTypeForPeriod(int startMs, int endMs) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT type, COALESCE(SUM(amount), 0) AS total FROM transactions '
      'WHERE occurred_at >= ? AND occurred_at < ? GROUP BY type',
      [startMs, endMs],
    );
    return {
      for (final row in rows)
        row['type'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> expenseByCategoryForPeriod(int startMs, int endMs) async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT category, COALESCE(SUM(amount), 0) AS total FROM transactions "
      "WHERE occurred_at >= ? AND occurred_at < ? AND type = 'expense' "
      'GROUP BY category ORDER BY total DESC',
      [startMs, endMs],
    );
    return {
      for (final row in rows)
        row['category'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> expenseByMerchantForPeriod(
    int startMs,
    int endMs, {
    int limit = 8,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT merchant, COALESCE(SUM(amount), 0) AS total FROM transactions "
      "WHERE occurred_at >= ? AND occurred_at < ? AND type = 'expense' "
      'GROUP BY merchant ORDER BY total DESC LIMIT ?',
      [startMs, endMs, limit],
    );
    return {
      for (final row in rows)
        row['merchant'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<TxRecord?> largestExpenseForPeriod(int startMs, int endMs) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: "type = 'expense' AND occurred_at >= ? AND occurred_at < ?",
      whereArgs: [startMs, endMs],
      orderBy: 'amount DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TxRecord.fromMap(rows.first);
  }

  Future<List<double>> monthlyExpenseForYear(int year) async {
    final db = await database;
    final start = DateTime(year, 1, 1).millisecondsSinceEpoch;
    final end = DateTime(year + 1, 1, 1).millisecondsSinceEpoch;
    final rows = await db.query(
      'transactions',
      columns: ['amount', 'occurred_at'],
      where: "type = 'expense' AND occurred_at >= ? AND occurred_at < ?",
      whereArgs: [start, end],
    );
    final totals = List<double>.filled(12, 0);
    for (final row in rows) {
      final amount = (row['amount'] as num).toDouble();
      final occurredAt = (row['occurred_at'] as num).toInt();
      final month = DateTime.fromMillisecondsSinceEpoch(occurredAt).month;
      totals[month - 1] += amount;
    }
    return totals;
  }

  Future<List<MerchantRule>> rules() async {
    final db = await database;
    final rows = await db.query('rules', orderBy: 'is_user_rule DESC, merchant COLLATE NOCASE ASC');
    return rows.map(MerchantRule.fromMap).toList();
  }

  Future<void> saveRule(MerchantRule rule) async {
    final db = await database;
    final values = {
      'merchant': rule.merchant.trim(),
      'keyword': rule.keyword.trim().toLowerCase(),
      'type': rule.type,
      'category': rule.category,
      'is_user_rule': rule.isUserRule ? 1 : 0,
      'enabled': rule.enabled ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (rule.id == null) {
      await db.insert('rules', values);
    } else {
      await db.update('rules', values, where: 'id = ?', whereArgs: [rule.id]);
    }
  }

  Future<void> toggleRule(int id, bool enabled) async {
    final db = await database;
    await db.update('rules', {'enabled': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRule(int id) async {
    final db = await database;
    await db.delete('rules', where: 'id = ? AND is_user_rule = 1', whereArgs: [id]);
  }

  Future<List<CategoryRecord>> categories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(CategoryRecord.fromMap).toList();
  }

  Future<List<CategoryRecord>> expenseCategories() async {
    final all = await categories();
    return all.where((c) => c.kind == 'expense').toList();
  }

  Future<void> addCategory(String name, String kind) async {
    final db = await database;
    await db.insert(
      'categories',
      {
        'name': name.trim(),
        'kind': kind,
        'is_system': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteCategory(String name) async {
    final db = await database;
    await db.delete('categories', where: 'name = ? AND is_system = 0', whereArgs: [name]);
  }

  Future<List<BudgetRecord>> budgets() async {
    final db = await database;
    final rows = await db.query('budgets', orderBy: 'category');
    return rows.map(BudgetRecord.fromMap).toList();
  }

  Future<double> overallBudget() async {
    final db = await database;
    final rows = await db.query(
      'budgets',
      columns: ['amount'],
      where: 'category = ?',
      whereArgs: ['__overall__'],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['amount'] as num).toDouble();
  }

  Future<void> setBudget(String category, double amount) async {
    final db = await database;
    await db.insert(
      'budgets',
      {'category': category, 'amount': amount, 'period': 'monthly'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBudget(String category) async {
    if (category == '__overall__') return;
    final db = await database;
    await db.delete('budgets', where: 'category = ?', whereArgs: [category]);
  }

  Future<String> getSetting(String key, {String fallback = ''}) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  Future<bool> getBoolSetting(String key, {bool fallback = false}) async =>
      (await getSetting(key, fallback: fallback ? '1' : '0')) == '1';

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
