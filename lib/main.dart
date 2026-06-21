/// Foundational Finance Friend — App Entry Point.
///
/// Sets up Provider tree, theme, routes, and the auth gate.
/// Firebase is initialized for FCM push notifications.
/// The app starts on AuthScreen and only navigates to HomeScreen
/// after successful biometric/PIN authentication.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:personal_finance_assistant/core/theme/app_theme.dart';
import 'package:personal_finance_assistant/core/routes/app_routes.dart';
import 'package:personal_finance_assistant/providers/auth_provider.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/core/services/sms_receiver_service.dart';
import 'package:personal_finance_assistant/services/finance_api_client.dart';
// Firebase imports — uncomment when google-services.json is configured:
// import 'package:firebase_core/firebase_core.dart';
// import 'package:personal_finance_assistant/services/notification_service.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   // Lock orientation to portrait
//   await SystemChrome.setPreferredOrientations([
//     DeviceOrientation.portraitUp,
//     DeviceOrientation.portraitDown,
//   ]);

//   // Firebase initialization — uncomment when google-services.json is added:
//   // await Firebase.initializeApp();
//   // FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
//   // await NotificationService().initialize();
//   runApp(const FinanceFriendApp());
// }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Firebase initialization — Now active!
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService().initialize();

  // Initialize native SMS listener services
  await SmsReceiverService.initialize();
  await SmsReceiverService.startListening();

  // [Cold Boot] Initiate a lightweight health check to wake up the Render container
  // with minimal payload weight during biometrics.
  debugPrint('[Cold Boot] Initiating container wake-up via checkBackendHealth() — Render container wake-up initiated.');
  FinanceApiClient().checkBackendHealth();

  final dashboardProvider = DashboardProvider();

  runApp(FinanceFriendApp(dashboardProvider: dashboardProvider));
}

class FinanceFriendApp extends StatelessWidget {
  final DashboardProvider dashboardProvider;

  const FinanceFriendApp({super.key, required this.dashboardProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: dashboardProvider),
      ],
      child: MaterialApp(
        title: 'Finance Friend',
        debugShowCheckedModeBanner: false,

        // ── Theme: System-default dark/light mode ────────────────────
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,

        // ── Routes ───────────────────────────────────────────────────
        initialRoute: AppRoutes.auth,
        routes: AppRoutes.routes,
      ),
    );
  }
}
