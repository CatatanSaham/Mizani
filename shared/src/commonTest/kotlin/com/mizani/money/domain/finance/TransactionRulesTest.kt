package com.mizani.money.domain.finance

import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.money.MoneyLimits
import kotlin.test.Test
import kotlin.test.assertFailsWith

class TransactionRulesTest {
    @Test
    fun incomeExpenseTransferAndRefundRequirePositiveAmounts() {
        listOf(
            TransactionType.EXPENSE,
            TransactionType.INCOME,
            TransactionType.TRANSFER,
            TransactionType.REFUND,
        ).forEach { type ->
            assertFailsWith<IllegalArgumentException> {
                TransactionRules.validateAmount(type, 0L)
            }
            assertFailsWith<IllegalArgumentException> {
                TransactionRules.validateAmount(type, -1L)
            }
        }
    }

    @Test
    fun adjustmentIsSignedButCannotBeZero() {
        TransactionRules.validateAmount(TransactionType.ADJUSTMENT, -1L)
        TransactionRules.validateAmount(TransactionType.ADJUSTMENT, 1L)
        assertFailsWith<IllegalArgumentException> {
            TransactionRules.validateAmount(TransactionType.ADJUSTMENT, 0L)
        }
    }

    @Test
    fun transactionAmountsCannotExceedTheSupportedMinorUnitRange() {
        listOf(
            TransactionType.EXPENSE,
            TransactionType.INCOME,
            TransactionType.TRANSFER,
            TransactionType.REFUND,
        ).forEach { type ->
            TransactionRules.validateAmount(type, MoneyLimits.MAX_MINOR_AMOUNT)
            assertFailsWith<IllegalArgumentException> {
                TransactionRules.validateAmount(type, MoneyLimits.MAX_MINOR_AMOUNT + 1L)
            }
        }

        TransactionRules.validateAmount(TransactionType.ADJUSTMENT, MoneyLimits.MAX_MINOR_AMOUNT)
        TransactionRules.validateAmount(TransactionType.ADJUSTMENT, -MoneyLimits.MAX_MINOR_AMOUNT)
        assertFailsWith<IllegalArgumentException> {
            TransactionRules.validateAmount(TransactionType.ADJUSTMENT, MoneyLimits.MAX_MINOR_AMOUNT + 1L)
        }
        assertFailsWith<IllegalArgumentException> {
            TransactionRules.validateAmount(TransactionType.ADJUSTMENT, -MoneyLimits.MAX_MINOR_AMOUNT - 1L)
        }
    }

    @Test
    fun feeCannotBeNegative() {
        TransactionRules.validateFee(0L)
        TransactionRules.validateFee(1L)
        TransactionRules.validateFee(MoneyLimits.MAX_MINOR_AMOUNT)
        assertFailsWith<IllegalArgumentException> {
            TransactionRules.validateFee(-1L)
        }
        assertFailsWith<IllegalArgumentException> {
            TransactionRules.validateFee(MoneyLimits.MAX_MINOR_AMOUNT + 1L)
        }
    }
}
