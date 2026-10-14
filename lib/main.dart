import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_db.dart';
import 'models.dart';
import 'native_bridge.dart';

const txTypes = ['expense', 'investment', 'income', 'transfer', 'refund'];
final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final dateTimeFmt = DateFormat('dd MMM, h:mm a');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
  WidgetsBinding.instance.addPostFrameCallback((_) => _initializeServices());
}

Future<void> _initializeServices() async {
  try {
    await AppDb.instance.initialize();
    final enabled = await AppDb.instance.getBoolSetting('daily_summary_enabled', fallback: true);
    final hour = int.tryParse(await AppDb.instance.getSetting('daily_summary_hour', fallback: '21')) ?? 21;
    final minute = int.tryParse(await AppDb.instance.getSetting('daily_summary_minute', fallback: '0')) ?? 0;
    await NativeBridge.scheduleDailySummary(enabled: enabled, hour: hour, minute: minute);
  } catch (e, stack) {
    debugPrint('Startup initialization failed: $e');
    debugPrintStack(stackTrace: stack);
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0C9A62);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFFBFCFB),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F7F5),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF15211A),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: .07),
          indicatorColor: const Color(0xFFE0F5E9),
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
                color: states.contains(WidgetState.selected) ? const Color(0xFF087849) : const Color(0xFF66736B),
              )),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                size: 23,
                color: states.contains(WidgetState.selected) ? const Color(0xFF087849) : const Color(0xFF768078),
              )),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelStyle: const TextStyle(color: Color(0xFF5D6A62)),
          hintStyle: const TextStyle(color: Color(0xFF98A29B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE3EAE6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: seed, width: 1.7)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            side: const BorderSide(color: Color(0xFFDDE5E0)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFE0F5E9),
          side: const BorderSide(color: Color(0xFFE2E9E5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFEDF1EF), thickness: 1, space: 1),
      ),
      home: const HomeShell(),
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

  void refresh() => setState(() => refreshToken++);
  void navigateTo(int value) => setState(() => index = value);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
      extendBody: true,
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

class HomePage extends StatelessWidget {
  final VoidCallback onChanged;
  final ValueChanged<int> onNavigate;
  const HomePage({super.key, required this.onChanged, required this.onNavigate});

