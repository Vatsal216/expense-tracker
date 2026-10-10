package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SummaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val db = ExpenseDatabase(context.applicationContext)
        if (db.getSetting("daily_summary_enabled", "1") == "1" && db.getSetting("notifications_enabled", "1") == "1") {
            val today = db.todayTotals()
            NotificationHelper.showDailySummary(context.applicationContext, today.first, today.second, db.currentMonthExpenseTotal(), db.budgetFor("__overall__"))
        }
        val enabled = db.getSetting("daily_summary_enabled", "1") == "1"
        val hour = db.getSetting("daily_summary_hour", "21").toIntOrNull() ?: 21
        val minute = db.getSetting("daily_summary_minute", "0").toIntOrNull() ?: 0
        db.close()
        if (enabled) SummaryScheduler.scheduleNext(context.applicationContext, hour, minute)
    }
}
