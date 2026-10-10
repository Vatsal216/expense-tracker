package com.example.expense_tracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "expense_tracker/native"
    private val smsRequestCode = 7001
    private val notificationRequestCode = 7002
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermission" -> requestSmsPermission(result)
                "hasSmsPermission" -> result.success(hasSmsPermission())
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "hasNotificationPermission" -> result.success(hasNotificationPermission())
                "scheduleDailySummary" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val hour = call.argument<Int>("hour") ?: 21
                    val minute = call.argument<Int>("minute") ?: 0
                    if (enabled) SummaryScheduler.scheduleNext(this, hour, minute) else SummaryScheduler.cancel(this)
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.M || checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) { result.success(true); return }
        pendingSmsResult = result
        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), smsRequestCode)
    }

    private fun hasNotificationPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) { result.success(true); return }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pendingNotificationResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequestCode)
        } else result.success(true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            smsRequestCode -> { pendingSmsResult?.success(granted); pendingSmsResult = null }
            notificationRequestCode -> { pendingNotificationResult?.success(granted); pendingNotificationResult = null }
        }
    }
}
