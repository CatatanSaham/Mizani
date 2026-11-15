package com.mizani.money.domain.finance

import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.model.WalletType
import com.mizani.money.core.model.IncomeSourceKind
import com.mizani.money.core.model.InvestmentAssetType
import com.mizani.money.core.model.SharedCountryCatalog
import com.mizani.money.core.model.SharedDefaultCategories
import com.mizani.money.core.money.Currency
import com.mizani.money.core.money.MoneyLimits
import com.mizani.money.core.money.MoneyInputRules
import com.mizani.money.core.money.SharedCurrencyCatalog
import com.mizani.money.core.security.PinPolicyRules
import com.mizani.money.domain.analytics.AnalyticsTransactionInput
import com.mizani.money.domain.analytics.LedgerAnalyticsRules

data class NativeCategoryDefinition(
    val id: String,
    val key: String,
    val name: String,
    val typeName: String,
    val icon: String,
    val colorHex: String,
)

data class NativeIncomeSourceKindDefinition(
    val name: String,
    val label: String,
)

data class NativeCurrencyDefinition(
    val code: String,
    val symbol: String,
    val name: String,
    val minorUnits: Int,
)

data class NativeCountryDefinition(
    val code: String,
    val name: String,
    val currencyCode: String,
)

data class NativeWalletTypeDefinition(
    val name: String,
    val label: String,
)

data class NativeInvestmentAssetTypeDefinition(
    val name: String,
    val label: String,
)

/** Swift-friendly checked projection of the shared portfolio aggregate. */
class NativeInvestmentPortfolioSummary internal constructor(
    val holdingCount: Int,
    val costBasisMinor: Long,
    val currentValueMinor: Long,
    val gainLossMinor: Long,
)

data class NativeAnalyticsCategoryTotal(
    val categoryId: String,
    val amountMinor: Long,
)

/** A Swift-friendly projection of the common analytics result without exposing a Kotlin map. */
class NativeLedgerAnalyticsSummary internal constructor(
    val incomeMinor: Long,
    val expenseMinor: Long,
    val feesMinor: Long,
    val refundsMinor: Long,
    val netMinor: Long,
    categorySpendMinor: Map<String, Long>,
) {
    private val categoryTotals = categorySpendMinor.entries
        .filter { it.value != 0L }
        .sortedWith(compareByDescending<Map.Entry<String, Long>> { it.value }.thenBy { it.key })
        .map { NativeAnalyticsCategoryTotal(categoryId = it.key, amountMinor = it.value) }

    fun categoryCount(): Int = categoryTotals.size

    fun categoryAt(index: Int): NativeAnalyticsCategoryTotal? = categoryTotals.getOrNull(index)
}

/** Narrow, stable entry points for the native Swift client to call the shared finance rules. */
object IosFinanceRules {
    fun appLockPinLength(): Int = PinPolicyRules.LENGTH

    fun appLockPbkdf2Iterations(): Int = PinPolicyRules.PBKDF2_ITERATIONS

    fun appLockBackgroundGracePeriodMs(): Long = PinPolicyRules.BACKGROUND_GRACE_PERIOD_MS

    fun isValidAppLockPin(pin: String): Boolean = PinPolicyRules.isValidPin(pin)

    fun appLockBackoffMs(failedAttempts: Int): Long = PinPolicyRules.backoffMs(failedAttempts)

    fun appLockBlockedRemainingMs(failedAttempts: Int, lastFailureAtMs: Long, nowMs: Long): Long =
        PinPolicyRules.blockedRemainingMs(failedAttempts, lastFailureAtMs, nowMs)

    fun isValidWalletTypeName(typeName: String): Boolean = WalletType.entries.any { it.name == typeName }

    fun isSupportedAmountMinor(amountMinor: Long): Boolean =
        amountMinor in -MoneyLimits.MAX_MINOR_AMOUNT..MoneyLimits.MAX_MINOR_AMOUNT

    fun isSupportedGoalTargetMinor(amountMinor: Long): Boolean =
        GoalRules.isValidTargetMinor(amountMinor)

