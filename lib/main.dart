import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_db.dart';
import 'models.dart';
import 'native_bridge.dart';

const txTypes = ['expense', 'investment', 'income', 'transfer', 'refund'];
final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeServices();
  });
}

Future<void> _initializeServices() async {
  try {
    await AppDb.instance.initialize();

    final enabled = await AppDb.instance.getBoolSetting(
      'daily_summary_enabled',
      fallback: true,
    );
    final hour = int.tryParse(
      await AppDb.instance.getSetting(
        'daily_summary_hour',
        fallback: '21',
      ),
    ) ?? 21;
    final minute = int.tryParse(
      await AppDb.instance.getSetting(
        'daily_summary_minute',
        fallback: '0',
      ),
    ) ?? 0;

    await NativeBridge.scheduleDailySummary(
      enabled: enabled,
      hour: hour,
      minute: minute,
    );
  } catch (error, stackTrace) {
    debugPrint('Service initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF079C5A)),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
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
      HomePage(key: ValueKey('home-$refreshToken')),
      TransactionsPage(key: ValueKey('tx-$refreshToken'), onChanged: refresh),
      BudgetsPage(key: ValueKey('budget-$refreshToken'), onChanged: refresh),
      ReportsPage(key: ValueKey('report-$refreshToken')),
      SettingsPage(key: ValueKey('settings-$refreshToken'), onChanged: refresh),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      floatingActionButton: index == 1
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (await showAddTransaction(context)) refresh();
              },
              icon: const Icon(Icons.add), label: const Text('Add'))
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() { index = v; refreshToken++; }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
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
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final totals = snap.data![0] as Map<String, double>;
        final budget = snap.data![1] as double;
        final recent = snap.data![2] as List<TxRecord>;
        final spent = totals['expense'] ?? 0;
        final invested = totals['investment'] ?? 0;
        final income = totals['income'] ?? 0;
        final progress = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0).toDouble();
        return ListView(padding: const EdgeInsets.all(18), children: [
          const PageHeader(title: 'Overview', subtitle: 'Automatic local SMS tracking'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF079C5A), Color(0xFF05B66A)]), borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Spent this month', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(money.format(spent), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
              Text('of ${money.format(budget)} budget', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(20), backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: MetricCard(title: 'Invested', value: money.format(invested), icon: Icons.trending_up)),
            const SizedBox(width: 10),
            Expanded(child: MetricCard(title: 'Income', value: money.format(income), icon: Icons.south_west)),
          ]),
          const SizedBox(height: 22),
          const Text('Recent transactions', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (recent.isEmpty) const EmptyCard(text: 'No transactions yet. Enable SMS tracking in Settings.') else ...recent.map((t) => TransactionTile(tx: t)),
        ]);
      },
    );
  }
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
    return Column(children: [
      const Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, 8), child: PageHeader(title: 'Transactions', subtitle: 'SMS and manual entries')),
      SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: ['all', ...txTypes].map((t) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(titleCase(t)), selected: filter == t, onSelected: (_) => setState(() => filter = t)))).toList())),
      const SizedBox(height: 8),
      Expanded(child: FutureBuilder<List<TxRecord>>(
        future: AppDb.instance.transactions(type: filter),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) return const Center(child: Text('No transactions'));
          return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), itemCount: snap.data!.length, itemBuilder: (context, i) {
            final tx = snap.data![i];
            return TransactionTile(tx: tx, onTap: () async {
              if (await editTransaction(context, tx) && mounted) { setState(() {}); widget.onChanged(); }
            });
          });
        },
      )),
    ]);
  }
}

class BudgetsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const BudgetsPage({super.key, required this.onChanged});
  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}
