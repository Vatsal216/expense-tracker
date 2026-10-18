package com.example.expense_tracker

import java.security.MessageDigest
import java.util.Locale

object TransactionParser {
    private val amountRegex = Regex("(?i)(?:₹|rs\\.?|inr)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)")
    private val upiRefRegex = Regex("(?i)(?:upi(?: ref(?:erence)?| txn)?|utr|ref(?:erence)?)[^A-Za-z0-9]*([A-Za-z0-9]{6,})")
    private val accountRegex = Regex("(?i)(?:a/c|acct|account|card)[^0-9]*[xX*]*([0-9]{3,4})")
    private val noteRegex = Regex("(?i)(?:note|remark|message)\\s*[:=-]\\s*([^|,;]+)")
    private val toRegex = Regex("(?i)(?:to|at)\\s+([A-Za-z0-9 .&'_-]{2,40})")

    fun parseSms(db: ExpenseDatabase, sender: String, message: String, occurredAt: Long): ParsedTransaction? {
        val text = message.trim()
        if (text.isBlank()) return null
        val amount = extractAmount(text) ?: return null
        val lower = text.lowercase(Locale.ROOT)
        val rule = db.findRule(text)
        val decision = classify(db, text, rule)
        if (decision.label == "ignore" || decision.label == "pending") return null

        val category = categoryFor(decision.label, lower, rule)
        val cardPayment = decision.label == "transfer" && isCreditCardBillPayment(lower)
        val merchant = if (cardPayment) {
            extractCreditCardMerchant(text) ?: "Credit Card Payment"
        } else {
            rule?.merchant ?: extractMerchant(text) ?: sender.ifBlank { "Unknown" }
        }
        val note = extractNote(text)
        val upiReference = upiRefRegex.find(text)?.groupValues?.getOrNull(1).orEmpty()
        val accountHint = accountRegex.find(text)?.groupValues?.getOrNull(1).orEmpty()
        val paymentMethod = when {
            cardPayment -> "Bank → Credit Card"
            lower.contains("upi") -> "UPI"
            lower.contains("card") -> "Card"
            else -> "Bank"
        }
        val fingerprint = fingerprint("sms|$sender|$amount|${decision.label}|$merchant|${occurredAt / 60000}|$upiReference")
        return ParsedTransaction(
            amount = amount,
            type = decision.label,
            category = category,
            merchant = merchant,
            note = note,
            rawMessage = text,
            sender = sender,
            paymentMethod = paymentMethod,
            accountHint = accountHint,
            upiReference = upiReference,
            occurredAt = occurredAt,
            fingerprint = fingerprint,
            classificationMethod = decision.method,
            classificationConfidence = decision.confidence,
            reviewStatus = if (decision.method == "low_confidence_review") "needs_review" else "accepted",
        )
    }

    /**
     * Gmail content is classified by the exact same hybrid classifier and user
     * rules as SMS.  The email text is deliberately not persisted: it is only
     * used in-memory to create a privacy-safe ledger record.
     */
    fun parseGmail(db: ExpenseDatabase, messageId: String, sender: String, subject: String, body: String, occurredAt: Long): ParsedTransaction? {
        val text = "$subject | $body".replace(Regex("\\s+"), " ").trim()
        if (text.isBlank() || Regex("(?i)\\b(otp|one.time.password|verification code|unsubscribe|cashback offer)\\b").containsMatchIn(text)) return null
        val amount = extractAmount(text) ?: return null
        val lower = text.lowercase(Locale.ROOT)
        if (!Regex("(?i)\\b(debited|spent|payment successful|transaction successful|paid|credited|refund|reversed)\\b").containsMatchIn(text)) return null
        val rule = db.findRule(text)
        val decision = classify(db, text, rule)
        if (decision.label == "ignore" || decision.label == "pending") return null
        val category = categoryFor(decision.label, lower, rule)
        val cardPayment = decision.label == "transfer" && isCreditCardBillPayment(lower)
        val merchant = if (cardPayment) extractCreditCardMerchant(text) ?: "Credit Card Payment" else rule?.merchant ?: extractMerchant(text) ?: sender.ifBlank { "Email payment" }
        val upiReference = upiRefRegex.find(text)?.groupValues?.getOrNull(1).orEmpty()
        val accountHint = accountRegex.find(text)?.groupValues?.getOrNull(1).orEmpty()
        val method = when { cardPayment -> "Bank → Credit Card"; lower.contains("upi") -> "UPI"; lower.contains("card") -> "Card"; else -> "Bank" }
        return ParsedTransaction(amount, decision.label, category, merchant, extractNote(text), "", sender, method, accountHint, upiReference,
            occurredAt, fingerprint("gmail|$messageId"), decision.method, decision.confidence,
            if (decision.method == "low_confidence_review") "needs_review" else "accepted")
    }

