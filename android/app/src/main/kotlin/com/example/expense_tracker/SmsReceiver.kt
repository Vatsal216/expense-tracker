package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val db = ExpenseDatabase(context.applicationContext)
        db.setSetting("sms_pipeline_last_received_at", System.currentTimeMillis().toString())
        if (db.getSetting("sms_tracking_enabled", "0") != "1") {
            db.setSetting("sms_pipeline_last_status", "Paused: SMS Tracking is off")
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) {
            db.setSetting("sms_pipeline_last_status", "No SMS parts received")
            return
        }
        val sender = messages.firstOrNull()?.displayOriginatingAddress.orEmpty()
        val body = messages.joinToString(separator = "") { it.displayMessageBody.orEmpty() }
        val occurredAt = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()
        val parsed = TransactionParser.parseSms(db, sender, body, occurredAt)
        if (parsed == null) {
            db.setSetting("sms_pipeline_last_status", "Ignored: not a completed financial SMS")
            return
        }
        val inserted = db.insertTransaction(parsed, "sms")
        db.setSetting("sms_pipeline_last_status", when {
            inserted > 0 -> "Saved ${parsed.type} • ${parsed.category}"
            inserted < 0 -> "Merged with an existing transaction"
            else -> "Duplicate transaction ignored"
        })
        if (inserted > 0) {
            if (parsed.reviewStatus == "accepted") BudgetGuard.check(context.applicationContext, db, parsed)
            ExpenseWidgetProvider.refresh(context.applicationContext)
        }
        if (inserted > 0 && db.getSetting("notifications_enabled", "1") == "1") {
            NotificationHelper.showTransaction(context, parsed, inserted)
        }
    }
}
