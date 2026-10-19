import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_db.dart';
import 'models.dart';
import 'native_bridge.dart';
import 'enhancements.dart';
import 'financial_ai.dart';
import 'financial_ai_agent.dart';
import 'fintech_design.dart';
import 'cards_page.dart';

const txTypes = ['expense', 'investment', 'income', 'transfer', 'refund'];
final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final moneyExact = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final dateTimeFmt = DateFormat('dd MMM, h:mm a');
final expenseDataRevision = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
  WidgetsBinding.instance.addPostFrameCallback((_) => _initializeServices());
}

Future<void> _initializeServices() async {
  try {
    await AppDb.instance.initialize();
    // v24: promotional/discount SMS such as "Rs 3000 OFF" must not remain
    // in the ledger after the classifier safety upgrade. Preserve manual/user
    // corrections because the native reclassifier explicitly excludes them.
    final promoCleanupDone = await AppDb.instance.getBoolSetting('classifier_promo_guard_v24_done', fallback: false);
    if (!promoCleanupDone) {
      try {
        await NativeBridge.reclassifyStoredSms();
        await AppDb.instance.setSetting('classifier_promo_guard_v24_done', '1');
        expenseDataRevision.value++;
      } catch (e) {
        debugPrint('v24 promotional SMS cleanup skipped: $e');
      }
    }
    final removedUnsafeRules = await AppDb.instance.cleanupUnsafeBroadUserRules();
    final patternCleanupDone = await AppDb.instance.getBoolSetting('classifier_pattern_cleanup_v22_done', fallback: false);
    if (!patternCleanupDone || removedUnsafeRules > 0) {
      try {
        await NativeBridge.reclassifyStoredSms();
        await AppDb.instance.setSetting('classifier_pattern_cleanup_v22_done', '1');
        expenseDataRevision.value++;
      } catch (e) {
        debugPrint('v22 pattern cleanup skipped: $e');
      }
    }
    final cleanupDone = await AppDb.instance.getBoolSetting('classifier_cleanup_v15_done', fallback: false);
    if (!cleanupDone) {
      try {
        await NativeBridge.reclassifyStoredSms();
        await AppDb.instance.setSetting('classifier_cleanup_v15_done', '1');
      } catch (e) {
        debugPrint('Stored SMS cleanup skipped: $e');
      }
    }
    final enabled = await AppDb.instance.getBoolSetting('daily_summary_enabled', fallback: true);
    final hour = int.tryParse(await AppDb.instance.getSetting('daily_summary_hour', fallback: '21')) ?? 21;
    final minute = int.tryParse(await AppDb.instance.getSetting('daily_summary_minute', fallback: '0')) ?? 0;
    Future<void> safeTask(String label, Future<void> Function() task) async {
      try {
        await task();
      } catch (e) {
        debugPrint('Startup task $label failed: $e');
      }
    }
    // Native sources attach evidence immediately; this safely backfills the
    // visible ledger created by older app versions.
    await safeTask('transaction evidence backfill', () => AppDb.instance.backfillTransactionEvidence());
    await safeTask('daily summary', () => NativeBridge.scheduleDailySummary(enabled: enabled, hour: hour, minute: minute));
    await safeTask('preferences', () => loadEnhancedPreferences());
    await safeTask('merchant normalization', () => AppDb.instance.normalizeExistingMerchants());
    await safeTask('account sync', () => AppDb.instance.syncAccountsFromTransactions());
    await safeTask('remove discontinued email imports', () async {
      final removed = await AppDb.instance.removeGmailImportedTransactionsOnce();
      if (removed > 0) expenseDataRevision.value++;
    });
    await safeTask('credit-card transaction linking', () => AppDb.instance.autoLinkCardTransactions());
    await safeTask('transfer matching', () async { await AppDb.instance.matchTransfers(); });
    await safeTask('deduplication', () async {
      final dedupResult = await AppDb.instance.smartDeduplicate();
      if ((dedupResult['ignored'] ?? 0) > 0) expenseDataRevision.value++;
    });
    await safeTask('smart alerts', () => runDailySmartAlerts());
    await safeTask('home widget', () => NativeBridge.updateHomeWidget());
  } catch (e, stack) {
    debugPrint('Startup initialization failed: $e');
    debugPrintStack(stackTrace: stack);
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  ThemeData _theme(Brightness brightness) => FintechDesign.theme(brightness);

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Expense Tracker',
        theme: _theme(Brightness.light),
        themeMode: ThemeMode.light,
        home: const AppLockGate(child: HomeShell()),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int index = 0;
  int refreshToken = 0;

  void refresh() {
    if (mounted) setState(() => refreshToken++);
  }
  void navigateTo(int value) => setState(() => index = value);

  Future<void> _openMore(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .72),
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('More'), subtitle: Text('Plans, reports, advisor and settings')),
            ListTile(leading: const Icon(Icons.savings_outlined), title: const Text('Plan & recurring'), onTap: () => Navigator.pop(sheetContext, 4)),
            ListTile(leading: const Icon(Icons.insights_rounded), title: const Text('Reports'), onTap: () => Navigator.pop(sheetContext, 5)),
            ListTile(leading: const Icon(Icons.auto_awesome_rounded), title: const Text('AI Advisor'), subtitle: const Text('Ask about spending, UPI, cards and budgets'), onTap: () => Navigator.pop(sheetContext, 7)),
            ListTile(leading: const Icon(Icons.settings_rounded), title: const Text('Settings'), onTap: () => Navigator.pop(sheetContext, 6)),
          ]),
        )),
      )),
    );
    if (!mounted || selected == null) return;
    if (selected == 7) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAdvisorPage()));
      refresh();
    } else {
      navigateTo(selected);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    expenseDataRevision.addListener(refresh);
    ledgerDataRevision.addListener(refresh);
  }

  @override
  void dispose() {
    expenseDataRevision.removeListener(refresh);
    ledgerDataRevision.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(onChanged: refresh, onNavigate: navigateTo),
      TransactionsPage(key: ValueKey('tx-$refreshToken'), onChanged: refresh),
      PayUpiPage(key: ValueKey('pay-$refreshToken'), onChanged: refresh),
      CardsPage(key: ValueKey('cards-$refreshToken'), onChanged: refresh),
      PlanPage(key: ValueKey('plan-$refreshToken')),
      ReportsPage(key: ValueKey('report-$refreshToken')),
      SettingsPage(key: ValueKey('settings-$refreshToken'), onChanged: refresh),
    ];

    return Scaffold(
      extendBody: false,
      body: SafeArea(bottom: false, child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 22, offset: Offset(0, -5))],
          ),
          child: NavigationBar(
            selectedIndex: index > 3 ? 4 : index,
            onDestinationSelected: (value) {
              if (value == 4) { _openMore(context); } else { navigateTo(value); }
            },
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'Activity'),
              NavigationDestination(icon: Icon(Icons.qr_code_2_rounded), label: 'Pay'),
              NavigationDestination(icon: Icon(Icons.credit_card_rounded), label: 'Cards'),
              NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'More'),
            ],
          ),
        ),
      ),
    );
  }
}

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Plan'),
            actions: [
              Tooltip(
                message: 'AI Advisor',
                child: TextButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('AI Advisor'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAdvisorPage())),
                ),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Goals'),
                Tab(text: 'Recurring'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              FinancialAssistantPage(embedded: true),
              RecurringPaymentsPage(embedded: true),
            ],
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  final VoidCallback onChanged;
  final ValueChanged<int> onNavigate;
  const HomePage({super.key, required this.onChanged, required this.onNavigate});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String period = 'week';
  DateTimeRange? customRange;

  @override
  void initState() {
    super.initState();
    _restorePeriod();
  }

  Future<void> _restorePeriod() async {
    final saved = await AppDb.instance.getSetting('home_period_filter', fallback: 'week');
    final valid = {'total', 'month', 'week', 'day', 'custom'}.contains(saved) ? saved : 'week';
    DateTimeRange? restored;
    if (valid == 'custom') {
      final start = int.tryParse(await AppDb.instance.getSetting('home_custom_start'));
      final end = int.tryParse(await AppDb.instance.getSetting('home_custom_end'));
      if (start != null && end != null && end >= start) {
        restored = DateTimeRange(
          start: DateTime.fromMillisecondsSinceEpoch(start),
          end: DateTime.fromMillisecondsSinceEpoch(end),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      period = valid == 'custom' && restored == null ? 'week' : valid;
      customRange = restored;
    });
  }

  (int, int) _range() {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    switch (period) {
      case 'day':
        return (DateTime(now.year, now.month, now.day).millisecondsSinceEpoch, endOfToday);
      case 'week':
        final startDay = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        return (startDay.millisecondsSinceEpoch, endOfToday);
      case 'total':
        return (0, endOfToday);
      case 'custom':
        final selected = customRange;
        if (selected == null) return (DateTime(now.year, now.month, 1).millisecondsSinceEpoch, endOfToday);
        final start = DateTime(selected.start.year, selected.start.month, selected.start.day).millisecondsSinceEpoch;
        final end = DateTime(selected.end.year, selected.end.month, selected.end.day + 1).millisecondsSinceEpoch;
        return (start, end);
      default:
        return (DateTime(now.year, now.month, 1).millisecondsSinceEpoch, endOfToday);
    }
  }

  String get _periodTitle => switch (period) {
        'day' => "TODAY'S SPENDING",
        'week' => 'WEEKLY SPENDING',
        'total' => 'ALL-TIME SPENDING',
        'custom' => 'CUSTOM SPENDING',
        _ => 'MONTHLY SPENDING',
      };

  String get _periodSubtitle => switch (period) {
        'day' => 'Today',
        'week' => 'This week',
        'total' => 'All recorded transactions',
        'custom' => customRange == null
            ? 'Custom range'
            : '${DateFormat('dd MMM').format(customRange!.start)} – ${DateFormat('dd MMM yyyy').format(customRange!.end)}',
        _ => DateFormat('MMMM yyyy').format(DateTime.now()),
      };

  Future<void> _selectPeriod(String value) async {
    if (value != 'custom') {
      setState(() => period = value);
      await AppDb.instance.setSetting('home_period_filter', value);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: now,
      initialDateRange: customRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: 'Select dashboard date range',
    );
    if (picked != null && mounted) {
      setState(() { customRange = picked; period = 'custom'; });
      await AppDb.instance.setSetting('home_period_filter', 'custom');
      await AppDb.instance.setSetting('home_custom_start', picked.start.millisecondsSinceEpoch.toString());
      await AppDb.instance.setSetting('home_custom_end', picked.end.millisecondsSinceEpoch.toString());
    }
  }

  Future<List<dynamic>> load() async {
    final range = _range();
    return Future.wait<dynamic>([
      AppDb.instance.totalsByTypeForPeriod(range.$1, range.$2),
      AppDb.instance.overallBudget(),
      AppDb.instance.searchTransactions(startMs: range.$1, endMs: range.$2, limit: 6),
      AppDb.instance.reviewTransactions(),
      AppDb.instance.expenseTrendForPeriod(range.$1, range.$2),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: load(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(message: 'Could not open local data: ${snap.error}');
        if (!snap.hasData) return const AppLoadingView(label: 'Preparing your dashboard');

        final totals = snap.data![0] as Map<String, double>;
        final budget = snap.data![1] as double;
        final recent = snap.data![2] as List<TxRecord>;
        final review = snap.data![3] as List<TxRecord>;
        final trend = snap.data![4] as List<double>;
        final spent = totals['expense'] ?? 0;
        final invested = totals['investment'] ?? 0;
        final income = totals['income'] ?? 0;
        final refunds = totals['refund'] ?? 0;
        final selectedRange = _range();
        final monthlyBudgetMode = period == 'month';
        final remaining = !monthlyBudgetMode || budget <= 0 ? 0.0 : (budget - spent).clamp(0, double.infinity).toDouble();
        final progress = !monthlyBudgetMode || budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0).toDouble();

        return RefreshIndicator(
          onRefresh: () async => widget.onChanged(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 104),
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 6))],
                    ),
                    child: ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.asset('assets/logo.png')),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: PageHeader(title: 'Good to see you', subtitle: 'Your spending at a glance')),
                  IconButton.filledTonal(onPressed: widget.onChanged, icon: const Icon(Icons.sync_rounded)),
                ],
              ),
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerLeft, child: _periodMenu()),
              const SizedBox(height: 16),
              _heroCard(spent: spent, income: income, invested: invested, refunds: refunds, budget: budget, remaining: remaining, progress: progress, trend: trend, trendLabels: _trendLabels(selectedRange)),
              const SizedBox(height: 22),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Recent activity',
                subtitle: recent.isEmpty ? 'No activity for $_periodSubtitle' : '${recent.length} most recent for $_periodSubtitle',
                actionLabel: 'View all',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FilteredTransactionsPage(
                      title: _periodSubtitle,
                      startMs: selectedRange.$1,
                      endMs: selectedRange.$2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (recent.isEmpty)
                EmptyCard(text: 'No transactions found for $_periodSubtitle.')
              else
                ...recent.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TransactionTile(
                      tx: t,
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailsPage(transaction: t)));
                        widget.onChanged();
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _periodMenu() => PopupMenuButton<String>(
        onSelected: _selectPeriod,
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'week', child: Text('This week')),
          PopupMenuItem(value: 'month', child: Text('This month')),
          PopupMenuItem(value: 'day', child: Text('Today')),
          PopupMenuItem(value: 'total', child: Text('All time')),
          PopupMenuItem(value: 'custom', child: Text('Custom range')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: const Color(0xFFF0F4F1), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_periodSubtitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ]),
        ),
      );

  Widget _heroCard({
    required double spent,
    required double income,
    required double invested,
    required double refunds,
    required double budget,
    required double remaining,
    required double progress,
    required List<double> trend,
    required List<String> trendLabels,
  }) {
    final monthlyBudgetMode = period == 'month';
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08794D), Color(0xFF0FAE6D), Color(0xFF34C981)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x33087A4D), blurRadius: 28, offset: Offset(0, 14))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total spending', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money.format(spent), style: const TextStyle(color: Colors.white, fontSize: 38, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
          ),
          const SizedBox(height: 6),
          Text(
            monthlyBudgetMode
                ? (budget > 0 ? '${money.format(remaining)} left from ${money.format(budget)} monthly budget' : 'Set a monthly budget to track progress')
                : '↓ Spending for $_periodSubtitle',
            style: const TextStyle(color: Color(0xFFE7FFF1), fontWeight: FontWeight.w600),
          ),
          if (monthlyBudgetMode) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: Colors.white.withValues(alpha: .18),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _WeeklySparkBars(values: trend, labels: trendLabels),
        ],
      ),
    );
  }

  List<String> _trendLabels((int, int) range) {
    final start = DateTime.fromMillisecondsSinceEpoch(range.$1);
    final end = DateTime.fromMillisecondsSinceEpoch(range.$2).subtract(const Duration(days: 1));
    if (period == 'day') return const ['12am', '4am', '8am', '12pm', '4pm', '8pm', 'Now'];
    if (period == 'week') return List.generate(7, (index) => DateFormat('EEE').format(start.add(Duration(days: index))));
    if (period == 'month') {
      final days = end.day;
      return List.generate(7, (index) {
        final from = 1 + (days * index ~/ 7);
        final to = (days * (index + 1) ~/ 7).clamp(from, days);
        return '$from–$to';
      });
    }
    if (period == 'total' && start.year == 1970) return const ['Earlier', '', '', '', '', '', 'Now'];
    final span = end.difference(start).inDays.clamp(0, 36500).toInt();
    return List.generate(7, (index) {
      final point = start.add(Duration(days: (span * index / 6).round()));
      return span > 90 ? DateFormat('MMM').format(point) : DateFormat('d MMM').format(point);
    });
  }

}

