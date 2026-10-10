package com.example.expense_tracker

enum class SmsAction { IMPORT, REVIEW, IGNORE }

data class SmsClassification(
    val action: SmsAction,
    val type: String? = null,
    val confidence: Int = 0,
    val reason: String = ""
) {
    val shouldImport get() = action == SmsAction.IMPORT
    val needsReview get() = action == SmsAction.REVIEW
}

object SmsClassifier {
    private val currencyAmountRegex = Regex(
        """(?:INR|RS[.:]?|₹)\s*([0-9][0-9,]*(?:\.\d{1,2})?)""",
        RegexOption.IGNORE_CASE
    )

    private val actionAmountRegex = Regex(
        """(?:DEBITED|DEBIT|DEDUCTED|CREDITED|SENT|SPENT|WITHDRAWN|PAID|REFUNDED|TRANSACTION(?:\s+OF)?)\s*(?:BY|FOR|WITH|OF)?\s*(?:INR|RS[.:]?|₹)?\s*([0-9][0-9,]*(?:\.\d{1,2})?)""",
        RegexOption.IGNORE_CASE
    )

    private val accountRegex = Regex(
        """(?:A/?C|ACCT|ACCOUNT|CARD)\s*(?:NO\.?|XX|X+)?\s*([0-9X*]{3,8})""",
        RegexOption.IGNORE_CASE
    )

    private val referenceRegex = Regex(
        """(?:UPI\s*REF(?:ERENCE)?(?:\s*NO)?|REF(?:ERENCE)?(?:\s*NO)?|UTR|TXN(?:\s*ID)?)\s*[:#-]?\s*([A-Z0-9]{6,})""",
        RegexOption.IGNORE_CASE
    )

    private val completedActions = listOf(
        "DEBITED", "DEBIT ", "DEDUCTED", "CREDITED", "SENT", "SPENT",
        "PURCHASED", "WITHDRAWN", "PAID", "PAYING", "PAYMENT CONFIRMED",
        "TRANSACTION SUCCESSFUL", "RECEIVED", "REFUND PROCESSED",
        "REFUNDED", "REVERSED", "REVERSAL", "USING YOUR",
        "ORDER EXECUTED", "ORDER CONFIRMED", "UNITS ALLOTTED"
    )

    private val hardRejectPhrases = listOf(
        "OTP", "ONE TIME PASSWORD", "VERIFICATION CODE", "PASSCODE",
        "TRANSACTION FAILED", "PAYMENT FAILED", "FAILED", "DECLINED",
        "PENDING", "WILL BE", "UPCOMING", "SCHEDULED", "MINIMUM DUE",
        "BILL DUE", "STATEMENT GENERATED", "MANDATE REGISTRATION",
        "AUTOPAY SETUP"
    )

    private val promotionalPhrases = listOf(
        "CASHBACK OFFER", "EARN CASHBACK", "REWARD POINTS",
        "LIMITED OFFER", "DISCOUNT", "COUPON", "CLICK HERE", "APPLY NOW"
    )

    private val statementPhrases = listOf(
        "THIS MONTH", "SPEND ANALYSIS", "MONTHLY SPEND", "AVAILABLE LIMIT"
    )

    private val investmentWords = listOf(
        "SIP", "MUTUAL FUND", "DEMAT", "SECURITIES", "STOCK",
        "EQUITY", "ETF", "NAV", "UNITS", "PORTFOLIO",
        "ORDER EXECUTED", "ORDER CONFIRMED"
    )

    fun extractAmount(message: String): Double? {
        val match = currencyAmountRegex.find(message)
            ?: actionAmountRegex.find(message)
            ?: return null

        return match.groupValues.getOrNull(1)
            ?.replace(",", "")
            ?.toDoubleOrNull()
    }

    fun classify(sender: String, message: String): SmsClassification {
        val text = message.uppercase()

        if (hardRejectPhrases.any(text::contains)) {
            return ignored("security, failed, or future-event SMS")
        }

        if (
            promotionalPhrases.any(text::contains) ||
            text.contains("HTTP://") ||
            text.contains("HTTPS://")
        ) {
            return ignored("promotional or link-containing SMS")
        }

        if (statementPhrases.any(text::contains)) {
            return ignored("statement or summary SMS")
        }

        if (extractAmount(message) == null) {
            return ignored("no transaction amount")
        }

        var score = 20

        if (completedActions.any(text::contains)) {
            score += 35
        } else {
            return ignored("no completed transaction action")
        }

        if (accountRegex.containsMatchIn(message)) score += 10
        if (referenceRegex.containsMatchIn(message)) score += 10

        if (
            text.contains("UPI") ||
            text.contains("IMPS") ||
            text.contains("NEFT") ||
            text.contains("RTGS") ||
            text.contains("ATM")
        ) {
            score += 10
        }

        if (investmentWords.any(text::contains)) {
            score += 10
        }

        val type = detectType(text)

        return when {
            score >= 85 ->
                SmsClassification(SmsAction.IMPORT, type, score, "strong transaction evidence")

            score >= 55 ->
                SmsClassification(SmsAction.REVIEW, type, score, "needs confirmation")

            else ->
                ignored("insufficient transaction evidence")
        }
    }

    fun fingerprint(sender: String, message: String): String {
        val reference = referenceRegex.find(message)
            ?.groupValues
            ?.getOrNull(1)
            ?.lowercase()

        val normalizedSender = sender.lowercase().trim()

        return if (!reference.isNullOrBlank()) {
            "$normalizedSender-ref-$reference"
        } else {
            "$normalizedSender-${Integer.toHexString(message.trim().lowercase().hashCode())}"
        }
    }

    private fun detectType(text: String): String = when {
        investmentWords.any(text::contains) -> "investment"

        listOf("REFUND", "REVERSED", "REVERSAL", "CASHBACK")
            .any(text::contains) -> "refund"

        listOf("SELF TRANSFER", "OWN ACCOUNT", "TRANSFER BETWEEN")
            .any(text::contains) -> "transfer"

        text.contains("CREDITED") || text.contains("RECEIVED") -> "income"

        else -> "expense"
    }

    private fun ignored(reason: String): SmsClassification {
        return SmsClassification(SmsAction.IGNORE, reason = reason)
    }
}
