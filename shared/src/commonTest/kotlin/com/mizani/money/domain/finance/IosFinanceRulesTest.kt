package com.mizani.money.domain.finance

import com.mizani.money.core.model.SharedDefaultCategories
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class IosFinanceRulesTest {
    @Test
    fun nativeAppLockPolicyUsesSharedPinRules() {
        assertEquals(6, IosFinanceRules.appLockPinLength())
        assertEquals(120_000, IosFinanceRules.appLockPbkdf2Iterations())
        assertEquals(15_000L, IosFinanceRules.appLockBackgroundGracePeriodMs())
        assertEquals(true, IosFinanceRules.isValidAppLockPin("019284"))
        assertEquals(false, IosFinanceRules.isValidAppLockPin("01928a"))
        assertEquals(5_000L, IosFinanceRules.appLockBackoffMs(5))
        assertEquals(10_000L, IosFinanceRules.appLockBlockedRemainingMs(6, 100_000L, 100_000L))
    }

    @Test
    fun transactionValidationUsesCanonicalSharedRules() {
        assertNull(IosFinanceRules.transactionValidationError("EXPENSE", 125L, 0L))
        assertEquals("amount_invalid", IosFinanceRules.transactionValidationError("EXPENSE", 0L, 0L))
        assertEquals("fee_invalid", IosFinanceRules.transactionValidationError("INCOME", 1L, -1L))
        assertEquals("transaction_type_invalid", IosFinanceRules.transactionValidationError("UNKNOWN", 1L, 0L))
    }

    @Test
    fun nativeWalletAndAmountChecksUseSharedEnumsAndLimits() {
        assertEquals(true, IosFinanceRules.isValidWalletTypeName("MOBILE_MONEY"))
        assertEquals(false, IosFinanceRules.isValidWalletTypeName("CHEQUE"))
        assertEquals(true, IosFinanceRules.isSupportedAmountMinor(9_000_000_000_000_000L))
        assertEquals(false, IosFinanceRules.isSupportedAmountMinor(9_000_000_000_000_001L))
        assertEquals(true, IosFinanceRules.isSupportedCurrencyCode("UGX"))
        assertEquals(false, IosFinanceRules.isSupportedCurrencyCode("ZZZ"))
    }

    @Test
    fun nativeGoalAmountChecksAndAllocationUseSharedRules() {
        assertEquals(true, IosFinanceRules.isSupportedGoalTargetMinor(1L))
        assertEquals(false, IosFinanceRules.isSupportedGoalTargetMinor(0L))
        assertEquals(false, IosFinanceRules.isSupportedGoalTargetMinor(9_000_000_000_000_001L))
        assertEquals(true, IosFinanceRules.isSupportedGoalContributionMinor(1L))
        assertEquals(false, IosFinanceRules.isSupportedGoalContributionMinor(-1L))
        assertEquals("150", IosFinanceRules.goalAllocatedMinorAfterContribution(100L, 50L))
        assertEquals(null, IosFinanceRules.goalAllocatedMinorAfterContribution(9_000_000_000_000_000L, 1L))
    }

    @Test
    fun nativeSetupCatalogExposesCurrencyPrecisionCountryChoicesAndWalletTypes() {
        assertEquals(10, IosFinanceRules.currencyCount())
        assertEquals(0, IosFinanceRules.currencyMinorUnits("UGX"))
        assertEquals(2, IosFinanceRules.currencyMinorUnits("USD"))
        assertEquals(-1, IosFinanceRules.currencyMinorUnits("ZZZ"))
        assertEquals("1235", IosFinanceRules.parseMoneyInput("12.345", "USD", ".", ","))
        assertEquals("1235", IosFinanceRules.parseMoneyInput("1234.5", "UGX", ".", ","))
        assertEquals("123450", IosFinanceRules.parseMoneyInput("1.234,50", "EUR", ",", "."))
        assertEquals(null, IosFinanceRules.parseMoneyInput("1", "ZZZ", ".", ","))
        assertEquals("UGX", IosFinanceRules.countryAt(0)?.currencyCode)
        assertEquals("OT", IosFinanceRules.countryAt(IosFinanceRules.countryCount() - 1)?.code)
        assertTrue(IosFinanceRules.walletTypeCount() > 0)
        assertEquals("CASH", IosFinanceRules.walletTypeAt(0)?.name)
    }

    @Test
    fun nativeIncomeSourceKindsKeepSharedPersistedNamesAndLabels() {
        val kinds = (0 until IosFinanceRules.incomeSourceKindCount()).mapNotNull {
            IosFinanceRules.incomeSourceKindAt(it)
        }

        assertEquals(
            listOf("SALARY", "BUSINESS", "FREELANCE", "GIG", "REMITTANCE", "FARMING", "OTHER"),
            kinds.map { it.name },
        )
        assertEquals("Casual / gig work", kinds.first { it.name == "GIG" }.label)
        assertEquals(null, IosFinanceRules.incomeSourceKindAt(-1))
        assertEquals(null, IosFinanceRules.incomeSourceKindAt(kinds.size))
    }

    @Test
    fun walletBalanceUsesCanonicalSharedLedgerRules() {
        assertEquals(
            "945",
            IosFinanceRules.walletBalanceMinor(
                walletId = "cash",
                openingBalanceMinor = 1_000L,
                transactionTypes = listOf("EXPENSE", "INCOME", "EXPENSE"),
                amountsMinor = listOf(100L, 50L, 25L),
                feesMinor = listOf(5L, 0L, 0L),
                sourceWalletIds = listOf("cash", "cash", "cash"),
                destinationWalletIds = listOf(null, null, null),
                deleted = listOf(false, false, true),
            ),
        )
    }

    @Test
    fun walletBalanceAccountsForIncomingTransferAndDetectsMalformedInputs() {
        assertEquals(
            "250",
            IosFinanceRules.walletBalanceMinor(
                walletId = "savings",
                openingBalanceMinor = 0L,
                transactionTypes = listOf("TRANSFER"),
                amountsMinor = listOf(250L),
                feesMinor = listOf(5L),
                sourceWalletIds = listOf("cash"),
                destinationWalletIds = listOf("savings"),
                deleted = listOf(false),
            ),
        )
        assertNull(
            IosFinanceRules.walletBalanceMinor(
                walletId = "cash",
                openingBalanceMinor = 0L,
                transactionTypes = listOf("EXPENSE"),
                amountsMinor = emptyList(),
                feesMinor = listOf(0L),
                sourceWalletIds = listOf("cash"),
                destinationWalletIds = listOf(null),
                deleted = listOf(false),
            ),
        )
    }

    @Test
    fun nativeAnalyticsSummaryUsesSharedRulesAndRejectsMalformedSnapshotColumns() {
        val summary = IosFinanceRules.ledgerAnalyticsSummary(
            transactionTypes = listOf("EXPENSE", "INCOME"),
            amountsMinor = listOf(100L, 200L),
            feesMinor = listOf(5L, 0L),
            categoryIds = listOf("food", "salary"),
            feeCategoryIds = listOf(null, null),
            localDateEpochDays = listOf(10L, 10L),
            deleted = listOf(false, false),
            startEpochDay = 10L,
            endEpochDay = 20L,
        )

        assertEquals(200L, summary?.incomeMinor)
        assertEquals(105L, summary?.expenseMinor)
        assertEquals(5L, summary?.feesMinor)
        assertEquals(95L, summary?.netMinor)
        assertEquals(2, summary?.categoryCount())
        assertEquals("food", summary?.categoryAt(0)?.categoryId)
        assertEquals(SharedDefaultCategories.feesId(), summary?.categoryAt(1)?.categoryId)
        assertNull(summary?.categoryAt(2))

        assertNull(
            IosFinanceRules.ledgerAnalyticsSummary(
                transactionTypes = listOf("UNKNOWN"),
                amountsMinor = listOf(1L),
                feesMinor = listOf(0L),
                categoryIds = listOf(null),
                feeCategoryIds = listOf(null),
                localDateEpochDays = listOf(10L),
                deleted = listOf(false),
                startEpochDay = 10L,
                endEpochDay = 20L,
            ),
        )
        assertNull(
            IosFinanceRules.ledgerAnalyticsSummary(
                transactionTypes = listOf("EXPENSE"),
                amountsMinor = emptyList(),
                feesMinor = listOf(0L),
                categoryIds = listOf("food"),
                feeCategoryIds = listOf(null),
                localDateEpochDays = listOf(10L),
                deleted = listOf(false),
                startEpochDay = 10L,
                endEpochDay = 20L,
            ),
        )
    }
}
