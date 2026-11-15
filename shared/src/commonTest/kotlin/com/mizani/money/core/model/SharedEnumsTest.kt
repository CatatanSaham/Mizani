package com.mizani.money.core.model

import kotlin.test.Test
import kotlin.test.assertEquals

class SharedEnumsTest {
    @Test
    fun persistedEnumNamesStayCompatibleWithAndroidDataAndBackups() {
        assertEquals(listOf("CASH", "MOBILE_MONEY", "BANK", "CARD", "SAVINGS", "DEBT", "OTHER"), WalletType.entries.map { it.name })
        assertEquals(listOf("STOCKS", "BONDS", "FUNDS", "REAL_ESTATE", "BUSINESS", "CASH_EQUIVALENT", "OTHER"), InvestmentAssetType.entries.map { it.name })
        assertEquals(listOf("EXPENSE", "INCOME"), CategoryType.entries.map { it.name })
        assertEquals(listOf("EXPENSE", "INCOME", "TRANSFER", "REFUND", "ADJUSTMENT"), TransactionType.entries.map { it.name })
        assertEquals(listOf("WEEKLY", "MONTHLY", "FOUR_WEEK", "CUSTOM"), BudgetPeriodType.entries.map { it.name })
        assertEquals(listOf("NONE", "POSITIVE", "BOTH"), RolloverRule.entries.map { it.name })
        assertEquals(listOf("BILL", "INCOME"), RecurringType.entries.map { it.name })
        assertEquals(listOf("WEEKLY", "BIWEEKLY", "MONTHLY", "QUARTERLY", "YEARLY"), Frequency.entries.map { it.name })
        assertEquals(listOf("SALARY", "BUSINESS", "FREELANCE", "GIG", "REMITTANCE", "FARMING", "OTHER"), IncomeSourceKind.entries.map { it.name })
        assertEquals(listOf("SYSTEM", "LIGHT", "DARK"), ThemeMode.entries.map { it.name })
        assertEquals(listOf("MIZANI", "OCEAN", "VIOLET", "FOREST", "ROSE"), ColorTheme.entries.map { it.name })
        assertEquals(listOf("SOFT_CHARCOAL", "WARM_SLATE"), DarkThemeStyle.entries.map { it.name })
    }

    @Test
    fun darkThemeFallbackKeepsLegacyValuesReadable() {
        assertEquals(DarkThemeStyle.SOFT_CHARCOAL, DarkThemeStyle.fromStoredValue(null))
        assertEquals(DarkThemeStyle.SOFT_CHARCOAL, DarkThemeStyle.fromStoredValue("OLED"))
        assertEquals(DarkThemeStyle.SOFT_CHARCOAL, DarkThemeStyle.fromStoredValue("DEEP_TEAL"))
        assertEquals(DarkThemeStyle.WARM_SLATE, DarkThemeStyle.fromStoredValue("WARM_SLATE"))
    }
}
