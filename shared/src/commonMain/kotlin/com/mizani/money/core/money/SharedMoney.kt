package com.mizani.money.core.money

/**
 * Currency metadata used by shared financial rules. Persisted values always use integer minor
 * units; formatting and runtime currency discovery remain platform-specific.
 */
data class Currency(
    val code: String,
    val symbol: String,
    val name: String,
    val minorUnits: Int,
) {
    init {
        require(minorUnits in 0..6) { "Currency minor units must be between zero and six" }
    }

    val scaleFactor: Long
        get() {
            var factor = 1L
            repeat(minorUnits) { factor *= 10L }
            return factor
        }
}

object MoneyLimits {
    /** Largest supported persisted minor-unit amount across entry, restore and analytics paths. */
    const val MAX_MINOR_AMOUNT = 9_000_000_000_000_000L
}

/**
 * Immutable money value. Arithmetic requires matching currencies and reports overflow instead of
 * silently wrapping. This type deliberately does not format values; each platform supplies locale
 * appropriate presentation.
 */
data class Money(val minorUnits: Long, val currencyCode: String) : Comparable<Money> {

    private fun requireSame(other: Money) {
        require(currencyCode == other.currencyCode) {
            "Currency mismatch: $currencyCode vs ${other.currencyCode}"
        }
    }

    operator fun plus(other: Money): Money {
        requireSame(other)
        return Money(addExact(minorUnits, other.minorUnits), currencyCode)
    }

    operator fun minus(other: Money): Money {
        requireSame(other)
        return Money(subtractExact(minorUnits, other.minorUnits), currencyCode)
    }

    operator fun times(factor: Long): Money = Money(multiplyExact(minorUnits, factor), currencyCode)

    operator fun unaryMinus(): Money = Money(negateExact(minorUnits), currencyCode)

    fun abs(): Money = Money(if (minorUnits < 0L) negateExact(minorUnits) else minorUnits, currencyCode)

    fun isZero(): Boolean = minorUnits == 0L

    fun isNegative(): Boolean = minorUnits < 0L

    fun isPositive(): Boolean = minorUnits > 0L

    override fun compareTo(other: Money): Int {
        requireSame(other)
        return minorUnits.compareTo(other.minorUnits)
    }

    companion object {
        fun zero(currencyCode: String): Money = Money(0L, currencyCode)

        fun ofMinor(minorUnits: Long, currencyCode: String): Money = Money(minorUnits, currencyCode)

        fun ofMajor(major: Long, currency: Currency): Money =
            Money(multiplyExact(major, currency.scaleFactor), currency.code)
    }
}

private fun addExact(left: Long, right: Long): Long {
    val result = left + right
    if (((left xor result) and (right xor result)) < 0L) {
        throw ArithmeticException("Long overflow while adding money")
    }
    return result
}

private fun subtractExact(left: Long, right: Long): Long {
    val result = left - right
    if (((left xor right) and (left xor result)) < 0L) {
        throw ArithmeticException("Long overflow while subtracting money")
    }
    return result
}

private fun multiplyExact(left: Long, right: Long): Long {
    if (left == 0L || right == 0L) return 0L
    if ((left == Long.MIN_VALUE && right == -1L) || (right == Long.MIN_VALUE && left == -1L)) {
        throw ArithmeticException("Long overflow while multiplying money")
    }
    val result = left * right
    if (result / right != left) {
        throw ArithmeticException("Long overflow while multiplying money")
    }
    return result
}

private fun negateExact(value: Long): Long {
    if (value == Long.MIN_VALUE) throw ArithmeticException("Long overflow while negating money")
    return -value
}
