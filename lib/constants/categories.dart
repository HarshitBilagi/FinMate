import 'package:flutter/material.dart';

/// Class representing a category option for UI grids, pickers, and modals.
class CategoryOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const CategoryOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Master list of all 15 Expense Categories supported by FinMate.
const List<CategoryOption> kExpenseCategories = [
  CategoryOption(
    id: 'rent',
    label: 'Rent',
    icon: Icons.home_outlined,
    color: Color(0xFFEF4444),
  ),
  CategoryOption(
    id: 'whey protein',
    label: 'Whey Protein',
    icon: Icons.fitness_center_outlined,
    color: Color(0xFF6366F1),
  ),
  CategoryOption(
    id: 'daily protein',
    label: 'Daily Protein',
    icon: Icons.restaurant_menu_outlined,
    color: Color(0xFFA855F7),
  ),
  CategoryOption(
    id: 'eggs',
    label: 'Eggs',
    icon: Icons.egg_outlined,
    color: Color(0xFFF59E0B),
  ),
  CategoryOption(
    id: 'sip',
    label: 'SIP',
    icon: Icons.trending_up_outlined,
    color: Color(0xFF10B981),
  ),
  CategoryOption(
    id: 'stocks',
    label: 'Stocks',
    icon: Icons.show_chart_outlined,
    color: Color(0xFF22C55E),
  ),
  CategoryOption(
    id: 'gym fees',
    label: 'Gym Fees',
    icon: Icons.sports_gymnastics_outlined,
    color: Color(0xFF0EA5E9),
  ),
  CategoryOption(
    id: 'beverages',
    label: 'Beverages',
    icon: Icons.local_cafe_outlined,
    color: Color(0xFFEC4899),
  ),
  CategoryOption(
    id: 'outside food',
    label: 'Outside Food',
    icon: Icons.restaurant_outlined,
    color: Color(0xFFF97316),
  ),
  CategoryOption(
    id: 'subscriptions',
    label: 'Subscriptions',
    icon: Icons.subscriptions_outlined,
    color: Color(0xFF78716C),
  ),
  CategoryOption(
    id: 'groceries',
    label: 'Groceries',
    icon: Icons.local_grocery_store_outlined,
    color: Color(0xFF84CC16),
  ),
  CategoryOption(
    id: 'transportion',
    label: 'Transportation',
    icon: Icons.directions_car_outlined,
    color: Color(0xFF3B82F6),
  ),
  CategoryOption(
    id: 'medicine',
    label: 'Medicine',
    icon: Icons.medical_services_outlined,
    color: Color(0xFF14B8A6),
  ),
  CategoryOption(
    id: 'shopping',
    label: 'Shopping',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFFE11D48),
  ),
  CategoryOption(
    id: 'uncategorized',
    label: 'Uncategorized',
    icon: Icons.help_outline,
    color: Color(0xFF94A3B8),
  ),
];

/// Helper to get the standard IconData for any category string.
IconData getCategoryIcon(String category) {
  final normalized = category.toLowerCase().trim();
  final resolved = (normalized == 'transportation' || normalized == 'transport')
      ? 'transportion'
      : normalized;

  final match = kExpenseCategories.where((c) => c.id == resolved);
  if (match.isNotEmpty) {
    return match.first.icon;
  }
  return Icons.help_outline;
}

/// Helper to get the standard Color for any category string.
Color getCategoryColor(String category) {
  final normalized = category.toLowerCase().trim();
  final resolved = (normalized == 'transportation' || normalized == 'transport')
      ? 'transportion'
      : normalized;

  final match = kExpenseCategories.where((c) => c.id == resolved);
  if (match.isNotEmpty) {
    return match.first.color;
  }
  return const Color(0xFF94A3B8);
}

/// Helper to get the display title/label for any category string.
String getCategoryLabel(String category) {
  final normalized = category.toLowerCase().trim();
  final resolved = (normalized == 'transportation' || normalized == 'transport')
      ? 'transportion'
      : normalized;

  final match = kExpenseCategories.where((c) => c.id == resolved);
  if (match.isNotEmpty) {
    return match.first.label;
  }
  return category.isNotEmpty ? category : 'Uncategorized';
}