class _WeeklySparkBars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  const _WeeklySparkBars({required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<double>(0, (maxValue, item) => item > maxValue ? item : maxValue);
    return SizedBox(
      height: 70,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) => Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(height: maximum <= 0 ? 6 : 8 + (34 * (values[index] / maximum)), width: 10, decoration: BoxDecoration(color: index == values.length - 1 ? const Color(0xFFFF8E7A) : Colors.white.withValues(alpha: .66), borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 6),
            Text(labels[index], style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ))),
      ),
    );
  }
}


class _HomeRecurringPreview extends StatelessWidget {
  const _HomeRecurringPreview();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDb.instance.userRecurringSummaries(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(FintechRadius.card),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded),
                SizedBox(width: 10),
                Expanded(child: Text('Recurring list is temporarily unavailable.')),
              ],
            ),
          );
        }
        if (!snap.hasData) {
          return Container(
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(FintechRadius.card),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }

        final items = snap.data!;
        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(FintechRadius.card),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(Icons.autorenew_rounded)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No recurring payments selected',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Choose recurring payments yourself from More tools or from a transaction. The app will not guess automatically.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final visible = items.take(2).toList();
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _RecurringHomeRow(item: visible[i]),
                if (i != visible.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecurringHomeRow extends StatelessWidget {
  final Map<String, Object?> item;
  const _RecurringHomeRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final merchant = '${item['name'] ?? item['merchant'] ?? 'Recurring payment'}';
    final average = (item['averageAmount'] as num?)?.toDouble() ?? 0;
    final nextDueMs = (item['nextDue'] as num?)?.toInt() ?? 0;
    final frequency = '${item['frequency'] ?? 'Recurring'}';
    final due = nextDueMs > 0
        ? DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(nextDueMs))
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.autorenew_rounded),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '$frequency • next around $due • user selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                moneyExact.format(average),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeToSpendCard extends StatelessWidget {
  final Map<String, Object?> snapshot;
  const _SafeToSpendCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final safe = (snapshot['safe'] as num?)?.toDouble() ?? 0;
    final daily = (snapshot['dailySafe'] as num?)?.toDouble() ?? 0;
    final upcoming = (snapshot['upcomingBills'] as num?)?.toDouble() ?? 0;
    final days = (snapshot['daysRemaining'] as num?)?.toInt() ?? 0;
    final mode = '${snapshot['mode'] ?? 'insufficient'}';
    final hasEstimate = mode != 'insufficient';
    final subtitle = switch (mode) {
      'budget' => 'After this month’s spending, investments and expected recurring bills',
      'cashflow' => 'Based on recorded income, spending, investments and expected recurring bills',
      _ => 'Set a monthly budget or record income to calculate a useful estimate',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.savings_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Safe to spend', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hasEstimate ? money.format(safe) : 'Not enough data yet',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.5),
            ),
          ),
          if (hasEstimate) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniFact(icon: Icons.today_outlined, text: '${money.format(daily)}/day for $days day${days == 1 ? '' : 's'}'),
                if (upcoming > 0) _MiniFact(icon: Icons.event_repeat_outlined, text: '${money.format(upcoming)} expected bills'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniFact({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 15), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))],
        ),
      );
}

class _FinancialInboxPreview extends StatelessWidget {
  final List<TxRecord> items;
  final VoidCallback onChanged;
  const _FinancialInboxPreview({required this.items, required this.onChanged});

  Future<void> _act(BuildContext context, TxRecord tx, bool accept) async {
    if (tx.id == null) return;
    if (accept) {
      await AppDb.instance.acceptReview(tx.id!);
    } else {
      await AppDb.instance.ignoreReview(tx.id!);
    }
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Transaction accepted' : 'Transaction ignored')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Row(
          children: [
            CircleAvatar(child: Icon(Icons.task_alt_rounded)),
            SizedBox(width: 12),
            Expanded(child: Text('Everything looks classified. New uncertain SMS will appear here instead of being silently trusted.')),
          ],
        ),
      );
    }
    return Column(
      children: items.map((tx) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tx.normalizedMerchant.isEmpty ? tx.merchant : tx.normalizedMerchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(moneyExact.format(tx.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${titleCase(tx.type)} • ${tx.category} • ${(tx.classificationConfidence * 100).round()}% confidence',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => _act(context, tx, false), child: const Text('Ignore'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await editTransaction(context, tx);
                        onChanged();
                      },
                      child: const Text('Fix'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: () => _act(context, tx, true), child: const Text('Accept'))),
                ],
              ),
            ],
          ),
        ),
      )).toList(),
    );
  }
}

class _WhatChangedCard extends StatelessWidget {
  final List<String> insights;
  const _WhatChangedCard({required this.insights});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: insights.isEmpty
            ? const Text('More history is needed before month-to-month comparisons become useful.')
            : Column(
                children: insights.asMap().entries.map((entry) => Padding(
                  padding: EdgeInsets.only(bottom: entry.key == insights.length - 1 ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(entry.key == 0 ? Icons.compare_arrows_rounded : Icons.auto_awesome_rounded, size: 17),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entry.value, style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600))),
                    ],
                  ),
                )).toList(),
              ),
      );
}


class _MoneyMapAsyncPreview extends StatelessWidget {
  final int startMs;
  final int endMs;
  final String periodLabel;
  const _MoneyMapAsyncPreview({required this.startMs, required this.endMs, required this.periodLabel});

  @override
  Widget build(BuildContext context) => FutureBuilder<MoneyMapSnapshot>(
        future: FinancialAiEngine.instance.moneyMap(startMs, endMs),
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyCard(text: 'Money Map is temporarily unavailable.');
          }
          if (!snap.hasData) {
            return Container(
              height: 116,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return _MoneyMapPreview(
            snapshot: snap.data!,
            startMs: startMs,
            endMs: endMs,
            periodLabel: periodLabel,
          );
        },
      );
}

class _FinancialAssistantAsyncPreview extends StatelessWidget {
  const _FinancialAssistantAsyncPreview();

  @override
  Widget build(BuildContext context) => FutureBuilder<FinancialAssistantSnapshot>(
        future: FinancialAiEngine.instance.assistantSnapshot(),
        builder: (context, snap) {
          if (snap.hasError) return const EmptyCard(text: 'Financial Assistant is temporarily unavailable.');
          if (!snap.hasData) {
            return Container(
              height: 104,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return _FinancialAssistantPreview(snapshot: snap.data!);
        },
      );
}

class _MoneyMapPreview extends StatelessWidget {
  final MoneyMapSnapshot snapshot;
  final int startMs;
  final int endMs;
  final String periodLabel;

  const _MoneyMapPreview({
    required this.snapshot,
    required this.startMs,
    required this.endMs,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final spending = snapshot.spendingAreas.entries.take(3).toList();
    final investing = snapshot.investmentAreas.entries.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _MoneyMapTotal(label: 'Spent', value: snapshot.expenseTotal, icon: Icons.south_east_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _MoneyMapTotal(label: 'Invested', value: snapshot.investmentTotal, icon: Icons.trending_up_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          Text('SPENDING AREAS', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 8),
          if (spending.isEmpty)
            const Text('No spending data for this period.')
          else
            ...spending.map((e) => _MoneyMapMiniRow(
                  label: e.key,
                  amount: e.value,
                  total: snapshot.expenseTotal,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MoneyAreaTransactionsPage(
                        title: '${e.key} · $periodLabel',
                        area: e.key,
                        kind: 'expense',
                        startMs: startMs,
                        endMs: endMs,
                      ),
                    ),
                  ),
                )),
          const SizedBox(height: 14),
          Text('INVESTMENT AREAS', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 8),
          if (investing.isEmpty)
            const Text('No investments identified for this period.')
          else
            ...investing.map((e) => _MoneyMapMiniRow(
                  label: e.key,
                  amount: e.value,
                  total: snapshot.investmentTotal,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MoneyAreaTransactionsPage(
                        title: '${e.key} · $periodLabel',
                        area: e.key,
                        kind: 'investment',
                        startMs: startMs,
                        endMs: endMs,
                      ),
                    ),
                  ),
                )),
          const SizedBox(height: 6),
          Text(
            'Investment areas are inferred locally from your recorded category, merchant and transaction text. Unclear items stay unidentified.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _MoneyMapTotal extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  const _MoneyMapTotal({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money.format(value), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MoneyMapMiniRow extends StatelessWidget {
  final String label;
  final double amount;
  final double total;
  final VoidCallback? onTap;
  const _MoneyMapMiniRow({required this.label, required this.amount, required this.total, this.onTap});

  @override
  Widget build(BuildContext context) {
    final share = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0).toDouble();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(width: 8),
                      Text('${(share * 100).round()}%', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(value: share, minHeight: 6, backgroundColor: Theme.of(context).dividerColor.withValues(alpha: .4)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(money.format(amount), style: const TextStyle(fontWeight: FontWeight.w900)),
            if (onTap != null) ...[const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, size: 18)],
          ],
        ),
      ),
    );
  }
}

