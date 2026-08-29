/// Expenses Screen displaying Donut Chart and Category breakdown table.
///
/// Categorizes individual categories into 3 Macro Groups:
/// 1. Investments (SIP, Stocks)
/// 2. Fixed/Health (Rent, Whey Protein, Daily Protein, Eggs, Gym Fees, Groceries, Transport, Medicine)
/// 3. Variables (Beverages, Outside Food, Subscriptions, Shopping, Uncategorized)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/constants/categories.dart';
import 'package:personal_finance_assistant/services/pdf_report_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _isExporting = false;

  Color _getMacroColorForCategory(String category) {
    switch (category.toLowerCase().trim()) {
      case 'sip':
      case 'stocks':
        return const Color(0xFF10B981); // Investments - Emerald
      case 'rent':
      case 'whey protein':
      case 'daily protein':
      case 'eggs':
      case 'gym fees':
      case 'groceries':
      case 'transportion':
      case 'transportation':
      case 'transport':
      case 'medicine':
        return const Color(0xFF6366F1); // Fixed/Health - Indigo
      default:
        return const Color(0xFFF59E0B); // Variables - Amber
    }
  }

  Future<void> _exportPdfReport() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final dashboard = context.read<DashboardProvider>();
      await PdfReportService.exportAndShareReport(
        month: DateTime.now(),
        monthlyBudget: dashboard.monthlyBudget,
        transactions: dashboard.recentTransactions,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF report: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Analysis'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export Monthly PDF Report',
            onPressed: _isExporting ? null : _exportPdfReport,
          ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
          final transactions = dashboard.recentTransactions;

          // 1. Initialize category totals dynamically from kExpenseCategories
          final categoryTotals = <String, double>{};
          for (final cat in kExpenseCategories) {
            categoryTotals[cat.id] = 0.0;
          }

          double totalOutflow = 0.0;
          for (final txn in transactions) {
            final cat = txn.category.toLowerCase().trim();
            final resolvedCat = (cat == 'transportation' || cat == 'transport') ? 'transportion' : cat;
            final isCredit = txn.transactionType == 'credit' || txn.isRefund;
            final signedAmount = isCredit ? -txn.amount : txn.amount;

            if (categoryTotals.containsKey(resolvedCat)) {
              categoryTotals[resolvedCat] = categoryTotals[resolvedCat]! + signedAmount;
              totalOutflow += signedAmount;
            } else {
              categoryTotals['uncategorized'] =
                  (categoryTotals['uncategorized'] ?? 0.0) + signedAmount;
              totalOutflow += signedAmount;
            }
          }

          // 2. Aggregate into the 3 defined Macro Groups
          final double investmentsTotal = (categoryTotals['sip'] ?? 0.0) + (categoryTotals['stocks'] ?? 0.0);

          final double fixedHealthTotal = (categoryTotals['rent'] ?? 0.0) +
              (categoryTotals['whey protein'] ?? 0.0) +
              (categoryTotals['daily protein'] ?? 0.0) +
              (categoryTotals['eggs'] ?? 0.0) +
              (categoryTotals['gym fees'] ?? 0.0) +
              (categoryTotals['groceries'] ?? 0.0) +
              (categoryTotals['transportion'] ?? 0.0) +
              (categoryTotals['medicine'] ?? 0.0);

          final double variablesTotal = (categoryTotals['beverages'] ?? 0.0) +
              (categoryTotals['outside food'] ?? 0.0) +
              (categoryTotals['subscriptions'] ?? 0.0) +
              (categoryTotals['shopping'] ?? 0.0) +
              (categoryTotals['uncategorized'] ?? 0.0);

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => dashboard.loadDashboard(),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  children: [
                    // Export PDF Report Banner Card
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF0F766E), const Color(0xFF134E4A)]
                              : [const Color(0xFF0D9488), const Color(0xFF14B8A6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Monthly PDF Report',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Export & share itemized ledger summary',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _isExporting ? null : _exportPdfReport,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F766E),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isExporting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    'Export',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // Macro Donut Chart Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Macro Breakdown',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Donut Chart representation
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 140,
                                      height: 140,
                                      child: CustomPaint(
                                        painter: DonutChartPainter(
                                          values: [
                                            investmentsTotal,
                                            fixedHealthTotal,
                                            variablesTotal
                                          ],
                                          colors: const [
                                            Color(0xFF10B981), // Investments - Emerald
                                            Color(0xFF6366F1), // Fixed/Health - Indigo
                                            Color(0xFFF59E0B), // Variables - Amber
                                          ],
                                          strokeWidth: 16,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'TOTAL',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.5)
                                                : Colors.black.withValues(alpha: 0.5),
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          currencyFormat.format(totalOutflow),
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF1E293B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Legend
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _LegendItem(
                                        label: 'Investments',
                                        amount: investmentsTotal,
                                        total: totalOutflow,
                                        color: const Color(0xFF10B981),
                                        currencyFormat: currencyFormat,
                                      ),
                                      const SizedBox(height: 12),
                                      _LegendItem(
                                        label: 'Fixed / Health',
                                        amount: fixedHealthTotal,
                                        total: totalOutflow,
                                        color: const Color(0xFF6366F1),
                                        currencyFormat: currencyFormat,
                                      ),
                                      const SizedBox(height: 12),
                                      _LegendItem(
                                        label: 'Variables',
                                        amount: variablesTotal,
                                        total: totalOutflow,
                                        color: const Color(0xFFF59E0B),
                                        currencyFormat: currencyFormat,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Granular Category Table
                    Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Table Header
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Category',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.4)
                                        : Colors.black.withValues(alpha: 0.4),
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                Text(
                                  'Total Outflow',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.4)
                                        : Colors.black.withValues(alpha: 0.4),
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                          // Table Body Rows
                          ...categoryTotals.entries.map((entry) {
                            final catName = entry.key;
                            final catAmount = entry.value;
                            final macroColor = _getMacroColorForCategory(catName);
                            final categoryTitle = getCategoryLabel(catName);

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: macroColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            categoryTitle,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.9)
                                                  : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        currencyFormat.format(catAmount),
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.05),
                                ),
                              ],
                            );
                          }),
                          // Mathematical Total Row
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.black.withValues(alpha: 0.02),
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(20)),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'TOTAL OUTFLOW',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(totalOutflow),
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? const Color(0xFF2DD4BF)
                                        : const Color(0xFF0D9488),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (dashboard.isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final double amount;
  final double total;
  final Color color;
  final NumberFormat currencyFormat;

  const _LegendItem({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
    required this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percent = total > 0 ? (amount / total) * 100 : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF1E293B),
                ),
              ),
              Text(
                '${percent.toStringAsFixed(1)}% • ${currencyFormat.format(amount)}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double strokeWidth;

  DonutChartPainter({
    required this.values,
    required this.colors,
    this.strokeWidth = 24.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0.0, (sum, val) => sum + val);
    if (total == 0) {
      // Draw a neutral gray circle if no expenses exist yet
      final paint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(
          size.center(Offset.zero), (size.width - strokeWidth) / 2, paint);
      return;
    }

    final double radius = (size.width - strokeWidth) / 2;
    final rect =
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    double startAngle = -3.141592653589793 / 2; // Start from top (-90 degrees)

    for (int i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweepAngle = (values[i] / total) * 2 * 3.141592653589793;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
