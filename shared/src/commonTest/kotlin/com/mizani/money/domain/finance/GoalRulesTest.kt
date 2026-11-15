package com.mizani.money.domain.finance

import com.mizani.money.core.money.MoneyLimits
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GoalRulesTest {
    @Test
    fun targetAndContributionAmountsUseSupportedPositiveRange() {
        assertFalse(GoalRules.isValidTargetMinor(Long.MIN_VALUE))
        assertFalse(GoalRules.isValidTargetMinor(-1L))
        assertFalse(GoalRules.isValidTargetMinor(0L))
        assertTrue(GoalRules.isValidTargetMinor(1L))
        assertTrue(GoalRules.isValidTargetMinor(MoneyLimits.MAX_MINOR_AMOUNT))
        assertFalse(GoalRules.isValidTargetMinor(MoneyLimits.MAX_MINOR_AMOUNT + 1L))
        assertFalse(GoalRules.isValidTargetMinor(Long.MAX_VALUE))

        assertFalse(GoalRules.isValidContributionMinor(0L))
        assertTrue(GoalRules.isValidContributionMinor(1L))
        assertTrue(GoalRules.isValidContributionMinor(MoneyLimits.MAX_MINOR_AMOUNT))
        assertFalse(GoalRules.isValidContributionMinor(MoneyLimits.MAX_MINOR_AMOUNT + 1L))
    }

    @Test
    fun contributionAllocationIsCheckedAndAllowsSupportedBoundary() {
        assertEquals(1L, GoalRules.allocatedMinorAfterContribution(0L, 1L))
        assertEquals(
            MoneyLimits.MAX_MINOR_AMOUNT,
            GoalRules.allocatedMinorAfterContribution(MoneyLimits.MAX_MINOR_AMOUNT - 1L, 1L),
        )
        assertNull(GoalRules.allocatedMinorAfterContribution(MoneyLimits.MAX_MINOR_AMOUNT, 1L))
        assertNull(GoalRules.allocatedMinorAfterContribution(Long.MAX_VALUE, 1L))
        assertNull(GoalRules.allocatedMinorAfterContribution(-1L, 1L))
        assertNull(GoalRules.allocatedMinorAfterContribution(0L, 0L))
        assertNull(GoalRules.allocatedMinorAfterContribution(0L, MoneyLimits.MAX_MINOR_AMOUNT + 1L))
    }
}
