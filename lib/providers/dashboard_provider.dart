/// Dashboard state provider.
///
/// Manages card data, computed net worth, and syncs with the FastAPI backend.
/// Uses optimistic UI updates with silent background refresh to avoid
/// loading spinner flashes during categorization.
library;

import 'package:flutter/material.dart';
import 'package:personal_finance_assistant/models/card_model.dart';
import 'package:personal_finance_assistant/models/transaction.dart';
import 'package:personal_finance_assistant/models/category_budget.dart';
import 'package:personal_finance_assistant/constants/categories.dart';
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
  final Map<String, double> _categoryBudgetLimits = {};

  bool get isLoading => _isLoading;
  bool get isCategorizing => _isCategorizing;
  String? get errorMessage => _errorMessage;
  double get savingsBalance => _savingsBalance;
  List<CardModel> get cards => _cards;

  /// Comparator prioritizing uncategorized transactions first, then most recent first.
  static int compareTransactionsPrioritized(Transaction a, Transaction b) {
    final aCat = a.category.trim().toLowerCase();
    final bCat = b.category.trim().toLowerCase();
    final aIsUncategorized = aCat == 'uncategorized' || aCat.isEmpty;
    final bIsUncategorized = bCat == 'uncategorized' || bCat.isEmpty;

    if (aIsUncategorized && !bIsUncategorized) return -1;
    if (!aIsUncategorized && bIsUncategorized) return 1;

    // Secondary: Most recent first
    return b.transactedAt.compareTo(a.transactedAt);
  }

  /// All transactions sorted with uncategorized first, followed by most recent first.
  List<Transaction> get sortedTransactions {
    final list = List<Transaction>.from(_recentTransactions);
    list.sort(compareTransactionsPrioritized);
    return list;
  }

  /// Prioritized list of transactions with uncategorized items pinned to the top.
  List<Transaction> get recentTransactions => sortedTransactions;

  double get monthlyBudget => _monthlyBudget;
  Map<String, double> get categoryBudgetLimits => Map.unmodifiable(_categoryBudgetLimits);

  /// Dynamically computes category budgets, remaining amounts, and percentages.
  /// Automatically recomputes whenever transactions are added, edited, or deleted.
  Map<String, CategoryBudget> get categoryBudgets {
    final Map<String, CategoryBudget> result = {};
    final txns = currentMonthTransactions;

    // Initialize spent map for all 15 master categories
    final Map<String, double> categorySpents = {};
    for (final cat in kExpenseCategories) {
      categorySpents[cat.id] = 0.0;
    }

    for (final txn in txns) {
      final rawCat = txn.category.toLowerCase().trim();
      final resolved = (rawCat == 'transportation' || rawCat == 'transport') ? 'transportion' : rawCat;
      final targetKey = categorySpents.containsKey(resolved) ? resolved : 'uncategorized';
      final isCredit = txn.transactionType == 'credit' || txn.isRefund;
      final signedAmount = isCredit ? -txn.amount : txn.amount;
      categorySpents[targetKey] = (categorySpents[targetKey] ?? 0.0) + signedAmount;
    }

    for (final cat in kExpenseCategories) {
      final limit = _categoryBudgetLimits[cat.id] ?? 0.0;
      final spent = categorySpents[cat.id] ?? 0.0;
      final remaining = limit - spent;
      final double percentage;
      if (limit > 0) {
        percentage = ((spent / limit) * 100.0).clamp(0.0, 999.0);
      } else {
        percentage = spent > 0 ? 100.0 : 0.0;
      }

      result[cat.id] = CategoryBudget(
        category: cat.id,
        budgetLimit: limit,
        spent: spent,
        remaining: remaining,
        percentageUsed: percentage,
      );
    }

    return result;
  }

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
    final list = _recentTransactions.where((txn) =>
        txn.transactedAt.month == now.month &&
        txn.transactedAt.year == now.year).toList();
    list.sort(compareTransactionsPrioritized);
    return list;
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

      _recentTransactions.sort(compareTransactionsPrioritized);

      // Hydrate category budgets alongside monthly dashboard hydration
      try {
        final now = DateTime.now();
        final budgetData = await _apiClient.getCategoryBudgets(now.month, now.year);
        final List<dynamic> catList = budgetData['categories'] ?? [];
        for (final item in catList) {
          if (item is Map<String, dynamic>) {
            final catName = (item['category'] as String? ?? '').toLowerCase().trim();
            final resolved = (catName == 'transportation' || catName == 'transport') ? 'transportion' : catName;
            final limit = (item['budget_limit'] as num?)?.toDouble() ?? 0.0;
            _categoryBudgetLimits[resolved] = limit;
          }
        }
      } catch (e) {
        debugPrint('[DashboardProvider] Warning fetching category budgets during hydration: $e');
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

      _recentTransactions.sort(compareTransactionsPrioritized);

      // Silently sync category budgets
      try {
        final now = DateTime.now();
        final budgetData = await _apiClient.getCategoryBudgets(now.month, now.year);
        final List<dynamic> catList = budgetData['categories'] ?? [];
        for (final item in catList) {
          if (item is Map<String, dynamic>) {
            final catName = (item['category'] as String? ?? '').toLowerCase().trim();
            final resolved = (catName == 'transportation' || catName == 'transport') ? 'transportion' : catName;
            final limit = (item['budget_limit'] as num?)?.toDouble() ?? 0.0;
            _categoryBudgetLimits[resolved] = limit;
          }
        }
      } catch (_) {}

      debugPrint('[API SILENT REFRESH] Fetched ${parsedTransactionsList.length} rows without loading flash.');
      notifyListeners();
    } catch (e) {
      debugPrint('[API SILENT REFRESH] Failed: $e');
      // Silent refresh failures are non-fatal — the optimistic state is still valid
    }
  }

  /// Explicitly fetches category budgets for a specific month and year.
  Future<void> fetchCategoryBudgets({int? month, int? year}) async {
    final now = DateTime.now();
    final targetMonth = month ?? now.month;
    final targetYear = year ?? now.year;

    try {
      final res = await _apiClient.getCategoryBudgets(targetMonth, targetYear);
      final List<dynamic> catList = res['categories'] ?? [];
      for (final item in catList) {
        if (item is Map<String, dynamic>) {
          final catName = (item['category'] as String? ?? '').toLowerCase().trim();
          final resolved = (catName == 'transportation' || catName == 'transport') ? 'transportion' : catName;
          final limit = (item['budget_limit'] as num?)?.toDouble() ?? 0.0;
          _categoryBudgetLimits[resolved] = limit;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[DashboardProvider] Failed to fetch category budgets: $e');
    }
  }

  /// Saves updated category budgets to backend and updates local state optimistically.
  Future<bool> saveCategoryBudgets(int month, int year, Map<String, double> budgets) async {
    try {
      // Optimistic local update
      budgets.forEach((cat, limit) {
        final resolved = (cat == 'transportation' || cat == 'transport') ? 'transportion' : cat;
        _categoryBudgetLimits[resolved] = limit;
      });
      notifyListeners();

      await _apiClient.setCategoryBudgets(month, year, budgets);
      await fetchCategoryBudgets(month: month, year: year);
      return true;
    } catch (e) {
      debugPrint('[DashboardProvider] Failed to save category budgets: $e');
      _errorMessage = "Failed to save category budgets: $e";
      notifyListeners();
      return false;
    }
  }

  /// Fetches budget limits from the previous month to support "Auto-fill from Last Month".
  Future<Map<String, double>> fetchPreviousMonthBudgets({int? currentMonth, int? currentYear}) async {
    final now = DateTime.now();
    final cm = currentMonth ?? now.month;
    final cy = currentYear ?? now.year;
    final prevMonth = cm == 1 ? 12 : cm - 1;
    final prevYear = cm == 1 ? cy - 1 : cy;

    try {
      final res = await _apiClient.getCategoryBudgets(prevMonth, prevYear);
      final List<dynamic> catList = res['categories'] ?? [];
      final Map<String, double> prevBudgets = {};
      for (final item in catList) {
        if (item is Map<String, dynamic>) {
          final catName = (item['category'] as String? ?? '').toLowerCase().trim();
          final resolved = (catName == 'transportation' || catName == 'transport') ? 'transportion' : catName;
          final limit = (item['budget_limit'] as num?)?.toDouble() ?? 0.0;
          if (limit > 0) {
            prevBudgets[resolved] = limit;
          }
        }
      }
      return prevBudgets;
    } catch (e) {
      debugPrint('[DashboardProvider] Failed to fetch previous month budgets: $e');
      return {};
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
    _recentTransactions.sort(compareTransactionsPrioritized);
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
      _recentTransactions.sort(compareTransactionsPrioritized);
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

    // Optimistic UI update — apply locally FIRST, sort, then notify
    _recentTransactions[idx] = txn.copyWith(
      category: category,
      isProcessing: true,
    );
    _recentTransactions.sort(compareTransactionsPrioritized);
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
      _recentTransactions.sort(compareTransactionsPrioritized);
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
        _recentTransactions.sort(compareTransactionsPrioritized);
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
        _recentTransactions.sort(compareTransactionsPrioritized);
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
    _recentTransactions.sort(compareTransactionsPrioritized);
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
