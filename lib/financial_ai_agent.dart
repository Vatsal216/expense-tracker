import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import 'app_db.dart';
import 'fintech_design.dart';
import 'models.dart';

enum AiProvider { gemini, openai, claude, deepseek }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.gemini => 'Gemini',
        AiProvider.openai => 'OpenAI',
        AiProvider.claude => 'Claude',
        AiProvider.deepseek => 'DeepSeek',
      };

  String get defaultModel => switch (this) {
        AiProvider.gemini => 'gemini-2.0-flash',
        AiProvider.openai => 'gpt-4.1-mini',
        AiProvider.claude => 'claude-3-5-haiku-latest',
        AiProvider.deepseek => 'deepseek-chat',
      };
}

class AiAgentConfig {
  final AiProvider provider;
  final String model;

  const AiAgentConfig({required this.provider, required this.model});
}

class FinanceApiKeyVault {
  static const _storage = FlutterSecureStorage();

  static String _key(AiProvider provider) => 'finance_agent_key_${provider.name}';

  static Future<void> save(AiProvider provider, String key) =>
      _storage.write(key: _key(provider), value: key.trim());

  static Future<String?> read(AiProvider provider) => _storage.read(key: _key(provider));

  static Future<void> remove(AiProvider provider) => _storage.delete(key: _key(provider));
}

class FinanceAgent {
  Future<String> ask({required AiAgentConfig config, required String apiKey, required String question}) async {
    final context = await _financeContext();
    const system = '''You are an in-app finance advisor. Use only the supplied local summary and say when data is missing. Be concise, practical, and supportive. Do not invent numbers. Do not give personalised securities buy/sell recommendations, tax/legal advice, or instructions to take loans. You may explain spending patterns, budgeting options, cash-flow risks, and questions the user can ask a qualified professional. The summary never includes raw SMS, sender, UPI reference, account hint, or notes.''';
    final prompt = '$system\n\nLOCAL FINANCE SUMMARY (user approved):\n${jsonEncode(context)}\n\nUSER QUESTION:\n${question.trim()}';
    return switch (config.provider) {
      AiProvider.openai => _openAi(config.model, apiKey, prompt),
      AiProvider.deepseek => _deepSeek(config.model, apiKey, prompt),
      AiProvider.gemini => _gemini(config.model, apiKey, system, question.trim(), context),
      AiProvider.claude => _claude(config.model, apiKey, system, question.trim(), context),
    };
  }

