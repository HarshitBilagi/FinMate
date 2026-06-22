import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:personal_finance_assistant/services/notification_service.dart';
import 'package:personal_finance_assistant/services/finance_api_client.dart';
import 'package:permission_handler/permission_handler.dart';

/// SharedPreferences key for staging a notification payload when the app
/// is launched from a killed state by tapping a local notification.
/// The HomeScreen reads and clears this after fully mounting.
const String _kPendingNotificationPayload = 'pending_notification_payload';

/// Top-level background SMS handler. Must be a top-level function.
/// Runs in a completely separate isolate — no access to main-isolate state.
@pragma('vm:entry-point')
void nativeSmsBackgroundHandler(SmsMessage message) async {
  // 1. Bootstrap Flutter engine bindings in this background isolate
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[SMS Background] Intercepted message from: ${message.address}');

  final body = message.body;
  if (body == null || body.isEmpty) return;

  // 2. Initialize a LOCAL FlutterLocalNotificationsPlugin for this isolate
  final bgNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await bgNotificationsPlugin.initialize(initSettings);

  debugPrint('[SMS Background] Local notifications plugin initialized in background isolate.');

  // 3. Parse the SMS body using shared regex logic
  final parsed = SmsReceiverService.parseSmsBody(body);
  if (parsed != null) {
    debugPrint('[SMS Background] Transaction parsed: ₹${parsed.amount} at ${parsed.merchant}');

    // 4. Attempt database write (via FastAPI backend), cache on failure
    await SmsReceiverService.saveTransactionToBackendOrCache(parsed, body);

    // 5. Fire notification directly from this isolate's own plugin instance
    final payload = jsonEncode({
      'transaction_id': parsed.transactionId,
      'amount': parsed.amount,
      'merchant': parsed.merchant,
      'upi_ref_id': parsed.upiRefId,
      'card_masked': parsed.cardMasked,
      'action': parsed.action,
    });

    const androidChannel = AndroidNotificationDetails(
      'transaction_interceptor_channel',
      'Transaction Alerts',
      channelDescription: 'Notifications for on-device SMS intercepted transactions.',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: true,
    );

    const platformDetails = NotificationDetails(android: androidChannel);

    await bgNotificationsPlugin.show(
      parsed.upiRefId.hashCode,
      'New Transaction Intercepted',
      '₹${parsed.amount} spent at ${parsed.merchant}',
      platformDetails,
      payload: payload,
    );

    debugPrint('[SMS Background] Notification fired from background isolate for: ${parsed.upiRefId}');
  }
}

