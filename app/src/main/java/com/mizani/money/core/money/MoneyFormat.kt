package com.mizani.money.core.money

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Locale

/** Locale-aware display and input parsing for Android/JVM money UI. */
fun Money.format(currency: Currency = Currencies.byCode(currencyCode)): String =
    MoneyFormat.format(minorUnits, currency)

object MoneyFormat {

    /** Formats minor units with the currency symbol and stable grouping (e.g. "USh 1,250,000"). */
    fun format(minorUnits: Long, currency: Currency): String {
        val negative = minorUnits < 0
        // Avoid Long.MIN_VALUE overflow when negating.
        val absolute = if (negative) {
            if (minorUnits == Long.MIN_VALUE) Long.MAX_VALUE else -minorUnits
        } else {
            minorUnits
        }
        val whole = absolute / currency.scaleFactor
        val fraction = (absolute % currency.scaleFactor).toInt()
        val grouping = NumberFormat.getIntegerInstance(Locale.US).apply {
            isGroupingUsed = true
        }.format(whole)
        val fractionPart = if (currency.minorUnits > 0) {
            "." + fraction.toString().padStart(currency.minorUnits, '0')
        } else {
            ""
        }
        val sign = if (negative) "-" else ""
        return "$sign${currency.symbol} $grouping$fractionPart"
    }

    /** Formatting without symbol, used in inputs and compact chart labels. Keeps the minus sign. */
    fun formatBare(minorUnits: Long, currency: Currency): String {
        val sign = if (minorUnits < 0) "-" else ""
        val magnitude = format(
            if (minorUnits == Long.MIN_VALUE) Long.MAX_VALUE else kotlin.math.abs(minorUnits),
            currency,
        )
        return sign + magnitude.removePrefix(currency.symbol).trim()
    }

    /**
     * Parses free-form user input into minor units. Accepts grouping commas, spaces and
     * a single decimal point. Returns null for malformed or out-of-range input.
     */
    fun parse(input: String, currency: Currency): Long? {
        val cleaned = input.trim()
            .replace(" ", "")
            .replace("\u00A0", "")
            .replace(",", "")
            .replace(currency.symbol, "")
        if (cleaned.isEmpty() || cleaned == ".") return null
        if (!Regex("^\\d{0,15}(\\.\\d{0,6})?$").matches(cleaned)) return null
        return try {
            val scaled = BigDecimal(cleaned)
                .movePointRight(currency.minorUnits)
                .setScale(0, RoundingMode.HALF_UP)
            if (scaled > BigDecimal.valueOf(MoneyLimits.MAX_MINOR_AMOUNT)) return null
            scaled.toLong()
        } catch (_: NumberFormatException) {
            null
        }
    }

    /** Converts minor units to a plain editable decimal string. */
    fun toInput(minorUnits: Long, currency: Currency): String {
        if (minorUnits == 0L) return ""
        val negative = minorUnits < 0
        val absolute = if (negative) -minorUnits else minorUnits
        val whole = absolute / currency.scaleFactor
        val fraction = absolute % currency.scaleFactor
        val base = if (currency.minorUnits == 0) {
            whole.toString()
        } else {
            whole.toString() + "." + fraction.toString().padStart(currency.minorUnits, '0')
        }
        return if (negative) "-$base" else base
    }
}
