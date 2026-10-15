import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cross_file/cross_file.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'app_db.dart';
import 'models.dart';
import 'native_bridge.dart';

final ValueNotifier<ThemeMode> expenseThemeMode = ValueNotifier(ThemeMode.light);
final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _date = DateFormat('dd MMM yyyy, h:mm a');

Future<void> loadEnhancedPreferences() async {
  final dark = await AppDb.instance.getBoolSetting('dark_mode');
  expenseThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;

  // v15 QA/stability release: screenshots are deliberately enabled.
  // Clear any persisted v12-v14 secure-screen preference so an upgrade cannot
  // keep FLAG_SECURE active. We can reintroduce this after UI testing is done.
  await AppDb.instance.setSetting('secure_screen_enabled', '0');
  try { await NativeBridge.setSecureScreen(false); } catch (_) {}
}

Future<void> runDailySmartAlerts() async {
  if (!await AppDb.instance.getBoolSetting('smart_alerts_enabled', fallback: true)) return;
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  if (await AppDb.instance.getSetting('last_smart_alert_day') == today) return;
  final insights = await AppDb.instance.smartInsights();
  if (insights.isEmpty) return;
  final first = insights.first;
  try {
    await NativeBridge.showSmartAlert('${first['title']}', '${first['message']}');
    await AppDb.instance.setSetting('last_smart_alert_day', today);
  } catch (_) {}
}

class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticateIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _unlocked = false;
    if (state == AppLifecycleState.resumed) _authenticateIfNeeded();
  }

  Future<void> _authenticateIfNeeded() async {
    final enabled = await AppDb.instance.getBoolSetting('privacy_lock_enabled');
    if (!enabled) {
      if (mounted) setState(() { _checking = false; _unlocked = true; });
      return;
    }
    if (_unlocked) return;
    if (mounted) setState(() => _checking = true);
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final ok = supported && await auth.authenticate(
        localizedReason: 'Unlock Expense Tracker',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (mounted) setState(() { _checking = false; _unlocked = ok; });
    } catch (_) {
      if (mounted) setState(() { _checking = false; _unlocked = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_unlocked) return widget.child;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_rounded, size: 54),
            const SizedBox(height: 16),
            const Text('Expense Tracker is locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Authenticate with your device lock to continue.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _authenticateIfNeeded, icon: const Icon(Icons.fingerprint), label: const Text('Unlock')),
          ]),
        ),
      ),
    );
  }
}

class EnhancementHubPage extends StatelessWidget {
  const EnhancementHubPage({super.key});
  @override
  Widget build(BuildContext context) {
    final items = <_HubItem>[
      _HubItem('Advanced search', 'Find transactions by merchant, amount, category, source or date.', Icons.manage_search_rounded, const AdvancedSearchPage()),
      _HubItem('Cash flow', 'Understand money in, money out and your current spending pace.', Icons.ssid_chart_rounded, const CashFlowPage()),
      _HubItem('Recurring payments', 'You decide which payments are recurring. The app will not guess.', Icons.repeat_rounded, const RecurringPaymentsPage()),
      _HubItem('Receipt scanner', 'Scan or import a receipt and save the expense locally.', Icons.document_scanner_rounded, const ReceiptImportPage()),
      _HubItem('Export & backup', 'Export reports or create an encrypted local backup.', Icons.ios_share_rounded, const ExportBackupPage()),
      _HubItem('Privacy & appearance', 'Biometric lock and dark mode. Screenshots remain enabled during QA.', Icons.security_rounded, const PrivacyAppearancePage()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('More tools')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final x = items[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              leading: CircleAvatar(child: Icon(x.icon)),
              title: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(x.subtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => x.page)),
            ),
          );
        },
      ),
    );
  }
}

class _HubItem {
  final String title, subtitle;
  final IconData icon;
  final Widget page;
  const _HubItem(this.title, this.subtitle, this.icon, this.page);
}

class SmartAutomationPage extends StatefulWidget {
  const SmartAutomationPage({super.key});
  @override
  State<SmartAutomationPage> createState() => _SmartAutomationPageState();
}

class _SmartAutomationPageState extends State<SmartAutomationPage> {
  bool loading = true;
  bool transfers = true;
  bool dedup = true;
  bool recurring = true;
  bool alerts = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    transfers = await AppDb.instance.getBoolSetting('smart_transfer_matching', fallback: true);
    dedup = await AppDb.instance.getBoolSetting('smart_dedup_enabled', fallback: true);
    recurring = await AppDb.instance.getBoolSetting('recurring_detection_enabled', fallback: true);
    alerts = await AppDb.instance.getBoolSetting('smart_alerts_enabled', fallback: true);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _set(String key, bool value) async {
    await AppDb.instance.setSetting(key, value ? '1' : '0');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Smart automation')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  SwitchListTile(
                    value: transfers,
                    secondary: const Icon(Icons.swap_horiz_rounded),
                    title: const Text('Smart transfer matching'),
                    subtitle: const Text('Match equal debit/credit pairs between different detected accounts.'),
                    onChanged: (v) { setState(() => transfers = v); _set('smart_transfer_matching', v); },
                  ),
                  SwitchListTile(
                    value: dedup,
                    secondary: const Icon(Icons.filter_alt_off_rounded),
                    title: const Text('Cross-source duplicate detection'),
                    subtitle: const Text('Hide likely duplicate SMS, PhonePe notification and UPI records.'),
                    onChanged: (v) { setState(() => dedup = v); _set('smart_dedup_enabled', v); },
                  ),
                  SwitchListTile(
                    value: recurring,
                    secondary: const Icon(Icons.autorenew_rounded),
                    title: const Text('Recurring payment detection'),
                    subtitle: const Text('Detect weekly, monthly, quarterly and yearly payment patterns.'),
                    onChanged: (v) { setState(() => recurring = v); _set('recurring_detection_enabled', v); },
                  ),
                  SwitchListTile(
                    value: alerts,
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Smart spending alerts'),
                    subtitle: const Text('Show local anomaly, budget forecast and upcoming recurring-payment alerts.'),
                    onChanged: (v) { setState(() => alerts = v); _set('smart_alerts_enabled', v); },
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('All automation runs locally on this device.', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
      );
}

class SmartTransfersPage extends StatefulWidget {
  const SmartTransfersPage({super.key});
  @override State<SmartTransfersPage> createState() => _SmartTransfersPageState();
}
class _SmartTransfersPageState extends State<SmartTransfersPage> {
  bool busy=false; int? matched; Map<String,int>? dedup;
  Future<void> run() async {
    setState(()=>busy=true);
    final m=await AppDb.instance.matchTransfers();
    final d=await AppDb.instance.smartDeduplicate();
    if(mounted)setState((){matched=m;dedup=d;busy=false;});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Smart transfers & dedup')),
    body:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Matches equal debit/credit amounts between different detected accounts within 12 hours. Duplicate intelligence also merges likely SMS + PhonePe + UPI copies.',style:TextStyle(height:1.5)),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:busy?null:run,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_fix_high),label:const Text('Run smart cleanup')),
      if(matched!=null)...[const SizedBox(height:20),Text('$matched transfer pair(s) matched',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),Text('${dedup?['ignored']??0} likely duplicate(s) hidden.')],
    ])),
  );
}

