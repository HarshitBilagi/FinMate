/// Full-width Bottom Sheet Modal to categorize intercepted transactions in real-time.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';

class TransactionCategorizeModal extends StatefulWidget {
  final TransactionNotification notification;
  final VoidCallback? onDismiss;

  const TransactionCategorizeModal({
    super.key,
    required this.notification,
    this.onDismiss,
  });

  @override
  State<TransactionCategorizeModal> createState() =>
      _TransactionCategorizeModalState();
}

class _TransactionCategorizeModalState
    extends State<TransactionCategorizeModal> {
  String? _selectedCategory;

  static const _categories = [
    _CategoryOption('food', Icons.restaurant_outlined, Color(0xFFEF4444)),
    _CategoryOption('shopping', Icons.shopping_bag_outlined, Color(0xFF8B5CF6)),
    _CategoryOption(
        'transport', Icons.directions_car_outlined, Color(0xFF3B82F6)),
    _CategoryOption('entertainment', Icons.movie_outlined, Color(0xFFEC4899)),
    _CategoryOption('bills', Icons.receipt_long_outlined, Color(0xFFF97316)),
    _CategoryOption('health', Icons.medical_services_outlined, Color(0xFF14B8A6)),
    _CategoryOption('education', Icons.school_outlined, Color(0xFF6366F1)),
    _CategoryOption('travel', Icons.flight_outlined, Color(0xFF0EA5E9)),
    _CategoryOption(
        'groceries', Icons.local_grocery_store_outlined, Color(0xFF22C55E)),
    _CategoryOption('fuel', Icons.local_gas_station_outlined, Color(0xFF78716C)),
    _CategoryOption(
        'uncategorized', Icons.help_outline_outlined, Color(0xFF94A3B8)),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = 'uncategorized';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 2,
    );

    final amountDouble = double.tryParse(widget.notification.amount) ?? 0.0;
    final formattedAmount = currencyFormat.format(amountDouble);
    final formattedDate =
        DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'NEW TRANSACTION DETECTED',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              widget.notification.merchant,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              formattedAmount,
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              children: [
                _MetaRow('Date & Time', formattedDate),
                const SizedBox(height: 8),
                _MetaRow('UPI Ref ID', widget.notification.upiRefId),
                if (widget.notification.cardMasked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MetaRow('Account / Card', widget.notification.cardMasked),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Categorize Expense',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat.name;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = cat.name;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cat.color.withValues(alpha: 0.2)
                          : cat.color.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? cat.color : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cat.icon, color: cat.color, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            cat.name[0].toUpperCase() + cat.name.substring(1),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cat.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    context
                        .read<DashboardProvider>()
                        .ignoreTransaction(widget.notification.upiRefId);
                    widget.onDismiss?.call();
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Transaction ignored.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.black.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final categoryToUse = _selectedCategory ?? 'uncategorized';
                    context
                        .read<DashboardProvider>()
                        .addAndCategorizeTransaction(
                          upiRefId: widget.notification.upiRefId,
                          amount: amountDouble,
                          merchant: widget.notification.merchant,
                          category: categoryToUse,
                        );
                    widget.onDismiss?.call();
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Transaction added to ${categoryToUse[0].toUpperCase() + categoryToUse.substring(1)}.'),
                        backgroundColor: const Color(0xFF10B981),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF2DD4BF)
                        : const Color(0xFF0D9488),
                    foregroundColor:
                        isDark ? const Color(0xFF0F172A) : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'Add',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.5),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark
                ? Colors.white.withValues(alpha: 0.9)
                : const Color(0xFF1E293B),
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
