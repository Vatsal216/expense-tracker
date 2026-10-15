import 'package:flutter/services.dart';

class UpiResult {
  final String status;
  final String txnId;
  final String txnRef;
  final String approvalRefNo;
  final String responseCode;
  final String raw;

  const UpiResult({
    required this.status,
    required this.txnId,
    required this.txnRef,
    required this.approvalRefNo,
    required this.responseCode,
    required this.raw,
  });

  bool get success => status.toLowerCase() == 'success' || responseCode == '00';

  factory UpiResult.fromMap(Map<dynamic, dynamic>? map) => UpiResult(
        status: '${map?['status'] ?? 'unknown'}',
        txnId: '${map?['txnId'] ?? ''}',
        txnRef: '${map?['txnRef'] ?? ''}',
        approvalRefNo: '${map?['approvalRefNo'] ?? ''}',
        responseCode: '${map?['responseCode'] ?? ''}',
        raw: '${map?['raw'] ?? ''}',
      );
}


class HistoricalSmsImportResult {
  final int scanned;
  final int imported;
  final int duplicates;
  final int ignored;

  const HistoricalSmsImportResult({
    required this.scanned,
    required this.imported,
    required this.duplicates,
    required this.ignored,
  });

  factory HistoricalSmsImportResult.fromMap(Map<dynamic, dynamic>? map) =>
      HistoricalSmsImportResult(
        scanned: (map?['scanned'] as num?)?.toInt() ?? 0,
        imported: (map?['imported'] as num?)?.toInt() ?? 0,
        duplicates: (map?['duplicates'] as num?)?.toInt() ?? 0,
        ignored: (map?['ignored'] as num?)?.toInt() ?? 0,
      );
}

class SmsReclassifyResult {
  final int checked;
  final int updated;
  final int ignored;
  final int unchanged;

  const SmsReclassifyResult({
    required this.checked,
    required this.updated,
    required this.ignored,
    required this.unchanged,
  });

  factory SmsReclassifyResult.fromMap(Map<dynamic, dynamic>? map) => SmsReclassifyResult(
        checked: (map?['checked'] as num?)?.toInt() ?? 0,
        updated: (map?['updated'] as num?)?.toInt() ?? 0,
        ignored: (map?['ignored'] as num?)?.toInt() ?? 0,
        unchanged: (map?['unchanged'] as num?)?.toInt() ?? 0,
      );
}

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('expense_tracker/native');

  static Future<bool> requestSmsPermission() async =>
      (await _channel.invokeMethod<bool>('requestSmsPermission')) ?? false;

  static Future<bool> hasSmsPermission() async =>
      (await _channel.invokeMethod<bool>('hasSmsPermission')) ?? false;

  static Future<bool> requestSmsHistoryPermission() async =>
      (await _channel.invokeMethod<bool>('requestSmsHistoryPermission')) ?? false;

  static Future<bool> hasSmsHistoryPermission() async =>
      (await _channel.invokeMethod<bool>('hasSmsHistoryPermission')) ?? false;

  static Future<HistoricalSmsImportResult> importHistoricalSms() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('importHistoricalSms');
    return HistoricalSmsImportResult.fromMap(raw);
  }

  static Future<SmsReclassifyResult> reclassifyStoredSms() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('reclassifyStoredSms');
    return SmsReclassifyResult.fromMap(raw);
  }

  static Future<bool> requestNotificationPermission() async =>
      (await _channel.invokeMethod<bool>('requestNotificationPermission')) ?? false;

  static Future<bool> hasNotificationPermission() async =>
      (await _channel.invokeMethod<bool>('hasNotificationPermission')) ?? false;

  static Future<bool> hasNotificationListenerPermission() async =>
      (await _channel.invokeMethod<bool>('hasNotificationListenerPermission')) ?? false;

  static Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod('openNotificationAccessSettings');

  static Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');

  static Future<void> setSecureScreen(bool enabled) =>
      _channel.invokeMethod('setSecureScreen', {'enabled': enabled});

  static Future<void> updateHomeWidget() =>
      _channel.invokeMethod('updateHomeWidget');

  static Future<void> showSmartAlert(String title, String text) =>
      _channel.invokeMethod('showSmartAlert', {'title': title, 'text': text});

  static Future<void> scheduleDailySummary({
    required bool enabled,
    required int hour,
    required int minute,
  }) =>
      _channel.invokeMethod('scheduleDailySummary', {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      });

  static Future<UpiResult> startUpiPayment({
    required String paymentUri,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('startUpiPayment', {
      'paymentUri': paymentUri,
    });
    return UpiResult.fromMap(raw);
  }
}
