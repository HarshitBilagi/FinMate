import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/constants/categories.dart';

class PdfReportService {
  /// Generates a structured, professional monthly PDF report and opens the native share/print dialog.
  static Future<void> exportAndShareReport({
    required DateTime month,
    required double monthlyBudget,
    required List<Transaction> transactions,
  }) async {
    final pdfBytes = await generateMonthlyReport(
      month: month,
      monthlyBudget: monthlyBudget,
      transactions: transactions,
    );

    final monthStr = DateFormat('MMMM_yyyy').format(month);
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'FinMate_Expense_Report_$monthStr.pdf',
    );
  }

  /// Builds the monthly PDF document and returns the raw byte data.
  static Future<Uint8List> generateMonthlyReport({
    required DateTime month,
    required double monthlyBudget,
    required List<Transaction> transactions,
  }) async {
    final pdf = pw.Document();

    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs. ',
      decimalDigits: 2,
    );

    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final generatedOn = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    // 1. Calculate Summary Metrics
    final currentMonthTxns = transactions.where((t) =>
        t.transactedAt.month == month.month &&
        t.transactedAt.year == month.year).toList();

    double totalDebits = 0.0;
    double totalCredits = 0.0;

    final Map<String, double> categoryDebits = {};
    final Map<String, double> categoryCredits = {};

    for (final cat in kExpenseCategories) {
      categoryDebits[cat.id] = 0.0;
      categoryCredits[cat.id] = 0.0;
    }

    for (final txn in currentMonthTxns) {
      final isCredit = txn.transactionType == 'credit' || txn.isRefund;
      final rawCat = txn.category.toLowerCase().trim();
      final cat = (rawCat == 'transportation' || rawCat == 'transport') ? 'transportion' : rawCat;
      final key = categoryDebits.containsKey(cat) ? cat : 'uncategorized';

      if (isCredit) {
        totalCredits += txn.amount;
        categoryCredits[key] = (categoryCredits[key] ?? 0.0) + txn.amount;
      } else {
        totalDebits += txn.amount;
        categoryDebits[key] = (categoryDebits[key] ?? 0.0) + txn.amount;
      }
    }

    final double totalOutflow = totalDebits - totalCredits;
    final double remainingBudget = monthlyBudget - totalOutflow;

    // Load Font for clean typography
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();
    final fontMedium = await PdfGoogleFonts.interMedium();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
          ),
        ),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FinMate',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 22,
                          color: PdfColors.teal800,
                        ),
                      ),
                      pw.Text(
                        'Monthly Expense & Budget Report',
                        style: pw.TextStyle(
                          font: fontMedium,
                          fontSize: 13,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        monthLabel,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 16,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        'Generated: $generatedOn',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 16),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 16),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            ),
          );
        },
        build: (pw.Context context) => [
          // ── KPI Summary Cards ──────────────────────────────────────────
          pw.Row(
            children: [
              _buildKpiCard(
                title: 'Monthly Budget',
                amount: currencyFormat.format(monthlyBudget),
                color: PdfColors.blue800,
                fontBold: fontBold,
                fontMedium: fontMedium,
              ),
              pw.SizedBox(width: 12),
              _buildKpiCard(
                title: 'Total Outflow',
                amount: currencyFormat.format(totalOutflow),
                color: const PdfColor.fromInt(0xFFE11D48),
                fontBold: fontBold,
                fontMedium: fontMedium,
              ),
              pw.SizedBox(width: 12),
              _buildKpiCard(
                title: 'Net Remaining',
                amount: currencyFormat.format(remainingBudget),
                color: remainingBudget >= 0 ? const PdfColor.fromInt(0xFF059669) : PdfColors.red700,
                fontBold: fontBold,
                fontMedium: fontMedium,
              ),
            ],
          ),
          pw.SizedBox(height: 24),

          // ── Expense Category Breakdown Table ───────────────────────────
          pw.Text(
            'Category Summary',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 14,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2.2),
              4: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableCell('Category', isHeader: true, fontBold: fontBold),
                  _buildTableCell('Debits', isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                  _buildTableCell('Credits', isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                  _buildTableCell('Net Spent', isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                  _buildTableCell('% Budget', isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                ],
              ),
              ...kExpenseCategories
                  .where((c) =>
                      (categoryDebits[c.id] ?? 0) > 0 ||
                      (categoryCredits[c.id] ?? 0) > 0)
                  .map((c) {
                final debits = categoryDebits[c.id] ?? 0.0;
                final credits = categoryCredits[c.id] ?? 0.0;
                final net = debits - credits;
                final pct = monthlyBudget > 0 ? (net / monthlyBudget * 100).toStringAsFixed(1) : '0.0';

                return pw.TableRow(
                  children: [
                    _buildTableCell(c.label),
                    _buildTableCell(currencyFormat.format(debits), align: pw.TextAlign.right),
                    _buildTableCell(currencyFormat.format(credits), align: pw.TextAlign.right),
                    _buildTableCell(currencyFormat.format(net), align: pw.TextAlign.right, isBold: true),
                    _buildTableCell('$pct%', align: pw.TextAlign.right),
                  ],
                );
              }),
              // Total Summary Row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableCell('Total Outflow', isHeader: true, fontBold: fontBold),
                  _buildTableCell(currencyFormat.format(totalDebits), isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                  _buildTableCell(currencyFormat.format(totalCredits), isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                  _buildTableCell(currencyFormat.format(totalOutflow), isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                  _buildTableCell(
                    monthlyBudget > 0 ? '${(totalOutflow / monthlyBudget * 100).toStringAsFixed(1)}%' : '0.0%',
                    isHeader: true,
                    align: pw.TextAlign.right,
                    fontBold: fontBold,
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 28),

          // ── Itemized Transactions Ledger ───────────────────────────────
          pw.Text(
            'Itemized Transaction Ledger (${currentMonthTxns.length} records)',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 14,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(3.5),
              2: pw.FlexColumnWidth(2.3),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(2.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableCell('Date & Time', isHeader: true, fontBold: fontBold),
                  _buildTableCell('Merchant / Description', isHeader: true, fontBold: fontBold),
                  _buildTableCell('Category', isHeader: true, fontBold: fontBold),
                  _buildTableCell('Type', isHeader: true, fontBold: fontBold),
                  _buildTableCell('Amount', isHeader: true, align: pw.TextAlign.right, fontBold: fontBold),
                ],
              ),
              ...currentMonthTxns.map((txn) {
                final isCredit = txn.transactionType == 'credit' || txn.isRefund;
                final sign = isCredit ? '+' : '-';
                final dateStr = DateFormat('dd MMM, hh:mm a').format(txn.transactedAt);
                final categoryName = getCategoryLabel(txn.category);

                return pw.TableRow(
                  children: [
                    _buildTableCell(dateStr),
                    _buildTableCell(txn.merchant ?? 'Unknown'),
                    _buildTableCell(categoryName),
                    _buildTableCell(txn.transactionType.toUpperCase()),
                    _buildTableCell(
                      '$sign${currencyFormat.format(txn.amount)}',
                      align: pw.TextAlign.right,
                      textColor: isCredit ? const PdfColor.fromInt(0xFF059669) : const PdfColor.fromInt(0xFFE11D48),
                      isBold: true,
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildKpiCard({
    required String title,
    required String amount,
    required PdfColor color,
    required pw.Font fontBold,
    required pw.Font fontMedium,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fontMedium,
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              amount,
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? textColor,
    pw.Font? fontBold,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: (isHeader || isBold) && fontBold != null ? fontBold : null,
          fontSize: isHeader ? 9.5 : 8.5,
          color: textColor ?? (isHeader ? PdfColors.black : PdfColors.grey900),
        ),
      ),
    );
  }
}
