package com.example.expense_tracker

import java.util.Locale

data class HybridDecision(
    val label: String,
    val confidence: Double,
    val method: String,
    val neuralLabel: String,
    val neuralConfidence: Double,
    val reason: String,
)

/**
 * Hybrid classifier = hard safety gates + deterministic transaction context
 * + tiny on-device neural model + learned/default rules.
 *
 * v24 safety principle:
 * A rupee amount alone is NEVER proof that money moved. Promotional amounts,
 * discounts, coupons and "up to Rs X OFF" must not enter the ledger.
 */
object HybridMessageClassifier {
    fun classify(
        text: String,
        rule: RuleMatch?,
        threshold: Double = 0.56,
        useNeural: Boolean = true,
    ): HybridDecision {
        val lower = text.lowercase(Locale.ROOT).trim()
        if (lower.isBlank()) return decision("ignore", 1.0, "hard_gate", "ignore", 0.0, "blank")

        // Safety gates run before rules/ML so a promotional SMS cannot become a
        // transaction merely because it contains a merchant name or rupee value.
        hardGate(lower)?.let { return it }

        // A neural prediction or merchant rule alone is never evidence of a transaction.
        // Conservative guard: uncertain alerts remain outside recorded expenses.
        val currencyAmount = Regex("""(?:₹|\brs\.?|\binr\b)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?""")
            .containsMatchIn(lower)
        val completedMoneyMovement = Regex(
            """\b(debited|deducted|credited|withdrawn|paid|spent|received|sent|refunded|transferred|purchased|invested)\b|cash withdrawal|payment successful|transaction successful|payment completed|order executed|units allotted"""
        ).containsMatchIn(lower)
        if (!currencyAmount || !completedMoneyMovement) {
            return decision("ignore", 1.0, "hard_gate", "ignore", 1.0,
                "no confirmed currency transaction")
        }

        val neural = if (useNeural) TinyNeuralClassifier.predict(text)
        else NeuralPrediction("ignore", 0.0, emptyMap())

        // Strong completed-transaction semantics beat statistical guesses.
        contextOverride(lower, neural)?.let { return it }

        val completedEvidence = hasCompletedFinancialEvidence(lower)

        // A learned v22+ conjunction rule is user-confirmed and specific, but it
        // still needs evidence that a transaction actually happened.
        if (rule != null && rule.keyword.contains("&&") && completedEvidence) {
            return decision(
                rule.type,
                0.995,
                "merchant_rule",
                neural.label,
                neural.confidence,
                "user-confirmed message-pattern rule"
            )
        }

        // Critical guard: an amount marker by itself is not a transaction.
        // This prevents ads such as "Rs 3000 OFF - use code - book now" from
        // being saved as expense/income/investment.
        if (!completedEvidence) {
            return decision(
                "ignore",
                0.995,
                "hard_gate",
                neural.label,
                neural.confidence,
                "no completed financial movement evidence"
            )
        }

        if (useNeural && neural.confidence >= threshold) {
            return decision(
                neural.label,
                neural.confidence,
                "neural",
                neural.label,
                neural.confidence,
                "tiny on-device neural model with completed-transaction evidence"
            )
        }

        // Default/single-keyword merchant rules are fallback only. They cannot
        // turn a non-transaction message into a transaction because evidence was
        // already required above.
        if (rule != null) {
            return decision(
                rule.type,
                0.60,
                "merchant_rule",
                neural.label,
                neural.confidence,
                "merchant rule with completed-transaction evidence"
            )
        }

        if (useNeural && neural.label !in setOf("ignore", "pending") && neural.confidence >= 0.35) {
            return decision(
                neural.label,
                neural.confidence,
                "low_confidence_review",
                neural.label,
                neural.confidence,
                "uncertain completed financial message; saved to Needs Review"
            )
        }

        return decision(
            "ignore",
            1.0 - neural.confidence.coerceIn(0.0, 1.0),
            "low_confidence",
            neural.label,
            neural.confidence,
            "uncertain/non-financial message"
        )
    }

    private fun hardGate(lower: String): HybridDecision? {
        val padded = " $lower "
        val otp = listOf(" otp ", "otp:", "otp is", "one time password", "verification code")
            .any { padded.contains(it) }
        if (otp) return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "OTP/security message")

