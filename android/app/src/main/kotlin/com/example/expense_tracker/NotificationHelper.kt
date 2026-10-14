package com.example.expense_tracker

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

object NotificationHelper {
    private const val channelId = "expense_tracker_transactions"

    private fun manager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = manager(context)
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(channelId, "Expense Tracker", NotificationManager.IMPORTANCE_DEFAULT).apply {
                        description = "Transaction and daily summary notifications"
                    }
                )
            }
        }
    }

    private fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun builder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, channelId)
        else Notification.Builder(context)

    fun showTransaction(context: Context, tx: ParsedTransaction) {
        ensureChannel(context)
        if (!canNotify(context)) return
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val sign = if (tx.type == "income" || tx.type == "refund") "+" else "-"
        val note = if (tx.note.isBlank()) "" else " • ${tx.note}"
        val notification = builder(context)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle(tx.merchant)
            .setContentText("$sign₹${"%.2f".format(tx.amount)} • ${tx.category}$note")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager(context).notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    fun showBudgetAlert(context: Context, title: String, text: String) {
        ensureChannel(context)
        if (!canNotify(context)) return
        val notification = builder(context)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        manager(context).notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    fun showDailySummary(context: Context, expense: Double, investment: Double) {
        ensureChannel(context)
        if (!canNotify(context)) return
        val notification = builder(context)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("Today's money summary")
            .setContentText("Expense ₹${"%.0f".format(expense)} • Investment ₹${"%.0f".format(investment)}")
            .setAutoCancel(true)
            .build()
        manager(context).notify(92002, notification)
    }
}
