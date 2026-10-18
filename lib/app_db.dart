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
      version: 7,
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
    await db.execute('''CREATE TABLE IF NOT EXISTS recurring_rules(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      merchant_key TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL,
      category TEXT NOT NULL,
      frequency TEXT NOT NULL DEFAULT 'Monthly',
      enabled INTEGER NOT NULL DEFAULT 1,
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
    await db.execute('''CREATE TABLE IF NOT EXISTS payment_cards(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      issuer TEXT NOT NULL DEFAULT '',
      last_four TEXT NOT NULL DEFAULT '',
      card_type TEXT NOT NULL DEFAULT 'credit',
      credit_limit REAL NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS card_ledger_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      card_id INTEGER NOT NULL,
      transaction_id INTEGER,
      entry_type TEXT NOT NULL,
      amount REAL NOT NULL,
      merchant TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      occurred_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(card_id) REFERENCES payment_cards(id) ON DELETE CASCADE,
      FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE SET NULL,
      UNIQUE(card_id, transaction_id)
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_time ON transactions(occurred_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_amount ON transactions(amount)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_review ON transactions(review_status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_normalized_merchant ON transactions(normalized_merchant)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_card_ledger_card_time ON card_ledger_entries(card_id, occurred_at)');
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

  Future<List<PaymentCardRecord>> paymentCards() async {
    final db = await database;
    final rows = await db.query('payment_cards', orderBy: 'created_at DESC');
    return rows.map(PaymentCardRecord.fromMap).toList();
  }

  Future<int> addPaymentCard({required String name, required String issuer, required String lastFour, required String cardType, required double creditLimit}) async {
    final db = await database;
    return db.insert('payment_cards', {
      'name': name.trim(), 'issuer': issuer.trim(), 'last_four': lastFour.replaceAll(RegExp(r'\D'), '').trim(),
      'card_type': cardType, 'credit_limit': creditLimit, 'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deletePaymentCard(int id) async {
    final db = await database;
    await db.delete('payment_cards', where: 'id=?', whereArgs: [id]);
  }

  Future<void> addCardLedgerEntry({required int cardId, int? transactionId, required String entryType, required double amount, required int occurredAt, required String merchant, String note = ''}) async {
    final db = await database;
    await db.insert('card_ledger_entries', {
      'card_id': cardId, 'transaction_id': transactionId, 'entry_type': entryType, 'amount': amount,
      'merchant': merchant.trim(), 'note': note.trim(), 'occurred_at': occurredAt, 'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> markCardBillPaid({required int cardId, required double amount, required int occurredAt}) =>
      addCardLedgerEntry(cardId: cardId, entryType: 'payment', amount: amount, occurredAt: occurredAt, merchant: 'Credit card bill payment', note: 'Marked as paid');

  Future<List<CardLedgerEntry>> cardLedger(int cardId, {required int startMs, required int endMs}) async {
    final db = await database;
    final rows = await db.query('card_ledger_entries', where: 'card_id=? AND occurred_at>=? AND occurred_at<?', whereArgs: [cardId, startMs, endMs], orderBy: 'occurred_at DESC');
    return rows.map(CardLedgerEntry.fromMap).toList();
  }

  Future<Map<String, double>> cardTotals(int cardId, {int? startMs, int? endMs}) async {
    final db = await database;
    final clauses = <String>['card_id=?'];
    final args = <Object>[cardId];
    if (startMs != null) { clauses.add('occurred_at>=?'); args.add(startMs); }
    if (endMs != null) { clauses.add('occurred_at<?'); args.add(endMs); }
    final rows = await db.rawQuery('SELECT entry_type, COALESCE(SUM(amount),0) total FROM card_ledger_entries WHERE ${clauses.join(' AND ')} GROUP BY entry_type', args);
    return {for (final row in rows) row['entry_type'] as String: (row['total'] as num).toDouble()};
  }

  /// Linked SMS entries keep their classified merchant/category. Manual entries
  /// are still represented, under a clear fallback label.
  Future<List<Map<String, Object?>>> cardSpendByCategory(int cardId, {required int startMs, required int endMs}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT COALESCE(NULLIF(t.category, ''), 'Other card spending') AS label, SUM(l.amount) AS total
      FROM card_ledger_entries l LEFT JOIN transactions t ON t.id=l.transaction_id
      WHERE l.card_id=? AND l.entry_type='purchase' AND l.occurred_at>=? AND l.occurred_at<?
      GROUP BY COALESCE(NULLIF(t.category, ''), 'Other card spending')
      ORDER BY total DESC LIMIT 6
    ''', [cardId, startMs, endMs]);
  }

  Future<List<Map<String, Object?>>> cardSpendByMerchant(int cardId, {required int startMs, required int endMs}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT COALESCE(NULLIF(l.merchant, ''), NULLIF(t.normalized_merchant, ''), NULLIF(t.merchant, ''), 'Unidentified merchant') AS label, SUM(l.amount) AS total
      FROM card_ledger_entries l LEFT JOIN transactions t ON t.id=l.transaction_id
      WHERE l.card_id=? AND l.entry_type='purchase' AND l.occurred_at>=? AND l.occurred_at<?
      GROUP BY COALESCE(NULLIF(l.merchant, ''), NULLIF(t.normalized_merchant, ''), NULLIF(t.merchant, ''), 'Unidentified merchant')
      ORDER BY total DESC LIMIT 6
    ''', [cardId, startMs, endMs]);
  }

  Future<List<Map<String, Object?>>> cardMonthlySpend(int cardId, int selectedYear) async {
    final db = await database;
    final start = DateTime(selectedYear, 1, 1).millisecondsSinceEpoch;
    final end = DateTime(selectedYear + 1, 1, 1).millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT CAST(strftime('%m', occurred_at / 1000, 'unixepoch', 'localtime') AS INTEGER) AS month, SUM(amount) AS total
      FROM card_ledger_entries WHERE card_id=? AND entry_type='purchase' AND occurred_at>=? AND occurred_at<?
      GROUP BY month ORDER BY month
    ''', [cardId, start, end]);
    final values = <int, double>{for (final row in rows) (row['month'] as num).toInt(): (row['total'] as num).toDouble()};
    return List.generate(12, (index) => {'label': 'M${index + 1}', 'total': values[index + 1] ?? 0});
  }

  /// Link accepted SMS/notification transactions when their text includes a
  /// user-supplied card last four digits. Bill-payment wording becomes a
  /// settlement entry, avoiding duplicate expense counting.
  Future<void> autoLinkCardTransactions() async {
    final cards = await paymentCards();
    final db = await database;
    for (final card in cards) {
      if (card.id == null || card.lastFour.length != 4) continue;
      final rows = await db.query('transactions', where: "review_status='accepted' AND (raw_message LIKE ? OR payment_method LIKE ? OR account_hint LIKE ?)", whereArgs: ['%${card.lastFour}%', '%${card.lastFour}%', '%${card.lastFour}%']);
      for (final row in rows) {
        final tx = TxRecord.fromMap(row);
        final text = '${tx.rawMessage} ${tx.paymentMethod} ${tx.merchant}'.toLowerCase();
        final isBillPayment = RegExp(r'credit\s*card\s*bill|card\s*bill\s*payment|cc\s*payment|card\s*payment').hasMatch(text);
        final type = isBillPayment ? 'payment' : 'purchase';
        await addCardLedgerEntry(cardId: card.id!, transactionId: tx.id, entryType: type, amount: tx.amount, occurredAt: tx.occurredAt, merchant: tx.merchant, note: isBillPayment ? 'Auto-linked bill payment' : 'Auto-linked card transaction');
      }
    }
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

  bool _unsafeBroadRule(String keyword) {
    final value = keyword.toLowerCase().trim();
    if (value.contains('&&')) return false;
    const generic = {
      'icici', 'icici bank', 'hdfc', 'hdfc bank', 'axis', 'axis bank', 'sbi', 'state bank',
      'kotak', 'kotak bank', 'yes bank', 'idfc', 'idfc bank', 'indusind', 'bank',
      'phonepe', 'google pay', 'gpay', 'paytm', 'upi payment', 'unknown',
    };
    const bankTokens = ['icici', 'hdfc bank', 'axis bank', 'state bank', 'sbi', 'kotak bank', 'yes bank', 'idfc bank', 'indusind'];
    const semantic = ['mutual fund', 'sip', 'gold', 'subscription', 'autopay', 'emi', 'loan', 'insurance', 'refund'];
    final bankOnly = bankTokens.any(value.contains) && !semantic.any(value.contains);
    return generic.contains(value) || bankOnly || RegExp(r'^(?:ad|ax|vm|bk|jm|vk|bp)-[a-z0-9-]+$', caseSensitive: false).hasMatch(value);
  }

  String _ruleText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9@& ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> _correctionPatternParts(TxRecord tx) {
    final raw = _ruleText(tx.rawMessage);
    final parts = <String>[];

    // Prefer the actual purpose/payee embedded in the message. Bank/sender names
    // are transport context, not the semantic identity of a transaction.
    final purposeMatchers = <RegExp>[
      RegExp(r'\btowards\s+([a-z0-9@.& _-]{2,45}?)(?=\s+(?:for|on|via|ref|retrieval|using|from)\b|$)', caseSensitive: false),
      RegExp(r'\bpaid\s+to\s+([a-z0-9@.& _-]{2,45}?)(?=\s+(?:on|via|ref|using|from)\b|$)', caseSensitive: false),
      RegExp(r'\bsent\s+to\s+([a-z0-9@.& _-]{2,45}?)(?=\s+(?:on|via|ref|using|from)\b|$)', caseSensitive: false),
      RegExp(r'\bto\s+([a-z0-9@.& _-]{2,35}?)(?=\s+(?:via|on|ref|using)\b|$)', caseSensitive: false),
    ];
    for (final matcher in purposeMatchers) {
      final match = matcher.firstMatch(raw);
      if (match != null) {
        var value = _ruleText(match.group(1) ?? '');
        value = value.replaceAll(RegExp(r'\b(?:bank|ltd|limited|pvt|private)\b'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (value.length >= 3 && !_unsafeBroadRule(value)) {
          parts.add(value);
          break;
        }
      }
    }

    const contexts = <String>[
      'subscription', 'autopay', 'auto pay', 'sip', 'mutual fund', 'gold', 'emi', 'loan',
      'insurance', 'premium', 'electricity', 'recharge', 'rent', 'credit card', 'google',
      'netflix', 'spotify', 'zerodha', 'groww', 'zomato', 'swiggy', 'refund', 'reversal',
    ];
    for (final context in contexts) {
      if (raw.contains(context) && !parts.contains(context)) parts.add(context);
      if (parts.length >= 4) break;
    }

    if (parts.isEmpty) {
      final normalized = _ruleText(tx.normalizedMerchant.trim().isNotEmpty ? tx.normalizedMerchant : tx.merchant);
      if (normalized.length >= 3 && !_unsafeBroadRule(normalized)) parts.add(normalized);
    }
    return parts.toSet().take(4).toList();
  }

  String _correctionPattern(TxRecord tx) => _correctionPatternParts(tx).join('&&');

  bool _matchesPatternText(String rawMessage, String merchant, String normalizedMerchantValue, String pattern) {
    final parts = pattern.split('&&').map(_ruleText).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    final haystack = _ruleText('$rawMessage $merchant $normalizedMerchantValue');
    return parts.every(haystack.contains);
  }

  Future<int> cleanupUnsafeBroadUserRules() async {
    final db = await database;
    final rows = await db.query('rules', columns: ['id', 'keyword'], where: 'is_user_rule=1');
    var removed = 0;
    for (final row in rows) {
      final keyword = '${row['keyword'] ?? ''}'.trim();
      if (_unsafeBroadRule(keyword)) {
        removed += await db.delete('rules', where: 'id=?', whereArgs: [row['id']]);
      }
    }
    return removed;
  }

  Future<void> updateTransaction(int id, {required String type, required String category, required String merchant, required String note, bool learnRule = true}) async {
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

    final learn = learnRule && before != null && await getBoolSetting('learn_from_corrections', fallback: true);
    if (learn) {
      final pattern = _correctionPattern(before);
      if (pattern.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final existing = await db.query('rules', columns: ['id'], where: 'keyword=? AND is_user_rule=1', whereArgs: [pattern], limit: 1);
        final values = {'merchant': normalized, 'keyword': pattern, 'type': type, 'category': category, 'is_user_rule': 1, 'enabled': 1, 'created_at': now};
        if (existing.isEmpty) { await db.insert('rules', values); } else { await db.update('rules', values, where: 'id=?', whereArgs: [existing.first['id']]); }
      }
    }
  }

  Future<int> countSimilarTransactions(TxRecord source) async {
    if (source.id == null) return 0;
    final pattern = _correctionPattern(source);
    if (pattern.isEmpty) return 0;
    final db = await database;
    final rows = await db.query(
      'transactions',
      columns: ['id', 'raw_message', 'merchant', 'normalized_merchant'],
      where: "review_status IN ('accepted','needs_review') AND id<>? AND source IN ('sms','phonepe_notification')",
      whereArgs: [source.id],
      limit: 5000,
    );
    return rows.where((row) => _matchesPatternText(
      '${row['raw_message'] ?? ''}', '${row['merchant'] ?? ''}', '${row['normalized_merchant'] ?? ''}', pattern,
    )).length;
  }

  Future<int> applyCorrectionToSimilar({
    required TxRecord source,
    required String type,
    required String category,
    required String merchant,
  }) async {
    if (source.id == null) return 0;
    final db = await database;
    final pattern = _correctionPattern(source);
    if (pattern.isEmpty) return 0;
    final normalized = await normalizedMerchant(merchant);
    final rows = await db.query(
      'transactions',
      columns: ['id', 'raw_message', 'merchant', 'normalized_merchant'],
      where: "review_status IN ('accepted','needs_review') AND id<>? AND source IN ('sms','phonepe_notification')",
      whereArgs: [source.id],
      limit: 5000,
    );
    var changed = 0;
    for (final row in rows) {
      if (!_matchesPatternText('${row['raw_message'] ?? ''}', '${row['merchant'] ?? ''}', '${row['normalized_merchant'] ?? ''}', pattern)) continue;
      changed += await db.update(
        'transactions',
        {
          'type': type,
          'category': category,
          'merchant': merchant.trim().isEmpty ? '${row['merchant'] ?? ''}' : merchant.trim(),
          'normalized_merchant': normalized,
          'classification_method': 'user_pattern_rule',
          'classification_confidence': 1.0,
          'review_status': 'accepted',
        },
        where: 'id=?',
        whereArgs: [row['id']],
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query('rules', columns: ['id'], where: 'keyword=? AND is_user_rule=1', whereArgs: [pattern], limit: 1);
    final values = {
      'merchant': normalized,
      'keyword': pattern,
      'type': type,
      'category': category,
      'is_user_rule': 1,
      'enabled': 1,
      'created_at': now,
    };
    if (existing.isEmpty) {
      await db.insert('rules', values);
    } else {
      await db.update('rules', values, where: 'id=?', whereArgs: [existing.first['id']]);
    }
    return changed;
  }

  Future<List<Map<String, Object?>>> recurringRules() async {
    final db = await database;
    return db.query('recurring_rules', where: 'enabled=1', orderBy: 'name COLLATE NOCASE');
  }

  Future<void> saveRecurringRuleFromTransaction(TxRecord tx, {String frequency = 'Monthly'}) async {
    final db = await database;
    final normalized = tx.normalizedMerchant.trim().isNotEmpty
        ? tx.normalizedMerchant.trim()
        : await normalizedMerchant(tx.merchant);
    final key = normalized.toLowerCase().trim();
    if (key.length < 2) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'recurring_rules',
      {
        'name': normalized,
        'merchant_key': key,
        'type': tx.type,
        'category': tx.category,
        'frequency': frequency,
        'enabled': 1,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRecurringRule(int id) async {
    final db = await database;
    await db.delete('recurring_rules', where: 'id=?', whereArgs: [id]);
  }

  int _recurringNextDue(int lastMs, String frequency) {
    DateTime advance(DateTime value) => switch (frequency.toLowerCase()) {
          'weekly' => value.add(const Duration(days: 7)),
          'quarterly' => DateTime(value.year, value.month + 3, value.day),
          'yearly' => DateTime(value.year + 1, value.month, value.day),
          _ => DateTime(value.year, value.month + 1, value.day),
        };
    var next = advance(DateTime.fromMillisecondsSinceEpoch(lastMs));
    final today = DateTime.now().subtract(const Duration(days: 1));
    while (next.isBefore(today)) {
      next = advance(next);
    }
    return next.millisecondsSinceEpoch;
  }

  Future<List<Map<String, Object?>>> userRecurringSummaries() async {
    final db = await database;
    final rules = await recurringRules();
    final out = <Map<String, Object?>>[];
    for (final rule in rules) {
      final key = '${rule['merchant_key'] ?? ''}'.toLowerCase();
      final rows = await db.query(
        'transactions',
        where: "review_status='accepted' AND (LOWER(normalized_merchant)=? OR LOWER(merchant)=?) AND type=?",
        whereArgs: [key, key, rule['type']],
        orderBy: 'occurred_at DESC',
        limit: 24,
      );
      if (rows.isEmpty) {
        out.add({...rule, 'occurrences': 0, 'averageAmount': 0.0, 'lastPaid': 0, 'nextDue': 0});
        continue;
      }
      final amounts = rows.map((e) => (e['amount'] as num).toDouble()).toList();
      final avg = amounts.fold<double>(0, (a, b) => a + b) / amounts.length;
      final lastMs = (rows.first['occurred_at'] as num).toInt();
      out.add({
        ...rule,
        'occurrences': rows.length,
        'averageAmount': avg,
        'lastPaid': lastMs,
        'nextDue': _recurringNextDue(lastMs, '${rule['frequency'] ?? 'Monthly'}'),
      });
    }
    out.sort((a, b) => ((a['nextDue'] as num?)?.toInt() ?? 0).compareTo((b['nextDue'] as num?)?.toInt() ?? 0));
    return out;
  }

  Future<List<TxRecord>> recurringTransactionsForRule(Map<String, Object?> rule, {int limit = 200}) async {
    final db = await database;
    final key = '${rule['merchant_key'] ?? ''}'.toLowerCase();
    final rows = await db.query(
      'transactions',
      where: "review_status='accepted' AND (LOWER(normalized_merchant)=? OR LOWER(merchant)=?) AND type=?",
      whereArgs: [key, key, rule['type']],
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(TxRecord.fromMap).toList();
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

  /// Expense totals distributed across a requested number of visual buckets.
  /// It is deliberately based on the selected date range, so charts change
  /// whenever the user changes a home/report filter.
  Future<List<double>> expenseTrendForPeriod(int startMs, int endMs, {int buckets = 7}) async {
    final safeBuckets = math.max(1, buckets);
    final duration = math.max(1, endMs - startMs);
    final totals = List<double>.filled(safeBuckets, 0);
    final db = await database;
    final rows = await db.query(
      'transactions',
      columns: ['amount', 'occurred_at'],
      where: "review_status='accepted' AND type='expense' AND occurred_at>=? AND occurred_at<?",
      whereArgs: [startMs, endMs],
    );
    for (final row in rows) {
      final at = (row['occurred_at'] as num).toInt();
      final ratio = (at - startMs) / duration;
      final index = (ratio * safeBuckets).floor().clamp(0, safeBuckets - 1).toInt();
      totals[index] += (row['amount'] as num).toDouble();
    }
    return totals;
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

  Future<List<TxRecord>> searchTransactions({String query='', String type='all', String category='', String merchant='', String source='', String account='', double? minAmount, double? maxAmount, int? startMs, int? endMs, int limit=500}) async {
    final db = await database;
    final clauses = <String>["review_status='accepted'"];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) { clauses.add('(merchant LIKE ? OR normalized_merchant LIKE ? OR note LIKE ? OR raw_message LIKE ? OR sender LIKE ?)'); final q='%${query.trim()}%'; args.addAll([q,q,q,q,q]); }
    if (type != 'all') { clauses.add('type=?'); args.add(type); }
    if (category.isNotEmpty) { clauses.add('(category=? OR id IN (SELECT transaction_id FROM transaction_splits WHERE category=?))'); args.addAll([category, category]); }
    if (merchant.isNotEmpty) { clauses.add('(LOWER(normalized_merchant)=? OR LOWER(merchant)=?)'); final m=merchant.toLowerCase(); args.addAll([m,m]); }
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

  Future<Map<String, Object?>> safeToSpendSnapshot() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final monthEndDate = DateTime(now.year, now.month + 1, 1);
    final monthEnd = monthEndDate.millisecondsSinceEpoch;
    final totals = await totalsByTypeForPeriod(monthStart, monthEnd);
    final budget = await overallBudget();
    final expense = totals['expense'] ?? 0.0;
    final refund = totals['refund'] ?? 0.0;
    final income = totals['income'] ?? 0.0;
    final investment = totals['investment'] ?? 0.0;
    final netExpense = math.max(0.0, expense - refund);

    var upcomingBills = 0.0;
    final recurring = await userRecurringSummaries();
    for (final item in recurring) {
      final type = '${item['type'] ?? ''}';
      final nextDue = (item['nextDue'] as num?)?.toInt() ?? 0;
      final amount = (item['averageAmount'] as num?)?.toDouble() ?? 0.0;
      if (type == 'expense' && nextDue >= now.millisecondsSinceEpoch && nextDue < monthEnd) {
        upcomingBills += amount;
      }
    }

    final daysRemaining = math.max(1, monthEndDate.difference(DateTime(now.year, now.month, now.day)).inDays);
    final hasBudget = budget > 0;
    final hasIncome = income > 0;
    final basis = hasBudget ? budget : (income + refund);
    final safe = math.max(0.0, hasBudget ? (budget - netExpense - upcomingBills) : (basis - netExpense - investment - upcomingBills));
    final dailySafe = safe / daysRemaining;
    final mode = hasBudget ? 'budget' : (hasIncome ? 'cashflow' : 'insufficient');

    return {
      'safe': safe,
      'dailySafe': dailySafe,
      'budget': budget,
      'income': income,
      'expense': expense,
      'refund': refund,
      'investment': investment,
      'upcomingBills': upcomingBills,
      'daysRemaining': daysRemaining,
      'mode': mode,
    };
  }

  Future<List<String>> whatChangedInsights() async {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final currentEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final previousDate = DateTime(now.year, now.month - 1, 1);
    final previousStart = previousDate.millisecondsSinceEpoch;
    final previousLastDay = DateTime(previousDate.year, previousDate.month + 1, 0).day;
    final previousEndDay = math.min(now.day + 1, previousLastDay + 1).toInt();
    final previousEnd = DateTime(previousDate.year, previousDate.month, previousEndDay).millisecondsSinceEpoch;

    final currentTotals = await totalsByTypeForPeriod(currentStart, currentEnd);
    final previousTotals = await totalsByTypeForPeriod(previousStart, previousEnd);
    final currentExpense = currentTotals['expense'] ?? 0.0;
    final previousExpense = previousTotals['expense'] ?? 0.0;
    final insights = <String>[];

    if (previousExpense > 0) {
      final delta = currentExpense - previousExpense;
      final pct = (delta.abs() / previousExpense) * 100;
      if (pct >= 5) {
        insights.add(delta > 0
            ? 'Spending is ${pct.round()}% higher than last month (${_compactMoney(delta.abs())} more).'
            : 'Spending is ${pct.round()}% lower than last month (${_compactMoney(delta.abs())} less).');
      } else {
        insights.add('Overall spending is almost unchanged from last month.');
      }
    } else if (currentExpense > 0) {
      insights.add('This is your first month with enough spending history for comparison.');
    }

    final currentCategories = await expenseByCategoryForPeriod(currentStart, currentEnd);
    final previousCategories = await expenseByCategoryForPeriod(previousStart, previousEnd);
    if (currentCategories.isNotEmpty) {
      final top = currentCategories.entries.first;
      final before = previousCategories[top.key] ?? 0.0;
      final delta = top.value - before;
      if (before > 0 && delta.abs() >= 100) {
        insights.add('${top.key} is your top category at ${_compactMoney(top.value)}, ${delta > 0 ? 'up' : 'down'} ${_compactMoney(delta.abs())} vs last month.');
      } else {
        insights.add('${top.key} is your largest category this month at ${_compactMoney(top.value)}.');
      }
    }

    final merchants = await expenseByMerchantForPeriod(currentStart, currentEnd, limit: 1);
    if (merchants.isNotEmpty) {
      final top = merchants.entries.first;
      insights.add('${top.key} is your highest-spend merchant this month at ${_compactMoney(top.value)}.');
    }


    return insights.take(4).toList();
  }

  String _compactMoney(double value) {
    final abs = value.abs();
    if (abs >= 10000000) return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
    if (abs >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}K';
    return '₹${value.round()}';
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
        // Two unrelated payments can have the same amount on the same day.
        // Require a shared transaction reference or explicit self-transfer evidence.
        final refA = (a['upi_reference'] as String? ?? '').trim().toLowerCase();
        final refB = (b['upi_reference'] as String? ?? '').trim().toLowerCase();
        if (refA.isNotEmpty && refB.isNotEmpty && refA != refB) continue;
        final sameRef = refA.isNotEmpty && refA == refB;
        final messageA = '${a['raw_message'] ?? ''}'.toLowerCase();
        final messageB = '${b['raw_message'] ?? ''}'.toLowerCase();
        final explicitSelf = [messageA, messageB].any((message) =>
          message.contains('self transfer') ||
          message.contains('own account') ||
          message.contains('between your accounts') ||
          message.contains('internal transfer'));
        if (!sameRef && !explicitSelf) continue;
        if (diff > (sameRef ? 30 : 5) * 60 * 1000) continue;
        final gid='tr-${math.min(aid,bid)}-${math.max(aid,bid)}';
        await db.update('transactions',{'type':'transfer','category':'Transfer','transfer_group_id':gid,'classification_method':'smart_transfer'},where:'id IN (?,?)',whereArgs:[aid,bid]);
        used.addAll([aid,bid]); matched++; break;
      }
    }
    return matched;
  }

  Future<Map<String,int>> smartDeduplicate() async {
    if (!await getBoolSetting('smart_dedup_enabled', fallback: true)) return {'ignored': 0, 'kept': 0};
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: "review_status='accepted' AND (source='sms' OR source LIKE '%_notification')",
      orderBy: 'occurred_at ASC',
    );
    if (rows.length < 2) return {'ignored': 0, 'kept': rows.length};

    bool isNotificationSource(String source) => source.endsWith('_notification');
    bool userCorrected(Map<String, Object?> row) => row['classification_method'] == 'user_corrected';
    String textValue(Map<String, Object?> row, String key) => (row[key] as String?)?.trim() ?? '';
    double amountValue(Map<String, Object?> row) => (row['amount'] as num).toDouble();
    int timeValue(Map<String, Object?> row) => (row['occurred_at'] as num).toInt();

    bool upiLike(Map<String, Object?> row) {
      final text = '${textValue(row, 'payment_method')} ${textValue(row, 'raw_message')} ${textValue(row, 'merchant')}'.toLowerCase();
      return const ['upi', 'gpay', 'google pay', 'phonepe', 'paytm', '@ybl', '@ibl', '@ok', '@upi']
          .any(text.contains);
    }

    double classificationRank(Map<String, Object?> row) {
      final method = textValue(row, 'classification_method');
      final category = textValue(row, 'category');
      final confidence = ((row['classification_confidence'] as num?) ?? 0).toDouble().clamp(0.0, 1.0).toDouble();
      final base = switch (method) {
        'user_corrected' => 100.0,
        'notification_action' => 95.0,
        'upi_intent' => 90.0,
        'merchant_rule' => 85.0,
        'context_override' => 78.0,
        'hard_gate' => 75.0,
        'neural' => 65.0,
        _ => 50.0,
      };
      return base + (category.isNotEmpty && category.toLowerCase() != 'uncategorized' ? 20.0 : 0.0) + confidence;
    }

    int merchantScore(String merchant) {
      final m = merchant.trim();
      if (m.isEmpty) return -100;
      final lower = m.toLowerCase();
      var score = 20;
      if (const ['unknown', 'phonepe', 'google pay', 'gpay', 'paytm'].contains(lower)) score -= 25;
      if (RegExp(r'^(?:gpay|phonepe|paytm)[-_ ]?\d+', caseSensitive: false).hasMatch(m)) score -= 35;
      if (RegExp(r'\d{7,}').hasMatch(m)) score -= 12;
      if (RegExp(r'[A-Za-z]').allMatches(m).length >= 5) score += 10;
      if (m.contains(' ')) score += 5;
      return score;
    }

    bool pairQualifies(Map<String, Object?> a, Map<String, Object?> b) {
      if ((amountValue(a) - amountValue(b)).abs() > 0.01) return false;
      final sourceA = textValue(a, 'source');
      final sourceB = textValue(b, 'source');
      final crossSource = (sourceA == 'sms' && isNotificationSource(sourceB)) ||
          (sourceB == 'sms' && isNotificationSource(sourceA));
      if (!crossSource) return false;

      final diff = (timeValue(a) - timeValue(b)).abs();
      final refA = textValue(a, 'upi_reference');
      final refB = textValue(b, 'upi_reference');
      if (refA.isNotEmpty && refB.isNotEmpty) {
        if (refA.toLowerCase() != refB.toLowerCase()) return false;
        return diff <= 10 * 60 * 1000;
      }

      final accountA = textValue(a, 'account_hint');
      final accountB = textValue(b, 'account_hint');
      if (accountA.isNotEmpty && accountB.isNotEmpty && accountA != accountB) return false;

      if (!userCorrected(a) && !userCorrected(b) && textValue(a, 'type') != textValue(b, 'type')) return false;

      final merchantA = textValue(a, 'normalized_merchant').isNotEmpty
          ? textValue(a, 'normalized_merchant')
          : textValue(a, 'merchant');
      final merchantB = textValue(b, 'normalized_merchant').isNotEmpty
          ? textValue(b, 'normalized_merchant')
          : textValue(b, 'merchant');
      final merchantMatch = merchantA.isNotEmpty && merchantA.toLowerCase() == merchantB.toLowerCase();
      if (merchantMatch && diff <= 5 * 60 * 1000) return true;
      return upiLike(a) && upiLike(b) && diff <= 3 * 60 * 1000;
    }

    int pairScore(Map<String, Object?> a, Map<String, Object?> b) {
      final diff = (timeValue(a) - timeValue(b)).abs();
      final refA = textValue(a, 'upi_reference');
      final refB = textValue(b, 'upi_reference');
      if (refA.isNotEmpty && refB.isNotEmpty && refA.toLowerCase() == refB.toLowerCase()) return 1000000 - diff;
      final merchantA = textValue(a, 'normalized_merchant').isNotEmpty ? textValue(a, 'normalized_merchant') : textValue(a, 'merchant');
      final merchantB = textValue(b, 'normalized_merchant').isNotEmpty ? textValue(b, 'normalized_merchant') : textValue(b, 'merchant');
      if (merchantA.isNotEmpty && merchantA.toLowerCase() == merchantB.toLowerCase()) return 800000 - diff;
      return 600000 - diff;
    }

    final used = <int>{};
    var merged = 0;

    for (var i = 0; i < rows.length; i++) {
      final a = rows[i];
      final aid = (a['id'] as num).toInt();
      if (used.contains(aid)) continue;

      Map<String, Object?>? best;
      var bestScore = -1 << 62;
      for (var j = i + 1; j < rows.length; j++) {
        final b = rows[j];
        final bid = (b['id'] as num).toInt();
        if (used.contains(bid)) continue;
        final diff = (timeValue(a) - timeValue(b)).abs();
        if (diff > 10 * 60 * 1000 && timeValue(b) > timeValue(a)) break;
        if (!pairQualifies(a, b)) continue;
        final score = pairScore(a, b);
        if (score > bestScore) { best = b; bestScore = score; }
      }
      if (best == null) continue;

      final bid = (best['id'] as num).toInt();
      final sms = textValue(a, 'source') == 'sms' ? a : best;
      final notification = identical(sms, a) ? best : a;
      final smsId = (sms['id'] as num).toInt();
      final notificationId = (notification['id'] as num).toInt();

      final bestClassification = classificationRank(a) >= classificationRank(best) ? a : best;
      final merchantA = textValue(a, 'merchant');
      final merchantB = textValue(best, 'merchant');
      final smsMerchant = textValue(sms, 'merchant');
      final chosenMerchant = merchantScore(smsMerchant) >= 0
          ? smsMerchant
          : (merchantScore(merchantA) >= merchantScore(merchantB) ? merchantA : merchantB);
      final chosenNormalized = await normalizedMerchant(chosenMerchant);
      final cluster = 'cross-source-$smsId-$notificationId';

      final chosenPaymentMethod = textValue(a, 'payment_method').toLowerCase().contains('upi') ||
              textValue(best, 'payment_method').toLowerCase().contains('upi')
          ? 'UPI'
          : (textValue(sms, 'payment_method').isNotEmpty ? textValue(sms, 'payment_method') : textValue(notification, 'payment_method'));

      await db.update('transactions', {
        'type': textValue(bestClassification, 'type'),
        'category': textValue(bestClassification, 'category'),
        'merchant': chosenMerchant,
        'normalized_merchant': chosenNormalized,
        'note': textValue(sms, 'note').isNotEmpty ? textValue(sms, 'note') : textValue(notification, 'note'),
        'source': 'sms',
        'raw_message': textValue(sms, 'raw_message'),
        'sender': textValue(sms, 'sender'),
        'payment_method': chosenPaymentMethod,
        'account_hint': textValue(sms, 'account_hint').isNotEmpty ? textValue(sms, 'account_hint') : textValue(notification, 'account_hint'),
        'upi_reference': textValue(sms, 'upi_reference').isNotEmpty ? textValue(sms, 'upi_reference') : textValue(notification, 'upi_reference'),
        'classification_method': textValue(bestClassification, 'classification_method'),
        'classification_confidence': bestClassification['classification_confidence'] ?? 1.0,
        'dedup_cluster': cluster,
        'review_status': 'accepted',
      }, where: 'id=?', whereArgs: [smsId]);

      await db.update('transactions', {
        'review_status': 'ignored',
        'dedup_cluster': cluster,
      }, where: 'id=?', whereArgs: [notificationId]);

      // A learned correction from either source should also teach the alternate merchant wording.
      if (textValue(bestClassification, 'classification_method') == 'user_corrected') {
        for (final merchantText in <String>{merchantA, merchantB, chosenMerchant}) {
          final learnedKeyword = (await normalizedMerchant(merchantText)).trim();
          if (learnedKeyword.length < 3 || learnedKeyword.toLowerCase() == 'unknown') continue;
          final existingRule = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM rules WHERE LOWER(keyword)=? AND is_user_rule=1',
            [learnedKeyword.toLowerCase()],
          )) ?? 0;
          if (existingRule == 0) {
            await db.insert('rules', {
              'merchant': chosenMerchant,
              'keyword': learnedKeyword.toLowerCase(),
              'type': textValue(bestClassification, 'type'),
              'category': textValue(bestClassification, 'category'),
              'is_user_rule': 1,
              'enabled': 1,
              'created_at': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      }

      used.addAll([aid, bid]);
      merged++;
    }

    return {'ignored': merged, 'kept': rows.length - merged};
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
    const tables=['transactions','rules','budgets','settings','categories','transaction_splits','accounts','merchant_aliases','review_feedback','recurring_rules','net_worth_items'];
    final data=<String,Object?>{'schema':7,'exportedAt':DateTime.now().toIso8601String()};
    for(final table in tables){data[table]=await db.query(table);}
    return data;
  }

  Future<void> restoreSnapshot(Map<String,Object?> snapshot) async {
    final db=await database;
    const tables=['transaction_splits','review_feedback','transactions','rules','budgets','settings','categories','accounts','merchant_aliases','recurring_rules','net_worth_items'];
    await db.transaction((txn) async {
      for(final table in tables){await txn.delete(table);}
      final insertionOrder=['categories','settings','budgets','rules','merchant_aliases','accounts','recurring_rules','net_worth_items','transactions','transaction_splits','review_feedback'];
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
