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

        return decision(
            "ignore",
            1.0 - neural.confidence.coerceIn(0.0, 1.0),
            "low_confidence",
            neural.label,
            neural.confidence,
            "uncertain message; not auto-saved"
        )
    }

    private fun hardGate(lower: String): HybridDecision? {
        val otp = listOf(" otp ", "otp:", "otp is", "one time password", "verification code")
            .any { " $lower ".contains(it) }
        if (otp) return decision("ignore", 1.0, "hard_gate", "ignore", 1.0, "OTP/security message")

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
            "will be debited", "will be auto-debited", "will be auto debited", "scheduled debit",
            "scheduled for", "autopay scheduled", "upcoming debit", "due on", "will be processed",
            "not yet completed", "payment is pending", "mandate payment will"
        ).any { lower.contains(it) }
        val completed = listOf(
            "has been debited", "successfully debited", "debited from", "payment successful",
            "paid successfully", "transaction successful", "completed successfully", "has been paid"
        ).any { lower.contains(it) }
        if (future && !completed) {
            return decision("pending", 1.0, "hard_gate", "pending", 1.0, "future/scheduled debit")
        }

        return null
    }

    private fun contextOverride(lower: String, neural: NeuralPrediction): HybridDecision? {
        if (listOf("refund", "refunded", "reversal", "reversed", "credited back", "returned to your account")
                .any { lower.contains(it) }) {
            return decision("refund", 0.99, "context_override", neural.label, neural.confidence, "refund/reversal context")
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