  Future<Map<String, Object?>> _financeContext() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, now.day).millisecondsSinceEpoch;
    final end = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final results = await Future.wait<Object>([
      AppDb.instance.transactions(limit: 100),
      AppDb.instance.cashFlowSummary(),
      AppDb.instance.expenseByCategoryForPeriod(start, end),
      AppDb.instance.overallBudget(),
    ]);
    final records = results[0] as List<TxRecord>;
    final cashFlow = results[1] as Map<String, double>;
    final categories = results[2] as Map<String, double>;
    final formatter = DateFormat('yyyy-MM-dd');
    return {
      'period': 'Last 90 days through ${formatter.format(now)}',
      'monthly_cash_flow': cashFlow,
      'monthly_budget': results[3],
      'expense_by_category': categories,
      'recent_transactions': records.map((tx) => {
            'date': formatter.format(DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)),
            'amount': tx.amount,
            'type': tx.type,
            'category': tx.category,
            'merchant': tx.normalizedMerchant.trim().isEmpty ? tx.merchant : tx.normalizedMerchant,
          }).toList(),
      'privacy': 'No raw SMS, sender, UPI reference, account hint, or transaction note is included.',
    };
  }

  Future<String> _openAi(String model, String key, String prompt) async => _requestText(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        {'Authorization': 'Bearer $key'},
        {'model': model, 'messages': [{'role': 'user', 'content': prompt}], 'temperature': 0.35},
        (json) => json['choices']?[0]?['message']?['content']?.toString(),
      );

  Future<String> _deepSeek(String model, String key, String prompt) async => _requestText(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        {'Authorization': 'Bearer $key'},
        {'model': model, 'messages': [{'role': 'user', 'content': prompt}], 'temperature': 0.35},
        (json) => json['choices']?[0]?['message']?['content']?.toString(),
      );

  Future<String> _gemini(String model, String key, String system, String question, Map<String, Object?> context) async => _requestText(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${Uri.encodeQueryComponent(key)}'),
        const {},
        {
          'systemInstruction': {'parts': [{'text': system}]},
          'contents': [{'role': 'user', 'parts': [{'text': 'LOCAL FINANCE SUMMARY:\n${jsonEncode(context)}\n\nUSER QUESTION:\n$question'}]}],
          'generationConfig': {'temperature': 0.35},
        },
        (json) => json['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString(),
      );

  Future<String> _claude(String model, String key, String system, String question, Map<String, Object?> context) async => _requestText(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        {'x-api-key': key, 'anthropic-version': '2023-06-01'},
        {'model': model, 'max_tokens': 700, 'system': system, 'messages': [{'role': 'user', 'content': 'LOCAL FINANCE SUMMARY:\n${jsonEncode(context)}\n\nUSER QUESTION:\n$question'}]},
        (json) => json['content']?[0]?['text']?.toString(),
      );

  Future<String> _requestText(Uri uri, Map<String, String> headers, Object body, String? Function(Map<String, dynamic>) pick) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 25));
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final raw = await utf8.decoder.bind(response).join();
      final json = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = json['error'] is Map ? (json['error']['message'] ?? json['error']['type']) : json['error'];
        throw Exception(detail?.toString().isNotEmpty == true ? detail : 'Provider returned ${response.statusCode}.');
      }
      final text = pick(json)?.trim();
      if (text == null || text.isEmpty) throw Exception('The provider returned no usable answer.');
      return text;
    } on SocketException {
      throw Exception('No internet connection. Your data stays on this device until you send a question.');
    } finally {
      client.close(force: true);
    }
  }
}

class AiAdvisorPage extends StatefulWidget {
  const AiAdvisorPage({super.key});

  @override
  State<AiAdvisorPage> createState() => _AiAdvisorPageState();
}

