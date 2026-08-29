/// Categorize bottom sheet for manual transaction categorization.
///
/// Shows transaction details (Amount, Merchant, UPI ID) and a grid
/// of category options. No LLM — user manually selects.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/models/transaction.dart';

import 'package:personal_finance_assistant/constants/categories.dart';

class CategorizeSheet extends StatefulWidget {
  final Transaction transaction;

  const CategorizeSheet({super.key, required this.transaction});

  @override
  State<CategorizeSheet> createState() => _CategorizeSheetState();
}

class _CategorizeSheetState extends State<CategorizeSheet> {
  bool _isSaving = false;

  final _categories = kExpenseCategories.where((c) => c.id != 'uncategorized').toList();

  Future<void> _onCategoryTap(String categoryId, String categoryLabel) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    // Capture provider BEFORE async gap
    final provider = context.read<DashboardProvider>();
    final success = await provider.categorizeTransaction(widget.transaction.id, categoryId);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to $categoryLabel')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save. Please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 2,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title & Delete action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Categorize Transaction',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFF43F5E)),
                  tooltip: 'Delete Transaction',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
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
                          'Are you sure you want to delete "${widget.transaction.merchant ?? 'Transaction'}"?',
                          style: GoogleFonts.inter(
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(false),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(true),
                            child: Text(
                              'Delete',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFF43F5E),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      final provider = context.read<DashboardProvider>();
                      await provider.deleteTransaction(widget.transaction.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Transaction deleted')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Transaction details
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                children: [
                  _DetailRow('Amount', currencyFormat.format(widget.transaction.amount)),
                  const SizedBox(height: 8),
                  _DetailRow('Merchant', widget.transaction.merchant ?? 'Unknown'),
                  const SizedBox(height: 8),
                  _DetailRow('UPI Ref', widget.transaction.upiRefId),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Category label
            Text(
              'Select Category',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.black.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),

            // Loading indicator while saving
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
            // Category grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = widget.transaction.category == cat.id;

                return GestureDetector(
                  onTap: () => _onCategoryTap(cat.id, cat.label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cat.color.withValues(alpha: 0.2)
                          : cat.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: isSelected
                          ? Border.all(color: cat.color, width: 2)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cat.icon, color: cat.color, size: 20),
                        const SizedBox(height: 6),
                        Text(
                          cat.label,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cat.color,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: isDark
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.5),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
