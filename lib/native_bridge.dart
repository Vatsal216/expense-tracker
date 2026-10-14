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

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('expense_tracker/native');

  static Future<bool> requestSmsPermission() async =>
      (await _channel.invokeMethod<bool>('requestSmsPermission')) ?? false;

  static Future<bool> hasSmsPermission() async =>
      (await _channel.invokeMethod<bool>('hasSmsPermission')) ?? false;

  static Future<bool> requestNotificationPermission() async =>
      (await _channel.invokeMethod<bool>('requestNotificationPermission')) ?? false;

  static Future<bool> hasNotificationPermission() async =>
      (await _channel.invokeMethod<bool>('hasNotificationPermission')) ?? false;

  static Future<bool> hasNotificationListenerPermission() async =>
      (await _channel.invokeMethod<bool>('hasNotificationListenerPermission')) ?? false;

  static Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod('openNotificationAccessSettings');

  static Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');

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
    required String upiId,
    required String payeeName,
    required double amount,
    required String note,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('startUpiPayment', {
      'upiId': upiId,
      'payeeName': payeeName,
      'amount': amount.toStringAsFixed(2),
      'note': note,
    });
    return UpiResult.fromMap(raw);
  }
}
