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
                        description = "Transaction, review and daily summary notifications"
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

    private fun action(context: Context, txId: Long, action: String, label: String, requestCode: Int): Notification.Action {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            putExtra("transaction_id", txId)
            putExtra("tx_action", action)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(0, label, pending).build()
    }

    fun showTransaction(context: Context, tx: ParsedTransaction, transactionId: Long) {
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
        val title = if (tx.reviewStatus == "needs_review") "Review: ${tx.merchant}" else tx.merchant
        val text = "$sign₹${"%.2f".format(tx.amount)} • ${tx.category}$note"
        val base = builder(context)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
        if (transactionId > 0L && tx.type != "income" && tx.type != "refund") {
            val seed = (transactionId % 100000).toInt() * 10
            base.addAction(action(context, transactionId, "food", "Food", seed + 1))
            base.addAction(action(context, transactionId, "shopping", "Shopping", seed + 2))
            base.addAction(action(context, transactionId, "transfer", "Transfer", seed + 3))
            base.addAction(action(context, transactionId, "ignore", "Ignore", seed + 4))
        }
        manager(context).notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), base.build())
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
