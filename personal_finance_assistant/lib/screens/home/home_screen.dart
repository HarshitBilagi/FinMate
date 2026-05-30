/// Home Dashboard screen with Stacked Card design.
///
/// Card 1: Total Net Worth (Savings + CC Limit Left)
/// Card 2: Credit Card Stats (Total Limit, Remaining, Bill Date, Due Date)
/// + Recent Transactions list with quick-categorize
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/screens/home/widgets/net_worth_card.dart';
import 'package:personal_finance_assistant/screens/home/widgets/credit_card_stats.dart';
import 'package:personal_finance_assistant/screens/home/widgets/transaction_tile.dart';
import 'package:personal_finance_assistant/screens/transactions/categorize_sheet.dart';
import 'package:personal_finance_assistant/models/transaction.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Friend'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
          if (dashboard.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => dashboard.loadDashboard(),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                const SizedBox(height: 8),
                // Greeting
                Text(
                  _greeting(),
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 20),

                // Card 1: Net Worth
                NetWorthCard(
                  netWorth: dashboard.totalNetWorth,
                  savings: dashboard.savingsBalance,
                  availableCredit:
                      dashboard.primaryCard?.availableLimit ?? 0,
                  currencyFormat: _currencyFormat,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),

                // Card 2: Credit Card Stats
                if (dashboard.primaryCard != null)
                  CreditCardStatsCard(
                    card: dashboard.primaryCard!,
                    currencyFormat: _currencyFormat,
                    isDark: isDark,
                  ),
                const SizedBox(height: 28),

                // Recent Transactions Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/transactions'),
                      child: Text(
                        'See All',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF2DD4BF)
                              : const Color(0xFF0D9488),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Transaction List
                ...dashboard.recentTransactions.map(
                  (txn) => TransactionTile(
                    transaction: txn,
                    currencyFormat: _currencyFormat,
                    onCategorize: () => _showCategorizeSheet(context, txn),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _showCategorizeSheet(BuildContext context, Transaction txn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategorizeSheet(transaction: txn),
    );
  }
}
