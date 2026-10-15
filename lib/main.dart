import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_db.dart';
import 'models.dart';
import 'native_bridge.dart';
import 'enhancements.dart';
import 'financial_ai.dart';

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
    await NativeBridge.scheduleDailySummary(enabled: enabled, hour: hour, minute: minute);
    await loadEnhancedPreferences();
    await AppDb.instance.normalizeExistingMerchants();
    await AppDb.instance.syncAccountsFromTransactions();
    await AppDb.instance.matchTransfers();
    final dedupResult = await AppDb.instance.smartDeduplicate();
    if ((dedupResult['ignored'] ?? 0) > 0) expenseDataRevision.value++;
    await runDailySmartAlerts();
    try { await NativeBridge.updateHomeWidget(); } catch (_) {}
  } catch (e, stack) {
    debugPrint('Startup initialization failed: $e');
    debugPrintStack(stackTrace: stack);
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  ThemeData _theme(Brightness brightness) {
    const seed = Color(0xFF0C9A62);
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final bg = dark ? const Color(0xFF101613) : const Color(0xFFF4F7F5);
    final surface = dark ? const Color(0xFF18211C) : Colors.white;
    final border = dark ? const Color(0xFF34423A) : const Color(0xFFE2E9E5);
    final muted = dark ? const Color(0xFFB3BEB7) : const Color(0xFF66736B);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(backgroundColor: bg, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false),
      cardTheme: CardThemeData(color: surface, surfaceTintColor: Colors.transparent, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        elevation: 4,
        indicatorColor: dark ? const Color(0xFF174A35) : const Color(0xFFE0F5E9),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: states.contains(WidgetState.selected) ? scheme.primary : muted)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(size: 23, color: states.contains(WidgetState.selected) ? scheme.primary : muted)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.7)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), side: BorderSide(color: border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800))),
      chipTheme: ChipThemeData(backgroundColor: surface, selectedColor: dark ? const Color(0xFF174A35) : const Color(0xFFE0F5E9), side: BorderSide(color: border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), labelStyle: const TextStyle(fontWeight: FontWeight.w700)),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: expenseThemeMode,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Expense Tracker',
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: const AppLockGate(child: HomeShell()),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    expenseDataRevision.addListener(refresh);
  }

  @override
  void dispose() {
    expenseDataRevision.removeListener(refresh);
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
      HomePage(key: ValueKey('home-$refreshToken'), onChanged: refresh, onNavigate: navigateTo),
      TransactionsPage(key: ValueKey('tx-$refreshToken'), onChanged: refresh),
      PayUpiPage(key: ValueKey('pay-$refreshToken'), onChanged: refresh),
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
            selectedIndex: index,
            onDestinationSelected: navigateTo,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'Activity'),
              NavigationDestination(icon: Icon(Icons.qr_code_2_rounded), label: 'Pay'),
              NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Reports'),
              NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onChanged;
  final ValueChanged<int> onNavigate;
  const HomePage({super.key, required this.onChanged, required this.onNavigate});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String period = 'month';
  DateTimeRange? customRange;

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
    if (picked != null && mounted) setState(() { customRange = picked; period = 'custom'; });
  }

  Future<List<dynamic>> load() async {
    final range = _range();
    return Future.wait<dynamic>([
      AppDb.instance.totalsByTypeForPeriod(range.$1, range.$2),
      AppDb.instance.overallBudget(),
      AppDb.instance.searchTransactions(startMs: range.$1, endMs: range.$2, limit: 6),
      AppDb.instance.reviewTransactions(),
      AppDb.instance.safeToSpendSnapshot(),
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
        final safe = snap.data![4] as Map<String, Object?>;
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
                  const Expanded(child: PageHeader(title: 'Expense Tracker', subtitle: 'Your money, automatically organised')),
                  IconButton.filledTonal(onPressed: widget.onChanged, icon: const Icon(Icons.sync_rounded)),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _periodChip('total', 'Total', Icons.all_inclusive_rounded),
                    _periodChip('month', 'Month', Icons.calendar_month_rounded),
                    _periodChip('week', 'Week', Icons.date_range_rounded),
                    _periodChip('day', 'Day', Icons.today_rounded),
                    _periodChip('custom', 'Custom', Icons.tune_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _heroCard(spent: spent, income: income, invested: invested, refunds: refunds, budget: budget, remaining: remaining, progress: progress),
              const SizedBox(height: 16),
              _SafeToSpendCard(snapshot: safe),
              const SizedBox(height: 22),
              SectionHeader(
                title: 'Money Map',
                subtitle: 'Where you are spending and investing for $_periodSubtitle',
                actionLabel: 'View report',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MoneyMapPage(
                      initialPeriod: ['month', 'week', 'custom'].contains(period) ? period : 'month',
                      initialCustomRange: period == 'custom' ? customRange : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MoneyMapAsyncPreview(
                startMs: selectedRange.$1,
                endMs: selectedRange.$2,
                periodLabel: _periodSubtitle,
              ),
              const SizedBox(height: 22),
              SectionHeader(
                title: 'AI Financial Coach',
                subtitle: 'Local pattern analysis, forecasts and saving opportunities',
                actionLabel: 'See analysis',
                onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialCoachPage())),
              ),
              const SizedBox(height: 12),
              const _FinancialCoachAsyncPreview(),
              const SizedBox(height: 22),
              SectionHeader(
                title: 'Financial inbox',
                subtitle: review.isEmpty ? 'Nothing needs your attention' : '${review.length} transaction${review.length == 1 ? '' : 's'} need a quick check',
                actionLabel: review.isEmpty ? null : 'Review',
                onAction: review.isEmpty ? null : () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewQueuePage()));
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 12),
              _FinancialInboxPreview(items: review.take(2).toList(), onChanged: widget.onChanged),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Quick actions', subtitle: 'Common things, one tap away'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: QuickActionCard(icon: Icons.qr_code_2_rounded, label: 'Pay UPI', caption: 'Scan or enter', onTap: () => widget.onNavigate(2))),
                  const SizedBox(width: 10),
                  Expanded(child: QuickActionCard(icon: Icons.add_rounded, label: 'Add', caption: 'Manual entry', onTap: () async { await showAddTransaction(context); widget.onChanged(); })),
                  const SizedBox(width: 10),
                  Expanded(child: QuickActionCard(icon: Icons.account_balance_wallet_rounded, label: 'Budget', caption: 'Set limits', onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsPage())); widget.onChanged(); })),
                ],
              ),
              const SizedBox(height: 22),
              SectionHeader(
                title: 'Recurring payments',
                subtitle: 'Only payments you choose are tracked here',
                actionLabel: 'Manage',
                onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringPaymentsPage())),
              ),
              const SizedBox(height: 12),
              const _HomeRecurringPreview(),
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

  Widget _periodChip(String value, String label, IconData icon) {
    final selected = period == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, size: 17, color: selected ? const Color(0xFF087849) : null),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => _selectPeriod(value),
        selectedColor: const Color(0xFFDDF5E9),
        backgroundColor: Theme.of(context).cardColor,
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF087849) : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(color: selected ? const Color(0xFFB7E5CD) : Theme.of(context).dividerColor),
      ),
    );
  }

  Widget _heroCard({
    required double spent,
    required double income,
    required double invested,
    required double refunds,
    required double budget,
    required double remaining,
    required double progress,
  }) {
    final monthlyBudgetMode = period == 'month';
    return Container(
      padding: const EdgeInsets.all(22),
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
          Row(
            children: [
              Expanded(child: Text(_periodTitle, style: const TextStyle(color: Colors.white70, letterSpacing: 1.1, fontSize: 12, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
                child: Text(monthlyBudgetMode && budget > 0 ? '${(progress * 100).round()}% budget' : _periodSubtitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money.format(spent), style: const TextStyle(color: Colors.white, fontSize: 38, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
          ),
          const SizedBox(height: 6),
          Text(
            monthlyBudgetMode
                ? (budget > 0 ? '${money.format(remaining)} left from ${money.format(budget)} monthly budget' : 'Set a monthly budget to track progress')
                : 'Expense for $_periodSubtitle',
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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _HeroStat(label: 'Income', value: money.format(income), icon: Icons.arrow_downward_rounded)),
              _heroDivider(),
              Expanded(child: _HeroStat(label: 'Invested', value: money.format(invested), icon: Icons.trending_up_rounded)),
              _heroDivider(),
              Expanded(child: _HeroStat(label: 'Refunds', value: money.format(refunds), icon: Icons.replay_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _heroDivider() => Container(width: 1, height: 36, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8));
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
              borderRadius: BorderRadius.circular(22),
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
              borderRadius: BorderRadius.circular(22),
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
              borderRadius: BorderRadius.circular(22),
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

class _FinancialCoachAsyncPreview extends StatelessWidget {
  const _FinancialCoachAsyncPreview();

  @override
  Widget build(BuildContext context) => FutureBuilder<FinancialCoachSnapshot>(
        future: FinancialAiEngine.instance.coachSnapshot(),
        builder: (context, snap) {
          if (snap.hasError) return const EmptyCard(text: 'Financial Coach is temporarily unavailable.');
          if (!snap.hasData) {
            return Container(
              height: 110,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return _FinancialCoachPreview(snapshot: snap.data!);
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

class _FinancialCoachPreview extends StatelessWidget {
  final FinancialCoachSnapshot snapshot;
  const _FinancialCoachPreview({required this.snapshot});

  IconData _icon(String kind) => switch (kind) {
        'forecast' => Icons.query_stats_rounded,
        'saving' => Icons.savings_outlined,
        'investment' => Icons.donut_large_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final items = snapshot.insights.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: items.isEmpty
          ? const Text('More transaction history is needed before useful behavior and forecast insights can be generated.')
          : Column(
              children: items.asMap().entries.map((entry) {
                final item = entry.value;
                return Padding(
                  padding: EdgeInsets.only(bottom: entry.key == items.length - 1 ? 0 : 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                        child: Icon(_icon(item.kind), size: 20),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text(item.body, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
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
    period = ['month', 'week', 'custom'].contains(widget.initialPeriod) ? widget.initialPeriod : 'month';
    customRange = widget.initialCustomRange;
  }

  (int, int) _range() {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    if (period == 'week') {
      final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      return (start.millisecondsSinceEpoch, todayEnd);
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
    if (period == 'week') return 'This week';
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
    if (picked != null && mounted) setState(() { customRange = picked; period = 'custom'; });
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
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('Month'), selected: period == 'month', onSelected: (_) => _select('month')),
                  ChoiceChip(label: const Text('Week'), selected: period == 'week', onSelected: (_) => _select('week')),
                  ChoiceChip(label: const Text('Custom'), selected: period == 'custom', onSelected: (_) => _select('custom')),
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

class FinancialCoachPage extends StatelessWidget {
  const FinancialCoachPage({super.key});

  IconData _icon(String kind) => switch (kind) {
        'forecast' => Icons.query_stats_rounded,
        'saving' => Icons.savings_outlined,
        'investment' => Icons.donut_large_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI Financial Coach')),
        body: FutureBuilder<FinancialCoachSnapshot>(
          future: FinancialAiEngine.instance.coachSnapshot(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final data = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('This month', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 14),
                      _CoachMetric(label: 'Spent so far', value: money.format(data.currentExpense)),
                      _CoachMetric(label: 'Projected month-end', value: data.projectedExpense > 0 ? money.format(data.projectedExpense) : 'Not enough data'),
                      _CoachMetric(label: 'Recent monthly average', value: data.normalMonthlyExpense > 0 ? money.format(data.normalMonthlyExpense) : 'Building history'),
                      _CoachMetric(label: 'Potential saving found', value: data.potentialSaving > 0 ? money.format(data.potentialSaving) : 'No clear excess yet'),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const SectionHeader(title: 'Coach insights', subtitle: 'Patterns calculated locally from your cleaned transaction history'),
                const SizedBox(height: 10),
                if (data.insights.isEmpty)
                  const EmptyCard(text: 'More history is needed before useful insights can be generated.')
                else
                  ...data.insights.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(13)),
                              child: Icon(_icon(item.kind), size: 21),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text(item.body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
                                  if (item.value != null) ...[
                                    const SizedBox(height: 8),
                                    Text(money.format(item.value), style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'The coach runs on-device using your structured transaction history. Forecasts and saving estimates are approximations, and investment concentration is descriptive rather than investment advice.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _CoachMetric extends StatelessWidget {
  final String label;
  final String value;
  const _CoachMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            const SizedBox(width: 12),
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
              const Expanded(child: PageHeader(title: 'Transactions', subtitle: 'SMS, PhonePe, UPI and manual entries')),
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
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: ['all', ...txTypes]
                .map((t) {
                  final selected = filter == t;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(titleCase(t)),
                      selected: selected,
                      onSelected: (_) => setState(() => filter = t),
                      showCheckmark: true,
                      checkmarkColor: const Color(0xFF087849),
                      selectedColor: const Color(0xFFDDF5E9),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected ? const Color(0xFF087849) : const Color(0xFF3F4A43),
                        fontWeight: FontWeight.w800,
                      ),
                      side: BorderSide(
                        color: selected ? const Color(0xFFB7E5CD) : const Color(0xFFD7DFDA),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  'If this is wrong, tap Edit transaction. You can apply the correction only here or to all similar transactions and future messages.',
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
      scannedQrHasFixedAmount = result.hasAmount;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('UPI QR scanned. Review the details before paying.')),
    );
  }

  String _buildUpiUri(double value) {
    final raw = scannedRawQr?.trim();
    if (raw != null && raw.isNotEmpty) {
      final original = Uri.tryParse(raw);
      if (original != null && original.scheme.toLowerCase() == 'upi' && original.host.toLowerCase() == 'pay') {
        final params = <String, String>{...original.queryParameters};
        // Preserve every QR-provided parameter. NPCI QR/intent interoperability
        // depends on passing merchant/reference parameters through unchanged.
        if (!params.containsKey('am') || params['am']!.trim().isEmpty) {
          params['am'] = value.toStringAsFixed(2);
        }
        if (!params.containsKey('tn') && note.text.trim().isNotEmpty) {
          params['tn'] = note.text.trim();
        }
        if (!params.containsKey('cu') || params['cu']!.trim().isEmpty) {
          params['cu'] = 'INR';
        }
        return original.replace(queryParameters: params).toString();
      }
    }

    final params = <String, String>{
      'pa': upi.text.trim(),
      'pn': payee.text.trim(),
      'am': value.toStringAsFixed(2),
      'cu': 'INR',
    };
    if (note.text.trim().isNotEmpty) params['tn'] = note.text.trim();
    return Uri(scheme: 'upi', host: 'pay', queryParameters: params).toString();
  }

  Future<void> pay() async {
    final value = double.tryParse(amount.text.replaceAll(',', '').trim());
    if (upi.text.trim().isEmpty || payee.text.trim().isEmpty || value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter UPI ID, payee and a valid amount.')));
      return;
    }
    setState(() => paying = true);
    try {
      final paymentUri = _buildUpiUri(value);
      final result = await NativeBridge.startUpiPayment(
        paymentUri: paymentUri,
      );
      if (!mounted) return;
      if (result.success) {
        final ref = result.txnId.isNotEmpty ? result.txnId : (result.txnRef.isNotEmpty ? result.txnRef : result.approvalRefNo);
        await AppDb.instance.addUpiTransaction(
          amount: value,
          merchant: payee.text.trim(),
          category: category,
          note: note.text.trim(),
          upiReference: ref,
          rawResponse: result.raw,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment saved with your note.')));
        amount.clear();
        note.clear();
        setState(() {
          scannedQr = false;
          scannedRawQr = null;
          scannedQrHasFixedAmount = false;
        });
        widget.onChanged();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment not confirmed (${result.status}). Nothing was saved.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open UPI payment: $e')));
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              scannedQr
                  ? 'The original QR payment parameters are preserved and passed to the UPI app. Some UPI apps can still block an externally initiated person-to-person payment for their own security checks.'
                  : 'Android will show compatible UPI apps installed on this phone. Some UPI apps can still block externally initiated person-to-person payments for their own security checks.',
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
            FilledButton.icon(
              onPressed: paying ? null : pay,
              icon: paying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_balance_wallet_outlined),
              label: Text(paying ? 'Opening UPI apps…' : 'Choose UPI app'),
            ),
          ],
        );
      },
    );
  }
}


class UpiQrData {
  final String upiId;
  final String payeeName;
  final double? amount;
  final String note;
  final String transactionRef;
  final String raw;
  final bool hasAmount;

  const UpiQrData({
    required this.upiId,
    required this.payeeName,
    required this.amount,
    required this.note,
    required this.transactionRef,
    required this.raw,
    required this.hasAmount,
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

    return UpiQrData(
      upiId: upiId,
      payeeName: (uri.queryParameters['pn'] ?? '').trim(),
      amount: parsedAmount,
      note: (uri.queryParameters['tn'] ?? '').trim(),
      transactionRef: (uri.queryParameters['tr'] ?? '').trim(),
      raw: value,
      hasAmount: amountText.isNotEmpty && parsedAmount != null && parsedAmount > 0,
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: MetricCard(title: 'Expense', value: money.format(totalExpense), icon: Icons.south_east_rounded, onTap: () => _openTransactions('Expenses • $periodLabel', type: 'expense'))),
                const SizedBox(width: 10),
                Expanded(child: MetricCard(title: 'Income', value: money.format(types['income'] ?? 0), icon: Icons.south_west_rounded, onTap: () => _openTransactions('Income • $periodLabel', type: 'income'))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: MetricCard(title: 'Investment', value: money.format(types['investment'] ?? 0), icon: Icons.show_chart_rounded, onTap: () => _openTransactions('Investments • $periodLabel', type: 'investment'))),
                const SizedBox(width: 10),
                Expanded(child: MetricCard(title: 'Refund', value: money.format(types['refund'] ?? 0), icon: Icons.replay_rounded, onTap: () => _openTransactions('Refunds • $periodLabel', type: 'refund'))),
              ],
            ),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Where your money went', subtitle: 'Largest spending signals for the selected period'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final categoryCard = _InsightCard(
                  title: 'Top category',
                  value: topCategory?.key ?? 'No data',
                  amount: topCategory == null ? '—' : money.format(topCategory.value),
                  icon: Icons.category_outlined,
                  onTap: topCategory == null ? null : () => _openTransactions('${topCategory!.key} • $periodLabel', type: 'expense', category: topCategory!.key),
                );
                final merchantCard = _InsightCard(
                  title: 'Top merchant',
                  value: topMerchant?.key ?? 'No data',
                  amount: topMerchant == null ? '—' : money.format(topMerchant.value),
                  icon: Icons.storefront_outlined,
                  onTap: topMerchant == null ? null : () => _openTransactions('${topMerchant!.key} • $periodLabel', type: 'expense', merchant: topMerchant!.key),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [
                      categoryCard,
                      const SizedBox(height: 10),
                      merchantCard,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: categoryCard),
                    const SizedBox(width: 10),
                    Expanded(child: merchantCard),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            _InsightCard(
              title: 'Largest single expense',
              value: largest?.merchant ?? 'No expense found',
              amount: largest == null ? '—' : money.format(largest.amount),
              icon: Icons.receipt_long_outlined,
              wide: true,
              onTap: largest == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailsPage(transaction: largest!))),
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: period == 'year' ? 'Monthly spending graph' : 'Expense by category',
              subtitle: period == 'year'
                  ? 'January to December $year'
                  : 'Category distribution for $periodLabel',
            ),
            const SizedBox(height: 12),
            if (period == 'year')
              MonthlySpendChart(
                values: monthly,
                onMonthTap: (selectedMonth) {
                  final start = DateTime(year, selectedMonth, 1).millisecondsSinceEpoch;
                  final end = DateTime(year, selectedMonth + 1, 1).millisecondsSinceEpoch;
                  _openTransactions('${DateFormat('MMMM yyyy').format(DateTime(year, selectedMonth))} expenses', type: 'expense', startMs: start, endMs: end);
                },
              )
            else if (categories.isEmpty)
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
  final ValueChanged<int>? onMonthTap;
  const MonthlySpendChart({super.key, required this.values, this.onMonthTap});

  @override
  Widget build(BuildContext context) {
    final normalized = List<double>.generate(12, (i) => i < values.length ? values[i] : 0);
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
              'Peak month: ${DateFormat.MMM().format(DateTime(2024, normalized.indexOf(maxValue) + 1))} · ${money.format(maxValue)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4F5D54)),
            )
          else
            const Text('No expense data for this year.', style: TextStyle(color: Color(0xFF738078))),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(12, (index) {
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
                        Text(
                          DateFormat.MMM().format(DateTime(2024, index + 1)).substring(0, 1),
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF7B8780), fontWeight: FontWeight.w700),
                        ),
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
  bool importingHistory = false;
  bool reclassifyingSms = false;
  String historyStatus = 'Optional: scan older bank/payment SMS already on this phone';
  String reclassifyStatus = 'Re-check imported SMS with the latest safety rules';
  bool phonePeEnabled = false;
  bool notificationAccess = false;
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
      smsHistoryPermission = await NativeBridge.hasSmsHistoryPermission();
      phonePeEnabled = await AppDb.instance.getBoolSetting('phonepe_notification_enabled');
      notificationAccess = await NativeBridge.hasNotificationListenerPermission();
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
            SwitchListTile(
              value: phonePeEnabled,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('PhonePe Notification Tracking'),
              subtitle: Text(notificationAccess ? 'Read new PhonePe transaction notifications locally' : 'Android Notification Access required'),
              onChanged: (v) async {
                if (v) {
                  notificationAccess = await NativeBridge.hasNotificationListenerPermission();
                  if (!notificationAccess) await NativeBridge.openNotificationAccessSettings();
                  phonePeEnabled = true;
                } else {
                  phonePeEnabled = false;
                }
                await AppDb.instance.setSetting('phonepe_notification_enabled', phonePeEnabled ? '1' : '0');
                if (mounted) setState(() {});
              },
            ),
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
              title: const Text('Biometric lock, secure preview & dark mode'),
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
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Theme.of(context).dividerColor)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: const Color(0xFFE7F6EE), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: const Color(0xFF0A8B56), size: 21),
              ),
              const SizedBox(height: 11),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A261F))),
              const SizedBox(height: 2),
              Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF7F8A83))),
            ]),
          ),
        ),
      );
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  const MetricCard({super.key, required this.title, required this.value, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: const [BoxShadow(color: Color(0x0B000000), blurRadius: 14, offset: Offset(0, 6))],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: const Color(0xFFE8F7EF), borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: const Color(0xFF0A8B56), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Color(0xFF7A877F), fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, maxLines: 1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF18241D))),
                  ),
                ])),
                if (onTap != null) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.chevron_right_rounded, size: 18)),
              ],
            ),
          ),
        ),
      );
}

