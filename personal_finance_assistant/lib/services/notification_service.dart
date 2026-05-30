/// Firebase Cloud Messaging notification service.
///
/// Handles FCM token retrieval, foreground message listening,
/// and background message dispatch. Parses data payloads
/// containing Amount, Merchant, and UPI ID.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Top-level handler for background FCM messages.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM Background] ${message.data}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Stream controller for incoming transaction notifications.
  /// Widgets can listen to this for real-time categorization prompts.
  final StreamController<TransactionNotification> _notificationStream =
      StreamController<TransactionNotification>.broadcast();

  Stream<TransactionNotification> get onTransactionReceived =>
      _notificationStream.stream;

  /// Initialize FCM: request permissions, get token, set up listeners.
  Future<void> initialize() async {
    // Request notification permissions (required on iOS & Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token for this device
    final token = await _messaging.getToken();
    debugPrint('[FCM] Token: $token');
    // TODO: Send this token to backend → users.fcm_token

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token refreshed: $newToken');
      // TODO: Update token in Supabase
    });

    // ── Foreground messages ──────────────────────────────────────────
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // ── Notification tap (app was in background) ─────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // ── Check if app was opened from a terminated state notification ─
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM Foreground] Data: ${message.data}');

    final notification = _parsePayload(message.data);
    if (notification != null) {
      _notificationStream.add(notification);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM Tap] Data: ${message.data}');

    final notification = _parsePayload(message.data);
    if (notification != null) {
      _notificationStream.add(notification);
    }
  }

  /// Parse the FCM data payload into a structured notification object.
  ///
  /// Expected payload (from backend):
  /// ```json
  /// {
  ///   "transaction_id": "uuid",
  ///   "amount": "80.00",
  ///   "merchant": "BEJADI V",
  ///   "upi_ref_id": "649827115634",
  ///   "card_masked": "XXXXXX",
  ///   "action": "categorize"
  /// }
  /// ```
  TransactionNotification? _parsePayload(Map<String, dynamic> data) {
    try {
      return TransactionNotification(
        transactionId: data['transaction_id'] as String? ?? '',
        amount: data['amount'] as String? ?? '0.00',
        merchant: data['merchant'] as String? ?? 'Unknown',
        upiRefId: data['upi_ref_id'] as String? ?? '',
        cardMasked: data['card_masked'] as String? ?? '',
        action: data['action'] as String? ?? 'categorize',
      );
    } catch (e) {
      debugPrint('[FCM] Failed to parse payload: $e');
      return null;
    }
  }

  void dispose() {
    _notificationStream.close();
  }
}

/// Structured representation of an incoming transaction push notification.
class TransactionNotification {
  final String transactionId;
  final String amount;
  final String merchant;
  final String upiRefId;
  final String cardMasked;
  final String action;

  const TransactionNotification({
    required this.transactionId,
    required this.amount,
    required this.merchant,
    required this.upiRefId,
    required this.cardMasked,
    required this.action,
  });

  @override
  String toString() =>
      'TxnNotification(amount=$amount, merchant=$merchant, upi=$upiRefId)';
}
