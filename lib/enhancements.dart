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
  final secure = await AppDb.instance.getBoolSetting('secure_screen_enabled', fallback: true);
  try { await NativeBridge.setSecureScreen(secure); } catch (_) {}
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
      _HubItem('Smart automation', 'Control transfer matching, dedup, recurring detection and alerts.', Icons.tune_rounded, const SmartAutomationPage()),
      _HubItem('Smart transfers', 'Match your own-account debit and credit pairs.', Icons.swap_horiz_rounded, const SmartTransfersPage()),
      _HubItem('Recurring & subscriptions', 'Detect bills, SIPs, EMIs and subscriptions.', Icons.autorenew_rounded, const RecurringPaymentsPage()),
      _HubItem('Accounts', 'Detected bank/account hints and balances.', Icons.account_balance_rounded, const AccountsPage()),
      _HubItem('Merchant cleanup', 'Merge messy merchant names into one merchant.', Icons.storefront_rounded, const MerchantAliasesPage()),
      _HubItem('Advanced search', 'Search by merchant, amount, category and source.', Icons.manage_search_rounded, const AdvancedSearchPage()),
      _HubItem('Cash flow', 'Savings rate, daily average and month-end projection.', Icons.ssid_chart_rounded, const CashFlowPage()),
      _HubItem('Smart insights', 'Anomaly alerts and budget forecasts.', Icons.auto_awesome_rounded, const SmartInsightsPage()),
      _HubItem('Receipt scanner', 'Scan or import receipts with on-device OCR.', Icons.document_scanner_rounded, const ReceiptImportPage()),
      _HubItem('Export & encrypted backup', 'CSV/PDF export and protected backup/restore.', Icons.ios_share_rounded, const ExportBackupPage()),
      _HubItem('Needs review', 'Review low-confidence ML detections.', Icons.fact_check_rounded, const ReviewQueuePage()),
      _HubItem('ML feedback', 'See accepted, corrected and ignored classifications.', Icons.psychology_alt_rounded, const ModelFeedbackPage()),
      _HubItem('Net worth', 'Track assets, liabilities and selected account balances.', Icons.account_balance_wallet_rounded, const NetWorthPage()),
      _HubItem('Privacy & appearance', 'Biometric lock, secure screen and dark mode.', Icons.security_rounded, const PrivacyAppearancePage()),
      _HubItem('Home widget', 'Refresh the Android spending widget.', Icons.widgets_rounded, const HomeWidgetPage()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Finance Hub')),
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

class RecurringPaymentsPage extends StatelessWidget {
  const RecurringPaymentsPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Recurring payments')),
    body:FutureBuilder<List<Map<String,Object?>>>(future:AppDb.instance.detectRecurringPayments(),builder:(context,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final data=s.data!; if(data.isEmpty)return const _EmptyInfo(icon:Icons.autorenew,title:'No recurring pattern yet',text:'Recurring detection needs at least two similar payments with a weekly, monthly, quarterly or yearly pattern.');
      return ListView.builder(padding:const EdgeInsets.all(16),itemCount:data.length,itemBuilder:(context,i){final r=data[i];return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.repeat)),title:Text('${r['merchant']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${r['category']} • every ~${r['intervalDays']} days • ${r['occurrences']} occurrences\nNext expected: ${DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(r['nextDue'] as int))}'),trailing:Text(_money.format(r['averageAmount']),style:const TextStyle(fontWeight:FontWeight.w900))));});
    }),
  );
}