class TransactionTile extends StatelessWidget {
  final TxRecord tx;
  final VoidCallback? onTap;
  const TransactionTile({super.key, required this.tx, this.onTap});

  @override
  Widget build(BuildContext context) {
    final positive = tx.type == 'income' || tx.type == 'refund';
    final amountColor = positive ? const Color(0xFF087D4A) : const Color(0xFF26312A);
    final typeColor = _transactionTypeColor(tx.type);
    final sign = positive ? '+' : '-';

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: typeColor.withValues(alpha: .11), borderRadius: BorderRadius.circular(16)),
                child: Icon(iconFor(tx.category), color: typeColor, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(tx.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900))),
                    const SizedBox(width: 8),
                    Text('$sign${money.format(tx.amount)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: amountColor)),
                  ]),
                  const SizedBox(height: 5),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: typeColor.withValues(alpha: .09), borderRadius: BorderRadius.circular(8)),
                      child: Text(tx.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: typeColor, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 7),
                    Expanded(child: Text(dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF879189)))),
                  ]),
                  if (tx.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(tx.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF657169), fontStyle: FontStyle.italic)),
                  ],
                  if (tx.source == 'sms' || tx.source == 'phonepe_notification') ...[
                    const SizedBox(height: 5),
                    Row(children: [
                      const Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFF0A8B56)),
                      const SizedBox(width: 4),
                      Text('${classifierLabel(tx.classificationMethod)} · ${(tx.classificationConfidence * 100).round()}%', style: const TextStyle(fontSize: 10.5, color: Color(0xFF0A8B56), fontWeight: FontWeight.w700)),
                    ]),
                  ],
                ]),
              ),
            ],
          ),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE5EBE7))),
        child: Column(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: const Color(0xFFEAF7F0), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF0A8B56), size: 26),
          ),
          const SizedBox(height: 13),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6F7B73), height: 1.4, fontWeight: FontWeight.w500)),
        ]),
      );
}

