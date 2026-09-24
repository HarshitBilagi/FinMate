import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/constants/categories.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';

class CategoryBudgetModal extends StatefulWidget {
  final int month;
  final int year;

  const CategoryBudgetModal({
    super.key,
    required this.month,
    required this.year,
  });

  static Future<void> show(BuildContext context, {int? month, int? year}) {
    final now = DateTime.now();
    final targetMonth = month ?? now.month;
    final targetYear = year ?? now.year;

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CategoryBudgetModal(
        month: targetMonth,
        year: targetYear,
      ),
    );
  }

  @override
  State<CategoryBudgetModal> createState() => _CategoryBudgetModalState();
}

class _CategoryBudgetModalState extends State<CategoryBudgetModal> {
  final Map<String, TextEditingController> _controllers = {};
  bool _isSaving = false;
  bool _isAutoFilling = false;
  double _totalBudget = 0.0;

  @override
  void initState() {
    super.initState();
    final dashboard = context.read<DashboardProvider>();
    final currentLimits = dashboard.categoryBudgetLimits;

    for (final cat in kExpenseCategories) {
      final existingLimit = currentLimits[cat.id] ?? 0.0;
      final text = existingLimit > 0
          ? (existingLimit % 1 == 0
              ? existingLimit.toInt().toString()
              : existingLimit.toStringAsFixed(2))
          : '';
      final controller = TextEditingController(text: text);
      controller.addListener(_recalculateTotal);
      _controllers[cat.id] = controller;
    }
    _recalculateTotal();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_recalculateTotal);
      controller.dispose();
    }
    super.dispose();
  }

  void _recalculateTotal() {
    double total = 0.0;
    for (final controller in _controllers.values) {
      final val = double.tryParse(controller.text.trim()) ?? 0.0;
      total += val;
    }
    if (mounted) {
      setState(() {
        _totalBudget = total;
      });
    }
  }

  Future<void> _autoFillFromLastMonth() async {
    if (_isAutoFilling) return;
    setState(() => _isAutoFilling = true);

    try {
      final dashboard = context.read<DashboardProvider>();
      final prevBudgets = await dashboard.fetchPreviousMonthBudgets(
        currentMonth: widget.month,
        currentYear: widget.year,
      );

      if (prevBudgets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No budget limits found for last month to copy.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      int filledCount = 0;
      for (final cat in kExpenseCategories) {
        final prevVal = prevBudgets[cat.id];
        if (prevVal != null && prevVal > 0) {
          final text = prevVal % 1 == 0
              ? prevVal.toInt().toString()
              : prevVal.toStringAsFixed(2);
          _controllers[cat.id]?.text = text;
          filledCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-filled $filledCount category budgets from last month.'),
            backgroundColor: const Color(0xFF0D9488),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error auto-filling budgets: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAutoFilling = false);
      }
    }
  }

  Future<void> _saveBudgets() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final Map<String, double> budgetsToSave = {};
      for (final cat in kExpenseCategories) {
        final text = _controllers[cat.id]?.text.trim() ?? '';
        final amount = double.tryParse(text) ?? 0.0;
        budgetsToSave[cat.id] = amount;
      }

      final dashboard = context.read<DashboardProvider>();
      final success = await dashboard.saveCategoryBudgets(
        widget.month,
        widget.year,
        budgetsToSave,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Category budgets saved successfully!'),
              backgroundColor: Color(0xFF0D9488),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(dashboard.errorMessage ?? 'Failed to save budgets.'),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime(widget.year, widget.month, 1));
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 0,
    );

    final bgColor = isDark ? const Color(0xFF131722) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E2433) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Top Grab Bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Category Budgets',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          monthLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Auto-fill from Last Month Quick Action Button
                  OutlinedButton.icon(
                    onPressed: _isAutoFilling ? null : _autoFillFromLastMonth,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D9488),
                      side: const BorderSide(color: Color(0xFF0D9488), width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: _isAutoFilling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D9488)),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      'Auto-fill Last Month',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Total Budget Summary Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Color(0xFF0D9488),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Total Planned Budget',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    currencyFormat.format(_totalBudget),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0D9488),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Scrollable 15 Categories List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                physics: const BouncingScrollPhysics(),
                itemCount: kExpenseCategories.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final cat = kExpenseCategories[index];
                  final controller = _controllers[cat.id];

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        // Category Icon Badge
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(cat.icon, color: cat.color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        // Category Label
                        Expanded(
                          child: Text(
                            cat.label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        // Limit Input Field
                        SizedBox(
                          width: 120,
                          height: 42,
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.end,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              prefixText: '\u20B9 ',
                              prefixStyle: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              hintText: '0',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 14,
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: isDark ? Colors.black26 : Colors.white,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white12 : Colors.black12,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0D9488),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Action Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveBudgets,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save Category Budgets',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
