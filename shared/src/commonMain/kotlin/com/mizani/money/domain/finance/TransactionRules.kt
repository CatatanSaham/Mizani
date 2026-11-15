package com.mizani.money.domain.finance

import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.money.MoneyLimits

/** Platform-independent entry rules shared by the Android and iOS transaction repositories. */
object TransactionRules {
    fun validateFee(feeMinor: Long) {
        require(feeMinor >= 0L) { "Fee cannot be negative" }
        require(feeMinor <= MoneyLimits.MAX_MINOR_AMOUNT) { "Fee is outside the supported amount range" }
    }

    fun validateAmount(type: TransactionType, amountMinor: Long) {
        when (type) {
            TransactionType.EXPENSE,
            TransactionType.INCOME ->
                require(amountMinor > 0L) { "Amount must be greater than zero" }
            TransactionType.TRANSFER -> require(amountMinor > 0L) { "Transfer amount must be positive" }
            TransactionType.REFUND -> require(amountMinor > 0L) { "Refund amount must be positive" }
            TransactionType.ADJUSTMENT -> require(amountMinor != 0L) { "Adjustment cannot be zero" }
        }
        require(amountMinor in -MoneyLimits.MAX_MINOR_AMOUNT..MoneyLimits.MAX_MINOR_AMOUNT) {
            "Transaction amount is outside the supported range"
        }
    }
}
