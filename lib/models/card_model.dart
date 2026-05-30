/// Card data model mirroring the Supabase `cards` table.
library;

class CardModel {
  final String id;
  final String userId;
  final String cardMasked;
  final String cardType; // 'credit_card' | 'debit_account'
  final double? totalLimit;
  final double? availableLimit;
  final int billingCycleDay;
  final bool isActive;

  const CardModel({
    required this.id,
    required this.userId,
    required this.cardMasked,
    this.cardType = 'credit_card',
    this.totalLimit,
    this.availableLimit,
    this.billingCycleDay = 1,
    this.isActive = true,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      cardMasked: json['card_masked'] as String,
      cardType: json['card_type'] as String? ?? 'credit_card',
      totalLimit: (json['total_limit'] as num?)?.toDouble(),
      availableLimit: (json['available_limit'] as num?)?.toDouble(),
      billingCycleDay: json['billing_cycle_day'] as int? ?? 1,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Computes the next billing date from today.
  DateTime get nextBillingDate {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, billingCycleDay);
    if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
      next = DateTime(now.year, now.month + 1, billingCycleDay);
    }
    return next;
  }

  /// Used credit = Total - Available
  double get usedCredit =>
      (totalLimit ?? 0) - (availableLimit ?? 0);
}
