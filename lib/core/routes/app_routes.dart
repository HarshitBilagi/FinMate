/// Centralized route definitions for the app.
///
/// Keeps navigation scalable — add new routes here without touching widgets.
library;

import 'package:flutter/material.dart';
import 'package:personal_finance_assistant/screens/auth/auth_screen.dart';
import 'package:personal_finance_assistant/screens/home/home_screen.dart';
import 'package:personal_finance_assistant/screens/transactions/transactions_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String auth = '/auth';
  static const String home = '/home';
  static const String transactions = '/transactions';

  static Map<String, WidgetBuilder> get routes => {
        auth: (_) => const AuthScreen(),
        home: (_) => const HomeScreen(),
        transactions: (_) => const TransactionsScreen(),
      };
}