class _FinancialAssistantPreview extends StatelessWidget {
  final FinancialAssistantSnapshot snapshot;
  const _FinancialAssistantPreview({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final hasSaving = snapshot.potentialSaving >= 250;
    final hasCommitments = snapshot.upcomingCommitments > 0;
    final forecastText = snapshot.forecastLikely > 0
        ? '${money.format(snapshot.forecastLow)} – ${money.format(snapshot.forecastHigh)}'
        : 'Building history';
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialAssistantPage())),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasSaving
                            ? 'Potential saving: ${money.format(snapshot.potentialSaving)} / month'
                            : hasCommitments
                                ? 'Upcoming commitments: ${money.format(snapshot.upcomingCommitments)}'
                                : 'Ask about your money',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hasSaving
                            ? 'Open a category-by-category action plan instead of another report.'
                            : hasCommitments
                                ? 'These are only recurring payments you explicitly confirmed.'
                                : 'Ask why spending changed, where to save, or what your month may finish at.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(child: _AssistantMiniMetric(label: 'Forecast range', value: forecastText)),
                const SizedBox(width: 10),
                Expanded(child: _AssistantMiniMetric(label: 'Confirmed commitments', value: money.format(snapshot.upcomingCommitments))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _AssistantMiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      );
}

class MoneyMapPage extends StatefulWidget {
  final String initialPeriod;
  final DateTimeRange? initialCustomRange;
  const MoneyMapPage({super.key, this.initialPeriod = 'month', this.initialCustomRange});

  @override
  State<MoneyMapPage> createState() => _MoneyMapPageState();
}

class _MoneyMapPageState extends State<MoneyMapPage> {
  late String period;
  DateTimeRange? customRange;

  @override
  void initState() {
    super.initState();
    period = ['total', 'month', 'week', 'day', 'custom'].contains(widget.initialPeriod) ? widget.initialPeriod : 'week';
    customRange = widget.initialCustomRange;
  }

  (int, int) _range() {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    if (period == 'day') {
      return (DateTime(now.year, now.month, now.day).millisecondsSinceEpoch, todayEnd);
    }
    if (period == 'week') {
      final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      return (start.millisecondsSinceEpoch, todayEnd);
    }
    if (period == 'total') {
      return (0, todayEnd);
    }
    if (period == 'custom' && customRange != null) {
      final s = customRange!.start;
      final e = customRange!.end;
      return (
        DateTime(s.year, s.month, s.day).millisecondsSinceEpoch,
        DateTime(e.year, e.month, e.day + 1).millisecondsSinceEpoch,
      );
    }
    return (DateTime(now.year, now.month, 1).millisecondsSinceEpoch, todayEnd);
  }

  String get _label {
    if (period == 'day') return 'Today';
    if (period == 'week') return 'This week';
    if (period == 'total') return 'All recorded transactions';
    if (period == 'custom' && customRange != null) {
      return '${DateFormat('dd MMM').format(customRange!.start)} – ${DateFormat('dd MMM yyyy').format(customRange!.end)}';
    }
    return DateFormat('MMMM yyyy').format(DateTime.now());
  }

  Future<void> _select(String value) async {
    if (value != 'custom') {
      setState(() => period = value);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: now,
      initialDateRange: customRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: 'Select Money Map range',
    );
    if (picked != null && mounted) {
      setState(() { customRange = picked; period = 'custom'; });
      await AppDb.instance.setSetting('home_period_filter', 'custom');
      await AppDb.instance.setSetting('home_custom_start', picked.start.millisecondsSinceEpoch.toString());
      await AppDb.instance.setSetting('home_custom_end', picked.end.millisecondsSinceEpoch.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range();
    return Scaffold(
      appBar: AppBar(title: const Text('Money Map')),
      body: FutureBuilder<MoneyMapSnapshot>(
        future: FinancialAiEngine.instance.moneyMap(range.$1, range.$2),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final map = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              Text('See where your money is going without mixing spending and investing.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              Wrap(
                spacing: FintechSpace.xs,
                runSpacing: FintechSpace.xs,
                children: [
                  FintechFilterPill(label: 'Week', icon: Icons.date_range_rounded, selected: period == 'week', onTap: () => _select('week')),
                  FintechFilterPill(label: 'Month', icon: Icons.calendar_month_rounded, selected: period == 'month', onTap: () => _select('month')),
                  FintechFilterPill(label: 'Day', icon: Icons.today_rounded, selected: period == 'day', onTap: () => _select('day')),
                  FintechFilterPill(label: 'Total', icon: Icons.all_inclusive_rounded, selected: period == 'total', onTap: () => _select('total')),
                  FintechFilterPill(label: 'Custom', icon: Icons.tune_rounded, selected: period == 'custom', onTap: () => _select('custom')),
                ],
              ),
              const SizedBox(height: 6),
              Text(_label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _MoneyMapTotal(label: 'Expense', value: map.expenseTotal, icon: Icons.south_east_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _MoneyMapTotal(label: 'Investment', value: map.investmentTotal, icon: Icons.trending_up_rounded)),
                ],
              ),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Spending areas', subtitle: 'Tap an area to see its transactions'),
              const SizedBox(height: 10),
              if (map.spendingAreas.isEmpty)
                const EmptyCard(text: 'No expense data for this period.')
              else
                ...map.spendingAreas.entries.map((e) => _MoneyMapDetailRow(
                      label: e.key,
                      amount: e.value,
                      total: map.expenseTotal,
                      icon: Icons.category_outlined,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MoneyAreaTransactionsPage(
                            title: '${e.key} · $_label',
                            area: e.key,
                            kind: 'expense',
                            startMs: range.$1,
                            endMs: range.$2,
                          ),
                        ),
                      ),
                    )),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Investment areas', subtitle: 'Locally inferred from the investment records the app can identify'),
              const SizedBox(height: 10),
              if (map.investmentAreas.isEmpty)
                const EmptyCard(text: 'No investments identified for this period.')
              else
                ...map.investmentAreas.entries.map((e) => _MoneyMapDetailRow(
                      label: e.key,
                      amount: e.value,
                      total: map.investmentTotal,
                      icon: Icons.pie_chart_outline_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MoneyAreaTransactionsPage(
                            title: '${e.key} · $_label',
                            area: e.key,
                            kind: 'investment',
                            startMs: range.$1,
                            endMs: range.$2,
                          ),
                        ),
                      ),
                    )),
              if (map.investmentCategories.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionHeader(title: 'Investment types', subtitle: 'Tap a type to view recorded transactions'),
                const SizedBox(height: 10),
                ...map.investmentCategories.entries.map((e) => _MoneyMapDetailRow(
                      label: e.key,
                      amount: e.value,
                      total: map.investmentTotal,
                      icon: Icons.account_balance_outlined,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FilteredTransactionsPage(
                            title: '${e.key} · $_label',
                            type: 'investment',
                            category: e.key,
                            startMs: range.$1,
                            endMs: range.$2,
                          ),
                        ),
                      ),
                    )),
              ],
              const SizedBox(height: 14),
              Text(
                'Area labels are best-effort local classifications. They describe recorded concentration and are not recommendations to buy or sell investments.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }
}


class MoneyAreaTransactionsPage extends StatelessWidget {
  final String title;
  final String area;
  final String kind;
  final int startMs;
  final int endMs;

  const MoneyAreaTransactionsPage({
    super.key,
    required this.title,
    required this.area,
    required this.kind,
    required this.startMs,
    required this.endMs,
  });

  Future<List<TxRecord>> _load() => kind == 'investment'
      ? FinancialAiEngine.instance.transactionsForInvestmentArea(area, startMs, endMs)
      : FinancialAiEngine.instance.transactionsForSpendingArea(area, startMs, endMs);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<List<TxRecord>>(
          future: _load(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No transactions found'));
            final total = rows.fold<double>(0, (sum, tx) => sum + tx.amount);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('${rows.length} transaction${rows.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(width: 10),
                      FittedBox(fit: BoxFit.scaleDown, child: Text(moneyExact.format(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...rows.map((tx) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: TransactionTile(
                        tx: tx,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailsPage(transaction: tx))),
                      ),
                    )),
              ],
            );
          },
        ),
      );
}

class _MoneyMapDetailRow extends StatelessWidget {
  final String label;
  final double amount;
  final double total;
  final IconData icon;
  final VoidCallback? onTap;
  const _MoneyMapDetailRow({required this.label, required this.amount, required this.total, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final share = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                        Text('${(share * 100).round()}%', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: share, minHeight: 6)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(money.format(amount), style: const TextStyle(fontWeight: FontWeight.w900)),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class FinancialAssistantPage extends StatefulWidget {
  final bool embedded;
  const FinancialAssistantPage({super.key, this.embedded = false});

  @override
  State<FinancialAssistantPage> createState() => _FinancialAssistantPageState();
}

class _FinancialAssistantPageState extends State<FinancialAssistantPage> {
  final question = TextEditingController();
  final goalAmount = TextEditingController();
  bool asking = false;
  bool planning = false;
  AssistantAnswer? answer;
  SavingsGoalPlan? goal;
  DateTime? goalDeadline;

  static const suggestions = [
    'Where can I save ₹5,000?',
    'Why did I spend more this month?',
    'Compare this month with last month',
    'What recurring payments are coming?',
    'Where am I investing most?',
    'Forecast this month',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedGoal();
  }

  Future<void> _loadSavedGoal() async {
    final amount = double.tryParse(await AppDb.instance.getSetting('savings_goal_amount', fallback: ''));
    final deadlineMs = int.tryParse(await AppDb.instance.getSetting('savings_goal_deadline', fallback: ''));
    if (amount != null && amount > 0 && deadlineMs != null && deadlineMs > DateTime.now().millisecondsSinceEpoch) {
      goalAmount.text = amount.toStringAsFixed(0);
      goalDeadline = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
      final plan = await FinancialAiEngine.instance.goalPlan(targetAmount: amount, deadline: goalDeadline!);
      if (mounted) setState(() => goal = plan);
    }
  }

  Future<void> _ask([String? preset]) async {
    final text = (preset ?? question.text).trim();
    if (text.isEmpty || asking) return;
    question.text = text;
    FocusScope.of(context).unfocus();
    setState(() => asking = true);
    try {
      final result = await FinancialAiEngine.instance.answerQuestion(text);
      if (mounted) setState(() => answer = result);
    } finally {
      if (mounted) setState(() => asking = false);
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month + 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDate: goalDeadline ?? DateTime(now.year, now.month + 6, now.day),
      helpText: 'Savings goal deadline',
    );
    if (picked != null && mounted) setState(() => goalDeadline = picked);
  }

  Future<void> _planGoal() async {
    final value = double.tryParse(goalAmount.text.replaceAll(',', '').trim());
    if (value == null || value <= 0 || goalDeadline == null || planning) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a target amount and choose a deadline.')));
      return;
    }
    setState(() => planning = true);
    try {
      final plan = await FinancialAiEngine.instance.goalPlan(targetAmount: value, deadline: goalDeadline!);
      await AppDb.instance.setSetting('savings_goal_amount', value.toString());
      await AppDb.instance.setSetting('savings_goal_deadline', goalDeadline!.millisecondsSinceEpoch.toString());
      if (mounted) setState(() => goal = plan);
    } finally {
      if (mounted) setState(() => planning = false);
    }
  }

  void _openAnswerTransactions() {
    final a = answer;
    if (a == null || !a.hasTransactionDrilldown) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilteredTransactionsPage(
          title: a.transactionLabel,
          startMs: a.startMs,
          endMs: a.endMs,
          type: a.type,
          category: a.category,
          merchant: a.merchant,
        ),
      ),
    );
  }

