package com.mizani.money.core.security

/** Cross-platform policy for the optional local app-lock PIN. */
object PinPolicyRules {
    const val LENGTH = 6
    const val FREE_ATTEMPTS = 5
    const val BACKOFF_BASE_MS = 5_000L
    const val BACKOFF_MAX_MS = 60_000L
    const val PBKDF2_ITERATIONS = 120_000
    const val BACKGROUND_GRACE_PERIOD_MS = 15_000L

    fun isValidPin(pin: String): Boolean =
        pin.length == LENGTH && pin.all { it in '0'..'9' }

    /** Consecutive wrong PINs allowed before any wait is imposed. */
    fun backoffMs(failedAttempts: Int): Long {
        if (failedAttempts < FREE_ATTEMPTS) return 0L
        var delayMs = BACKOFF_BASE_MS
        var step = FREE_ATTEMPTS
        while (step < failedAttempts && delayMs < BACKOFF_MAX_MS) {
            delayMs = (delayMs * 2).coerceAtMost(BACKOFF_MAX_MS)
            step++
        }
        return delayMs
    }

    /** Time-based lockout expires; invalid counters and a clock rollback never lock forever. */
    fun blockedRemainingMs(failedAttempts: Int, lastFailureAtMs: Long, nowMs: Long): Long {
        if (failedAttempts < FREE_ATTEMPTS) return 0L
        if (lastFailureAtMs <= 0L || nowMs < lastFailureAtMs) return 0L
        val elapsed = nowMs - lastFailureAtMs
        if (elapsed < 0L) return 0L // subtraction overflow, treated as invalid time state
        return (backoffMs(failedAttempts) - elapsed).coerceAtLeast(0L)
    }
}