class _BudgetsPageState extends State<BudgetsPage> {
  Future<List<dynamic>> load() async => [await AppDb.instance.budgets(), await AppDb.instance.monthExpenseByCategory()];
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(future: load(), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final budgets = snap.data![0] as List<BudgetRecord>;
      final spending = snap.data![1] as Map<String, double>;
      BudgetRecord? overall;
      for (final b in budgets) { if (b.category == '__overall__') overall = b; }
      final total = spending.values.fold<double>(0, (a, b) => a + b);
      return ListView(padding: const EdgeInsets.all(18), children: [
        const PageHeader(title: 'Budgets', subtitle: 'Monthly limits'),
        const SizedBox(height: 16),
        BudgetCard(title: 'Overall budget', spent: total, budget: overall?.amount ?? 0, onTap: () async { await budgetDialog(context, '__overall__', overall?.amount ?? 0); setState(() {}); widget.onChanged(); }),
        const SizedBox(height: 18),
        Row(children: [const Expanded(child: Text('Category budgets', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), TextButton.icon(onPressed: () async {
          final cats = await AppDb.instance.categories(); if (!context.mounted) return; final c = await pickCategory(context, cats); if (c != null && context.mounted) { await budgetDialog(context, c, 0); setState(() {}); }
        }, icon: const Icon(Icons.add), label: const Text('Add'))]),
        ...budgets.where((b) => b.category != '__overall__').map((b) => Padding(padding: const EdgeInsets.only(bottom: 10), child: BudgetCard(title: b.category, spent: spending[b.category] ?? 0, budget: b.amount, onTap: () async { await budgetDialog(context, b.category, b.amount); setState(() {}); }, onDelete: () async { await AppDb.instance.deleteBudget(b.category); setState(() {}); }))),
      ]);
    });
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  Future<List<dynamic>> load() async => [await AppDb.instance.monthTotalsByType(), await AppDb.instance.monthExpenseByCategory()];
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(future: load(), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final types = snap.data![0] as Map<String, double>;
      final categories = snap.data![1] as Map<String, double>;
      double max = 1; for (final v in categories.values) { if (v > max) max = v; }
      return ListView(padding: const EdgeInsets.all(18), children: [
        const PageHeader(title: 'Reports', subtitle: 'This month'), const SizedBox(height: 16),
        Row(children: [Expanded(child: MetricCard(title: 'Expense', value: money.format(types['expense'] ?? 0), icon: Icons.south_east)), const SizedBox(width: 10), Expanded(child: MetricCard(title: 'Investment', value: money.format(types['investment'] ?? 0), icon: Icons.show_chart))]),
        const SizedBox(height: 22), const Text('Expense by category', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 12),
        if (categories.isEmpty) const EmptyCard(text: 'No expense data this month.') else ...categories.entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(children: [Row(children: [Expanded(child: Text(e.key)), Text(money.format(e.value), style: const TextStyle(fontWeight: FontWeight.w700))]), const SizedBox(height: 7), LinearProgressIndicator(value: e.value / max, minHeight: 8, borderRadius: BorderRadius.circular(20))]))),
      ]);
    });
  }
}

class SettingsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const SettingsPage({super.key, required this.onChanged});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  bool loading = true, smsEnabled = false, smsPermission = false, notifications = true, notificationPermission = false, summary = true;
  TimeOfDay summaryTime = const TimeOfDay(hour: 21, minute: 0);
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    smsEnabled = await AppDb.instance.getBoolSetting('sms_tracking_enabled');
    smsPermission = await NativeBridge.hasSmsPermission();
    notifications = await AppDb.instance.getBoolSetting('notifications_enabled', fallback: true);
    notificationPermission = await NativeBridge.hasNotificationPermission();
    summary = await AppDb.instance.getBoolSetting('daily_summary_enabled', fallback: true);
    summaryTime = TimeOfDay(hour: int.tryParse(await AppDb.instance.getSetting('daily_summary_hour', fallback: '21')) ?? 21, minute: int.tryParse(await AppDb.instance.getSetting('daily_summary_minute', fallback: '0')) ?? 0);
    if (mounted) setState(() => loading = false);
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
    return ListView(padding: const EdgeInsets.all(18), children: [
      const PageHeader(title: 'Settings', subtitle: 'Tracking, rules and privacy'), const SizedBox(height: 16),
      SettingsBox(title: 'Automatic tracking', children: [
        SwitchListTile(value: smsEnabled, secondary: const Icon(Icons.sms_outlined), title: const Text('SMS Tracking'), subtitle: Text(smsPermission ? 'Detect financial SMS automatically' : 'SMS permission required'), onChanged: (v) async {
          if (v) { smsPermission = await NativeBridge.requestSmsPermission(); smsEnabled = smsPermission; } else { smsEnabled = false; }
          await AppDb.instance.setSetting('sms_tracking_enabled', smsEnabled ? '1' : '0'); if (mounted) setState(() {});
        }),
        if (!smsPermission) ListTile(title: const Text('Android permission is off'), trailing: TextButton(onPressed: NativeBridge.openAppSettings, child: const Text('App settings'))),
      ]), const SizedBox(height: 14),
      SettingsBox(title: 'Rules & categories', children: [
        ListTile(leading: const Icon(Icons.tune), title: const Text('Merchant Rules'), subtitle: const Text('SMS contains(keyword) → category'), trailing: const Icon(Icons.chevron_right), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesPage())); widget.onChanged(); }),
        ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Categories'), subtitle: const Text('Add custom categories'), trailing: const Icon(Icons.chevron_right), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesPage())); widget.onChanged(); }),
      ]), const SizedBox(height: 14),
      SettingsBox(title: 'Notifications', children: [
        SwitchListTile(value: notifications, secondary: const Icon(Icons.notifications_outlined), title: const Text('Transaction alerts'), subtitle: Text(notificationPermission ? 'Alert after automatic detection' : 'Notification permission required on Android 13+'), onChanged: (v) async {
          if (v) { notificationPermission = await NativeBridge.requestNotificationPermission(); notifications = notificationPermission; } else { notifications = false; }
          await AppDb.instance.setSetting('notifications_enabled', notifications ? '1' : '0'); if (mounted) setState(() {});
        }),
        SwitchListTile(value: summary, secondary: const Icon(Icons.schedule), title: const Text('Daily summary'), subtitle: Text('Around ${summaryTime.format(context)}'), onChanged: (v) async { summary = v; await saveSummary(); setState(() {}); }),
        ListTile(enabled: summary, leading: const Icon(Icons.access_time), title: const Text('Summary time'), trailing: Text(summaryTime.format(context)), onTap: !summary ? null : () async { final t = await showTimePicker(context: context, initialTime: summaryTime); if (t != null) { summaryTime = t; await saveSummary(); setState(() {}); } }),
      ]), const SizedBox(height: 14),
      const SettingsBox(title: 'Privacy', children: [ListTile(leading: Icon(Icons.lock_outline), title: Text('No backend'), subtitle: Text('SMS, transactions, budgets and rules stay on this device.'))]),
    ]);
  }
}

class RulesPage extends StatefulWidget { const RulesPage({super.key}); @override State<RulesPage> createState() => _RulesPageState(); }
class _RulesPageState extends State<RulesPage> {
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Merchant Rules'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () async { await ruleEditor(context); setState(() {}); })]), body: FutureBuilder<List<MerchantRule>>(future: AppDb.instance.rules(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)), child: const Text('Matching is case-insensitive. If the SMS contains the keyword, the rule applies. User rules are checked before defaults.')), ...snap.data!.map((r) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: Icon(r.isUserRule ? Icons.person_outline : Icons.auto_awesome), title: Text(r.merchant, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('"${r.keyword}" → ${titleCase(r.type)} / ${r.category}${r.isUserRule ? ' • My rule' : ''}'), trailing: Switch(value: r.enabled, onChanged: (v) async { await AppDb.instance.toggleRule(r.id!, v); setState(() {}); }), onTap: r.isUserRule ? () async { await ruleEditor(context, existing: r); setState(() {}); } : null, onLongPress: r.isUserRule ? () async { await AppDb.instance.deleteRule(r.id!); setState(() {}); } : null))) ]);
  }));
}

class CategoriesPage extends StatefulWidget { const CategoriesPage({super.key}); @override State<CategoriesPage> createState() => _CategoriesPageState(); }
class _CategoriesPageState extends State<CategoriesPage> {
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Categories'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () async { await addCategoryDialog(context); setState(() {}); })]), body: FutureBuilder<List<CategoryRecord>>(future: AppDb.instance.categories(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: snap.data!.map((c) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: Icon(iconFor(c.name)), title: Text(c.name), subtitle: Text(titleCase(c.kind)), trailing: c.isSystem ? const Text('Built-in') : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await AppDb.instance.deleteCategory(c.name); setState(() {}); })))) .toList());
  }));
}

