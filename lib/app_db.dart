import 'dart:math' as math;
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
      version: 6,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db);
        await _migrate(db);
        await _seed(db);
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
      normalized_merchant TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL,
      raw_message TEXT NOT NULL DEFAULT '',
      sender TEXT NOT NULL DEFAULT '',
      payment_method TEXT NOT NULL DEFAULT '',
      account_hint TEXT NOT NULL DEFAULT '',
      upi_reference TEXT NOT NULL DEFAULT '',
      classification_method TEXT NOT NULL DEFAULT 'legacy',
      classification_confidence REAL NOT NULL DEFAULT 1.0,
      review_status TEXT NOT NULL DEFAULT 'accepted',
      transfer_group_id TEXT NOT NULL DEFAULT '',
      dedup_cluster TEXT NOT NULL DEFAULT '',
      parent_transaction_id INTEGER,
      is_split_parent INTEGER NOT NULL DEFAULT 0,
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
    await db.execute('CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute('''CREATE TABLE IF NOT EXISTS categories(
      name TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      is_system INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS transaction_splits(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transaction_id INTEGER NOT NULL,
      category TEXT NOT NULL,
      amount REAL NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS accounts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_key TEXT NOT NULL UNIQUE,
      account_hint TEXT NOT NULL DEFAULT '',
      sender TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL,
      institution TEXT NOT NULL DEFAULT '',
      current_balance REAL NOT NULL DEFAULT 0,
      include_net_worth INTEGER NOT NULL DEFAULT 0,
      last_seen INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS merchant_aliases(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pattern TEXT NOT NULL UNIQUE,
      normalized_name TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS review_feedback(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transaction_id INTEGER,
      original_type TEXT NOT NULL DEFAULT '',
      final_type TEXT NOT NULL DEFAULT '',
      original_category TEXT NOT NULL DEFAULT '',
      final_category TEXT NOT NULL DEFAULT '',
      action TEXT NOT NULL DEFAULT 'corrected',
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS net_worth_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      item_type TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT '',
      balance REAL NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_time ON transactions(occurred_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_amount ON transactions(amount)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_review ON transactions(review_status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_normalized_merchant ON transactions(normalized_merchant)');
  }

  Future<void> _ensureColumn(Database db, String table, String column, String definition) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    if (!rows.any((e) => '${e['name']}' == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _migrate(Database db) async {
    await _ensureColumn(db, 'transactions', 'note', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'transactions', 'upi_reference', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'transactions', 'classification_method', "TEXT NOT NULL DEFAULT 'legacy'");
    await _ensureColumn(db, 'transactions', 'classification_confidence', 'REAL NOT NULL DEFAULT 1.0');
    await _ensureColumn(db, 'transactions', 'normalized_merchant', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'transactions', 'review_status', "TEXT NOT NULL DEFAULT 'accepted'");
    await _ensureColumn(db, 'transactions', 'transfer_group_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'transactions', 'dedup_cluster', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'transactions', 'parent_transaction_id', 'INTEGER');
    await _ensureColumn(db, 'transactions', 'is_split_parent', 'INTEGER NOT NULL DEFAULT 0');
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const categories = <(String, String)>[
      ('Food & Dining', 'expense'), ('Groceries', 'expense'), ('Transport', 'expense'),
      ('Shopping', 'expense'), ('Entertainment', 'expense'), ('Bills & Utilities', 'expense'),
      ('Healthcare', 'expense'), ('Travel', 'expense'), ('Education', 'expense'),
      ('Rent & Housing', 'expense'), ('EMI & Loans', 'expense'), ('Insurance', 'expense'),
      ('Stocks', 'investment'), ('Mutual Funds', 'investment'), ('Gold', 'investment'),
      ('Other Investment', 'investment'), ('Salary', 'income'), ('Refund', 'refund'),
      ('Transfer', 'transfer'), ('Credit Card Payment', 'transfer'), ('Uncategorized', 'expense'),
    ];
    for (final item in categories) {
      await db.insert('categories', {'name': item.$1, 'kind': item.$2, 'is_system': 1, 'created_at': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    const defaults = <(String, String, String, String)>[
      ('Zomato', 'zomato', 'expense', 'Food & Dining'), ('Swiggy', 'swiggy', 'expense', 'Food & Dining'),
      ('Blinkit', 'blinkit', 'expense', 'Groceries'), ('Zepto', 'zepto', 'expense', 'Groceries'),
      ('BigBasket', 'bigbasket', 'expense', 'Groceries'), ('Uber', 'uber', 'expense', 'Transport'),
      ('Ola', 'ola', 'expense', 'Transport'), ('Rapido', 'rapido', 'expense', 'Transport'),
      ('Netflix', 'netflix', 'expense', 'Entertainment'), ('Spotify', 'spotify', 'expense', 'Entertainment'),
      ('Amazon', 'amazon', 'expense', 'Shopping'), ('Flipkart', 'flipkart', 'expense', 'Shopping'),
      ('Myntra', 'myntra', 'expense', 'Shopping'), ('AJIO', 'ajio', 'expense', 'Shopping'),
      ('IRCTC', 'irctc', 'expense', 'Travel'), ('MakeMyTrip', 'makemytrip', 'expense', 'Travel'),
      ('Zerodha', 'zerodha', 'investment', 'Stocks'), ('Groww', 'groww', 'investment', 'Other Investment'),
      ('Mutual Fund', 'mutual fund', 'investment', 'Mutual Funds'), ('SIP', 'sip', 'investment', 'Mutual Funds'),
    ];
    for (final rule in defaults) {
      final exists = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rules WHERE keyword=? AND is_user_rule=0', [rule.$2])) ?? 0;
      if (exists == 0) {
        await db.insert('rules', {'merchant': rule.$1, 'keyword': rule.$2, 'type': rule.$3, 'category': rule.$4, 'is_user_rule': 0, 'enabled': 1, 'created_at': now});
      }
    }

    const aliases = <String, String>{
      'zomato': 'Zomato', 'swiggy': 'Swiggy', 'blinkit': 'Blinkit', 'zepto': 'Zepto',
      'amazon': 'Amazon', 'amzn': 'Amazon', 'flipkart': 'Flipkart', 'myntra': 'Myntra',
      'uber': 'Uber', 'rapido': 'Rapido', 'netflix': 'Netflix', 'spotify': 'Spotify',
      'phonepe': 'PhonePe', 'google pay': 'Google Pay', 'gpay': 'Google Pay', 'paytm': 'Paytm',
      'zerodha': 'Zerodha', 'groww': 'Groww', 'irctc': 'IRCTC', 'makemytrip': 'MakeMyTrip',
    };
    for (final e in aliases.entries) {
      await db.insert('merchant_aliases', {'pattern': e.key, 'normalized_name': e.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await db.insert('budgets', {'category': '__overall__', 'amount': 30000.0, 'period': 'monthly'}, conflictAlgorithm: ConflictAlgorithm.ignore);
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
      'smart_transfer_matching': '1',
      'smart_dedup_enabled': '1',
      'recurring_detection_enabled': '1',
      'privacy_lock_enabled': '0',
      'secure_screen_enabled': '0',
      'dark_mode': '0',
      'smart_alerts_enabled': '1',
    };
    for (final e in settings.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  (int, int) _monthRange([DateTime? date]) {
    final now = date ?? DateTime.now();
    return (DateTime(now.year, now.month, 1).millisecondsSinceEpoch, DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch);
  }

  String _acceptedWhere([String extra = '']) => "review_status='accepted'${extra.isEmpty ? '' : ' AND $extra'}";

  Future<String> normalizedMerchant(String merchant) async {
    final db = await database;
    final lower = merchant.toLowerCase().trim();
    if (lower.isEmpty) return merchant;
    final aliases = await db.query('merchant_aliases', orderBy: 'LENGTH(pattern) DESC');
    for (final a in aliases) {
      final pattern = (a['pattern'] as String).toLowerCase();
      if (pattern.isNotEmpty && lower.contains(pattern)) return a['normalized_name'] as String;
    }
    var cleaned = merchant.replaceAll(RegExp(r'[@_*\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\b(?:upi|payment|payments|pvt|private|limited|ltd|india|online|store|stores)\b', caseSensitive: false), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? merchant.trim() : cleaned;
  }

  Future<List<TxRecord>> transactions({String? type, int limit = 300}) async {
    final db = await database;
    final clauses = <String>["review_status='accepted'"];
    final args = <Object?>[];
    if (type != null && type != 'all') { clauses.add('type=?'); args.add(type); }
    final rows = await db.query('transactions', where: clauses.join(' AND '), whereArgs: args, orderBy: 'occurred_at DESC', limit: limit);
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<List<TxRecord>> recentTransactions([int limit = 6]) async {
    final db = await database;
    final rows = await db.query('transactions', where: "review_status='accepted'", orderBy: 'occurred_at DESC', limit: limit);
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<List<TxRecord>> reviewTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', where: "review_status='needs_review'", orderBy: 'occurred_at DESC');
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<int> addManualTransaction({required double amount, required String merchant, required String type, required String category, String note = '', String paymentMethod = 'Manual'}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawMerchant = merchant.trim().isEmpty ? 'Manual transaction' : merchant.trim();
    final normalized = await normalizedMerchant(rawMerchant);
    return db.insert('transactions', {
      'amount': amount, 'type': type, 'category': category, 'merchant': rawMerchant, 'normalized_merchant': normalized,
      'note': note.trim(), 'source': 'manual', 'raw_message': '', 'sender': '', 'payment_method': paymentMethod,
      'account_hint': '', 'upi_reference': '', 'classification_method': 'manual', 'classification_confidence': 1.0,
      'review_status': 'accepted', 'occurred_at': now, 'created_at': now,
      'fingerprint': 'manual-$now-${DateTime.now().microsecondsSinceEpoch}', 'is_manual': 1,
    });
  }

  Future<int> addReceiptTransaction({required double amount, required String merchant, required String category, required String rawText, String note = ''}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = await normalizedMerchant(merchant);
    return db.insert('transactions', {
      'amount': amount, 'type': 'expense', 'category': category, 'merchant': merchant, 'normalized_merchant': normalized,
      'note': note, 'source': 'receipt_ocr', 'raw_message': rawText, 'sender': 'Receipt', 'payment_method': 'Receipt',
      'classification_method': 'receipt_ocr', 'classification_confidence': 0.9, 'review_status': 'accepted',
      'occurred_at': now, 'created_at': now, 'fingerprint': 'receipt-$now-${amount.toStringAsFixed(2)}', 'is_manual': 1,
    });
  }

  Future<int> addUpiTransaction({required double amount, required String merchant, required String category, required String note, required String upiReference, String rawResponse = ''}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = upiReference.trim();
    final rawMerchant = merchant.trim().isEmpty ? 'UPI payment' : merchant.trim();
    final normalized = await normalizedMerchant(rawMerchant);
    final fingerprint = ref.isNotEmpty ? 'upi-$ref' : 'upi-${amount.toStringAsFixed(2)}-${normalized.toLowerCase()}-${now ~/ 60000}';
    return db.insert('transactions', {
      'amount': amount, 'type': 'expense', 'category': category, 'merchant': rawMerchant, 'normalized_merchant': normalized,
      'note': note.trim(), 'source': 'upi_intent', 'raw_message': rawResponse, 'sender': '', 'payment_method': 'UPI',
      'account_hint': '', 'upi_reference': ref, 'classification_method': 'upi_intent', 'classification_confidence': 1.0,
      'review_status': 'accepted', 'occurred_at': now, 'created_at': now, 'fingerprint': fingerprint, 'is_manual': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateTransaction(int id, {required String type, required String category, required String merchant, required String note}) async {
    final db = await database;
    final before = await transactionById(id);
    final normalized = await normalizedMerchant(merchant);
    await db.update('transactions', {
      'type': type, 'category': category, 'merchant': merchant, 'normalized_merchant': normalized, 'note': note,
      'classification_method': 'user_corrected', 'classification_confidence': 1.0, 'review_status': 'accepted',
    }, where: 'id=?', whereArgs: [id]);

    if (before != null && (before.type != type || before.category != category || before.merchant != merchant)) {
      await db.insert('review_feedback', {
        'transaction_id': id, 'original_type': before.type, 'final_type': type, 'original_category': before.category,
        'final_category': category, 'action': 'corrected', 'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    final learn = await getBoolSetting('learn_from_corrections', fallback: true);
    final keyword = normalized.trim().toLowerCase();
    const generic = {'unknown', 'phonepe', 'upi payment', 'manual transaction'};
    if (learn && keyword.length >= 3 && !generic.contains(keyword)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await db.query('rules', columns: ['id'], where: 'keyword=? AND is_user_rule=1', whereArgs: [keyword], limit: 1);
      final values = {'merchant': normalized, 'keyword': keyword, 'type': type, 'category': category, 'is_user_rule': 1, 'enabled': 1, 'created_at': now};
      if (existing.isEmpty) { await db.insert('rules', values); } else { await db.update('rules', values, where: 'id=?', whereArgs: [existing.first['id']]); }
    }
  }

  Future<void> acceptReview(int id) async {
    final db = await database;
    await db.update('transactions', {'review_status': 'accepted'}, where: 'id=?', whereArgs: [id]);
    await db.insert('review_feedback', {'transaction_id': id, 'action': 'accepted', 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  Future<void> ignoreReview(int id) async {
    final db = await database;
    await db.update('transactions', {'review_status': 'ignored'}, where: 'id=?', whereArgs: [id]);
    await db.insert('review_feedback', {'transaction_id': id, 'action': 'ignored', 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'id=?', whereArgs: [id]);
  }

  Future<TxRecord?> transactionById(int id) async {
    final db = await database;
    final rows = await db.query('transactions', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : TxRecord.fromMap(rows.first);
  }

  Future<void> setSplits(int transactionId, List<Map<String, Object?>> splits) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transaction_splits', where: 'transaction_id=?', whereArgs: [transactionId]);
      for (final s in splits) {
        await txn.insert('transaction_splits', {'transaction_id': transactionId, 'category': s['category'], 'amount': s['amount'], 'note': s['note'] ?? ''});
      }
      await txn.update('transactions', {'is_split_parent': splits.isEmpty ? 0 : 1}, where: 'id=?', whereArgs: [transactionId]);
    });
  }

  Future<List<Map<String, Object?>>> splitsFor(int transactionId) async {
    final db = await database;
    return db.query('transaction_splits', where: 'transaction_id=?', whereArgs: [transactionId], orderBy: 'id');
  }

  Future<Map<String, double>> monthTotalsByType() async {
    final range = _monthRange();
    return totalsByTypeForPeriod(range.$1, range.$2);
  }

  Future<Map<String, double>> monthExpenseByCategory() async {
    final range = _monthRange();
    return expenseByCategoryForPeriod(range.$1, range.$2);
  }

  Future<List<int>> availableYears() async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['occurred_at'], where: "review_status='accepted'");
    final years = <int>{DateTime.now().year};
    for (final row in rows) { final value = row['occurred_at']; if (value is num) years.add(DateTime.fromMillisecondsSinceEpoch(value.toInt()).year); }
    final result = years.toList()..sort((a, b) => b.compareTo(a));
    return result;
  }

  Future<Map<String, double>> totalsByTypeForPeriod(int startMs, int endMs) async {
    final db = await database;
    final rows = await db.rawQuery('SELECT type,COALESCE(SUM(amount),0) total FROM transactions WHERE review_status=\'accepted\' AND occurred_at>=? AND occurred_at<? GROUP BY type', [startMs, endMs]);
    return {for (final row in rows) row['type'] as String: (row['total'] as num).toDouble()};
  }

  Future<Map<String, double>> expenseByCategoryForPeriod(int startMs, int endMs) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT category, SUM(total) AS total FROM (
        SELECT t.category AS category, t.amount AS total
        FROM transactions t
        WHERE t.review_status='accepted' AND t.type='expense' AND t.occurred_at>=? AND t.occurred_at<?
          AND NOT EXISTS(SELECT 1 FROM transaction_splits s WHERE s.transaction_id=t.id)
        UNION ALL
        SELECT s.category AS category, s.amount AS total
        FROM transaction_splits s JOIN transactions t ON t.id=s.transaction_id
        WHERE t.review_status='accepted' AND t.type='expense' AND t.occurred_at>=? AND t.occurred_at<?
      ) GROUP BY category ORDER BY total DESC
    ''', [startMs, endMs, startMs, endMs]);
    return {for (final row in rows) row['category'] as String: (row['total'] as num).toDouble()};
  }

  Future<Map<String, double>> expenseByMerchantForPeriod(int startMs, int endMs, {int limit = 8}) async {
    final db = await database;
    final rows = await db.rawQuery("SELECT CASE WHEN normalized_merchant='' THEN merchant ELSE normalized_merchant END merchant,COALESCE(SUM(amount),0) total FROM transactions WHERE review_status='accepted' AND type='expense' AND occurred_at>=? AND occurred_at<? GROUP BY CASE WHEN normalized_merchant='' THEN merchant ELSE normalized_merchant END ORDER BY total DESC LIMIT ?", [startMs, endMs, limit]);
    return {for (final row in rows) row['merchant'] as String: (row['total'] as num).toDouble()};
  }

  Future<TxRecord?> largestExpenseForPeriod(int startMs, int endMs) async {
    final db = await database;
    final rows = await db.query('transactions', where: "review_status='accepted' AND type='expense' AND occurred_at>=? AND occurred_at<?", whereArgs: [startMs, endMs], orderBy: 'amount DESC', limit: 1);
    return rows.isEmpty ? null : TxRecord.fromMap(rows.first);
  }

  Future<List<double>> monthlyExpenseForYear(int year) async {
    final db = await database;
    final start = DateTime(year, 1, 1).millisecondsSinceEpoch;
    final end = DateTime(year + 1, 1, 1).millisecondsSinceEpoch;
    final rows = await db.query('transactions', columns: ['amount','occurred_at'], where: "review_status='accepted' AND type='expense' AND occurred_at>=? AND occurred_at<?", whereArgs: [start, end]);
    final totals = List<double>.filled(12, 0);
    for (final row in rows) { totals[DateTime.fromMillisecondsSinceEpoch((row['occurred_at'] as num).toInt()).month - 1] += (row['amount'] as num).toDouble(); }
    return totals;
  }

  Future<List<TxRecord>> searchTransactions({String query='', String type='all', String category='', String source='', String account='', double? minAmount, double? maxAmount, int? startMs, int? endMs, int limit=500}) async {
    final db = await database;
    final clauses = <String>["review_status='accepted'"];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) { clauses.add('(merchant LIKE ? OR normalized_merchant LIKE ? OR note LIKE ? OR raw_message LIKE ? OR sender LIKE ?)'); final q='%${query.trim()}%'; args.addAll([q,q,q,q,q]); }
    if (type != 'all') { clauses.add('type=?'); args.add(type); }
    if (category.isNotEmpty) { clauses.add('category=?'); args.add(category); }
    if (source.isNotEmpty) { clauses.add('source=?'); args.add(source); }
    if (account.isNotEmpty) { clauses.add('(account_hint=? OR sender||\'|\'||account_hint=?)'); args.addAll([account,account]); }
    if (minAmount != null) { clauses.add('amount>=?'); args.add(minAmount); }
    if (maxAmount != null) { clauses.add('amount<=?'); args.add(maxAmount); }
    if (startMs != null) { clauses.add('occurred_at>=?'); args.add(startMs); }
    if (endMs != null) { clauses.add('occurred_at<?'); args.add(endMs); }
    final rows = await db.query('transactions', where: clauses.join(' AND '), whereArgs: args, orderBy: 'occurred_at DESC', limit: limit);
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<Map<String, double>> cashFlowSummary() async {
    final now = DateTime.now();
    final range = _monthRange(now);
    final totals = await totalsByTypeForPeriod(range.$1, range.$2);
    final expense = totals['expense'] ?? 0;
    final income = totals['income'] ?? 0;
    final investment = totals['investment'] ?? 0;
    final refund = totals['refund'] ?? 0;

    // Transfers are intentionally excluded: moving money between the user's own
    // accounts is neither income nor spending. Investments are a real cash
    // outflow, but they are shown separately from day-to-day spending.
    final inflow = income + refund;
    final outflow = expense + investment;
    final net = inflow - outflow;
    final netExpense = math.max(0.0, expense - refund);

    final daysElapsed = math.max(1, now.day);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dailyAverage = expense / daysElapsed;
    final projected = dailyAverage * daysInMonth;

    // Treat investments as savings allocation rather than "spending" for this
    // percentage. This keeps the savings rate understandable and bounded.
    final savingsRate = income <= 0
        ? 0.0
        : (((income - netExpense) / income) * 100).clamp(-999.0, 100.0).toDouble();

    return {
      'income': income,
      'expense': expense,
      'investment': investment,
      'refund': refund,
      'inflow': inflow,
      'outflow': outflow,
      'net': net,
      'netExpense': netExpense,
      'dailyAverage': dailyAverage,
      'projectedExpense': projected,
      'savingsRate': savingsRate,
    };
  }

  Future<List<Map<String, Object?>>> detectRecurringPayments() async {
    if (!await getBoolSetting('recurring_detection_enabled', fallback: true)) return [];
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: "review_status='accepted' AND type IN ('expense','investment')",
      orderBy: 'occurred_at ASC',
    );

    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final normalized = (row['normalized_merchant'] as String?)?.trim() ?? '';
      final merchant = normalized.isNotEmpty ? normalized : (row['merchant'] as String? ?? '').trim();
      if (merchant.isEmpty) continue;
      final key = '${merchant.toLowerCase()}|${row['category']}|${row['type']}';
      groups.putIfAbsent(key, () => <Map<String, Object?>>[]).add(row);
    }

    bool hasRecurringHint(Map<String, Object?> row) {
      final text = '${row['raw_message'] ?? ''} ${row['note'] ?? ''}'.toLowerCase();
      const hints = [
        'subscription', 'autopay', 'auto-pay', 'auto debit', 'auto-debit',
        'standing instruction', 'recurring', 'monthly plan', 'monthly bill',
        'emi', 'sip', 'premium', 'membership', 'renewal',
      ];
      return hints.any(text.contains);
    }

    String? frequencyFor(int days) {
      if (days >= 5 && days <= 9) return 'Weekly';
      if (days >= 25 && days <= 35) return 'Monthly';
      if (days >= 80 && days <= 100) return 'Quarterly';
      if (days >= 350 && days <= 380) return 'Yearly';
      return null;
    }

    int targetFor(String frequency) => switch (frequency) {
          'Weekly' => 7,
          'Monthly' => 30,
          'Quarterly' => 91,
          'Yearly' => 365,
          _ => 30,
        };

    final out = <Map<String, Object?>>[];
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final original in groups.values) {
      // More recent history is more relevant and avoids old merchant behavior
      // dominating the current pattern.
      final g = original.length > 10 ? original.sublist(original.length - 10) : original;
      final explicit = g.any(hasRecurringHint);
      if (g.length < (explicit ? 2 : 3)) continue;

      final intervals = <int>[];
      for (var i = 1; i < g.length; i++) {
        final delta = (g[i]['occurred_at'] as num).toInt() - (g[i - 1]['occurred_at'] as num).toInt();
        final days = (delta / Duration.millisecondsPerDay).round();
        if (days > 0) intervals.add(days);
      }
      if (intervals.isEmpty) continue;

      final candidates = <String, List<int>>{};
      for (final d in intervals) {
        final f = frequencyFor(d);
        if (f != null) candidates.putIfAbsent(f, () => <int>[]).add(d);
      }
      if (candidates.isEmpty) continue;

      final ranked = candidates.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      final best = ranked.first;
      final requiredMatches = explicit && intervals.length == 1
          ? 1
          : math.max(2, (intervals.length * 0.67).ceil());
      if (best.value.length < requiredMatches) continue;

      final matchedIntervals = [...best.value]..sort();
      final intervalDays = matchedIntervals[matchedIntervals.length ~/ 2];
      final target = targetFor(best.key);
      final intervalError = matchedIntervals
              .map((d) => (d - target).abs() / target)
              .fold<double>(0, (a, b) => a + b) /
          matchedIntervals.length;

      final amounts = g.map((e) => (e['amount'] as num).toDouble()).toList()..sort();
      final medianAmount = amounts[amounts.length ~/ 2];
      if (medianAmount <= 0) continue;
      final avgAmount = amounts.fold<double>(0, (a, b) => a + b) / amounts.length;
      final avgDeviation = amounts
              .map((a) => (a - medianAmount).abs() / medianAmount)
              .fold<double>(0, (a, b) => a + b) /
          amounts.length;

      final last = g.last;
      final variableBill = ['bills', 'utilities', 'electricity', 'mobile', 'broadband']
          .any((x) => '${last['category']}'.toLowerCase().contains(x));
      final allowedAmountVariation = variableBill ? 0.40 : (explicit ? 0.25 : 0.18);
      if (avgDeviation > allowedAmountVariation) continue;

      final occurrenceScore = (g.length / 5.0).clamp(0.0, 1.0);
      final intervalScore = (1.0 - intervalError).clamp(0.0, 1.0);
      final amountScore = (1.0 - (avgDeviation / math.max(0.01, allowedAmountVariation))).clamp(0.0, 1.0);
      final confidence = (0.40 * intervalScore + 0.30 * amountScore + 0.20 * occurrenceScore + (explicit ? 0.10 : 0.0))
          .clamp(0.0, 0.99)
          .toDouble();
      if (confidence < 0.70) continue;

      var nextDue = (last['occurred_at'] as num).toInt() + intervalDays * Duration.millisecondsPerDay;
      // If the pattern has missed a cycle, advance to the next plausible future
      // occurrence rather than showing a permanently overdue date.
      while (nextDue < nowMs - 2 * Duration.millisecondsPerDay) {
        nextDue += intervalDays * Duration.millisecondsPerDay;
      }

      final normalized = (last['normalized_merchant'] as String?)?.trim() ?? '';
      out.add({
        'merchant': normalized.isNotEmpty ? normalized : last['merchant'],
        'category': last['category'],
        'type': last['type'],
        'averageAmount': avgAmount,
        'intervalDays': intervalDays,
        'frequency': best.key,
        'nextDue': nextDue,
        'occurrences': g.length,
        'confidence': confidence,
        'amountVariationPct': avgDeviation * 100,
        'explicitHint': explicit,
      });
    }

    out.sort((a, b) => (a['nextDue'] as int).compareTo(b['nextDue'] as int));
    return out;
  }

  Future<List<Map<String,Object?>>> smartInsights() async {
    final db = await database;
    final now = DateTime.now();
    final startThisWeek = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final startHistory = now.subtract(const Duration(days: 35)).millisecondsSinceEpoch;
    final categories = await expenseCategories();
    final out = <Map<String,Object?>>[];
    for (final c in categories) {
      final current = Sqflite.firstIntValue(await db.rawQuery("SELECT CAST(COALESCE(SUM(amount),0) AS INTEGER) FROM transactions WHERE review_status='accepted' AND type='expense' AND category=? AND occurred_at>=?", [c.name,startThisWeek]))?.toDouble() ?? 0;
      final previous = Sqflite.firstIntValue(await db.rawQuery("SELECT CAST(COALESCE(SUM(amount),0) AS INTEGER) FROM transactions WHERE review_status='accepted' AND type='expense' AND category=? AND occurred_at>=? AND occurred_at<?", [c.name,startHistory,startThisWeek]))?.toDouble() ?? 0;
      final weeklyAvg = previous/4;
      if (current >= 500 && weeklyAvg > 0 && current > weeklyAvg*1.4) {
        out.add({'kind':'anomaly','title':'${c.name} spending is unusually high','message':'Last 7 days are ${((current/weeklyAvg-1)*100).round()}% above your recent weekly average.','value':current});
      }
    }
    final budget = await overallBudget();
    final cash = await cashFlowSummary();
    final projected = cash['projectedExpense'] ?? 0;
    if (budget > 0 && projected > budget) out.add({'kind':'forecast','title':'Budget may be exceeded','message':'At the current pace, spending may reach ₹${projected.round()} vs ₹${budget.round()} budget.','value':projected-budget});
    final recurring = await detectRecurringPayments();
    final sevenDays = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
    for (final r in recurring.where((e)=>(e['nextDue'] as int)<=sevenDays).take(3)) {
      out.add({'kind':'recurring','title':'Upcoming ${r['merchant']}','message':'Around ₹${(r['averageAmount'] as double).round()} expected in the next 7 days.','value':r['averageAmount']});
    }
    return out;
  }

  Future<int> normalizeExistingMerchants() async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['id','merchant']);
    var changed=0;
    for (final r in rows) {
      final normalized = await normalizedMerchant(r['merchant'] as String);
      changed += await db.update('transactions', {'normalized_merchant': normalized}, where:'id=? AND normalized_merchant<>?', whereArgs:[r['id'],normalized]);
    }
    return changed;
  }

  Future<List<Map<String,Object?>>> merchantAliases() async {
    final db=await database; return db.query('merchant_aliases', orderBy:'normalized_name COLLATE NOCASE');
  }
  Future<void> saveMerchantAlias(String pattern,String normalized) async {
    final db=await database; await db.insert('merchant_aliases', {'pattern':pattern.trim().toLowerCase(),'normalized_name':normalized.trim()}, conflictAlgorithm:ConflictAlgorithm.replace); await normalizeExistingMerchants();
  }
  Future<void> deleteMerchantAlias(int id) async { final db=await database; await db.delete('merchant_aliases',where:'id=?',whereArgs:[id]); }

  Future<int> syncAccountsFromTransactions() async {
    final db=await database;
    final rows=await db.rawQuery("SELECT sender,account_hint,MAX(occurred_at) last_seen FROM transactions WHERE review_status='accepted' AND account_hint<>'' GROUP BY sender,account_hint");
    var count=0;
    for(final r in rows){
      final sender=(r['sender'] as String?)??''; final hint=(r['account_hint'] as String?)??''; final key='$sender|$hint';
      final name='${sender.isEmpty?'Account':sender} ••••$hint';
      count += await db.insert('accounts', {'account_key':key,'account_hint':hint,'sender':sender,'name':name,'institution':sender,'current_balance':0.0,'include_net_worth':0,'last_seen':r['last_seen']??0}, conflictAlgorithm:ConflictAlgorithm.ignore);
      await db.update('accounts', {'last_seen':r['last_seen']??0}, where:'account_key=?',whereArgs:[key]);
    }
    return count;
  }

  Future<List<Map<String,Object?>>> accounts() async { await syncAccountsFromTransactions(); final db=await database; return db.query('accounts',orderBy:'last_seen DESC,name'); }
  Future<void> updateAccount(int id,{required String name,required double balance,required bool includeNetWorth}) async { final db=await database; await db.update('accounts',{'name':name,'current_balance':balance,'include_net_worth':includeNetWorth?1:0},where:'id=?',whereArgs:[id]); }
  Future<Map<String,Map<String,double>>> spendByAccount() async {
    final db=await database;
    final rows=await db.rawQuery("SELECT sender||'|'||account_hint account_key,type,COALESCE(SUM(amount),0) total FROM transactions WHERE review_status='accepted' AND account_hint<>'' GROUP BY sender,account_hint,type");
    final out=<String,Map<String,double>>{};
    for(final r in rows){final key=r['account_key'] as String;out.putIfAbsent(key,()=>{'expense':0,'income':0,'investment':0,'transfer':0});out[key]![r['type'] as String]=(r['total'] as num).toDouble();}
    return out;
  }

  Future<int> matchTransfers() async {
    if (!await getBoolSetting('smart_transfer_matching',fallback:true)) return 0;
    final db=await database;
    final rows=await db.query('transactions',where:"review_status='accepted' AND transfer_group_id='' AND account_hint<>'' AND type IN ('expense','income')",orderBy:'occurred_at ASC');
    final used=<int>{}; var matched=0;
    for(var i=0;i<rows.length;i++){
      final a=rows[i]; final aid=a['id'] as int; if(used.contains(aid)) continue;
      for(var j=i+1;j<rows.length;j++){
        final b=rows[j]; final bid=b['id'] as int; if(used.contains(bid)) continue;
        if(a['type']==b['type']) continue;
        final diff=((a['occurred_at'] as int)-(b['occurred_at'] as int)).abs(); if(diff>12*60*60*1000) { if((b['occurred_at'] as int)>(a['occurred_at'] as int)) break; continue; }
        if(((a['amount'] as num).toDouble()-(b['amount'] as num).toDouble()).abs()>0.01) continue;
        if(a['account_hint']==b['account_hint']) continue;
        final gid='tr-${math.min(aid,bid)}-${math.max(aid,bid)}';
        await db.update('transactions',{'type':'transfer','category':'Transfer','transfer_group_id':gid,'classification_method':'smart_transfer'},where:'id IN (?,?)',whereArgs:[aid,bid]);
        used.addAll([aid,bid]); matched++; break;
      }
    }
    return matched;
  }

  Future<Map<String,int>> smartDeduplicate() async {
    if (!await getBoolSetting('smart_dedup_enabled', fallback: true)) return {'ignored': 0, 'kept': 0};
    final db=await database;
    final rows=await db.query('transactions',where:"review_status='accepted'",orderBy:'occurred_at ASC');
    var removed=0; final keep=<int>[];
    for(final r in rows){
      final id=r['id'] as int; bool duplicate=false;
      for(final kid in keep.reversed.take(50)){
        final k=rows.firstWhere((x)=>x['id']==kid);
        final diff=((r['occurred_at'] as int)-(k['occurred_at'] as int)).abs(); if(diff>5*60*1000) continue;
        if(((r['amount'] as num).toDouble()-(k['amount'] as num).toDouble()).abs()>0.01) continue;
        final ref=(r['upi_reference'] as String?)??''; final kref=(k['upi_reference'] as String?)??'';
        final rm=((r['normalized_merchant'] as String?)?.isNotEmpty==true?r['normalized_merchant']:r['merchant']).toString().toLowerCase();
        final km=((k['normalized_merchant'] as String?)?.isNotEmpty==true?k['normalized_merchant']:k['merchant']).toString().toLowerCase();
        if((ref.isNotEmpty && ref==kref) || (rm==km && r['source']!=k['source'])) { duplicate=true; break; }
      }
      if(duplicate){ await db.update('transactions',{'review_status':'ignored','dedup_cluster':'smart-duplicate'},where:'id=?',whereArgs:[id]); removed++; } else { keep.add(id); }
    }
    return {'ignored':removed,'kept':keep.length};
  }

  Future<Map<String,int>> modelFeedbackStats() async {
    final db=await database;
    final total=Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM transactions WHERE source IN ('sms','phonepe_notification')"))??0;
    final corrected=Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM review_feedback WHERE action='corrected'"))??0;
    final accepted=Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM review_feedback WHERE action='accepted'"))??0;
    final ignored=Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM review_feedback WHERE action='ignored'"))??0;
    final pending=Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM transactions WHERE review_status='needs_review'"))??0;
    return {'auto':total,'corrected':corrected,'accepted':accepted,'ignored':ignored,'pending':pending};
  }

  Future<List<MerchantRule>> rules() async { final db=await database; final rows=await db.query('rules',orderBy:'is_user_rule DESC,merchant COLLATE NOCASE'); return rows.map(MerchantRule.fromMap).toList(); }
  Future<void> saveRule(MerchantRule rule) async { final db=await database; final values={'merchant':rule.merchant.trim(),'keyword':rule.keyword.trim().toLowerCase(),'type':rule.type,'category':rule.category,'is_user_rule':rule.isUserRule?1:0,'enabled':rule.enabled?1:0,'created_at':DateTime.now().millisecondsSinceEpoch}; if(rule.id==null){await db.insert('rules',values);}else{await db.update('rules',values,where:'id=?',whereArgs:[rule.id]);} }
  Future<void> toggleRule(int id,bool enabled) async { final db=await database; await db.update('rules',{'enabled':enabled?1:0},where:'id=?',whereArgs:[id]); }
  Future<void> deleteRule(int id) async { final db=await database; await db.delete('rules',where:'id=? AND is_user_rule=1',whereArgs:[id]); }

  Future<List<CategoryRecord>> categories() async { final db=await database; final rows=await db.query('categories',orderBy:'name COLLATE NOCASE'); return rows.map(CategoryRecord.fromMap).toList(); }
  Future<List<CategoryRecord>> expenseCategories() async => (await categories()).where((c)=>c.kind=='expense').toList();
  Future<void> addCategory(String name,String kind) async { final db=await database; await db.insert('categories',{'name':name.trim(),'kind':kind,'is_system':0,'created_at':DateTime.now().millisecondsSinceEpoch},conflictAlgorithm:ConflictAlgorithm.ignore); }
  Future<void> deleteCategory(String name) async { final db=await database; await db.delete('categories',where:'name=? AND is_system=0',whereArgs:[name]); }

  Future<List<BudgetRecord>> budgets() async { final db=await database; final rows=await db.query('budgets',orderBy:'category'); return rows.map(BudgetRecord.fromMap).toList(); }
  Future<double> overallBudget() async { final db=await database; final rows=await db.query('budgets',columns:['amount'],where:'category=?',whereArgs:['__overall__'],limit:1); return rows.isEmpty?0:(rows.first['amount'] as num).toDouble(); }
  Future<void> setBudget(String category,double amount) async { final db=await database; await db.insert('budgets',{'category':category,'amount':amount,'period':'monthly'},conflictAlgorithm:ConflictAlgorithm.replace); }
  Future<void> deleteBudget(String category) async { if(category=='__overall__')return; final db=await database; await db.delete('budgets',where:'category=?',whereArgs:[category]); }

  Future<List<Map<String,Object?>>> netWorthItems() async { final db=await database; return db.query('net_worth_items',orderBy:'item_type,name'); }
  Future<void> saveNetWorthItem({int? id,required String name,required String itemType,required String category,required double balance}) async { final db=await database; final values={'name':name,'item_type':itemType,'category':category,'balance':balance,'updated_at':DateTime.now().millisecondsSinceEpoch}; if(id==null){await db.insert('net_worth_items',values);}else{await db.update('net_worth_items',values,where:'id=?',whereArgs:[id]);} }
  Future<void> deleteNetWorthItem(int id) async { final db=await database; await db.delete('net_worth_items',where:'id=?',whereArgs:[id]); }
  Future<Map<String,double>> netWorthSummary() async { final db=await database; final rows=await db.rawQuery("SELECT item_type,COALESCE(SUM(balance),0) total FROM net_worth_items GROUP BY item_type"); double assets=0,liabilities=0; for(final r in rows){if(r['item_type']=='asset')assets=(r['total'] as num).toDouble();else liabilities=(r['total'] as num).toDouble();} return {'assets':assets,'liabilities':liabilities,'netWorth':assets-liabilities}; }

  Future<Map<String,Object?>> exportSnapshot() async {
    final db=await database;
    const tables=['transactions','rules','budgets','settings','categories','transaction_splits','accounts','merchant_aliases','review_feedback','net_worth_items'];
    final data=<String,Object?>{'schema':6,'exportedAt':DateTime.now().toIso8601String()};
    for(final table in tables){data[table]=await db.query(table);}
    return data;
  }

  Future<void> restoreSnapshot(Map<String,Object?> snapshot) async {
    final db=await database;
    const tables=['transaction_splits','review_feedback','transactions','rules','budgets','settings','categories','accounts','merchant_aliases','net_worth_items'];
    await db.transaction((txn) async {
      for(final table in tables){await txn.delete(table);}
      final insertionOrder=['categories','settings','budgets','rules','merchant_aliases','accounts','net_worth_items','transactions','transaction_splits','review_feedback'];
      for(final table in insertionOrder){
        final rows=(snapshot[table] as List?)?.cast<Map>()??const[];
        for(final raw in rows){await txn.insert(table,Map<String,Object?>.from(raw),conflictAlgorithm:ConflictAlgorithm.replace);}
      }
    });
    await _seed(db);
  }

  Future<String> getSetting(String key,{String fallback=''}) async { final db=await database; final rows=await db.query('settings',columns:['value'],where:'key=?',whereArgs:[key],limit:1); return rows.isEmpty?fallback:rows.first['value'] as String; }
  Future<bool> getBoolSetting(String key,{bool fallback=false}) async => (await getSetting(key,fallback:fallback?'1':'0'))=='1';
  Future<void> setSetting(String key,String value) async { final db=await database; await db.insert('settings',{'key':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace); }
}
