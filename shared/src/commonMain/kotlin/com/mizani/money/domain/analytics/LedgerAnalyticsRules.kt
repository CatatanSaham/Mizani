package com.mizani.money.domain.analytics

import com.mizani.money.core.model.SharedDefaultCategories
import com.mizani.money.core.model.TransactionType

/** Platform-neutral transaction fields needed for deterministic ledger analytics. */
data class AnalyticsTransactionInput(
    val type: TransactionType,
    val amountMinor: Long,
    val feeMinor: Long,
    val categoryId: String?,
    val feeCategoryId: String?,
    val localDateEpochDay: Long,
    val deleted: Boolean,
)

/** Totals for one inclusive local-date range, with every amount kept in integer minor units. */
data class LedgerAnalyticsSummary(
    val incomeMinor: Long,
    val expenseMinor: Long,
    val feesMinor: Long,
    val refundsMinor: Long,
    val netMinor: Long,
    val categorySpendMinor: Map<String, Long>,
)

/** Shared posted-ledger analytics used by Android and the native iOS client. */
object LedgerAnalyticsRules {
    const val UNCATEGORISED = "uncategorised"

    fun summarize(
        transactions: List<AnalyticsTransactionInput>,
        startEpochDay: Long,
        endEpochDay: Long,
    ): LedgerAnalyticsSummary {
        require(startEpochDay <= endEpochDay) { "End date must not be before start date" }

        var incomeMinor = 0L
        var feesMinor = 0L
        var refundsMinor = 0L
        val categorySpend = mutableMapOf<String, Long>()

        for (transaction in transactions) {
            if (transaction.deleted || transaction.localDateEpochDay !in startEpochDay..endEpochDay) continue

            feesMinor = addExact(feesMinor, transaction.feeMinor)
            when (transaction.type) {
                TransactionType.INCOME -> {
                    incomeMinor = addExact(incomeMinor, transaction.amountMinor)
                    addPositiveFee(categorySpend, transaction)
                }
                TransactionType.EXPENSE -> {
                    add(categorySpend, transaction.categoryId ?: UNCATEGORISED, transaction.amountMinor)
                    addPositiveFee(categorySpend, transaction)
                }
                TransactionType.TRANSFER -> addPositiveFee(categorySpend, transaction)
                TransactionType.REFUND -> {
                    refundsMinor = addExact(refundsMinor, transaction.amountMinor)
                    add(
                        categorySpend,
                        transaction.categoryId ?: UNCATEGORISED,
                        negateExact(transaction.amountMinor),
                    )
                    addPositiveFee(categorySpend, transaction)
                }
                TransactionType.ADJUSTMENT -> Unit
            }
        }

        val expenseMinor = categorySpend.values.fold(0L, ::addExact)
        return LedgerAnalyticsSummary(
            incomeMinor = incomeMinor,
            expenseMinor = expenseMinor,
            feesMinor = feesMinor,
            refundsMinor = refundsMinor,
            netMinor = subtractExact(incomeMinor, expenseMinor),
            categorySpendMinor = categorySpend.toMap(),
        )
    }

    private fun addPositiveFee(
        categorySpend: MutableMap<String, Long>,
        transaction: AnalyticsTransactionInput,
    ) {
        if (transaction.feeMinor > 0L) {
            add(categorySpend, transaction.feeCategoryId ?: SharedDefaultCategories.feesId(), transaction.feeMinor)
        }
    }

    private fun add(totals: MutableMap<String, Long>, categoryId: String, amountMinor: Long) {
        totals[categoryId] = addExact(totals[categoryId] ?: 0L, amountMinor)
    }

    private fun addExact(left: Long, right: Long): Long {
        val result = left + right
        if (((left xor result) and (right xor result)) < 0L) {
            throw ArithmeticException("Long overflow while summing analytics")
        }
        return result
    }

    private fun subtractExact(left: Long, right: Long): Long {
        val result = left - right
        if (((left xor right) and (left xor result)) < 0L) {
            throw ArithmeticException("Long overflow while subtracting analytics")
        }
        return result
    }

    private fun negateExact(value: Long): Long {
        if (value == Long.MIN_VALUE) throw ArithmeticException("Long overflow while negating analytics")
        return -value
    }
}