class AccountsPage extends StatefulWidget { const AccountsPage({super.key}); @override State<AccountsPage> createState()=>_AccountsPageState(); }
class _AccountsPageState extends State<AccountsPage>{
  Future<void> edit(Map<String,Object?> a) async{
    final n=TextEditingController(text:'${a['name']}'); final b=TextEditingController(text:'${a['current_balance']}'); bool include=(a['include_net_worth'] as int)==1;
    await showDialog(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('Account'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Account name')),const SizedBox(height:10),TextField(controller:b,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Current balance',prefixText:'₹ ')),SwitchListTile(contentPadding:EdgeInsets.zero,value:include,onChanged:(v)=>set(()=>include=v),title:const Text('Include in net worth'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{await AppDb.instance.updateAccount(a['id'] as int,name:n.text,balance:double.tryParse(b.text)??0,includeNetWorth:include);if(c.mounted)Navigator.pop(c);},child:const Text('Save'))]))); if(mounted)setState((){});
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Accounts')),body:FutureBuilder<List<Object>>(future:Future.wait<Object>([AppDb.instance.accounts(),AppDb.instance.spendByAccount()]),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final d=s.data![0] as List<Map<String,Object?>>;final stats=s.data![1] as Map<String,Map<String,double>>;if(d.isEmpty)return const _EmptyInfo(icon:Icons.account_balance,title:'No account hints found',text:'Account detection uses the SMS sender and last 3–4 account/card digits when banks include them.');return ListView.builder(padding:const EdgeInsets.all(16),itemCount:d.length,itemBuilder:(context,i){final a=d[i];final st=stats['${a['account_key']}']??const <String,double>{};return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.account_balance)),title:Text('${a['name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Detected: ${a['sender']} ••••${a['account_hint']}\nSpent ${_money.format(st['expense']??0)} • Income ${_money.format(st['income']??0)}'),isThreeLine:true,trailing:Text(_money.format(a['current_balance'])),onTap:()=>edit(a)));});}));
}

class MerchantAliasesPage extends StatefulWidget{const MerchantAliasesPage({super.key});@override State<MerchantAliasesPage> createState()=>_MerchantAliasesPageState();}
class _MerchantAliasesPageState extends State<MerchantAliasesPage>{
  Future<void> add()async{final p=TextEditingController(),n=TextEditingController();await showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('Merchant alias'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:p,decoration:const InputDecoration(labelText:'Text/pattern',hintText:'zomato@icici')),const SizedBox(height:10),TextField(controller:n,decoration:const InputDecoration(labelText:'Normalize to',hintText:'Zomato'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{if(p.text.trim().isNotEmpty&&n.text.trim().isNotEmpty){await AppDb.instance.saveMerchantAlias(p.text,n.text);if(c.mounted)Navigator.pop(c);}},child:const Text('Save'))]));if(mounted)setState((){});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Merchant normalization'),actions:[IconButton(onPressed:add,icon:const Icon(Icons.add))]),body:FutureBuilder<List<Map<String,Object?>>>(future:AppDb.instance.merchantAliases(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView.builder(padding:const EdgeInsets.all(16),itemCount:s.data!.length,itemBuilder:(context,i){final a=s.data![i];return Card(child:ListTile(title:Text('${a['normalized_name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Contains: ${a['pattern']}'),trailing:IconButton(onPressed:()async{await AppDb.instance.deleteMerchantAlias(a['id'] as int);setState((){});},icon:const Icon(Icons.delete_outline))));});}));
}