class SmsReceiverService {
  static final Telephony _telephony = Telephony.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize local notifications and handle deep-linking taps
  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Foreground tap — HomeScreen is already mounted, safe to push to stream
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationPayload(payload);
        }
      },
    );

    // Cold-start: app was launched by tapping a notification while killed.
    // Do NOT push to the stream here — no widget is listening yet.
    // Instead, stage the payload in SharedPreferences for HomeScreen to drain.
    final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kPendingNotificationPayload, payload);
        debugPrint('[SMS Receiver] Cold-start payload staged for HomeScreen.');
      }
    }

    // Process cached offline transactions on foreground initialization
    await processOfflineCache();
  }

  /// Process deep-linking when a notification is tapped
  static void _handleNotificationPayload(String payload) {
    try {
      final Map<String, dynamic> data = jsonDecode(payload);
      final notification = TransactionNotification(
        transactionId: data['transaction_id'] ?? '',
        amount: data['amount'] ?? '0.00',
        merchant: data['merchant'] ?? 'Unknown',
        upiRefId: data['upi_ref_id'] ?? '',
        cardMasked: data['card_masked'] ?? '',
        action: data['action'] ?? 'categorize',
      );
      
      // Publish event to trigger TransactionCategorizeModal on HomeScreen
      NotificationService().triggerTransactionCategorization(notification);
      debugPrint('[SMS Receiver] Deep-linked transaction to UI: ${notification.upiRefId}');
    } catch (e) {
      debugPrint('[SMS Receiver] Error parsing notification payload: $e');
    }
  }

  /// Read and clear any pending notification payload staged during cold-start.
  /// Called by HomeScreen after it has fully mounted and can show modals.
  static Future<TransactionNotification?> drainPendingNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_kPendingNotificationPayload);
    if (payload == null || payload.isEmpty) return null;

    // Clear immediately so it's never processed twice
    await prefs.remove(_kPendingNotificationPayload);
    debugPrint('[SMS Receiver] Draining cold-start pending notification.');

    try {
      final Map<String, dynamic> data = jsonDecode(payload);
      return TransactionNotification(
        transactionId: data['transaction_id'] ?? '',
        amount: data['amount'] ?? '0.00',
        merchant: data['merchant'] ?? 'Unknown',
        upiRefId: data['upi_ref_id'] ?? '',
        cardMasked: data['card_masked'] ?? '',
        action: data['action'] ?? 'categorize',
      );
    } catch (e) {
      debugPrint('[SMS Receiver] Error parsing pending notification: $e');
      return null;
    }
  }

  /// Start foreground & background SMS listeners if permissions are granted
  static Future<void> startListening() async {
    final permissionsGranted = await Permission.sms.isGranted;
    if (permissionsGranted == true) {
      _telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) async {
          debugPrint('[SMS Foreground] Intercepted message: ${message.body}');
          final body = message.body;
          if (body != null && body.isNotEmpty) {
            final parsed = parseSmsBody(body);
            if (parsed != null) {
              // Direct foreground trigger of modal
              NotificationService().triggerTransactionCategorization(parsed);
              // Save to backend or cache
              await saveTransactionToBackendOrCache(parsed, body);
              // Also show local notification
              await showLocalNotification(parsed);
            }
          }
        },
        onBackgroundMessage: nativeSmsBackgroundHandler,
        listenInBackground: true,
      );
      debugPrint('[SMS Receiver] Listener started.');
    } else {
      debugPrint('[SMS Receiver] SMS permissions not granted. Listener not started.');
    }
  }

  /// Request exemption from Android Doze mode battery optimizations.
  /// This is critical for Android 14+ (API 34+) where background isolates
  /// are aggressively killed. Should be called during app initialization.
  static Future<void> requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      final result = await Permission.ignoreBatteryOptimizations.request();
      debugPrint('[SMS Receiver] Battery optimization exemption: ${result.isGranted ? "GRANTED" : "DENIED"}');
    } else {
      debugPrint('[SMS Receiver] Battery optimization exemption already granted.');
    }
  }

  /// Parse the ICICI SMS text structure.
  /// Handles both Credit Card and Debit Account message patterns.
  ///
  /// Production samples:
  ///   CC:    "ICICI Bank Credit Card XX1008 debited for INR 40.00 on 04-Jun-26 for UPI-652117366854-TEA CUBE."
  ///   Debit: "ICICI Bank Acct XX423 debited for Rs 267.00 on 13-May-26; NIDHIN NATH T P credited. UPI:649918293649."
  static TransactionNotification? parseSmsBody(String body) {
    // ── Shared regex components ────────────────────────────────────────────────
    //  Currency: INR, Rs, Rs., ₹  (case-insensitive)
    final amountPattern = RegExp(r'(?:INR|Rs\.?|₹)\s*([\d,]+\.\d{2})', caseSensitive: false);
    //  Date: dd-MMM-yy  (e.g. 04-Jun-26, 13-May-26)
    final datePattern = RegExp(r'on\s+(\d{2}-[A-Za-z]{3}-\d{2})');

    // ── Pattern 1: Credit Card Alert ──────────────────────────────────────────
    //  "ICICI Bank Credit Card XX1008 debited for INR 40.00 on 04-Jun-26 for UPI-652117366854-TEA CUBE."
    final ccCardMatch = RegExp(r'Credit\s+Card\s+(XX?\d{3,6})', caseSensitive: false).firstMatch(body);
    final ccAmountMatch = amountPattern.firstMatch(body);
    final ccUpiMatch = RegExp(r'UPI[-:]\s*(\d{6,15})', caseSensitive: false).firstMatch(body);
    // Merchant: everything after "UPI-digits-" up to the first literal period
    // This prevents trailing bank text ("To dispute call...") from leaking in
    final ccMerchantMatch = RegExp(r'UPI-\d+-([^.]+)', caseSensitive: false).firstMatch(body);
    final ccDateMatch = datePattern.firstMatch(body);

    if (ccCardMatch != null && ccAmountMatch != null && ccUpiMatch != null) {
      final card = ccCardMatch.group(1) ?? 'XXXXXX';
      final amount = ccAmountMatch.group(1)?.replaceAll(',', '') ?? '0.00';
      final upi = ccUpiMatch.group(1) ?? '';
      final merchant = ccMerchantMatch != null
          ? ccMerchantMatch.group(1)?.trim() ?? 'Unknown'
          : 'Unknown';
      final txnDate = ccDateMatch != null ? _parseSmsDate(ccDateMatch.group(1)!) : null;

      debugPrint('[SMS Parser] CC Match → card=$card amount=$amount upi=$upi merchant=$merchant date=$txnDate');

      return TransactionNotification(
        transactionId: 'txn-sms-${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
        merchant: merchant,
        upiRefId: upi,
        cardMasked: card,
        action: 'categorize',
        transactionDate: txnDate,
      );
    }

    // ── Pattern 2: Debit/Account SMS Alert ─────────────────────────────────────
    //  "ICICI Bank Acct XX423 debited for Rs 267.00 on 13-May-26; NIDHIN NATH T P credited. UPI:649918293649."
    final smsAcctMatch = RegExp(r'Acct\s+(XX?\d{3,6})', caseSensitive: false).firstMatch(body);
    final smsAmountMatch = amountPattern.firstMatch(body);
    final smsUpiMatch = RegExp(r'UPI[:\s]+(\d{6,15})', caseSensitive: false).firstMatch(body);
    final smsMerchantMatch = RegExp(r';\s*(.+?)\s+credited', caseSensitive: false).firstMatch(body);
    final smsDateMatch = datePattern.firstMatch(body);

    if (smsAcctMatch != null && smsAmountMatch != null && smsUpiMatch != null) {
      final card = smsAcctMatch.group(1) ?? 'XX000';
      final amount = smsAmountMatch.group(1)?.replaceAll(',', '') ?? '0.00';
      final upi = smsUpiMatch.group(1) ?? '';
      final merchant = smsMerchantMatch != null
          ? smsMerchantMatch.group(1)?.trim() ?? 'Unknown'
          : 'Unknown';
      final txnDate = smsDateMatch != null ? _parseSmsDate(smsDateMatch.group(1)!) : null;

      debugPrint('[SMS Parser] Debit Match → card=$card amount=$amount upi=$upi merchant=$merchant date=$txnDate');

      return TransactionNotification(
        transactionId: 'txn-sms-${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
        merchant: merchant,
        upiRefId: upi,
        cardMasked: card,
        action: 'categorize',
        transactionDate: txnDate,
      );
    }

    debugPrint('[SMS Parser] No pattern matched for body: ${body.substring(0, body.length.clamp(0, 80))}…');
    return null;
  }

  /// Parse an ICICI-style date string "dd-MMM-yy" (e.g. "04-Jun-26") into a [DateTime].
  /// Handles 2-digit year safely: values 0–49 → 2000s, 50–99 → 1900s.
  static DateTime? _parseSmsDate(String raw) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };

    try {
      final parts = raw.split('-'); // ["04", "Jun", "26"]
      if (parts.length != 3) return null;

      final day = int.parse(parts[0]);
      final month = months[parts[1].toLowerCase()];
      final yearShort = int.parse(parts[2]);

      if (month == null) return null;

      // 2-digit year pivot: 00–49 → 2000–2049, 50–99 → 1950–1999
      final year = yearShort < 50 ? 2000 + yearShort : 1900 + yearShort;

      return DateTime(year, month, day);
    } catch (e) {
      debugPrint('[SMS Parser] Date parse error for "$raw": $e');
      return null;
    }
  }

  /// Write the transaction to the backend, fallback to SharedPreferences cache if offline
  static Future<void> saveTransactionToBackendOrCache(TransactionNotification txn, String rawMessage) async {
    // 1. Immediately cache the transaction locally to ensure offline session caching persists instantly
    await _cacheTransactionLocally(txn, rawMessage);

    try {
      final client = FinanceApiClient();
      await client.createTransaction(
        upiRefId: txn.upiRefId,
        amount: double.parse(txn.amount),
        merchant: txn.merchant,
        cardMasked: txn.cardMasked,
        rawMessage: rawMessage,
        source: 'sms',
        transactionDate: txn.transactionDate,
      );
      // 2. Remove the transaction from the cache now that the write request succeeded
      await _removeTransactionFromCache(txn.upiRefId);
      debugPrint('[SMS Background] Transaction written to backend and removed from cache: ${txn.upiRefId}');
    } catch (e) {
      debugPrint('[SMS Background] Failed to write to backend: $e. Transaction remains in local cache.');
      // Do NOT remove from the local cache if a TimeoutException or any other error/status failure occurs.
    }
  }

  /// Write transaction details locally to SharedPreferences for retry on app boot
  static Future<void> _cacheTransactionLocally(TransactionNotification txn, String rawMessage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('offline_transactions_cache') ?? '[]';
      final List<dynamic> list = jsonDecode(cachedStr);
      
      // Check if the UPI Ref ID already exists in the cache to avoid duplicates
      final exists = list.any((item) => item['upi_ref_id'] == txn.upiRefId);
      if (!exists) {
        list.add({
          'upi_ref_id': txn.upiRefId,
          'amount': txn.amount,
          'merchant': txn.merchant,
          'card_masked': txn.cardMasked,
          'raw_message': rawMessage,
          'transaction_id': txn.transactionId,
          'action': txn.action,
          'transaction_date': txn.transactionDate?.toIso8601String(),
        });
        await prefs.setString('offline_transactions_cache', jsonEncode(list));
        debugPrint('[SMS Cache] Cached transaction locally: ${txn.upiRefId}');
      } else {
        debugPrint('[SMS Cache] Transaction already cached: ${txn.upiRefId}');
      }
    } catch (e) {
      debugPrint('[SMS Cache] Error caching transaction: $e');
    }
  }

  /// Remove a transaction from SharedPreferences cache once synced successfully
  static Future<void> _removeTransactionFromCache(String upiRefId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('offline_transactions_cache') ?? '[]';
      final List<dynamic> list = jsonDecode(cachedStr);
      final initialLength = list.length;
      list.removeWhere((item) => item['upi_ref_id'] == upiRefId);
      if (list.length < initialLength) {
        await prefs.setString('offline_transactions_cache', jsonEncode(list));
        debugPrint('[SMS Cache] Removed transaction from cache: $upiRefId');
      }
    } catch (e) {
      debugPrint('[SMS Cache] Error removing transaction from cache: $e');
    }
  }

  /// Retries sending any cached offline transactions to the backend
  static Future<void> processOfflineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('offline_transactions_cache');
      if (cachedStr == null || cachedStr == '[]') return;

      final List<dynamic> list = jsonDecode(cachedStr);
      debugPrint('[SMS Cache] Retry syncing ${list.length} transaction(s)...');
      
      final List<dynamic> remaining = [];
      final client = FinanceApiClient();

      for (final item in list) {
        try {
          final cachedDateStr = item['transaction_date'] as String?;
          final cachedDate = cachedDateStr != null ? DateTime.tryParse(cachedDateStr) : null;
          await client.createTransaction(
            upiRefId: item['upi_ref_id'],
            amount: double.parse(item['amount']),
            merchant: item['merchant'],
            cardMasked: item['card_masked'],
            rawMessage: item['raw_message'],
            source: 'sms',
            transactionDate: cachedDate,
          );
          debugPrint('[SMS Cache] Synced transaction: ${item['upi_ref_id']}');
        } catch (e) {
          debugPrint('[SMS Cache] Retry failed for: ${item['upi_ref_id']}: $e');
          remaining.add(item);
        }
      }

      await prefs.setString('offline_transactions_cache', jsonEncode(remaining));
    } catch (e) {
      debugPrint('[SMS Cache] Error running cache sync: $e');
    }
  }

  /// Display a local notification with transaction payload
  static Future<void> showLocalNotification(TransactionNotification txn) async {
    final payload = jsonEncode({
      'transaction_id': txn.transactionId,
      'amount': txn.amount,
      'merchant': txn.merchant,
      'upi_ref_id': txn.upiRefId,
      'card_masked': txn.cardMasked,
      'action': txn.action,
    });

    const androidChannel = AndroidNotificationDetails(
      'transaction_interceptor_channel',
      'Transaction Alerts',
      channelDescription: 'Notifications for on-device SMS intercepted transactions.',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: true,
    );

    const platformDetails = NotificationDetails(android: androidChannel);

    await _localNotifications.show(
      txn.upiRefId.hashCode, // unique notification ID
      'New Transaction Intercepted',
      '₹${txn.amount} spent at ${txn.merchant}',
      platformDetails,
      payload: payload,
    );
  }
}
