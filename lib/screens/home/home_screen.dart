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
import 'package:personal_finance_assistant/screens/home/widgets/net_worth_card.dart';
import 'package:personal_finance_assistant/screens/home/widgets/transaction_tile.dart';
import 'package:personal_finance_assistant/screens/transactions/categorize_sheet.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/models/card_model.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';
import 'package:personal_finance_assistant/screens/transactions/transaction_categorize_modal.dart';
import 'package:permission_handler/permission_handler.dart';
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

  /// Dynamic queue of unprocessed notifications (replaces the old mock handler)
  final List<TransactionNotification> _pendingNotifications = [];
  int _unreadCount = 0;

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.notification,
    ].request();

    if (statuses[Permission.sms]?.isGranted ?? false) {
      // Start listening to SMS if permissions were granted
      SmsReceiverService.startListening();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
      _requestPermissions();
      _drainPendingTransaction();
    });

    // Listen for incoming transaction notifications — queue them, don't auto-show
    _notificationSubscription =
        NotificationService().onTransactionReceived.listen((notification) {
      if (mounted) {
        setState(() {
          _pendingNotifications.insert(0, notification);
          _unreadCount++;
        });
        // Also auto-show the modal for foreground interceptions
        _showTransactionCategorizeModal(context, notification);
      }
    });
  }

  /// Drain any cold-start notification payload that was staged in SharedPreferences
  /// by SmsReceiverService.initialize() when the app was launched from a notification tap.
  Future<void> _drainPendingTransaction() async {
    final pending = await SmsReceiverService.drainPendingNotification();
    if (pending != null && mounted) {
      setState(() {
        _pendingNotifications.insert(0, pending);
        _unreadCount++;
      });
      _showTransactionCategorizeModal(context, pending);
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _clearNotification(TransactionNotification notification) {
    if (!mounted) return;
    setState(() {
      _pendingNotifications.removeWhere((n) => n.upiRefId == notification.upiRefId);
      _unreadCount = _pendingNotifications.length;
    });
  }

  void _showTransactionCategorizeModal(
      BuildContext context, TransactionNotification notification) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionCategorizeModal(
        notification: notification,
        onDismiss: () => _clearNotification(notification),
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
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  if (_pendingNotifications.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No new transactions.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  // Show the most recent real pending notification
                  final latest = _pendingNotifications.first;
                  _showTransactionCategorizeModal(context, latest);
                },
              ),
              if (_unreadCount > 0)
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
                      '$_unreadCount',
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
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboard, _) {
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
                  netWorth: dashboard.isLoading ? 0.0 : dashboard.totalNetWorth,
                  savings: dashboard.isLoading ? 0.0 : dashboard.savingsBalance,
                  availableCredit: dashboard.isLoading
                      ? 0.0
                      : (dashboard.primaryCard?.availableLimit ?? 0.0),
                  currencyFormat: _currencyFormat,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),

                // Card 2: ICICI Card Status
                _ICICICardStatusCard(
                  isLoading: dashboard.isLoading,
                  card: dashboard.primaryCard,
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

class _ICICICardStatusCard extends StatelessWidget {
  final bool isLoading;
  final CardModel? card;
  final NumberFormat currencyFormat;
  final bool isDark;

  const _ICICICardStatusCard({
    required this.isLoading,
    required this.card,
    required this.currencyFormat,
    required this.isDark,
  });

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

  @override
  Widget build(BuildContext context) {
    final totalLimit = isLoading ? 0.0 : 90000.00;
    final availableLimit = isLoading ? 0.0 : (card?.availableLimit ?? 90000.00);
    final usedCredit = isLoading ? 0.0 : (totalLimit - availableLimit);
    final usagePercent =
        totalLimit > 0 ? (usedCredit / totalLimit).clamp(0.0, 1.0) : 0.0;

    final statementDueAmount = usedCredit;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = _getNextDueDate(today);
    final formattedDueDate = DateFormat('dd MMM yyyy').format(dueDate);
    
    final daysRemaining = dueDate.difference(today).inDays;

    return Card(
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
                      color: isDark
                          ? const Color(0xFF2DD4BF)
                          : const Color(0xFF0D9488),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'ICICI Card Status',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                _buildAlertPill(daysRemaining, isDark),
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  '${currencyFormat.format(usedCredit)} / ${currencyFormat.format(totalLimit)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: usagePercent,
                minHeight: 8,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(
                  usagePercent > 0.8
                      ? const Color(0xFFF43F5E)
                      : usagePercent > 0.5
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Divider(
              color: isDark
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  currencyFormat.format(statementDueAmount),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  formattedDueDate,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ],
        ),
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
