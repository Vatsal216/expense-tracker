class TxRecord {
  final int id;
  final double amount;
  final String type;
  final String category;
  final String merchant;
  final String source;
  final String paymentMethod;
  final String sender;
  final String rawMessage;
  final DateTime occurredAt;

  const TxRecord({required this.id, required this.amount, required this.type, required this.category, required this.merchant, required this.source, required this.paymentMethod, required this.sender, required this.rawMessage, required this.occurredAt});

  factory TxRecord.fromMap(Map<String, Object?> map) => TxRecord(
    id: map['id'] as int,
    amount: (map['amount'] as num).toDouble(),
    type: (map['type'] as String?) ?? 'expense',
    category: (map['category'] as String?) ?? 'Uncategorized',
    merchant: (map['merchant'] as String?) ?? 'Unknown',
    source: (map['source'] as String?) ?? 'sms',
    paymentMethod: (map['payment_method'] as String?) ?? '',
    sender: (map['sender'] as String?) ?? '',
    rawMessage: (map['raw_message'] as String?) ?? '',
    occurredAt: DateTime.fromMillisecondsSinceEpoch((map['occurred_at'] as num).toInt()),
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

  const MerchantRule({this.id, required this.merchant, required this.keyword, required this.type, required this.category, this.isUserRule = true, this.enabled = true});

  factory MerchantRule.fromMap(Map<String, Object?> map) => MerchantRule(
    id: map['id'] as int,
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
  const BudgetRecord({this.id, required this.category, required this.amount});
  factory BudgetRecord.fromMap(Map<String, Object?> map) => BudgetRecord(id: map['id'] as int, category: map['category'] as String, amount: (map['amount'] as num).toDouble());
}

class CategoryRecord {
  final String name;
  final String kind;
  final bool isSystem;
  const CategoryRecord({required this.name, required this.kind, required this.isSystem});
  factory CategoryRecord.fromMap(Map<String, Object?> map) => CategoryRecord(name: map['name'] as String, kind: map['kind'] as String, isSystem: (map['is_system'] as int) == 1);
}