  @override
  void dispose() {
    question.dispose();
    goalAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
          children: [
            if (!widget.embedded) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Plan with your transaction data', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(
                    'This is local financial analysis, not a general AI chatbot. Ask practical questions and get answers grounded in your cleaned transactions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: question,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: InputDecoration(
                      hintText: 'e.g. Where can I save ₹5,000 next month?',
                      prefixIcon: const Icon(Icons.auto_awesome_rounded),
                      suffixIcon: IconButton(onPressed: asking ? null : _ask, icon: const Icon(Icons.arrow_upward_rounded)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: suggestions.map((item) => ActionChip(label: Text(item), onPressed: asking ? null : () => _ask(item))).toList(),
                  ),
                ],
              ),
            ),
            if (asking) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
            if (answer != null) ...[
              const SizedBox(height: 20),
              _AssistantAnswerCard(answer: answer!, onShowTransactions: answer!.hasTransactionDrilldown ? _openAnswerTransactions : null),
            ],
            ],
            if (widget.embedded) ...[
              FintechSurface(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAdvisorPage())),
                tint: const Color(0xFFEAF6EE),
                child: const Row(children: [
                  CircleAvatar(child: Icon(Icons.auto_awesome_rounded)),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('AI Advisor', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    SizedBox(height: 2),
                    Text('Ask questions using your selected AI provider'),
                  ])),
                  Icon(Icons.chevron_right_rounded),
                ]),
              ),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 24),
            const SectionHeader(title: 'Your savings goal', subtitle: 'Set a target and get the monthly gap plus a realistic action plan'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: goalAmount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Target amount', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickDeadline,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(goalDeadline == null ? 'Choose deadline' : DateFormat('dd MMM yyyy').format(goalDeadline!)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: planning ? null : _planGoal,
                      icon: const Icon(Icons.flag_rounded),
                      label: Text(planning ? 'Calculating…' : 'Build my plan'),
                    ),
                  ),
                  if (goal != null) ...[
                    const SizedBox(height: 18),
                    _GoalPlanView(plan: goal!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'This planner runs locally from structured transaction data. It does not send SMS text to a server. Savings suggestions avoid fixed costs and investments by default, and investment observations are descriptive rather than buy/sell advice.',
                style: TextStyle(height: 1.45),
              ),
            ),
          ],
        );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Money planner')),
      body: content,
    );
  }
}

class _AssistantAnswerCard extends StatelessWidget {
  final AssistantAnswer answer;
  final VoidCallback? onShowTransactions;
  const _AssistantAnswerCard({required this.answer, this.onShowTransactions});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.auto_awesome_rounded, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(child: Text(answer.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 12),
            Text(answer.answer, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
            if (answer.amount != null) ...[
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(moneyExact.format(answer.amount), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
              ),
            ],
            if (answer.points.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...answer.points.map((point) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6)),
                        const SizedBox(width: 9),
                        Expanded(child: Text(point, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45))),
                      ],
                    ),
                  )),
            ],
            if (onShowTransactions != null) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onShowTransactions,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(answer.transactionLabel),
              ),
            ],
          ],
        ),
      );
}

class _GoalPlanView extends StatelessWidget {
  final SavingsGoalPlan plan;
  const _GoalPlanView({required this.plan});

  @override
  Widget build(BuildContext context) {
    final covered = plan.actions.fold<double>(0, (a, b) => a + b.savingAmount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.looksAchievable ? 'Your recorded cash flow can support this target' : 'Monthly gap to close',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 10),
        _GoalMetric(label: 'Required per month', value: money.format(plan.requiredMonthly)),
        _GoalMetric(label: 'Recent recorded capacity', value: plan.recentMonthlyCapacity > 0 ? money.format(plan.recentMonthlyCapacity) : 'Not enough income data'),
        if (plan.monthlyGap > 0) _GoalMetric(label: 'Gap', value: money.format(plan.monthlyGap)),
        const SizedBox(height: 10),
        if (plan.monthlyGap > 0 && plan.actions.isEmpty)
          const Text('I could not find enough discretionary history to build a safe cut plan. Correcting Uncategorized transactions will make this more useful.')
        else if (plan.actions.isNotEmpty) ...[
          Text('Suggested monthly changes · about ${money.format(covered)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...plan.actions.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• ${a.title}: aim for ${money.format(a.targetAmount)} instead of ~${money.format(a.currentAmount)} (save ~${money.format(a.savingAmount)})'),
              )),
        ],
      ],
    );
  }
}

class _GoalMetric extends StatelessWidget {
  final String label;
  final String value;
  const _GoalMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(width: 10),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900)))),
          ],
        ),
      );
}

class TransactionsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const TransactionsPage({super.key, required this.onChanged});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Row(
            children: [
              const Expanded(child: PageHeader(title: 'Activity', subtitle: 'Your recent transactions')),
              IconButton(
                onPressed: () async {
                  await showAddTransaction(context);
                  if (mounted) setState(() {});
                  widget.onChanged();
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: const ['all', 'expense', 'investment', 'income']
                .map((t) {
                  final selected = filter == t;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FintechFilterPill(
                      label: switch (t) { 'all' => 'All', 'expense' => 'Expenses', 'investment' => 'Investments', _ => 'Income' },
                      selected: selected,
                      onTap: () => setState(() => filter = t),
                    ),
                  );
                })
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<TxRecord>>(
            future: AppDb.instance.transactions(type: filter),
            builder: (context, snap) {
              if (snap.hasError) return ErrorView(message: '${snap.error}');
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.isEmpty) return const Center(child: Text('No transactions'));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
                itemCount: snap.data!.length,
                itemBuilder: (context, i) {
                  final tx = snap.data![i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TransactionTile(
                      tx: tx,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => TransactionDetailsPage(transaction: tx)),
                        );
                        if (mounted) setState(() {});
                        widget.onChanged();
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}


class FilteredTransactionsPage extends StatefulWidget {
  final String title;
  final int? startMs;
  final int? endMs;
  final String type;
  final String category;
  final String merchant;

  const FilteredTransactionsPage({
    super.key,
    required this.title,
    this.startMs,
    this.endMs,
    this.type = 'all',
    this.category = '',
    this.merchant = '',
  });

  @override
  State<FilteredTransactionsPage> createState() => _FilteredTransactionsPageState();
}

class _FilteredTransactionsPageState extends State<FilteredTransactionsPage> {
  Future<List<TxRecord>> _load() => AppDb.instance.searchTransactions(
        type: widget.type,
        category: widget.category,
        merchant: widget.merchant,
        startMs: widget.startMs,
        endMs: widget.endMs,
        limit: 1000,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: FutureBuilder<List<TxRecord>>(
          future: _load(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Center(child: Text('No transactions found'));
            final total = rows.fold<double>(0, (sum, tx) => sum + tx.amount);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('${rows.length} transaction${rows.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      if (widget.category.isEmpty)
                        FittedBox(fit: BoxFit.scaleDown, child: Text(moneyExact.format(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...rows.map((tx) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: TransactionTile(
                        tx: tx,
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailsPage(transaction: tx)));
                          if (mounted) setState(() {});
                        },
                      ),
                    )),
              ],
            );
          },
        ),
      );
}

class TransactionDetailsPage extends StatefulWidget {
  final TxRecord transaction;
  const TransactionDetailsPage({super.key, required this.transaction});

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  late TxRecord tx;

  @override
  void initState() {
    super.initState();
    tx = widget.transaction;
  }

  Future<void> _edit() async {
    await editTransaction(context, tx);
    if (tx.id == null) return;
    final updated = await AppDb.instance.transactionById(tx.id!);
    if (!mounted) return;
    if (updated == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => tx = updated);
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _transactionTypeColor(tx.type);
    final sourceName = sourceLabel(tx.source);
    final rawLabel = tx.source == 'sms'
        ? 'Full SMS message'
        : tx.source == 'phonepe_notification'
            ? 'Full PhonePe notification'
            : 'Raw transaction response';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction details'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE4EBE7)),
              boxShadow: const [
                BoxShadow(color: Color(0x0B000000), blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(iconFor(tx.category), color: typeColor),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.merchant,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF18231D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)),
                            style: const TextStyle(color: Color(0xFF758078)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${tx.type == 'income' || tx.type == 'refund' ? '+' : '-'}${moneyExact.format(tx.amount)}',
                      style: TextStyle(
                        color: typeColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailChip(titleCase(tx.type), typeColor),
                    _detailChip(tx.category, const Color(0xFF4B5A51)),
                    _detailChip(sourceName, const Color(0xFF2879E0)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DetailSection(
            title: 'Payment details',
            children: [
              _detailRow('Amount', moneyExact.format(tx.amount)),
              _detailRow('Type', titleCase(tx.type)),
              _detailRow('Category', tx.category),
              _detailRow('Source', sourceName),
              if (tx.paymentMethod.isNotEmpty) _detailRow('Payment method', tx.paymentMethod),
              if (tx.sender.isNotEmpty) _detailRow('SMS sender', tx.sender),
              if (tx.accountHint.isNotEmpty) _detailRow('Account / card', '•••• ${tx.accountHint}'),
              if (tx.upiReference.isNotEmpty) _detailRow('UPI / reference', tx.upiReference),
              if (tx.source == 'sms' || tx.source == 'phonepe_notification')
                _detailRow(
                  'Classification',
                  '${classifierLabel(tx.classificationMethod)} · ${(tx.classificationConfidence * 100).round()}%',
                ),
            ],
          ),
          if (tx.source == 'sms' || tx.source == 'phonepe_notification') ...[
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Why this classification?',
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.psychology_alt_outlined, size: 20),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classificationExplanation(tx),
                            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: tx.classificationConfidence.clamp(0.0, 1.0).toDouble(),
                              minHeight: 7,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${(tx.classificationConfidence * 100).round()}% confidence • ${classifierLabel(tx.classificationMethod)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'If this is wrong, tap Edit transaction. You can apply the correction only here or to the same message pattern and future matching messages.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ],
          if (tx.note.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Note',
              children: [
                SelectableText(
                  tx.note,
                  style: const TextStyle(
                    color: Color(0xFF344139),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ],
          if (tx.rawMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _DetailSection(
              title: rawLabel,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F8F6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE1E8E4)),
                  ),
                  child: SelectableText(
                    tx.rawMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF2E3932),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (tx.type == 'expense' && tx.id != null) ...[
            OutlinedButton.icon(
              onPressed: () async {
                final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SplitTransactionPage(transaction: tx)));
                if (changed == true && mounted) setState(() {});
              },
              icon: const Icon(Icons.call_split_rounded),
              label: Text(tx.isSplitParent ? 'Edit split transaction' : 'Split transaction'),
            ),
            const SizedBox(height: 8),
          ],
          if (tx.type == 'expense' || tx.type == 'investment') ...[
            OutlinedButton.icon(
              onPressed: () async {
                final saved = await showMarkRecurringDialog(context, tx);
                if (saved && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to recurring payments')));
                }
              },
              icon: const Icon(Icons.repeat_rounded),
              label: const Text('Mark as recurring'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit transaction'),
          ),
        ],
      ),
    );
  }

  static Widget _detailChip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      );

  static Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF7A857E), fontSize: 13),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(
                  color: Color(0xFF253129),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4EBE7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF1E2A23),
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class PayUpiPage extends StatefulWidget {
  final VoidCallback onChanged;
  const PayUpiPage({super.key, required this.onChanged});

  @override
  State<PayUpiPage> createState() => _PayUpiPageState();
}

class _PayUpiPageState extends State<PayUpiPage> {
  final upi = TextEditingController();
  final payee = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  String category = 'Uncategorized';
  bool paying = false;
  bool scannedQr = false;
  String? scannedRawQr;
  bool scannedQrHasFixedAmount = false;
  double? scannedMinimumAmount;
  bool scannedQrSigned = false;
  bool scannedQrMerchant = false;

  @override
  void dispose() {
    upi.dispose();
    payee.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> scanQr() async {
    final result = await Navigator.push<UpiQrData>(
      context,
      MaterialPageRoute(builder: (_) => const UpiQrScannerPage()),
    );
    if (!mounted || result == null) return;

    setState(() {
      upi.text = result.upiId;
      if (result.payeeName.isNotEmpty) payee.text = result.payeeName;
      if (result.amount != null && result.amount! > 0) {
        amount.text = result.amount!.toStringAsFixed(2);
      }
      if (result.note.isNotEmpty) note.text = result.note;
      scannedQr = true;
      scannedRawQr = result.raw;
      scannedQrHasFixedAmount = result.hasAmount && !result.hasMinimumAmount;
      scannedMinimumAmount = result.minimumAmount;
      scannedQrSigned = result.hasSignedPayload;
      scannedQrMerchant = result.isMerchant;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('UPI QR scanned. Review the details before paying.')),
    );
  }

  String _buildUpiUri(double? value) {
    // QR payloads may include merchant-specific or signed fields. Never rewrite
    // or re-encode any scanned UPI URI; even optional fields may be significant.
    final raw = scannedRawQr?.trim();
    if (scannedQr && raw != null && raw.isNotEmpty) {
      final original = Uri.tryParse(raw);
      if (original == null ||
          original.scheme.toLowerCase() != 'upi' ||
          original.host.toLowerCase() != 'pay' ||
          (original.queryParameters['pa'] ?? '').trim().isEmpty) {
        throw const FormatException('The scanned QR is not a valid UPI payment request.');
      }
      return raw;
    }

    if (value == null || value <= 0) {
      throw const FormatException('A valid amount is required for a manually entered UPI payment.');
    }
    final params = <String, String>{
      'pa': upi.text.trim(),
      'pn': payee.text.trim().isEmpty ? upi.text.trim() : payee.text.trim(),
      'am': value.toStringAsFixed(2),
      'cu': 'INR',
    };
    if (note.text.trim().isNotEmpty) params['tn'] = note.text.trim();
    return Uri(scheme: 'upi', host: 'pay', queryParameters: params).toString();
  }

  Future<void> _showProviderFallback() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Payment not confirmed'),
        content: const Text(
          'Some UPI apps restrict payments initiated by other apps. '
          'No payment has been recorded. Open PhonePe or Paytm directly '
          'and scan the original QR in that app, or enter the recipient UPI ID. '
          'Check your bank history before trying again to avoid duplicate payments.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: upi.text.trim()));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recipient UPI ID copied.')),
              );
            },
            child: const Text('Copy UPI ID'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<String?> _chooseUpiApp(String paymentUri) async {
    final apps = await NativeBridge.getUpiApps(paymentUri: paymentUri);
    if (!mounted) return null;
    if (apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No UPI-ready app was found. Open Paytm, PhonePe, Google Pay or BHIM once and finish UPI setup, then try again.')),
      );
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          children: [
            const ListTile(
              title: Text('Choose how to pay', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              subtitle: Text('Only UPI-ready apps detected on this phone are shown.'),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.apps_rounded)),
              title: const Text('Pay by any UPI app', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text("Use Android's UPI chooser"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(sheetContext, '__ANY__'),
            ),
            const Divider(),
            ...apps.map((app) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
                  title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => Navigator.pop(sheetContext, app.packageName),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _openProviderHome(String provider) async {
    try {
      final opened = await NativeBridge.openPaymentApp(provider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(opened
          ? '${provider == 'phonepe' ? 'PhonePe' : 'Paytm'} opened. Scan and pay inside the app. Expense Tracker will look for a confirmed bank SMS or available payment notification; opening the app does not confirm payment.'
          : 'Unable to launch the payment app.')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Payment app not available.')));
    }
  }

  Future<void> pay() async {
    final parsedValue = double.tryParse(amount.text.replaceAll(',', '').trim());
    final signedStaticQrWithoutAmount = scannedQr && scannedQrSigned && !scannedQrHasFixedAmount &&
        ((Uri.tryParse(scannedRawQr ?? '')?.queryParameters['am'] ?? '').trim().isEmpty);

    if (upi.text.trim().isEmpty || !upi.text.trim().contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter or scan a valid UPI ID.')));
      return;
    }
    if (!signedStaticQrWithoutAmount && (parsedValue == null || parsedValue <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    final minAmount = scannedMinimumAmount;
    if (parsedValue != null && minAmount != null && minAmount > 0 && parsedValue < minAmount) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This QR requires at least ₹${money.format(minAmount)}.')));
      return;
    }

    setState(() => paying = true);
    try {
      final paymentUri = _buildUpiUri(parsedValue);
      final selected = await _chooseUpiApp(paymentUri);
      if (!mounted || selected == null) return;

      final result = await NativeBridge.startUpiPayment(
        paymentUri: paymentUri,
        packageName: selected == '__ANY__' ? null : selected,
      );
      if (!mounted) return;
      if (result.success) {
        final ref = result.txnId.isNotEmpty ? result.txnId : (result.txnRef.isNotEmpty ? result.txnRef : result.approvalRefNo);
        // When a signed static QR contains no amount, we deliberately pass it untouched.
        // The PSP app collects the actual amount; SMS/notification capture records the
        // authoritative transaction instead of creating a potentially wrong duplicate here.
        if (parsedValue != null && parsedValue > 0 && !signedStaticQrWithoutAmount) {
          await AppDb.instance.addUpiTransaction(
            amount: parsedValue,
            merchant: payee.text.trim().isEmpty ? upi.text.trim() : payee.text.trim(),
            category: category,
            note: note.text.trim(),
            upiReference: ref,
            rawResponse: result.raw,
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(signedStaticQrWithoutAmount
              ? 'Payment completed. The actual amount will be captured from your bank SMS/notification.'
              : 'Payment completed and saved.')),
        );
        amount.clear();
        note.clear();
        setState(() {
          scannedQr = false;
          scannedRawQr = null;
          scannedQrHasFixedAmount = false;
          scannedMinimumAmount = null;
          scannedQrSigned = false;
          scannedQrMerchant = false;
        });
        widget.onChanged();
      } else {
        final statusText = result.status == 'pending'
            ? 'Payment is pending. Nothing was saved yet; bank SMS/notification will confirm it.'
            : 'Payment not confirmed (${result.status}). Nothing was saved.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(statusText)));
        if (result.status != 'pending') await _showProviderFallback();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'UPI_APP_NOT_READY' => 'That UPI app is installed but is not ready for this payment. Finish UPI setup in the app or choose another app.',
        'NO_UPI_APP' => 'No compatible UPI-ready app was found on this phone.',
        _ => e.message ?? 'Could not open the UPI app.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _showProviderFallback();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open UPI payment: $e')));
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) => DirectAppPayPage(onChanged: widget.onChanged);

  // The old QR/manual flow remains in source for existing deep links, but this
  // screen intentionally launches payment apps directly as requested.
  Widget _legacyPaymentForm(BuildContext context) {
    return FutureBuilder<List<CategoryRecord>>(
      future: AppDb.instance.expenseCategories(),
      builder: (context, snap) {
        final cats = snap.data ?? const <CategoryRecord>[];
        if (cats.isNotEmpty && !cats.any((c) => c.name == category)) category = cats.first.name;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 104),
          children: [
            const PageHeader(title: 'Pay with UPI', subtitle: 'Scan a UPI QR or enter payment details manually'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF08794D), Color(0xFF12A866)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Color(0x2608794D), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(17)),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 30),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Scan UPI QR', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                            SizedBox(height: 3),
                            Text('PhonePe, GPay, Paytm or any standard UPI QR', style: TextStyle(color: Color(0xFFD9F8E8), fontSize: 12.5, height: 1.3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF087849),
                      ),
                      onPressed: paying ? null : scanQr,
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      label: Text(scannedQr ? 'Scan another QR' : 'Open QR scanner'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    scannedQr ? 'REVIEW SCANNED DETAILS' : 'OR ENTER MANUALLY',
                    style: const TextStyle(fontSize: 10.5, letterSpacing: .8, color: Color(0xFF77827B), fontWeight: FontWeight.w900),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: upi, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Recipient UPI ID', hintText: 'name@bank', prefixIcon: Icon(Icons.alternate_email_rounded))),
            const SizedBox(height: 12),
            TextField(controller: payee, decoration: const InputDecoration(labelText: 'Payee name', hintText: 'Person or merchant')),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              readOnly: scannedQrHasFixedAmount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                helperText: scannedQrHasFixedAmount ? 'Amount supplied by this QR and kept unchanged for payment compatibility.' : null,
              ),
            ),
            const SizedBox(height: 12),
            if (cats.isNotEmpty)
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: cats.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => category = v ?? category),
              ),
            const SizedBox(height: 12),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note / remark', hintText: 'Example: Dinner with client')),
            const SizedBox(height: 10),
            Text(
              scannedQrSigned
                  ? 'Signed merchant QR detected. Its original UPI payload is passed unchanged so Paytm/PhonePe/GPay/BHIM can verify it correctly.'
                  : scannedQrMerchant
                      ? 'Merchant QR detected. Merchant/reference parameters are preserved. You can choose any UPI-ready app found on this phone.'
                      : 'You can pay with Paytm, Google Pay, PhonePe, BHIM or any other UPI-ready app detected on this phone.',
              style: const TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final id = upi.text.trim();
                if (id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter or scan a UPI ID first.')));
                  return;
                }
                await Clipboard.setData(ClipboardData(text: id));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('UPI ID copied. You can paste/search it directly inside your UPI app if an external payment is blocked.')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy UPI ID'),
            ),
            const SizedBox(height: 18),
            const Text('Open payment app directly', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('No UPI ID, amount, or QR is sent. Scan and complete the payment inside your chosen app. Expense Tracker can later detect a confirmed SMS or notification; no automatic payment callback is available.'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: paying ? null : () => _openProviderHome('phonepe'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('PhonePe'),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: paying ? null : () => _openProviderHome('paytm'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Paytm'),
              )),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: paying ? null : pay,
              icon: paying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_balance_wallet_outlined),
              label: Text(paying ? 'Opening UPI apps…' : 'Pay with UPI app'),
            ),
          ],
        );
      },
    );
  }
}