class TransactionTile extends StatelessWidget {
  final TxRecord tx; final VoidCallback? onTap; const TransactionTile({super.key, required this.tx, this.onTap});
  @override Widget build(BuildContext context) {
    final out = tx.type == 'expense' || tx.type == 'investment';
    return Container(margin: const EdgeInsets.only(bottom: 9), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: ListTile(onTap: onTap, leading: CircleAvatar(child: Icon(iconFor(tx.category))), title: Text(tx.merchant, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${tx.category} • ${tx.paymentMethod.isEmpty ? tx.source.toUpperCase() : tx.paymentMethod}'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${out ? '-' : '+'}${money.format(tx.amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: tx.type == 'income' || tx.type == 'refund' ? Colors.green.shade700 : Colors.black87)), const SizedBox(height: 3), Text(DateFormat('d MMM, h:mm a').format(tx.occurredAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade600))])));
  }
}

class MetricCard extends StatelessWidget {
  final String title, value; final IconData icon; const MetricCard({super.key, required this.title, required this.value, required this.icon});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 10), Text(title, style: TextStyle(color: Colors.grey.shade600)), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))]));
}
class BudgetCard extends StatelessWidget {
  final String title; final double spent, budget; final VoidCallback onTap; final VoidCallback? onDelete; const BudgetCard({super.key, required this.title, required this.spent, required this.budget, required this.onTap, this.onDelete});
  @override Widget build(BuildContext context) { final ratio = budget <= 0 ? 0.0 : spent / budget; return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)), child: Column(children: [Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text('${money.format(spent)} / ${money.format(budget)}'), if (onDelete != null) IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 19))]), const SizedBox(height: 10), LinearProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(20)), if (ratio > 1) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 7), child: Text('Over by ${money.format(spent - budget)}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))))]))); }
}
class SettingsBox extends StatelessWidget { final String title; final List<Widget> children; const SettingsBox({super.key, required this.title, required this.children}); @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)), child: Column(children: children))]); }
class PageHeader extends StatelessWidget { final String title, subtitle; const PageHeader({super.key, required this.title, required this.subtitle}); @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), Text(subtitle, style: TextStyle(color: Colors.grey.shade600))]); }
class EmptyCard extends StatelessWidget { final String text; const EmptyCard({super.key, required this.text}); @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)), child: Text(text)); }

Future<bool> showAddTransaction(BuildContext context) async {
  final amount = TextEditingController(), merchant = TextEditingController(); String type = 'expense', category = 'Uncategorized'; final cats = await AppDb.instance.categories(); if (!context.mounted) return false;
  return (await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (context) => StatefulBuilder(builder: (context, setState) => Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 22), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Add transaction', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)), const SizedBox(height: 14), TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')), const SizedBox(height: 10), TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant / note')), const SizedBox(height: 10), DropdownButtonFormField(value: type, items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { if (v != null) setState(() => type = v); }, decoration: const InputDecoration(labelText: 'Type')), const SizedBox(height: 10), DropdownButtonFormField(value: category, items: cats.map((e) => DropdownMenuItem(value: e.name, child: Text(e.name))).toList(), onChanged: (v) { if (v != null) setState(() => category = v); }, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 14), SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { final v = double.tryParse(amount.text.replaceAll(',', '')); if (v == null || v <= 0) return; await AppDb.instance.addManualTransaction(amount: v, merchant: merchant.text, type: type, category: category); if (context.mounted) Navigator.pop(context, true); }, child: const Text('Add transaction')))])))) ?? false);
}

Future<bool> editTransaction(BuildContext context, TxRecord tx) async {
  final merchant = TextEditingController(text: tx.merchant); String type = tx.type, category = tx.category; final cats = await AppDb.instance.categories(); if (!context.mounted) return false;
  return (await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(title: const Text('Edit transaction'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(money.format(tx.amount), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), const SizedBox(height: 12), TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant')), const SizedBox(height: 10), DropdownButtonFormField(value: txTypes.contains(type) ? type : 'expense', items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { if (v != null) setState(() => type = v); }, decoration: const InputDecoration(labelText: 'Type')), const SizedBox(height: 10), DropdownButtonFormField(value: cats.any((e) => e.name == category) ? category : cats.first.name, items: cats.map((e) => DropdownMenuItem(value: e.name, child: Text(e.name))).toList(), onChanged: (v) { if (v != null) setState(() => category = v); }, decoration: const InputDecoration(labelText: 'Category')), if (tx.rawMessage.isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Original SMS'), children: [SelectableText(tx.rawMessage)])])), actions: [TextButton(onPressed: () async { await AppDb.instance.deleteTransaction(tx.id); if (context.mounted) Navigator.pop(context, true); }, child: const Text('Delete')), FilledButton(onPressed: () async { await AppDb.instance.updateTransaction(tx.id, type: type, category: category, merchant: merchant.text.trim().isEmpty ? tx.merchant : merchant.text.trim()); if (context.mounted) Navigator.pop(context, true); }, child: const Text('Save'))]))) ?? false);
}

