package com.mizani.money.core.security

import kotlin.test.Test
import kotlin.test.assertEquals

class PinPolicyRulesTest {
    @Test
    fun backgroundGraceMatchesTheExistingAndroidPolicy() {
        assertEquals(15_000L, PinPolicyRules.BACKGROUND_GRACE_PERIOD_MS)
    }

    @Test
    fun acceptsOnlySixAsciiDigits() {
        assertEquals(true, PinPolicyRules.isValidPin("012345"))
        assertEquals(false, PinPolicyRules.isValidPin("12345"))
        assertEquals(false, PinPolicyRules.isValidPin("1234567"))
        assertEquals(false, PinPolicyRules.isValidPin("12a456"))
        assertEquals(false, PinPolicyRules.isValidPin("١٢٣٤٥٦"))
    }

    @Test
    fun backoffMatchesAndroidBoundariesAndCap() {
        assertEquals(0L, PinPolicyRules.backoffMs(0))
        assertEquals(0L, PinPolicyRules.backoffMs(PinPolicyRules.FREE_ATTEMPTS - 1))
        assertEquals(5_000L, PinPolicyRules.backoffMs(PinPolicyRules.FREE_ATTEMPTS))
        assertEquals(10_000L, PinPolicyRules.backoffMs(6))
        assertEquals(20_000L, PinPolicyRules.backoffMs(7))
        assertEquals(40_000L, PinPolicyRules.backoffMs(8))
        assertEquals(PinPolicyRules.BACKOFF_MAX_MS, PinPolicyRules.backoffMs(Int.MAX_VALUE))
    }

    @Test
    fun lockoutExpiresAndClockRollbackDoesNotCreateAnEndlessWait() {
        val failureAt = 1_700_000_000_000L
        assertEquals(10_000L, PinPolicyRules.blockedRemainingMs(6, failureAt, failureAt))
        assertEquals(4_000L, PinPolicyRules.blockedRemainingMs(6, failureAt, failureAt + 6_000L))
        assertEquals(0L, PinPolicyRules.blockedRemainingMs(6, failureAt, failureAt + 10_000L))
        assertEquals(0L, PinPolicyRules.blockedRemainingMs(9, failureAt, failureAt - 1L))
        assertEquals(0L, PinPolicyRules.blockedRemainingMs(9, 0L, Long.MAX_VALUE))
        assertEquals(0L, PinPolicyRules.blockedRemainingMs(-1, failureAt, failureAt + 1L))
    }
}
