package com.mizani.money.domain.finance

import com.mizani.money.core.model.InvestmentAssetType
import com.mizani.money.core.money.MoneyLimits

data class InvestmentPortfolioSummary(
    val holdingCount: Int,
    val costBasisMinor: Long,
    val currentValueMinor: Long,
    val gainLossMinor: Long,
)

/** Shared validation and checked aggregation for manually recorded investment snapshots. */
object InvestmentRules {
    const val MAX_NAME_LENGTH = 80
    const val MAX_PROVIDER_LENGTH = 80
    const val MAX_NOTE_LENGTH = 240

    /** Returns a stable, non-sensitive validation error code, or null when the draft is valid. */
    fun validateDraft(
        name: String,
        provider: String,
        note: String,
        assetTypeName: String,
        costBasisMinor: Long,
        currentValueMinor: Long,
        valuationEpochDay: Long,
        todayEpochDay: Long,
    ): String? {
        val normalizedName = name.trim()
        val normalizedProvider = provider.trim()
        val normalizedNote = note.trim()

        return when {
            normalizedName.isEmpty() -> "name_required"
            normalizedName.length > MAX_NAME_LENGTH -> "name_too_long"
            normalizedProvider.isEmpty() -> "provider_required"
            normalizedProvider.length > MAX_PROVIDER_LENGTH -> "provider_too_long"
            normalizedNote.length > MAX_NOTE_LENGTH -> "note_too_long"
            InvestmentAssetType.entries.none { it.name == assetTypeName } -> "asset_type_invalid"
            costBasisMinor !in 1L..MoneyLimits.MAX_MINOR_AMOUNT -> "cost_basis_invalid"
            currentValueMinor !in 0L..MoneyLimits.MAX_MINOR_AMOUNT -> "current_value_invalid"
            valuationEpochDay > todayEpochDay -> "valuation_date_invalid"
            else -> null
        }
    }

    /** Returns null for mismatched columns, invalid active values, or checked aggregate overflow. */
    fun summarize(
        costBasisMinor: List<Long>,
        currentValueMinor: List<Long>,
        active: List<Boolean>,
    ): InvestmentPortfolioSummary? {
        val size = costBasisMinor.size
        if (currentValueMinor.size != size || active.size != size) return null

        var holdingCount = 0
        var totalCostBasis = 0L
        var totalCurrentValue = 0L
        for (index in 0 until size) {
            if (!active[index]) continue
            val cost = costBasisMinor[index]
            val value = currentValueMinor[index]
            if (cost !in 1L..MoneyLimits.MAX_MINOR_AMOUNT) return null
            if (value !in 0L..MoneyLimits.MAX_MINOR_AMOUNT) return null
            totalCostBasis = addExactOrNull(totalCostBasis, cost) ?: return null
            totalCurrentValue = addExactOrNull(totalCurrentValue, value) ?: return null
            holdingCount++
        }

        val gainLoss = subtractExactOrNull(totalCurrentValue, totalCostBasis) ?: return null
        return InvestmentPortfolioSummary(
            holdingCount = holdingCount,
            costBasisMinor = totalCostBasis,
            currentValueMinor = totalCurrentValue,
            gainLossMinor = gainLoss,
        )
    }

    private fun addExactOrNull(left: Long, right: Long): Long? {
        val result = left + right
        return if (((left xor result) and (right xor result)) < 0L) null else result
    }

    private fun subtractExactOrNull(left: Long, right: Long): Long? {
        val result = left - right
        return if (((left xor right) and (left xor result)) < 0L) null else result
    }
}
