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
import java.text.NumberFormat
import java.util.Locale

object NotificationHelper {
    private const val transactionChannel = "transactions"
    private const val summaryChannel = "daily_summary"

    fun showTransaction(context: Context, db: ExpenseDatabase, id: Long, tx: ParsedTransaction) {
        if (db.getSetting("notifications_enabled", "1") != "1" || !canNotify(context)) return
        ensureChannels(context)
        val amount = NumberFormat.getCurrencyInstance(Locale("en", "IN")).format(tx.amount)
        val title = when (tx.type) {
            "investment" -> "Investment detected"
            "income" -> "Income detected"
            "refund" -> "Refund detected"
            "transfer" -> "Transfer detected"
            else -> "Expense detected"
        }
        val budget = budgetMessage(db, tx)
        val body = "$amount • ${tx.merchant} • ${tx.category}" + if (budget.isBlank()) "" else "\n$budget"
        val notification = baseBuilder(context, transactionChannel).setContentTitle(title).setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true).build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify((id % Int.MAX_VALUE).toInt(), notification)
    }

    fun showDailySummary(context: Context, expense: Double, investment: Double, monthExpense: Double, overallBudget: Double?) {
        if (!canNotify(context)) return
        ensureChannels(context)
        val f = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
        val budget = if (overallBudget != null && overallBudget > 0) " • Month ${f.format(monthExpense)} / ${f.format(overallBudget)}" else ""
        val body = "Spent ${f.format(expense)} • Invested ${f.format(investment)}$budget"
        val notification = baseBuilder(context, summaryChannel).setContentTitle("Today's money report").setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true).build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(91000, notification)
    }

    private fun budgetMessage(db: ExpenseDatabase, tx: ParsedTransaction): String {
        if (tx.type != "expense") return ""
        val f = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
        val overall = db.budgetFor("__overall__")
        val month = db.currentMonthExpenseTotal()
        val categoryBudget = db.budgetFor(tx.category)
        val categorySpent = if (categoryBudget != null) db.currentMonthCategoryExpense(tx.category) else 0.0
        return when {
            categoryBudget != null && categorySpent > categoryBudget -> "${tx.category} budget exceeded by ${f.format(categorySpent - categoryBudget)}"
            overall != null && month > overall -> "Monthly budget exceeded by ${f.format(month - overall)}"
            categoryBudget != null && categorySpent >= categoryBudget * .8 -> "${tx.category}: ${((categorySpent / categoryBudget) * 100).toInt()}% of budget used"
            overall != null && month >= overall * .8 -> "Monthly budget: ${((month / overall) * 100).toInt()}% used"
            else -> ""
        }
    }

    private fun baseBuilder(context: Context, channel: String): Notification.Builder {
        val pending = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, channel).setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pending)
        else Notification.Builder(context).setSmallIcon(android.R.drawable.ic_dialog_info).setContentIntent(pending)
    }

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(transactionChannel, "Detected transactions", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Automatically detected transactions" })
        manager.createNotificationChannel(NotificationChannel(summaryChannel, "Daily summary", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Daily expense and investment summary" })
    }

    private fun canNotify(context: Context): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
}
