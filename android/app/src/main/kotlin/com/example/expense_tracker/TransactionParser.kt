package com.example.expense_tracker

data class ParsedTransaction(
    val amount: Double,
    val type: String,
    val category: String,
    val merchant: String,
    val sender: String,
    val paymentMethod: String,
    val accountHint: String,
    val rawMessage: String,
    val occurredAt: Long,
    val fingerprint: String
)

object TransactionParser {
    private val amountRegex = Regex("""(?:INR|RS\.?|₹)\s*([0-9][0-9,]*(?:\.\d{1,2})?)""", RegexOption.IGNORE_CASE)
    private val accountRegex = Regex("""(?:A/?C|ACCT|ACCOUNT|CARD)\s*(?:NO\.?|XX|X+)?\s*([0-9X*]{3,8})""", RegexOption.IGNORE_CASE)
    private val merchantRegex = Regex("""(?:\bTO\b|\bAT\b)\s+([A-Z0-9*._@& -]{2,50})""", RegexOption.IGNORE_CASE)

    fun looksFinancial(message: String): Boolean {
        val text = message.uppercase()
        if (text.contains("OTP") || text.contains("ONE TIME PASSWORD") || text.contains("VERIFICATION CODE")) return false
        if (amountRegex.find(message) == null) return false
        return listOf("DEBITED", "CREDITED", "SPENT", "PURCHASE", "PAID", "PAYMENT", "WITHDRAWN", "WITHDRAWAL", "RECEIVED", "REFUND", "REVERSED", "CASHBACK", "UPI", "IMPS", "NEFT", "RTGS", "SIP", "INVEST").any { text.contains(it) }
    }

    fun parse(sender: String, message: String, db: ExpenseDatabase, occurredAt: Long = System.currentTimeMillis()): ParsedTransaction? {
        if (!looksFinancial(message)) return null
        val amount = amountRegex.find(message)?.groupValues?.getOrNull(1)?.replace(",", "")?.toDoubleOrNull() ?: return null
        val rule = db.findRule(message)
        val text = message.uppercase()
        val type = rule?.type ?: detectType(text)
        val category = rule?.category ?: defaultCategory(type)
        val merchant = rule?.merchant ?: extractMerchant(message)
        val paymentMethod = when {
            text.contains("UPI") -> "UPI"
            text.contains("IMPS") -> "IMPS"
            text.contains("NEFT") -> "NEFT"
            text.contains("RTGS") -> "RTGS"
            text.contains("ATM") -> "ATM"
            text.contains("CARD") -> "Card"
            else -> "Bank"
        }
        val accountHint = accountRegex.find(message)?.groupValues?.getOrNull(1)?.takeLast(4) ?: ""
        val fingerprint = "${sender.lowercase()}-${Integer.toHexString(message.trim().lowercase().hashCode())}"
        return ParsedTransaction(amount, type, category, merchant.ifBlank { "Unknown merchant" }, sender, paymentMethod, accountHint, message, occurredAt, fingerprint)
    }

    private fun detectType(text: String): String {
        if (listOf("SIP", "MUTUAL FUND", "ZERODHA", "GROWW", "SECURITIES", "DEMAT", "INVEST").any { text.contains(it) }) return "investment"
        if (listOf("REFUND", "REVERSED", "REVERSAL", "CASHBACK").any { text.contains(it) }) return "refund"
        if (listOf("SELF TRANSFER", "OWN ACCOUNT", "TRANSFER BETWEEN").any { text.contains(it) }) return "transfer"
        if (text.contains("CREDITED") || text.contains("RECEIVED")) return "income"
        return "expense"
    }

    private fun defaultCategory(type: String): String = when (type) {
        "investment" -> "Other Investment"
        "income" -> "Salary"
        "refund" -> "Refund"
        "transfer" -> "Transfer"
        else -> "Uncategorized"
    }

    private fun extractMerchant(message: String): String {
        val match = merchantRegex.find(message) ?: return "Unknown merchant"
        var merchant = match.groupValues[1].trim()
        val upper = merchant.uppercase()
        var cut = merchant.length
        for (stop in listOf(" ON ", " VIA ", " REF ", " AVAIL", " AVL ", " BAL ", " FROM ")) {
            val i = upper.indexOf(stop)
            if (i >= 0 && i < cut) cut = i
        }
        merchant = merchant.substring(0, cut).trim(' ', '.', '-', '*')
        return merchant.take(40).ifBlank { "Unknown merchant" }
    }
}