class _AiAdvisorPageState extends State<AiAdvisorPage> {
  final _question = TextEditingController();
  bool _asking = false;
  bool _loading = true;
  List<Map<String, Object?>> _messages = const [];
  List<double> _trend = const [];
  Map<String, double> _categories = const {};
  List<TxRecord> _weekUpi = const [];
  double _spent = 0;
  double _income = 0;
  double _budget = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5, 1).millisecondsSinceEpoch;
    final end = DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch;
    final data = await Future.wait<dynamic>([
      AppDb.instance.aiChatHistory(),
      AppDb.instance.totalsByTypeForPeriod(start, end),
      AppDb.instance.expenseByCategoryForPeriod(start, end),
      AppDb.instance.expenseTrendForPeriod(start, end, buckets: 6),
      AppDb.instance.overallBudget(),
      AppDb.instance.transactions(limit: 400),
    ]);
    if (!mounted) return;
    final totals = data[1] as Map<String, double>;
    final today = DateTime.now();
    final weekStart = DateTime(today.year, today.month, today.day).subtract(Duration(days: today.weekday - 1));
    final records = data[5] as List<TxRecord>;
    setState(() { _messages = data[0] as List<Map<String, Object?>>; _spent = totals['expense'] ?? 0; _income = totals['income'] ?? 0; _categories = data[2] as Map<String, double>; _trend = data[3] as List<double>; _budget = data[4] as double; _weekUpi = records.where((tx) => tx.type == 'expense' && tx.occurredAt >= weekStart.millisecondsSinceEpoch && tx.paymentMethod.toLowerCase().contains('upi')).toList(); _loading = false; });
  }

  Future<void> _ask() async {
    final question = _question.text.trim();
    if (question.isEmpty || _asking) return;
    final providerName = await AppDb.instance.getSetting('ai_agent_provider', fallback: AiProvider.gemini.name);
    final providers = AiProvider.values.where((item) => item.name == providerName).toList();
    final provider = providers.isEmpty ? AiProvider.gemini : providers.first;
    final model = await AppDb.instance.getSetting('ai_agent_model', fallback: provider.defaultModel);
    final key = await FinanceApiKeyVault.read(provider);
    if (key == null || key.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set up your AI provider in Settings first.')));
      return;
    }
    await AppDb.instance.addAiChatMessage(role: 'user', content: question);
    _question.clear();
    if (mounted) setState(() { _messages = [..._messages, {'role': 'user', 'content': question, 'created_at': DateTime.now().millisecondsSinceEpoch}]; _asking = true; });
    try {
      final answer = await FinanceAgent().ask(
        config: AiAgentConfig(provider: provider, model: model),
        apiKey: key,
        question: question,
      );
      await AppDb.instance.addAiChatMessage(role: 'assistant', content: answer);
      if (mounted) setState(() => _messages = [..._messages, {'role': 'assistant', 'content': answer, 'created_at': DateTime.now().millisecondsSinceEpoch}]);
    } catch (error) {
      final answer = 'Could not get an answer: ${error.toString().replaceFirst('Exception: ', '')}';
      await AppDb.instance.addAiChatMessage(role: 'assistant', content: answer);
      if (mounted) setState(() => _messages = [..._messages, {'role': 'assistant', 'content': answer, 'created_at': DateTime.now().millisecondsSinceEpoch}]);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _clearHistory() async {
    await AppDb.instance.clearAiChatHistory();
    if (mounted) setState(() => _messages = const []);
  }

  @override
  void dispose() { _question.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('AI Advisor'), Text('Ask about your money', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))]), actions: [IconButton(onPressed: _messages.isEmpty ? null : _clearHistory, tooltip: 'Clear chat', icon: const Icon(Icons.history_rounded))]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      children: [
                        if (_messages.isEmpty) const _AdvisorWelcome(),
                        for (var index = 0; index < _messages.length; index++) ...[
                          _AdvisorBubble(role: '${_messages[index]['role']}', content: '${_messages[index]['content']}'),
                          if ('${_messages[index]['role']}' == 'assistant')
                            _AdvisorVisualForQuery(query: _questionBefore(index), spent: _spent, income: _income, budget: _budget, categories: _categories, trend: _trend, upi: _weekUpi),
                        ],
                        if (_asking) const _AdvisorBubble(role: 'assistant', content: 'Thinking…', loading: true),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline))),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Row(children: [
                        IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline_rounded)),
                        Expanded(child: TextField(controller: _question, textCapitalization: TextCapitalization.sentences, minLines: 1, maxLines: 4, onSubmitted: (_) => _ask(), decoration: const InputDecoration(hintText: 'Ask about spending, cards or budgets', prefixIcon: Icon(Icons.auto_awesome_rounded)))),
                        const SizedBox(width: 8),
                        IconButton.filled(onPressed: _asking ? null : _ask, icon: const Icon(Icons.arrow_upward_rounded)),
                      ]),
                    ),
                  ),
                ],
              ),
      );

  String _questionBefore(int index) { for (var i = index - 1; i >= 0; i--) { if ('${_messages[i]['role']}' == 'user') return '${_messages[i]['content']}'; } return ''; }
}

