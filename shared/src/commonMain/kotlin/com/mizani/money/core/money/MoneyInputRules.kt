package com.mizani.money.core.money

/** Deterministic decimal input conversion shared by native clients. */
object MoneyInputRules {
    /**
     * Parses a non-negative decimal amount into integer minor units. Locale grouping and decimal
     * separators, spaces, non-breaking spaces, and the supplied currency symbol are normalized.
     * Extra precision is rounded HALF_UP to match the existing Android entry behavior.
     */
    fun parseMinorUnits(
        input: String,
        currencySymbol: String,
        minorUnits: Int,
        decimalSeparator: String = ".",
        groupingSeparator: String = ",",
    ): Long? {
        if (minorUnits !in 0..6 || decimalSeparator.isEmpty()) return null

        var localizedInput = input
        if (currencySymbol.isNotEmpty()) localizedInput = localizedInput.replace(currencySymbol, "")
        if (groupingSeparator.isNotEmpty() && groupingSeparator != decimalSeparator) {
            localizedInput = localizedInput.replace(groupingSeparator, "")
        }
        if (decimalSeparator != ".") localizedInput = localizedInput.replace(decimalSeparator, ".")
        val cleaned = localizedInput.trim()
            .replace(" ", "")
            .replace("\u00A0", "")
            .replace(",", "")
        if (cleaned.isEmpty() || cleaned == ".") return null

        val separatorIndex = cleaned.indexOf('.')
        if (separatorIndex != cleaned.lastIndexOf('.')) return null
        val wholeText = if (separatorIndex < 0) cleaned else cleaned.substring(0, separatorIndex)
        val fractionText = if (separatorIndex < 0) "" else cleaned.substring(separatorIndex + 1)
        if (wholeText.length > 15 || fractionText.length > 6) return null
        if (wholeText.any { it !in '0'..'9' } || fractionText.any { it !in '0'..'9' }) return null
        if (wholeText.isEmpty() && fractionText.isEmpty()) return null

        val factor = scaleFactor(minorUnits)
        val major = if (wholeText.isEmpty()) 0L else wholeText.toLongOrNull() ?: return null
        if (major > MoneyLimits.MAX_MINOR_AMOUNT / factor) return null
        var amount = major * factor

        val keptFraction = fractionText.take(minorUnits)
        val paddedFraction = keptFraction + "0".repeat(minorUnits - keptFraction.length)
        val fractionalMinor = if (paddedFraction.isEmpty()) 0L else paddedFraction.toLongOrNull() ?: return null
        if (amount > MoneyLimits.MAX_MINOR_AMOUNT - fractionalMinor) return null
        amount += fractionalMinor

        if (fractionText.length > minorUnits && fractionText[minorUnits] >= '5') {
            if (amount == MoneyLimits.MAX_MINOR_AMOUNT) return null
            amount += 1L
        }
        return amount.takeIf { it <= MoneyLimits.MAX_MINOR_AMOUNT }
    }

    private fun scaleFactor(minorUnits: Int): Long {
        var factor = 1L
        repeat(minorUnits) { factor *= 10L }
        return factor
    }
}