class AdvancedSearchPage extends StatefulWidget { const AdvancedSearchPage({super.key}); @override State<AdvancedSearchPage> createState()=>_AdvancedSearchPageState(); }
class _AdvancedSearchPageState extends State<AdvancedSearchPage>{
  final q=TextEditingController(),min=TextEditingController(),max=TextEditingController(),account=TextEditingController(); String type='all',category='',source=''; DateTime? from,to; List<TxRecord>? results;
  Future<void> search()async{results=await AppDb.instance.searchTransactions(query:q.text,type:type,category:category,source:source,account:account.text.trim(),minAmount:double.tryParse(min.text),maxAmount:double.tryParse(max.text),startMs:from?.millisecondsSinceEpoch,endMs:to==null?null:DateTime(to!.year,to!.month,to!.day+1).millisecondsSinceEpoch);if(mounted)setState((){});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Advanced search')),body:FutureBuilder<List<CategoryRecord>>(future:AppDb.instance.categories(),builder:(context,s){final cats=s.data??[];return Column(children:[Padding(padding:const EdgeInsets.all(14),child:Column(children:[TextField(controller:q,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Merchant, note, SMS text…'),onSubmitted:(_)=>search()),const SizedBox(height:8),Row(children:[Expanded(child:DropdownButtonFormField(value:type,items:['all','expense','income','investment','transfer','refund'].map((x)=>DropdownMenuItem(value:x,child:Text(x=='all'?'All types':_cap(x)))).toList(),onChanged:(v)=>setState(()=>type=v??'all'),decoration:const InputDecoration(labelText:'Type'))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField(value:category,items:[const DropdownMenuItem(value:'',child:Text('Any category')),...cats.map((c)=>DropdownMenuItem(value:c.name,child:Text(c.name,overflow:TextOverflow.ellipsis)))],onChanged:(v)=>setState(()=>category=v??''),decoration:const InputDecoration(labelText:'Category')))]),const SizedBox(height:8),Row(children:[Expanded(child:TextField(controller:min,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Min amount'))),const SizedBox(width:8),Expanded(child:TextField(controller:max,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Max amount'))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField(value:source,items:const [DropdownMenuItem(value:'',child:Text('Any source')),DropdownMenuItem(value:'sms',child:Text('SMS')),DropdownMenuItem(value:'phonepe_notification',child:Text('PhonePe')),DropdownMenuItem(value:'upi_intent',child:Text('UPI')),DropdownMenuItem(value:'manual',child:Text('Manual')),DropdownMenuItem(value:'receipt_ocr',child:Text('Receipt'))],onChanged:(v)=>setState(()=>source=v??''),decoration:const InputDecoration(labelText:'Source')))]),const SizedBox(height:8),TextField(controller:account,decoration:const InputDecoration(labelText:'Account hint / sender',prefixIcon:Icon(Icons.account_balance_outlined))),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:context,initialDate:from??DateTime.now(),firstDate:DateTime(2015),lastDate:DateTime.now());if(d!=null)setState(()=>from=d);},icon:const Icon(Icons.date_range),label:Text(from==null?'From date':DateFormat('dd MMM yy').format(from!)))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:context,initialDate:to??DateTime.now(),firstDate:DateTime(2015),lastDate:DateTime.now());if(d!=null)setState(()=>to=d);},icon:const Icon(Icons.event),label:Text(to==null?'To date':DateFormat('dd MMM yy').format(to!))))]),const SizedBox(height:10),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:search,icon:const Icon(Icons.manage_search),label:const Text('Search')))])),Expanded(child:results==null?const _EmptyInfo(icon:Icons.manage_search,title:'Search transactions',text:'Combine merchant text, amount, category, type and source filters.'):results!.isEmpty?const Center(child:Text('No matches')):ListView.builder(padding:const EdgeInsets.fromLTRB(14,0,14,100),itemCount:results!.length,itemBuilder:(context,i)=>_TxMiniTile(tx:results![i]))) ]); }));
}