        val explicitSpam = listOf(
            "warning: spam", "spam |", "spam:", "suspected spam", "reported as spam"
        ).any { lower.contains(it) }
        val marketTipSpam = listOf(
            "option chain", "stock tip", "trading signal", "signal clean upside",
            "buy call", "sell call", "target price", "stock guild", "intraday call",
            "join telegram", "telegram channel", "whatsapp group"
        ).any { lower.contains(it) }
        if (explicitSpam || marketTipSpam) {
            return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "spam/stock-tip message")
        }

        // Promotional/advertising language. Only suppress when there is no
        // completed movement evidence so legitimate messages such as
        // "cashback of Rs 100 credited" still survive.
        val promotionalCue = listOf(
            "special deal", "special offer", "exclusive offer", "limited offer", "limited time",
            "pre-approved", "pre approved", "apply now", "loan offer", "cashback offer",
            "reward points", "rewards points", "use code", "promo code", "coupon code", "coupon",
            "book now", "shop now", "buy now", "order now", "avail now", "redeem now",
            "offer valid", "sale ends", "flash sale", "mega sale", "deal on", "deals on",
            "flat discount", "discount", "save up to", "up to rs", "up to inr", "up to ₹",
            "get flat", "get up to", "win ", "congratulations! you have won", "invest now",
            "start investing", "start sip", "open demat", "open an account"
        ).any { lower.contains(it) }

        val discountAmount = Regex("(?i)(?:rs\\.?|inr|₹)\\s*[0-9,]+(?:\\.[0-9]{1,2})?\\s*(?:off|discount|cashback)")
            .containsMatchIn(lower) ||
            Regex("(?i)(?:up to|save|get)\\s*(?:rs\\.?|inr|₹)\\s*[0-9,]+(?:\\.[0-9]{1,2})?")
                .containsMatchIn(lower)

        val percentOffer = Regex("(?i)\\b(?:up to\\s*)?[0-9]{1,3}%\\s*(?:off|discount|cashback)")
            .containsMatchIn(lower)

        if ((promotionalCue || discountAmount || percentOffer) && !hasCompletedFinancialEvidence(lower)) {
            return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "promotional/discount message")
        }

        val collectRequest = listOf(
            "payment request", "collect request", "approve or decline", "approve the request",
            "request received", "requested ₹", "requested rs"
        ).any { lower.contains(it) }
        if (collectRequest && !listOf("payment successful", "paid successfully", "transaction successful").any { lower.contains(it) }) {
            return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "payment/collect request is not a completed transaction")
        }

        val future = listOf(
            "will be debited", "shall be debited", "would be debited", "to be debited",
            "will be auto-debited", "will be auto debited", "scheduled debit", "debit scheduled",
            "scheduled for", "autopay scheduled", "upcoming debit", "due on", "will be processed",
            "not yet completed", "payment is pending", "mandate payment will", "will be charged"
        ).any { lower.contains(it) }
        val completed = listOf(
            "has been debited", "successfully debited", "was debited", "payment successful",
            "paid successfully", "transaction successful", "completed successfully", "has been paid",
            "debited from", "credited to"
        ).any { lower.contains(it) }
        if (future && !completed) {
            return decision("pending", 1.0, "hard_gate", "pending", 1.0, "future/scheduled debit")
        }

        val reversedOrFailed = listOf(
            "reversed", "reversal", "transaction failed", "payment failed", "unsuccessful",
            "declined", "insufficient balance", "insufficient funds", "er04"
        ).any { lower.contains(it) }
        val explicitCreditBack = listOf(
            "credited back", "refund credited", "amount credited", "credited to your account",
            "returned to your account", "refund has been credited"
        ).any { lower.contains(it) }
        if (reversedOrFailed && !explicitCreditBack) {
            return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "failed/reversed transaction with no confirmed cash credit")
        }

        val creditCardBillPayment =
            lower.contains("credit card") && (
                (lower.contains("payment of") && lower.contains("has been received")) ||
                lower.contains("payment received towards") ||
                lower.contains("payment received for") ||
                lower.contains("payment received against") ||
                lower.contains("payment received on your") ||
                lower.contains("payment has been received") ||
                lower.contains("credit card payment received") ||
                lower.contains("received towards your") ||
                (lower.contains("thank you for your payment") && lower.contains("card")) ||
                lower.contains("card bill payment successful")
            )
        if (creditCardBillPayment) {
            return decision("transfer", 0.995, "hard_gate", "transfer", 1.0, "credit-card bill payment")
        }

        return null
    }

    private fun contextOverride(lower: String, neural: NeuralPrediction): HybridDecision? {
        val completedRefund = listOf(
            "refunded", "refund credited", "refund has been credited", "credited back",
            "returned to your account", "refund successful", "amount refunded", "reversal credited",
            "reversed and credited"
        ).any { lower.contains(it) }
        if (completedRefund) {
            return decision("refund", 0.99, "context_override", neural.label, neural.confidence, "confirmed refund/credit-back context")
        }

        if (listOf("self transfer", "own account", "between your accounts", "internal transfer", "moved between your accounts")
                .any { lower.contains(it) } && hasCompletedFinancialEvidence(lower)) {
            return decision("transfer", 0.98, "context_override", neural.label, neural.confidence, "self/internal transfer context")
        }

        val investmentProduct = listOf(
            "sip", "mutual fund", "zerodha", "groww", "stock purchase", "bought stocks",
            "gold investment", "invested in", "units allotted", "units purchased", "order executed"
        ).any { lower.contains(it) }
        val investmentExecution = listOf(
            "debited", "paid", "purchase", "purchased", "invested", "allotted", "executed",
            "successful", "completed", "transaction id", "folio", "units"
        ).any { lower.contains(it) }
        if (investmentProduct && investmentExecution && hasCompletedFinancialEvidence(lower)) {
            return decision("investment", 0.97, "context_override", neural.label, neural.confidence, "completed investment context")
        }

        val credit = listOf(
            "credited to", "credited by", "received from", "salary credited", "salary of",
            "deposited in", "deposited to"
        ).any { lower.contains(it) }
        if (credit && !lower.contains("credited back")) {
            return decision("income", 0.96, "context_override", neural.label, neural.confidence, "credit/income context")
        }

        // Common bank wording: "PNB Credit Card 4872 debited with Rs.7200 at
        // FASHION FIESTA through UPI". This is a completed card purchase, not
        // a card bill settlement or an offer, so it must not depend on ML score.
        val cardPurchase = lower.contains("credit card") &&
            Regex("\\b(?:debited|charged|spent)\\b").containsMatchIn(lower) &&
            Regex("(?:rs\\.?|inr|₹)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?").containsMatchIn(lower)
        if (cardPurchase) {
            return decision("expense", 0.99, "context_override", neural.label, neural.confidence, "confirmed credit-card purchase")
        }

        val cardCashWithdrawal = lower.contains("credit card") &&
            (lower.contains("cash withdrawal") || lower.contains("cash withdrawn")) &&
            Regex("(?:rs\\.?|inr|₹)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?").containsMatchIn(lower)
        if (cardCashWithdrawal) {
            return decision("expense", 0.99, "context_override", neural.label, neural.confidence, "confirmed credit-card cash withdrawal")
        }

        // Restore a deterministic fallback for regular bank wording such as
        // "Rs 1,200 debited from account" or "Debit of Rs 900 at merchant".
        // Scheduled debits were already rejected in hardGate above.
        val confirmedDebit = Regex("\\b(?:debited|debit\\s+of|deducted|charged|spent|withdrawn|paid)\\b.{0,55}(?:rs\\.?|inr|₹)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?", RegexOption.IGNORE_CASE).containsMatchIn(lower) ||
            Regex("(?:rs\\.?|inr|₹)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.{0,55}\\b(?:debited|deducted|charged|spent|withdrawn|paid)\\b", RegexOption.IGNORE_CASE).containsMatchIn(lower)
        if (confirmedDebit) {
            return decision("expense", 0.94, "context_override", neural.label, neural.confidence, "confirmed debit wording")
        }

        val debit = listOf(
            "debited from", "has been debited", "successfully debited", "was debited", "paid to",
            "spent ", "card was charged", "charged to", "sent ₹", "sent rs", "payment successful",
            "paid successfully", "withdrawn from", "purchase at", "transaction successful"
        ).any { lower.contains(it) }
        if (debit) {
            return decision("expense", 0.95, "context_override", neural.label, neural.confidence, "completed debit/payment context")
        }

        return null
    }

    private fun hasCompletedFinancialEvidence(lower: String): Boolean {
        // Intentionally excludes bare words such as "offer", "cashback", "payment",
        // "investment", merchant names and currency amounts.
        val phrases = listOf(
            "debited from", "has been debited", "successfully debited", "was debited",
            "credited to", "has been credited", "successfully credited", "credited by",
            "paid to", "paid successfully", "has been paid", "payment successful",
            "transaction successful", "completed successfully", "spent ", "card was charged",
            "charged to", "sent ₹", "sent rs", "sent inr", "received from", "salary credited",
            "withdrawn from", "cash withdrawal", "deposited in", "deposited to", "transferred to",
            "transferred from", "refund credited", "credited back", "amount refunded",
            "units allotted", "units purchased", "order executed", "purchase successful",
            "investment successful", "sip successful", "sip processed", "purchase at"
        )
        if (phrases.any { lower.contains(it) }) return true

        // Bank SMS often uses compact grammar such as "INR 500 debited" or
        // "Rs 1200 credited". These regexes capture movement verbs near a value.
        val currency = "(?:rs\\.?|inr|₹)\\s*[0-9,]+(?:\\.[0-9]{1,2})?"
        val movementAfter = Regex("(?i)$currency.{0,45}\\b(?:debited|credited|paid|spent|charged|sent|withdrawn|deposited|transferred|refunded|invested)\\b")
        val movementBefore = Regex("(?i)\\b(?:debited|credited|paid|spent|charged|sent|withdrawn|deposited|transferred|refunded|invested)\\b.{0,45}$currency")
        return movementAfter.containsMatchIn(lower) || movementBefore.containsMatchIn(lower)
    }

    private fun decision(
        label: String,
        confidence: Double,
        method: String,
        neuralLabel: String,
        neuralConfidence: Double,
        reason: String,
    ) = HybridDecision(label, confidence, method, neuralLabel, neuralConfidence, reason)
}
