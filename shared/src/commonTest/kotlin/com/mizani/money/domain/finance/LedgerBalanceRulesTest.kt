package com.mizani.money.domain.finance

import com.mizani.money.core.model.TransactionType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class LedgerBalanceRulesTest {
    @Test
    fun derivesBalancesForAllTransactionTypes() {
        val balances = LedgerBalanceRules.walletBalances(
            wallets = listOf(
                WalletBalanceInput("cash", 1_000L),
                WalletBalanceInput("bank", 200L),
            ),
            transactions = listOf(
                TransactionBalanceInput(TransactionType.INCOME, 500L, 0L, "cash"),
                TransactionBalanceInput(TransactionType.EXPENSE, 200L, 5L, "cash"),
                TransactionBalanceInput(TransactionType.TRANSFER, 100L, 2L, "cash", "bank"),
                TransactionBalanceInput(TransactionType.REFUND, 30L, 1L, "cash"),
                TransactionBalanceInput(TransactionType.ADJUSTMENT, -10L, 0L, "bank"),
                TransactionBalanceInput(TransactionType.INCOME, 900L, 0L, "cash", deleted = true),
            ),
        )

        assertEquals(mapOf("cash" to 1_222L, "bank" to 290L), balances)
    }

    @Test
    fun transferWithoutDestinationOnlyReducesSourceWallet() {
        val balances = LedgerBalanceRules.walletBalances(
            wallets = listOf(WalletBalanceInput("cash", 500L)),
            transactions = listOf(
                TransactionBalanceInput(TransactionType.TRANSFER, 100L, 3L, "cash"),
            ),
        )

        assertEquals(mapOf("cash" to 397L), balances)
    }

    @Test
    fun incomeFeeIsDeductedFromWalletCredit() {
        val balances = LedgerBalanceRules.walletBalances(
            wallets = listOf(WalletBalanceInput("cash", 500L)),
            transactions = listOf(
                TransactionBalanceInput(TransactionType.INCOME, 100L, 7L, "cash"),
            ),
        )

        assertEquals(mapOf("cash" to 593L), balances)
    }

    @Test
    fun breakdownExplainsTheSameBalanceAcrossAllLedgerTypes() {
        val breakdowns = LedgerBalanceRules.walletBalanceBreakdowns(
            wallets = listOf(
                WalletBalanceInput("cash", 125_000L),
                WalletBalanceInput("bank", 500L),
            ),
            transactions = listOf(
                TransactionBalanceInput(TransactionType.INCOME, 10_000L, 250L, "cash"),
                TransactionBalanceInput(TransactionType.EXPENSE, 1_000L, 15L, "cash"),
                TransactionBalanceInput(TransactionType.TRANSFER, 500L, 10L, "cash", "bank"),
                TransactionBalanceInput(TransactionType.REFUND, 200L, 10L, "cash"),
                TransactionBalanceInput(TransactionType.ADJUSTMENT, -200L, 0L, "cash"),
                TransactionBalanceInput(TransactionType.EXPENSE, 777L, 0L, "cash", deleted = true),
            ),
        )

        assertEquals(
            WalletBalanceBreakdown(
                openingBalanceMinor = 125_000L,
                incomeNetMinor = 9_750L,
                expenseOutflowMinor = -1_015L,
                transferInMinor = 0L,
                transferOutMinor = -510L,
                refundNetMinor = 190L,
                adjustmentMinor = -200L,
                currentBalanceMinor = 133_215L,
            ),
            breakdowns.getValue("cash"),
        )
        assertEquals(1_000L, breakdowns.getValue("bank").currentBalanceMinor)
    }

    @Test
    fun adjustmentToTargetUsesSignedExactDifference() {
        assertEquals(
            -29_235L,
            LedgerBalanceRules.adjustmentToTarget(
                currentBalanceMinor = 125_000L,
                targetBalanceMinor = 95_765L,
            ),
        )
        assertEquals(29_235L, LedgerBalanceRules.adjustmentToTarget(95_765L, 125_000L))
        assertEquals(0L, LedgerBalanceRules.adjustmentToTarget(95_765L, 95_765L))
    }

    @Test
    fun adjustmentToTargetRejectsOverflow() {
        assertFailsWith<ArithmeticException> {
            LedgerBalanceRules.adjustmentToTarget(Long.MAX_VALUE, Long.MIN_VALUE)
        }
    }

    @Test
    fun rejectsOverflowInsteadOfWrappingWalletBalances() {
        assertFailsWith<ArithmeticException> {
            LedgerBalanceRules.walletBalances(
                wallets = listOf(WalletBalanceInput("cash", Long.MAX_VALUE)),
                transactions = listOf(
                    TransactionBalanceInput(TransactionType.INCOME, 1L, 0L, "cash"),
                ),
            )
        }
    }
}