class DirectAppPayPage extends StatefulWidget {
  final VoidCallback onChanged;
  const DirectAppPayPage({super.key, required this.onChanged});

  @override
  State<DirectAppPayPage> createState() => _DirectAppPayPageState();
}

class _DirectAppPayPageState extends State<DirectAppPayPage> {
  static const _discoveryUri = 'upi://pay?pa=expense.tracker%40upi&pn=Expense%20Tracker&am=1&cu=INR';
  late Future<List<UpiApp>> _apps = NativeBridge.getUpiApps(paymentUri: _discoveryUri);

  Future<void> _launch(UpiApp app) async {
    try {
      await NativeBridge.openPaymentPackage(app.packageName);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${app.name} opened. Complete your payment inside the app.')));
    } on PlatformException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Could not open ${app.name}.')));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<UpiApp>>(
        future: _apps,
        builder: (context, snapshot) {
          final apps = snapshot.data ?? const <UpiApp>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 104),
            children: [
              const PageHeader(title: 'Pay', subtitle: 'Choose a payment app'),
              const SizedBox(height: 22),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError || apps.isEmpty)
                FintechSurface(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 28),
                    const SizedBox(height: 12),
                    const Text('No payment app found', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    const SizedBox(height: 4),
                    const Text('Install or finish setting up a UPI app, then refresh this screen.'),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(onPressed: () => setState(() => _apps = NativeBridge.getUpiApps(paymentUri: _discoveryUri)), icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh')),
                  ]),
                )
              else
                FintechSurface(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var index = 0; index < apps.length; index++) ...[
                      _PaymentAppRow(app: apps[index], onTap: () => _launch(apps[index])),
                      if (index < apps.length - 1) const Divider(height: 1),
                    ],
                  ]),
                ),
              const SizedBox(height: 20),
              Text('Your transaction will be completed inside the payment app. This screen does not ask for a QR, UPI ID, or amount.', style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
            ],
          );
        },
      );
}

class _PaymentAppRow extends StatelessWidget {
  final UpiApp app;
  final VoidCallback onTap;
  const _PaymentAppRow({required this.app, required this.onTap});

  String get _subtitle => switch (app.name.toLowerCase()) {
        'phonepe' => 'Pay securely with your bank account',
        'google pay' => 'Fast and secure payments',
        'paytm' => 'Simple and reliable payments',
        'bhim' => 'A secure way to pay',
        _ => 'Open and pay securely in this app',
      };

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: Container(
          width: 34,
          height: 34,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFFEAF5EF), borderRadius: BorderRadius.circular(10)),
          child: app.iconBytes == null
              ? const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF08794D), size: 18)
              : Image.memory(app.iconBytes!, fit: BoxFit.cover),
        ),
        title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(_subtitle),
        trailing: const Icon(Icons.chevron_right_rounded, size: 22),
        onTap: onTap,
      );
}


class UpiQrData {
  final String upiId;
  final String payeeName;
  final double? amount;
  final String note;
  final String transactionRef;
  final String raw;
  final bool hasAmount;
  final double? minimumAmount;
  final bool hasMinimumAmount;
  final bool hasSignedPayload;
  final bool isMerchant;

  const UpiQrData({
    required this.upiId,
    required this.payeeName,
    required this.amount,
    required this.note,
    required this.transactionRef,
    required this.raw,
    required this.hasAmount,
    required this.minimumAmount,
    required this.hasMinimumAmount,
    required this.hasSignedPayload,
    required this.isMerchant,
  });

  static UpiQrData? parse(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != 'upi' || uri.host.toLowerCase() != 'pay') {
      return null;
    }

    final upiId = (uri.queryParameters['pa'] ?? '').trim();
    if (upiId.isEmpty || !upiId.contains('@')) return null;

    final amountText = (uri.queryParameters['am'] ?? '').replaceAll(',', '').trim();
    final parsedAmount = amountText.isEmpty ? null : double.tryParse(amountText);

    final minimumText = (uri.queryParameters['mam'] ?? '').replaceAll(',', '').trim();
    final minimumAmount = minimumText.isEmpty ? null : double.tryParse(minimumText);
    final hasSignature = (uri.queryParameters['sign'] ?? '').trim().isNotEmpty;
    final merchantSignals = <String>['mc', 'tr', 'mode', 'orgid', 'paytmqr', 'sign'];

