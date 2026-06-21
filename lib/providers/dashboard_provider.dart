/// Dashboard state provider.
///
/// Manages card data, computed net worth, and syncs with the FastAPI backend.
library;

import 'package:flutter/material.dart';
import 'package:personal_finance_assistant/models/card_model.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/services/finance_api_client.dart';

class DashboardProvider extends ChangeNotifier {
  final FinanceApiClient _apiClient = FinanceApiClient();

  bool _isLoading = false;
  String? _errorMessage;
  
  double _savingsBalance = 0;
  List<CardModel> _cards = [];
  final List<Transaction> _recentTransactions = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  double get savingsBalance => _savingsBalance;
  List<CardModel> get cards => _cards;
  List<Transaction> get recentTransactions => _recentTransactions;

  /// Total Net Worth = Savings + Sum of Available Credit Limits
  double get totalNetWorth {
    final availableCredit = _cards.fold<double>(
      0,
      (sum, card) => sum + (card.availableLimit ?? 0),
    );
    return _savingsBalance + availableCredit;
  }

  /// Primary credit card (first active card).
  CardModel? get primaryCard =>
      _cards.isNotEmpty ? _cards.first : null;

  /// Load dashboard data using the API Client.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final summary = await _apiClient.fetchDashboardSummary();
      
      _savingsBalance = (summary['total_balance'] ?? 0.0).toDouble();
      final remainingLimit = (summary['remaining_limit'] ?? 0.0).toDouble();
      final totalLimit = (summary['total_limit'] ?? 90000.00).toDouble();
      final nextBillDate = DateTime.parse(summary['next_bill_date']);
      
      // Update cards based on summary
      if (_cards.isEmpty) {
        _cards = [
          CardModel(
            id: 'card-primary',
            userId: 'user-001',
            cardMasked: 'XX4326',
            cardType: 'credit_card',
            totalLimit: totalLimit,
            availableLimit: remainingLimit,
            billingCycleDay: nextBillDate.day,
          ),
        ];
      } else {
        _cards[0] = CardModel(
            id: _cards[0].id,
            userId: _cards[0].userId,
            cardMasked: _cards[0].cardMasked,
            cardType: _cards[0].cardType,
            totalLimit: totalLimit,
            availableLimit: remainingLimit,
            billingCycleDay: nextBillDate.day,
        );
      }

      // Populate recent transactions from the backend
      final txnData = await _apiClient.fetchTransactions();
      final List<dynamic> txList = txnData['transactions'] ?? [];
      final parsedTransactionsList = txList
          .map((jsonTx) => Transaction.fromJson(jsonTx as Map<String, dynamic>))
          .toList();

      _recentTransactions.clear();
      _recentTransactions.addAll(parsedTransactionsList);

      debugPrint('[API READ] Boot initialization fetched ${parsedTransactionsList.length} total history rows.');
    } on FinanceApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = "Failed to load dashboard: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update a transaction's category via API and sync local state.
  Future<void> categorizeTransaction(String transactionId, String category) async {
    final idx = _recentTransactions.indexWhere((t) => t.id == transactionId);
    if (idx == -1) return;

    // Optimistic UI update
    final oldCategory = _recentTransactions[idx].category;
    _recentTransactions[idx] = _recentTransactions[idx].copyWith(category: category);
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.categorizeTransaction(transactionId, category);
      final newRemainingLimit = response['remaining_limit'];
      
      // Sync card remaining limit if updated
      if (_cards.isNotEmpty && newRemainingLimit != null) {
        _cards[0] = CardModel(
          id: _cards[0].id,
          userId: _cards[0].userId,
          cardMasked: _cards[0].cardMasked,
          cardType: _cards[0].cardType,
          totalLimit: _cards[0].totalLimit,
          availableLimit: (newRemainingLimit as num).toDouble(),
          billingCycleDay: _cards[0].billingCycleDay,
        );
      }
    } on FinanceApiException catch (e) {
      // Revert optimistic update
      _recentTransactions[idx] = _recentTransactions[idx].copyWith(category: oldCategory);
      _errorMessage = e.message;
    } catch (e) {
      // Revert optimistic update
      _recentTransactions[idx] = _recentTransactions[idx].copyWith(category: oldCategory);
      _errorMessage = "Failed to categorize: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Flags a transaction as ignored locally and on the backend.
  Future<void> ignoreTransaction(String upiRefId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiClient.ignoreTransaction(upiRefId);
      final idx = _recentTransactions.indexWhere((t) => t.upiRefId == upiRefId);
      if (idx != -1) {
        _recentTransactions[idx] = _recentTransactions[idx].copyWith(category: 'ignored');
      }
    } on FinanceApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = "Failed to ignore transaction: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a new transaction or updates an existing one and categorizes it.
  Future<void> addAndCategorizeTransaction({
    required String upiRefId,
    required double amount,
    required String merchant,
    required String category,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final existingIdx = _recentTransactions.indexWhere((t) => t.upiRefId == upiRefId);

    if (existingIdx != -1) {
      final txn = _recentTransactions[existingIdx];
      _recentTransactions[existingIdx] = txn.copyWith(category: category);
      try {
        final response = await _apiClient.categorizeTransaction(txn.id, category);
        final newRemainingLimit = response['remaining_limit'];
        if (_cards.isNotEmpty && newRemainingLimit != null) {
          _cards[0] = CardModel(
            id: _cards[0].id,
            userId: _cards[0].userId,
            cardMasked: _cards[0].cardMasked,
            cardType: _cards[0].cardType,
            totalLimit: _cards[0].totalLimit,
            availableLimit: (newRemainingLimit as num).toDouble(),
            billingCycleDay: _cards[0].billingCycleDay,
          );
        }
      } catch (e) {
        _errorMessage = "Failed to categorize: $e";
      }
    } else {
      final newTxn = Transaction(
        id: 'txn-${DateTime.now().millisecondsSinceEpoch}',
        cardId: 'card-primary',
        upiRefId: upiRefId,
        amount: amount,
        merchant: merchant,
        category: category,
        transactedAt: DateTime.now(),
      );

      _recentTransactions.insert(0, newTxn);

      try {
        final response = await _apiClient.categorizeTransaction(newTxn.id, category);
        final newRemainingLimit = response['remaining_limit'];
        if (_cards.isNotEmpty && newRemainingLimit != null) {
          _cards[0] = CardModel(
            id: _cards[0].id,
            userId: _cards[0].userId,
            cardMasked: _cards[0].cardMasked,
            cardType: _cards[0].cardType,
            totalLimit: _cards[0].totalLimit,
            availableLimit: (newRemainingLimit as num).toDouble(),
            billingCycleDay: _cards[0].billingCycleDay,
          );
        }
      } catch (e) {
        debugPrint("Could not sync category to backend: $e");
      }
    }

    _isLoading = false;
    notifyListeners();
  }
}