class CashFlowPage extends StatelessWidget { const CashFlowPage({super.key}); @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Cash flow')),body:FutureBuilder<Map<String,double>>(future:AppDb.instance.cashFlowSummary(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final x=s.data!;return ListView(padding:const EdgeInsets.all(16),children:[_MetricCard('Net cash flow',_money.format(x['net']),Icons.account_balance_wallet_rounded),Row(children:[Expanded(child:_MetricCard('Income',_money.format(x['income']),Icons.south_west_rounded)),const SizedBox(width:10),Expanded(child:_MetricCard('Expense',_money.format(x['expense']),Icons.north_east_rounded))]),Row(children:[Expanded(child:_MetricCard('Daily average',_money.format(x['dailyAverage']),Icons.today_rounded)),const SizedBox(width:10),Expanded(child:_MetricCard('Projected month',_money.format(x['projectedExpense']),Icons.trending_up_rounded))]),_MetricCard('Savings rate','${(x['savingsRate']??0).toStringAsFixed(1)}%',Icons.savings_rounded)]); })); }

class SmartInsightsPage extends StatelessWidget { const SmartInsightsPage({super.key}); @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Smart insights')),body:FutureBuilder<List<Map<String,Object?>>>(future:AppDb.instance.smartInsights(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());if(s.data!.isEmpty)return const _EmptyInfo(icon:Icons.check_circle_outline,title:'Nothing unusual detected',text:'Insights will appear when spending deviates from your recent pattern or a budget is projected to exceed.');return ListView.builder(padding:const EdgeInsets.all(16),itemCount:s.data!.length,itemBuilder:(context,i){final x=s.data![i];return Card(child:ListTile(leading:CircleAvatar(child:Icon(x['kind']=='forecast'?Icons.speed:x['kind']=='recurring'?Icons.autorenew:Icons.insights)),title:Text('${x['title']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${x['message']}')));});})); }

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

class ReviewQueuePage extends StatefulWidget{const ReviewQueuePage({super.key});@override State<ReviewQueuePage> createState()=>_ReviewQueuePageState();}
class _ReviewQueuePageState extends State<ReviewQueuePage>{
  Future<void> act(TxRecord t,bool accept)async{if(t.id==null)return;if(accept)await AppDb.instance.acceptReview(t.id!);else await AppDb.instance.ignoreReview(t.id!);setState((){});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Needs review')),body:FutureBuilder<List<TxRecord>>(future:AppDb.instance.reviewTransactions(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());if(s.data!.isEmpty)return const _EmptyInfo(icon:Icons.task_alt,title:'Review queue is clear',text:'Low-confidence ML detections will appear here instead of being silently added or discarded.');return ListView.builder(padding:const EdgeInsets.all(16),itemCount:s.data!.length,itemBuilder:(context,i){final t=s.data![i];return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t.merchant,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),Text('${_money.format(t.amount)} • ${t.type} • ${(t.classificationConfidence*100).round()}% confidence'),if(t.rawMessage.isNotEmpty)...[const SizedBox(height:8),Text(t.rawMessage,maxLines:4,overflow:TextOverflow.ellipsis)],const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>act(t,false),child:const Text('Ignore'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>act(t,true),child:const Text('Accept')))])])));});}));
}

class ModelFeedbackPage extends StatelessWidget{const ModelFeedbackPage({super.key});@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('ML feedback')),body:FutureBuilder<Map<String,int>>(future:AppDb.instance.modelFeedbackStats(),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final x=s.data!;final auto=x['auto']??0, corrected=x['corrected']??0;final acceptance=auto==0?0.0:((auto-corrected)/auto*100).clamp(0,100).toDouble();return ListView(padding:const EdgeInsets.all(16),children:[_MetricCard('Estimated accepted without correction','${acceptance.toStringAsFixed(1)}%',Icons.psychology),_MetricCard('Auto-classified','$auto',Icons.auto_awesome),_MetricCard('User corrections','$corrected',Icons.edit_note),_MetricCard('Review accepted','${x['accepted']??0}',Icons.check_circle),_MetricCard('Review ignored','${x['ignored']??0}',Icons.block),_MetricCard('Pending review','${x['pending']??0}',Icons.pending_actions),const Padding(padding:EdgeInsets.all(8),child:Text('These are local product-quality signals, not a formal benchmark accuracy score.',style:TextStyle(fontSize:12))) ]); }));}

class NetWorthPage extends StatefulWidget{const NetWorthPage({super.key});@override State<NetWorthPage> createState()=>_NetWorthPageState();}
class _NetWorthPageState extends State<NetWorthPage>{
  Future<void> add([Map<String,Object?>? item])async{final n=TextEditingController(text:item?['name']?.toString()??'');final b=TextEditingController(text:item?['balance']?.toString()??'');String type=item?['item_type']?.toString()??'asset';final cat=TextEditingController(text:item?['category']?.toString()??'');await showDialog(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(item==null?'Add net-worth item':'Edit item'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Name')),const SizedBox(height:8),DropdownButtonFormField(value:type,items:const [DropdownMenuItem(value:'asset',child:Text('Asset')),DropdownMenuItem(value:'liability',child:Text('Liability'))],onChanged:(v)=>set(()=>type=v??type),decoration:const InputDecoration(labelText:'Type')),const SizedBox(height:8),TextField(controller:cat,decoration:const InputDecoration(labelText:'Category')),const SizedBox(height:8),TextField(controller:b,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Balance',prefixText:'₹ '))]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{await AppDb.instance.saveNetWorthItem(id: item == null ? null : item['id'] as int, name:n.text,itemType:type,category:cat.text,balance:double.tryParse(b.text)??0);if(c.mounted)Navigator.pop(c);},child:const Text('Save'))])));if(mounted)setState((){});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Net worth'),actions:[IconButton(onPressed:()=>add(),icon:const Icon(Icons.add))]),body:FutureBuilder<List<Object>>(future:Future.wait<Object>([AppDb.instance.netWorthSummary(),AppDb.instance.netWorthItems()]),builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final sum=s.data![0] as Map<String,double>;final items=s.data![1] as List<Map<String,Object?>>;return ListView(padding:const EdgeInsets.all(16),children:[_MetricCard('Net worth',_money.format(sum['netWorth']),Icons.account_balance_wallet),Row(children:[Expanded(child:_MetricCard('Assets',_money.format(sum['assets']),Icons.add_circle_outline)),const SizedBox(width:8),Expanded(child:_MetricCard('Liabilities',_money.format(sum['liabilities']),Icons.remove_circle_outline))]),const SizedBox(height:8),...items.map((x)=>Card(child:ListTile(title:Text('${x['name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${_cap('${x['item_type']}')} • ${x['category']}'),trailing:Text(_money.format(x['balance'])),onTap:()=>add(x),onLongPress:()async{await AppDb.instance.deleteNetWorthItem(x['id'] as int);setState((){});}))) ]); }));}

