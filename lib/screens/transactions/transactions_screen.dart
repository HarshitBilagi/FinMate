/// Full transactions list screen.
///
/// Shows all transactions with category indicators,
/// multi-select batch categorization, and individual categorize bottom sheet access.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/screens/transactions/categorize_sheet.dart';
import 'package:personal_finance_assistant/screens/transactions/batch_categorize_sheet.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/constants/categories.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final Set<String> _selectedTxnIds = {};

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedTxnIds.contains(id)) {
        _selectedTxnIds.remove(id);
      } else {
        _selectedTxnIds.add(id);
      }
    });
  }

  void _selectAll(List<Transaction> txns) {
    setState(() {
      _selectedTxnIds.addAll(txns.map((t) => t.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedTxnIds.clear();
    });
  }

  Future<void> _openBatchCategorize(BuildContext context) async {
    if (_selectedTxnIds.isEmpty) return;

    final dashboard = context.read<DashboardProvider>();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: dashboard,
        child: BatchCategorizeSheet(
          transactionIds: _selectedTxnIds.toList(),
        ),
      ),
    );

    if (result == true) {
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelectionMode = _selectedTxnIds.isNotEmpty;
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSelectionMode
              ? '${_selectedTxnIds.length} Selected'
              : 'Transaction Ledger',
        ),
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: [
          if (isSelectionMode)
            Consumer<DashboardProvider>(
              builder: (context, dashboard, _) => TextButton(
                onPressed: () => _selectAll(dashboard.recentTransactions),
                child: Text(
                  'Select All',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
          final transactions = dashboard.recentTransactions;

          if (transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No transactions yet',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
            physics: const BouncingScrollPhysics(),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final txn = transactions[index];
              final isSelected = _selectedTxnIds.contains(txn.id);

              return GestureDetector(
                onTap: () {
                  if (isSelectionMode) {
                    _toggleSelect(txn.id);
                  } else {
                    _showCategorizeSheet(context, txn);
                  }
                },
                onLongPress: () => _toggleSelect(txn.id),
                child: _buildLedgerRow(
                  context,
                  txn,
                  currencyFormat,
                  isSelectionMode: isSelectionMode,
                  isSelected: isSelected,
                  onToggleSelect: () => _toggleSelect(txn.id),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: isSelectionMode
          ? Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedTxnIds.length} items selected',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openBatchCategorize(context),
                    icon: const Icon(Icons.category_outlined, size: 18),
                    label: Text(
                      'Categorize (${_selectedTxnIds.length})',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildLedgerRow(
    BuildContext context,
    Transaction txn,
    NumberFormat currencyFormat, {
    required bool isSelectionMode,
    required bool isSelected,
    required VoidCallback onToggleSelect,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final dateStr = DateFormat('dd MMM yyyy').format(txn.transactedAt);
    final timeStr = DateFormat('hh:mm a').format(txn.transactedAt);
    final categoryLabel = getCategoryLabel(txn.category);
    final categoryColor = getCategoryColor(txn.category);
    final isCredit = txn.transactionType == 'credit' || txn.isRefund;
    final prefix = isCredit ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                ? const Color(0xFF0D9488).withValues(alpha: 0.18)
                : const Color(0xFFCCFBF1).withValues(alpha: 0.7))
            : (isDark ? const Color(0xFF121212) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isSelected
              ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488))
              : (isDark
                  ? const Color(0xFF333333)
                  : Colors.black.withValues(alpha: 0.04)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (isSelectionMode) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
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
                      size: 16,
                      color: isDark ? Colors.black : Colors.white,
                    )
                  : null,
            ),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeStr,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.merchant ?? 'Unknown Receiver',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                txn.isProcessing
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2DD4BF)),
                          ),
                        ),
                      )
                    : Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          categoryLabel,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: categoryColor,
                          ),
                        ),
                      ),
              ],
            ),
          ),
          Text(
            '$prefix${currencyFormat.format(txn.amount)}',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isCredit
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (isDark ? Colors.white : const Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategorizeSheet(BuildContext context, Transaction txn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategorizeSheet(transaction: txn),
    );
  }
}