    return UpiQrData(
      upiId: upiId,
      payeeName: (uri.queryParameters['pn'] ?? '').trim(),
      amount: parsedAmount,
      note: (uri.queryParameters['tn'] ?? '').trim(),
      transactionRef: (uri.queryParameters['tr'] ?? '').trim(),
      raw: value,
      hasAmount: amountText.isNotEmpty && parsedAmount != null && parsedAmount > 0,
      minimumAmount: minimumAmount,
      hasMinimumAmount: minimumAmount != null && minimumAmount > 0,
      hasSignedPayload: hasSignature,
      isMerchant: merchantSignals.any((key) => (uri.queryParameters[key] ?? '').trim().isNotEmpty),
    );
  }
}

class UpiQrScannerPage extends StatefulWidget {
  const UpiQrScannerPage({super.key});

  @override
  State<UpiQrScannerPage> createState() => _UpiQrScannerPageState();
}

class _UpiQrScannerPageState extends State<UpiQrScannerPage> {
  final MobileScannerController controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool handled = false;
  String? errorMessage;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (handled) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) return;

    final data = UpiQrData.parse(raw);
    if (data == null) {
      setState(() => errorMessage = 'This is not a valid UPI payment QR. Scan a QR containing a UPI payment address.');
      return;
    }

    handled = true;
    await controller.stop();
    if (!mounted) return;
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan UPI QR'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            onPressed: controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_rounded),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _handleCapture,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 255,
                height: 255,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x77000000), blurRadius: 28, spreadRadius: 8)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 34,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      errorMessage ?? 'Place the merchant UPI QR inside the frame. Payment details will be shown for review before anything is paid.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: errorMessage == null ? Colors.white : const Color(0xFFFFB4AB),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => setState(() => errorMessage = null),
                        child: const Text('Try another QR'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String period = 'month';
  int year = DateTime.now().year;
  int month = DateTime.now().month;

  (int, int) _range() {
    if (period == 'year') {
      return (
        DateTime(year, 1, 1).millisecondsSinceEpoch,
        DateTime(year + 1, 1, 1).millisecondsSinceEpoch,
      );
    }
    return (
      DateTime(year, month, 1).millisecondsSinceEpoch,
      DateTime(year, month + 1, 1).millisecondsSinceEpoch,
    );
  }

  Future<List<dynamic>> load() async {
    final range = _range();
    return [
      await AppDb.instance.availableYears(),
      await AppDb.instance.totalsByTypeForPeriod(range.$1, range.$2),
      await AppDb.instance.expenseByCategoryForPeriod(range.$1, range.$2),
      await AppDb.instance.expenseByMerchantForPeriod(range.$1, range.$2),
      await AppDb.instance.largestExpenseForPeriod(range.$1, range.$2),
      await AppDb.instance.monthlyExpenseForYear(year),
      await AppDb.instance.expenseTrendForPeriod(range.$1, range.$2, buckets: 5),
    ];
  }

  String get periodLabel => period == 'year'
      ? '$year'
      : DateFormat('MMMM yyyy').format(DateTime(year, month));

  void _openTransactions(String title, {String type = 'all', String category = '', String merchant = '', int? startMs, int? endMs}) {
    final range = _range();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilteredTransactionsPage(
          title: title,
          startMs: startMs ?? range.$1,
          endMs: endMs ?? range.$2,
          type: type,
          category: category,
          merchant: merchant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: load(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(message: '${snap.error}');
        if (!snap.hasData) return const AppLoadingView(label: 'Building your reports');

        final years = snap.data![0] as List<int>;
        final types = snap.data![1] as Map<String, double>;
        final categories = snap.data![2] as Map<String, double>;
        final merchants = snap.data![3] as Map<String, double>;
        final largest = snap.data![4] as TxRecord?;
        final monthly = snap.data![5] as List<double>;
        final selectedMonthTrend = snap.data![6] as List<double>;
        final trendValues = period == 'year' ? monthly : selectedMonthTrend;
        final trendLabels = period == 'year'
            ? const ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']
            : const ['Week 1', 'Week 2', 'Week 3', 'Week 4', 'Week 5'];

        final topCategory = categories.isEmpty ? null : categories.entries.first;
        final topMerchant = merchants.isEmpty ? null : merchants.entries.first;
        final totalExpense = types['expense'] ?? 0;

        double maxCategory = 1;
        for (final value in categories.values) {
          if (value > maxCategory) maxCategory = value;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 104),
          children: [
            PageHeader(title: 'Reports', subtitle: periodLabel),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'month', label: Text('Monthly'), icon: Icon(Icons.calendar_view_month_rounded)),
                ButtonSegment(value: 'year', label: Text('Yearly'), icon: Icon(Icons.calendar_today_rounded)),
              ],
              selected: {period},
              onSelectionChanged: (value) => setState(() => period = value.first),
              style: ButtonStyle(
                textStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: years.contains(year) ? year : years.first,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: years.map((value) => DropdownMenuItem(value: value, child: Text('$value'))).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => year = value);
                    },
                  ),
                ),
                if (period == 'month') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: month,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: List.generate(
                        12,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text(DateFormat.MMMM().format(DateTime(2024, index + 1))),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) setState(() => month = value);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Spending trend'),
            const SizedBox(height: 10),
            MonthlySpendChart(values: trendValues, labels: trendLabels),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Key numbers'),
            const SizedBox(height: 10),
            Column(children: [
              _ReportKeyNumber(title: 'Spending', value: money.format(totalExpense), icon: Icons.south_east_rounded, tint: const Color(0xFFFFECE8), onTap: () => _openTransactions('Expenses • $periodLabel', type: 'expense')),
              const SizedBox(height: 10),
              _ReportKeyNumber(title: 'Income', value: money.format(types['income'] ?? 0), icon: Icons.south_west_rounded, tint: const Color(0xFFEAF6EE), onTap: () => _openTransactions('Income • $periodLabel', type: 'income')),
              const SizedBox(height: 10),
              _ReportKeyNumber(title: 'Investments', value: money.format(types['investment'] ?? 0), icon: Icons.savings_rounded, tint: const Color(0xFFF0F4EA), onTap: () => _openTransactions('Investments • $periodLabel', type: 'investment')),
            ]),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Spending by category'),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              const EmptyCard(text: 'No expense data for this month.')
            else
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: categories.entries.take(10).map((entry) {
                    final ratio = maxCategory <= 0 ? 0.0 : entry.value / maxCategory;
                    final share = totalExpense <= 0 ? 0 : ((entry.value / totalExpense) * 100).round();
                    return InkWell(
                      onTap: () => _openTransactions('${entry.key} • $periodLabel', type: 'expense', category: entry.key),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16, top: 4),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  '${money.format(entry.value)} · $share%',
                                  style: const TextStyle(
                                    color: Color(0xFF59675E),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded, size: 18),
                              ],
                            ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                value: ratio.clamp(0.0, 1.0).toDouble(),
                                minHeight: 9,
                                backgroundColor: const Color(0xFFE9EFEB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Top merchants', subtitle: 'Highest total expense by merchant'),
            const SizedBox(height: 12),
            if (merchants.isEmpty)
              const EmptyCard(text: 'No merchant spending data for this period.')
            else
              ...merchants.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openTransactions('${entry.key} • $periodLabel', type: 'expense', merchant: entry.key),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF7F0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.storefront_outlined, color: Color(0xFF0A8B56), size: 20),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                entry.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(money.format(entry.value), style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReportKeyNumber extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  const _ReportKeyNumber({required this.title, required this.value, required this.icon, required this.tint, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .58), shape: BoxShape.circle), child: Icon(icon, color: const Color(0xFF1C5C45), size: 20)),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))])),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
        ),
      );
}

class _InsightCard extends StatelessWidget {
  final String title;
  final String value;
  final String amount;
  final IconData icon;
  final bool wide;
  final VoidCallback? onTap;