class PrivacyAppearancePage extends StatefulWidget{const PrivacyAppearancePage({super.key});@override State<PrivacyAppearancePage> createState()=>_PrivacyAppearancePageState();}
class _PrivacyAppearancePageState extends State<PrivacyAppearancePage>{bool loading=true,lock=false,secure=true,dark=false;@override void initState(){super.initState();load();}Future<void>load()async{lock=await AppDb.instance.getBoolSetting('privacy_lock_enabled');secure=await AppDb.instance.getBoolSetting('secure_screen_enabled',fallback:true);dark=await AppDb.instance.getBoolSetting('dark_mode');if(mounted)setState(()=>loading=false);}Future<void>setv(String k,bool v)async{await AppDb.instance.setSetting(k,v?'1':'0');if(k=='dark_mode')expenseThemeMode.value=v?ThemeMode.dark:ThemeMode.light;if(k=='secure_screen_enabled')await NativeBridge.setSecureScreen(v);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Privacy & appearance')),body:loading?const Center(child:CircularProgressIndicator()):ListView(children:[SwitchListTile(value:lock,onChanged:(v){setState(()=>lock=v);setv('privacy_lock_enabled',v);},secondary:const Icon(Icons.fingerprint),title:const Text('Biometric/device lock'),subtitle:const Text('Require local authentication when opening the app.')),SwitchListTile(value:secure,onChanged:(v){setState(()=>secure=v);setv('secure_screen_enabled',v);},secondary:const Icon(Icons.visibility_off),title:const Text('Hide recent-app preview'),subtitle:const Text('Uses Android FLAG_SECURE to protect sensitive amounts and screens.')),SwitchListTile(value:dark,onChanged:(v){setState(()=>dark=v);setv('dark_mode',v);},secondary:const Icon(Icons.dark_mode),title:const Text('Dark mode')),const ListTile(leading:Icon(Icons.cloud_off),title:Text('Local-first privacy'),subtitle:Text('SMS, notification text, receipts, ML decisions and backups stay on device unless you explicitly share/export them.'))]));}

class HomeWidgetPage extends StatefulWidget{const HomeWidgetPage({super.key});@override State<HomeWidgetPage> createState()=>_HomeWidgetPageState();}
class _HomeWidgetPageState extends State<HomeWidgetPage>{String status='';Future<void>refresh()async{try{await NativeBridge.updateHomeWidget();setState(()=>status='Widget refreshed. Add “Expense Tracker” from your Android home-screen widget picker if it is not already placed.');}catch(e){setState(()=>status='Could not refresh widget: $e');}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Home widget')),body:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Icon(Icons.widgets_rounded,size:64),const SizedBox(height:16),const Text('Monthly spending widget',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),const SizedBox(height:8),const Text('Shows current-month expense and remaining overall budget without opening the app.',textAlign:TextAlign.center),const SizedBox(height:24),FilledButton.icon(onPressed:refresh,icon:const Icon(Icons.refresh),label:const Text('Refresh widget')),if(status.isNotEmpty)...[const SizedBox(height:16),Text(status,textAlign:TextAlign.center)] ])));}

class SplitTransactionPage extends StatefulWidget{
  final TxRecord transaction;
  const SplitTransactionPage({super.key,required this.transaction});
  @override State<SplitTransactionPage> createState()=>_SplitTransactionPageState();
}
class _SplitTransactionPageState extends State<SplitTransactionPage>{final rows=<Map<String,dynamic>>[];List<CategoryRecord>cats=[];@override void initState(){super.initState();load();}Future<void>load()async{cats=await AppDb.instance.expenseCategories();final existing=await AppDb.instance.splitsFor(widget.transaction.id!);if(existing.isNotEmpty)rows.addAll(existing.map((e)=>{'category':e['category'],'amount':(e['amount']as num).toDouble(),'note':e['note']??''}));else rows.add({'category':widget.transaction.category,'amount':widget.transaction.amount,'note':''});if(mounted)setState((){});}double get total=>rows.fold(0,(a,b)=>a+(b['amount']as double));Future<void>save()async{if((total-widget.transaction.amount).abs()>0.01){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Split amounts must equal the transaction amount.')));return;}await AppDb.instance.setSplits(widget.transaction.id!,rows.map((x)=><String,Object?>{'category':x['category'],'amount':x['amount'],'note':x['note']}).toList());if(mounted)Navigator.pop(context,true);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Split transaction')),body:ListView(padding:const EdgeInsets.all(16),children:[Text('${widget.transaction.merchant} • ${_money.format(widget.transaction.amount)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:12),...rows.asMap().entries.map((e){final i=e.key,r=e.value;return Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:DropdownButtonFormField(value:r['category'] as String,items:cats.map((c)=>DropdownMenuItem(value:c.name,child:Text(c.name))).toList(),onChanged:(v)=>setState(()=>r['category']=v),decoration:const InputDecoration(labelText:'Category'))),const SizedBox(width:8),SizedBox(width:110,child:TextFormField(initialValue:(r['amount']as double).toStringAsFixed(2),keyboardType:TextInputType.number,onChanged:(v)=>r['amount']=double.tryParse(v)??0,decoration:const InputDecoration(labelText:'Amount'))),IconButton(onPressed:rows.length<=1?null:()=>setState(()=>rows.removeAt(i)),icon:const Icon(Icons.close))])));}),OutlinedButton.icon(onPressed:()=>setState(()=>rows.add({'category':cats.isEmpty?'Uncategorized':cats.first.name,'amount':0.0,'note':''})),icon:const Icon(Icons.add),label:const Text('Add split')),const SizedBox(height:8),Text('Split total: ${_money.format(total)} / ${_money.format(widget.transaction.amount)}',style:TextStyle(fontWeight:FontWeight.w800,color:(total-widget.transaction.amount).abs()<=0.01?Colors.green:Colors.red)),const SizedBox(height:12),FilledButton(onPressed:save,child:const Text('Save split'))]));}

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

class _MetricCard extends StatelessWidget{final String label,value;final IconData icon;const _MetricCard(this.label,this.value,this.icon);@override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[CircleAvatar(child:Icon(icon)),const SizedBox(width:12),Expanded(child:Text(label,style:const TextStyle(fontWeight:FontWeight.w700))),Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))])));}
class _ToolTile extends StatelessWidget{final IconData icon;final String title,subtitle;final VoidCallback onTap;const _ToolTile({required this.icon,required this.title,required this.subtitle,required this.onTap});@override Widget build(BuildContext context)=>Card(child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right),onTap:onTap));}
class _EmptyInfo extends StatelessWidget{final IconData icon;final String title,text;const _EmptyInfo({required this.icon,required this.title,required this.text});@override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:54,color:Theme.of(context).colorScheme.primary),const SizedBox(height:14),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:7),Text(text,textAlign:TextAlign.center,style:const TextStyle(height:1.4))])));}
String _cap(String x)=>x.isEmpty?x:x[0].toUpperCase()+x.substring(1);

extension _StringTake on String { String take(int n)=>length<=n?this:substring(0,n); }