Future<bool> showMarkRecurringDialog(BuildContext context, TxRecord tx) async {
  String frequency = 'Monthly';
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Mark as recurring?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tx.normalizedMerchant.isNotEmpty ? tx.normalizedMerchant : tx.merchant,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 6),
            const Text('Only payments you confirm here will appear as recurring. Future matching transactions will automatically appear in this recurring group.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: frequency,
              decoration: const InputDecoration(labelText: 'Expected frequency'),
              items: const ['Weekly', 'Monthly', 'Quarterly', 'Yearly']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) => setState(() => frequency = value ?? frequency),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await AppDb.instance.saveRecurringRuleFromTransaction(tx, frequency: frequency);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Mark recurring'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

class RecurringPaymentsPage extends StatefulWidget {
  const RecurringPaymentsPage({super.key});
  @override
  State<RecurringPaymentsPage> createState() => _RecurringPaymentsPageState();
}

class _RecurringPaymentsPageState extends State<RecurringPaymentsPage> {
  Future<void> _add() async {
    final transactions = await AppDb.instance.transactions(limit: 120);
    if (!mounted) return;
    final seen = <String>{};
    final candidates = <TxRecord>[];
    for (final tx in transactions) {
      if (tx.type != 'expense' && tx.type != 'investment') continue;
      final key = (tx.normalizedMerchant.isNotEmpty ? tx.normalizedMerchant : tx.merchant).toLowerCase().trim();
      if (key.isEmpty || !seen.add(key)) continue;
      candidates.add(tx);
    }
    final selected = await showModalBottomSheet<TxRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Choose a payment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text('Pick one existing transaction. The app will use that merchant/person as the recurring rule instead of trying to detect patterns automatically.'),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final tx = candidates[i];
                    return Card(
                      child: ListTile(
                        title: Text(tx.normalizedMerchant.isNotEmpty ? tx.normalizedMerchant : tx.merchant, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${tx.category} • ${DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt))}'),
                        trailing: Text(_money.format(tx.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                        onTap: () => Navigator.pop(context, tx),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final saved = await showMarkRecurringDialog(context, selected);
    if (saved && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recurring payments')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add recurring'),
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: AppDb.instance.userRecurringSummaries(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final data = snap.data!;
            if (data.isEmpty) {
              return _EmptyInfo(
                icon: Icons.repeat_rounded,
                title: 'You have not marked anything recurring',
                text: 'Tap “Add recurring” and choose a transaction. The app will never decide recurring payments by itself.',
                action: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Choose a payment')),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: data.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = data[i];
                final nextMs = (r['nextDue'] as num?)?.toInt() ?? 0;
                final amount = (r['averageAmount'] as num?)?.toDouble() ?? 0;
                final count = (r['occurrences'] as num?)?.toInt() ?? 0;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: const CircleAvatar(child: Icon(Icons.repeat_rounded)),
                    title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(
                      '${amount > 0 ? '${_money.format(amount)} • ' : ''}${r['frequency']} • $count matching transaction${count == 1 ? '' : 's'}${nextMs > 0 ? ' • next around ${DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(nextMs))}' : ''}',
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Recurring options',
                      onSelected: (value) async {
                        if (value == 'delete') {
                          await AppDb.instance.deleteRecurringRule((r['id'] as num).toInt());
                          if (mounted) setState(() {});
                        }
                      },
                      itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove recurring rule'))],
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _RecurringRuleTransactionsPage(rule: r))),
                  ),
                );
              },
            );
          },
        ),
      );
}

class _RecurringRuleTransactionsPage extends StatelessWidget {
  final Map<String, Object?> rule;
  const _RecurringRuleTransactionsPage({required this.rule});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${rule['name']}')),
        body: FutureBuilder<List<TxRecord>>(
          future: AppDb.instance.recurringTransactionsForRule(rule),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const _EmptyInfo(icon: Icons.receipt_long_outlined, title: 'No matching transactions', text: 'Future matching transactions will appear here automatically.');
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final tx = rows[i];
                return Card(
                  child: ListTile(
                    title: Text(tx.merchant, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${tx.category} • ${_date.format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt))}'),
                    trailing: Text(_money.format(tx.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                );
              },
            );
          },
        ),
      );
}

