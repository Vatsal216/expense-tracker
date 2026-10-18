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

class ExpenseDatabase(context: Context) : SQLiteOpenHelper(context, "expense_tracker.db", null, 7) {
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
        db.execSQL("""CREATE TABLE IF NOT EXISTS transaction_evidence(
            id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER NOT NULL,
            source TEXT NOT NULL, external_id TEXT NOT NULL, source_label TEXT NOT NULL DEFAULT '',
            occurred_at INTEGER NOT NULL, amount REAL NOT NULL, merchant_hint TEXT NOT NULL DEFAULT '',
            reference_hint TEXT NOT NULL DEFAULT '', metadata_json TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
            UNIQUE(source, external_id), FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
        )""".trimIndent())
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
        db.execSQL("""CREATE TABLE IF NOT EXISTS recurring_rules(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            merchant_key TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            category TEXT NOT NULL,
            frequency TEXT NOT NULL DEFAULT 'Monthly',
            enabled INTEGER NOT NULL DEFAULT 1,
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
        settingIfMissing(db, "notification_tracking_packages", "")
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
            .replace(Regex("[^a-z0-9@& ]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        readableDatabase.rawQuery("SELECT merchant,keyword,type,category FROM rules WHERE enabled=1 ORDER BY is_user_rule DESC,id ASC", null).use { c ->
            while (c.moveToNext()) {
                val keyword = c.getString(1).lowercase(Locale.ROOT).trim()
                if (keyword.isBlank()) continue
                // v22 user-learning rules may contain a conjunction such as
                // "zarivault&&subscription&&autopay". Every stable token must
                // be present, preventing a broad bank-name rule (e.g. ICICI)
                // from relabeling unrelated transactions.
                val parts = keyword.split("&&").map { it.trim() }.filter { it.isNotBlank() }
                val matches = parts.isNotEmpty() && parts.all { text.contains(it) }
                if (matches) return RuleMatch(c.getString(0), c.getString(2), c.getString(3), keyword)
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

    private data class DuplicateCandidate(
        val id: Long,
        val source: String,
        val type: String,
        val category: String,
        val merchant: String,
        val normalizedMerchant: String,
        val note: String,
        val rawMessage: String,
        val sender: String,
        val paymentMethod: String,
        val accountHint: String,
        val upiReference: String,
        val classificationMethod: String,
        val classificationConfidence: Double,
        val occurredAt: Long,
    )

    private fun isNotificationSource(source: String): Boolean = source.endsWith("_notification")

    private fun isUpiLike(paymentMethod: String, rawMessage: String, merchant: String): Boolean {
        val text = "$paymentMethod $rawMessage $merchant".lowercase(Locale.ROOT)
        return listOf("upi", "gpay", "google pay", "phonepe", "paytm", "@ybl", "@ibl", "@ok", "@upi")
            .any { text.contains(it) }
    }

    private fun classificationRank(method: String, category: String, confidence: Double): Double {
        val base = when (method) {
            "user_corrected" -> 100.0
            "notification_action" -> 95.0
            "merchant_rule" -> 85.0
            "context_override" -> 78.0
            "hard_gate" -> 75.0
            "neural" -> 65.0
            "upi_intent" -> 90.0
            else -> 50.0
        }
        val categoryBonus = if (category.isNotBlank() && !category.equals("Uncategorized", ignoreCase = true)) 20.0 else 0.0
        return base + categoryBonus + confidence.coerceIn(0.0, 1.0)
    }

    private fun merchantScore(merchant: String): Int {
        val m = merchant.trim()
        if (m.isBlank()) return -100
        val lower = m.lowercase(Locale.ROOT)
        var score = 20
        if (lower == "unknown" || lower == "phonepe" || lower == "google pay" || lower == "gpay" || lower == "paytm") score -= 25
        if (Regex("(?i)^(?:gpay|phonepe|paytm)[-_ ]?\\d+").containsMatchIn(m)) score -= 35
        if (Regex("\\d{7,}").containsMatchIn(m)) score -= 12
        if (m.count { it.isLetter() } >= 5) score += 10
        if (m.contains(' ')) score += 5
        return score
    }

    private fun findDuplicateCandidate(tx: ParsedTransaction, source: String, normalized: String): DuplicateCandidate? {
        if (getSetting("smart_dedup_enabled", "1") != "1") return null
        // Email receipts can arrive long after an SMS/app alert.  Keep the
        // wider Gmail window strict by also requiring merchant/card/reference
        // evidence below, so equal-value unrelated purchases never collapse.
        val gmailWindow = source == "gmail"
        val windowMs = if (gmailWindow) 36 * 60 * 60 * 1000L else 10 * 60 * 1000L
        val start = tx.occurredAt - windowMs
        val end = tx.occurredAt + windowMs
        var best: DuplicateCandidate? = null
        var bestScore = Long.MIN_VALUE

        readableDatabase.rawQuery(
            """SELECT id,source,type,category,merchant,normalized_merchant,note,raw_message,sender,payment_method,
                      account_hint,upi_reference,classification_method,classification_confidence,occurred_at
               FROM transactions
               WHERE review_status<>'ignored' AND amount BETWEEN ? AND ? AND occurred_at>=? AND occurred_at<=?""".trimIndent(),
            arrayOf((tx.amount - 0.01).toString(), (tx.amount + 0.01).toString(), start.toString(), end.toString())
        ).use { c ->
            while (c.moveToNext()) {
                val candidate = DuplicateCandidate(
                    id = c.getLong(0), source = c.getString(1).orEmpty(), type = c.getString(2).orEmpty(), category = c.getString(3).orEmpty(),
                    merchant = c.getString(4).orEmpty(), normalizedMerchant = c.getString(5).orEmpty(), note = c.getString(6).orEmpty(),
                    rawMessage = c.getString(7).orEmpty(), sender = c.getString(8).orEmpty(), paymentMethod = c.getString(9).orEmpty(),
                    accountHint = c.getString(10).orEmpty(), upiReference = c.getString(11).orEmpty(), classificationMethod = c.getString(12).orEmpty(),
                    classificationConfidence = c.getDouble(13), occurredAt = c.getLong(14),
                )
                val diff = kotlin.math.abs(candidate.occurredAt - tx.occurredAt)
                val exactRef = tx.upiReference.isNotBlank() && candidate.upiReference.isNotBlank() &&
                    tx.upiReference.equals(candidate.upiReference, ignoreCase = true)

                if (exactRef) {
                    val score = 1000000L - diff
                    if (score > bestScore) { best = candidate; bestScore = score }
                    continue
                }

                val candidateIsGmail = candidate.source == "gmail"
                val crossSource = (source == "sms" && isNotificationSource(candidate.source)) ||
                    (candidate.source == "sms" && isNotificationSource(source)) ||
                    (source == "gmail" && candidate.source != "gmail") ||
                    (candidateIsGmail && source != "gmail")
                if (!crossSource) continue

                if (candidate.accountHint.isNotBlank() && tx.accountHint.isNotBlank() && candidate.accountHint != tx.accountHint) continue

                val userCorrected = candidate.classificationMethod == "user_corrected" || tx.classificationMethod == "user_corrected"
                if (!userCorrected && candidate.type != tx.type) continue

                val candidateNormalized = candidate.normalizedMerchant.ifBlank { normalizeMerchant(candidate.merchant) }
                val merchantMatch = candidateNormalized.equals(normalized, ignoreCase = true)
                val upiMatch = isUpiLike(candidate.paymentMethod, candidate.rawMessage, candidate.merchant) &&
                    isUpiLike(tx.paymentMethod, tx.rawMessage, tx.merchant)

                val usesGmail = source == "gmail" || candidateIsGmail
                val cardMatch = candidate.accountHint.isNotBlank() && tx.accountHint.isNotBlank() && candidate.accountHint == tx.accountHint
                val qualifies = when {
                    usesGmail && merchantMatch && diff <= 36 * 60 * 60 * 1000L -> true
                    usesGmail && cardMatch && diff <= 24 * 60 * 60 * 1000L -> true
                    merchantMatch && diff <= 5 * 60 * 1000L -> true
                    upiMatch && diff <= 3 * 60 * 1000L -> true
                    else -> false
                }
                if (!qualifies) continue

                val score = when {
                    merchantMatch -> 800000L - diff
                    else -> 600000L - diff
                }
                if (score > bestScore) { best = candidate; bestScore = score }
            }
        }
        return best
    }

    private fun mergeDuplicate(existing: DuplicateCandidate, incoming: ParsedTransaction, incomingSource: String, incomingNormalized: String): Long {
        val existingRank = classificationRank(existing.classificationMethod, existing.category, existing.classificationConfidence)
        val incomingRank = classificationRank(incoming.classificationMethod, incoming.category, incoming.classificationConfidence)
        val incomingClassificationWins = incomingRank > existingRank

        val chosenType = if (incomingClassificationWins) incoming.type else existing.type
        val chosenCategory = if (incomingClassificationWins) incoming.category else existing.category
        val chosenMethod = if (incomingClassificationWins) incoming.classificationMethod else existing.classificationMethod
        val chosenConfidence = if (incomingClassificationWins) incoming.classificationConfidence else existing.classificationConfidence

        val existingMerchantScore = merchantScore(existing.merchant)
        val incomingMerchantScore = merchantScore(incoming.merchant)
        val chosenMerchant = when {
            incomingSource == "sms" && incomingMerchantScore >= 0 -> incoming.merchant
            existing.source == "sms" && existingMerchantScore >= 0 -> existing.merchant
            incomingMerchantScore > existingMerchantScore -> incoming.merchant
            else -> existing.merchant
        }.ifBlank { existing.merchant.ifBlank { incoming.merchant } }
        val chosenNormalized = normalizeMerchant(chosenMerchant).ifBlank {
            if (incomingNormalized.isNotBlank()) incomingNormalized else existing.normalizedMerchant
        }

        val smsIsIncoming = incomingSource == "sms"
        val smsIsExisting = existing.source == "sms"
        val chosenSource = if (smsIsIncoming || smsIsExisting) "sms" else existing.source
        val chosenRaw = when {
            smsIsIncoming && incoming.rawMessage.isNotBlank() -> incoming.rawMessage
            smsIsExisting && existing.rawMessage.isNotBlank() -> existing.rawMessage
            existing.rawMessage.isNotBlank() -> existing.rawMessage
            else -> incoming.rawMessage
        }
        val chosenSender = when {
            smsIsIncoming && incoming.sender.isNotBlank() -> incoming.sender
            smsIsExisting && existing.sender.isNotBlank() -> existing.sender
            existing.sender.isNotBlank() -> existing.sender
            else -> incoming.sender
        }
        val chosenAccount = when {
            smsIsIncoming && incoming.accountHint.isNotBlank() -> incoming.accountHint
            smsIsExisting && existing.accountHint.isNotBlank() -> existing.accountHint
            existing.accountHint.isNotBlank() -> existing.accountHint
            else -> incoming.accountHint
        }
        val chosenPaymentMethod = when {
            existing.paymentMethod.contains("UPI", ignoreCase = true) || incoming.paymentMethod.contains("UPI", ignoreCase = true) -> "UPI"
            existing.paymentMethod.isNotBlank() -> existing.paymentMethod
            else -> incoming.paymentMethod
        }
        val chosenRef = existing.upiReference.ifBlank { incoming.upiReference }
        val chosenNote = existing.note.ifBlank { incoming.note }
        val chosenOccurredAt = when {
            smsIsIncoming -> incoming.occurredAt
            smsIsExisting -> existing.occurredAt
            else -> minOf(existing.occurredAt, incoming.occurredAt)
        }
        val cluster = "cross-source-${existing.id}-${chosenOccurredAt / 60000}"

        val values = ContentValues().apply {
            put("type", chosenType); put("category", chosenCategory); put("merchant", chosenMerchant); put("normalized_merchant", chosenNormalized)
            put("note", chosenNote); put("source", chosenSource); put("raw_message", chosenRaw); put("sender", chosenSender)
            put("payment_method", chosenPaymentMethod); put("account_hint", chosenAccount); put("upi_reference", chosenRef)
            put("classification_method", chosenMethod); put("classification_confidence", chosenConfidence)
            put("review_status", "accepted"); put("dedup_cluster", cluster); put("occurred_at", chosenOccurredAt)
        }
        writableDatabase.update("transactions", values, "id=?", arrayOf(existing.id.toString()))

        // A correction learned from either source should also teach the alternate merchant wording.
        if (chosenMethod == "user_corrected") {
            setOf(existing.merchant, incoming.merchant, chosenMerchant).forEach { merchantText ->
                val keyword = normalizeMerchant(merchantText).trim().lowercase(Locale.ROOT)
                if (keyword.length >= 3 && !keyword.equals("unknown", ignoreCase = true)) {
                    val already = readableDatabase.rawQuery(
                        "SELECT COUNT(*) FROM rules WHERE LOWER(keyword)=? AND is_user_rule=1",
                        arrayOf(keyword)
                    ).use { c -> c.moveToFirst() && c.getInt(0) > 0 }
                    if (!already) {
                        val rule = ContentValues().apply {
                            put("merchant", chosenMerchant); put("keyword", keyword); put("type", chosenType); put("category", chosenCategory)
                            put("is_user_rule", 1); put("enabled", 1); put("created_at", System.currentTimeMillis())
                        }
                        writableDatabase.insert("rules", null, rule)
                    }
                }
            }
        }
        return existing.id
    }

    private fun addEvidence(transactionId: Long, source: String, externalId: String, tx: ParsedTransaction) {
        if (transactionId <= 0 || externalId.isBlank()) return
        val values = ContentValues().apply {
            put("transaction_id", transactionId); put("source", source); put("external_id", externalId)
            put("source_label", tx.sender); put("occurred_at", tx.occurredAt); put("amount", tx.amount)
            put("merchant_hint", tx.merchant); put("reference_hint", tx.upiReference); put("metadata_json", "")
            put("created_at", System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict("transaction_evidence", null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun insertTransaction(tx: ParsedTransaction, source: String): Long {
        val normalized = normalizeMerchant(tx.merchant)
        val duplicate = findDuplicateCandidate(tx, source, normalized)
        if (duplicate != null) {
            val canonicalId = mergeDuplicate(duplicate, tx, source, normalized)
            addEvidence(canonicalId, source, tx.fingerprint, tx)
            return -canonicalId
        }
        val v = ContentValues().apply {
            put("amount", tx.amount); put("type", tx.type); put("category", tx.category); put("merchant", tx.merchant)
            put("normalized_merchant", normalized); put("note", tx.note); put("source", source); put("raw_message", tx.rawMessage)
            put("sender", tx.sender); put("payment_method", tx.paymentMethod); put("account_hint", tx.accountHint); put("upi_reference", tx.upiReference)
            put("classification_method", tx.classificationMethod); put("classification_confidence", tx.classificationConfidence); put("review_status", tx.reviewStatus)
            put("occurred_at", tx.occurredAt); put("created_at", System.currentTimeMillis()); put("fingerprint", tx.fingerprint); put("is_manual", 0)
        }
        val id = writableDatabase.insertWithOnConflict("transactions", null, v, SQLiteDatabase.CONFLICT_IGNORE)
        if (id > 0) addEvidence(id, source, tx.fingerprint, tx)
        return id
    }

    fun ingestGmailEmail(messageId: String, sender: String, subject: String, body: String, occurredAt: Long): Map<String, Any> {
        val parsed = TransactionParser.parseGmail(this, messageId, sender, subject, body, occurredAt)
            ?: return mapOf("status" to "ignored")
        val id = insertTransaction(parsed, "gmail")
        return when {
            id > 0 -> mapOf("status" to "imported", "transactionId" to id)
            id < -1 -> mapOf("status" to "merged", "transactionId" to -id)
            else -> mapOf("status" to "duplicate")
        }
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
