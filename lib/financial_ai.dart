import 'dart:math' as math;

import 'app_db.dart';
import 'models.dart';

class MoneyMapSnapshot {
  final int startMs;
  final int endMs;
  final Map<String, double> spendingAreas;
  final Map<String, double> spendingCategories;
  final Map<String, double> investmentCategories;
  final Map<String, double> investmentAreas;
  final double expenseTotal;
  final double investmentTotal;

  const MoneyMapSnapshot({
    required this.startMs,
    required this.endMs,
    required this.spendingAreas,
    required this.spendingCategories,
    required this.investmentCategories,
    required this.investmentAreas,
    required this.expenseTotal,
    required this.investmentTotal,
  });
}

class CoachInsight {
  final String kind;
  final String title;
  final String body;
  final double? value;

  const CoachInsight({
    required this.kind,
    required this.title,
    required this.body,
    this.value,
  });
}

class FinancialCoachSnapshot {
  final double currentExpense;
  final double projectedExpense;
  final double normalMonthlyExpense;
  final double potentialSaving;
  final String savingCategory;
  final String topInvestmentArea;
  final double topInvestmentShare;
  final int historyMonths;
  final List<CoachInsight> insights;

  const FinancialCoachSnapshot({
    required this.currentExpense,
    required this.projectedExpense,
    required this.normalMonthlyExpense,
    required this.potentialSaving,
    required this.savingCategory,
    required this.topInvestmentArea,
    required this.topInvestmentShare,
    required this.historyMonths,
    required this.insights,
  });
}

/// Local-first financial intelligence. It deliberately uses structured
/// transactions instead of sending raw SMS text to a cloud model.
class FinancialAiEngine {
  FinancialAiEngine._();
  static final FinancialAiEngine instance = FinancialAiEngine._();

  Future<MoneyMapSnapshot> moneyMap(int startMs, int endMs) async {
    final spendingCategories = await AppDb.instance.expenseByCategoryForPeriod(startMs, endMs);
    final expenses = await AppDb.instance.searchTransactions(
      type: 'expense',
      startMs: startMs,
      endMs: endMs,
      limit: 5000,
    );
    final investments = await AppDb.instance.searchTransactions(
      type: 'investment',
      startMs: startMs,
      endMs: endMs,
      limit: 3000,
    );

    final spendingAreas = <String, double>{};
    for (final tx in expenses) {
      final area = _spendingArea(tx);
      spendingAreas[area] = (spendingAreas[area] ?? 0) + tx.amount;
    }

    final investmentCategories = <String, double>{};
    final investmentAreas = <String, double>{};
    for (final tx in investments) {
      final category = tx.category.trim().isEmpty ? 'Other Investment' : tx.category.trim();
      investmentCategories[category] = (investmentCategories[category] ?? 0) + tx.amount;
      final area = _investmentArea(tx);
      investmentAreas[area] = (investmentAreas[area] ?? 0) + tx.amount;
    }

    final sortedSpendingAreas = _sortedMap(spendingAreas);
    final sortedInvestmentCategories = _sortedMap(investmentCategories);
    final sortedInvestmentAreas = _sortedMap(investmentAreas);
    final expenseTotal = expenses.fold<double>(0, (a, b) => a + b.amount);
    final investmentTotal = investments.fold<double>(0, (a, b) => a + b.amount);

    return MoneyMapSnapshot(
      startMs: startMs,
      endMs: endMs,
      spendingAreas: sortedSpendingAreas,
      spendingCategories: spendingCategories,
      investmentCategories: sortedInvestmentCategories,
      investmentAreas: sortedInvestmentAreas,
      expenseTotal: expenseTotal,
      investmentTotal: investmentTotal,
    );
  }

  Future<List<TxRecord>> transactionsForSpendingArea(String area, int startMs, int endMs) async {
    final rows = await AppDb.instance.searchTransactions(type: 'expense', startMs: startMs, endMs: endMs, limit: 5000);
    return rows.where((tx) => _spendingArea(tx) == area).toList();
  }

