package com.mizani.money.domain.finance

import com.mizani.money.core.money.MoneyLimits

/** Shared amount and overflow rules for savings goals. */
object GoalRules {
    fun isValidTargetMinor(amountMinor: Long): Boolean = isSupportedPositiveAmount(amountMinor)

    fun isValidContributionMinor(amountMinor: Long): Boolean = isSupportedPositiveAmount(amountMinor)

    /**
     * Returns the next allocation when both values and their sum are supported money amounts.
     * Null indicates invalid persisted state, an invalid contribution, or an out-of-range sum.
     */
    fun allocatedMinorAfterContribution(currentAllocatedMinor: Long, contributionMinor: Long): Long? {
        if (currentAllocatedMinor !in 0L..MoneyLimits.MAX_MINOR_AMOUNT) return null
        if (!isValidContributionMinor(contributionMinor)) return null

        val nextAllocatedMinor = currentAllocatedMinor + contributionMinor
        return nextAllocatedMinor.takeIf { it <= MoneyLimits.MAX_MINOR_AMOUNT }
    }

    private fun isSupportedPositiveAmount(amountMinor: Long): Boolean =
        amountMinor in 1L..MoneyLimits.MAX_MINOR_AMOUNT
}
