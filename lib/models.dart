class TxRecord {
  final int? id;
  final double amount;
  final String type;
  final String category;
  final String merchant;
  final String normalizedMerchant;
  final String note;
  final String source;
  final String rawMessage;
  final String sender;
  final String paymentMethod;
  final String accountHint;
  final String upiReference;
  final String classificationMethod;
  final double classificationConfidence;
  final String reviewStatus;
  final String transferGroupId;
  final String dedupCluster;
  final int? parentTransactionId;
  final bool isSplitParent;
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
    this.normalizedMerchant = '',
    this.note = '',
    required this.source,
    this.rawMessage = '',
    this.sender = '',
    this.paymentMethod = '',
    this.accountHint = '',
    this.upiReference = '',
    this.classificationMethod = 'legacy',
    this.classificationConfidence = 1.0,
    this.reviewStatus = 'accepted',
    this.transferGroupId = '',
    this.dedupCluster = '',
    this.parentTransactionId,
    this.isSplitParent = false,
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
        normalizedMerchant: (map['normalized_merchant'] as String?) ?? '',
        note: (map['note'] as String?) ?? '',
        source: map['source'] as String,
        rawMessage: (map['raw_message'] as String?) ?? '',
        sender: (map['sender'] as String?) ?? '',
        paymentMethod: (map['payment_method'] as String?) ?? '',
        accountHint: (map['account_hint'] as String?) ?? '',
        upiReference: (map['upi_reference'] as String?) ?? '',
        classificationMethod: (map['classification_method'] as String?) ?? 'legacy',
        classificationConfidence: ((map['classification_confidence'] as num?) ?? 1.0).toDouble(),
        reviewStatus: (map['review_status'] as String?) ?? 'accepted',
        transferGroupId: (map['transfer_group_id'] as String?) ?? '',
        dedupCluster: (map['dedup_cluster'] as String?) ?? '',
        parentTransactionId: (map['parent_transaction_id'] as num?)?.toInt(),
        isSplitParent: ((map['is_split_parent'] as int?) ?? 0) == 1,
        occurredAt: map['occurred_at'] as int,
        createdAt: map['created_at'] as int,
        fingerprint: map['fingerprint'] as String,
        isManual: ((map['is_manual'] as int?) ?? 0) == 1,
      );
}

class PaymentCardRecord {
  final int? id;
  final String name;
  final String issuer;
  final String lastFour;
  final String cardType;
  final double creditLimit;

  const PaymentCardRecord({this.id, required this.name, required this.issuer, required this.lastFour, required this.cardType, required this.creditLimit});

  factory PaymentCardRecord.fromMap(Map<String, Object?> map) => PaymentCardRecord(
        id: map['id'] as int?,
        name: map['name'] as String,
        issuer: (map['issuer'] as String?) ?? '',
        lastFour: (map['last_four'] as String?) ?? '',
        cardType: (map['card_type'] as String?) ?? 'credit',
        creditLimit: ((map['credit_limit'] as num?) ?? 0).toDouble(),
      );
}

class CardLedgerEntry {
  final int? id;
  final int cardId;
  final int? transactionId;
  final String entryType;
  final double amount;
  final int occurredAt;
  final String merchant;
  final String note;

  const CardLedgerEntry({this.id, required this.cardId, this.transactionId, required this.entryType, required this.amount, required this.occurredAt, required this.merchant, required this.note});

  factory CardLedgerEntry.fromMap(Map<String, Object?> map) => CardLedgerEntry(
        id: map['id'] as int?, cardId: map['card_id'] as int, transactionId: (map['transaction_id'] as num?)?.toInt(),
        entryType: map['entry_type'] as String, amount: (map['amount'] as num).toDouble(), occurredAt: map['occurred_at'] as int,
        merchant: (map['merchant'] as String?) ?? '', note: (map['note'] as String?) ?? '',
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
