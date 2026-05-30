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
      transactedAt: DateTime.parse(json['transacted_at'] as String),
    );
  }

  Transaction copyWith({String? category}) {
    return Transaction(
      id: id,
      cardId: cardId,
      upiRefId: upiRefId,
      amount: amount,
      merchant: merchant,
      category: category ?? this.category,
      transactionType: transactionType,
      isRefund: isRefund,
      source: source,
      transactedAt: transactedAt,
    );
  }
}
