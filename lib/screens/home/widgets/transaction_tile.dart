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
          child: Icon(
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
    return switch (category) {
      'food' => Icons.restaurant_outlined,
      'shopping' => Icons.shopping_bag_outlined,
      'transport' => Icons.directions_car_outlined,
      'entertainment' => Icons.movie_outlined,
      'bills' => Icons.receipt_long_outlined,
      'health' => Icons.medical_services_outlined,
      'education' => Icons.school_outlined,
      'travel' => Icons.flight_outlined,
      'groceries' => Icons.local_grocery_store_outlined,
      'fuel' => Icons.local_gas_station_outlined,
      _ => Icons.help_outline,
    };
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'food' => const Color(0xFFEF4444),
      'shopping' => const Color(0xFF8B5CF6),
      'transport' => const Color(0xFF3B82F6),
      'entertainment' => const Color(0xFFEC4899),
      'bills' => const Color(0xFFF97316),
      'health' => const Color(0xFF14B8A6),
      'education' => const Color(0xFF6366F1),
      'travel' => const Color(0xFF0EA5E9),
      'groceries' => const Color(0xFF22C55E),
      'fuel' => const Color(0xFF78716C),
      _ => const Color(0xFF94A3B8),
    };
  }
}
