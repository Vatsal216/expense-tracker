package com.example.expense_tracker

import android.content.Context

object BudgetGuard {
    fun check(context: Context, db: ExpenseDatabase, tx: ParsedTransaction) {
        if (tx.type != "expense") return
        val overall = db.budgetFor("__overall__")
        val overallSpent = db.currentMonthExpenseTotal()
        if (overall != null && overall > 0 && overallSpent >= overall) {
            NotificationHelper.showBudgetAlert(
                context,
                "Monthly budget reached",
                "Spent ₹${"%.0f".format(overallSpent)} of ₹${"%.0f".format(overall)}"
            )
        }
        val categoryBudget = db.budgetFor(tx.category)
        val categorySpent = db.currentMonthCategoryExpense(tx.category)
        if (categoryBudget != null && categoryBudget > 0 && categorySpent >= categoryBudget) {
            NotificationHelper.showBudgetAlert(
                context,
                "${tx.category} budget reached",
                "Spent ₹${"%.0f".format(categorySpent)} of ₹${"%.0f".format(categoryBudget)}"
            )
        }
    }
}
