package com.mizani.money.core.security

/** App-lock PIN policy shared by setup, unlock and settings flows. */
object PinDefaults {
    const val LENGTH = PinPolicyRules.LENGTH

    const val FREE_ATTEMPTS = PinPolicyRules.FREE_ATTEMPTS

    const val BACKOFF_BASE_MS = PinPolicyRules.BACKOFF_BASE_MS

    const val BACKOFF_MAX_MS = PinPolicyRules.BACKOFF_MAX_MS

    fun isValidPin(pin: String): Boolean = PinPolicyRules.isValidPin(pin)

    fun backoffMs(failedAttempts: Int): Long = PinPolicyRules.backoffMs(failedAttempts)

    /**
     * Milliseconds remaining until another attempt is allowed; 0 when not blocked.
     * The block is purely time-based on [lastFailureAtMs], so it always expires.
     * Ignores invalid state (no recorded failure or a clock before it).
     */
    fun blockedRemainingMs(failedAttempts: Int, lastFailureAtMs: Long, nowMs: Long): Long =
        PinPolicyRules.blockedRemainingMs(failedAttempts, lastFailureAtMs, nowMs)
}