class AccountsPage extends StatefulWidget { const AccountsPage({super.key}); @override State<AccountsPage> createState()=>_AccountsPageState(); }
class _AccountsPageState extends State<AccountsPage>{
  Future<void> edit(Map<String,Object?> a) async{
    final n=TextEditingController(text:'${a['name']}'); final b=TextEditingController(text:'${a['current_balance']}'); bool include=(a['include_net_worth'] as int)==1;
    await showDialog(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('Account'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Account name')),const SizedBox(height:10),TextField(controller:b,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Current balance',prefixText:'₹ ')),SwitchListTile(contentPadding:EdgeInsets.zero,value:include,onChanged:(v)=>set(()=>include=v),title:const Text('Include in net worth'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{await AppDb.instance.updateAccount(a['id'] as int,name:n.text,balance:double.tryParse(b.text)??0,includeNetWorth:include);if(c.mounted)Navigator.pop(c);},child:const Text('Save'))]))); if(mounted)setState((){});
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Accounts')),body:FutureBuilder<List<Object>>(future:Future.wait<Object>([AppDb.instance.accounts(),AppDb.instance.spendByAccount()]),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final d=s.data![0] as List<Map<String,Object?>>;final stats=s.data![1] as Map<String,Map<String,double>>;if(d.isEmpty)return const _EmptyInfo(icon:Icons.account_balance,title:'No account hints found',text:'Account detection uses the SMS sender and last 3–4 account/card digits when banks include them.');return ListView.builder(padding:const EdgeInsets.all(16),itemCount:d.length,itemBuilder:(context,i){final a=d[i];final st=stats['${a['account_key']}']??const <String,double>{};return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:const CircleAvatar(child:Icon(Icons.account_balance)),title:Text('${a['name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Detected: ${a['sender']} ••••${a['account_hint']}\nSpent ${_money.format(st['expense']??0)} • Income ${_money.format(st['income']??0)}'),isThreeLine:true,trailing:Text(_money.format(a['current_balance'])),onTap:()=>edit(a)));});}));
}

class MerchantAliasesPage extends StatefulWidget{const MerchantAliasesPage({super.key});@override State<MerchantAliasesPage> createState()=>_MerchantAliasesPageState();}
class _MerchantAliasesPageState extends State<MerchantAliasesPage>{
  Future<void> add()async{final p=TextEditingController(),n=TextEditingController();await showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('Merchant alias'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:p,decoration:const InputDecoration(labelText:'Text/pattern',hintText:'zomato@icici')),const SizedBox(height:10),TextField(controller:n,decoration:const InputDecoration(labelText:'Normalize to',hintText:'Zomato'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{if(p.text.trim().isNotEmpty&&n.text.trim().isNotEmpty){await AppDb.instance.saveMerchantAlias(p.text,n.text);if(c.mounted)Navigator.pop(c);}},child:const Text('Save'))]));if(mounted)setState((){});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Merchant normalization'),actions:[IconButton(onPressed:add,icon:const Icon(Icons.add))]),body:FutureBuilder<List<Map<String,Object?>>>(future:AppDb.instance.merchantAliases(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView.builder(padding:const EdgeInsets.all(16),itemCount:s.data!.length,itemBuilder:(context,i){final a=s.data![i];return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(title:Text('${a['normalized_name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Contains: ${a['pattern']}'),trailing:IconButton(onPressed:()async{await AppDb.instance.deleteMerchantAlias(a['id'] as int);setState((){});},icon:const Icon(Icons.delete_outline))));});}));
}

class AdvancedSearchPage extends StatefulWidget {
  const AdvancedSearchPage({super.key});
  @override
  State<AdvancedSearchPage> createState() => _AdvancedSearchPageState();
}

class _AdvancedSearchPageState extends State<AdvancedSearchPage> {
  final q = TextEditingController();
  final min = TextEditingController();
  final max = TextEditingController();
  final account = TextEditingController();
  String type = 'all';
  String category = '';
  String source = '';
  DateTime? from, to;
  List<TxRecord>? results;
  bool busy = false;

  @override
  void dispose() {
    q.dispose();
    min.dispose();
    max.dispose();
    account.dispose();
    super.dispose();
  }

