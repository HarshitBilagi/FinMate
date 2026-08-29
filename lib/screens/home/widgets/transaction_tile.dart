/// Reusable transaction list tile widget.
///
/// Shows merchant, amount (color-coded for debit/refund),
/// timestamp, category icon, inline "Categorize" chip,
/// swipe-to-delete support, and multi-selection mode.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:personal_finance_assistant/core/theme/app_theme.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/constants/categories.dart';

class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final NumberFormat currencyFormat;
  final VoidCallback onCategorize;
  final VoidCallback? onDelete;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.currencyFormat,
    required this.onCategorize,
    this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCredit = transaction.isRefund || transaction.transactionType == 'credit';
    final amountColor = isCredit ? AppTheme.income : AppTheme.expense;
    final amountPrefix = isCredit ? '+' : '-';
    final catColor = getCategoryColor(transaction.category);
    final catIcon = getCategoryIcon(transaction.category);

    final tileContent = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                ? const Color(0xFF0D9488).withValues(alpha: 0.18)
                : const Color(0xFFCCFBF1).withValues(alpha: 0.7))
            : (isDark ? AppTheme.cardDark1 : AppTheme.cardLight1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488))
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06)),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (isSelectionMode && onToggleSelect != null) {
              onToggleSelect!();
            } else if (transaction.category == 'uncategorized') {
              onCategorize();
            }
          },
          onLongPress: onLongPress ?? onToggleSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Selection checkbox or category icon
                if (isSelectionMode) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488))
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488))
                            : (isDark ? Colors.white38 : Colors.black38),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: isDark ? Colors.black : Colors.white,
                          )
                        : null,
                  ),
                ],

                // Leading Category Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: transaction.isProcessing
                      ? Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              color: catColor,
                            ),
                          ),
                        )
                      : Icon(
                          catIcon,
                          color: catColor,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 12),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.merchant ?? 'Unknown',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
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
                          if (transaction.category == 'uncategorized' && !isSelectionMode) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: onCategorize,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Trailing Amount
                Text(
                  '$amountPrefix${currencyFormat.format(transaction.amount)}',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // When selection mode is active, disable swipe-to-dismiss to prevent accidental deletion
    if (isSelectionMode) {
      return tileContent;
    }

    return Dismissible(
      key: Key(transaction.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
                ),
              ),
              title: Text(
                'Delete Transaction?',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              content: Text(
                'Are you sure you want to delete "${transaction.merchant ?? 'Transaction'}" (${currencyFormat.format(transaction.amount)})?',
                style: GoogleFonts.inter(
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(
                    'Delete',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFF43F5E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        ) ?? false;
      },
      onDismissed: (direction) {
        if (onDelete != null) {
          onDelete!();
        } else {
          context.read<DashboardProvider>().deleteTransaction(transaction.id);
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF43F5E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      child: tileContent,
    );
  }
}
