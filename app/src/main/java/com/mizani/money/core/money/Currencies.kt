package com.mizani.money.core.money

import java.util.Currency as JavaCurrency
import java.util.Locale

/** Runtime currency catalog for Android/JVM, augmented by shared curated metadata. */
object Currencies {
    val UGX = SharedCurrencyCatalog.UGX
    val KES = SharedCurrencyCatalog.KES
    val TZS = SharedCurrencyCatalog.TZS
    val RWF = SharedCurrencyCatalog.RWF
    val NGN = SharedCurrencyCatalog.NGN
    val GHS = SharedCurrencyCatalog.GHS
    val ZAR = SharedCurrencyCatalog.ZAR
    val USD = SharedCurrencyCatalog.USD
    val EUR = SharedCurrencyCatalog.EUR
    val GBP = SharedCurrencyCatalog.GBP

    private val curatedCurrencies = SharedCurrencyCatalog.curated

    /** Currency codes currently assigned to an ISO country or territory. */
    private val currentCurrencyCodes: Set<String> by lazy {
        Locale.getISOCountries().mapNotNullTo(mutableSetOf()) { region ->
            runCatching {
                JavaCurrency.getInstance(Locale.Builder().setRegion(region).build()).currencyCode
            }.getOrNull()
        }
    }

    /**
     * Selectable catalog: every currency currently assigned to an ISO country or territory plus
     * the curated defaults, deduplicated by code (curated metadata wins) and sorted by code.
     * Historical and non-country codes are excluded here but stay resolvable through [byCode].
     */
    private fun currentUnionCurated(): List<Currency> {
        val byCode = (runtimeCurrencies.filter { it.code in currentCurrencyCodes } + curatedCurrencies)
            .associateBy { it.code }
        return byCode.values.sortedBy { it.code }
    }

    /** Every currency usable as a workspace currency. */
    val all: List<Currency> by lazy { currentUnionCurated() }

    /** Current foreign currencies supported for transaction entry and search. */
    val transactionCurrencies: List<Currency> by lazy { currentUnionCurated() }

    /**
     * All currencies known to the runtime are retained so [byCode] can keep formatting older
     * records. Historical and non-country codes are deliberately not offered for new entry.
     */
    private val runtimeCurrencies: List<Currency> by lazy {
        JavaCurrency.getAvailableCurrencies().mapNotNull { javaCurrency ->
            val code = javaCurrency.currencyCode
            val minorUnits = javaCurrency.defaultFractionDigits
            if (code == "XXX" || minorUnits !in 0..6) return@mapNotNull null
            Currency(
                code = code,
                symbol = javaCurrency.getSymbol(Locale.US),
                name = javaCurrency.getDisplayName(Locale.ENGLISH),
                minorUnits = minorUnits,
            )
        }
    }

    private val allCurrenciesByCode: Map<String, Currency> by lazy {
        (curatedCurrencies + runtimeCurrencies).associateBy { it.code }
    }

    fun byCode(code: String): Currency =
        allCurrenciesByCode[code.uppercase(Locale.ROOT)] ?: USD
}
