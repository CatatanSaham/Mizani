package com.mizani.money.domain.finance

import com.mizani.money.core.model.InvestmentAssetType
import com.mizani.money.core.money.MoneyLimits
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class InvestmentRulesTest {
    private val validDraft = InvestmentDraftInput(
        name = "Unit trust",
        provider = "Local provider",
        note = "Long-term savings",
        assetTypeName = "FUNDS",
        costBasisMinor = 100_000L,
        currentValueMinor = 110_000L,
        valuationEpochDay = 10L,
        todayEpochDay = 10L,
    )

    @Test
    fun draftValidationAcceptsTrimmedValuesAndDocumentedBoundaries() {
        assertNull(validate(validDraft.copy(name = "  Unit trust  ", provider = " Provider ")))
        assertNull(
            validate(
                validDraft.copy(
                    name = "n".repeat(InvestmentRules.MAX_NAME_LENGTH),
                    provider = "p".repeat(InvestmentRules.MAX_PROVIDER_LENGTH),
                    note = "x".repeat(InvestmentRules.MAX_NOTE_LENGTH),
                    costBasisMinor = MoneyLimits.MAX_MINOR_AMOUNT,
                    currentValueMinor = MoneyLimits.MAX_MINOR_AMOUNT,
                ),
            ),
        )
        assertNull(validate(validDraft.copy(currentValueMinor = 0L)))
        assertNull(validate(validDraft.copy(valuationEpochDay = 9L)))
    }

    @Test
    fun draftValidationReturnsStableErrorCodes() {
        assertEquals("name_required", validate(validDraft.copy(name = "  \t ")))
        assertEquals("name_too_long", validate(validDraft.copy(name = "n".repeat(81))))
        assertEquals("provider_required", validate(validDraft.copy(provider = " \n ")))
        assertEquals("provider_too_long", validate(validDraft.copy(provider = "p".repeat(81))))
        assertEquals("note_too_long", validate(validDraft.copy(note = "n".repeat(241))))
        assertEquals("asset_type_invalid", validate(validDraft.copy(assetTypeName = "UNKNOWN")))
        assertEquals("cost_basis_invalid", validate(validDraft.copy(costBasisMinor = 0L)))
        assertEquals(
            "cost_basis_invalid",
            validate(validDraft.copy(costBasisMinor = MoneyLimits.MAX_MINOR_AMOUNT + 1L)),
        )
        assertEquals("current_value_invalid", validate(validDraft.copy(currentValueMinor = -1L)))
        assertEquals(
            "current_value_invalid",
            validate(validDraft.copy(currentValueMinor = MoneyLimits.MAX_MINOR_AMOUNT + 1L)),
        )
        assertEquals("valuation_date_invalid", validate(validDraft.copy(valuationEpochDay = 11L)))
    }

    @Test
    fun portfolioSummaryIncludesOnlyActiveHoldings() {
        val summary = InvestmentRules.summarize(
            costBasisMinor = listOf(100L, 200L, 300L, 999L),
            currentValueMinor = listOf(125L, 175L, 400L, 999L),
            // The false entries represent archived or deleted holdings.
            active = listOf(true, true, false, false),
        )

        assertEquals(
            InvestmentPortfolioSummary(
                holdingCount = 2,
                costBasisMinor = 300L,
                currentValueMinor = 300L,
                gainLossMinor = 0L,
            ),
            summary,
        )
    }

    @Test
    fun portfolioSummaryAllowsNoActiveHoldingsAndRejectsMalformedColumns() {
        assertEquals(
            InvestmentPortfolioSummary(0, 0L, 0L, 0L),
            InvestmentRules.summarize(
                costBasisMinor = listOf(100L),
                currentValueMinor = listOf(50L),
                active = listOf(false),
            ),
        )
        assertNull(InvestmentRules.summarize(listOf(100L), emptyList(), listOf(true)))
        assertNull(InvestmentRules.summarize(listOf(100L), listOf(100L), emptyList()))
        assertNull(InvestmentRules.summarize(listOf(0L), listOf(100L), listOf(true)))
        assertNull(InvestmentRules.summarize(listOf(100L), listOf(-1L), listOf(true)))
        // Inactive rows are not part of the summary and may be ignored safely.
        assertTrue(
            InvestmentRules.summarize(listOf(0L), listOf(-1L), listOf(false)) != null,
        )
    }

    @Test
    fun portfolioSummaryReturnsNullWhenCheckedAggregationWouldOverflow() {
        val overflowingCount = 1_025
        assertNull(
            InvestmentRules.summarize(
                costBasisMinor = List(overflowingCount) { MoneyLimits.MAX_MINOR_AMOUNT },
                currentValueMinor = List(overflowingCount) { 0L },
                active = List(overflowingCount) { true },
            ),
        )
    }

    @Test
    fun iosBridgeProjectsAssetTypesValidationAndCheckedSummary() {
        assertEquals(InvestmentAssetType.entries.size, IosFinanceRules.investmentAssetTypeCount())
        assertEquals("STOCKS", IosFinanceRules.investmentAssetTypeAt(0)?.name)
        assertEquals("Stocks", IosFinanceRules.investmentAssetTypeAt(0)?.label)
        assertNull(IosFinanceRules.investmentAssetTypeAt(-1))
        assertNull(IosFinanceRules.investmentAssetTypeAt(IosFinanceRules.investmentAssetTypeCount()))

        assertNull(
            IosFinanceRules.investmentDraftValidationError(
                name = "Fund",
                provider = "Provider",
                note = "",
                assetTypeName = "FUNDS",
                costBasisMinor = 10L,
                currentValueMinor = 12L,
                valuationEpochDay = 5L,
                todayEpochDay = 5L,
            ),
        )
        assertEquals(
            "valuation_date_invalid",
            IosFinanceRules.investmentDraftValidationError(
                name = "Fund",
                provider = "Provider",
                note = "",
                assetTypeName = "FUNDS",
                costBasisMinor = 10L,
                currentValueMinor = 12L,
                valuationEpochDay = 6L,
                todayEpochDay = 5L,
            ),
        )

        val summary = IosFinanceRules.investmentPortfolioSummary(
            costBasisMinor = listOf(10L, 20L),
            currentValueMinor = listOf(15L, 30L),
            active = listOf(true, false),
        )
        assertEquals(1, summary?.holdingCount)
        assertEquals(10L, summary?.costBasisMinor)
        assertEquals(15L, summary?.currentValueMinor)
        assertEquals(5L, summary?.gainLossMinor)
        assertNull(
            IosFinanceRules.investmentPortfolioSummary(
                costBasisMinor = listOf(10L),
                currentValueMinor = emptyList(),
                active = listOf(true),
            ),
        )
    }

    private fun validate(input: InvestmentDraftInput): String? = InvestmentRules.validateDraft(
        name = input.name,
        provider = input.provider,
        note = input.note,
        assetTypeName = input.assetTypeName,
        costBasisMinor = input.costBasisMinor,
        currentValueMinor = input.currentValueMinor,
        valuationEpochDay = input.valuationEpochDay,
        todayEpochDay = input.todayEpochDay,
    )

    private data class InvestmentDraftInput(
        val name: String,
        val provider: String,
        val note: String,
        val assetTypeName: String,
        val costBasisMinor: Long,
        val currentValueMinor: Long,
        val valuationEpochDay: Long,
        val todayEpochDay: Long,
    )
}