  Future<void> search() async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final found = await AppDb.instance.searchTransactions(
        query: q.text,
        type: type,
        category: category,
        source: source,
        account: account.text.trim(),
        minAmount: double.tryParse(min.text.replaceAll(',', '')),
        maxAmount: double.tryParse(max.text.replaceAll(',', '')),
        startMs: from?.millisecondsSinceEpoch,
        endMs: to == null ? null : DateTime(to!.year, to!.month, to!.day + 1).millisecondsSinceEpoch,
        limit: 300,
      );
      if (mounted) setState(() => results = found);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void clear() {
    q.clear(); min.clear(); max.clear(); account.clear();
    setState(() { type = 'all'; category = ''; source = ''; from = null; to = null; results = null; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Advanced search'),
          actions: [IconButton(tooltip: 'Clear filters', onPressed: clear, icon: const Icon(Icons.refresh_rounded))],
        ),
        body: FutureBuilder<List<CategoryRecord>>(
          future: AppDb.instance.categories(),
          builder: (context, snap) {
            final cats = snap.data ?? const <CategoryRecord>[];
            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: q,
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Merchant, note, SMS text…'),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => search(),
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, c) {
                                final wide = c.maxWidth >= 520;
                                final width = wide ? (c.maxWidth - 12) / 2 : c.maxWidth;
                                return Wrap(
                                  spacing: 12, runSpacing: 12,
                                  children: [
                                    SizedBox(width: width, child: DropdownButtonFormField<String>(value: type, isExpanded: true, items: ['all','expense','income','investment','transfer','refund'].map((x) => DropdownMenuItem(value: x, child: Text(x == 'all' ? 'All types' : _cap(x), overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => type = v ?? 'all'), decoration: const InputDecoration(labelText: 'Type'))),
                                    SizedBox(width: width, child: DropdownButtonFormField<String>(value: category, isExpanded: true, items: [const DropdownMenuItem(value: '', child: Text('Any category')),...cats.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name, overflow: TextOverflow.ellipsis)))], onChanged: (v) => setState(() => category = v ?? ''), decoration: const InputDecoration(labelText: 'Category'))),
                                    SizedBox(width: width, child: TextField(controller: min, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Min amount', prefixText: '₹ '))),
                                    SizedBox(width: width, child: TextField(controller: max, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Max amount', prefixText: '₹ '))),
                                    SizedBox(width: width, child: DropdownButtonFormField<String>(value: source, isExpanded: true, items: const [DropdownMenuItem(value: '', child: Text('Any source')),DropdownMenuItem(value: 'sms', child: Text('SMS')),DropdownMenuItem(value: 'phonepe_notification', child: Text('PhonePe')),DropdownMenuItem(value: 'upi_intent', child: Text('UPI')),DropdownMenuItem(value: 'manual', child: Text('Manual')),DropdownMenuItem(value: 'receipt_ocr', child: Text('Receipt'))], onChanged: (v) => setState(() => source = v ?? ''), decoration: const InputDecoration(labelText: 'Source'))),
                                    SizedBox(width: width, child: TextField(controller: account, decoration: const InputDecoration(labelText: 'Account hint / sender', prefixIcon: Icon(Icons.account_balance_outlined)))),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: context, initialDate: from ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now()); if (d != null) setState(() => from = d); }, icon: const Icon(Icons.date_range), label: FittedBox(fit: BoxFit.scaleDown, child: Text(from == null ? 'From date' : DateFormat('dd MMM yy').format(from!))))),
                                const SizedBox(width: 10),
                                Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: context, initialDate: to ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now()); if (d != null) setState(() => to = d); }, icon: const Icon(Icons.event), label: FittedBox(fit: BoxFit.scaleDown, child: Text(to == null ? 'To date' : DateFormat('dd MMM yy').format(to!))))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: busy ? null : search,
                              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.manage_search),
                              label: Text(busy ? 'Searching…' : 'Search'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (results == null)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyInfo(icon: Icons.manage_search, title: 'Search transactions', text: 'Combine merchant text, amount, category, type, source, account and date filters.'))
                else if (results!.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No matches')))
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    sliver: SliverToBoxAdapter(child: Text('${results!.length} result${results!.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TxMiniTile(tx: results![i]),
                        ),
                        childCount: results!.length,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
}

class CashFlowPage extends StatelessWidget {
  const CashFlowPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cash flow')),
        body: FutureBuilder<Map<String, double>>(
          future: AppDb.instance.cashFlowSummary(),
          builder: (context, snap) {
            if (snap.hasError) return _EmptyInfo(icon: Icons.error_outline, title: 'Could not calculate cash flow', text: '${snap.error}');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final x = snap.data!;
            final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(monthLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Transfers are excluded. Investments are shown separately from everyday expenses.', style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                const SizedBox(height: 14),
                _MetricCard('Net cash flow', _money.format(x['net']), Icons.account_balance_wallet_rounded, emphasized: true),
                const SizedBox(height: 2),
                _MetricGrid(
                  children: [
                    _MetricCard('Money in', _money.format(x['inflow']), Icons.south_west_rounded, subtitle: 'Income + refunds'),
                    _MetricCard('Money out', _money.format(x['outflow']), Icons.north_east_rounded, subtitle: 'Expenses + investments'),
                    _MetricCard('Income', _money.format(x['income']), Icons.payments_outlined),
                    _MetricCard('Refunds', _money.format(x['refund']), Icons.replay_rounded),
                    _MetricCard('Expenses', _money.format(x['expense']), Icons.shopping_bag_outlined),
                    _MetricCard('Investments', _money.format(x['investment']), Icons.trending_up_rounded),
                    _MetricCard('Daily expense avg.', _money.format(x['dailyAverage']), Icons.today_rounded),
                    _MetricCard('Projected expense', _money.format(x['projectedExpense']), Icons.show_chart_rounded),
                  ],
                ),
                _MetricCard('Savings rate', '${(x['savingsRate'] ?? 0).toStringAsFixed(1)}%', Icons.savings_rounded, subtitle: 'Based on income vs net everyday expenses'),
              ],
            );
          },
        ),
      );
}

class SmartInsightsPage extends StatelessWidget { const SmartInsightsPage({super.key}); @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Smart insights')),body:FutureBuilder<List<Map<String,Object?>>>(future:AppDb.instance.smartInsights(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());if(s.data!.isEmpty)return const _EmptyInfo(icon:Icons.check_circle_outline,title:'Nothing unusual detected',text:'Insights will appear when spending deviates from your recent pattern or a budget is projected to exceed.');return ListView.builder(padding:const EdgeInsets.all(16),itemCount:s.data!.length,itemBuilder:(context,i){final x=s.data![i];return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:CircleAvatar(child:Icon(x['kind']=='forecast'?Icons.speed:x['kind']=='recurring'?Icons.autorenew:Icons.insights)),title:Text('${x['title']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${x['message']}')));});})); }

class ReceiptImportPage extends StatefulWidget {
  const ReceiptImportPage({super.key});

  @override
  State<ReceiptImportPage> createState() => _ReceiptImportPageState();
}

class _ReceiptImportPageState extends State<ReceiptImportPage> {
  bool busy = false;
  String raw = '';
  String receiptDateText = '';
  String taxText = '';
  List<String> itemLines = const [];
  final merchant = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  String category = 'Uncategorized';

