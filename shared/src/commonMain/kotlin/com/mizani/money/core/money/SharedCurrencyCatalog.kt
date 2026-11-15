package com.mizani.money.core.money

/** Curated currency metadata available identically to Android and iOS. */
object SharedCurrencyCatalog {
    val UGX = Currency("UGX", "USh", "Ugandan Shilling", 0)
    val KES = Currency("KES", "KSh", "Kenyan Shilling", 0)
    val TZS = Currency("TZS", "TSh", "Tanzanian Shilling", 0)
    val RWF = Currency("RWF", "FRw", "Rwandan Franc", 0)
    val NGN = Currency("NGN", "₦", "Nigerian Naira", 2)
    val GHS = Currency("GHS", "GH₵", "Ghanaian Cedi", 2)
    val ZAR = Currency("ZAR", "R", "South African Rand", 2)
    val USD = Currency("USD", "$", "US Dollar", 2)
    val EUR = Currency("EUR", "€", "Euro", 2)
    val GBP = Currency("GBP", "£", "British Pound", 2)

    val curated: List<Currency> = listOf(UGX, KES, TZS, RWF, NGN, GHS, ZAR, USD, EUR, GBP)

    fun byCode(code: String): Currency? = curated.firstOrNull { it.code == code.uppercase() }
}