  Future<List<TxRecord>> transactionsForInvestmentArea(String area, int startMs, int endMs) async {
    final rows = await AppDb.instance.searchTransactions(type: 'investment', startMs: startMs, endMs: endMs, limit: 3000);
    return rows.where((tx) => _investmentArea(tx) == area).toList();
  }

  Future<FinancialCoachSnapshot> coachSnapshot() async {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final currentEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = math.max(1, now.day);

    final currentTotals = await AppDb.instance.totalsByTypeForPeriod(currentStart, currentEnd);
    final currentExpense = currentTotals['expense'] ?? 0.0;
    final projectedExpense = currentExpense <= 0 ? 0.0 : currentExpense / daysElapsed * daysInMonth;

    final historyExpenses = <double>[];
    final categoryHistory = <String, double>{};
    var historyMonths = 0;
    for (var back = 1; back <= 3; back++) {
      final startDate = DateTime(now.year, now.month - back, 1);
      final endDate = DateTime(now.year, now.month - back + 1, 1);
      final start = startDate.millisecondsSinceEpoch;
      final end = endDate.millisecondsSinceEpoch;
      final totals = await AppDb.instance.totalsByTypeForPeriod(start, end);
      final value = totals['expense'] ?? 0.0;
      if (value > 0) {
        historyExpenses.add(value);
        historyMonths++;
      }
      final cats = await AppDb.instance.expenseByCategoryForPeriod(start, end);
      for (final entry in cats.entries) {
        categoryHistory[entry.key] = (categoryHistory[entry.key] ?? 0) + entry.value;
      }
    }

    final normalMonthlyExpense = historyExpenses.isEmpty
        ? 0.0
        : historyExpenses.fold<double>(0, (a, b) => a + b) / historyExpenses.length;

    final currentCategories = await AppDb.instance.expenseByCategoryForPeriod(currentStart, currentEnd);
    final saving = _savingOpportunity(
      currentCategories: currentCategories,
      historyTotals: categoryHistory,
      historyMonths: historyMonths > 0 ? historyMonths : 1,
    );

    final monthMap = await moneyMap(currentStart, currentEnd);
    final investmentTop = monthMap.investmentAreas.isEmpty ? null : monthMap.investmentAreas.entries.first;
    final investmentShare = investmentTop == null || monthMap.investmentTotal <= 0
        ? 0.0
        : investmentTop.value / monthMap.investmentTotal;

    final insights = <CoachInsight>[];
    if (projectedExpense > 0) {
      if (normalMonthlyExpense > 0) {
        final deltaPct = ((projectedExpense - normalMonthlyExpense) / normalMonthlyExpense) * 100;
        if (deltaPct >= 10) {
          insights.add(CoachInsight(
            kind: 'forecast',
            title: 'Spending pace is above normal',
            body: 'At the current pace, this month may finish about ${deltaPct.abs().round()}% above your recent monthly average.',
            value: projectedExpense,
          ));
        } else if (deltaPct <= -10) {
          insights.add(CoachInsight(
            kind: 'forecast',
            title: 'Spending pace is below normal',
            body: 'At the current pace, this month may finish about ${deltaPct.abs().round()}% below your recent monthly average.',
            value: projectedExpense,
          ));
        } else {
          insights.add(CoachInsight(
            kind: 'forecast',
            title: 'Spending is close to your normal pace',
            body: 'Your projected month-end spending is within about 10% of your recent monthly average.',
            value: projectedExpense,
          ));
        }
      } else {
        insights.add(CoachInsight(
          kind: 'forecast',
          title: 'Month-end forecast',
          body: 'There is not enough history for a baseline yet, so the forecast uses your current daily spending pace.',
          value: projectedExpense,
        ));
      }
    }

    if (saving.amount > 0 && saving.category.isNotEmpty) {
      insights.add(CoachInsight(
        kind: 'saving',
        title: 'Possible saving opportunity',
        body: '${saving.category} is running above its recent pattern. A modest reduction could free up roughly ${_compactMoney(saving.amount)} this month.',
        value: saving.amount,
      ));
    } else if (currentCategories.isNotEmpty) {
      final top = currentCategories.entries.first;
      insights.add(CoachInsight(
        kind: 'saving',
        title: 'Largest spending area',
        body: '${top.key} is currently your largest recorded expense area. Review it before cutting fixed or essential costs.',
        value: top.value,
      ));
    }

    if (investmentTop != null && monthMap.investmentTotal > 0) {
      insights.add(CoachInsight(
        kind: 'investment',
        title: 'Investment concentration',
        body: '${investmentTop.key} represents ${(investmentShare * 100).round()}% of the investments this app could identify this month. This is descriptive, not investment advice.',
        value: investmentTop.value,
      ));
    }

    final merchants = await AppDb.instance.expenseByMerchantForPeriod(currentStart, currentEnd, limit: 1);
    if (merchants.isNotEmpty && currentExpense > 0) {
      final top = merchants.entries.first;
      final share = top.value / currentExpense;
      if (share >= .15) {
        insights.add(CoachInsight(
          kind: 'behavior',
          title: 'Merchant concentration',
          body: '${top.key} accounts for ${(share * 100).round()}% of recorded expenses this month.',
          value: top.value,
        ));
      }
    }

    return FinancialCoachSnapshot(
      currentExpense: currentExpense,
      projectedExpense: projectedExpense,
      normalMonthlyExpense: normalMonthlyExpense,
      potentialSaving: saving.amount,
      savingCategory: saving.category,
      topInvestmentArea: investmentTop?.key ?? '',
      topInvestmentShare: investmentShare,
      historyMonths: historyMonths,
      insights: insights.take(4).toList(),
    );
  }

