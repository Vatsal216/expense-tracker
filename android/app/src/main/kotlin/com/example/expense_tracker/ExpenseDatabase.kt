package com.example.expense_tracker

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.Calendar
import java.util.Locale

data class RuleMatch(val merchant: String, val type: String, val category: String, val keyword: String)

data class ParsedTransaction(
    val amount: Double,
    val type: String,
    val category: String,
    val merchant: String,
    val note: String,
    val rawMessage: String,
    val sender: String,
    val paymentMethod: String,
    val accountHint: String,
    val upiReference: String,
    val occurredAt: Long,
    val fingerprint: String,
    val classificationMethod: String = "hybrid",
    val classificationConfidence: Double = 1.0,
    val reviewStatus: String = "accepted",
)

class ExpenseDatabase(context: Context) : SQLiteOpenHelper(context, "expense_tracker.db", null, 6) {
    override fun onCreate(db: SQLiteDatabase) {
        createSchema(db)
        seed(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        createSchema(db)
        ensureColumn(db, "transactions", "note", "TEXT NOT NULL DEFAULT ''")
        ensureColumn(db, "transactions", "upi_reference", "TEXT NOT NULL DEFAULT ''")
        ensureColumn(db, "transactions", "classification_method", "TEXT NOT NULL DEFAULT 'legacy'")
        ensureColumn(db, "transactions", "classification_confidence", "REAL NOT NULL DEFAULT 1.0")
        ensureColumn(db, "transactions", "normalized_merchant", "TEXT NOT NULL DEFAULT ''")
        ensureColumn(db, "transactions", "review_status", "TEXT NOT NULL DEFAULT 'accepted'")
        ensureColumn(db, "transactions", "transfer_group_id", "TEXT NOT NULL DEFAULT ''")
        ensureColumn(db, "transactions", "dedup_cluster", "TEXT NOT NULL DEFAULT ''")
        ensureColumn(db, "transactions", "parent_transaction_id", "INTEGER")
        ensureColumn(db, "transactions", "is_split_parent", "INTEGER NOT NULL DEFAULT 0")
        seed(db)
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    private fun createSchema(db: SQLiteDatabase) {
        db.execSQL("""CREATE TABLE IF NOT EXISTS transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            category TEXT NOT NULL,
            merchant TEXT NOT NULL,
            normalized_merchant TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL,
            raw_message TEXT NOT NULL DEFAULT '',
            sender TEXT NOT NULL DEFAULT '',
            payment_method TEXT NOT NULL DEFAULT '',
            account_hint TEXT NOT NULL DEFAULT '',
            upi_reference TEXT NOT NULL DEFAULT '',
            classification_method TEXT NOT NULL DEFAULT 'legacy',
            classification_confidence REAL NOT NULL DEFAULT 1.0,
            review_status TEXT NOT NULL DEFAULT 'accepted',
            transfer_group_id TEXT NOT NULL DEFAULT '',
            dedup_cluster TEXT NOT NULL DEFAULT '',
            parent_transaction_id INTEGER,
            is_split_parent INTEGER NOT NULL DEFAULT 0,
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
        db.execSQL("""CREATE TABLE IF NOT EXISTS merchant_aliases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pattern TEXT NOT NULL UNIQUE,
            normalized_name TEXT NOT NULL
        )""".trimIndent())
        db.execSQL("""CREATE TABLE IF NOT EXISTS review_feedback(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER,
            original_type TEXT NOT NULL DEFAULT '',
            final_type TEXT NOT NULL DEFAULT '',
            original_category TEXT NOT NULL DEFAULT '',
            final_category TEXT NOT NULL DEFAULT '',
            action TEXT NOT NULL DEFAULT 'corrected',
            created_at INTEGER NOT NULL
        )""".trimIndent())
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_native_amount_time ON transactions(amount, occurred_at)")
    }

    private fun ensureColumn(db: SQLiteDatabase, table: String, column: String, definition: String) {
        val exists = db.rawQuery("PRAGMA table_info($table)", null).use { c ->
            val nameIndex = c.getColumnIndex("name")
            var found = false
            while (c.moveToNext()) {
                if (nameIndex >= 0 && c.getString(nameIndex) == column) { found = true; break }
            }
            found
        }
        if (!exists) db.execSQL("ALTER TABLE $table ADD COLUMN $column $definition")
    }

    private fun seed(db: SQLiteDatabase) {
        val now = System.currentTimeMillis()
        val categories = listOf(
            "Food & Dining" to "expense", "Groceries" to "expense", "Transport" to "expense",
            "Shopping" to "expense", "Entertainment" to "expense", "Bills & Utilities" to "expense",
            "Healthcare" to "expense", "Travel" to "expense", "Education" to "expense",
            "Rent & Housing" to "expense", "EMI & Loans" to "expense", "Insurance" to "expense",
            "Stocks" to "investment", "Mutual Funds" to "investment", "Gold" to "investment",
            "Other Investment" to "investment", "Salary" to "income", "Refund" to "refund",
            "Transfer" to "transfer", "Credit Card Payment" to "transfer", "Uncategorized" to "expense"
        )
        for ((name, kind) in categories) {
            val v = ContentValues().apply { put("name", name); put("kind", kind); put("is_system", 1); put("created_at", now) }
            db.insertWithOnConflict("categories", null, v, SQLiteDatabase.CONFLICT_IGNORE)
        }

        val defaults = listOf(
            arrayOf("Zomato", "zomato", "expense", "Food & Dining"), arrayOf("Swiggy", "swiggy", "expense", "Food & Dining"),
            arrayOf("Blinkit", "blinkit", "expense", "Groceries"), arrayOf("Zepto", "zepto", "expense", "Groceries"),
            arrayOf("BigBasket", "bigbasket", "expense", "Groceries"), arrayOf("Uber", "uber", "expense", "Transport"),
            arrayOf("Ola", "ola", "expense", "Transport"), arrayOf("Rapido", "rapido", "expense", "Transport"),
            arrayOf("Netflix", "netflix", "expense", "Entertainment"), arrayOf("Spotify", "spotify", "expense", "Entertainment"),
            arrayOf("Amazon", "amazon", "expense", "Shopping"), arrayOf("Flipkart", "flipkart", "expense", "Shopping"),
            arrayOf("Myntra", "myntra", "expense", "Shopping"), arrayOf("AJIO", "ajio", "expense", "Shopping"),
            arrayOf("IRCTC", "irctc", "expense", "Travel"), arrayOf("MakeMyTrip", "makemytrip", "expense", "Travel"),
            arrayOf("Zerodha", "zerodha", "investment", "Stocks"), arrayOf("Groww", "groww", "investment", "Other Investment"),
            arrayOf("Mutual Fund", "mutual fund", "investment", "Mutual Funds"), arrayOf("SIP", "sip", "investment", "Mutual Funds")
        )
        for (r in defaults) {
            db.rawQuery("SELECT COUNT(*) FROM rules WHERE keyword=? AND is_user_rule=0", arrayOf(r[1])).use { c ->
                c.moveToFirst()
                if (c.getInt(0) == 0) {
                    val v = ContentValues().apply {
                        put("merchant", r[0]); put("keyword", r[1]); put("type", r[2]); put("category", r[3])
                        put("is_user_rule", 0); put("enabled", 1); put("created_at", now)
                    }
                    db.insert("rules", null, v)
                }
            }
        }

        val aliases = mapOf(
            "zomato" to "Zomato", "swiggy" to "Swiggy", "blinkit" to "Blinkit", "zepto" to "Zepto",
            "amazon" to "Amazon", "amzn" to "Amazon", "flipkart" to "Flipkart", "myntra" to "Myntra",
            "uber" to "Uber", "rapido" to "Rapido", "netflix" to "Netflix", "spotify" to "Spotify",
            "phonepe" to "PhonePe", "gpay" to "Google Pay", "google pay" to "Google Pay", "paytm" to "Paytm",
            "zerodha" to "Zerodha", "groww" to "Groww"
        )
        for ((pattern, normalized) in aliases) {
            val v = ContentValues().apply { put("pattern", pattern); put("normalized_name", normalized) }
            db.insertWithOnConflict("merchant_aliases", null, v, SQLiteDatabase.CONFLICT_IGNORE)
        }

        settingIfMissing(db, "sms_tracking_enabled", "0")
        settingIfMissing(db, "phonepe_notification_enabled", "0")
        settingIfMissing(db, "notifications_enabled", "1")
        settingIfMissing(db, "daily_summary_enabled", "1")
        settingIfMissing(db, "daily_summary_hour", "21")
        settingIfMissing(db, "daily_summary_minute", "0")
        settingIfMissing(db, "hybrid_classifier_enabled", "1")
        settingIfMissing(db, "classifier_confidence_threshold", "0.56")
        settingIfMissing(db, "learn_from_corrections", "1")
        settingIfMissing(db, "smart_dedup_enabled", "1")
        settingIfMissing(db, "smart_transfer_matching", "1")
        settingIfMissing(db, "smart_alerts_enabled", "1")

        val b = ContentValues().apply { put("category", "__overall__"); put("amount", 30000.0); put("period", "monthly") }
        db.insertWithOnConflict("budgets", null, b, SQLiteDatabase.CONFLICT_IGNORE)
    }

    private fun settingIfMissing(db: SQLiteDatabase, key: String, value: String) {
        val v = ContentValues().apply { put("key", key); put("value", value) }
        db.insertWithOnConflict("settings", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun getSetting(key: String, fallback: String): String = readableDatabase
        .rawQuery("SELECT value FROM settings WHERE key=? LIMIT 1", arrayOf(key))
        .use { c -> if (c.moveToFirst()) c.getString(0) else fallback }

    fun findRule(fullText: String): RuleMatch? {
        val text = fullText.lowercase(Locale.ROOT)
        readableDatabase.rawQuery("SELECT merchant,keyword,type,category FROM rules WHERE enabled=1 ORDER BY is_user_rule DESC,id ASC", null).use { c ->
            while (c.moveToNext()) {
                val keyword = c.getString(1).lowercase(Locale.ROOT)
                if (keyword.isNotBlank() && text.contains(keyword)) return RuleMatch(c.getString(0), c.getString(2), c.getString(3), keyword)
            }
        }
        return null
    }

    fun normalizeMerchant(merchant: String): String {
        val lower = merchant.lowercase(Locale.ROOT).trim()
        readableDatabase.rawQuery("SELECT pattern,normalized_name FROM merchant_aliases ORDER BY LENGTH(pattern) DESC", null).use { c ->
            while (c.moveToNext()) {
                val pattern = c.getString(0).lowercase(Locale.ROOT)
                if (pattern.isNotBlank() && lower.contains(pattern)) return c.getString(1)
            }
        }
        return merchant.replace(Regex("[@_*\\-]+"), " ")
            .replace(Regex("(?i)\\b(?:upi|payment|payments|pvt|private|limited|ltd|india|online|store|stores)\\b"), "")
            .replace(Regex("\\s+"), " ").trim().ifBlank { merchant.trim() }
    }

    private fun likelyDuplicate(tx: ParsedTransaction, source: String, normalized: String): Boolean {
        if (getSetting("smart_dedup_enabled", "1") != "1") return false
        val start = tx.occurredAt - 5 * 60 * 1000L
        val end = tx.occurredAt + 5 * 60 * 1000L
        readableDatabase.rawQuery(
            "SELECT source,upi_reference,normalized_merchant,merchant FROM transactions WHERE review_status<>'ignored' AND amount BETWEEN ? AND ? AND occurred_at>=? AND occurred_at<=?",
            arrayOf((tx.amount - 0.01).toString(), (tx.amount + 0.01).toString(), start.toString(), end.toString())
        ).use { c ->
            while (c.moveToNext()) {
                val existingSource = c.getString(0)
                val ref = c.getString(1).orEmpty()
                val existingNormalized = c.getString(2).orEmpty().ifBlank { normalizeMerchant(c.getString(3).orEmpty()) }
                if (tx.upiReference.isNotBlank() && ref == tx.upiReference) return true
                if (source != existingSource && normalized.equals(existingNormalized, ignoreCase = true)) return true
            }
        }
        return false
    }

    fun insertTransaction(tx: ParsedTransaction, source: String): Long {
        val normalized = normalizeMerchant(tx.merchant)
        if (likelyDuplicate(tx, source, normalized)) return -2L
        val v = ContentValues().apply {
            put("amount", tx.amount); put("type", tx.type); put("category", tx.category); put("merchant", tx.merchant)
            put("normalized_merchant", normalized); put("note", tx.note); put("source", source); put("raw_message", tx.rawMessage)
            put("sender", tx.sender); put("payment_method", tx.paymentMethod); put("account_hint", tx.accountHint); put("upi_reference", tx.upiReference)
            put("classification_method", tx.classificationMethod); put("classification_confidence", tx.classificationConfidence); put("review_status", tx.reviewStatus)
            put("occurred_at", tx.occurredAt); put("created_at", System.currentTimeMillis()); put("fingerprint", tx.fingerprint); put("is_manual", 0)
        }
        return writableDatabase.insertWithOnConflict("transactions", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun reclassifyStoredSms(): Map<String, Int> {
        var checked = 0
        var updated = 0
        var ignored = 0
        var unchanged = 0

        val rows = mutableListOf<List<Any>>()
        readableDatabase.rawQuery(
            """SELECT id,sender,raw_message,occurred_at,type,category,merchant,classification_method
               FROM transactions
               WHERE source='sms' AND is_manual=0 AND raw_message<>''
                 AND classification_method NOT IN ('user_corrected','notification_action')""".trimIndent(),
            null,
        ).use { c ->
            while (c.moveToNext()) {
                rows += listOf(
                    c.getLong(0), c.getString(1).orEmpty(), c.getString(2).orEmpty(), c.getLong(3),
                    c.getString(4).orEmpty(), c.getString(5).orEmpty(), c.getString(6).orEmpty(), c.getString(7).orEmpty(),
                )
            }
        }

        for (row in rows) {
            checked++
            val id = row[0] as Long
            val sender = row[1] as String
            val raw = row[2] as String
            val occurredAt = row[3] as Long
            val oldType = row[4] as String
            val oldCategory = row[5] as String
            val oldMerchant = row[6] as String
            val oldMethod = row[7] as String

            val parsed = TransactionParser.parseSms(this, sender, raw, occurredAt)
            if (parsed == null) {
                val values = ContentValues().apply {
                    put("review_status", "ignored")
                    put("classification_method", "reclassified_ignored")
                    put("classification_confidence", 1.0)
                }
                writableDatabase.update("transactions", values, "id=?", arrayOf(id.toString()))
                ignored++
                continue
            }

            val normalized = normalizeMerchant(parsed.merchant)
            val changed = oldType != parsed.type || oldCategory != parsed.category ||
                oldMerchant != parsed.merchant || oldMethod != parsed.classificationMethod
            val values = ContentValues().apply {
                put("amount", parsed.amount)
                put("type", parsed.type)
                put("category", parsed.category)
                put("merchant", parsed.merchant)
                put("normalized_merchant", normalized)
                put("note", parsed.note)
                put("payment_method", parsed.paymentMethod)
                put("account_hint", parsed.accountHint)
                put("upi_reference", parsed.upiReference)
                put("classification_method", parsed.classificationMethod)
                put("classification_confidence", parsed.classificationConfidence)
                put("review_status", parsed.reviewStatus)
            }
            writableDatabase.update("transactions", values, "id=?", arrayOf(id.toString()))
            if (changed) updated++ else unchanged++
        }

        return mapOf("checked" to checked, "updated" to updated, "ignored" to ignored, "unchanged" to unchanged)
    }

    fun applyNotificationAction(transactionId: Long, action: String) {
        var originalType = ""
        var originalCategory = ""
        readableDatabase.rawQuery(
            "SELECT type,category FROM transactions WHERE id=? LIMIT 1",
            arrayOf(transactionId.toString())
        ).use { c ->
            if (c.moveToFirst()) {
                originalType = c.getString(0).orEmpty()
                originalCategory = c.getString(1).orEmpty()
            }
        }

        var finalType = originalType
        var finalCategory = originalCategory
        var feedbackAction = "corrected"
        when (action) {
            "food" -> {
                finalType = "expense"; finalCategory = "Food & Dining"; feedbackAction = "corrected"
                writableDatabase.update("transactions", ContentValues().apply { put("type", finalType); put("category", finalCategory); put("review_status", "accepted"); put("classification_method", "notification_action") }, "id=?", arrayOf(transactionId.toString()))
            }
            "shopping" -> {
                finalType = "expense"; finalCategory = "Shopping"; feedbackAction = "corrected"
                writableDatabase.update("transactions", ContentValues().apply { put("type", finalType); put("category", finalCategory); put("review_status", "accepted"); put("classification_method", "notification_action") }, "id=?", arrayOf(transactionId.toString()))
            }
            "transfer" -> {
                finalType = "transfer"; finalCategory = "Transfer"; feedbackAction = "corrected"
                writableDatabase.update("transactions", ContentValues().apply { put("type", finalType); put("category", finalCategory); put("review_status", "accepted"); put("classification_method", "notification_action") }, "id=?", arrayOf(transactionId.toString()))
            }
            "ignore" -> {
                feedbackAction = "ignored"
                writableDatabase.update("transactions", ContentValues().apply { put("review_status", "ignored"); put("classification_method", "notification_action") }, "id=?", arrayOf(transactionId.toString()))
            }
            else -> return
        }

        writableDatabase.insert("review_feedback", null, ContentValues().apply {
            put("transaction_id", transactionId)
            put("original_type", originalType)
            put("final_type", finalType)
            put("original_category", originalCategory)
            put("final_category", finalCategory)
            put("action", feedbackAction)
            put("created_at", System.currentTimeMillis())
        })
    }

    fun currentMonthExpenseTotal(): Double {
        val r = monthRange()
        return readableDatabase.rawQuery("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE review_status='accepted' AND type='expense' AND occurred_at>=? AND occurred_at<?", arrayOf(r.first.toString(), r.second.toString())).use { c -> c.moveToFirst(); c.getDouble(0) }
    }

    fun currentMonthCategoryExpense(category: String): Double {
        val r = monthRange()
        return readableDatabase.rawQuery("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE review_status='accepted' AND type='expense' AND category=? AND occurred_at>=? AND occurred_at<?", arrayOf(category, r.first.toString(), r.second.toString())).use { c -> c.moveToFirst(); c.getDouble(0) }
    }

    fun budgetFor(category: String): Double? = readableDatabase.rawQuery("SELECT amount FROM budgets WHERE category=? LIMIT 1", arrayOf(category)).use { c -> if (c.moveToFirst()) c.getDouble(0) else null }

    fun todayTotals(): Pair<Double, Double> {
        val cal = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val start = cal.timeInMillis; cal.add(Calendar.DAY_OF_MONTH, 1); val end = cal.timeInMillis
        fun total(type: String): Double = readableDatabase.rawQuery("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE review_status='accepted' AND type=? AND occurred_at>=? AND occurred_at<?", arrayOf(type, start.toString(), end.toString())).use { c -> c.moveToFirst(); c.getDouble(0) }
        return total("expense") to total("investment")
    }

    fun widgetSummary(): Triple<Double, Double, Double> {
        val expense = currentMonthExpenseTotal()
        val budget = budgetFor("__overall__") ?: 0.0
        return Triple(expense, budget, (budget - expense).coerceAtLeast(0.0))
    }

    private fun monthRange(): Pair<Long, Long> {
        val cal = Calendar.getInstance().apply { set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val start = cal.timeInMillis; cal.add(Calendar.MONTH, 1); return start to cal.timeInMillis
    }
}
