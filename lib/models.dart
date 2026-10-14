class TxRecord {
  final int? id;
  final double amount;
  final String type;
  final String category;
  final String merchant;
  final String note;
  final String source;
  final String rawMessage;
  final String sender;
  final String paymentMethod;
  final String accountHint;
  final String upiReference;
  final String classificationMethod;
  final double classificationConfidence;
  final int occurredAt;
  final int createdAt;
  final String fingerprint;
  final bool isManual;

  const TxRecord({
    this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.merchant,
    this.note = '',
    required this.source,
    this.rawMessage = '',
    this.sender = '',
    this.paymentMethod = '',
    this.accountHint = '',
    this.upiReference = '',
    this.classificationMethod = 'legacy',
    this.classificationConfidence = 1.0,
    required this.occurredAt,
    required this.createdAt,
    required this.fingerprint,
    this.isManual = false,
  });

  factory TxRecord.fromMap(Map<String, Object?> map) => TxRecord(
        id: map['id'] as int?,
        amount: (map['amount'] as num).toDouble(),
        type: map['type'] as String,
        category: map['category'] as String,
        merchant: map['merchant'] as String,
        note: (map['note'] as String?) ?? '',
        source: map['source'] as String,
        rawMessage: (map['raw_message'] as String?) ?? '',
        sender: (map['sender'] as String?) ?? '',
        paymentMethod: (map['payment_method'] as String?) ?? '',
        accountHint: (map['account_hint'] as String?) ?? '',
        upiReference: (map['upi_reference'] as String?) ?? '',
        classificationMethod: (map['classification_method'] as String?) ?? 'legacy',
        classificationConfidence: ((map['classification_confidence'] as num?) ?? 1.0).toDouble(),
        occurredAt: map['occurred_at'] as int,
        createdAt: map['created_at'] as int,
        fingerprint: map['fingerprint'] as String,
        isManual: ((map['is_manual'] as int?) ?? 0) == 1,
      );
}

class MerchantRule {
  final int? id;
  final String merchant;
  final String keyword;
  final String type;
  final String category;
  final bool isUserRule;
  final bool enabled;

  const MerchantRule({
    this.id,
    required this.merchant,
    required this.keyword,
    required this.type,
    required this.category,
    required this.isUserRule,
    required this.enabled,
  });

  factory MerchantRule.fromMap(Map<String, Object?> map) => MerchantRule(
        id: map['id'] as int?,
        merchant: map['merchant'] as String,
        keyword: map['keyword'] as String,
        type: map['type'] as String,
        category: map['category'] as String,
        isUserRule: (map['is_user_rule'] as int) == 1,
        enabled: (map['enabled'] as int) == 1,
      );
}

class BudgetRecord {
  final int? id;
  final String category;
  final double amount;
  final String period;

  const BudgetRecord({this.id, required this.category, required this.amount, this.period = 'monthly'});

  factory BudgetRecord.fromMap(Map<String, Object?> map) => BudgetRecord(
        id: map['id'] as int?,
        category: map['category'] as String,
        amount: (map['amount'] as num).toDouble(),
        period: (map['period'] as String?) ?? 'monthly',
      );
}

class CategoryRecord {
  final String name;
  final String kind;
  final bool isSystem;

  const CategoryRecord({required this.name, required this.kind, required this.isSystem});

  factory CategoryRecord.fromMap(Map<String, Object?> map) => CategoryRecord(
        name: map['name'] as String,
        kind: map['kind'] as String,
        isSystem: (map['is_system'] as int) == 1,
      );
}
