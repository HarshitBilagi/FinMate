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
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';
import 'package:personal_finance_assistant/screens/transactions/transaction_categorize_modal.dart';

import 'package:personal_finance_assistant/core/services/sms_receiver_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
                    const SizedBox(height: 16),

                    // Card 2: ICICI Credit Card Status
                    _ICICICardStatusCard(
                      isLoading: dashboard.isLoading,
                      usedCredit: dashboard.usedCredit,
                      totalLimit: dashboard.totalCreditLimit,
                      remainingCredit: dashboard.remainingCredit,
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
                    ...dashboard.currentMonthTransactions.map(
                      (txn) => TransactionTile(
                        transaction: txn,
                        currencyFormat: _currencyFormat,
                        onCategorize: () => _showCategorizeSheet(context, txn),
                      ),
                    ),
                    const SizedBox(height: 32),
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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
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

class _ICICICardStatusCard extends StatefulWidget {
  final bool isLoading;
  final double usedCredit;
  final double totalLimit;
  final double remainingCredit;
  final NumberFormat currencyFormat;
  final bool isDark;

  const _ICICICardStatusCard({
    required this.isLoading,
    required this.usedCredit,
    required this.totalLimit,
    required this.remainingCredit,
    required this.currencyFormat,
    required this.isDark,
  });

  @override
  State<_ICICICardStatusCard> createState() => _ICICICardStatusCardState();
}

class _ICICICardStatusCardState extends State<_ICICICardStatusCard> {
  bool _isPaid = false;
  late String _storageKey;

  @override
  void initState() {
    super.initState();
    _initStorageKeyAndLoad();
  }

  @override
  void didUpdateWidget(covariant _ICICICardStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initStorageKeyAndLoad();
  }

  void _initStorageKeyAndLoad() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = _getNextDueDate(today);
    final formattedDueDate = DateFormat('yyyy-MM-dd').format(dueDate);
    _storageKey = 'card_statement_paid_$formattedDueDate';
    _loadPaidState();
  }

  Future<void> _loadPaidState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isPaid = prefs.getBool(_storageKey) ?? false;
      });
    }
  }

  Future<void> _togglePaidState(bool paid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, paid);
    if (mounted) {
      setState(() {
        _isPaid = paid;
      });
    }
  }

  DateTime _getNextDueDate(DateTime today) {
    final dateOnly = DateTime(today.year, today.month, today.day);

    // 1. Due date for the statement generated on the 28th of the previous month
    final prevMonthVal = today.month == 1 ? 12 : today.month - 1;
    final prevYearVal = today.month == 1 ? today.year - 1 : today.year;
    final statementPrev = DateTime(prevYearVal, prevMonthVal, 28);
    final duePrev = statementPrev.add(const Duration(days: 18));

    // 2. Due date for the statement generated on the 28th of the current month
    final statementCurr = DateTime(today.year, today.month, 28);
    final dueCurr = statementCurr.add(const Duration(days: 18));

    // 3. Due date for the statement generated on the 28th of the next month
    final nextMonthVal = today.month == 12 ? 1 : today.month + 1;
    final nextYearVal = today.month == 12 ? today.year + 1 : today.year;
    final statementNext = DateTime(nextYearVal, nextMonthVal, 28);
    final dueNext = statementNext.add(const Duration(days: 18));

    if (dateOnly.isBefore(duePrev) || dateOnly.isAtSameMomentAs(duePrev)) {
      return duePrev;
    } else if (dateOnly.isBefore(dueCurr) || dateOnly.isAtSameMomentAs(dueCurr)) {
      return dueCurr;
    } else {
      return dueNext;
    }
  }

  void _showPaymentConfirmationDialog(double amount) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        if (_isPaid) {
          return AlertDialog(
            backgroundColor: const Color(0xFF121212),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF333333), width: 1),
            ),
            title: Text(
              'Statement Payment',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'This billing cycle statement has already been marked as paid. Would you like to mark it as unpaid?',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'No',
                  style: GoogleFonts.inter(color: const Color(0xFF8E8E93)),
                ),
              ),
              TextButton(
                onPressed: () {
                  _togglePaidState(false);
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Yes',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        } else {
          return AlertDialog(
            backgroundColor: const Color(0xFF121212),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF333333), width: 1),
            ),
            title: Text(
              'Statement Payment Confirmation',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Have you already cleared the due amount of ${widget.currencyFormat.format(amount)} for this billing cycle?',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'No',
                  style: GoogleFonts.inter(color: const Color(0xFF8E8E93)),
                ),
              ),
              TextButton(
                onPressed: () {
                  _togglePaidState(true);
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Yes',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = _getNextDueDate(today);
    final formattedDueDate = DateFormat('dd MMM yyyy').format(dueDate);
    
    final daysRemaining = dueDate.difference(today).inDays;
    
    final progressValue = widget.totalLimit > 0 
        ? (widget.usedCredit / widget.totalLimit).clamp(0.0, 1.0) 
        : 0.0;
    
    final progressColor = progressValue > 0.8 
        ? const Color(0xFFF43F5E) // Red/coral
        : const Color(0xFF10B981); // Emerald green (original)

    return GestureDetector(
      onTap: widget.isLoading ? null : () => _showPaymentConfirmationDialog(widget.usedCredit),
      child: Card(
        margin: const EdgeInsets.only(bottom: 24),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.credit_card_rounded,
                        color: widget.isDark
                            ? const Color(0xFF2DD4BF)
                            : const Color(0xFF0D9488),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'ICICI CC (XX1008)',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: widget.isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  _isPaid
                      ? _buildPaidPill(dueDate, widget.isDark)
                      : _buildAlertPill(daysRemaining, widget.isDark),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Used Credit',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '₹${widget.usedCredit.toStringAsFixed(2)} / ₹${widget.totalLimit.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 8,
                  backgroundColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: 20),
              Divider(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                height: 1,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Statement Due Amount',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    widget.currencyFormat.format(widget.usedCredit),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: widget.isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Due Date',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    formattedDueDate,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: widget.isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaidPill(DateTime dueDate, bool isDark) {
    final Color baseColor = const Color(0xFF10B981);
    // final nextMonthDate = DateTime(dueDate.year, dueDate.month + 1, 15);
    // final formattedNextDueDate = DateFormat('dd MMM yyyy').format(nextMonthDate);
    // final label = 'Due next month ($formattedNextDueDate)';
    final label = 'Due next month';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: baseColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 12,
            color: baseColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: baseColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertPill(int daysRemaining, bool isDark) {
    final Color baseColor;
    final String label;

    if (daysRemaining == 0) {
      baseColor = const Color(0xFFF43F5E);
      label = 'Due Today';
    } else if (daysRemaining <= 5) {
      baseColor = const Color(0xFFF43F5E);
      label = '$daysRemaining days left';
    } else if (daysRemaining <= 10) {
      baseColor = const Color(0xFFF59E0B);
      label = '$daysRemaining days left';
    } else {
      baseColor = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
      label = '$daysRemaining days left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: baseColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time_filled_rounded,
            size: 12,
            color: baseColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: baseColor,
            ),
          ),
        ],
      ),
    );
  }
}
