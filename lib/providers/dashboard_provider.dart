/// Dashboard state provider.
///
/// Manages card data, computed net worth, and syncs with the FastAPI backend.
/// Uses optimistic UI updates with silent background refresh to avoid
/// loading spinner flashes during categorization.
library;

import 'package:flutter/material.dart';
import 'package:personal_finance_assistant/models/card_model.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/services/finance_api_client.dart';

import 'package:shared_preferences/shared_preferences.dart';

class DashboardProvider extends ChangeNotifier {
  final FinanceApiClient _apiClient = FinanceApiClient();

  bool _isLoading = false;
  bool _isCategorizing = false;
  String? _errorMessage;
  
  double _savingsBalance = 0;
  List<CardModel> _cards = [];
  final List<Transaction> _recentTransactions = [];

  double _monthlyBudget = 50000.0;

  bool get isLoading => _isLoading;
  bool get isCategorizing => _isCategorizing;
  String? get errorMessage => _errorMessage;
  double get savingsBalance => _savingsBalance;
  List<CardModel> get cards => _cards;
  List<Transaction> get recentTransactions => _recentTransactions;

  double get monthlyBudget => _monthlyBudget;

  Future<void> initBudget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _monthlyBudget = prefs.getDouble('monthly_budget') ?? 50000.0;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load budget: $e');
    }
  }

  Future<void> setMonthlyBudget(double amount) async {
    _monthlyBudget = amount;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('monthly_budget', amount);
    } catch (e) {
      debugPrint('Failed to save budget: $e');
    }
  }

  List<Transaction> get currentMonthTransactions {
    final now = DateTime.now();
    return _recentTransactions.where((txn) =>
        txn.transactedAt.month == now.month &&
        txn.transactedAt.year == now.year).toList();
  }

  List<Transaction> get uncategorized {
    return currentMonthTransactions.where((txn) {
      final cat = txn.category.toLowerCase().trim();
      return cat == 'uncategorized' || cat.isEmpty;
    }).toList();
  }

  double get totalExpenses {
    return currentMonthTransactions.fold<double>(
        0.0, (sum, txn) => (txn.transactionType == 'credit' || txn.isRefund)
            ? sum - txn.amount
            : sum + txn.amount);
  }

  double get remainingBudget => _monthlyBudget - totalExpenses;

  double get usedCredit {
    return currentMonthTransactions
        .where((txn) => txn.cardId == 'XX1008')
        .fold<double>(0.0, (sum, txn) => sum + txn.amount);
  }

  double get totalCreditLimit => 90000.0;

  double get remainingCredit => totalCreditLimit - usedCredit;

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
  /// Guarded against re-entrancy to prevent infinite loops when multiple
  /// screens/listeners trigger this on the same notifyListeners() cycle.
  Future<void> loadDashboard() async {
    if (_isLoading) return; // Re-entrancy guard
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        _monthlyBudget = prefs.getDouble('monthly_budget') ?? 50000.0;
      } catch (e) {
        debugPrint('Failed to load budget in loadDashboard: $e');
      }

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

      // Lock: retain any locally processing/updating transaction to prevent backend overwriting
      final processingTxns = _recentTransactions.where((t) => t.isProcessing).toList();

      _recentTransactions.clear();
      for (final parsed in parsedTransactionsList) {
        final lockIdx = processingTxns.indexWhere((pt) => pt.id == parsed.id || pt.upiRefId == parsed.upiRefId);
        if (lockIdx != -1) {
          _recentTransactions.add(processingTxns[lockIdx]);
        } else {
          _recentTransactions.add(parsed);
        }
      }

      // Also retain any processing items that might not have returned in parsed list yet
      for (final pt in processingTxns) {
        if (!_recentTransactions.any((t) => t.id == pt.id || t.upiRefId == pt.upiRefId)) {
          _recentTransactions.add(pt);
        }
      }

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

  /// Silent refresh: re-fetches transactions from the backend WITHOUT
  /// setting _isLoading = true, so the UI doesn't flash or jump.
  Future<void> _silentRefresh() async {
    try {
      final txnData = await _apiClient.fetchTransactions();
      final List<dynamic> txList = txnData['transactions'] ?? [];
      final parsedTransactionsList = txList
          .map((jsonTx) => Transaction.fromJson(jsonTx as Map<String, dynamic>))
          .toList();

      // Lock: retain any locally processing/updating transaction to prevent backend overwriting
      final processingTxns = _recentTransactions.where((t) => t.isProcessing).toList();

      _recentTransactions.clear();
      for (final parsed in parsedTransactionsList) {
        final lockIdx = processingTxns.indexWhere((pt) => pt.id == parsed.id || pt.upiRefId == parsed.upiRefId);
        if (lockIdx != -1) {
          _recentTransactions.add(processingTxns[lockIdx]);
        } else {
          _recentTransactions.add(parsed);
        }
      }

      // Also retain any processing items that might not have returned in parsed list yet
      for (final pt in processingTxns) {
        if (!_recentTransactions.any((t) => t.id == pt.id || t.upiRefId == pt.upiRefId)) {
          _recentTransactions.add(pt);
        }
      }

      debugPrint('[API SILENT REFRESH] Fetched ${parsedTransactionsList.length} rows without loading flash.');
      notifyListeners();
    } catch (e) {
      debugPrint('[API SILENT REFRESH] Failed: $e');
      // Silent refresh failures are non-fatal — the optimistic state is still valid
    }
  }

  /// Permanently deletes a transaction locally and on the backend.
  Future<bool> deleteTransaction(String transactionId) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final idx = _recentTransactions.indexWhere((t) => t.id == transactionId);
      if (idx != -1) {
        final txn = _recentTransactions[idx];
        _recentTransactions.removeAt(idx);
        notifyListeners();

        if (!txn.id.startsWith('txn-')) {
          await _apiClient.deleteTransaction(transactionId);
        }
      }

      await _silentRefresh();
      return true;
    } on FinanceApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = "Failed to delete transaction: $e";
      return false;
    } finally {
      notifyListeners();
    }
  }

  /// Categorizes multiple transactions at once, updating state optimistically and syncing with backend.
  Future<bool> batchCategorizeTransactions(List<String> transactionIds, String category) async {
    if (transactionIds.isEmpty) return false;

    // 1. Optimistic UI update: change category for all selected transactions
    for (int i = 0; i < _recentTransactions.length; i++) {
      if (transactionIds.contains(_recentTransactions[i].id)) {
        _recentTransactions[i] = _recentTransactions[i].copyWith(
          category: category,
          isProcessing: true,
        );
      }
    }
    _errorMessage = null;
    notifyListeners();

    try {
      final realIds = <String>[];
      for (final id in transactionIds) {
        if (id.startsWith('txn-')) {
          final txn = _recentTransactions.firstWhere((t) => t.id == id);
          final createRes = await _apiClient.createTransaction(
            upiRefId: txn.upiRefId,
            amount: txn.amount,
            merchant: txn.merchant ?? 'Unknown',
            cardMasked: txn.cardId,
            rawMessage: 'App intercepted transaction categorized manually',
            transactionDate: txn.transactedAt,
            category: category,
          );
          final realId = createRes['id'] as String;
          realIds.add(realId);

          final idx = _recentTransactions.indexWhere((t) => t.id == id);
          if (idx != -1) {
            _recentTransactions[idx] = _recentTransactions[idx].copyWith(id: realId);
          }
        } else {
          realIds.add(id);
        }
      }

      if (realIds.isNotEmpty) {
        await _apiClient.batchCategorize(
          transactionIds: realIds,
          category: category,
        );
      }

      for (int i = 0; i < _recentTransactions.length; i++) {
        if (realIds.contains(_recentTransactions[i].id)) {
          _recentTransactions[i] = _recentTransactions[i].copyWith(
            isProcessing: false,
          );
        }
      }
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 600));
      await _silentRefresh();
      return true;
    } catch (e) {
      debugPrint('[BATCH CATEGORIZE] Failed: $e');
      await _silentRefresh();
      return false;
    } finally {
      notifyListeners();
    }
  }

  /// Returns true on success, false on failure. Callers can use this
  /// to decide whether to pop the modal or show an error.
  Future<bool> categorizeTransaction(String transactionId, String category) async {
    if (_isCategorizing) return false;
    _isCategorizing = true;

    final idx = _recentTransactions.indexWhere((t) => t.id == transactionId);
    if (idx == -1) {
      _isCategorizing = false;
      return false;
    }

    final txn = _recentTransactions[idx];
    final isTempId = transactionId.startsWith('txn-');
    final oldCategory = txn.category;

    // Optimistic UI update — apply locally FIRST, then notify
    _recentTransactions[idx] = txn.copyWith(
      category: category,
      isProcessing: true,
    );
    _errorMessage = null;
    notifyListeners();

    try {
      final String realId;
      if (isTempId) {
        // Create/fetch on backend first to obtain the real database UUID (idempotent based on upiRefId)
        final createResponse = await _apiClient.createTransaction(
          upiRefId: txn.upiRefId,
          amount: txn.amount,
          merchant: txn.merchant ?? 'Unknown',
          cardMasked: txn.cardId,
          rawMessage: 'App intercepted transaction categorized manually',
          transactionDate: txn.transactedAt,
        );
        realId = createResponse['id'];

        // Update local item ID to the real database UUID
        final idxUpdated = _recentTransactions.indexWhere((t) => t.upiRefId == txn.upiRefId);
        if (idxUpdated != -1) {
          _recentTransactions[idxUpdated] = _recentTransactions[idxUpdated].copyWith(
            id: realId,
          );
        }
      } else {
        realId = transactionId;
      }

      await _apiClient.categorizeTransaction(realId, category);
      
      // Set local item processing flag to false as write is verified
      final idxUpdated = _recentTransactions.indexWhere((t) => t.id == realId || t.upiRefId == txn.upiRefId);
      if (idxUpdated != -1) {
        _recentTransactions[idxUpdated] = _recentTransactions[idxUpdated].copyWith(
          isProcessing: false,
        );
      }
      notifyListeners();

      // Write-verification delay before silent background refresh
      await Future.delayed(const Duration(milliseconds: 800));
      await _silentRefresh();
      return true;
    } on FinanceApiException catch (e) {
      // Revert optimistic update
      final idxUpdated = _recentTransactions.indexWhere((t) => t.upiRefId == txn.upiRefId);
      if (idxUpdated != -1) {
        _recentTransactions[idxUpdated] = _recentTransactions[idxUpdated].copyWith(
          category: oldCategory,
          isProcessing: false,
        );
      }
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      // Revert optimistic update
      final idxUpdated = _recentTransactions.indexWhere((t) => t.upiRefId == txn.upiRefId);
      if (idxUpdated != -1) {
        _recentTransactions[idxUpdated] = _recentTransactions[idxUpdated].copyWith(
          category: oldCategory,
          isProcessing: false,
        );
      }
      _errorMessage = "Failed to categorize: $e";
      notifyListeners();
      return false;
    } finally {
      _isCategorizing = false;
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
  /// Returns true on success, false on failure.
  Future<bool> addAndCategorizeTransaction({
    required String upiRefId,
    required double amount,
    required String merchant,
    required String category,
    String? cardMasked,
    DateTime? transactionDate,
  }) async {
    final existingIdx = _recentTransactions.indexWhere((t) => t.upiRefId == upiRefId);

    if (existingIdx != -1) {
      final txn = _recentTransactions[existingIdx];
      return categorizeTransaction(txn.id, category);
    } else {
      final tempId = 'txn-${DateTime.now().millisecondsSinceEpoch}';
      final cardToUse = cardMasked ?? (primaryCard?.cardMasked ?? 'XX4326');
      final dateToUse = transactionDate ?? DateTime.now();

      // Create local temporary transaction
      final newTxn = Transaction(
        id: tempId,
        cardId: cardToUse,
        upiRefId: upiRefId,
        amount: amount,
        merchant: merchant,
        category: category,
        transactedAt: dateToUse,
        isProcessing: false,
      );

      _recentTransactions.insert(0, newTxn);

      final success = await categorizeTransaction(tempId, category);

      if (!success) {
        // If it failed, remove it from the list
        _recentTransactions.removeWhere((t) => t.upiRefId == upiRefId);
        notifyListeners();
      }
      return success;
    }
  }

  /// Adds a manually created transaction from the app UI.
  Future<bool> addManualTransaction({
    required double amount,
    required String merchant,
    required DateTime transactionDate,
    required String category,
    required String paymentMode,
    required String transactionType,
  }) async {
    final upiRefId = 'manual-${DateTime.now().millisecondsSinceEpoch}';
    final tempId = 'txn-${DateTime.now().millisecondsSinceEpoch}';

    final newTxn = Transaction(
      id: tempId,
      cardId: paymentMode,
      upiRefId: upiRefId,
      amount: amount,
      merchant: merchant,
      category: category,
      transactionType: transactionType,
      transactedAt: transactionDate,
      source: 'manual',
      isProcessing: true,
    );

    _recentTransactions.insert(0, newTxn);
    notifyListeners();

    try {
      final createResponse = await _apiClient.createTransaction(
        upiRefId: upiRefId,
        amount: amount,
        merchant: merchant,
        cardMasked: paymentMode,
        rawMessage: 'Manual transaction added via app',
        source: 'manual',
        transactionDate: transactionDate,
        category: category,
        transactionType: transactionType,
      );

      final realId = createResponse['id'] ?? tempId;

      final idxUpdated = _recentTransactions.indexWhere((t) => t.upiRefId == upiRefId);
      if (idxUpdated != -1) {
        _recentTransactions[idxUpdated] = _recentTransactions[idxUpdated].copyWith(
          id: realId,
          isProcessing: false,
        );
      }
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));
      await _silentRefresh();
      return true;
    } catch (e) {
      _recentTransactions.removeWhere((t) => t.upiRefId == upiRefId);
      _errorMessage = "Failed to add manual transaction: $e";
      notifyListeners();
      return false;
    }
  }
}