    fun isSupportedGoalContributionMinor(amountMinor: Long): Boolean =
        GoalRules.isValidContributionMinor(amountMinor)

    /** Returns the updated allocation as text, or null when the contribution would be invalid. */
    fun goalAllocatedMinorAfterContribution(currentAllocatedMinor: Long, contributionMinor: Long): String? =
        GoalRules.allocatedMinorAfterContribution(currentAllocatedMinor, contributionMinor)?.toString()

    /** Validates commitment currency, saved daily rate, and the exact converted target. */
    fun commitmentDraftValidationError(
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        targetMinor: Long,
        targetWorkspaceMinor: Long,
        exchangeRate: String?,
        exchangeRateDate: String?,
        todayEpochDay: Long,
    ): String? = CommitmentRules.validationError(
        workspaceCurrency = SharedCurrencyCatalog.byCode(workspaceCurrencyCode),
        commitmentCurrency = SharedCurrencyCatalog.byCode(commitmentCurrencyCode),
        targetMinor = targetMinor,
        targetWorkspaceMinor = targetWorkspaceMinor,
        exchangeRate = exchangeRate,
        exchangeRateDate = exchangeRateDate,
        todayEpochDay = todayEpochDay,
    )

    /** Returns the converted minor units as text, or null for unsupported/overflowing input. */
    fun commitmentToWorkspaceMinor(
        amountMinor: Long,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?,
    ): String? = convertCommitmentAmount(
        amountMinor = amountMinor,
        workspaceCurrencyCode = workspaceCurrencyCode,
        commitmentCurrencyCode = commitmentCurrencyCode,
        exchangeRate = exchangeRate,
        toWorkspace = true,
    )

    /** Returns the converted minor units as text, or null for unsupported/overflowing input. */
    fun workspaceToCommitmentMinor(
        amountMinor: Long,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?,
    ): String? = convertCommitmentAmount(
        amountMinor = amountMinor,
        workspaceCurrencyCode = workspaceCurrencyCode,
        commitmentCurrencyCode = commitmentCurrencyCode,
        exchangeRate = exchangeRate,
        toWorkspace = false,
    )

    private fun convertCommitmentAmount(
        amountMinor: Long,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?,
        toWorkspace: Boolean,
    ): String? {
        val workspaceCurrency = SharedCurrencyCatalog.byCode(workspaceCurrencyCode) ?: return null
        val commitmentCurrency = SharedCurrencyCatalog.byCode(commitmentCurrencyCode) ?: return null
        if (workspaceCurrency.code == commitmentCurrency.code) return amountMinor.toString()
        val rate = exchangeRate ?: return null
        return try {
            (if (toWorkspace) {
                CommitmentRules.commitmentToWorkspaceMinor(
                    amountMinor = amountMinor,
                    commitmentCurrency = commitmentCurrency,
                    workspaceCurrency = workspaceCurrency,
                    exchangeRate = rate,
                )
            } else {
                CommitmentRules.workspaceToCommitmentMinor(
                    amountMinor = amountMinor,
                    workspaceCurrency = workspaceCurrency,
                    commitmentCurrency = commitmentCurrency,
                    exchangeRate = rate,
                )
            }).toString()
        } catch (_: IllegalArgumentException) {
            null
        } catch (_: ArithmeticException) {
            null
        }
    }

    fun isSupportedCurrencyCode(currencyCode: String): Boolean =
        SharedCurrencyCatalog.byCode(currencyCode) != null

    fun currencyCount(): Int = SharedCurrencyCatalog.curated.size

    fun currencyAt(index: Int): NativeCurrencyDefinition? =
        SharedCurrencyCatalog.curated.getOrNull(index)?.toNativeDefinition()

    fun currencyMinorUnits(currencyCode: String): Int =
        SharedCurrencyCatalog.byCode(currencyCode)?.minorUnits ?: -1

