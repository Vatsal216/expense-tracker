package com.example.expense_tracker

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class PhonePeNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val item = sbn ?: return
        // Only allow-listed finance app notifications; never read arbitrary apps.
        val appName = when (item.packageName) {
            "com.phonepe.app" -> "PhonePe"
            "net.one97.paytm" -> "Paytm"
            "com.google.android.apps.nbu.paisa.user" -> "Google Pay"
            else -> return
        }

        val db = ExpenseDatabase(applicationContext)
        if (db.getSetting("phonepe_notification_enabled", "0") != "1") return

        val extras = item.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        val body = listOf(text, bigText, subText).filter { it.isNotBlank() }.distinct().joinToString(" | ")
        // Use the same explicit transaction evidence guard for all supported UPI apps.
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
