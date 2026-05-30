/// Full transactions list screen.
///
/// Shows all transactions with category filtering and
/// categorize bottom sheet access.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/screens/home/widgets/transaction_tile.dart';
import 'package:personal_finance_assistant/screens/transactions/categorize_sheet.dart';
import 'package:personal_finance_assistant/models/transaction.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Transactions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No transactions yet',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark
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
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final txn = transactions[index];
              return TransactionTile(
                transaction: txn,
                currencyFormat: currencyFormat,
                onCategorize: () => _showCategorizeSheet(context, txn),
              );
            },
          );
        },
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