/* Legacy compact UI implementation retained as a comment during migration.
class _AdvisorWelcome extends StatelessWidget { const _AdvisorWelcome(); @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(8, 30, 8, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [CircleAvatar(backgroundColor: FintechDesign.pale, child: Icon(Icons.auto_awesome_rounded, color: FintechDesign.mint)), const SizedBox(width: 10), const Expanded(child: Text('Your private financial advisor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))]), const SizedBox(height: 8), const Text('Ask a question and get a live answer with the relevant money view.'), const SizedBox(height: 18), Wrap(spacing: 8, runSpacing: 8, children: const [Chip(label: Text('UPI spending this week')), Chip(label: Text('Where did I spend most?')), Chip(label: Text('How is my budget?'))]) ])); }
class _AdvisorBubble extends StatelessWidget { final String role; final String content; final bool loading; const _AdvisorBubble({required this.role, required this.content, this.loading = false}); @override Widget build(BuildContext context) { final user = role == 'user'; final bubble = Container(constraints: const BoxConstraints(maxWidth: 330), margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), decoration: BoxDecoration(color: user ? const Color(0xFFD6F4E5) : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(22), topRight: const Radius.circular(22), bottomLeft: Radius.circular(user ? 22 : 6), bottomRight: Radius.circular(user ? 6 : 22)), border: Border.all(color: const Color(0xFFDDE7E8))), child: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : SelectableText(content, style: const TextStyle(color: FintechDesign.ink, height: 1.4, fontSize: 16))); return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: [if (!user) ...[CircleAvatar(radius: 18, backgroundColor: FintechDesign.pale, child: Icon(Icons.smart_toy_outlined, color: FintechDesign.mint, size: 20)), const SizedBox(width: 8)], bubble])); }}

class _AdvisorVisualForQuery extends StatelessWidget { final String query; final double spent; final double income; final double budget; final Map<String, double> categories; final List<double> trend; final List<TxRecord> upi; const _AdvisorVisualForQuery({required this.query, required this.spent, required this.income, required this.budget, required this.categories, required this.trend, required this.upi}); @override Widget build(BuildContext context) { final q = query.toLowerCase(); final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0); final entries = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value)); final upiMode = q.contains('upi'); final categoryMode = q.contains('category') || q.contains('where') || q.contains('merchant'); final budgetMode = q.contains('budget') || q.contains('limit'); final cashMode = q.contains('income') || q.contains('cash') || q.contains('balance') || q.contains('save'); if (upiMode) return _UpiInsightCard(transactions: upi); if (budgetMode) { final used = budget <= 0 ? 0.0 : (spent / 6 / budget).clamp(0.0, 1.0).toDouble(); return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Budget progress', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(budget > 0 ? '${currency.format(spent / 6)} average monthly spend of ${currency.format(budget)} budget' : 'No monthly budget has been set yet.'), if (budget > 0) ...[const SizedBox(height: 10), LinearProgressIndicator(value: used, minHeight: 9, borderRadius: BorderRadius.circular(9)), const SizedBox(height: 5), Text('${(used * 100).round()}% of monthly budget used on average')]])); } if (cashMode) return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Cash-flow view · last 6 months', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 12), Row(children: [Expanded(child: _VisualMetric(label: 'Income', value: currency.format(income), color: const Color(0xFF087A57))), Expanded(child: _VisualMetric(label: 'Expenses', value: currency.format(spent), color: const Color(0xFFCF5151))), Expanded(child: _VisualMetric(label: 'Net', value: currency.format(income - spent), color: const Color(0xFF243743)))]))); if (categoryMode) return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Category breakdown · last 6 months', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 8), if (entries.isEmpty) const Text('No expense data yet.') else ...entries.take(4).map((e) => Padding(padding: const EdgeInsets.only(top: 9), child: Row(children: [Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)), Text(currency.format(e.value), style: const TextStyle(fontWeight: FontWeight.w800))])))])); final maximum = trend.fold<double>(0, (a, b) => a > b ? a : b); final now = DateTime.now(); return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Spending trend · last 6 months', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 12), SizedBox(height: 96, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(6, (i) { final value = i < trend.length ? trend[i] : 0; return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text(value == 0 ? '' : '${(value / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 9)), Container(height: maximum == 0 ? 5 : 8 + 45 * value / maximum, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: const Color(0xFF0E9365), borderRadius: BorderRadius.circular(6))), const SizedBox(height: 5), Text(DateFormat.MMM().format(DateTime(now.year, now.month - 5 + i)), style: const TextStyle(fontSize: 9))])); })))])); }}

class _UpiInsightCard extends StatelessWidget { final List<TxRecord> transactions; const _UpiInsightCard({required this.transactions}); @override Widget build(BuildContext context) { final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0); final days = List<double>.filled(7, 0); for (final tx in transactions) { final day = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt).weekday - 1; days[day] += tx.amount; } final total = days.fold<double>(0, (a, b) => a + b); final top = transactions.isEmpty ? '' : (transactions.toList()..sort((a,b) => b.amount.compareTo(a.amount))).first.category; final maximum = days.fold<double>(0, (a,b) => a > b ? a : b); const labels = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']; return Padding(padding: const EdgeInsets.only(left: 44, bottom: 14), child: FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('UPI spending · This week', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text(money.format(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 31)), const SizedBox(height: 14), SizedBox(height: 110, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(7, (i) => Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Container(height: maximum == 0 ? 5 : 8 + 60 * days[i] / maximum, width: 18, decoration: BoxDecoration(color: FintechDesign.mint, borderRadius: BorderRadius.circular(9))), const SizedBox(height: 7), Text(labels[i], style: const TextStyle(fontSize: 10))])))), const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [Chip(avatar: const Icon(Icons.payments_outlined, size: 17), label: Text('${transactions.length} payments')), if (top.isNotEmpty) Chip(avatar: const Icon(Icons.restaurant_outlined, size: 17), label: Text('Top: $top'))]) ])); }}
class _VisualMetric extends StatelessWidget { final String label; final String value; final Color color; const _VisualMetric({required this.label, required this.value, required this.color}); @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color))]); }

*/

