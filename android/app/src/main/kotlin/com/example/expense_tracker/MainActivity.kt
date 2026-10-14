package com.example.expense_tracker

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.provider.Telephony
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "expense_tracker/native"
    private val smsRequestCode = 7001
    private val notificationRequestCode = 7002
    private val smsHistoryRequestCode = 7003
    private val upiRequestCode = 7100
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingSmsHistoryResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingUpiResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Screenshots are intentionally enabled in v15 while UI testing is ongoing.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermission" -> requestSmsPermission(result)
                "hasSmsPermission" -> result.success(hasSmsPermission())
                "requestSmsHistoryPermission" -> requestSmsHistoryPermission(result)
                "hasSmsHistoryPermission" -> result.success(hasSmsHistoryPermission())
                "importHistoricalSms" -> importHistoricalSms(result)
                "reclassifyStoredSms" -> reclassifyStoredSms(result)
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "hasNotificationPermission" -> result.success(hasNotificationPermission())
                "hasNotificationListenerPermission" -> result.success(hasNotificationListenerPermission())
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
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
                "setSecureScreen" -> {
                    // Temporarily disabled by product request so screenshots can be used for UI QA.
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "updateHomeWidget" -> {
                    ExpenseWidgetProvider.refresh(applicationContext)
                    result.success(null)
                }
                "showSmartAlert" -> {
                    val args = call.arguments as? Map<*, *>
                    val title = args?.get("title")?.toString().orEmpty()
                    val text = args?.get("text")?.toString().orEmpty()
                    if (title.isNotBlank() && text.isNotBlank()) NotificationHelper.showBudgetAlert(applicationContext, title, text)
                    result.success(null)
                }
                "startUpiPayment" -> startUpiPayment(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }
        pendingSmsResult = result
        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), smsRequestCode)
    }

    private fun hasSmsHistoryPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsHistoryPermission(result: MethodChannel.Result) {
        if (hasSmsHistoryPermission()) {
            result.success(true)
            return
        }
        pendingSmsHistoryResult = result
        requestPermissions(arrayOf(Manifest.permission.READ_SMS), smsHistoryRequestCode)
    }

    private fun importHistoricalSms(result: MethodChannel.Result) {
        if (!hasSmsHistoryPermission()) {
            result.error("READ_SMS_REQUIRED", "SMS history permission is required.", null)
            return
        }

        Thread {
            try {
                val db = ExpenseDatabase(applicationContext)
                var scanned = 0
                var imported = 0
                var duplicates = 0
                var ignored = 0

                val projection = arrayOf(
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                )

                contentResolver.query(
                    Telephony.Sms.Inbox.CONTENT_URI,
                    projection,
                    null,
                    null,
                    "${Telephony.Sms.DATE} DESC",
                )?.use { cursor ->
                    val addressIndex = cursor.getColumnIndex(Telephony.Sms.ADDRESS)
                    val bodyIndex = cursor.getColumnIndex(Telephony.Sms.BODY)
                    val dateIndex = cursor.getColumnIndex(Telephony.Sms.DATE)

                    while (cursor.moveToNext()) {
                        scanned++
                        val sender = if (addressIndex >= 0) cursor.getString(addressIndex).orEmpty() else ""
                        val body = if (bodyIndex >= 0) cursor.getString(bodyIndex).orEmpty() else ""
                        val occurredAt = if (dateIndex >= 0) cursor.getLong(dateIndex) else System.currentTimeMillis()

                        val parsed = TransactionParser.parseSms(db, sender, body, occurredAt)
                        if (parsed == null) {
                            ignored++
                            continue
                        }

                        val inserted = db.insertTransaction(parsed, "sms")
                        if (inserted > 0) imported++ else duplicates++
                    }
                }

                ExpenseWidgetProvider.refresh(applicationContext)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "scanned" to scanned,
                            "imported" to imported,
                            "duplicates" to duplicates,
                            "ignored" to ignored,
                        )
                    )
                }
            } catch (e: SecurityException) {
                runOnUiThread {
                    result.error("READ_SMS_DENIED", "SMS history permission was denied.", null)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SMS_IMPORT_FAILED", e.message ?: "Historical SMS import failed.", null)
                }
            }
        }.start()
    }

    private fun reclassifyStoredSms(result: MethodChannel.Result) {
        Thread {
            try {
                val db = ExpenseDatabase(applicationContext)
                val stats = db.reclassifyStoredSms()
                ExpenseWidgetProvider.refresh(applicationContext)
                runOnUiThread { result.success(stats) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("RECLASSIFY_FAILED", e.message ?: "Stored SMS reclassification failed.", null)
                }
            }
        }.start()
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pendingNotificationResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequestCode)
        } else {
            result.success(true)
        }
    }

    private fun hasNotificationListenerPermission(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
        return enabled.contains(packageName)
    }

    private fun startUpiPayment(args: Map<*, *>?, result: MethodChannel.Result) {
        val upiId = args?.get("upiId")?.toString()?.trim().orEmpty()
        val payeeName = args?.get("payeeName")?.toString()?.trim().orEmpty()
        val amount = args?.get("amount")?.toString()?.trim().orEmpty()
        val note = args?.get("note")?.toString()?.trim().orEmpty()

        if (upiId.isBlank() || payeeName.isBlank() || amount.isBlank()) {
            result.error("INVALID_UPI", "UPI ID, payee name and amount are required.", null)
            return
        }

        val uri = Uri.Builder()
            .scheme("upi")
            .authority("pay")
            .appendQueryParameter("pa", upiId)
            .appendQueryParameter("pn", payeeName)
            .appendQueryParameter("am", amount)
            .appendQueryParameter("cu", "INR")
            .appendQueryParameter("tn", note)
            .build()

        val baseIntent = Intent(Intent.ACTION_VIEW, uri)
        pendingUpiResult = result

        try {
            if (baseIntent.resolveActivity(packageManager) != null) {
                // Let Android show every compatible installed UPI app (GPay, PhonePe, Paytm, etc.).
                startActivityForResult(Intent.createChooser(baseIntent, "Choose UPI app"), upiRequestCode)
            } else {
                pendingUpiResult = null
                result.error("NO_UPI_APP", "No UPI app is available on this device.", null)
            }
        } catch (e: ActivityNotFoundException) {
            pendingUpiResult = null
            result.error("NO_UPI_APP", "No compatible UPI app was found.", null)
        } catch (e: Exception) {
            pendingUpiResult = null
            result.error("UPI_LAUNCH_FAILED", e.message, null)
        }
    }

    @Deprecated("Deprecated in Android API but retained for UPI app result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != upiRequestCode) return

        val raw = data?.getStringExtra("response")
            ?: data?.dataString
            ?: data?.extras?.keySet()?.joinToString("&") { key -> "$key=${data.extras?.get(key)}" }
            ?: ""

        val parsed = mutableMapOf<String, String>()
        raw.split("&").forEach { part ->
            val pair = part.split("=", limit = 2)
            if (pair.size == 2) parsed[pair[0].trim().lowercase()] = pair[1].trim()
        }

        val status = parsed["status"]
            ?: if (resultCode == Activity.RESULT_CANCELED) "cancelled" else "unknown"

        pendingUpiResult?.success(
            mapOf(
                "status" to status,
                "txnId" to (parsed["txnid"] ?: parsed["txn_id"] ?: ""),
                "txnRef" to (parsed["txnref"] ?: parsed["txn_ref"] ?: ""),
                "approvalRefNo" to (parsed["approvalrefno"] ?: parsed["approval_ref_no"] ?: ""),
                "responseCode" to (parsed["responsecode"] ?: parsed["response_code"] ?: ""),
                "raw" to raw,
            )
        )
        pendingUpiResult = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            smsRequestCode -> {
                pendingSmsResult?.success(granted)
                pendingSmsResult = null
            }
            smsHistoryRequestCode -> {
                pendingSmsHistoryResult?.success(granted)
                pendingSmsHistoryResult = null
            }
            notificationRequestCode -> {
                pendingNotificationResult?.success(granted)
                pendingNotificationResult = null
            }
        }
    }
}
