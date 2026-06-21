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

class CategorizeSheet extends StatelessWidget {
  final Transaction transaction;

  const CategorizeSheet({super.key, required this.transaction});

  static const _categories = [
    _CategoryOption('rent', Icons.home_outlined, Color(0xFFEF4444)),
    _CategoryOption('whey protein', Icons.fitness_center_outlined, Color(0xFF6366F1)),
    _CategoryOption('eggs', Icons.egg_outlined, Color(0xFFF59E0B)),
    _CategoryOption('sip', Icons.trending_up_outlined, Color(0xFF10B981)),
    _CategoryOption('stocks', Icons.show_chart_outlined, Color(0xFF22C55E)),
    _CategoryOption('gym fees', Icons.sports_gymnastics_outlined, Color(0xFF0EA5E9)),
    _CategoryOption('beverages', Icons.local_cafe_outlined, Color(0xFFEC4899)),
    _CategoryOption('outside food', Icons.restaurant_outlined, Color(0xFFF97316)),
    _CategoryOption('subscriptions', Icons.subscriptions_outlined, Color(0xFF78716C)),
    _CategoryOption('groceries', Icons.local_grocery_store_outlined, Color(0xFF84CC16)),
    _CategoryOption('transportion', Icons.directions_car_outlined, Color(0xFF3B82F6)),
  ];

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

            // Title
            Text(
              'Categorize Transaction',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
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
                  _DetailRow('Amount', currencyFormat.format(transaction.amount)),
                  const SizedBox(height: 8),
                  _DetailRow('Merchant', transaction.merchant ?? 'Unknown'),
                  const SizedBox(height: 8),
                  _DetailRow('UPI Ref', transaction.upiRefId),
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
                final isSelected = transaction.category == cat.name;

                return GestureDetector(
                  onTap: () {
                    context
                        .read<DashboardProvider>()
                        .categorizeTransaction(transaction.id, cat.name);
                    Navigator.of(context).pop();
                  },
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
                          cat.name.split(' ').map((word) => word.toLowerCase() == 'sip' ? 'SIP' : (word[0].toUpperCase() + word.substring(1).toLowerCase())).join(' '),
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

class _CategoryOption {
  final String name;
  final IconData icon;
  final Color color;

  const _CategoryOption(this.name, this.icon, this.color);
}
