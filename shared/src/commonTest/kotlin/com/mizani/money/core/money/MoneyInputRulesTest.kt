package com.mizani.money.core.money

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MoneyInputRulesTest {
    @Test
    fun `parses grouping currency symbols and leading decimal fractions`() {
        assertEquals(1_500_000L, MoneyInputRules.parseMinorUnits("1,500,000", "USh", 0))
        assertEquals(1_500_000L, MoneyInputRules.parseMinorUnits(" 1 500 000 ", "USh", 0))
        assertEquals(5L, MoneyInputRules.parseMinorUnits(".05", "$", 2))
    }

    @Test
    fun `rounds extra decimal precision half up for zero and multi decimal currencies`() {
        assertEquals(1_235L, MoneyInputRules.parseMinorUnits("1234.50", "USh", 0))
        assertEquals(1_234L, MoneyInputRules.parseMinorUnits("1234.49", "USh", 0))
        assertEquals(1_235L, MoneyInputRules.parseMinorUnits("12.349", "$", 2))
    }

    @Test
    fun `uses a locale decimal separator without changing integer storage`() {
        assertEquals(12_345L, MoneyInputRules.parseMinorUnits("123,45", "€", 2, decimalSeparator = ","))
        assertEquals(
            123_450L,
            MoneyInputRules.parseMinorUnits(
                "1.234,50",
                "€",
                2,
                decimalSeparator = ",",
                groupingSeparator = ".",
            ),
        )
    }

    @Test
    fun `rejects malformed negative excessive and out of range values`() {
        assertNull(MoneyInputRules.parseMinorUnits("", "$", 2))
        assertNull(MoneyInputRules.parseMinorUnits("12.3.4", "$", 2))
        assertNull(MoneyInputRules.parseMinorUnits("-1", "$", 2))
        assertNull(MoneyInputRules.parseMinorUnits("1.1234567", "$", 2))
        assertNull(MoneyInputRules.parseMinorUnits("999999999999999", "$", 2))
        assertNull(MoneyInputRules.parseMinorUnits("1", "$", 7))
    }
}
