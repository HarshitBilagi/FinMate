/// Reusable transaction list tile widget.
///
/// Shows merchant, amount (color-coded for debit/refund),
/// timestamp, category icon, and an inline "Categorize" chip
/// for uncategorized transactions.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/core/theme/app_theme.dart';
import 'package:personal_finance_assistant/models/transaction.dart';

class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final NumberFormat currencyFormat;
  final VoidCallback onCategorize;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.currencyFormat,
    required this.onCategorize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRefund = transaction.isRefund;
    final amountColor = isRefund ? AppTheme.income : AppTheme.expense;
    final amountPrefix = isRefund ? '+' : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark1 : AppTheme.cardLight1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _categoryColor(transaction.category)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: transaction.isProcessing
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: _categoryColor(transaction.category),
                    ),
                  ),
                )
              : Icon(
                  _categoryIcon(transaction.category),
                  color: _categoryColor(transaction.category),
                  size: 22,
                ),
        ),
        title: Text(
          transaction.merchant ?? 'Unknown',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              DateFormat('dd MMM, hh:mm a').format(transaction.transactedAt),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.45),
              ),
            ),
            if (transaction.category == 'uncategorized') ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCategorize,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Categorize',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Text(
          '$amountPrefix${currencyFormat.format(transaction.amount)}',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: amountColor,
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    return switch (category.toLowerCase().trim()) {
      'rent' => Icons.home_outlined,
      'whey protein' => Icons.fitness_center_outlined,
      'eggs' => Icons.egg_outlined,
      'sip' => Icons.trending_up_outlined,
      'stocks' => Icons.show_chart_outlined,
      'gym fees' => Icons.sports_gymnastics_outlined,
      'beverages' => Icons.local_cafe_outlined,
      'outside food' => Icons.restaurant_outlined,
      'subscriptions' => Icons.subscriptions_outlined,
      'groceries' => Icons.local_grocery_store_outlined,
      'transportion' || 'transportation' || 'transport' => Icons.directions_car_outlined,
      _ => Icons.help_outline,
    };
  }

  Color _categoryColor(String category) {
    return switch (category.toLowerCase().trim()) {
      'rent' => const Color(0xFFEF4444),
      'whey protein' => const Color(0xFF6366F1),
      'eggs' => const Color(0xFFF59E0B),
      'sip' => const Color(0xFF10B981),
      'stocks' => const Color(0xFF22C55E),
      'gym fees' => const Color(0xFF0EA5E9),
      'beverages' => const Color(0xFFEC4899),
      'outside food' => const Color(0xFFF97316),
      'subscriptions' => const Color(0xFF78716C),
      'groceries' => const Color(0xFF84CC16),
      'transportion' || 'transportation' || 'transport' => const Color(0xFF3B82F6),
      _ => const Color(0xFF94A3B8),
    };
  }
}