  @override
  void dispose() {
    merchant.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    setState(() => busy = true);
    TextRecognizer? recognizer;
    try {
      final x = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (x == null) return;
      final input = InputImage.fromFilePath(x.path);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(input);
      raw = result.text;
      final lines = raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      merchant.text = lines.isEmpty ? 'Receipt' : lines.first.take(60);

      final totalPatterns = [
        RegExp(r'(?:grand\s*total|amount\s*paid|total)\s*[:₹Rs.INR ]*([0-9,]+(?:\.\d{1,2})?)', caseSensitive: false),
        RegExp(r'(?:₹|Rs\.?|INR)\s*([0-9,]+(?:\.\d{1,2})?)', caseSensitive: false),
      ];
      for (final pattern in totalPatterns) {
        final matches = pattern.allMatches(raw).toList();
        if (matches.isNotEmpty) {
          amount.text = matches.last.group(1)!.replaceAll(',', '');
          break;
        }
      }

      final tax = RegExp(
        r'(?:gst|tax|vat)\s*[:₹Rs.INR ]*([0-9,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ).firstMatch(raw);
      taxText = tax?.group(1)?.replaceAll(',', '') ?? '';
      final dateMatch = RegExp(r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b').firstMatch(raw);
      receiptDateText = dateMatch?.group(1) ?? '';

      final itemPattern = RegExp(r'^(.*?\S)\s+(?:₹|Rs\.?|INR)?\s*([0-9,]+(?:\.\d{1,2})?)$', caseSensitive: false);
      final totalWords = RegExp(r'\b(total|subtotal|tax|gst|vat|change|cash|card|upi|amount paid)\b', caseSensitive: false);
      itemLines = lines
          .where((line) {
            final m = itemPattern.firstMatch(line);
            if (m == null || totalWords.hasMatch(line)) return false;
            final label = m.group(1)?.trim() ?? '';
            return label.length >= 2 && RegExp(r'[A-Za-z]').hasMatch(label);
          })
          .take(20)
          .toList();

      if (note.text.trim().isEmpty) {
        final parts = <String>[];
        if (receiptDateText.isNotEmpty) parts.add('Receipt date $receiptDateText');
        if (taxText.isNotEmpty) parts.add('Tax ₹$taxText');
        if (itemLines.isNotEmpty) parts.add('${itemLines.length} item line(s) detected');
        note.text = parts.join(' • ');
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read receipt: $e')));
      }
    } finally {
      await recognizer?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final value = double.tryParse(amount.text.replaceAll(',', ''));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid receipt amount.')));
      return;
    }
    final itemSummary = itemLines.isEmpty ? '' : '\nItems detected:\n${itemLines.join('\n')}';
    await AppDb.instance.addReceiptTransaction(
      amount: value,
      merchant: merchant.text.trim().isEmpty ? 'Receipt' : merchant.text.trim(),
      category: category,
      rawText: raw,
      note: '${note.text.trim()}$itemSummary'.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt transaction saved.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Receipt scanner')),
        body: FutureBuilder<List<CategoryRecord>>(
          future: AppDb.instance.expenseCategories(),
          builder: (context, snapshot) {
            final cats = snapshot.data ?? [];
            if (cats.isNotEmpty && !cats.any((c) => c.name == category)) category = cats.first.name;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : () => pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (raw.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: category,
                    items: cats.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                    onChanged: (v) => setState(() => category = v ?? category),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 10),
                  if (receiptDateText.isNotEmpty || taxText.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Detected ${receiptDateText.isNotEmpty ? 'date $receiptDateText' : ''}'
                        '${receiptDateText.isNotEmpty && taxText.isNotEmpty ? ' • ' : ''}'
                        '${taxText.isNotEmpty ? 'tax ₹$taxText' : ''}',
                      ),
                    ),
                  if (itemLines.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('${itemLines.length} receipt item line(s) detected'),
                      children: itemLines.map((line) => ListTile(dense: true, title: Text(line))).toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: note, decoration: const InputDecoration(labelText: 'Note / receipt details')),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Full recognized receipt text'),
                    children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText(raw))],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Save transaction')),
                ],
              ],
            );
          },
        ),
      );
}

class ExportBackupPage extends StatefulWidget {
  const ExportBackupPage({super.key});

  @override
  State<ExportBackupPage> createState() => _ExportBackupPageState();
}

class _ExportBackupPageState extends State<ExportBackupPage> {
  bool busy = false;

  Future<File> _temp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> exportCsv() async {
    setState(() => busy = true);
    try {
      final tx = await AppDb.instance.transactions(limit: 10000);
      final out = StringBuffer('date,type,category,merchant,amount,source,note,account,upi_ref\n');
      for (final t in tx) {
        out.writeln([
          _csvEscape(DateTime.fromMillisecondsSinceEpoch(t.occurredAt).toIso8601String()),
          _csvEscape(t.type),
          _csvEscape(t.category),
          _csvEscape(t.normalizedMerchant.isEmpty ? t.merchant : t.normalizedMerchant),
          t.amount.toStringAsFixed(2),
          _csvEscape(t.source),
          _csvEscape(t.note),
          _csvEscape(t.accountHint),
          _csvEscape(t.upiReference),
        ].join(','));
      }
      final file = await _temp(
        'expense-tracker-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        utf8.encode(out.toString()),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportPdf() async {
    setState(() => busy = true);
    try {
      final tx = await AppDb.instance.transactions(limit: 500);
      final doc = pw.Document();
      final total = tx.where((t) => t.type == 'expense').fold<double>(0, (sum, t) => sum + t.amount);
      doc.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Header(level: 0, child: pw.Text('Expense Tracker Report')),
            pw.Text('Generated ${DateFormat('dd MMM yyyy').format(DateTime.now())}'),
            pw.SizedBox(height: 8),
            pw.Text('Total expense: INR ${total.toStringAsFixed(0)}'),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Merchant', 'Category', 'Type', 'INR'],
              data: tx.take(200).map((t) => [
                    DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(t.occurredAt)),
                    t.normalizedMerchant.isEmpty ? t.merchant : t.normalizedMerchant,
                    t.category,
                    t.type,
                    t.amount.toStringAsFixed(0),
                  ]).toList(),
            ),
          ],
        ),
      );
      final file = await _temp(
        'expense-report-${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
        await doc.save(),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _passphrase(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Backup passphrase'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> backup() async {
    final pass = await _passphrase('Create encrypted backup');
    if (pass == null || pass.length < 4) return;
    setState(() => busy = true);
    try {
      final snapshot = await AppDb.instance.exportSnapshot();
      final salt = SecretKeyData.random(length: 16).bytes;
      final nonce = SecretKeyData.random(length: 12).bytes;
      final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);
      final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode(jsonEncode(snapshot)),
        secretKey: key,
        nonce: nonce,
      );
      final wrapper = {
        'format': 'expense-tracker-backup-v1',
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'cipher': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      };
      final file = await _temp(
        'expense-tracker-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.etbak',
        utf8.encode(jsonEncode(wrapper)),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    final pass = await _passphrase('Restore encrypted backup');
    if (pass == null || pass.isEmpty) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => busy = true);
    try {
      final wrapper = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      if (wrapper['format'] != 'expense-tracker-backup-v1') throw const FormatException('Unsupported backup format');
      final salt = base64Decode(wrapper['salt'] as String);
      final nonce = base64Decode(wrapper['nonce'] as String);
      final cipher = base64Decode(wrapper['cipher'] as String);
      final mac = base64Decode(wrapper['mac'] as String);
      final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);
      final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      await AppDb.instance.restoreSnapshot(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored. Reopen the app to refresh all screens.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Export & backup')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(),
            _ToolTile(
              icon: Icons.table_chart,
              title: 'Export CSV',
              subtitle: 'All accepted transactions for spreadsheet analysis.',
              onTap: exportCsv,
            ),
            _ToolTile(
              icon: Icons.picture_as_pdf,
              title: 'Export PDF',
              subtitle: 'Share a readable transaction report.',
              onTap: exportPdf,
            ),
            _ToolTile(
              icon: Icons.lock_clock,
              title: 'Encrypted backup',
              subtitle: 'AES-256-GCM protected local data backup.',
              onTap: backup,
            ),
            _ToolTile(
              icon: Icons.restore,
              title: 'Restore backup',
              subtitle: 'Choose an .etbak file and enter its passphrase.',
              onTap: restore,
            ),
          ],
        ),
      );
}

