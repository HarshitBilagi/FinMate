/// Centralized route definitions for the app.
///
/// Keeps navigation scalable — add new routes here without touching widgets.
library;

import 'package:flutter/material.dart';
import 'package:personal_finance_assistant/screens/auth/auth_screen.dart';
import 'package:personal_finance_assistant/screens/home/home_screen.dart';
import 'package:personal_finance_assistant/screens/transactions/transactions_screen.dart';
import 'package:personal_finance_assistant/screens/expenses/expenses_screen.dart';
import 'package:personal_finance_assistant/screens/notifications/notifications_inbox_screen.dart';
import 'package:personal_finance_assistant/screens/loading/loading_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String auth = '/auth';
  static const String loading = '/loading';
  static const String home = '/home';
  static const String transactions = '/transactions';
  static const String expenses = '/expenses';
  static const String notifications = '/notifications';

  static Map<String, WidgetBuilder> get routes => {
        auth: (_) => const AuthScreen(),
        loading: (_) => const LoadingScreen(),
        home: (_) => const HomeScreen(),
        transactions: (_) => const TransactionsScreen(),
        expenses: (_) => const ExpensesScreen(),
        notifications: (_) => const NotificationsInboxScreen(),
      };
}
