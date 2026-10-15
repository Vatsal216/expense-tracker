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

class AssistantActionItem {
  final String title;
  final String detail;
  final double currentAmount;
  final double targetAmount;
  final double savingAmount;
  final String type;
  final String category;
  final String merchant;

  const AssistantActionItem({
    required this.title,
    required this.detail,
    required this.currentAmount,
    required this.targetAmount,
    required this.savingAmount,
    this.type = 'expense',
    this.category = '',
    this.merchant = '',
  });
}

class FinancialAssistantSnapshot {
  final double currentExpense;
  final double forecastLow;
  final double forecastLikely;
  final double forecastHigh;
  final double recentMonthlyAverage;
  final double upcomingCommitments;
  final double potentialSaving;
  final List<AssistantActionItem> savingActions;
  final int historyMonths;

  const FinancialAssistantSnapshot({
    required this.currentExpense,
    required this.forecastLow,
    required this.forecastLikely,
    required this.forecastHigh,
    required this.recentMonthlyAverage,
    required this.upcomingCommitments,
    required this.potentialSaving,
    required this.savingActions,
    required this.historyMonths,
  });
}

class AssistantAnswer {
  final String title;
  final String answer;
  final List<String> points;
  final double? amount;
  final int? startMs;
  final int? endMs;
  final String type;
  final String category;
  final String merchant;
  final String transactionLabel;

  const AssistantAnswer({
    required this.title,
    required this.answer,
    this.points = const [],
    this.amount,
    this.startMs,
    this.endMs,
    this.type = 'all',
    this.category = '',
    this.merchant = '',
    this.transactionLabel = '',
  });

  bool get hasTransactionDrilldown =>
      transactionLabel.isNotEmpty && (type != 'all' || category.isNotEmpty || merchant.isNotEmpty || startMs != null || endMs != null);
}

class SavingsGoalPlan {
  final double targetAmount;
  final DateTime deadline;
  final int monthsRemaining;
  final double requiredMonthly;
  final double recentMonthlyCapacity;
  final double monthlyGap;
  final List<AssistantActionItem> actions;

  const SavingsGoalPlan({
    required this.targetAmount,
    required this.deadline,
    required this.monthsRemaining,
    required this.requiredMonthly,
    required this.recentMonthlyCapacity,
    required this.monthlyGap,
    required this.actions,
  });

  bool get looksAchievable => monthlyGap <= 0;
}

