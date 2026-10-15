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
    private var pendingUpiPackage: String? = null

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
                "getUpiApps" -> getUpiApps(call.arguments as? Map<*, *>, result)
                "startUpiPayment" -> startUpiPayment(call.arguments as? Map<*, *>, result)
                "openPaymentApp" -> openPaymentApp(call.arguments as? Map<*, *>, result)
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

    private fun validatedUpiUri(paymentUri: String): Uri? {
        val uri = try { Uri.parse(paymentUri) } catch (_: Exception) { null } ?: return null
        if (!uri.scheme.equals("upi", ignoreCase = true) || !uri.host.equals("pay", ignoreCase = true)) return null
        val upiId = uri.getQueryParameter("pa").orEmpty().trim()
        if (upiId.isBlank() || !upiId.contains("@")) return null
        return uri
    }

    private fun upiReadyPackages(uri: Uri? = null): Set<String> {
        val pm = packageManager
        val generic = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        val ready = pm.queryIntentActivities(generic, PackageManager.MATCH_DEFAULT_ONLY)
            .mapNotNull { it.activityInfo?.packageName }
            .filter { it != packageName }
            .toMutableSet()

        if (uri != null) {
            val exact = Intent(Intent.ACTION_VIEW, uri)
            val exactPackages = pm.queryIntentActivities(exact, PackageManager.MATCH_DEFAULT_ONLY)
                .mapNotNull { it.activityInfo?.packageName }
                .toSet()
            ready.retainAll(exactPackages)
        }
        return ready
    }

    private fun friendlyUpiName(packageName: String, fallback: String): String = when (packageName) {
        "net.one97.paytm" -> "Paytm"
        "com.google.android.apps.nbu.paisa.user" -> "Google Pay"
        "com.phonepe.app" -> "PhonePe"
        "in.org.npci.upiapp" -> "BHIM"
        else -> fallback
    }

    private fun getUpiApps(args: Map<*, *>?, result: MethodChannel.Result) {
        val paymentUri = args?.get("paymentUri")?.toString()?.trim().orEmpty()
        val uri = if (paymentUri.isBlank()) null else validatedUpiUri(paymentUri)
        if (paymentUri.isNotBlank() && uri == null) {
            result.error("INVALID_UPI", "Invalid UPI payment URI.", null)
            return
        }

        val pm = packageManager
        val packages = upiReadyPackages(uri)
        val knownOrder = mapOf(
            "net.one97.paytm" to 0,
            "com.google.android.apps.nbu.paisa.user" to 1,
            "com.phonepe.app" to 2,
            "in.org.npci.upiapp" to 3,
        )

        val apps = packages.mapNotNull { pkg ->
            try {
                val info = pm.getApplicationInfo(pkg, 0)
                val systemLabel = pm.getApplicationLabel(info).toString().trim().ifBlank { pkg }
                mapOf(
                    "packageName" to pkg,
                    "name" to friendlyUpiName(pkg, systemLabel),
                    "known" to knownOrder.containsKey(pkg),
                )
            } catch (_: Exception) {
                null
            }
        }.sortedWith(
            compareBy<Map<String, Any>> { knownOrder[it["packageName"] as String] ?: 100 }
                .thenBy { (it["name"] as String).lowercase() }
        )
        result.success(apps)
    }

    // Launch the provider's home screen, not a payment intent. This does not
    // return a payment result; confirmed bank SMS/notifications are handled separately.
    private fun openPaymentApp(args: Map<*, *>?, result: MethodChannel.Result) {
        val provider = args?.get("provider")?.toString()?.lowercase()?.trim().orEmpty()
        val targetPackage = when (provider) {
            "phonepe" -> "com.phonepe.app"
            "paytm" -> "net.one97.paytm"
            "cred" -> "com.dreamplug.androidapp"
            else -> {
                result.error("UNSUPPORTED_APP", "Choose a supported payment app.", null)
                return
            }
        }
        val intent = packageManager.getLaunchIntentForPackage(targetPackage)
        if (intent == null) {
            result.error("APP_NOT_INSTALLED", "The selected payment app is not available.", null)
            return
        }
        try {
            startActivity(intent)
            result.success(true) // App opened, NOT payment completed.
        } catch (e: Exception) {
            result.error("APP_OPEN_FAILED", e.message, null)
        }
    }

    private fun startUpiPayment(args: Map<*, *>?, result: MethodChannel.Result) {
        val paymentUri = args?.get("paymentUri")?.toString()?.trim().orEmpty()
        if (paymentUri.isBlank()) {
            result.error("INVALID_UPI", "UPI payment URI is required.", null)
            return
        }

        val uri = validatedUpiUri(paymentUri)
        if (uri == null) {
            result.error("INVALID_UPI", "A valid upi://pay URI with payee UPI ID is required.", null)
            return
        }

        val requestedPackage = args?.get("packageName")?.toString()?.trim().orEmpty()
        val baseIntent = Intent(Intent.ACTION_VIEW, uri)
        val readyPackages = upiReadyPackages(uri)
        if (readyPackages.isEmpty()) {
            result.error("NO_UPI_APP", "No UPI-ready app is available for this payment on this device.", null)
            return
        }
        if (requestedPackage.isNotBlank() && !readyPackages.contains(requestedPackage)) {
            result.error("UPI_APP_NOT_READY", "The selected UPI app is not ready to handle this payment.", null)
            return
        }

        pendingUpiResult = result
        pendingUpiPackage = requestedPackage.ifBlank { null }

        try {
            if (requestedPackage.isNotBlank()) {
                // Direct smart-intent launch: Paytm / Google Pay / PhonePe / BHIM / any
                // dynamically discovered UPI app. The complete URI is passed untouched.
                baseIntent.setPackage(requestedPackage)
                startActivityForResult(baseIntent, upiRequestCode)
            } else {
                // NPCI-compatible generic option: always keep "Pay by any UPI app" available.
                startActivityForResult(Intent.createChooser(baseIntent, "Pay by any UPI app"), upiRequestCode)
            }
        } catch (e: ActivityNotFoundException) {
            pendingUpiResult = null
            pendingUpiPackage = null
            result.error("NO_UPI_APP", "The selected UPI app could not be opened.", null)
        } catch (e: Exception) {
            pendingUpiResult = null
            pendingUpiPackage = null
            result.error("UPI_LAUNCH_FAILED", e.message, null)
        }
    }

    private fun decodeUpiValue(value: String): String = try {
        Uri.decode(value).trim()
    } catch (_: Exception) {
        value.trim()
    }

    @Deprecated("Deprecated in Android API but retained for UPI app result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != upiRequestCode) return

        val parsed = linkedMapOf<String, String>()
        data?.extras?.keySet()?.forEach { key ->
            val value = data.extras?.get(key)?.toString().orEmpty()
            if (value.isNotBlank()) parsed[key.trim().lowercase()] = decodeUpiValue(value)
        }

        val response = data?.getStringExtra("response").orEmpty()
        if (response.isNotBlank()) {
            response.split("&").forEach { part ->
                val pair = part.split("=", limit = 2)
                if (pair.size == 2) parsed[pair[0].trim().lowercase()] = decodeUpiValue(pair[1])
            }
        }

        val dataString = data?.dataString.orEmpty()
        if (dataString.contains("=")) {
            val query = dataString.substringAfter('?', dataString)
            query.split("&").forEach { part ->
                val pair = part.split("=", limit = 2)
                if (pair.size == 2) parsed.putIfAbsent(pair[0].trim().lowercase(), decodeUpiValue(pair[1]))
            }
        }

        val raw = when {
            response.isNotBlank() -> response
            parsed.isNotEmpty() -> parsed.entries.joinToString("&") { "${it.key}=${it.value}" }
            dataString.isNotBlank() -> dataString
            else -> ""
        }

        val rawStatus = parsed["status"].orEmpty()
        val responseCode = parsed["responsecode"] ?: parsed["response_code"] ?: ""
        val status = when {
            rawStatus.equals("success", true) || responseCode == "00" -> "success"
            rawStatus.equals("submitted", true) || rawStatus.equals("pending", true) -> "pending"
            rawStatus.equals("failure", true) || rawStatus.equals("failed", true) -> "failed"
            resultCode == Activity.RESULT_CANCELED -> "cancelled"
            else -> rawStatus.ifBlank { "unknown" }.lowercase()
        }

        pendingUpiResult?.success(
            mapOf(
                "status" to status,
                "txnId" to (parsed["txnid"] ?: parsed["txn_id"] ?: ""),
                "txnRef" to (parsed["txnref"] ?: parsed["txn_ref"] ?: parsed["tr"] ?: ""),
                "approvalRefNo" to (parsed["approvalrefno"] ?: parsed["approval_ref_no"] ?: ""),
                "responseCode" to responseCode,
                "appPackage" to (pendingUpiPackage ?: ""),
                "raw" to raw,
            )
        )
        pendingUpiResult = null
        pendingUpiPackage = null
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
