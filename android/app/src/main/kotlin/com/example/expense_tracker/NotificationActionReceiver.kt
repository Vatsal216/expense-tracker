package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val txId = intent.getLongExtra("transaction_id", -1L)
        val action = intent.getStringExtra("tx_action").orEmpty()
        if (txId <= 0L || action.isBlank()) return
        ExpenseDatabase(context.applicationContext).applyNotificationAction(txId, action)
        ExpenseWidgetProvider.refresh(context.applicationContext)
    }
}