    fun parsePhonePeNotification(db: ExpenseDatabase, title: String, body: String, occurredAt: Long, appName: String = "PhonePe"): ParsedTransaction? {
        val text = listOf(title, body).filter { it.isNotBlank() }.joinToString(" | ").trim()
        if (text.isBlank()) return null
        val amount = extractAmount(text) ?: return null
        val lower = text.lowercase(Locale.ROOT)
        val rule = db.findRule(text)
        val decision = classify(db, text, rule)
        if (decision.label == "ignore" || decision.label == "pending") return null

        val category = categoryFor(decision.label, lower, rule)
        val merchant = rule?.merchant ?: extractMerchant(text) ?: title.ifBlank { "PhonePe" }
        val note = extractNote(text)
        val upiReference = upiRefRegex.find(text)?.groupValues?.getOrNull(1).orEmpty()
        val fingerprint = fingerprint("notification|$appName|$amount|${decision.label}|$merchant|${occurredAt / 60000}|$upiReference|$text")
        return ParsedTransaction(
            amount = amount,
            type = decision.label,
            category = category,
            merchant = merchant,
            note = note,
            rawMessage = text,
            sender = appName,
            paymentMethod = "UPI / $appName",
            accountHint = "",
            upiReference = upiReference,
            occurredAt = occurredAt,
            fingerprint = fingerprint,
            classificationMethod = decision.method,
            classificationConfidence = decision.confidence,
            reviewStatus = if (decision.method == "low_confidence_review") "needs_review" else "accepted",
        )
    }

    private fun classify(db: ExpenseDatabase, text: String, rule: RuleMatch?): HybridDecision {
        val enabled = db.getSetting("hybrid_classifier_enabled", "1") == "1"
        val threshold = db.getSetting("classifier_confidence_threshold", "0.56").toDoubleOrNull()?.coerceIn(0.40, 0.95) ?: 0.56
        return HybridMessageClassifier.classify(
            text = text,
            rule = rule,
            threshold = threshold,
            useNeural = enabled,
        )
    }

    private fun categoryFor(type: String, lower: String, rule: RuleMatch?): String = when (type) {
        "refund" -> "Refund"
        "transfer" -> if (isCreditCardBillPayment(lower)) "Credit Card Payment" else "Transfer"
        "investment" -> if (rule?.type == "investment") rule.category else when {
            lower.contains("mutual fund") || lower.contains("sip") -> "Mutual Funds"
            lower.contains("gold") -> "Gold"
            lower.contains("stock") || lower.contains("zerodha") -> "Stocks"
            else -> "Other Investment"
        }
        "income" -> if (lower.contains("salary")) "Salary" else if (rule?.type == "income") rule.category else "Uncategorized"
        else -> rule?.category ?: "Uncategorized"
    }

    private fun extractAmount(text: String): Double? {
        val raw = amountRegex.find(text)?.groupValues?.getOrNull(1) ?: return null
        return raw.replace(",", "").toDoubleOrNull()
    }

    private fun extractMerchant(text: String): String? {
        val match = toRegex.find(text)?.groupValues?.getOrNull(1)?.trim()?.trimEnd('.', ',')
        return match?.takeIf { it.length in 2..40 }
    }

    private fun extractNote(text: String): String =
        noteRegex.find(text)?.groupValues?.getOrNull(1)?.trim().orEmpty()

    private fun isCreditCardBillPayment(lower: String): Boolean =
        lower.contains("credit card") && (
            (lower.contains("payment of") && lower.contains("has been received")) ||
            lower.contains("payment received towards") ||
            lower.contains("payment received for") ||
            lower.contains("credit card payment received") ||
            lower.contains("received towards your") ||
            (lower.contains("thank you for your payment") && lower.contains("card")) ||
            lower.contains("card bill payment successful")
        )

    private fun extractCreditCardMerchant(text: String): String? {
        val patterns = listOf(
            Regex("(?i)(?:towards|for)\\s+(?:your\\s+)?([A-Za-z][A-Za-z .&'-]{1,40}?credit card)"),
            Regex("(?i)([A-Za-z][A-Za-z .&'-]{1,40}?credit card)")
        )
        for (pattern in patterns) {
            val value = pattern.find(text)?.groupValues?.getOrNull(1)
                ?.trim()?.trimEnd('.', ',', '-', ':')
            if (!value.isNullOrBlank()) return value
        }
        return null
    }

    private fun fingerprint(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
