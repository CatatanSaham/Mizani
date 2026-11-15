package com.mizani.money.domain.finance

import com.mizani.money.core.money.Currency
import com.mizani.money.core.money.SharedCurrencyCatalog
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class CommitmentRulesTest {
    private val ugx = SharedCurrencyCatalog.UGX
    private val usd = SharedCurrencyCatalog.USD

    @Test
    fun sameCurrencyRequiresExactTargetAndNoSavedRate() {
        assertNull(
            CommitmentRules.validationError(
                workspaceCurrency = ugx,
                commitmentCurrency = ugx,
                targetMinor = 10_000L,
                targetWorkspaceMinor = 10_000L,
                exchangeRate = null,
                exchangeRateDate = null,
                todayEpochDay = 0L,
            ),
        )
        assertEquals(
            "same_currency_target_mismatch",
            CommitmentRules.validationError(
                workspaceCurrency = ugx,
                commitmentCurrency = ugx,
                targetMinor = 10_000L,
                targetWorkspaceMinor = 9_999L,
                exchangeRate = null,
                exchangeRateDate = null,
                todayEpochDay = 0L,
            ),
        )
        assertEquals(
            "same_currency_rate_present",
            CommitmentRules.validationError(
                workspaceCurrency = ugx,
                commitmentCurrency = ugx,
                targetMinor = 10_000L,
                targetWorkspaceMinor = 10_000L,
                exchangeRate = "1",
                exchangeRateDate = "1970-01-01",
                todayEpochDay = 0L,
            ),
        )
    }

    @Test
    fun foreignTargetUsesSavedRateAndHalfUpMinorUnits() {
        assertNull(
            CommitmentRules.validationError(
                workspaceCurrency = ugx,
                commitmentCurrency = usd,
                targetMinor = 10_000L,
                targetWorkspaceMinor = 360_000L,
                exchangeRate = "3600",
                exchangeRateDate = "1970-01-01",
                todayEpochDay = 0L,
            ),
        )
        assertEquals(
            360_000L,
            CommitmentRules.commitmentToWorkspaceMinor(10_000L, usd, ugx, "3600"),
        )
        assertEquals(
            10_000L,
            CommitmentRules.workspaceToCommitmentMinor(360_000L, ugx, usd, "3600"),
        )
        // A half minor unit rounds away from zero (HALF_UP), matching Android BigDecimal.
        assertEquals(
            1L,
            CommitmentRules.commitmentToWorkspaceMinor(
                amountMinor = 1L,
                commitmentCurrency = Currency("SRC", "", "Source", 0),
                workspaceCurrency = Currency("TGT", "", "Target", 2),
                exchangeRate = "0.005",
            ),
        )
    }

    @Test
    fun rejectsMalformedRatesDatesTargetsAndMismatchedConversions() {
        fun error(rate: String?, date: String?, target: Long = 360_000L): String? =
            CommitmentRules.validationError(
                workspaceCurrency = ugx,
                commitmentCurrency = usd,
                targetMinor = 10_000L,
                targetWorkspaceMinor = target,
                exchangeRate = rate,
                exchangeRateDate = date,
                todayEpochDay = 0L,
            )

        assertEquals("rate_missing_or_invalid", error(null, "1970-01-01"))
        assertEquals("rate_invalid", error("0", "1970-01-01"))
        assertEquals("rate_invalid", error("١.٢", "1970-01-01"))
        assertEquals("rate_invalid", error("1.234567890123456789012345678901234567", "1970-01-01"))
        assertEquals("rate_date_missing", error("3600", null))
        assertEquals("rate_date_invalid", error("3600", "1970-02-30"))
        assertEquals("rate_date_invalid", error("3600", "١970-01-01"))
        assertEquals("rate_date_future", error("3600", "1970-01-02"))
        assertEquals("converted_target_mismatch", error("3600", "1970-01-01", 359_999L))
        assertEquals("target_invalid", CommitmentRules.validationError(ugx, usd, 0L, 1L, "3600", "1970-01-01", 0L))
    }

    @Test
    fun malformedCurrenciesAndOverflowAreRejectedWithoutWrapping() {
        assertEquals(
            "currency_unsupported",
            CommitmentRules.validationError(null, usd, 1L, 1L, null, null, 0L),
        )
        assertEquals(
            "currency_unsupported",
            CommitmentRules.validationError(ugx, null, 1L, 1L, null, null, 0L),
        )
        assertFailsWith<ArithmeticException> {
            CommitmentRules.commitmentToWorkspaceMinor(
                amountMinor = 9_000_000_000_000_000L,
                commitmentCurrency = Currency("SRC", "", "Source", 0),
                workspaceCurrency = Currency("TGT", "", "Target", 6),
                exchangeRate = "999999999999999999999999999999999999",
            )
        }
    }
}
