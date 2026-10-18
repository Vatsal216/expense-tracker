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
  AiProvider _provider = AiProvider.gemini;
  late final TextEditingController _model = TextEditingController(text: _provider.defaultModel);
  final _key = TextEditingController();
  final _question = TextEditingController();
  bool _loadingKey = true;
  bool _asking = false;
  bool _showKey = false;
  String? _answer;

  @override
  void initState() { super.initState(); _restore(); }

  Future<void> _restore() async {
    final name = await AppDb.instance.getSetting('ai_agent_provider', fallback: AiProvider.gemini.name);
    final matches = AiProvider.values.where((item) => item.name == name);
    final provider = matches.isEmpty ? AiProvider.gemini : matches.first;
    final model = await AppDb.instance.getSetting('ai_agent_model', fallback: provider.defaultModel);
    final savedKey = await FinanceApiKeyVault.read(provider);
    if (!mounted) return;
    setState(() { _provider = provider; _model.text = model; _key.text = savedKey ?? ''; _loadingKey = false; });
  }

  Future<void> _changeProvider(AiProvider provider) async {
    final savedKey = await FinanceApiKeyVault.read(provider);
    setState(() { _provider = provider; _model.text = provider.defaultModel; _key.text = savedKey ?? ''; });
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty || _model.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both an API key and model name.')));
      return;
    }
    await FinanceApiKeyVault.save(_provider, _key.text);
    await AppDb.instance.setSetting('ai_agent_provider', _provider.name);
    await AppDb.instance.setSetting('ai_agent_model', _model.text.trim());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved securely on this device.')));
  }

  Future<void> _ask() async {
    if (_question.text.trim().isEmpty) return;
    await _save();
    if (_key.text.trim().isEmpty || _model.text.trim().isEmpty) return;
    setState(() { _asking = true; _answer = null; });
    try {
      final answer = await FinanceAgent().ask(
        config: AiAgentConfig(provider: _provider, model: _model.text.trim()),
        apiKey: _key.text.trim(),
        question: _question.text,
      );
      if (mounted) setState(() => _answer = answer);
    } catch (error) {
      if (mounted) setState(() => _answer = 'Could not get an answer: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  void dispose() { _model.dispose(); _key.dispose(); _question.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI Advisor')),
        body: _loadingKey
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                children: [
                  FintechSurface(
                    child: const Row(children: [
                      CircleAvatar(child: Icon(Icons.auto_awesome_rounded)), SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Your private finance context', style: TextStyle(fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('The selected provider receives only your approved transaction summary, budgets and category totals. Raw SMS, UPI references and account hints are never sent.'),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  const Text('Provider', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AiProvider>(
                    value: _provider,
                    items: AiProvider.values.map((provider) => DropdownMenuItem(value: provider, child: Text(provider.label))).toList(),
                    onChanged: (value) { if (value != null) _changeProvider(value); },
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model name', prefixIcon: Icon(Icons.memory_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: _key, obscureText: !_showKey, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: '${_provider.label} API key', prefixIcon: const Icon(Icons.key_rounded), suffixIcon: IconButton(icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded), onPressed: () => setState(() => _showKey = !_showKey)))),
                  const SizedBox(height: 10),
                  Text('Your key is stored with Android secure storage and is used only for requests you send.', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(onPressed: _save, icon: const Icon(Icons.lock_outline_rounded), label: const Text('Save provider setup')),
                  const SizedBox(height: 24),
                  const Text('Ask about your money', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  TextField(controller: _question, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Example: What changed in my spending this month?')),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _asking ? null : _ask, icon: _asking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded), label: Text(_asking ? 'Analysing…' : 'Ask AI Advisor')),
                  if (_answer != null) ...[
                    const SizedBox(height: 18),
                    FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Advisor response', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 10), SelectableText(_answer!, style: const TextStyle(height: 1.45))])),
                  ],
                ],
              ),
      );
}
