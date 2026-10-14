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
 * Hybrid classifier = hard safety gates + deterministic context + tiny neural model
 * + user/default merchant rules + confidence threshold.
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

        hardGate(lower)?.let { return it }

        val neural = if (useNeural) TinyNeuralClassifier.predict(text)
        else NeuralPrediction("ignore", 0.0, emptyMap())

        // Strong semantic context always wins over merchant defaults.
        contextOverride(lower, neural)?.let { return it }

        if (useNeural && neural.confidence >= threshold) {
            return decision(
                neural.label,
                neural.confidence,
                "neural",
                neural.label,
                neural.confidence,
                "tiny on-device neural model"
            )
        }

        if (rule != null) {
            return decision(
                rule.type,
                0.55,
                "merchant_rule",
                neural.label,
                neural.confidence,
                "merchant/user rule fallback"
            )
        }

        if (useNeural && neural.label !in setOf("ignore", "pending") && neural.confidence >= 0.25) {
            return decision(
                neural.label,
                neural.confidence,
                "low_confidence_review",
                neural.label,
                neural.confidence,
                "uncertain financial message; saved to Needs Review"
            )
        }

        return decision(
            "ignore",
            1.0 - neural.confidence.coerceIn(0.0, 1.0),
            "low_confidence",
            neural.label,
            neural.confidence,
            "uncertain non-financial message"
        )
    }

    private fun hardGate(lower: String): HybridDecision? {
        val otp = listOf(" otp ", "otp:", "otp is", "one time password", "verification code")
            .any { " $lower ".contains(it) }
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

        val promotional = listOf(
            "pre-approved", "pre approved", "apply now", "exclusive offer", "limited offer",
            "loan offer", "cashback offer", "reward points", "win ", "congratulations! you have won"
        ).any { lower.contains(it) }
        if (promotional) return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "promotional message")

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
            "paid successfully", "transaction successful", "completed successfully", "has been paid"
        ).any { lower.contains(it) }
        if (future && !completed) {
            return decision("pending", 1.0, "hard_gate", "pending", 1.0, "future/scheduled debit")
        }

        // Some providers send a reversal/failure notice even though no cash refund was credited.
        // Example: a SIP purchase reversed because of insufficient balance. Treat this as no cash movement.
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
            "returned to your account", "refund successful", "amount refunded"
        ).any { lower.contains(it) }
        if (completedRefund) {
            return decision("refund", 0.99, "context_override", neural.label, neural.confidence, "confirmed refund/credit-back context")
        }

        if (listOf("self transfer", "own account", "between your accounts", "internal transfer", "moved between your accounts")
                .any { lower.contains(it) }) {
            return decision("transfer", 0.98, "context_override", neural.label, neural.confidence, "self/internal transfer context")
        }

        if (listOf("sip", "mutual fund", "zerodha", "groww", "stock purchase", "bought stocks", "gold investment", "invested in")
                .any { lower.contains(it) }) {
            return decision("investment", 0.97, "context_override", neural.label, neural.confidence, "investment context")
        }

        val credit = listOf("credited to", "credited by", "received from", "salary credited", "salary of")
            .any { lower.contains(it) }
        if (credit && !lower.contains("credited back")) {
            return decision("income", 0.96, "context_override", neural.label, neural.confidence, "credit/income context")
        }

        val debit = listOf("debited from", "paid to", "spent ", "card was charged", "sent ₹", "sent rs", "payment successful")
            .any { lower.contains(it) }
        if (debit) {
            return decision("expense", 0.95, "context_override", neural.label, neural.confidence, "completed debit/payment context")
        }

        return null
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