Future<void> ruleEditor(BuildContext context, {MerchantRule? existing}) async {
  final merchant = TextEditingController(text: existing?.merchant ?? ''), keyword = TextEditingController(text: existing?.keyword ?? ''); String type = existing?.type ?? 'expense', category = existing?.category ?? 'Uncategorized'; final cats = await AppDb.instance.categories(); if (!context.mounted) return;
  await showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(title: Text(existing == null ? 'Add rule' : 'Edit rule'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant name')), const SizedBox(height: 10), TextField(controller: keyword, decoration: const InputDecoration(labelText: 'SMS keyword', helperText: 'Example: zomato')), const SizedBox(height: 10), DropdownButtonFormField(value: type, items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { if (v != null) setState(() => type = v); }, decoration: const InputDecoration(labelText: 'Type')), const SizedBox(height: 10), DropdownButtonFormField(value: cats.any((c) => c.name == category) ? category : cats.first.name, items: cats.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(), onChanged: (v) { if (v != null) setState(() => category = v); }, decoration: const InputDecoration(labelText: 'Category'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () async { if (merchant.text.trim().isEmpty || keyword.text.trim().isEmpty) return; await AppDb.instance.saveRule(MerchantRule(id: existing?.id, merchant: merchant.text, keyword: keyword.text, type: type, category: category, isUserRule: true, enabled: existing?.enabled ?? true)); if (context.mounted) Navigator.pop(context); }, child: const Text('Save'))])));
}

Future<void> addCategoryDialog(BuildContext context) async {
  final name = TextEditingController(); String kind = 'expense'; await showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(title: const Text('Custom category'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), const SizedBox(height: 10), DropdownButtonFormField(value: kind, items: txTypes.map((e) => DropdownMenuItem(value: e, child: Text(titleCase(e)))).toList(), onChanged: (v) { if (v != null) setState(() => kind = v); }, decoration: const InputDecoration(labelText: 'Type'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () async { if (name.text.trim().isEmpty) return; await AppDb.instance.addCategory(name.text, kind); if (context.mounted) Navigator.pop(context); }, child: const Text('Add'))])));
}

Future<void> budgetDialog(BuildContext context, String category, double existing) async {
  final c = TextEditingController(text: existing > 0 ? existing.toStringAsFixed(0) : ''); await showDialog(context: context, builder: (context) => AlertDialog(title: Text(category == '__overall__' ? 'Overall monthly budget' : category), content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Monthly limit')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () async { final v = double.tryParse(c.text.replaceAll(',', '')); if (v == null || v <= 0) return; await AppDb.instance.setBudget(category, v); if (context.mounted) Navigator.pop(context); }, child: const Text('Save'))]));
}

Future<String?> pickCategory(BuildContext context, List<CategoryRecord> categories) => showModalBottomSheet<String>(context: context, builder: (context) => ListView(children: categories.where((c) => c.kind == 'expense').map((c) => ListTile(leading: Icon(iconFor(c.name)), title: Text(c.name), onTap: () => Navigator.pop(context, c.name))).toList()));

String titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
IconData iconFor(String category) { final c = category.toLowerCase(); if (c.contains('food') || c.contains('grocer')) return Icons.restaurant; if (c.contains('transport')) return Icons.directions_car; if (c.contains('shop')) return Icons.shopping_bag; if (c.contains('entertain')) return Icons.play_circle; if (c.contains('bill')) return Icons.receipt; if (c.contains('health')) return Icons.favorite; if (c.contains('travel')) return Icons.flight; if (c.contains('stock') || c.contains('invest') || c.contains('fund')) return Icons.trending_up; if (c.contains('salary')) return Icons.account_balance_wallet; if (c.contains('transfer')) return Icons.swap_horiz; return Icons.category; }
