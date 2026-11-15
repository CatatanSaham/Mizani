package com.mizani.money.domain.analytics

import com.mizani.money.core.model.SharedDefaultCategories
import com.mizani.money.core.model.TransactionType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class LedgerAnalyticsRulesTest {
    @Test
    fun countsPostedIncomeExpensesFeesTransfersRefundsAndAdjustmentsLikeAndroid() {
        val feesCategoryId = SharedDefaultCategories.feesId()
        val result = LedgerAnalyticsRules.summarize(
            transactions = listOf(
                transaction(TransactionType.EXPENSE, amount = 100L, fee = 5L, category = "food", feeCategory = "card-fees"),
                transaction(TransactionType.TRANSFER, amount = 30L, fee = 2L, day = 11L),
                transaction(TransactionType.REFUND, amount = 20L, fee = 3L, category = "food", day = 12L),
                transaction(TransactionType.INCOME, amount = 50L, category = "salary", day = 13L),
                transaction(TransactionType.ADJUSTMENT, amount = 999L, fee = 4L, category = "food", day = 14L),
                transaction(TransactionType.EXPENSE, amount = 1_000L, category = "food", deleted = true),
                transaction(TransactionType.EXPENSE, amount = 2_000L, category = "food", day = 21L),
            ),
            startEpochDay = 10L,
            endEpochDay = 20L,
        )

        assertEquals(50L, result.incomeMinor)
        assertEquals(90L, result.expenseMinor)
        assertEquals(14L, result.feesMinor)
        assertEquals(20L, result.refundsMinor)
        assertEquals(-40L, result.netMinor)
        assertEquals(mapOf("food" to 80L, "card-fees" to 5L, feesCategoryId to 5L), result.categorySpendMinor)
    }

    @Test
    fun includesBothRangeBoundariesAndAllowsRefundsToExceedRecordedSpending() {
        val result = LedgerAnalyticsRules.summarize(
            transactions = listOf(
                transaction(TransactionType.EXPENSE, amount = 40L, category = "food", day = 10L),
                transaction(TransactionType.REFUND, amount = 70L, category = "food", day = 20L),
                transaction(TransactionType.INCOME, amount = 500L, day = 9L),
            ),
            startEpochDay = 10L,
            endEpochDay = 20L,
        )

        assertEquals(-30L, result.expenseMinor)
        assertEquals(0L, result.incomeMinor)
        assertEquals(-30L, result.categorySpendMinor["food"])
    }

    @Test
    fun incomeFeeIsRecordedAsSpendingAlongsideGrossIncome() {
        val feesCategoryId = SharedDefaultCategories.feesId()
        val result = LedgerAnalyticsRules.summarize(
            transactions = listOf(
                transaction(
                    TransactionType.INCOME,
                    amount = 100L,
                    fee = 7L,
                    category = "salary",
                    day = 10L,
                ),
            ),
            startEpochDay = 10L,
            endEpochDay = 20L,
        )

        assertEquals(100L, result.incomeMinor)
        assertEquals(7L, result.feesMinor)
        assertEquals(7L, result.expenseMinor)
        assertEquals(93L, result.netMinor)
        assertEquals(mapOf(feesCategoryId to 7L), result.categorySpendMinor)
    }

    @Test
    fun rejectsInvalidPeriodsAndLongOverflow() {
        assertFailsWith<IllegalArgumentException> {
            LedgerAnalyticsRules.summarize(emptyList(), startEpochDay = 2L, endEpochDay = 1L)
        }
        assertFailsWith<ArithmeticException> {
            LedgerAnalyticsRules.summarize(
                transactions = listOf(
                    transaction(TransactionType.INCOME, amount = Long.MAX_VALUE),
                    transaction(TransactionType.INCOME, amount = 1L),
                ),
                startEpochDay = 10L,
                endEpochDay = 20L,
            )
        }
        assertFailsWith<ArithmeticException> {
            LedgerAnalyticsRules.summarize(
                transactions = listOf(
                    transaction(TransactionType.REFUND, amount = Long.MIN_VALUE, category = "food"),
                ),
                startEpochDay = 10L,
                endEpochDay = 20L,
            )
        }
    }

    private fun transaction(
        type: TransactionType,
        amount: Long = 0L,
        fee: Long = 0L,
        category: String? = null,
        feeCategory: String? = null,
        day: Long = 10L,
        deleted: Boolean = false,
    ) = AnalyticsTransactionInput(
        type = type,
        amountMinor = amount,
        feeMinor = fee,
        categoryId = category,
        feeCategoryId = feeCategory,
        localDateEpochDay = day,
        deleted = deleted,
    )
}
