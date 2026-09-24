/// Model representing the budget status for a specific category in a given month.
class CategoryBudget {
  final String category;
  final double budgetLimit;
  final double spent;
  final double remaining;
  final double percentageUsed;

  const CategoryBudget({
    required this.category,
    required this.budgetLimit,
    required this.spent,
    required this.remaining,
    required this.percentageUsed,
  });

  factory CategoryBudget.fromJson(Map<String, dynamic> json) {
    return CategoryBudget(
      category: json['category'] as String? ?? 'uncategorized',
      budgetLimit: (json['budget_limit'] as num?)?.toDouble() ?? 0.0,
      spent: (json['spent'] as num?)?.toDouble() ?? 0.0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0.0,
      percentageUsed: (json['percentage_used'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'budget_limit': budgetLimit,
      'spent': spent,
      'remaining': remaining,
      'percentage_used': percentageUsed,
    };
  }

  CategoryBudget copyWith({
    String? category,
    double? budgetLimit,
    double? spent,
    double? remaining,
    double? percentageUsed,
  }) {
    return CategoryBudget(
      category: category ?? this.category,
      budgetLimit: budgetLimit ?? this.budgetLimit,
      spent: spent ?? this.spent,
      remaining: remaining ?? this.remaining,
      percentageUsed: percentageUsed ?? this.percentageUsed,
    );
  }
}
