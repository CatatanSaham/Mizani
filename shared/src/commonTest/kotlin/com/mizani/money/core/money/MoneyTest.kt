package com.mizani.money.core.money

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MoneyTest {
    @Test
    fun currencyScaleUsesConfiguredMinorUnits() {
        assertEquals(1L, Currency("UGX", "USh", "Ugandan Shilling", 0).scaleFactor)
        assertEquals(100L, Currency("USD", "$", "US Dollar", 2).scaleFactor)
        assertEquals(1_000L, Currency("BHD", "BD", "Bahraini Dinar", 3).scaleFactor)
    }

    @Test
    fun currencyRejectsUnsupportedScale() {
        assertFailsWith<IllegalArgumentException> { Currency("BAD", "?", "Invalid", -1) }
        assertFailsWith<IllegalArgumentException> { Currency("BAD", "?", "Invalid", 7) }
    }

    @Test
    fun arithmeticPreservesMinorUnitsAndCurrency() {
        val first = Money(10_000L, "UGX")
        val second = Money(2_500L, "UGX")

        assertEquals(Money(12_500L, "UGX"), first + second)
        assertEquals(Money(7_500L, "UGX"), first - second)
        assertEquals(Money(30_000L, "UGX"), second * 12L)
        assertEquals(Money(-10_000L, "UGX"), -first)
        assertEquals(first, (-first).abs())
    }

    @Test
    fun comparisonRequiresMatchingCurrencies() {
        assertTrue(Money(1L, "USD") < Money(2L, "USD"))
        assertFalse(Money.zero("USD").isPositive())
        assertFailsWith<IllegalArgumentException> { Money(1L, "USD").compareTo(Money(1L, "EUR")) }
    }

    @Test
    fun arithmeticRejectsCurrencyMismatchAndOverflow() {
        assertFailsWith<IllegalArgumentException> { Money(100L, "UGX") + Money(100L, "KES") }
        assertFailsWith<ArithmeticException> { Money(Long.MAX_VALUE, "UGX") + Money(1L, "UGX") }
        assertFailsWith<ArithmeticException> { Money(Long.MIN_VALUE, "UGX") - Money(1L, "UGX") }
        assertFailsWith<ArithmeticException> { Money(Long.MAX_VALUE, "UGX") * 2L }
        assertFailsWith<ArithmeticException> { -Money(Long.MIN_VALUE, "UGX") }
        assertFailsWith<ArithmeticException> { Money(Long.MIN_VALUE, "UGX").abs() }
    }

    @Test
    fun majorUnitFactoryUsesCurrencyScale() {
        assertEquals(
            Money(123_450L, "USD"),
            Money.ofMajor(1_234L, Currency("USD", "$", "US Dollar", 2)) + Money(50L, "USD"),
        )
    }
}
