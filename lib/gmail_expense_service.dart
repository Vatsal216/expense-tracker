import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import 'app_db.dart';
import 'native_bridge.dart';

class GmailSyncResult {
  final int scanned;
  final int imported;
  final int ignored;
  const GmailSyncResult({required this.scanned, required this.imported, required this.ignored});
}

/// Gmail is deliberately opt-in. The app uses Google's OAuth consent flow and
/// receives read-only access; it never asks for or stores an email password.
class GmailExpenseService {
  static const _scope = 'https://www.googleapis.com/auth/gmail.readonly';

  Future<GmailSyncResult> connectAndSync({bool interactive = true}) async {
    final serverClientId = await AppDb.instance.getSetting('gmail_server_client_id');
    final signIn = GoogleSignIn(
      scopes: const [_scope],
      serverClientId: serverClientId.trim().isEmpty ? null : serverClientId.trim(),
    );
    GoogleSignInAccount? account = await signIn.signInSilently();
    account ??= interactive ? await signIn.signIn() : null;
    if (account == null) throw Exception('Gmail connection was cancelled.');
    final headers = await account.authHeaders;
    await AppDb.instance.setSetting('gmail_connected_email', account.email);
    await AppDb.instance.setSetting('gmail_sync_enabled', '1');
    return _sync(headers);
  }

  Future<GmailSyncResult> syncSilently() async {
    final serverClientId = await AppDb.instance.getSetting('gmail_server_client_id');
    final signIn = GoogleSignIn(scopes: const [_scope], serverClientId: serverClientId.trim().isEmpty ? null : serverClientId.trim());
    final account = await signIn.signInSilently();
    if (account == null) throw Exception('Reconnect Gmail to continue syncing.');
    return _sync(await account.authHeaders);
  }

  Future<void> disconnect() async {
    final signIn = GoogleSignIn(scopes: const [_scope]);
    await signIn.disconnect();
    await AppDb.instance.setSetting('gmail_sync_enabled', '0');
    await AppDb.instance.setSetting('gmail_connected_email', '');
  }

  Future<GmailSyncResult> _sync(Map<String, String> headers) async {
    const query = 'newer_than:90d (debit OR debited OR transaction OR payment OR spent OR credited OR refund) -category:promotions -category:social';
    final list = await _getJson('https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${Uri.encodeQueryComponent(query)}&maxResults=100', headers);
    final messages = (list['messages'] as List? ?? const []).whereType<Map>().toList();
    var imported = 0;
    var ignored = 0;
    for (final summary in messages) {
      final id = '${summary['id'] ?? ''}';
      if (id.isEmpty) continue;
      try {
        final message = await _getJson('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full', headers);
        final email = _emailPayload(message);
        if (email == null) { ignored++; continue; }
        final result = await NativeBridge.ingestGmailEmail(
          messageId: id, sender: email.sender, subject: email.subject,
          body: email.body, occurredAt: email.occurredAt,
        );
        if (result.status == 'imported' || result.status == 'merged') imported++; else ignored++;
      } catch (_) { ignored++; }
    }
    await AppDb.instance.setSetting('gmail_last_sync_at', DateTime.now().millisecondsSinceEpoch.toString());
    return GmailSyncResult(scanned: messages.length, imported: imported, ignored: ignored);
  }

  Future<Map<String, dynamic>> _getJson(String url, Map<String, String> headers) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      headers.forEach(request.headers.set);
      final response = await request.close();
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Gmail returned ${response.statusCode}.');
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally { client.close(force: true); }
  }

  _EmailPayload? _emailPayload(Map<String, dynamic> message) {
    final payload = message['payload'] as Map?;
    final headers = (payload?['headers'] as List? ?? const []).whereType<Map>();
    String header(String name) => headers.firstWhere((h) => '${h['name']}'.toLowerCase() == name.toLowerCase(), orElse: () => const {})['value']?.toString() ?? '';
    final subject = header('Subject');
    final from = header('From');
    final body = _bodyText(payload ?? const {});
    final text = '$subject\n$body'.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = text.toLowerCase();
    if (RegExp(r'\b(otp|one.time.password|verification code|offer|cashback offer|unsubscribe)\b').hasMatch(lower)) return null;
    final isCompleted = RegExp(r'\b(debited|spent|payment successful|transaction successful|paid|credited|refund|reversed)\b').hasMatch(lower);
    if (!isCompleted) return null;
    final occurredAt = int.tryParse('${message['internalDate']}') ?? DateTime.now().millisecondsSinceEpoch;
    return _EmailPayload(sender: _senderName(from), subject: subject, body: text, occurredAt: occurredAt);
  }

  String _bodyText(Map payload) {
    final data = payload['body'] is Map ? payload['body']['data']?.toString() : null;
    if (data != null && data.isNotEmpty) return utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
    final parts = payload['parts'] as List? ?? const [];
    return parts.whereType<Map>().map((part) => _bodyText(part)).join('\n');
  }

  String _senderName(String from) => from.replaceAll(RegExp(r'<.*>'), '').replaceAll(RegExp("[\\\"']"), '').trim();
}

class _EmailPayload { final String sender; final String subject; final String body; final int occurredAt; const _EmailPayload({required this.sender, required this.subject, required this.body, required this.occurredAt}); }