class ReviewQueuePage extends StatefulWidget {
  const ReviewQueuePage({super.key});
  @override
  State<ReviewQueuePage> createState() => _ReviewQueuePageState();
}

class _ReviewQueuePageState extends State<ReviewQueuePage> {
  Future<void> act(TxRecord t, bool accept) async {
    if (t.id == null) return;
    if (accept) {
      await AppDb.instance.acceptReview(t.id!);
    } else {
      await AppDb.instance.ignoreReview(t.id!);
    }
    if (mounted) setState(() {});
  }

  Future<void> fix(TxRecord t) async {
    if (t.id == null) return;
    final merchant = TextEditingController(text: t.merchant);
    final note = TextEditingController(text: t.note);
    var type = t.type;
    var category = t.category;
    final categories = await AppDb.instance.categories();
    bool allowed(CategoryRecord c) => c.kind == type || type == 'transfer' || type == 'refund';
    final initialEligible = categories.where(allowed).toList();
    if (!initialEligible.any((c) => c.name == category) && initialEligible.isNotEmpty) {
      category = initialEligible.first.name;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Fix classification'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const ['expense', 'investment', 'income', 'transfer', 'refund']
                      .map((x) => DropdownMenuItem(value: x, child: Text(_cap(x))))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      type = value;
                      final matching = categories.where((c) => c.kind == type).toList();
                      if (matching.isNotEmpty) category = matching.first.name;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: categories.where((c) => c.kind == type || type == 'transfer' || type == 'refund').any((c) => c.name == category) ? category : null,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .where((c) => c.kind == type || type == 'transfer' || type == 'refund')
                      .map((c) => DropdownMenuItem(value: c.name, child: Text(c.name)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => category = value ?? category),
                ),
                const SizedBox(height: 10),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final merchantValue = merchant.text.trim().isEmpty ? t.merchant : merchant.text.trim();
                final similarCount = await AppDb.instance.countSimilarTransactions(t);
                if (!dialogContext.mounted) return;
                final scope = await showDialog<String>(
                  context: dialogContext,
                  builder: (scopeContext) => AlertDialog(
                    title: const Text('Apply this correction?'),
                    content: Text(
                      similarCount > 0
                          ? 'There are $similarCount similar existing transaction${similarCount == 1 ? '' : 's'}. Update only this one, or apply the correction to similar transactions and future messages?'
                          : 'Save only this transaction, or remember the same correction for future similar messages?',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(scopeContext, 'one'), child: const Text('Only this')),
                      FilledButton(onPressed: () => Navigator.pop(scopeContext, 'all'), child: Text(similarCount > 0 ? 'All similar + future' : 'Remember for future')),
                    ],
                  ),
                );
                if (scope == null) return;
                await AppDb.instance.updateTransaction(
                  t.id!,
                  type: type,
                  category: category,
                  merchant: merchantValue,
                  note: note.text.trim(),
                  learnRule: false,
                );
                if (scope == 'all') {
                  await AppDb.instance.applyCorrectionToSimilar(source: t, type: type, category: category, merchant: merchantValue);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save correction'),
            ),
          ],
        ),
      ),
    );
    merchant.dispose();
    note.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Financial inbox')),
        body: FutureBuilder<List<TxRecord>>(
          future: AppDb.instance.reviewTransactions(),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            if (s.data!.isEmpty) {
              return const _EmptyInfo(
                icon: Icons.task_alt,
                title: 'Inbox is clear',
                text: 'Low-confidence financial messages appear here so the app asks instead of guessing.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: s.data!.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = s.data![i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(t.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                            const SizedBox(width: 8),
                            Text(_money.format(t.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${_cap(t.type)} • ${t.category} • ${(t.classificationConfidence * 100).round()}% confidence'),
                        if (t.rawMessage.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(t.rawMessage, maxLines: 4, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton(onPressed: () => act(t, false), child: const Text('Ignore'))),
                            const SizedBox(width: 8),
                            Expanded(child: OutlinedButton(onPressed: () => fix(t), child: const Text('Fix'))),
                            const SizedBox(width: 8),
                            Expanded(child: FilledButton(onPressed: () => act(t, true), child: const Text('Accept'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

class ModelFeedbackPage extends StatelessWidget{const ModelFeedbackPage({super.key});@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('ML feedback')),body:FutureBuilder<Map<String,int>>(future:AppDb.instance.modelFeedbackStats(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final x=s.data!;final auto=x['auto']??0, corrected=x['corrected']??0;final acceptance=auto==0?0.0:((auto-corrected)/auto*100).clamp(0,100).toDouble();return ListView(padding:const EdgeInsets.all(16),children:[_MetricCard('Estimated accepted without correction','${acceptance.toStringAsFixed(1)}%',Icons.psychology),_MetricCard('Auto-classified','$auto',Icons.auto_awesome),_MetricCard('User corrections','$corrected',Icons.edit_note),_MetricCard('Review accepted','${x['accepted']??0}',Icons.check_circle),_MetricCard('Review ignored','${x['ignored']??0}',Icons.block),_MetricCard('Pending review','${x['pending']??0}',Icons.pending_actions),const Padding(padding:EdgeInsets.all(8),child:Text('These are local product-quality signals, not a formal benchmark accuracy score.',style:TextStyle(fontSize:12))) ]); }));}

class NetWorthPage extends StatefulWidget{const NetWorthPage({super.key});@override State<NetWorthPage> createState()=>_NetWorthPageState();}
class _NetWorthPageState extends State<NetWorthPage>{
  Future<void> add([Map<String,Object?>? item])async{final n=TextEditingController(text:item?['name']?.toString()??'');final b=TextEditingController(text:item?['balance']?.toString()??'');String type=item?['item_type']?.toString()??'asset';final cat=TextEditingController(text:item?['category']?.toString()??'');await showDialog(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(item==null?'Add net-worth item':'Edit item'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Name')),const SizedBox(height:8),DropdownButtonFormField(value:type,items:const [DropdownMenuItem(value:'asset',child:Text('Asset')),DropdownMenuItem(value:'liability',child:Text('Liability'))],onChanged:(v)=>set(()=>type=v??type),decoration:const InputDecoration(labelText:'Type')),const SizedBox(height:8),TextField(controller:cat,decoration:const InputDecoration(labelText:'Category')),const SizedBox(height:8),TextField(controller:b,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Balance',prefixText:'₹ '))]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{await AppDb.instance.saveNetWorthItem(id: item == null ? null : item['id'] as int, name:n.text,itemType:type,category:cat.text,balance:double.tryParse(b.text)??0);if(c.mounted)Navigator.pop(c);},child:const Text('Save'))])));if(mounted)setState((){});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Net worth'),actions:[IconButton(onPressed:()=>add(),icon:const Icon(Icons.add))]),body:FutureBuilder<List<Object>>(future:Future.wait<Object>([AppDb.instance.netWorthSummary(),AppDb.instance.netWorthItems()]),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final sum=s.data![0] as Map<String,double>;final items=s.data![1] as List<Map<String,Object?>>;return ListView(padding:const EdgeInsets.all(16),children:[const _SimpleNotice(text:'Net worth is optional and manual. SMS-detected bank/card hints are not treated as balances.'),const SizedBox(height:12),_MetricCard('Net worth',_money.format(sum['netWorth']),Icons.account_balance_wallet),Row(children:[Expanded(child:_MetricCard('Assets',_money.format(sum['assets']),Icons.add_circle_outline)),const SizedBox(width:8),Expanded(child:_MetricCard('Liabilities',_money.format(sum['liabilities']),Icons.remove_circle_outline))]),const SizedBox(height:8),...items.map((x)=>Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(title:Text('${x['name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${_cap('${x['item_type']}')} • ${x['category']}'),trailing:Text(_money.format(x['balance'])),onTap:()=>add(x),onLongPress:()async{await AppDb.instance.deleteNetWorthItem(x['id'] as int);setState((){});}))) ]); }));}