  const _InsightCard({
    required this.title,
    required this.value,
    required this.amount,
    required this.icon,
    this.wide = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(FintechRadius.card),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF7F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: const Color(0xFF0A8B56), size: 22),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7B8780), fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  value,
                  maxLines: wide ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0A8B56)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class MonthlySpendChart extends StatelessWidget {
  final List<double> values;
  final List<String>? labels;
  final ValueChanged<int>? onMonthTap;
  const MonthlySpendChart({super.key, required this.values, this.labels, this.onMonthTap});

  @override
  Widget build(BuildContext context) {
    final normalized = values.isEmpty ? const <double>[0] : values;
    final axisLabels = labels ?? List<String>.generate(normalized.length, (index) => DateFormat.MMM().format(DateTime(2024, index + 1)).substring(0, 1));
    var maxValue = 0.0;
    for (final v in normalized) {
      if (v > maxValue) maxValue = v;
    }
    final hasData = maxValue > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasData)
            Text(
              'Peak period: ${axisLabels[normalized.indexOf(maxValue)]} · ${money.format(maxValue)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4F5D54)),
            )
          else
            const Text('No expense data for this year.', style: TextStyle(color: Color(0xFF738078))),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(normalized.length, (index) {
                final value = normalized[index];
                final height = hasData ? (12 + (118 * (value / maxValue))).clamp(12.0, 130.0).toDouble() : 12.0;
                return Expanded(
                  child: InkWell(
                    onTap: value <= 0 || onMonthTap == null ? null : () => onMonthTap!(index + 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 16,
                              height: height,
                              decoration: BoxDecoration(
                                color: value == maxValue && value > 0
                                    ? const Color(0xFF0A8B56)
                                    : const Color(0xFFBFE7D1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(axisLabels[index], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Color(0xFF7B8780), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  Future<List<dynamic>> load() async => [await AppDb.instance.budgets(), await AppDb.instance.monthExpenseByCategory()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: FutureBuilder<List<dynamic>>(
        future: load(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: '${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final budgets = snap.data![0] as List<BudgetRecord>;
          final spending = snap.data![1] as Map<String, double>;
          BudgetRecord? overall;
          for (final b in budgets) {
            if (b.category == '__overall__') overall = b;
          }
          final total = spending.values.fold<double>(0, (a, b) => a + b);
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              BudgetCard(
                title: 'Overall budget',
                spent: total,
                budget: overall?.amount ?? 0,
                onTap: () async {
                  await budgetDialog(context, '__overall__', overall?.amount ?? 0);
                  setState(() {});
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Text('Category budgets', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                  TextButton.icon(
                    onPressed: () async {
                      final cats = await AppDb.instance.expenseCategories();
                      if (!context.mounted) return;
                      final c = await pickCategory(context, cats);
                      if (c != null && context.mounted) {
                        await budgetDialog(context, c, 0);
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              ...budgets.where((b) => b.category != '__overall__').map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BudgetCard(
                      title: b.category,
                      spent: spending[b.category] ?? 0,
                      budget: b.amount,
                      onTap: () async {
                        await budgetDialog(context, b.category, b.amount);
                        setState(() {});
                      },
                      onDelete: () async {
                        await AppDb.instance.deleteBudget(b.category);
                        setState(() {});
                      },
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const SettingsPage({super.key, required this.onChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool loading = true;
  bool smsEnabled = false;
  bool smsPermission = false;
  bool smsHistoryPermission = false;
  String smsPipelineStatus = 'Checking SMS receiver…';
  bool importingHistory = false;
  bool reclassifyingSms = false;
  String historyStatus = 'Optional: scan older bank/payment SMS already on this phone';
  String reclassifyStatus = 'Re-check imported SMS with the latest safety rules';
  bool phonePeEnabled = false;
  bool notificationAccess = false;
  List<UpiApp> financialApps = const [];
  Set<String> trackedNotificationPackages = <String>{};
  bool hybridClassifier = true;
  bool notifications = true;
  bool notificationPermission = false;
  bool summary = true;
  TimeOfDay summaryTime = const TimeOfDay(hour: 21, minute: 0);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      smsEnabled = await AppDb.instance.getBoolSetting('sms_tracking_enabled');
      smsPermission = await NativeBridge.hasSmsPermission();
      final pipeline = await NativeBridge.smsPipelineStatus();
      final lastReceived = int.tryParse(pipeline['lastReceivedAt'] ?? '');
      final status = pipeline['lastStatus'] ?? 'No status available';
      smsPipelineStatus = lastReceived == null ? status : '$status · last SMS ${dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(lastReceived))}';
      smsHistoryPermission = await NativeBridge.hasSmsHistoryPermission();
      phonePeEnabled = await AppDb.instance.getBoolSetting('phonepe_notification_enabled');
      notificationAccess = await NativeBridge.hasNotificationListenerPermission();
      final configuredPackages = await AppDb.instance.getSetting('notification_tracking_packages');
      trackedNotificationPackages = configuredPackages.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
      if (trackedNotificationPackages.isEmpty && phonePeEnabled) trackedNotificationPackages.add('com.phonepe.app');
      try {
        financialApps = await NativeBridge.getUpiApps(paymentUri: 'upi://pay?pa=expense.tracker%40upi&pn=Expense%20Tracker&am=1&cu=INR');
      } catch (_) {
        financialApps = const [];
      }
      hybridClassifier = await AppDb.instance.getBoolSetting('hybrid_classifier_enabled', fallback: true);
      notifications = await AppDb.instance.getBoolSetting('notifications_enabled', fallback: true);
      notificationPermission = await NativeBridge.hasNotificationPermission();
      summary = await AppDb.instance.getBoolSetting('daily_summary_enabled', fallback: true);
      summaryTime = TimeOfDay(
        hour: int.tryParse(await AppDb.instance.getSetting('daily_summary_hour', fallback: '21')) ?? 21,
        minute: int.tryParse(await AppDb.instance.getSetting('daily_summary_minute', fallback: '0')) ?? 0,
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _setFinancialAppTracking(UpiApp app, bool enabled) async {
    if (enabled && !notificationAccess) {
      await NativeBridge.openNotificationAccessSettings();
      notificationAccess = await NativeBridge.hasNotificationListenerPermission();
      if (!notificationAccess) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable Notification Access for Expense Tracker, then return and select apps.')));
        return;
      }
    }
    setState(() {
      if (enabled) {
        trackedNotificationPackages.add(app.packageName);
      } else {
        trackedNotificationPackages.remove(app.packageName);
      }
      phonePeEnabled = trackedNotificationPackages.isNotEmpty;
    });
    await AppDb.instance.setSetting('notification_tracking_packages', trackedNotificationPackages.join(','));
    await AppDb.instance.setSetting('phonepe_notification_enabled', phonePeEnabled ? '1' : '0');
  }

  Future<void> importPreviousSms() async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import previous SMS?'),
            content: const Text(
              'Expense Tracker will scan your existing SMS inbox locally, run the same hybrid classifier, '
              'and add only messages that look like completed financial transactions. OTPs, promotional '
              'messages and pending/autopay reminders are ignored. No SMS text is uploaded.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow & import')),
            ],
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;

    smsHistoryPermission = await NativeBridge.requestSmsHistoryPermission();
    if (!smsHistoryPermission) {
      if (mounted) {
        setState(() {
          historyStatus = 'READ_SMS permission was not granted';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        importingHistory = true;
        historyStatus = 'Scanning previous SMS on this device…';
      });
    }

    try {
      final result = await NativeBridge.importHistoricalSms();
      await AppDb.instance.setSetting(
        'last_sms_import_at',
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      if (!mounted) return;
      setState(() {
        historyStatus =
            'Scanned ${result.scanned} · imported ${result.imported} · duplicates ${result.duplicates} · ignored ${result.ignored}';
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${result.imported} previous transactions.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        historyStatus = 'Historical SMS import failed: $e';
      });
    } finally {
      if (mounted) setState(() => importingHistory = false);
    }
  }

  Future<void> reclassifyExistingSms() async {
    if (mounted) {
      setState(() {
        reclassifyingSms = true;
        reclassifyStatus = 'Re-checking stored SMS transactions…';
      });
    }
    try {
      final result = await NativeBridge.reclassifyStoredSms();
      if (!mounted) return;
      setState(() {
        reclassifyStatus =
            'Checked ${result.checked} · updated ${result.updated} · removed from reports ${result.ignored} · unchanged ${result.unchanged}';
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reclassified ${result.checked} stored SMS transactions.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => reclassifyStatus = 'Reclassification failed: $e');
    } finally {
      if (mounted) setState(() => reclassifyingSms = false);
    }
  }

  Future<void> saveSummary() async {
    await AppDb.instance.setSetting('daily_summary_enabled', summary ? '1' : '0');
    await AppDb.instance.setSetting('daily_summary_hour', '${summaryTime.hour}');
    await AppDb.instance.setSetting('daily_summary_minute', '${summaryTime.minute}');
    await NativeBridge.scheduleDailySummary(enabled: summary, hour: summaryTime.hour, minute: summaryTime.minute);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 104),
      children: [
        Row(
          children: [
            const Expanded(child: PageHeader(title: 'Settings', subtitle: 'Tracking, rules, permissions and privacy')),
            IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 16),
        SettingsBox(
          title: 'Automatic tracking',
          children: [
            SwitchListTile(
              value: smsEnabled,
              secondary: const Icon(Icons.sms_outlined),
              title: const Text('SMS Tracking'),
              subtitle: Text(smsPermission ? 'Detect incoming bank/payment SMS' : 'SMS permission required'),
              onChanged: (v) async {
                if (v) {
                  smsPermission = await NativeBridge.requestSmsPermission();
                  smsEnabled = smsPermission;
                } else {
                  smsEnabled = false;
                }
                await AppDb.instance.setSetting('sms_tracking_enabled', smsEnabled ? '1' : '0');
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: Icon(smsPipelineStatus.startsWith('Saved') || smsPipelineStatus.startsWith('Merged') ? Icons.check_circle_outline_rounded : Icons.sms_failed_outlined),
              title: const Text('SMS receiver status'),
              subtitle: Text(smsPipelineStatus),
              trailing: TextButton(onPressed: load, child: const Text('Check')),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Import previous SMS'),
              subtitle: Text(historyStatus),
              trailing: importingHistory
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : FilledButton.tonal(
                      onPressed: importPreviousSms,
                      child: Text(smsHistoryPermission ? 'Import again' : 'Allow'),
                    ),
              onTap: importingHistory ? null : importPreviousSms,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.rule_rounded),
              title: const Text('Reclassify existing SMS'),
              subtitle: Text(reclassifyStatus),
              trailing: reclassifyingSms
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: reclassifyingSms ? null : reclassifyExistingSms,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Financial app notification tracking'),
              subtitle: Text(notificationAccess
                  ? 'Choose the installed payment apps whose transaction notifications you want to track locally.'
                  : 'Android Notification Access is required before tracking any app.'),
              trailing: Text('${trackedNotificationPackages.length} selected'),
            ),
            if (financialApps.isEmpty)
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('No supported payment app detected'),
                subtitle: Text('Open or finish UPI setup in your payment app, then reopen Settings.'),
              )
            else
              ...financialApps.map((app) => SwitchListTile(
                    value: trackedNotificationPackages.contains(app.packageName),
                    secondary: Container(
                      width: 32,
                      height: 32,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: const Color(0xFFEAF5EF), borderRadius: BorderRadius.circular(9)),
                      child: app.iconBytes == null
                          ? const Icon(Icons.account_balance_wallet_rounded, size: 18)
                          : Image.memory(app.iconBytes!, fit: BoxFit.cover),
                    ),
                    title: Text(app.name),
                    subtitle: const Text('Read only its new transaction notifications on this device'),
                    onChanged: (value) => _setFinancialAppTracking(app, value),
                  )),
            if (!notificationAccess)
              ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Notification Access is off'),
                subtitle: const Text('Enable Expense Tracker, then return and tap refresh.'),
                trailing: TextButton(onPressed: NativeBridge.openNotificationAccessSettings, child: const Text('Open')),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SettingsBox(
          title: 'AI Advisor',
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('AI provider setup'),
              subtitle: const Text('Configure Gemini, OpenAI, Claude or DeepSeek'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAdvisorSettingsPage())),
            ),
            const ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('Chat history stays on this device'),
              subtitle: Text('Your API key uses secure storage. Finance summaries are sent only when you ask a question.'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SettingsBox(
          title: 'Smart classification',
          children: [
            SwitchListTile(
              value: hybridClassifier,
              secondary: const Icon(Icons.psychology_alt_outlined),
              title: const Text('Hybrid ML classifier'),
              subtitle: const Text('Safety rules + tiny on-device neural model + merchant rules'),
              onChanged: (v) async {
                hybridClassifier = v;
                await AppDb.instance.setSetting('hybrid_classifier_enabled', v ? '1' : '0');
                if (mounted) setState(() {});
              },
            ),
            const ListTile(
              leading: Icon(Icons.offline_bolt_outlined),
              title: Text('Model runs fully on device'),
              subtitle: Text('No SMS or notification text is sent to a server. Low-confidence financial messages go to Needs Review instead of being silently trusted.'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SettingsBox(
          title: 'Rules & data',
          children: [
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Merchant Rules'),
              subtitle: const Text('Keyword → merchant / category'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesPage()));
                widget.onChanged();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Categories'),
              subtitle: const Text('Add custom categories'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesPage()));
                widget.onChanged();
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Budgets'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsPage())),
            ),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('More tools'),
              subtitle: const Text('Search, cash flow, recurring, receipts, backup and privacy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnhancementHubPage())),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SettingsBox(
          title: 'Notifications',
          children: [
            SwitchListTile(
              value: notifications,
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Transaction alerts'),
              subtitle: Text(notificationPermission ? 'Alert after automatic detection' : 'Notification permission required on Android 13+'),
              onChanged: (v) async {
                if (v) {
                  notificationPermission = await NativeBridge.requestNotificationPermission();
                  notifications = notificationPermission;
                } else {
                  notifications = false;
                }
                await AppDb.instance.setSetting('notifications_enabled', notifications ? '1' : '0');
                if (mounted) setState(() {});
              },
            ),
            SwitchListTile(
              value: summary,
              secondary: const Icon(Icons.schedule),
              title: const Text('Daily summary'),
              subtitle: Text('Around ${summaryTime.format(context)}'),
              onChanged: (v) async {
                summary = v;
                await saveSummary();
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              enabled: summary,
              leading: const Icon(Icons.access_time),
              title: const Text('Summary time'),
              trailing: Text(summaryTime.format(context)),
              onTap: !summary
                  ? null
                  : () async {
                      final t = await showTimePicker(context: context, initialTime: summaryTime);
                      if (t != null) {
                        summaryTime = t;
                        await saveSummary();
                        if (mounted) setState(() {});
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 14),
        SettingsBox(
          title: 'Privacy & appearance',
          children: [
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Local-only by default'),
              subtitle: Text('SMS, PhonePe notification text, notes, receipts, transactions and ML decisions remain on this device unless you explicitly export them.'),
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Biometric lock & secure preview'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyAppearancePage())),
            ),
          ],
        ),
      ],
    );
  }
}

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Rules'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () async { await ruleEditor(context); setState(() {}); })],
      ),
      body: FutureBuilder<List<MerchantRule>>(
        future: AppDb.instance.rules(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                child: const Text('Matching is case-insensitive. Context such as refund/reversal overrides the rule default type.'),
              ),
              ...snap.data!.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(r.isUserRule ? Icons.person_outline : Icons.auto_awesome),
                      title: Text(r.merchant, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('"${r.keyword}" → ${titleCase(r.type)} / ${r.category}${r.isUserRule ? ' • My rule' : ''}'),
                      trailing: Switch(value: r.enabled, onChanged: (v) async { await AppDb.instance.toggleRule(r.id!, v); setState(() {}); }),
                      onTap: r.isUserRule ? () async { await ruleEditor(context, existing: r); setState(() {}); } : null,
                      onLongPress: r.isUserRule ? () async { await AppDb.instance.deleteRule(r.id!); setState(() {}); } : null,
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () async { await addCategoryDialog(context); setState(() {}); })],
      ),
      body: FutureBuilder<List<CategoryRecord>>(
        future: AppDb.instance.categories(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: snap.data!
                .map((c) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(iconFor(c.name)),
                        title: Text(c.name),
                        subtitle: Text(titleCase(c.kind)),
                        trailing: c.isSystem
                            ? const Text('Built-in')
                            : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await AppDb.instance.deleteCategory(c.name); setState(() {}); }),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const PageHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 25, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -.5)),
          const SizedBox(height: 5),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ],
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.subtitle, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w900)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      );
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeroStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: Colors.white70, size: 15), const SizedBox(width: 4), Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)))]),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
        ],
      );
}

class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  const QuickActionCard({super.key, required this.icon, required this.label, required this.caption, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FintechSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(FintechSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(15)),
          child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
        ),
        const SizedBox(height: FintechSpace.sm),
        Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onSurface)),
        const SizedBox(height: FintechSpace.xxs),
        Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  const MetricCard({super.key, required this.title, required this.value, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FintechSurface(
            onTap: onTap,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: scheme.onSecondaryContainer, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, maxLines: 1, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                  ),
                ])),
                if (onTap != null) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.chevron_right_rounded, size: 18)),
              ],
            ),
          );
  }
}

class TransactionTile extends StatelessWidget {
  final TxRecord tx;
  final VoidCallback? onTap;
  const TransactionTile({super.key, required this.tx, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positive = tx.type == 'income' || tx.type == 'refund';
    final amountColor = positive ? scheme.primary : scheme.onSurface;
    final typeColor = _transactionTypeColor(tx.type);
    final sign = positive ? '+' : '-';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: .48)))),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: typeColor.withValues(alpha: .10), shape: BoxShape.circle),
              child: Icon(iconFor(tx.category), color: typeColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.onSurface)),
              const SizedBox(height: 3),
              Text(dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$sign${money.format(tx.amount)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: amountColor)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: positive ? const Color(0xFFE7F6EB) : const Color(0xFFF2F4F1), borderRadius: BorderRadius.circular(8)),
                child: Text(positive ? 'Credited' : 'Completed', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: positive ? const Color(0xFF17704F) : scheme.onSurfaceVariant)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

