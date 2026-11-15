package com.mizani.money.core.model

/** Country-specific setup defaults shared by the Android and iOS clients. */
data class SharedWalletSuggestion(
    val name: String,
    val type: WalletType,
)

data class SharedCountryPack(
    val code: String,
    val name: String,
    val currencyCode: String,
    val walletSuggestions: List<SharedWalletSuggestion>,
    val mobileMoneyProviders: List<String>,
)

object SharedCountryCatalog {
    val uganda = SharedCountryPack(
        code = "UG",
        name = "Uganda",
        currencyCode = "UGX",
        walletSuggestions = listOf(
            SharedWalletSuggestion("MTN MoMo", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Airtel Money", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
        ),
        mobileMoneyProviders = listOf("MTN MoMo", "Airtel Money"),
    )
    val kenya = SharedCountryPack(
        code = "KE",
        name = "Kenya",
        currencyCode = "KES",
        walletSuggestions = listOf(
            SharedWalletSuggestion("M-Pesa", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Airtel Money", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
        ),
        mobileMoneyProviders = listOf("M-Pesa", "Airtel Money"),
    )
    val tanzania = SharedCountryPack(
        code = "TZ",
        name = "Tanzania",
        currencyCode = "TZS",
        walletSuggestions = listOf(
            SharedWalletSuggestion("M-Pesa", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Tigo Pesa", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Airtel Money", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Cash", WalletType.CASH),
        ),
        mobileMoneyProviders = listOf("M-Pesa", "Tigo Pesa", "Airtel Money"),
    )
    val rwanda = SharedCountryPack(
        code = "RW",
        name = "Rwanda",
        currencyCode = "RWF",
        walletSuggestions = listOf(
            SharedWalletSuggestion("MTN MoMo", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Airtel Money", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
        ),
        mobileMoneyProviders = listOf("MTN MoMo", "Airtel Money"),
    )
    val nigeria = SharedCountryPack(
        code = "NG",
        name = "Nigeria",
        currencyCode = "NGN",
        walletSuggestions = listOf(
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
            SharedWalletSuggestion("OPay", WalletType.MOBILE_MONEY),
        ),
        mobileMoneyProviders = listOf("OPay", "PalmPay", "Moniepoint"),
    )
    val ghana = SharedCountryPack(
        code = "GH",
        name = "Ghana",
        currencyCode = "GHS",
        walletSuggestions = listOf(
            SharedWalletSuggestion("MTN MoMo", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Telecel Cash", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
        ),
        mobileMoneyProviders = listOf("MTN MoMo", "Telecel Cash", "AirtelTigo Money"),
    )
    val southAfrica = SharedCountryPack(
        code = "ZA",
        name = "South Africa",
        currencyCode = "ZAR",
        walletSuggestions = listOf(
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
            SharedWalletSuggestion("Savings", WalletType.SAVINGS),
        ),
        mobileMoneyProviders = listOf("MTN MoMo", "Capitec Pay"),
    )
    val other = SharedCountryPack(
        code = "OT",
        name = "Other / not listed",
        currencyCode = "USD",
        walletSuggestions = listOf(
            SharedWalletSuggestion("Cash", WalletType.CASH),
            SharedWalletSuggestion("Mobile money", WalletType.MOBILE_MONEY),
            SharedWalletSuggestion("Bank account", WalletType.BANK),
        ),
        mobileMoneyProviders = listOf("Mobile money"),
    )

    val supportedPacks: List<SharedCountryPack> = listOf(
        uganda,
        kenya,
        tanzania,
        rwanda,
        nigeria,
        ghana,
        southAfrica,
    )

    val selectablePacks: List<SharedCountryPack> = supportedPacks + other

    fun byCode(code: String): SharedCountryPack =
        selectablePacks.firstOrNull { it.code == code.uppercase() } ?: other

    fun forDeviceRegion(regionCode: String): SharedCountryPack =
        selectablePacks.firstOrNull { it.code.equals(regionCode, ignoreCase = true) } ?: uganda
}
