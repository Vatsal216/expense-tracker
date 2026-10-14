package com.example.expense_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class ExpenseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        update(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ExpenseWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) update(context, manager, ids)
        }

        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val (expense, budget, remaining) = ExpenseDatabase(context.applicationContext).widgetSummary()
            val openIntent = Intent(context, MainActivity::class.java)
            val open = PendingIntent.getActivity(context, 9911, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.expense_widget)
                views.setTextViewText(R.id.widget_spent, "₹${"%.0f".format(expense)} spent")
                views.setTextViewText(R.id.widget_remaining, if (budget > 0) "₹${"%.0f".format(remaining)} left of ₹${"%.0f".format(budget)}" else "Open app to set a budget")
                views.setOnClickPendingIntent(R.id.widget_root, open)
                manager.updateAppWidget(id, views)
            }
        }
    }
}