    fun parseMoneyInput(
        input: String,
        currencyCode: String,
        decimalSeparator: String,
        groupingSeparator: String,
    ): String? {
        val currency = SharedCurrencyCatalog.byCode(currencyCode) ?: return null
        return MoneyInputRules.parseMinorUnits(
            input = input,
            currencySymbol = currency.symbol,
            minorUnits = currency.minorUnits,
            decimalSeparator = decimalSeparator,
            groupingSeparator = groupingSeparator,
        )?.toString()
    }

    fun countryCount(): Int = SharedCountryCatalog.selectablePacks.size

    fun countryAt(index: Int): NativeCountryDefinition? =
        SharedCountryCatalog.selectablePacks.getOrNull(index)?.let { country ->
            NativeCountryDefinition(
                code = country.code,
                name = country.name,
                currencyCode = country.currencyCode,
            )
        }

    fun walletTypeCount(): Int = WalletType.entries.size

    fun walletTypeAt(index: Int): NativeWalletTypeDefinition? =
        WalletType.entries.getOrNull(index)?.let { type ->
            NativeWalletTypeDefinition(name = type.name, label = type.label)
        }

    fun investmentAssetTypeCount(): Int = InvestmentAssetType.entries.size

    fun investmentAssetTypeAt(index: Int): NativeInvestmentAssetTypeDefinition? =
        InvestmentAssetType.entries.getOrNull(index)?.let { type ->
            NativeInvestmentAssetTypeDefinition(name = type.name, label = type.label)
        }

    /** Returns a stable validation error code, or null when the investment draft is valid. */
    fun investmentDraftValidationError(
        name: String,
        provider: String,
        note: String,
        assetTypeName: String,
        costBasisMinor: Long,
        currentValueMinor: Long,
        valuationEpochDay: Long,
        todayEpochDay: Long,
    ): String? = InvestmentRules.validateDraft(
        name = name,
        provider = provider,
        note = note,
        assetTypeName = assetTypeName,
        costBasisMinor = costBasisMinor,
        currentValueMinor = currentValueMinor,
        valuationEpochDay = valuationEpochDay,
        todayEpochDay = todayEpochDay,
    )

    /** Returns null for mismatched columns, invalid active values, or aggregation overflow. */
    fun investmentPortfolioSummary(
        costBasisMinor: List<Long>,
        currentValueMinor: List<Long>,
        active: List<Boolean>,
    ): NativeInvestmentPortfolioSummary? = InvestmentRules.summarize(
        costBasisMinor = costBasisMinor,
        currentValueMinor = currentValueMinor,
        active = active,
    )?.let { summary ->
        NativeInvestmentPortfolioSummary(
            holdingCount = summary.holdingCount,
            costBasisMinor = summary.costBasisMinor,
            currentValueMinor = summary.currentValueMinor,
            gainLossMinor = summary.gainLossMinor,
        )
    }

    fun defaultCategoryCount(): Int = SharedDefaultCategories.all.size

    fun defaultCategoryAt(index: Int): NativeCategoryDefinition? =
        SharedDefaultCategories.all.getOrNull(index)?.let { category ->
            NativeCategoryDefinition(
                id = SharedDefaultCategories.categoryId(category.key),
                key = category.key,
                name = category.name,
                typeName = category.type.name,
                icon = category.icon,
                colorHex = category.colorHex,
            )
        }

    fun feesCategoryId(): String = SharedDefaultCategories.feesId()

