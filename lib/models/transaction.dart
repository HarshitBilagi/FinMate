/// Transaction data model mirroring the Supabase schema.
///
/// Used by both the dashboard and transaction list providers.
library;

class Transaction {
  final String id;
  final String cardId;
  final String upiRefId;
  final double amount;
  final String? merchant;
  final String category;
  final String transactionType; // 'debit' | 'credit' | 'refund'
  final bool isRefund;
  final String source; // 'email' | 'sms' | 'manual'
  final DateTime transactedAt;

  final bool isProcessing;

  const Transaction({
    required this.id,
    required this.cardId,
    required this.upiRefId,
    required this.amount,
    this.merchant,
    this.category = 'uncategorized',
    this.transactionType = 'debit',
    this.isRefund = false,
    this.source = 'email',
    required this.transactedAt,
    this.isProcessing = false,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      cardId: json['card_id'] as String,
      upiRefId: json['upi_ref_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      merchant: json['merchant'] as String?,
      category: json['category'] as String? ?? 'uncategorized',
      transactionType: json['transaction_type'] as String? ?? 'debit',
      isRefund: json['is_refund'] as bool? ?? false,
      source: json['source'] as String? ?? 'email',
      transactedAt: DateTime.parse(json['transacted_at'] as String).toLocal(),
      isProcessing: false,
    );
  }

  Transaction copyWith({
    String? id,
    String? cardId,
    String? upiRefId,
    double? amount,
    String? merchant,
    String? category,
    String? transactionType,
    bool? isRefund,
    String? source,
    DateTime? transactedAt,
    bool? isProcessing,
  }) {
    return Transaction(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      upiRefId: upiRefId ?? this.upiRefId,
      amount: amount ?? this.amount,
      merchant: merchant ?? this.merchant,
      category: category ?? this.category,
      transactionType: transactionType ?? this.transactionType,
      isRefund: isRefund ?? this.isRefund,
      source: source ?? this.source,
      transactedAt: transactedAt ?? this.transactedAt,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}
