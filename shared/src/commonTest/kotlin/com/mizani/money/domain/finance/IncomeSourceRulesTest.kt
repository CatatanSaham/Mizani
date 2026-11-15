package com.mizani.money.domain.finance

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class IncomeSourceRulesTest {
    @Test
    fun sourceLinksAreLimitedToIncomeTransactions() {
        assertTrue(IncomeSourceRules.canAssign("INCOME", hasIncomeSource = true))
        assertTrue(IncomeSourceRules.canAssign("INCOME", hasIncomeSource = false))
        assertTrue(IncomeSourceRules.canAssign("EXPENSE", hasIncomeSource = false))
        assertFalse(IncomeSourceRules.canAssign("EXPENSE", hasIncomeSource = true))
        assertFalse(IncomeSourceRules.canAssign("TRANSFER", hasIncomeSource = true))
    }
}
