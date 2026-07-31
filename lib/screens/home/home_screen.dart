/// Home Dashboard screen with Stacked Card design.
///
/// Card 1: Total Net Worth (Savings + CC Limit Left)
/// Card 2: Credit Card Stats (Total Limit, Remaining, Bill Date, Due Date)
/// + Recent Transactions list with quick-categorize
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/screens/home/widgets/monthly_budget_card.dart';
import 'package:personal_finance_assistant/screens/home/widgets/transaction_tile.dart';
import 'package:personal_finance_assistant/screens/transactions/categorize_sheet.dart';
import 'package:personal_finance_assistant/screens/transactions/add_transaction_modal.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';
import 'package:personal_finance_assistant/screens/transactions/transaction_categorize_modal.dart';

import 'package:personal_finance_assistant/core/services/sms_receiver_service.dart';

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

  StreamSubscription<TransactionNotification>? _notificationSubscription;



  @override
  void initState() {
    super.initState();
    // Dashboard is pre-hydrated in main.dart — no need to call loadDashboard() again.
    // SMS listener is registered in main.dart — no need to call startListening() again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainPendingTransaction();
    });

    // Listen for incoming transaction notifications
    _notificationSubscription =
        NotificationService().onTransactionReceived.listen((notification) {
      if (mounted) {
        final dashboard = context.read<DashboardProvider>();
        final matchingTxns = dashboard.recentTransactions.where((t) => t.upiRefId == notification.upiRefId);
        TransactionNotification latestNotification = notification;
        if (matchingTxns.isNotEmpty) {
          final latestTxn = matchingTxns.first;
          latestNotification = TransactionNotification(
            transactionId: latestTxn.id,
            amount: latestTxn.amount.toString(),
            merchant: latestTxn.merchant ?? notification.merchant,
            upiRefId: latestTxn.upiRefId,
            cardMasked: latestTxn.cardId,
            action: latestTxn.category,
            transactionDate: latestTxn.transactedAt,
          );
        }
        _showTransactionCategorizeModal(context, latestNotification);
      }
    });
  }

  /// Drain any cold-start notification payload that was staged in SharedPreferences
  /// by SmsReceiverService.initialize() when the app was launched from a notification tap.
  Future<void> _drainPendingTransaction() async {
    final pending = await SmsReceiverService.drainPendingNotification();
    if (pending != null && mounted) {
      final dashboard = context.read<DashboardProvider>();
      final matchingTxns = dashboard.recentTransactions.where((t) => t.upiRefId == pending.upiRefId);
      TransactionNotification latestNotification = pending;
      if (matchingTxns.isNotEmpty) {
        final latestTxn = matchingTxns.first;
        latestNotification = TransactionNotification(
          transactionId: latestTxn.id,
          amount: latestTxn.amount.toString(),
          merchant: latestTxn.merchant ?? pending.merchant,
          upiRefId: latestTxn.upiRefId,
          cardMasked: latestTxn.cardId,
          action: latestTxn.category,
          transactionDate: latestTxn.transactedAt,
        );
      }
      _showTransactionCategorizeModal(context, latestNotification);
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _showTransactionCategorizeModal(
      BuildContext context, TransactionNotification notification) {
    final dashboard = context.read<DashboardProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: dashboard,
        child: TransactionCategorizeModal(
          notification: notification,
          // No onDismiss needed — categorization already triggers _silentRefresh()
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('A Finance Sidekick'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () => Navigator.of(context).pushNamed('/expenses'),
          ),
          // Dynamic notification badge — shows unread count from real SMS data
          Consumer<DashboardProvider>(
            builder: (context, dashboard, _) {
              final uncategorizedCount = dashboard.uncategorized.length;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.of(context).pushNamed('/notifications'),
                  ),
                  if (uncategorizedCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF43F5E),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$uncategorizedCount',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
          return Stack(
            children: [
              RefreshIndicator(
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

                    // Card 1: Monthly Budget Card
                    MonthlyBudgetCard(
                      provider: dashboard,
                      currencyFormat: _currencyFormat,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 24),

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
                    ...dashboard.currentMonthTransactions.map(
                      (txn) => TransactionTile(
                        transaction: txn,
                        currencyFormat: _currencyFormat,
                        onCategorize: () => _showCategorizeSheet(context, txn),
                      ),
                    ),
                    const SizedBox(height: 80),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTransactionModal(context),
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add Transaction',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _showAddTransactionModal(BuildContext context) {
    final dashboard = context.read<DashboardProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: dashboard,
        child: const AddTransactionModal(),
      ),
    );
  }

  void _showCategorizeSheet(BuildContext context, Transaction txn) {
    final dashboard = context.read<DashboardProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: dashboard,
        child: CategorizeSheet(transaction: txn),
      ),
    );
  }
}
