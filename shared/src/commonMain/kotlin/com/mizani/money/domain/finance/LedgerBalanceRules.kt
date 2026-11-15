package com.mizani.money.domain.finance

import com.mizani.money.core.model.TransactionType

/** Platform-neutral balance inputs mapped from each client's local persistence models. */
data class WalletBalanceInput(
    val id: String,
    val openingBalanceMinor: Long,
)

data class TransactionBalanceInput(
    val type: TransactionType,
    val amountMinor: Long,
    val feeMinor: Long,
    val walletId: String,
    val toWalletId: String? = null,
    val deleted: Boolean = false,
)

/** Signed ledger contributions that explain a wallet's derived balance. */
data class WalletBalanceBreakdown(
    val openingBalanceMinor: Long,
    val incomeNetMinor: Long,
    val expenseOutflowMinor: Long,
    val transferInMinor: Long,
    val transferOutMinor: Long,
    val refundNetMinor: Long,
    val adjustmentMinor: Long,
    val currentBalanceMinor: Long,
)

/** Deterministic wallet balances derived from the canonical transaction ledger. */
object LedgerBalanceRules {
    fun walletBalances(
        wallets: List<WalletBalanceInput>,
        transactions: List<TransactionBalanceInput>,
    ): Map<String, Long> {
        val balances = wallets.associate { it.id to it.openingBalanceMinor }.toMutableMap()
        for (transaction in transactions) {
            forEachDelta(transaction) { delta ->
                add(balances, delta.walletId, delta.amountMinor)
            }
        }
        return balances
    }

    /**
     * Returns the same posted-ledger balance with signed totals grouped by activity type.
     * Category totals are also checked; callers may omit this explanation if they overflow,
     * while [walletBalances] remains the canonical balance calculation.
     */
    fun walletBalanceBreakdowns(
        wallets: List<WalletBalanceInput>,
        transactions: List<TransactionBalanceInput>,
    ): Map<String, WalletBalanceBreakdown> {
        val balances = wallets.associate { it.id to it.openingBalanceMinor }.toMutableMap()
        val parts = wallets.associate { it.id to MutableBreakdown(it.openingBalanceMinor) }.toMutableMap()
        for (transaction in transactions) {
            forEachDelta(transaction) { delta ->
                add(balances, delta.walletId, delta.amountMinor)
                parts.getOrPut(delta.walletId) { MutableBreakdown(0L) }.add(delta)
            }
        }
        return parts.mapValues { (walletId, part) ->
            part.toResult(balances[walletId] ?: 0L)
        }
    }

    /** Signed adjustment required to bring a derived balance to a user-entered statement balance. */
    fun adjustmentToTarget(currentBalanceMinor: Long, targetBalanceMinor: Long): Long =
        subtractExact(targetBalanceMinor, currentBalanceMinor)

    private fun add(balances: MutableMap<String, Long>, walletId: String, delta: Long) {
        balances[walletId] = addExact(balances[walletId] ?: 0L, delta)
    }

    private inline fun forEachDelta(
        transaction: TransactionBalanceInput,
        action: (BalanceDelta) -> Unit,
    ) {
        if (transaction.deleted) return
        when (transaction.type) {
            TransactionType.INCOME -> action(
                BalanceDelta(
                    transaction.walletId,
                    subtractExact(transaction.amountMinor, transaction.feeMinor),
                    BalanceComponent.INCOME,
                ),
            )
            TransactionType.EXPENSE -> action(
                BalanceDelta(
                    transaction.walletId,
                    negateExact(addExact(transaction.amountMinor, transaction.feeMinor)),
                    BalanceComponent.EXPENSE,
                ),
            )
            TransactionType.TRANSFER -> {
                action(
                    BalanceDelta(
                        transaction.walletId,
                        negateExact(addExact(transaction.amountMinor, transaction.feeMinor)),
                        BalanceComponent.TRANSFER_OUT,
                    ),
                )
                transaction.toWalletId?.let { destination ->
                    action(BalanceDelta(destination, transaction.amountMinor, BalanceComponent.TRANSFER_IN))
                }
            }
            TransactionType.REFUND -> action(
                BalanceDelta(
                    transaction.walletId,
                    subtractExact(transaction.amountMinor, transaction.feeMinor),
                    BalanceComponent.REFUND,
                ),
            )
            TransactionType.ADJUSTMENT -> action(
                BalanceDelta(transaction.walletId, transaction.amountMinor, BalanceComponent.ADJUSTMENT),
            )
        }
    }
}

private data class BalanceDelta(
    val walletId: String,
    val amountMinor: Long,
    val component: BalanceComponent,
)

private enum class BalanceComponent {
    INCOME,
    EXPENSE,
    TRANSFER_IN,
    TRANSFER_OUT,
    REFUND,
    ADJUSTMENT,
}

private class MutableBreakdown(openingBalanceMinor: Long) {
    var incomeNetMinor = 0L
        private set
    var expenseOutflowMinor = 0L
        private set
    var transferInMinor = 0L
        private set
    var transferOutMinor = 0L
        private set
    var refundNetMinor = 0L
        private set
    var adjustmentMinor = 0L
        private set

    val openingBalanceMinor = openingBalanceMinor

    fun add(delta: BalanceDelta) {
        when (delta.component) {
            BalanceComponent.INCOME -> incomeNetMinor = addExact(incomeNetMinor, delta.amountMinor)
            BalanceComponent.EXPENSE -> expenseOutflowMinor = addExact(expenseOutflowMinor, delta.amountMinor)
            BalanceComponent.TRANSFER_IN -> transferInMinor = addExact(transferInMinor, delta.amountMinor)
            BalanceComponent.TRANSFER_OUT -> transferOutMinor = addExact(transferOutMinor, delta.amountMinor)
            BalanceComponent.REFUND -> refundNetMinor = addExact(refundNetMinor, delta.amountMinor)
            BalanceComponent.ADJUSTMENT -> adjustmentMinor = addExact(adjustmentMinor, delta.amountMinor)
        }
    }

    fun toResult(currentBalanceMinor: Long) = WalletBalanceBreakdown(
        openingBalanceMinor = openingBalanceMinor,
        incomeNetMinor = incomeNetMinor,
        expenseOutflowMinor = expenseOutflowMinor,
        transferInMinor = transferInMinor,
        transferOutMinor = transferOutMinor,
        refundNetMinor = refundNetMinor,
        adjustmentMinor = adjustmentMinor,
        currentBalanceMinor = currentBalanceMinor,
    )
}

private fun addExact(left: Long, right: Long): Long {
    val result = left + right
    if (((left xor result) and (right xor result)) < 0L) {
        throw ArithmeticException("Long overflow while adding wallet balance")
    }
    return result
}

private fun subtractExact(left: Long, right: Long): Long {
    val result = left - right
    if (((left xor right) and (left xor result)) < 0L) {
        throw ArithmeticException("Long overflow while subtracting wallet balance")
    }
    return result
}

private fun negateExact(value: Long): Long {
    if (value == Long.MIN_VALUE) throw ArithmeticException("Long overflow while negating wallet balance")
    return -value
}