class PrivacyAppearancePage extends StatefulWidget {
  const PrivacyAppearancePage({super.key});
  @override
  State<PrivacyAppearancePage> createState() => _PrivacyAppearancePageState();
}

class _PrivacyAppearancePageState extends State<PrivacyAppearancePage> {
  bool loading = true;
  bool lock = false;
  bool dark = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    lock = await AppDb.instance.getBoolSetting('privacy_lock_enabled');
    dark = await AppDb.instance.getBoolSetting('dark_mode');
    await AppDb.instance.setSetting('secure_screen_enabled', '0');
    try { await NativeBridge.setSecureScreen(false); } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _set(String key, bool value) async {
    await AppDb.instance.setSetting(key, value ? '1' : '0');
    if (key == 'dark_mode') {
      expenseThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Privacy & appearance')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  SwitchListTile(
                    value: lock,
                    onChanged: (v) { setState(() => lock = v); _set('privacy_lock_enabled', v); },
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Biometric/device lock'),
                    subtitle: const Text('Require local authentication when opening the app.'),
                  ),
                  SwitchListTile(
                    value: dark,
                    onChanged: (v) { setState(() => dark = v); _set('dark_mode', v); },
                    secondary: const Icon(Icons.dark_mode),
                    title: const Text('Dark mode'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.photo_camera_outlined),
                    title: Text('Screenshots enabled'),
                    subtitle: Text('Screen capture protection is temporarily disabled so UI issues can be reported with screenshots.'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.cloud_off),
                    title: Text('Local-first privacy'),
                    subtitle: Text('SMS, notification text, receipts, ML decisions and backups stay on device unless you explicitly share/export them.'),
                  ),
                ],
              ),
      );
}

