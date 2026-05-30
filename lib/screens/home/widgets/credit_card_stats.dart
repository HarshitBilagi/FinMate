/// Credit Card stats widget.
///
/// Indigo→Purple gradient card with usage bar,
/// total/remaining limits, and bill/due dates.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/core/theme/app_theme.dart';
import 'package:personal_finance_assistant/models/card_model.dart';

class CreditCardStatsCard extends StatelessWidget {
  final CardModel card;
  final NumberFormat currencyFormat;
  final bool isDark;

  const CreditCardStatsCard({
    super.key,
    required this.card,
    required this.currencyFormat,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final totalLimit = card.totalLimit ?? 0.0;
    final availableLimit = card.availableLimit ?? 0.0;
    final usedCredit = card.usedCredit;
    final usagePercent =
        totalLimit > 0 ? (usedCredit / totalLimit).clamp(0.0, 1.0) : 0.0;
    final billingDate = card.nextBillingDate;
    final dueDate = billingDate.add(const Duration(days: 20));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.ccCardGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.credit_card, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'ICICI **** ${card.cardMasked}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'CREDIT',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.8),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Usage bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Used: ${currencyFormat.format(usedCredit)}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Text(
                '${(usagePercent * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: usagePercent,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                usagePercent > 0.8
                    ? AppTheme.expense
                    : usagePercent > 0.5
                        ? AppTheme.warning
                        : AppTheme.income,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Stats grid
          Row(
            children: [
              _StatItem(label: 'Total Limit', value: currencyFormat.format(totalLimit)),
              _StatItem(label: 'Remaining', value: currencyFormat.format(availableLimit)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(label: 'Bill Date', value: DateFormat('dd MMM').format(billingDate)),
              _StatItem(label: 'Due Date', value: DateFormat('dd MMM').format(dueDate)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
