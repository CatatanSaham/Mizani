package com.mizani.money.core.model

import com.mizani.money.BuildConfig
import com.mizani.money.core.money.Currencies
import java.util.Currency as JavaCurrency
import java.util.Locale
import java.util.UUID

data class Insight(
    val id: String,
    val kind: InsightKind,
    val tone: InsightTone,
    val title: String,
    val body: String,
    val explanation: String,
    val actionLabel: String? = null,
)

data class CountryPack(
    val code: String,
    val name: String,
    val currencyCode: String,
    val walletSuggestions: List<WalletSuggestion>,
    val mobileMoneyProviders: List<String>,
)

data class WalletSuggestion(
    val name: String,
    val type: WalletType,
)

object DefaultCategories {
    const val FEES_KEY = SharedDefaultCategories.FEES_KEY

    val all: List<DefaultCategory> = SharedDefaultCategories.all

    fun feesId(): String = SharedDefaultCategories.feesId()

    fun defaultEntityId(entity: String, key: String): String =
        SharedDefaultCategories.defaultEntityId(entity, key)
}

object CountryPacks {
    private fun fromShared(pack: com.mizani.money.core.model.SharedCountryPack) = CountryPack(
        code = pack.code,
        name = pack.name,
        currencyCode = pack.currencyCode,
        walletSuggestions = pack.walletSuggestions.map { WalletSuggestion(it.name, it.type) },
        mobileMoneyProviders = pack.mobileMoneyProviders,
    )

    val uganda = fromShared(SharedCountryCatalog.uganda)
    val kenya = fromShared(SharedCountryCatalog.kenya)
    val tanzania = fromShared(SharedCountryCatalog.tanzania)
    val rwanda = fromShared(SharedCountryCatalog.rwanda)
    val nigeria = fromShared(SharedCountryCatalog.nigeria)
    val ghana = fromShared(SharedCountryCatalog.ghana)
    val southAfrica = fromShared(SharedCountryCatalog.southAfrica)
    val other = fromShared(SharedCountryCatalog.other)

    private val supportedPacks = SharedCountryCatalog.supportedPacks.map(::fromShared)
    private val supportedCodes = supportedPacks.mapTo(mutableSetOf()) { it.code }
    private val genericCountryPacks = Locale.getISOCountries().mapNotNull { code ->
        if (code in supportedCodes) return@mapNotNull null
        val region = Locale.Builder().setRegion(code).build()
        val currencyCode = runCatching { JavaCurrency.getInstance(region).currencyCode }.getOrNull()
            ?.takeIf { candidate -> Currencies.all.any { it.code == candidate } }
            ?: return@mapNotNull null
        CountryPack(
            code = code,
            name = region.getDisplayCountry(Locale.ENGLISH),
            currencyCode = currencyCode,
            walletSuggestions = listOf(
                WalletSuggestion("Cash", WalletType.CASH),
                WalletSuggestion("Mobile money", WalletType.MOBILE_MONEY),
                WalletSuggestion("Bank account", WalletType.BANK),
            ),
            mobileMoneyProviders = emptyList(),
        )
    }

    val all: List<CountryPack> = (supportedPacks + genericCountryPacks)
        .sortedBy { it.name } + other

    fun byCode(code: String): CountryPack = all.firstOrNull { it.code == code } ?: other

    fun forDeviceRegion(regionCode: String): CountryPack =
        all.firstOrNull { it.code.equals(regionCode, ignoreCase = true) } ?: uganda

    fun currencyFor(countryCode: String): String = byCode(countryCode).currencyCode
}

object Ids {
    fun newId(): String = UUID.randomUUID().toString()
}

object AppInfo {
    const val NAME = "Mizani"
    const val TAGLINE = "Your money, in balance."
    val VERSION: String = BuildConfig.VERSION_NAME
}