class _AdvisorWelcome extends StatelessWidget {
  const _AdvisorWelcome();
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(8, 30, 8, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [CircleAvatar(backgroundColor: FintechDesign.pale, child: const Icon(Icons.auto_awesome_rounded, color: FintechDesign.mint)), const SizedBox(width: 10), const Expanded(child: Text('Your private financial advisor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))]),
    const SizedBox(height: 8), const Text('Ask a question and get a live answer with the relevant money view.'),
    const SizedBox(height: 18), Wrap(spacing: 8, runSpacing: 8, children: const [Chip(label: Text('UPI spending this week')), Chip(label: Text('Where did I spend most?')), Chip(label: Text('How is my budget?'))]),
  ]));
}

class _AdvisorBubble extends StatelessWidget {
  final String role, content;
  final bool loading;
  const _AdvisorBubble({required this.role, required this.content, this.loading = false});
  @override
  Widget build(BuildContext context) {
    final user = role == 'user';
    final bubble = Container(constraints: const BoxConstraints(maxWidth: 330), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), decoration: BoxDecoration(color: user ? const Color(0xFFD6F4E5) : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFDDE7E8))), child: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : SelectableText(content, style: const TextStyle(color: FintechDesign.ink, height: 1.4, fontSize: 16)));
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: [if (!user) ...[CircleAvatar(radius: 18, backgroundColor: FintechDesign.pale, child: const Icon(Icons.smart_toy_outlined, color: FintechDesign.mint, size: 20)), const SizedBox(width: 8)], bubble]));
  }
}

class _AdvisorVisualForQuery extends StatelessWidget {
  final String query;
  final double spent, income, budget;
  final Map<String, double> categories;
  final List<double> trend;
  final List<TxRecord> upi;
  const _AdvisorVisualForQuery({super.key, required this.query, required this.spent, required this.income, required this.budget, required this.categories, required this.trend, required this.upi});

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    if (q.contains('upi')) return _UpiInsightCard(transactions: upi);
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    if (q.contains('budget') || q.contains('limit')) {
      final ratio = budget <= 0 ? 0.0 : (spent / 6 / budget).clamp(0.0, 1.0).toDouble();
      return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Budget progress', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(budget <= 0 ? 'No monthly budget has been set yet.' : '${money.format(spent / 6)} average monthly spend of ${money.format(budget)} budget'),
        if (budget > 0) ...[const SizedBox(height: 10), LinearProgressIndicator(value: ratio, minHeight: 9, borderRadius: BorderRadius.circular(9)), const SizedBox(height: 5), Text('${(ratio * 100).round()}% of monthly budget used on average')],
      ]));
    }
    final maximum = trend.fold<double>(0, (a, b) => a > b ? a : b);
    final now = DateTime.now();
    return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Spending trend · last 6 months', style: TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      SizedBox(height: 96, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(6, (i) {
        final value = i < trend.length ? trend[i] : 0.0;
        return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text(value == 0 ? '' : '${(value / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 9)),
          Container(height: maximum == 0 ? 5 : 8 + 45 * value / maximum, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: FintechDesign.mint, borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 5), Text(DateFormat.MMM().format(DateTime(now.year, now.month - 5 + i)), style: const TextStyle(fontSize: 9)),
        ]));
      }))),
    ]));
  }
}

