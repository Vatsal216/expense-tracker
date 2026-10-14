package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val db = ExpenseDatabase(context.applicationContext)
        if (db.getSetting("sms_tracking_enabled", "0") != "1") return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) return
        val sender = messages.firstOrNull()?.displayOriginatingAddress.orEmpty()
        val body = messages.joinToString(separator = "") { it.displayMessageBody.orEmpty() }
        val occurredAt = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()
        val parsed = TransactionParser.parseSms(db, sender, body, occurredAt) ?: return
        val inserted = db.insertTransaction(parsed, "sms")
        if (inserted > 0) {
            BudgetGuard.check(context.applicationContext, db, parsed)
        }
        if (inserted > 0 && db.getSetting("notifications_enabled", "1") == "1") {
            NotificationHelper.showTransaction(context, parsed)
        }
    }
}