  Future<List<dynamic>> load() async => [
        await AppDb.instance.monthTotalsByType(),
        await AppDb.instance.overallBudget(),
        await AppDb.instance.recentTransactions(),
      ];

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
        final spent = totals['expense'] ?? 0;
        final invested = totals['investment'] ?? 0;
        final income = totals['income'] ?? 0;
        final refunds = totals['refund'] ?? 0;
        final remaining = budget <= 0 ? 0.0 : (budget - spent).clamp(0, double.infinity).toDouble();
        final progress = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0).toDouble();

        return RefreshIndicator(
          onRefresh: () async => onChanged(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 104),
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 6))],
                    ),
                    child: ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.asset('assets/logo.png')),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: PageHeader(title: 'Expense Tracker', subtitle: 'Your money, automatically organised')),
                  IconButton.filledTonal(onPressed: onChanged, icon: const Icon(Icons.sync_rounded)),
                ],
              ),
              const SizedBox(height: 22),
              Container(
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
                        const Expanded(child: Text('MONTHLY SPENDING', style: TextStyle(color: Colors.white70, letterSpacing: 1.1, fontSize: 12, fontWeight: FontWeight.w800))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
                          child: Text('${(progress * 100).round()}% used', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(money.format(spent), style: const TextStyle(color: Colors.white, fontSize: 38, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
                    const SizedBox(height: 6),
                    Text(
                      budget > 0 ? '${money.format(remaining)} left from ${money.format(budget)}' : 'Set a monthly budget to track progress',
                      style: const TextStyle(color: Color(0xFFE7FFF1), fontWeight: FontWeight.w600),
                    ),
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
              ),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Quick actions', subtitle: 'Common things, one tap away'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: QuickActionCard(icon: Icons.qr_code_2_rounded, label: 'Pay UPI', caption: 'Save note', onTap: () => onNavigate(2))),
                  const SizedBox(width: 10),
                  Expanded(child: QuickActionCard(icon: Icons.add_rounded, label: 'Add', caption: 'Manual entry', onTap: () async { await showAddTransaction(context); onChanged(); })),
                  const SizedBox(width: 10),
                  Expanded(child: QuickActionCard(icon: Icons.account_balance_wallet_rounded, label: 'Budget', caption: 'Set limits', onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsPage())); onChanged(); })),
                ],
              ),
              const SizedBox(height: 24),
              SectionHeader(title: 'Recent activity', subtitle: recent.isEmpty ? 'Your latest transactions will appear here' : '${recent.length} most recent', actionLabel: 'View all', onAction: () => onNavigate(1)),
              const SizedBox(height: 12),
              if (recent.isEmpty)
                const EmptyCard(text: 'No transactions yet. Turn on SMS or PhonePe tracking in Settings, or add one manually.')
              else
                ...recent.map((t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TransactionTile(tx: t))),
            ],
          ),
        );
      },
    );
  }

  static Widget _heroDivider() => Container(width: 1, height: 36, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8));
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
                .map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(titleCase(t)), selected: filter == t, onSelected: (_) => setState(() => filter = t)),
                    ))
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
                        await editTransaction(context, tx);
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

  @override
  void dispose() {
    upi.dispose();
    payee.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> pay() async {
    final value = double.tryParse(amount.text.replaceAll(',', '').trim());
    if (upi.text.trim().isEmpty || payee.text.trim().isEmpty || value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter UPI ID, payee and a valid amount.')));
      return;
    }
    setState(() => paying = true);
    try {
      final result = await NativeBridge.startUpiPayment(
        upiId: upi.text.trim(),
        payeeName: payee.text.trim(),
        amount: value,
        note: note.text.trim(),
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
            const PageHeader(title: 'Pay with UPI', subtitle: 'Your note is saved locally before PhonePe opens'),
            const SizedBox(height: 16),
            Center(child: Image.asset('assets/logo.png', width: 96, height: 96)),
            const SizedBox(height: 18),
            TextField(controller: upi, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Recipient UPI ID', hintText: 'name@bank')),
            const SizedBox(height: 12),
            TextField(controller: payee, decoration: const InputDecoration(labelText: 'Payee name', hintText: 'Person or merchant')),
            const SizedBox(height: 12),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ')),
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
            const Text(
              'The note is stored in this app first and is also sent to the UPI app as the transaction note. This is how we preserve notes without reading PhonePe private history.',
              style: TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: paying ? null : pay,
              icon: paying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_balance_wallet_outlined),
              label: Text(paying ? 'Opening UPI…' : 'Open PhonePe / UPI'),
            ),
          ],
        );
      },
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  Future<List<dynamic>> load() async => [
        await AppDb.instance.monthTotalsByType(),
        await AppDb.instance.monthExpenseByCategory(),
      ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: load(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(message: '${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final types = snap.data![0] as Map<String, double>;
        final categories = snap.data![1] as Map<String, double>;
        double max = 1;
        for (final v in categories.values) {
          if (v > max) max = v;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 104),
          children: [
            const PageHeader(title: 'Reports', subtitle: 'Current month'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: MetricCard(title: 'Expense', value: money.format(types['expense'] ?? 0), icon: Icons.south_east)),
                const SizedBox(width: 10),
                Expanded(child: MetricCard(title: 'Investment', value: money.format(types['investment'] ?? 0), icon: Icons.show_chart)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: MetricCard(title: 'Income', value: money.format(types['income'] ?? 0), icon: Icons.south_west)),
                const SizedBox(width: 10),
                Expanded(child: MetricCard(title: 'Refund', value: money.format(types['refund'] ?? 0), icon: Icons.replay)),
              ],
            ),
            const SizedBox(height: 22),
            const Text('Expense by category', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              const EmptyCard(text: 'No expense data this month.')
            else
              ...categories.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      children: [
                        Row(children: [Expanded(child: Text(e.key)), Text(money.format(e.value), style: const TextStyle(fontWeight: FontWeight.w700))]),
                        const SizedBox(height: 7),
                        ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: e.value / max, minHeight: 8)),
                      ],
                    ),
                  )),
          ],
        );
      },
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
  bool phonePeEnabled = false;
  bool notificationAccess = false;
  bool hybridClassifier = true;
  bool learnCorrections = true;
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
      phonePeEnabled = await AppDb.instance.getBoolSetting('phonepe_notification_enabled');
      notificationAccess = await NativeBridge.hasNotificationListenerPermission();
      hybridClassifier = await AppDb.instance.getBoolSetting('hybrid_classifier_enabled', fallback: true);
      learnCorrections = await AppDb.instance.getBoolSetting('learn_from_corrections', fallback: true);
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
            SwitchListTile(
              value: learnCorrections,
              secondary: const Icon(Icons.school_outlined),
              title: const Text('Learn from corrections'),
              subtitle: const Text('Editing a transaction creates a local merchant override for future messages'),
              onChanged: (v) async {
                learnCorrections = v;
                await AppDb.instance.setSetting('learn_from_corrections', v ? '1' : '0');
                if (mounted) setState(() {});
              },
            ),
            const ListTile(
              leading: Icon(Icons.offline_bolt_outlined),
              title: Text('Model runs fully on device'),
              subtitle: Text('No SMS or notification text is sent to a server. Low-confidence messages are ignored instead of auto-saved.'),
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
        const SettingsBox(
          title: 'Privacy',
          children: [
            ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Local-only by default'),
              subtitle: Text('SMS, PhonePe notification text, notes, transactions and budgets remain on this device. No backend is used.'),
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
          Text(title, style: const TextStyle(fontSize: 25, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -.5, color: Color(0xFF17231C))),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: Color(0xFF718078), fontSize: 13.5, fontWeight: FontWeight.w500)),
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
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF17231C))),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: Color(0xFF7B877F))),
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
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE4EBE7))),
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
  const MetricCard({super.key, required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4EBE7)),
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
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF18241D))),
            ])),
          ],
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: const Color(0xFFE6ECE8)),
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
                    Expanded(child: Text(tx.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF1C2821)))),
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
                  TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ')),
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
              if (tx.id != null) await AppDb.instance.updateTransaction(tx.id!, type: type, category: category, merchant: merchant.text, note: note.text);
              if (context.mounted) Navigator.pop(context);
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
    default:
      return 'Hybrid';
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
