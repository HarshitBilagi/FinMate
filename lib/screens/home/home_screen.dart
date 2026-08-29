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
import 'package:personal_finance_assistant/screens/transactions/batch_categorize_sheet.dart';

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
  final Set<String> _selectedTxnIds = {};

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
        _showTransactionCategorizeModal(context, notification);
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedTxnIds.contains(id)) {
        _selectedTxnIds.remove(id);
      } else {
        _selectedTxnIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedTxnIds.clear();
    });
  }

  void _selectAll(List<Transaction> txns) {
    setState(() {
      _selectedTxnIds.addAll(txns.map((t) => t.id));
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

  /// Drain any cold-start notification payload that was staged in SharedPreferences
  /// by SmsReceiverService.initialize() when the app was launched from a notification tap.
  Future<void> _drainPendingTransaction() async {
    final pending = await SmsReceiverService.drainPendingNotification();
    if (pending != null && mounted) {
      _showTransactionCategorizeModal(context, pending);
    }
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
    final isSelectionMode = _selectedTxnIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              isSelectionMode
                  ? '${_selectedTxnIds.length} Selected'
                  : 'A Finance Sidekick',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          if (isSelectionMode) ...[
            TextButton(
              onPressed: _clearSelection,
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                ),
              ),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'Expense Analytics & PDF Export',
              onPressed: () => Navigator.of(context).pushNamed('/expenses'),
            ),
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
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2DD4BF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
          final txns = dashboard.currentMonthTransactions;

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
                    if (!isSelectionMode)
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
                    if (!isSelectionMode)
                      MonthlyBudgetCard(
                        provider: dashboard,
                        currencyFormat: _currencyFormat,
                        isDark: isDark,
                      ),
                    if (!isSelectionMode) const SizedBox(height: 24),

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
                        if (isSelectionMode)
                          TextButton(
                            onPressed: () => _selectAll(txns),
                            child: Text(
                              'Select All',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                              ),
                            ),
                          )
                        else
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
                    ...txns.map(
                      (txn) => TransactionTile(
                        transaction: txn,
                        currencyFormat: _currencyFormat,
                        isSelectionMode: isSelectionMode,
                        isSelected: _selectedTxnIds.contains(txn.id),
                        onToggleSelect: () => _toggleSelect(txn.id),
                        onLongPress: () => _toggleSelect(txn.id),
                        onCategorize: () => _showCategorizeSheet(context, txn),
                      ),
                    ),
                    const SizedBox(height: 90),
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
                      'Categorize',
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
          : FloatingActionButton.extended(
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
      floatingActionButtonLocation: isSelectionMode
          ? FloatingActionButtonLocation.centerFloat
          : FloatingActionButtonLocation.endFloat,
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