  ({String category, double amount}) _savingOpportunity({
    required Map<String, double> currentCategories,
    required Map<String, double> historyTotals,
    required int historyMonths,
  }) {
    const protected = <String>{
      'emi', 'loan', 'rent', 'insurance', 'healthcare', 'medical', 'education',
      'utilities', 'electricity', 'investment', 'mutual funds', 'stocks', 'uncategorized', 'other',
    };

    String bestCategory = '';
    double bestSaving = 0;
    for (final entry in currentCategories.entries) {
      final lower = entry.key.toLowerCase();
      if (protected.any(lower.contains)) continue;
      final baseline = (historyTotals[entry.key] ?? 0) / historyMonths;
      double candidate;
      if (baseline > 0) {
        final excess = math.max(0.0, entry.value - baseline).toDouble();
        candidate = math.min(excess, entry.value * .25).toDouble();
      } else {
        candidate = entry.value * .10;
      }
      if (candidate >= 250 && candidate > bestSaving) {
        bestCategory = entry.key;
        bestSaving = candidate;
      }
    }
    return (category: bestCategory, amount: bestSaving);
  }

  Map<String, double> _sortedMap(Map<String, double> source) {
    final entries = source.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in entries) e.key: e.value};
  }

  String _spendingArea(TxRecord tx) {
    final category = tx.category.trim();
    final lowerCategory = category.toLowerCase();
    if (category.isNotEmpty && lowerCategory != 'uncategorized' && lowerCategory != 'other') {
      if (lowerCategory.contains('food') || lowerCategory.contains('dining')) return 'Food & Dining';
      if (lowerCategory.contains('grocery')) return 'Groceries';
      if (lowerCategory.contains('health') || lowerCategory.contains('medical')) return 'Healthcare';
      if (lowerCategory.contains('transport') || lowerCategory.contains('fuel')) return 'Transport';
      if (lowerCategory.contains('travel')) return 'Travel';
      if (lowerCategory.contains('shopping')) return 'Shopping';
      if (lowerCategory.contains('emi') || lowerCategory.contains('loan')) return 'EMI & Loans';
      if (lowerCategory.contains('utility') || lowerCategory.contains('bill')) return 'Bills & Utilities';
      if (lowerCategory.contains('subscription')) return 'Subscriptions';
      if (lowerCategory.contains('education')) return 'Education';
      if (lowerCategory.contains('entertainment')) return 'Entertainment';
      if (lowerCategory.contains('rent') || lowerCategory.contains('housing')) return 'Housing';
      return category;
    }

    final text = '${tx.merchant} ${tx.normalizedMerchant} ${tx.note} ${tx.rawMessage}'.toLowerCase();
    bool hasAny(List<String> terms) => terms.any(text.contains);

    if (hasAny([' emi ', 'loan emi', 'loan repayment', 'installment', 'instalment'])) return 'EMI & Loans';
    if (hasAny(['rent ', 'house rent', 'landlord'])) return 'Housing';
    if (hasAny(['medical', 'pharmacy', 'hospital', 'clinic', 'apollo pharmacy', '1mg', 'netmeds'])) return 'Healthcare';
    if (hasAny(['zomato', 'swiggy', 'restaurant', 'cafe', 'coffee', 'food order', 'dining'])) return 'Food & Dining';
    if (hasAny(['blinkit', 'zepto', 'bigbasket', 'grocery', 'supermarket', 'dmart'])) return 'Groceries';
    if (hasAny(['uber', 'ola', 'rapido', 'metro', 'petrol', 'diesel', 'fuel'])) return 'Transport';
    if (hasAny(['flight', 'airline', 'hotel', 'irctc', 'railway', 'train ticket', 'booking.com', 'makemytrip'])) return 'Travel';
    if (hasAny(['amazon', 'flipkart', 'myntra', 'ajio', 'shopping', 'retail'])) return 'Shopping';
    if (hasAny(['netflix', 'spotify', 'youtube premium', 'prime video', 'subscription', 'membership'])) return 'Subscriptions';
    if (hasAny(['electricity', 'water bill', 'gas bill', 'broadband', 'mobile recharge', 'airtel', 'jio recharge', 'utility'])) return 'Bills & Utilities';
    if (hasAny(['school fee', 'college fee', 'tuition', 'course', 'udemy', 'education'])) return 'Education';
    if (hasAny(['movie', 'cinema', 'bookmyshow', 'gaming', 'entertainment'])) return 'Entertainment';
    if (hasAny(['atm cash', 'cash withdrawal', 'withdrawn from atm'])) return 'Cash';
    return 'Uncategorized';
  }

  String _investmentArea(TxRecord tx) {
    final text = '${tx.category} ${tx.merchant} ${tx.normalizedMerchant} ${tx.note} ${tx.rawMessage}'.toLowerCase();
    bool hasAny(List<String> terms) => terms.any(text.contains);

    if (hasAny(['defence', 'defense', 'hal ', 'bharat dynamics', 'mazagon', 'bel '])) return 'Defence';
    if (hasAny(['pharma', 'healthcare', 'cipla', 'sun pharma', 'dr reddy', 'apollo'])) return 'Healthcare';
    if (hasAny(['infosys', 'tcs', 'wipro', 'hcl tech', 'technology', 'software', ' it '])) return 'IT & Technology';
    if (hasAny(['tata motors', 'maruti', 'mahindra', 'auto', 'automobile'])) return 'Automobile';
    if (hasAny(['ongc', 'oil', 'gas', 'power', 'energy', 'reliance'])) return 'Energy';
    if (hasAny(['hindustan zinc', 'hindzinc', 'steel', 'metal', 'zinc', 'aluminium'])) return 'Metals';
    if (hasAny(['gold', 'sovereign gold', 'sgb'])) return 'Gold';
    if (hasAny(['mutual fund', 'sip', 'fund regular', 'fund direct'])) return 'Mutual Funds';
    if (hasAny(['banking', 'bank ltd', 'bank limited', 'finance ltd', 'nbfc'])) return 'Banking & Financials';
    if (hasAny(['fixed deposit', 'fd ', 'recurring deposit', 'rd '])) return 'Deposits';

    final category = tx.category.trim();
    if (category.isNotEmpty && category.toLowerCase() != 'other investment') return category;
    return 'Other / unidentified';
  }

  String _compactMoney(double value) {
    final abs = value.abs();
    if (abs >= 10000000) return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
    if (abs >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}K';
    return '₹${value.round()}';
  }
}
