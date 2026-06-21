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

    // Listen for incoming transaction notifications
    _notificationSubscription =
        NotificationService().onTransactionReceived.listen((notification) {
      if (mounted) {
        context.read<DashboardProvider>().loadDashboard();
        _showTransactionCategorizeModal(context, notification);
      }
    });
  }

  /// Drain any cold-start notification payload that was staged in SharedPreferences
  /// by SmsReceiverService.initialize() when the app was launched from a notification tap.
  Future<void> _drainPendingTransaction() async {
    final pending = await SmsReceiverService.drainPendingNotification();
    if (pending != null && mounted) {
      context.read<DashboardProvider>().loadDashboard();
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
    context.read<DashboardProvider>().loadDashboard();
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
          Consumer<DashboardProvider>(
            builder: (context, dashboard, _) {
              final uncategorizedCount = dashboard.recentTransactions.where((t) {
                final cat = t.category.toLowerCase().trim();
                return cat == 'uncategorized' || cat.isEmpty;
              }).length;

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

class _ICICICardStatusCard extends StatefulWidget {
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
            title: const Text('Statement Payment'),
            content: const Text(
              'This billing cycle statement has already been marked as paid. Would you like to mark it as unpaid?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () {
                  _togglePaidState(false);
                  Navigator.of(context).pop();
                },
                child: const Text('Yes'),
              ),
            ],
          );
        } else {
          return AlertDialog(
            title: const Text('Statement Payment Confirmation'),
            content: const Text(
              'Have you already cleared the due amount of ₹--,---.-- for this billing cycle?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () {
                  _togglePaidState(true);
                  Navigator.of(context).pop();
                },
                child: const Text('Yes'),
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

    return GestureDetector(
      onTap: widget.isLoading ? null : () => _showPaymentConfirmationDialog(0.0),
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
                        'ICICI Card Status',
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
                    '₹--,---.-- / ₹--,---.--',
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
                  value: 0.0,
                  minHeight: 8,
                  backgroundColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF10B981),
                  ),
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
                    '₹--,---.--',
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