class HomeWidgetPage extends StatefulWidget{const HomeWidgetPage({super.key});@override State<HomeWidgetPage> createState()=>_HomeWidgetPageState();}
class _HomeWidgetPageState extends State<HomeWidgetPage>{String status='';Future<void>refresh()async{try{await NativeBridge.updateHomeWidget();setState(()=>status='Widget refreshed. Add “Expense Tracker” from your Android home-screen widget picker if it is not already placed.');}catch(e){setState(()=>status='Could not refresh widget: $e');}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Home widget')),body:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Icon(Icons.widgets_rounded,size:64),const SizedBox(height:16),const Text('Monthly spending widget',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),const SizedBox(height:8),const Text('Shows current-month expense and remaining overall budget without opening the app.',textAlign:TextAlign.center),const SizedBox(height:24),FilledButton.icon(onPressed:refresh,icon:const Icon(Icons.refresh),label:const Text('Refresh widget')),if(status.isNotEmpty)...[const SizedBox(height:16),Text(status,textAlign:TextAlign.center)] ])));}

class SplitTransactionPage extends StatefulWidget{
  final TxRecord transaction;
  const SplitTransactionPage({super.key,required this.transaction});
  @override State<SplitTransactionPage> createState()=>_SplitTransactionPageState();
}
class _SplitTransactionPageState extends State<SplitTransactionPage>{final rows=<Map<String,dynamic>>[];List<CategoryRecord>cats=[];@override void initState(){super.initState();load();}Future<void>load()async{cats=await AppDb.instance.expenseCategories();final existing=await AppDb.instance.splitsFor(widget.transaction.id!);if(existing.isNotEmpty)rows.addAll(existing.map((e)=>{'category':e['category'],'amount':(e['amount']as num).toDouble(),'note':e['note']??''}));else rows.add({'category':widget.transaction.category,'amount':widget.transaction.amount,'note':''});if(mounted)setState((){});}double get total=>rows.fold(0,(a,b)=>a+(b['amount']as double));Future<void>save()async{if((total-widget.transaction.amount).abs()>0.01){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Split amounts must equal the transaction amount.')));return;}await AppDb.instance.setSplits(widget.transaction.id!,rows.map((x)=><String,Object?>{'category':x['category'],'amount':x['amount'],'note':x['note']}).toList());if(mounted)Navigator.pop(context,true);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Split transaction')),body:ListView(padding:const EdgeInsets.all(16),children:[Text('${widget.transaction.merchant} • ${_money.format(widget.transaction.amount)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:12),...rows.asMap().entries.map((e){final i=e.key,r=e.value;return Card(margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:DropdownButtonFormField(value:r['category'] as String,items:cats.map((c)=>DropdownMenuItem(value:c.name,child:Text(c.name))).toList(),onChanged:(v)=>setState(()=>r['category']=v),decoration:const InputDecoration(labelText:'Category'))),const SizedBox(width:8),SizedBox(width:110,child:TextFormField(initialValue:(r['amount']as double).toStringAsFixed(2),keyboardType:TextInputType.number,onChanged:(v)=>r['amount']=double.tryParse(v)??0,decoration:const InputDecoration(labelText:'Amount'))),IconButton(onPressed:rows.length<=1?null:()=>setState(()=>rows.removeAt(i)),icon:const Icon(Icons.close))])));}),OutlinedButton.icon(onPressed:()=>setState(()=>rows.add({'category':cats.isEmpty?'Uncategorized':cats.first.name,'amount':0.0,'note':''})),icon:const Icon(Icons.add),label:const Text('Add split')),const SizedBox(height:8),Text('Split total: ${_money.format(total)} / ${_money.format(widget.transaction.amount)}',style:TextStyle(fontWeight:FontWeight.w800,color:(total-widget.transaction.amount).abs()<=0.01?Colors.green:Colors.red)),const SizedBox(height:12),FilledButton(onPressed:save,child:const Text('Save split'))]));}

class _TxMiniTile extends StatelessWidget {
  final TxRecord tx;
  const _TxMiniTile({required this.tx});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Icon(tx.type == 'income' ? Icons.south_west : Icons.north_east),
          ),
          title: Text(
            tx.normalizedMerchant.isEmpty ? tx.merchant : tx.normalizedMerchant,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${tx.category} • ${_date.format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt))}',
          ),
          trailing: Text(
            '${tx.type == 'income' || tx.type == 'refund' ? '+' : '-'}${_money.format(tx.amount)}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (sheetContext) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: .65,
              maxChildSize: .9,
              builder: (sheetContext, scrollController) => ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(tx.merchant, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('${_money.format(tx.amount)} • ${tx.type} • ${tx.category}'),
                  const Divider(height: 28),
                  Text(
                    'Source: ${tx.source}\n'
                    'Account: ${tx.accountHint.isEmpty ? '—' : tx.accountHint}\n'
                    'UPI ref: ${tx.upiReference.isEmpty ? '—' : tx.upiReference}\n'
                    'Confidence: ${(tx.classificationConfidence * 100).round()}%',
                  ),
                  if (tx.note.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Note: ${tx.note}'),
                  ],
                  if (tx.rawMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Full original message', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    SelectableText(tx.rawMessage),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final String? subtitle;
  final bool emphasized;
  const _MetricCard(this.label, this.value, this.icon, {this.subtitle, this.emphasized = false});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: EdgeInsets.all(emphasized ? 18 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(radius: emphasized ? 23 : 20, child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: TextStyle(fontSize: emphasized ? 24 : 20, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _MetricGrid extends StatelessWidget {
  final List<Widget> children;
  const _MetricGrid({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final columns = c.maxWidth >= 520 ? 2 : 1;
          final width = columns == 2 ? (c.maxWidth - 10) / 2 : c.maxWidth;
          return Wrap(
            spacing: 10,
            runSpacing: 0,
            children: children.map((child) => SizedBox(width: width, child: child)).toList(),
          );
        },
      );
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoPill({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 15), const SizedBox(width: 5), Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))],
        ),
      );
}

class _ToolTile extends StatelessWidget{final IconData icon;final String title,subtitle;final VoidCallback onTap;const _ToolTile({required this.icon,required this.title,required this.subtitle,required this.onTap});@override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right),onTap:onTap));}

class _SimpleNotice extends StatelessWidget {
  final String text;
  const _SimpleNotice({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      );
}


class _EmptyInfo extends StatelessWidget{final IconData icon;final String title,text;final Widget? action;const _EmptyInfo({required this.icon,required this.title,required this.text,this.action});@override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:54,color:Theme.of(context).colorScheme.primary),const SizedBox(height:14),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:7),Text(text,textAlign:TextAlign.center,style:const TextStyle(height:1.4)),if(action!=null)...[const SizedBox(height:18),action!]])));}
String _cap(String x)=>x.isEmpty?x:x[0].toUpperCase()+x.substring(1);

extension _StringTake on String { String take(int n)=>length<=n?this:substring(0,n); }
