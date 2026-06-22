import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';
import 'package:personal_finance_assistant/screens/transactions/transaction_categorize_modal.dart';

class NotificationsInboxScreen extends StatelessWidget {
  const NotificationsInboxScreen({super.key});

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
        title: const Text('Uncategorized Inbox'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
          final uncategorizedTransactions = dashboard.recentTransactions.where((t) {
            final cat = t.category.toLowerCase().trim();
            return cat == 'uncategorized' || cat.isEmpty;
          }).toList();

          if (uncategorizedTransactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Inbox clear! No uncategorized transactions.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            physics: const BouncingScrollPhysics(),
            itemCount: uncategorizedTransactions.length,
            itemBuilder: (context, index) {
              final txn = uncategorizedTransactions[index];
              return GestureDetector(
                onTap: () => _showCategorizeModal(context, txn),
                child: _buildInboxRow(context, txn, currencyFormat),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInboxRow(
      BuildContext context, Transaction txn, NumberFormat currencyFormat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('dd MMM yyyy').format(txn.transactedAt);
    final timeStr = DateFormat('hh:mm a').format(txn.transactedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? const Color(0xFF333333)
              : Colors.black.withValues(alpha: 0.04),
          width: 1,
        ),
      ),
      child: Row(
        children: [
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
          const SizedBox(width: 20),
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
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                          ),
                        ),
                      )
                    : Text(
                        'Uncategorized',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
              ],
            ),
          ),
          Text(
            currencyFormat.format(txn.amount),
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategorizeModal(BuildContext context, Transaction txn) {
    final dashboard = context.read<DashboardProvider>();
    final notification = TransactionNotification(
      transactionId: txn.id,
      amount: txn.amount.toString(),
      merchant: txn.merchant ?? 'Unknown',
      cardMasked: '',
      upiRefId: txn.upiRefId,
      action: 'categorize',
      transactionDate: txn.transactedAt,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: dashboard,
        child: TransactionCategorizeModal(
          notification: notification,
          // No need for onDismiss → loadDashboard(); categorization already
          // triggers _silentRefresh() via the provider.
        ),
      ),
    );
  }
}
