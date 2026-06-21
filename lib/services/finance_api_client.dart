import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FinanceApiException implements Exception {
  final String message;
  final int? statusCode;

  FinanceApiException(this.message, [this.statusCode]);

  @override
  String toString() => "FinanceApiException: $message (Code: $statusCode)";
}

class FinanceApiClient {
  // Use 10.0.2.2 for Android emulator testing against local backend
  // In production, this would be your remote backend URL
  static const String _baseUrl = 'https://finmate-backend-34vb.onrender.com';
  static const Duration _timeout = Duration(seconds: 60);
  
  // For the MVP, we use a dummy device ID to identify the user
  static const String _deviceId = 'dev-device-123';

  final http.Client _client;

  FinanceApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// Checks the backend health status to wake up the container.
  Future<bool> checkBackendHealth() async {
    try {
      final response = await _request('GET', '/health');
      return response['status'] == 'ok' || response['status'] == 'healthy';
    } catch (e) {
      debugPrint('[API HEALTH] Health check ping failed: $e');
      return false;
    }
  }

  /// Fetches the dashboard summary metrics.
  Future<Map<String, dynamic>> fetchDashboardSummary() async {
    return _request('GET', '/dashboard/summary');
  }

  /// Fetches all transactions from the backend.
  Future<Map<String, dynamic>> fetchTransactions() async {
    return _request('GET', '/transactions');
  }

  /// Categorizes a transaction on the backend.
  /// Returns the updated Remaining Limit.
  Future<Map<String, dynamic>> categorizeTransaction(String transactionId, String category) async {
    return _request(
      'POST',
      '/transactions/categorize/$transactionId',
      body: {'category': category},
    );
  }

  /// Flags a transaction as ignored on the backend using the unique UPI Ref ID.
  Future<Map<String, dynamic>> ignoreTransaction(String upiRefId) async {
    return _request(
      'POST',
      '/transactions/ignore/$upiRefId',
    );
  }

  /// Creates a new transaction parsed by the local SMS receiver on the backend.
  Future<Map<String, dynamic>> createTransaction({
    required String upiRefId,
    required double amount,
    required String merchant,
    required String cardMasked,
    required String rawMessage,
    String source = 'sms',
    DateTime? transactionDate,
  }) async {
    final payload = <String, dynamic>{
      'upi_ref_id': upiRefId,
      'amount': amount,
      'merchant': merchant,
      'card_masked': cardMasked,
      'raw_message': rawMessage,
      'source': source,
      'transaction_type': 'debit',
    };
    if (transactionDate != null) {
      payload['transaction_date'] = transactionDate.toIso8601String();
    }

    // Structural elements validation check
    final String? checkCardId = cardMasked.isEmpty ? null : cardMasked;
    final double checkAmount = amount;
    final String? checkMerchant = merchant.isEmpty ? null : merchant;
    const String checkTxnType = 'debit';
    final String? checkUpiRefId = upiRefId.isEmpty ? null : upiRefId;

    if (checkCardId == null ||
        checkAmount <= 0 ||
        checkMerchant == null ||
        checkUpiRefId == null) {
      debugPrint('[CRITICAL VALIDATION ALERT] Missing or empty structural elements required by backend schema: card_id/card_masked = $checkCardId, amount = $checkAmount, merchant = $checkMerchant, transaction_type = $checkTxnType, upi_ref_id = $checkUpiRefId');
    }

    debugPrint('[API WRITE] Sending transaction payload to Render: ${jsonEncode(payload)}');

    try {
      final uri = Uri.parse('$_baseUrl/transactions');
      final headers = {
        'Content-Type': 'application/json',
        'x-device-id': _deviceId,
      };

      final response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);

      debugPrint('[API WRITE RESPONSE] Server responded with status code: ${response.statusCode}');
      debugPrint('[API WRITE BODY] Server payload body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw FinanceApiException(
          'Failed to create transaction: Server responded with status code ${response.statusCode}',
          response.statusCode,
        );
      }

      return _handleResponse(response);
    } catch (e) {
      debugPrint('[API WRITE ERROR] Failed writing transaction payload to Render: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(String method, String endpoint, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      'x-device-id': _deviceId,
    };

    try {
      http.Response response;
      
      if (method == 'GET') {
        response = await _client.get(uri, headers: headers).timeout(_timeout);
      } else if (method == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } else {
        throw UnsupportedError('HTTP method $method not supported');
      }

      return _handleResponse(response);
      
    } on SocketException {
      throw FinanceApiException('No Internet connection. Please check your network.', 0);
    } on TimeoutException {
      throw FinanceApiException('Request timed out after ${_timeout.inSeconds} seconds.', 408);
    } on FormatException {
      throw FinanceApiException('Bad response format from server.', 500);
    } catch (e) {
      throw FinanceApiException('An unexpected error occurred: $e', 500);
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } 

    String errorMessage = 'Server error';
    try {
      final errorBody = jsonDecode(response.body);
      if (errorBody is Map && errorBody.containsKey('detail')) {
        errorMessage = errorBody['detail'];
      }
    } catch (_) {
      // Ignored: body is not json
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw FinanceApiException('Unauthorized: Please authenticate again.', response.statusCode);
    } else if (response.statusCode == 404) {
      throw FinanceApiException('Resource not found: $errorMessage', response.statusCode);
    } else {
      throw FinanceApiException('Error: $errorMessage', response.statusCode);
    }
  }
}