class _UpiInsightCard extends StatelessWidget {
  final List<TxRecord> transactions;
  const _UpiInsightCard({required this.transactions});
  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final days = List<double>.filled(7, 0);
    for (final tx in transactions) { days[DateTime.fromMillisecondsSinceEpoch(tx.occurredAt).weekday - 1] += tx.amount; }
    final total = days.fold<double>(0, (a, b) => a + b);
    final maximum = days.fold<double>(0, (a, b) => a > b ? a : b);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(padding: const EdgeInsets.only(left: 44, bottom: 14), child: FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('UPI spending · This week', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      Text(money.format(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 31)),
      const SizedBox(height: 14),
      SizedBox(height: 110, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(7, (i) => Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(height: maximum == 0 ? 5 : 8 + 60 * days[i] / maximum, width: 18, decoration: BoxDecoration(color: FintechDesign.mint, borderRadius: BorderRadius.circular(9))),
        const SizedBox(height: 7), Text(labels[i], style: const TextStyle(fontSize: 10)),
      ]))))),
      const SizedBox(height: 14),
      Chip(avatar: const Icon(Icons.payments_outlined, size: 17), label: Text('${transactions.length} payments')),
    ])));
  }
}

class AiAdvisorSettingsPage extends StatefulWidget { const AiAdvisorSettingsPage({super.key}); @override State<AiAdvisorSettingsPage> createState() => _AiAdvisorSettingsPageState(); }
class _AiAdvisorSettingsPageState extends State<AiAdvisorSettingsPage> { AiProvider _provider = AiProvider.gemini; late final TextEditingController _model = TextEditingController(); final _key = TextEditingController(); bool _showKey = false; bool _loading = true; @override void initState() { super.initState(); _restore(); } Future<void> _restore() async { final name = await AppDb.instance.getSetting('ai_agent_provider', fallback: AiProvider.gemini.name); final providers = AiProvider.values.where((v) => v.name == name).toList(); _provider = providers.isEmpty ? AiProvider.gemini : providers.first; _model.text = await AppDb.instance.getSetting('ai_agent_model', fallback: _provider.defaultModel); _key.text = await FinanceApiKeyVault.read(_provider) ?? ''; if (mounted) setState(() => _loading = false); } Future<void> _save() async { if (_key.text.trim().isEmpty || _model.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an API key and model name.'))); return; } await FinanceApiKeyVault.save(_provider, _key.text); await AppDb.instance.setSetting('ai_agent_provider', _provider.name); await AppDb.instance.setSetting('ai_agent_model', _model.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI provider saved securely on this device.'))); } @override void dispose() { _model.dispose(); _key.dispose(); super.dispose(); } @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('AI Advisor setup')), body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(18), children: [const Text('Choose your own provider and API key. The key stays in Android secure storage.'), const SizedBox(height: 16), DropdownButtonFormField<AiProvider>(value: _provider, decoration: const InputDecoration(labelText: 'Provider'), items: AiProvider.values.map((v) => DropdownMenuItem(value: v, child: Text(v.label))).toList(), onChanged: (v) async { if (v == null) return; final key = await FinanceApiKeyVault.read(v); setState(() { _provider = v; _model.text = v.defaultModel; _key.text = key ?? ''; }); }), const SizedBox(height: 12), TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model name')), const SizedBox(height: 12), TextField(controller: _key, obscureText: !_showKey, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: '${_provider.label} API key', suffixIcon: IconButton(onPressed: () => setState(() => _showKey = !_showKey), icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded)))), const SizedBox(height: 16), FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save AI setup')), const SizedBox(height: 20), const Text('Only a user-approved local finance summary is sent when you ask a question. Raw SMS, UPI references, account hints and notes are excluded.', style: TextStyle(height: 1.4))])); }
