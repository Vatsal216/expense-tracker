package com.example.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SummaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val db = ExpenseDatabase(context.applicationContext)
        if (db.getSetting("daily_summary_enabled", "1") != "1") return
        val totals = db.todayTotals()
        NotificationHelper.showDailySummary(context, totals.first, totals.second)
        val hour = db.getSetting("daily_summary_hour", "21").toIntOrNull() ?: 21
        val minute = db.getSetting("daily_summary_minute", "0").toIntOrNull() ?: 0
        SummaryScheduler.scheduleNext(context, hour, minute)
    }
}