/// Local financial intelligence built on structured, cleaned transactions.
/// Raw SMS text never leaves the device. This engine intentionally separates
/// reporting (Money Map) from action-oriented assistance.
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

    final expenseTotal = expenses.fold<double>(0, (a, b) => a + b.amount);
    final investmentTotal = investments.fold<double>(0, (a, b) => a + b.amount);
    return MoneyMapSnapshot(
      startMs: startMs,
      endMs: endMs,
      spendingAreas: _sortedMap(spendingAreas),
      spendingCategories: _sortedMap(spendingCategories),
      investmentCategories: _sortedMap(investmentCategories),
      investmentAreas: _sortedMap(investmentAreas),
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

  Future<FinancialAssistantSnapshot> assistantSnapshot() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final todayEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = math.max(1, now.day);

    final totals = await AppDb.instance.totalsByTypeForPeriod(monthStart, todayEnd);
    final currentExpense = totals['expense'] ?? 0;
    final paceProjection = currentExpense <= 0 ? 0.0 : currentExpense / daysElapsed * daysInMonth;

    final fullMonthExpenses = <double>[];
    for (var back = 1; back <= 4; back++) {
      final start = DateTime(now.year, now.month - back, 1).millisecondsSinceEpoch;
      final end = DateTime(now.year, now.month - back + 1, 1).millisecondsSinceEpoch;
      final monthTotals = await AppDb.instance.totalsByTypeForPeriod(start, end);
      final value = monthTotals['expense'] ?? 0;
      if (value > 0) fullMonthExpenses.add(value);
    }
    final recentAverage = fullMonthExpenses.isEmpty
        ? 0.0
        : fullMonthExpenses.fold<double>(0, (a, b) => a + b) / fullMonthExpenses.length;

    // Blend current pace with history only when history exists. This avoids a
    // single unusually large early-month transaction dominating the forecast.
    final likely = paceProjection <= 0
        ? 0.0
        : recentAverage > 0
            ? (paceProjection * .68) + (recentAverage * .32)
            : paceProjection;

    double variability = .10;
    if (fullMonthExpenses.length >= 2 && recentAverage > 0) {
      final variance = fullMonthExpenses
              .map((v) => math.pow(v - recentAverage, 2).toDouble())
              .fold<double>(0, (a, b) => a + b) /
          fullMonthExpenses.length;
      variability = (math.sqrt(variance) / recentAverage).clamp(.08, .25).toDouble();
    }
    final low = math.max(currentExpense, likely * (1 - variability)).toDouble();
    final high = math.max(low, likely * (1 + variability)).toDouble();

    final actions = await _savingActions(limit: 5);
    final potential = actions.fold<double>(0, (sum, item) => sum + item.savingAmount);
    final commitments = await _upcomingCommitments(now);

    return FinancialAssistantSnapshot(
      currentExpense: currentExpense,
      forecastLow: low,
      forecastLikely: likely,
      forecastHigh: high,
      recentMonthlyAverage: recentAverage,
      upcomingCommitments: commitments,
      potentialSaving: potential,
      savingActions: actions,
      historyMonths: fullMonthExpenses.length,
    );
  }

  Future<AssistantAnswer> answerQuestion(String rawQuestion) async {
    final question = rawQuestion.trim();
    final lower = question.toLowerCase();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final todayEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;

    if (question.isEmpty) {
      return const AssistantAnswer(
        title: 'Ask a money question',
        answer: 'Ask about saving, this month versus last month, spending changes, upcoming recurring payments, investments, or your month-end forecast.',
      );
    }

    final target = _extractMoneyTarget(lower);
    if (lower.contains('save') || lower.contains('saving') || lower.contains('reduce') || lower.contains('cut')) {
      final actions = await _savingActions(target: target > 0 ? target : null, limit: 6);
      final possible = actions.fold<double>(0, (a, b) => a + b.savingAmount);
      if (actions.isEmpty) {
        return const AssistantAnswer(
          title: 'No clear discretionary cut found yet',
          answer: 'I do not have enough stable category history to recommend a cut without guessing. Correcting Uncategorized transactions will improve this analysis.',
        );
      }
      final desired = target > 0 ? target : possible;
      final points = actions
          .map((a) => '${a.title}: ${_compactMoney(a.currentAmount)} recent monthly level → target about ${_compactMoney(a.targetAmount)} (save ~${_compactMoney(a.savingAmount)})')
          .toList();
      return AssistantAnswer(
        title: target > 0 ? 'Plan to free up ${_compactMoney(target)}' : 'Where you can save',
        answer: possible >= desired
            ? 'Based on your recent discretionary spending, I found a realistic path covering about ${_compactMoney(desired)} without targeting fixed costs, healthcare, EMIs, or investments.'
            : 'I found about ${_compactMoney(possible)} of conservative discretionary reductions. That is below your ${_compactMoney(desired)} target, so cutting further would require choices I should not make automatically.',
        points: points,
        amount: math.min(possible, desired).toDouble(),
        startMs: monthStart,
        endMs: todayEnd,
        type: 'expense',
        category: actions.length == 1 ? actions.first.category : '',
        transactionLabel: actions.length == 1 ? 'Show ${actions.first.title} transactions' : 'Show this month expenses',
      );
    }

    if ((lower.contains('why') && (lower.contains('spend') || lower.contains('expense'))) || lower.contains('spent more') || lower.contains('spending more')) {
      return _whySpendingChanged();
    }

    if (lower.contains('compare') || (lower.contains('last month') && lower.contains('this month'))) {
      return _compareMonthToDate();
    }

    if (lower.contains('forecast') || lower.contains('month end') || lower.contains('month-end') || lower.contains('project')) {
      final snapshot = await assistantSnapshot();
      return AssistantAnswer(
        title: 'Month-end forecast',
        answer: snapshot.forecastLikely <= 0
            ? 'There is not enough spending data this month to form a useful forecast.'
            : 'Your likely recorded month-end expense is around ${_compactMoney(snapshot.forecastLikely)}. A reasonable range is ${_compactMoney(snapshot.forecastLow)} to ${_compactMoney(snapshot.forecastHigh)} based on current pace and recent month-to-month variation.',
        points: [
          if (snapshot.upcomingCommitments > 0) 'User-confirmed upcoming recurring commitments: ${_compactMoney(snapshot.upcomingCommitments)}.',
          if (snapshot.recentMonthlyAverage > 0) 'Recent recorded monthly average: ${_compactMoney(snapshot.recentMonthlyAverage)}.',
        ],
        amount: snapshot.forecastLikely,
        startMs: monthStart,
        endMs: todayEnd,
        type: 'expense',
        transactionLabel: 'Show this month expenses',
      );
    }

    if (lower.contains('subscription') || lower.contains('recurring') || lower.contains('emi') || lower.contains('commitment')) {
      final recurring = await AppDb.instance.userRecurringSummaries();
      if (recurring.isEmpty) {
        return const AssistantAnswer(
          title: 'No user-confirmed recurring payments yet',
          answer: 'Recurring payments are only tracked when you mark them. Open a transaction and choose “Mark as recurring” so I do not guess from one message.',
        );
      }
      final enabled = recurring.where((r) => ((r['nextDue'] as num?)?.toInt() ?? 0) > 0).toList();
      final next = enabled.take(6).map((r) {
        final amount = ((r['averageAmount'] as num?) ?? 0).toDouble();
        return '${r['name']}: about ${_compactMoney(amount)} · ${r['frequency']}';
      }).toList();
      final total = enabled.fold<double>(0, (sum, r) => sum + (((r['averageAmount'] as num?) ?? 0).toDouble()));
      return AssistantAnswer(
        title: 'Recurring commitments you confirmed',
        answer: 'I found ${enabled.length} active recurring pattern${enabled.length == 1 ? '' : 's'}. These are based only on rules you explicitly marked, not automatic guesses.',
        points: next,
        amount: total,
      );
    }

    if (lower.contains('invest') || lower.contains('sector') || lower.contains('portfolio')) {
      final map = await moneyMap(monthStart, todayEnd);
      if (map.investmentAreas.isEmpty) {
        return const AssistantAnswer(
          title: 'No identified investments this month',
          answer: 'I could not confidently identify investment transactions for the current month. Correcting investment categories will improve the Money Map.',
        );
      }
      final entries = map.investmentAreas.entries.take(5).toList();
      final points = entries.map((e) {
        final share = map.investmentTotal <= 0 ? 0 : e.value / map.investmentTotal * 100;
        return '${e.key}: ${_compactMoney(e.value)} (${share.round()}%)';
      }).toList();
      final top = entries.first;
      return AssistantAnswer(
        title: 'Where your identified investments went',
        answer: '${top.key} is currently the largest identified investment area this month. This describes recorded concentration; it is not a recommendation to buy or sell.',
        points: points,
        amount: map.investmentTotal,
        startMs: monthStart,
        endMs: todayEnd,
        type: 'investment',
        transactionLabel: 'Show this month investments',
      );
    }

    if (lower.contains('food') || lower.contains('grocery') || lower.contains('shopping') || lower.contains('health') || lower.contains('travel')) {
      final category = lower.contains('grocery')
          ? 'Groceries'
          : lower.contains('food')
              ? 'Food & Dining'
              : lower.contains('shopping')
                  ? 'Shopping'
                  : lower.contains('health')
                      ? 'Healthcare'
                      : 'Travel';
      final current = (await AppDb.instance.expenseByCategoryForPeriod(monthStart, todayEnd))[category] ?? 0;
      final baseline = await _categoryMonthlyAverage(category);
      final delta = current - baseline;
      return AssistantAnswer(
        title: '$category this month',
        answer: baseline <= 0
            ? 'You have ${_compactMoney(current)} recorded in $category this month. I do not yet have enough prior history for a stable baseline.'
            : delta > 0
                ? '$category is ${_compactMoney(delta)} above its recent full-month average of ${_compactMoney(baseline)}. Because the current month is not finished, treat this as a warning signal rather than a final comparison.'
                : '$category is currently ${_compactMoney(delta.abs())} below its recent full-month average of ${_compactMoney(baseline)}.',
        amount: current,
        startMs: monthStart,
        endMs: todayEnd,
        type: 'expense',
        category: category,
        transactionLabel: 'Show $category transactions',
      );
    }

    return const AssistantAnswer(
      title: 'I can answer from your transaction history',
      answer: 'Try asking “Where can I save ₹5,000?”, “Why did I spend more this month?”, “Compare this month with last month”, “What recurring payments are coming?”, “Where am I investing most?”, or “Forecast this month”.',
    );
  }

  Future<SavingsGoalPlan> goalPlan({required double targetAmount, required DateTime deadline}) async {
    final now = DateTime.now();
    final months = math.max(1, (deadline.year - now.year) * 12 + deadline.month - now.month + (deadline.day >= now.day ? 1 : 0));
    final required = targetAmount / months;

    final capacityMonths = <double>[];
    for (var back = 1; back <= 3; back++) {
      final start = DateTime(now.year, now.month - back, 1).millisecondsSinceEpoch;
      final end = DateTime(now.year, now.month - back + 1, 1).millisecondsSinceEpoch;
      final totals = await AppDb.instance.totalsByTypeForPeriod(start, end);
      final income = (totals['income'] ?? 0) + (totals['refund'] ?? 0);
      final out = (totals['expense'] ?? 0) + (totals['investment'] ?? 0);
      if (income > 0) capacityMonths.add(math.max(0.0, income - out).toDouble());
    }
    final capacity = capacityMonths.isEmpty ? 0.0 : capacityMonths.fold<double>(0, (a, b) => a + b) / capacityMonths.length;
    final gap = math.max(0.0, required - capacity).toDouble();
    final actions = gap > 0 ? await _savingActions(target: gap, limit: 6) : <AssistantActionItem>[];

    return SavingsGoalPlan(
      targetAmount: targetAmount,
      deadline: deadline,
      monthsRemaining: months,
      requiredMonthly: required,
      recentMonthlyCapacity: capacity,
      monthlyGap: gap,
      actions: actions,
    );
  }

  Future<List<AssistantActionItem>> _savingActions({double? target, int limit = 5}) async {
    final now = DateTime.now();
    final history = <String, List<double>>{};
    for (var back = 1; back <= 3; back++) {
      final start = DateTime(now.year, now.month - back, 1).millisecondsSinceEpoch;
      final end = DateTime(now.year, now.month - back + 1, 1).millisecondsSinceEpoch;
      final cats = await AppDb.instance.expenseByCategoryForPeriod(start, end);
      for (final entry in cats.entries) {
        history.putIfAbsent(entry.key, () => <double>[]).add(entry.value);
      }
    }

    const protected = <String>{
      'healthcare', 'emi & loans', 'rent & housing', 'housing', 'education', 'insurance', 'credit card payment',
    };
    const rates = <String, double>{
      'food & dining': .25,
      'shopping': .30,
      'entertainment': .30,
      'subscriptions': .50,
      'travel': .15,
      'groceries': .10,
      'transport': .10,
      'bills & utilities': .08,
    };

    final out = <AssistantActionItem>[];
    for (final entry in history.entries) {
      final key = entry.key.toLowerCase();
      if (protected.contains(key) || key == 'uncategorized') continue;
      final months = entry.value.where((v) => v > 0).toList();
      if (months.isEmpty) continue;
      final average = months.fold<double>(0, (a, b) => a + b) / months.length;
      if (average < 500) continue;
      final rate = rates[key] ?? .10;
      final saving = average * rate;
      if (saving < 150) continue;
      out.add(AssistantActionItem(
        title: entry.key,
        detail: 'Conservative reduction of ${(rate * 100).round()}% from the recent monthly level.',
        currentAmount: average,
        targetAmount: math.max(0, average - saving).toDouble(),
        savingAmount: saving,
        category: entry.key,
      ));
    }
    out.sort((a, b) => b.savingAmount.compareTo(a.savingAmount));

    if (target != null && target > 0) {
      final selected = <AssistantActionItem>[];
      var accumulated = 0.0;
      for (final item in out) {
        if (accumulated >= target) break;
        final remaining = target - accumulated;
        if (item.savingAmount <= remaining) {
          selected.add(item);
          accumulated += item.savingAmount;
        } else {
          final adjusted = remaining;
          selected.add(AssistantActionItem(
            title: item.title,
            detail: item.detail,
            currentAmount: item.currentAmount,
            targetAmount: math.max(0, item.currentAmount - adjusted).toDouble(),
            savingAmount: adjusted,
            category: item.category,
          ));
          accumulated += adjusted;
        }
      }
      return selected.take(limit).toList();
    }
    return out.take(limit).toList();
  }

  Future<AssistantAnswer> _whySpendingChanged() async {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final currentEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final previousStartDate = DateTime(now.year, now.month - 1, 1);
    final previousDays = DateTime(previousStartDate.year, previousStartDate.month + 1, 0).day;
    final comparableDay = math.min(now.day, previousDays);
    final previousStart = previousStartDate.millisecondsSinceEpoch;
    final previousEnd = DateTime(previousStartDate.year, previousStartDate.month, comparableDay + 1).millisecondsSinceEpoch;

    final current = await AppDb.instance.expenseByCategoryForPeriod(currentStart, currentEnd);
    final previous = await AppDb.instance.expenseByCategoryForPeriod(previousStart, previousEnd);
    final currentTotal = current.values.fold<double>(0, (a, b) => a + b);
    final previousTotal = previous.values.fold<double>(0, (a, b) => a + b);
    final delta = currentTotal - previousTotal;

    final changes = <MapEntry<String, double>>[];
    for (final key in {...current.keys, ...previous.keys}) {
      final difference = (current[key] ?? 0) - (previous[key] ?? 0);
      if (difference > 100) changes.add(MapEntry(key, difference));
    }
    changes.sort((a, b) => b.value.compareTo(a.value));
    final top = changes.take(4).toList();

    return AssistantAnswer(
      title: delta >= 0 ? 'Why spending is higher' : 'Spending is lower so far',
      answer: previousTotal <= 0
          ? 'I do not have a comparable previous-month period yet.'
          : delta >= 0
              ? 'Through day ${now.day}, recorded expenses are ${_compactMoney(delta)} higher than the same number of days last month. The categories below explain most of the increase.'
              : 'Through day ${now.day}, recorded expenses are ${_compactMoney(delta.abs())} lower than the same number of days last month.',
      points: top.map((e) => '${e.key}: +${_compactMoney(e.value)} versus the comparable period').toList(),
      amount: currentTotal,
      startMs: currentStart,
      endMs: currentEnd,
      type: 'expense',
      category: top.length == 1 ? top.first.key : '',
      transactionLabel: top.length == 1 ? 'Show ${top.first.key} transactions' : 'Show this month expenses',
    );
  }

  Future<AssistantAnswer> _compareMonthToDate() async {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final currentEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final prev = DateTime(now.year, now.month - 1, 1);
    final prevLastDay = DateTime(prev.year, prev.month + 1, 0).day;
    final comparable = math.min(now.day, prevLastDay);
    final previousStart = prev.millisecondsSinceEpoch;
    final previousEnd = DateTime(prev.year, prev.month, comparable + 1).millisecondsSinceEpoch;
    final a = await AppDb.instance.totalsByTypeForPeriod(currentStart, currentEnd);
    final b = await AppDb.instance.totalsByTypeForPeriod(previousStart, previousEnd);
    final expenseA = a['expense'] ?? 0;
    final expenseB = b['expense'] ?? 0;
    final difference = expenseA - expenseB;
    final pct = expenseB > 0 ? difference / expenseB * 100 : 0.0;
    return AssistantAnswer(
      title: 'This month vs the same days last month',
      answer: expenseB <= 0
          ? 'There is not enough previous-month data for a fair comparison.'
          : 'Recorded expenses are ${difference >= 0 ? '${_compactMoney(difference)} higher' : '${_compactMoney(difference.abs())} lower'} (${pct.abs().round()}%) through day ${now.day}. I compare equal day counts so a partial month is not compared with a full month.',
      points: [
        'This month through day ${now.day}: ${_compactMoney(expenseA)}',
        'Last month through day $comparable: ${_compactMoney(expenseB)}',
      ],
      amount: expenseA,
      startMs: currentStart,
      endMs: currentEnd,
      type: 'expense',
      transactionLabel: 'Show this month expenses',
    );
  }

  Future<double> _categoryMonthlyAverage(String category) async {
    final now = DateTime.now();
    final values = <double>[];
    for (var back = 1; back <= 3; back++) {
      final start = DateTime(now.year, now.month - back, 1).millisecondsSinceEpoch;
      final end = DateTime(now.year, now.month - back + 1, 1).millisecondsSinceEpoch;
      final cats = await AppDb.instance.expenseByCategoryForPeriod(start, end);
      if ((cats[category] ?? 0) > 0) values.add(cats[category]!);
    }
    return values.isEmpty ? 0 : values.fold<double>(0, (a, b) => a + b) / values.length;
  }

  Future<double> _upcomingCommitments(DateTime now) async {
    final end = DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch;
    final current = now.millisecondsSinceEpoch;
    final rules = await AppDb.instance.userRecurringSummaries();
    var total = 0.0;
    for (final rule in rules) {
      final next = ((rule['nextDue'] as num?) ?? 0).toInt();
      if (next >= current && next < end) total += ((rule['averageAmount'] as num?) ?? 0).toDouble();
    }
    return total;
  }

  double _extractMoneyTarget(String text) {
    final lakh = RegExp(r'(?:₹|rs\.?\s*)?([0-9]+(?:\.[0-9]+)?)\s*(?:lakh|lac|lacs)', caseSensitive: false).firstMatch(text);
    if (lakh != null) return (double.tryParse(lakh.group(1) ?? '') ?? 0) * 100000;
    final thousand = RegExp(r'(?:₹|rs\.?\s*)?([0-9]+(?:\.[0-9]+)?)\s*k\b', caseSensitive: false).firstMatch(text);
    if (thousand != null) return (double.tryParse(thousand.group(1) ?? '') ?? 0) * 1000;
    final amount = RegExp(r'(?:₹|rs\.?\s*)\s*([0-9][0-9,]*(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(text);
    if (amount != null) return double.tryParse((amount.group(1) ?? '').replaceAll(',', '')) ?? 0;
    return 0;
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

  static String _compactMoney(double value) {
    final abs = value.abs();
    if (abs >= 10000000) return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
    if (abs >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}K';
    return '₹${value.round()}';
  }
}
