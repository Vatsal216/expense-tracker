import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('expense_tracker/native');
  static Future<bool> requestSmsPermission() async => (await _channel.invokeMethod<bool>('requestSmsPermission')) ?? false;
  static Future<bool> hasSmsPermission() async => (await _channel.invokeMethod<bool>('hasSmsPermission')) ?? false;
  static Future<bool> requestNotificationPermission() async => (await _channel.invokeMethod<bool>('requestNotificationPermission')) ?? false;
  static Future<bool> hasNotificationPermission() async => (await _channel.invokeMethod<bool>('hasNotificationPermission')) ?? false;
  static Future<void> scheduleDailySummary({required bool enabled, required int hour, required int minute}) => _channel.invokeMethod('scheduleDailySummary', {'enabled': enabled, 'hour': hour, 'minute': minute});
  static Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');
}
