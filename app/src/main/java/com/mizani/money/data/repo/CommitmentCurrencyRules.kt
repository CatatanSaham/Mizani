package com.mizani.money.data.repo

import com.mizani.money.core.money.Currencies
import com.mizani.money.domain.finance.CommitmentRules
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneOffset

/** Android adapter for the shared commitment validation and conversion rules. */
internal object CommitmentCurrencyRules {
    fun validate(
        workspaceCurrencyCode: String,
        currencyCode: String,
        targetMinor: Long,
        targetWorkspaceMinor: Long,
        exchangeRate: String?,
        exchangeRateDate: String?,
    ) {
        val workspaceCurrency = Currencies.all.firstOrNull { it.code == workspaceCurrencyCode }
            ?: throw IllegalArgumentException("Workspace currency is not supported")
        val commitmentCurrency = Currencies.transactionCurrencies.firstOrNull { it.code == currencyCode }
            ?: throw IllegalArgumentException("Commitment currency is not supported")
        val error = CommitmentRules.validationError(
            workspaceCurrency = workspaceCurrency,
            commitmentCurrency = commitmentCurrency,
            targetMinor = targetMinor,
            targetWorkspaceMinor = targetWorkspaceMinor,
            exchangeRate = exchangeRate,
            exchangeRateDate = exchangeRateDate,
            todayEpochDay = LocalDate.now(ZoneOffset.UTC).toEpochDay(),
        )
        require(error == null) { messageFor(error!!) }
    }

    fun commitmentToWorkspaceMinor(
        amountMinor: Long,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: BigDecimal?,
    ): Long {
        val workspace = Currencies.all.firstOrNull { it.code == workspaceCurrencyCode }
            ?: throw IllegalArgumentException("Workspace currency is not supported")
        val commitment = Currencies.transactionCurrencies.firstOrNull { it.code == commitmentCurrencyCode }
            ?: throw IllegalArgumentException("Commitment currency is not supported")
        if (workspace.code == commitment.code) return amountMinor
        return CommitmentRules.commitmentToWorkspaceMinor(
            amountMinor = amountMinor,
            commitmentCurrency = commitment,
            workspaceCurrency = workspace,
            exchangeRate = requireNotNull(exchangeRate) { "Exchange rate is required for a foreign commitment" }.toString(),
        )
    }

    fun workspaceToCommitmentMinor(
        amountMinor: Long,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: BigDecimal?,
    ): Long {
        val workspace = Currencies.all.firstOrNull { it.code == workspaceCurrencyCode }
            ?: throw IllegalArgumentException("Workspace currency is not supported")
        val commitment = Currencies.transactionCurrencies.firstOrNull { it.code == commitmentCurrencyCode }
            ?: throw IllegalArgumentException("Commitment currency is not supported")
        if (workspace.code == commitment.code) return amountMinor
        return CommitmentRules.workspaceToCommitmentMinor(
            amountMinor = amountMinor,
            workspaceCurrency = workspace,
            commitmentCurrency = commitment,
            exchangeRate = requireNotNull(exchangeRate) { "Exchange rate is required for a foreign commitment" }.toString(),
        )
    }

    private fun messageFor(error: String): String = when (error) {
        "target_invalid" -> "Enter a valid commitment amount"
        "target_workspace_invalid" -> "The converted commitment amount is invalid"
        "same_currency_target_mismatch" -> "A workspace-currency commitment cannot have a converted target"
        "same_currency_rate_present" -> "A workspace-currency commitment cannot have an exchange rate"
        "rate_missing_or_invalid" -> "Exchange rate is missing or invalid"
        "rate_invalid" -> "Exchange rate is invalid"
        "rate_date_missing" -> "Exchange-rate date is missing"
        "rate_date_invalid" -> "Exchange-rate date is invalid"
        "rate_date_future" -> "Exchange-rate date cannot be in the future"
        "converted_target_invalid" -> "The converted commitment amount is invalid"
        "converted_target_mismatch" -> "Converted commitment amount does not match the saved exchange rate"
        else -> "Commitment currency is not supported"
    }
}
