package com.example.expense_tracker

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class PhonePeNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val item = sbn ?: return
        val db = ExpenseDatabase(applicationContext)
        // Android grants listener access to this app, not to individual apps.
        // Enforce the user's explicit per-app selection before reading content.
        val selected = db.getSetting("notification_tracking_packages", "")
            .split(',').map { it.trim() }.filter { it.isNotBlank() }.toSet()
        val legacyEnabled = db.getSetting("phonepe_notification_enabled", "0") == "1"
        val allowed = if (selected.isEmpty() && legacyEnabled) setOf("com.phonepe.app") else selected
        if (!allowed.contains(item.packageName)) return
        val appName = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(item.packageName, 0)).toString()
        } catch (_: Exception) {
            "Payment app"
        }

        val extras = item.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        val body = listOf(text, bigText, subText).filter { it.isNotBlank() }.distinct().joinToString(" | ")
        // Use the same explicit transaction-evidence guard for every user-selected financial app.
        val parsed = TransactionParser.parsePhonePeNotification(db, title, body, item.postTime, appName) ?: return
        val inserted = db.insertTransaction(parsed, "${appName.lowercase().replace(" ", "_")}_notification")
        if (inserted > 0) {
            if (parsed.reviewStatus == "accepted") BudgetGuard.check(applicationContext, db, parsed)
            ExpenseWidgetProvider.refresh(applicationContext)
        }
        if (inserted > 0 && db.getSetting("notifications_enabled", "1") == "1") {
            NotificationHelper.showTransaction(applicationContext, parsed, inserted)
        }
    }
}
