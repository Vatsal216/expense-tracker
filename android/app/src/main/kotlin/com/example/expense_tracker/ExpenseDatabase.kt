package com.example.expense_tracker

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.Calendar

data class RuleMatch(val merchant: String, val type: String, val category: String, val keyword: String)

class ExpenseDatabase(context: Context) : SQLiteOpenHelper(context, "expense_tracker.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) { createSchema(db); seed(db) }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    override fun onConfigure(db: SQLiteDatabase) { super.onConfigure(db); db.setForeignKeyConstraintsEnabled(true); db.enableWriteAheadLogging() }

    private fun createSchema(db: SQLiteDatabase) {
        db.execSQL("""CREATE TABLE IF NOT EXISTS transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            category TEXT NOT NULL,
            merchant TEXT NOT NULL,
            source TEXT NOT NULL,
            raw_message TEXT NOT NULL DEFAULT '',
            sender TEXT NOT NULL DEFAULT '',
            payment_method TEXT NOT NULL DEFAULT '',
            account_hint TEXT NOT NULL DEFAULT '',
            occurred_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            fingerprint TEXT NOT NULL UNIQUE,
            is_manual INTEGER NOT NULL DEFAULT 0
        )""".trimIndent())
        db.execSQL("""CREATE TABLE IF NOT EXISTS rules(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            merchant TEXT NOT NULL,
            keyword TEXT NOT NULL,
            type TEXT NOT NULL,
            category TEXT NOT NULL,
            is_user_rule INTEGER NOT NULL DEFAULT 0,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL
        )""".trimIndent())
        db.execSQL("""CREATE TABLE IF NOT EXISTS budgets(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL UNIQUE,
            amount REAL NOT NULL,
            period TEXT NOT NULL DEFAULT 'monthly'
        )""".trimIndent())
        db.execSQL("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        db.execSQL("""CREATE TABLE IF NOT EXISTS categories(
            name TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        )""".trimIndent())
    }

    private fun seed(db: SQLiteDatabase) {
        val now = System.currentTimeMillis()
        val categories = listOf(
            "Food & Dining" to "expense", "Groceries" to "expense", "Transport" to "expense",
            "Shopping" to "expense", "Entertainment" to "expense", "Bills & Utilities" to "expense",
            "Healthcare" to "expense", "Travel" to "expense", "Education" to "expense",
            "Rent & Housing" to "expense", "EMI & Loans" to "expense", "Insurance" to "expense",
            "Stocks" to "investment", "Mutual Funds" to "investment", "Gold" to "investment",
            "Fixed Deposit" to "investment", "Other Investment" to "investment", "Salary" to "income",
            "Refund" to "refund", "Transfer" to "transfer", "Uncategorized" to "expense"
        )
        for ((name, kind) in categories) {
            val v = ContentValues().apply { put("name", name); put("kind", kind); put("is_system", 1); put("created_at", now) }
            db.insertWithOnConflict("categories", null, v, SQLiteDatabase.CONFLICT_IGNORE)
        }

        val defaults = listOf(
            arrayOf("Zomato", "zomato", "expense", "Food & Dining"),
            arrayOf("Swiggy", "swiggy", "expense", "Food & Dining"),
            arrayOf("Blinkit", "blinkit", "expense", "Groceries"),
            arrayOf("Zepto", "zepto", "expense", "Groceries"),
            arrayOf("BigBasket", "bigbasket", "expense", "Groceries"),
            arrayOf("Uber", "uber", "expense", "Transport"),
            arrayOf("Ola", "ola", "expense", "Transport"),
            arrayOf("Rapido", "rapido", "expense", "Transport"),
            arrayOf("Netflix", "netflix", "expense", "Entertainment"),
            arrayOf("Spotify", "spotify", "expense", "Entertainment"),
            arrayOf("Amazon", "amazon", "expense", "Shopping"),
            arrayOf("Flipkart", "flipkart", "expense", "Shopping"),
            arrayOf("Myntra", "myntra", "expense", "Shopping"),
            arrayOf("AJIO", "ajio", "expense", "Shopping"),
            arrayOf("IRCTC", "irctc", "expense", "Travel"),
            arrayOf("MakeMyTrip", "makemytrip", "expense", "Travel"),
            arrayOf("Zerodha", "zerodha", "investment", "Stocks"),
            arrayOf("Groww", "groww", "investment", "Other Investment"),
            arrayOf("Mutual Fund", "mutual fund", "investment", "Mutual Funds"),
            arrayOf("SIP", "sip", "investment", "Mutual Funds")
        )
        for (r in defaults) {
            db.rawQuery("SELECT COUNT(*) FROM rules WHERE keyword=? AND is_user_rule=0", arrayOf(r[1])).use { c ->
                c.moveToFirst()
                if (c.getInt(0) == 0) {
                    val v = ContentValues().apply {
                        put("merchant", r[0]); put("keyword", r[1]); put("type", r[2]); put("category", r[3]);
                        put("is_user_rule", 0); put("enabled", 1); put("created_at", now)
                    }
                    db.insert("rules", null, v)
                }
            }
        }
        settingIfMissing(db, "sms_tracking_enabled", "0")
        settingIfMissing(db, "notifications_enabled", "1")
        settingIfMissing(db, "daily_summary_enabled", "1")
        settingIfMissing(db, "daily_summary_hour", "21")
        settingIfMissing(db, "daily_summary_minute", "0")
        val b = ContentValues().apply { put("category", "__overall__"); put("amount", 30000.0); put("period", "monthly") }
        db.insertWithOnConflict("budgets", null, b, SQLiteDatabase.CONFLICT_IGNORE)
    }

    private fun settingIfMissing(db: SQLiteDatabase, key: String, value: String) {
        val v = ContentValues().apply { put("key", key); put("value", value) }
        db.insertWithOnConflict("settings", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun getSetting(key: String, fallback: String): String = readableDatabase.rawQuery("SELECT value FROM settings WHERE key=? LIMIT 1", arrayOf(key)).use { c -> if (c.moveToFirst()) c.getString(0) else fallback }

    fun findRule(fullSms: String): RuleMatch? {
        val text = fullSms.lowercase()
        readableDatabase.rawQuery("SELECT merchant,keyword,type,category FROM rules WHERE enabled=1 ORDER BY is_user_rule DESC,id ASC", null).use { c ->
            while (c.moveToNext()) {
                val keyword = c.getString(1).lowercase()
                if (keyword.isNotBlank() && text.contains(keyword)) return RuleMatch(c.getString(0), c.getString(2), c.getString(3), keyword)
            }
        }
        return null
    }

    fun insertTransaction(tx: ParsedTransaction): Long {
        val v = ContentValues().apply {
            put("amount", tx.amount); put("type", tx.type); put("category", tx.category); put("merchant", tx.merchant)
            put("source", "sms"); put("raw_message", tx.rawMessage); put("sender", tx.sender); put("payment_method", tx.paymentMethod)
            put("account_hint", tx.accountHint); put("occurred_at", tx.occurredAt); put("created_at", System.currentTimeMillis())
            put("fingerprint", tx.fingerprint); put("is_manual", 0)
        }
        return writableDatabase.insertWithOnConflict("transactions", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun currentMonthExpenseTotal(): Double {
        val r = monthRange()
        return readableDatabase.rawQuery("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE type='expense' AND occurred_at>=? AND occurred_at<?", arrayOf(r.first.toString(), r.second.toString())).use { c -> c.moveToFirst(); c.getDouble(0) }
    }

    fun currentMonthCategoryExpense(category: String): Double {
        val r = monthRange()
        return readableDatabase.rawQuery("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE type='expense' AND category=? AND occurred_at>=? AND occurred_at<?", arrayOf(category, r.first.toString(), r.second.toString())).use { c -> c.moveToFirst(); c.getDouble(0) }
    }

    fun budgetFor(category: String): Double? = readableDatabase.rawQuery("SELECT amount FROM budgets WHERE category=? LIMIT 1", arrayOf(category)).use { c -> if (c.moveToFirst()) c.getDouble(0) else null }

    fun todayTotals(): Pair<Double, Double> {
        val cal = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val start = cal.timeInMillis; cal.add(Calendar.DAY_OF_MONTH, 1); val end = cal.timeInMillis
        fun total(type: String): Double = readableDatabase.rawQuery("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE type=? AND occurred_at>=? AND occurred_at<?", arrayOf(type, start.toString(), end.toString())).use { c -> c.moveToFirst(); c.getDouble(0) }
        return total("expense") to total("investment")
    }

    private fun monthRange(): Pair<Long, Long> {
        val cal = Calendar.getInstance().apply { set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val start = cal.timeInMillis; cal.add(Calendar.MONTH, 1); return start to cal.timeInMillis
    }
}