class SettingsBox extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsBox({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE4EBE7)),
          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 14, offset: Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(17, 14, 17, 11),
              color: const Color(0xFFF7FAF8),
              child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11.5, letterSpacing: .8, color: Color(0xFF6C7A71), fontWeight: FontWeight.w900)),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE4EBE7))),
          child: Column(
            children: [
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFE8F7EF), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF0A8B56), size: 21)),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B2720))), const SizedBox(height: 2), Text('${money.format(remaining)} remaining', style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C8880)))])),
                if (onDelete != null) IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, size: 20)),
              ]),
              const SizedBox(height: 13),
              Row(children: [Text('${money.format(spent)} spent', style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text('${(progress * 100).round()}%', style: const TextStyle(color: Color(0xFF0A8B56), fontWeight: FontWeight.w900))]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: const Color(0xFFE9EFEB))),
            ],
          ),
        ),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
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
                          ? 'There are $similarCount similar existing transaction${similarCount == 1 ? '' : 's'}. You can update only this one, or update similar transactions and teach the same rule for future messages.'
                          : 'Do you want this correction only for this transaction, or should the app also remember it for future similar messages?',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(scopeContext, 'one'), child: const Text('Only this')),
                      FilledButton(
                        onPressed: () => Navigator.pop(scopeContext, 'all'),
                        child: Text(similarCount > 0 ? 'All similar + future' : 'Remember for future'),
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
                            ? 'Updated ${updatedSimilar + 1} transaction${updatedSimilar == 0 ? '' : 's'} and saved the rule for future messages.'
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
