package com.mizani.money.domain.finance

/** Keeps source metadata attached only to income entries on every platform. */
object IncomeSourceRules {
    fun canAssign(transactionTypeName: String, hasIncomeSource: Boolean): Boolean =
        !hasIncomeSource || transactionTypeName == "INCOME"
}