    /**
     * Calculates posted income and spending from parallel native snapshot columns. Null indicates
     * malformed input, an unknown persisted transaction type, or checked integer overflow.
     */
    fun ledgerAnalyticsSummary(
        transactionTypes: List<String>,
        amountsMinor: List<Long>,
        feesMinor: List<Long>,
        categoryIds: List<String?>,
        feeCategoryIds: List<String?>,
        localDateEpochDays: List<Long>,
        deleted: List<Boolean>,
        startEpochDay: Long,
        endEpochDay: Long,
    ): NativeLedgerAnalyticsSummary? {
        val size = transactionTypes.size
        if (listOf(
                amountsMinor.size,
                feesMinor.size,
                categoryIds.size,
                feeCategoryIds.size,
                localDateEpochDays.size,
                deleted.size,
            ).any { it != size }
        ) return null

        val transactions = mutableListOf<AnalyticsTransactionInput>()
        for (index in 0 until size) {
            val type = TransactionType.entries.firstOrNull { it.name == transactionTypes[index] }
                ?: return null
            transactions += AnalyticsTransactionInput(
                type = type,
                amountMinor = amountsMinor[index],
                feeMinor = feesMinor[index],
                categoryId = categoryIds[index],
                feeCategoryId = feeCategoryIds[index],
                localDateEpochDay = localDateEpochDays[index],
                deleted = deleted[index],
            )
        }

        return try {
            val summary = LedgerAnalyticsRules.summarize(transactions, startEpochDay, endEpochDay)
            NativeLedgerAnalyticsSummary(
                incomeMinor = summary.incomeMinor,
                expenseMinor = summary.expenseMinor,
                feesMinor = summary.feesMinor,
                refundsMinor = summary.refundsMinor,
                netMinor = summary.netMinor,
                categorySpendMinor = summary.categorySpendMinor,
            )
        } catch (_: IllegalArgumentException) {
            null
        } catch (_: ArithmeticException) {
            null
        }
    }

    fun canAssignIncomeSource(transactionTypeName: String, hasIncomeSource: Boolean): Boolean =
        IncomeSourceRules.canAssign(transactionTypeName, hasIncomeSource)

    fun incomeSourceKindCount(): Int = IncomeSourceKind.entries.size

    fun incomeSourceKindAt(index: Int): NativeIncomeSourceKindDefinition? =
        IncomeSourceKind.entries.getOrNull(index)?.let { kind ->
            NativeIncomeSourceKindDefinition(name = kind.name, label = kind.label)
        }

    /** Returns a non-sensitive error code, or null when the transaction is valid. */
    fun transactionValidationError(
        typeName: String,
        amountMinor: Long,
        feeMinor: Long,
    ): String? {
        val type = TransactionType.entries.firstOrNull { it.name == typeName }
            ?: return "transaction_type_invalid"

        return try {
            TransactionRules.validateFee(feeMinor)
            TransactionRules.validateAmount(type, amountMinor)
            null
        } catch (_: IllegalArgumentException) {
            if (feeMinor < 0L) "fee_invalid" else "amount_invalid"
        }
    }

    /**
     * Calculates one wallet from the same ledger rules used by Android. Parallel lists must all
     * describe the same transaction sequence. A null result indicates malformed input or overflow.
     */
    fun walletBalanceMinor(
        walletId: String,
        openingBalanceMinor: Long,
        transactionTypes: List<String>,
        amountsMinor: List<Long>,
        feesMinor: List<Long>,
        sourceWalletIds: List<String>,
        destinationWalletIds: List<String?>,
        deleted: List<Boolean>,
    ): String? {
        val size = transactionTypes.size
        if (listOf(
                amountsMinor.size,
                feesMinor.size,
                sourceWalletIds.size,
                destinationWalletIds.size,
                deleted.size,
            ).any { it != size }
        ) return null

        val transactions = mutableListOf<TransactionBalanceInput>()
        for (index in 0 until size) {
            val type = TransactionType.entries.firstOrNull { it.name == transactionTypes[index] }
                ?: return null
            transactions += TransactionBalanceInput(
                type = type,
                amountMinor = amountsMinor[index],
                feeMinor = feesMinor[index],
                walletId = sourceWalletIds[index],
                toWalletId = destinationWalletIds[index],
                deleted = deleted[index],
            )
        }

        return try {
            LedgerBalanceRules.walletBalances(
                wallets = listOf(WalletBalanceInput(walletId, openingBalanceMinor)),
                transactions = transactions,
            )[walletId]?.toString()
        } catch (_: ArithmeticException) {
            null
        }
    }
}

private fun Currency.toNativeDefinition() = NativeCurrencyDefinition(
    code = code,
    symbol = symbol,
    name = name,
    minorUnits = minorUnits,
)