Color _transactionTypeColor(String type) {
  switch (type) {
    case 'income':
      return const Color(0xFF0A8B56);
    case 'refund':
      return const Color(0xFF2879E0);
    case 'investment':
      return const Color(0xFF7257D8);
    case 'transfer':
      return const Color(0xFFCE7A18);
    default:
      return const Color(0xFFE05252);
  }
}

class EmptyCard extends StatelessWidget {
  final String text;
  const EmptyCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) => FintechSurface(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.receipt_long_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 26),
          ),
          const SizedBox(height: 13),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4, fontWeight: FontWeight.w600)),
        ]),
      );
}

class SettingsBox extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsBox({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => FintechSurface(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(17, 14, 17, 11),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: .8, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w900)),
            ),
            ...children,
          ],
        ),
      );
}

class BudgetCard extends StatelessWidget {
  final String title;
  final double spent;
  final double budget;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const BudgetCard({super.key, required this.title, required this.spent, required this.budget, required this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final progress = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0).toDouble();
    final remaining = (budget - spent).clamp(0, double.infinity).toDouble();
    final scheme = Theme.of(context).colorScheme;
    return FintechSurface(
          onTap: onTap,
          padding: const EdgeInsets.all(17),
          child: Column(
            children: [
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.account_balance_wallet_outlined, color: scheme.onPrimaryContainer, size: 21)),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onSurface)), const SizedBox(height: 2), Text('${money.format(remaining)} remaining', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant))])),
                if (onDelete != null) IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, size: 20)),
              ]),
              const SizedBox(height: 13),
              Row(children: [Text('${money.format(spent)} spent', style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text('${(progress * 100).round()}%', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: scheme.surfaceContainerHighest)),
            ],
          ),
        );
  }
}

class AppLoadingView extends StatelessWidget {
  final String label;
  const AppLoadingView({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 70, height: 70, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 20)]), child: Image.asset('assets/logo.png')),
          const SizedBox(height: 18),
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Color(0xFF718078), fontWeight: FontWeight.w700)),
        ]),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  const ErrorView({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE5EBE7))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFFFEDED), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.error_outline_rounded, color: Color(0xFFD94A4A), size: 28)),
              const SizedBox(height: 14),
              const Text('Something went wrong', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6E7972), height: 1.4)),
            ]),
          ),
        ),
      );
}

Future<bool> showAddTransaction(BuildContext context) async {
  final amount = TextEditingController();
  final merchant = TextEditingController();
  final note = TextEditingController();
  String type = 'expense';
  String category = 'Uncategorized';
  final cats = await AppDb.instance.categories();
  if (!context.mounted) return false;
  return (await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add transaction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
              controller: amount,
              readOnly: false,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                helperText: null,
              ),
            ),
                  const SizedBox(height: 10),
                  TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant / person')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(),
                    onChanged: (v) => setState(() {
                      type = v ?? type;
                      final matching = cats.where((c) => c.kind == type).toList();
                      if (matching.isNotEmpty) category = matching.first.name;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: cats.any((c) => c.name == category) ? category : cats.first.name,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: cats.where((c) => c.kind == type || type == 'transfer' || type == 'refund').map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                    onChanged: (v) => setState(() => category = v ?? category),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final v = double.tryParse(amount.text.replaceAll(',', ''));
                  if (v == null || v <= 0) return;
                  await AppDb.instance.addManualTransaction(amount: v, merchant: merchant.text, type: type, category: category, note: note.text);
                  if (context.mounted) Navigator.pop(context, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      )) ??
      false;
}

Future<void> editTransaction(BuildContext context, TxRecord tx) async {
  final merchant = TextEditingController(text: tx.merchant);
  final note = TextEditingController(text: tx.note);
  String type = tx.type;
  String category = tx.category;
  final cats = await AppDb.instance.categories();
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit transaction'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant / person')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(),
                onChanged: (v) => setState(() => type = v ?? type),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: cats.any((c) => c.name == category) ? category : cats.first.name,
                decoration: const InputDecoration(labelText: 'Category'),
                items: cats.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => category = v ?? category),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
              const SizedBox(height: 10),
              if (tx.upiReference.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text('UPI ref: ${tx.upiReference}', style: const TextStyle(color: Colors.black54))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (tx.id != null) await AppDb.instance.deleteTransaction(tx.id!);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
          FilledButton(
            onPressed: () async {
              if (tx.id == null) {
                if (context.mounted) Navigator.pop(context);
                return;
              }
              final merchantValue = merchant.text.trim().isEmpty ? tx.merchant : merchant.text.trim();
              final classificationChanged = type != tx.type || category != tx.category || merchantValue != tx.merchant;
              var applyAll = false;
              var similarCount = 0;
              if (classificationChanged) {
                similarCount = await AppDb.instance.countSimilarTransactions(tx);
                if (!context.mounted) return;
                final scope = await showDialog<String>(
                  context: context,
                  builder: (scopeContext) => AlertDialog(
                    title: const Text('Apply this correction?'),
                    content: Text(
                      similarCount > 0
                          ? 'There are $similarCount existing transaction${similarCount == 1 ? '' : 's'} with the same message pattern. You can update only this one, or apply the correction to that pattern and future matching messages.'
                          : 'Do you want this correction only for this transaction, or should the app remember the stable message pattern (payee/purpose + context) for future matching messages?',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(scopeContext, 'one'), child: const Text('Only this')),
                      FilledButton(
                        onPressed: () => Navigator.pop(scopeContext, 'all'),
                        child: Text(similarCount > 0 ? 'Same pattern + future' : 'Remember for future'),
                      ),
                    ],
                  ),
                );
                if (scope == null) return;
                applyAll = scope == 'all';
              }

              await AppDb.instance.updateTransaction(
                tx.id!,
                type: type,
                category: category,
                merchant: merchantValue,
                note: note.text,
                learnRule: false,
              );
              var updatedSimilar = 0;
              if (classificationChanged && applyAll) {
                updatedSimilar = await AppDb.instance.applyCorrectionToSimilar(
                  source: tx,
                  type: type,
                  category: category,
                  merchant: merchantValue,
                );
              }
              if (context.mounted) {
                Navigator.pop(context);
                if (classificationChanged) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        applyAll
                            ? 'Updated ${updatedSimilar + 1} transaction${updatedSimilar == 0 ? '' : 's'} and saved the message-pattern rule for future messages.'
                            : 'Updated this transaction only.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> ruleEditor(BuildContext context, {MerchantRule? existing}) async {
  final merchant = TextEditingController(text: existing?.merchant ?? '');
  final keyword = TextEditingController(text: existing?.keyword ?? '');
  String type = existing?.type ?? 'expense';
  String category = existing?.category ?? 'Uncategorized';
  final cats = await AppDb.instance.categories();
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Add rule' : 'Edit rule'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant name')),
              const SizedBox(height: 10),
              TextField(controller: keyword, decoration: const InputDecoration(labelText: 'SMS keyword', helperText: 'Example: zomato')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(value: type, items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) => setState(() => type = v ?? type), decoration: const InputDecoration(labelText: 'Default type')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(value: cats.any((c) => c.name == category) ? category : cats.first.name, items: cats.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(), onChanged: (v) => setState(() => category = v ?? category), decoration: const InputDecoration(labelText: 'Category')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (merchant.text.trim().isEmpty || keyword.text.trim().isEmpty) return;
              await AppDb.instance.saveRule(MerchantRule(id: existing?.id, merchant: merchant.text, keyword: keyword.text, type: type, category: category, isUserRule: true, enabled: existing?.enabled ?? true));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> addCategoryDialog(BuildContext context) async {
  final name = TextEditingController();
  String kind = 'expense';
  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Custom category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: kind, items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) => setState(() => kind = v ?? kind), decoration: const InputDecoration(labelText: 'Type')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await AppDb.instance.addCategory(name.text, kind);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

Future<void> budgetDialog(BuildContext context, String category, double existing) async {
  final c = TextEditingController(text: existing > 0 ? existing.toStringAsFixed(0) : '');
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(category == '__overall__' ? 'Overall monthly budget' : category),
      content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Monthly limit')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final v = double.tryParse(c.text.replaceAll(',', ''));
            if (v == null || v <= 0) return;
            await AppDb.instance.setBudget(category, v);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<String?> pickCategory(BuildContext context, List<CategoryRecord> categories) => showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        children: categories.map((c) => ListTile(leading: Icon(iconFor(c.name)), title: Text(c.name), onTap: () => Navigator.pop(context, c.name))).toList(),
      ),
    );

String titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String classifierLabel(String method) {
  switch (method) {
    case 'neural':
      return 'ML';
    case 'context_override':
      return 'Context';
    case 'hard_gate':
      return 'Safety rule';
    case 'merchant_rule':
      return 'Merchant rule';
    case 'user_corrected':
      return 'Learned';
    case 'low_confidence_review':
      return 'Needs review';
    case 'low_confidence':
      return 'Low confidence';
    default:
      return 'Hybrid';
  }
}

String classificationExplanation(TxRecord tx) {
  final merchant = tx.normalizedMerchant.isEmpty ? tx.merchant : tx.normalizedMerchant;
  final source = sourceLabel(tx.source);
  switch (tx.classificationMethod) {
    case 'hard_gate':
      return 'A high-confidence safety rule recognized explicit banking or spam/pending language in the $source message.';
    case 'context_override':
      return 'Strong transaction wording in the $source message matched ${titleCase(tx.type)} context, so context was trusted over a merchant default.';
    case 'merchant_rule':
      return 'The message matched the saved merchant rule for $merchant, which maps it to ${titleCase(tx.type)} / ${tx.category}.';
    case 'neural':
      return 'The on-device text classifier recognized this as ${titleCase(tx.type)} from the message wording. No message text was sent to a server.';
    case 'user_corrected':
      return 'This classification reflects a correction you previously made, so the local learned rule is being used.';
    case 'upi_intent':
      return 'This transaction was created from a UPI payment started inside the app.';
    default:
      return 'The local hybrid classifier combined transaction wording, merchant information and safety rules to choose ${titleCase(tx.type)} / ${tx.category}.';
  }
}

String sourceLabel(String source) {
  switch (source) {
    case 'sms':
      return 'SMS';
    case 'phonepe_notification':
      return 'PhonePe';
    case 'upi_intent':
      return 'UPI';
    default:
      return 'Manual';
  }
}

IconData iconFor(String category) {
  final c = category.toLowerCase();
  if (c.contains('food') || c.contains('grocer')) return Icons.restaurant;
  if (c.contains('transport')) return Icons.directions_car;
  if (c.contains('shop')) return Icons.shopping_bag;
  if (c.contains('entertain')) return Icons.play_circle;
  if (c.contains('bill')) return Icons.receipt;
  if (c.contains('health')) return Icons.favorite;
  if (c.contains('travel')) return Icons.flight;
  if (c.contains('stock') || c.contains('invest') || c.contains('fund')) return Icons.trending_up;
  if (c.contains('salary')) return Icons.account_balance_wallet;
  if (c.contains('transfer')) return Icons.swap_horiz;
  if (c.contains('refund')) return Icons.replay;
  return Icons.category;
}
