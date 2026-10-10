package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val db = ExpenseDatabase(context.applicationContext)
        if (db.getSetting("sms_tracking_enabled", "0") != "1") { db.close(); return }
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) { db.close(); return }
        val sender = messages.firstOrNull()?.originatingAddress ?: "Unknown"
        val body = messages.joinToString("") { it.messageBody ?: "" }
        val timestamp = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()
        val parsed = TransactionParser.parse(sender, body, db, timestamp)
        if (parsed != null) {
            val id = db.insertTransaction(parsed)
            if (id > 0) NotificationHelper.showTransaction(context.applicationContext, db, id, parsed)
        }
        db.close()
    }
}
