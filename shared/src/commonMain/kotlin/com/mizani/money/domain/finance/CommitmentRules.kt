package com.mizani.money.domain.finance

import com.mizani.money.core.money.Currency
import com.mizani.money.core.money.MoneyLimits

/** Shared validation and exact decimal conversion for one-off commitments. */
object CommitmentRules {
    const val MAX_RATE_LENGTH = 64
    const val MAX_RATE_PRECISION = 36
    private const val INVERSE_SCALE = 48

    fun validationError(
        workspaceCurrency: Currency?,
        commitmentCurrency: Currency?,
        targetMinor: Long,
        targetWorkspaceMinor: Long,
        exchangeRate: String?,
        exchangeRateDate: String?,
        todayEpochDay: Long,
    ): String? {
        if (workspaceCurrency == null || commitmentCurrency == null) return "currency_unsupported"
        if (targetMinor !in 1L..MoneyLimits.MAX_MINOR_AMOUNT) return "target_invalid"
        if (targetWorkspaceMinor !in 1L..MoneyLimits.MAX_MINOR_AMOUNT) return "target_workspace_invalid"

        if (workspaceCurrency.code == commitmentCurrency.code) {
            if (targetWorkspaceMinor != targetMinor) return "same_currency_target_mismatch"
            if (exchangeRate != null || exchangeRateDate != null) return "same_currency_rate_present"
            return null
        }

        if (exchangeRate == null || exchangeRate.length > MAX_RATE_LENGTH) return "rate_missing_or_invalid"
        val rate = Decimal.parse(exchangeRate) ?: return "rate_invalid"
        if (rate.precision > MAX_RATE_PRECISION || !rate.isPositive) return "rate_invalid"
        if (exchangeRateDate == null) return "rate_date_missing"
        val rateDate = parseIsoDateEpochDay(exchangeRateDate) ?: return "rate_date_invalid"
        if (rateDate > todayEpochDay) return "rate_date_future"

        val converted = try {
            convertMinorUnits(
                amountMinor = targetMinor,
                source = commitmentCurrency,
                target = workspaceCurrency,
                exchangeRate = rate,
            )
        } catch (_: ArithmeticException) {
            return "converted_target_invalid"
        }
        return if (converted == targetWorkspaceMinor) null else "converted_target_mismatch"
    }

    fun commitmentToWorkspaceMinor(
        amountMinor: Long,
        commitmentCurrency: Currency,
        workspaceCurrency: Currency,
        exchangeRate: String,
    ): Long = convertMinorUnits(
        amountMinor = amountMinor,
        source = commitmentCurrency,
        target = workspaceCurrency,
        exchangeRate = Decimal.parse(exchangeRate) ?: throw IllegalArgumentException("Exchange rate is invalid"),
    )

    fun workspaceToCommitmentMinor(
        amountMinor: Long,
        workspaceCurrency: Currency,
        commitmentCurrency: Currency,
        exchangeRate: String,
    ): Long {
        require(amountMinor >= 0L) { "Amount cannot be negative" }
        if (workspaceCurrency.code == commitmentCurrency.code) return amountMinor
        val rate = Decimal.parse(exchangeRate) ?: throw IllegalArgumentException("Exchange rate is invalid")
        if (!rate.isPositive) throw IllegalArgumentException("Exchange rate must be positive")

        // Android historically rounds 1/rate to 48 decimal places before converting. Preserve
        // that exact intermediate rounding so old commitment progress values remain identical.
        val inverseScaled = dividePowerOfTenBy(rate.digits, INVERSE_SCALE + rate.scale)
        val product = multiplyUnsigned(amountMinor.toString(), inverseScaled)
        return scaleAndRound(product, commitmentCurrency.minorUnits - workspaceCurrency.minorUnits - INVERSE_SCALE)
    }

    private fun convertMinorUnits(
        amountMinor: Long,
        source: Currency,
        target: Currency,
        exchangeRate: Decimal,
    ): Long {
        require(amountMinor >= 0L) { "Amount cannot be negative" }
        require(exchangeRate.isPositive) { "Exchange rate must be positive" }
        val product = multiplyUnsigned(amountMinor.toString(), exchangeRate.digits)
        return scaleAndRound(product, target.minorUnits - source.minorUnits - exchangeRate.scale)
    }

    /** Represents a non-negative decimal as digits * 10^-scale. */
    private data class Decimal(
        val digits: String,
        val scale: Int,
        val precision: Int,
    ) {
        val isPositive: Boolean get() = digits != "0"

        companion object {
            fun parse(input: String): Decimal? {
                if (input.isEmpty()) return null
                var text = input
                if (text[0] == '+') text = text.drop(1)
                if (text.isEmpty() || text[0] == '-') return null

                var exponent = 0
                val exponentIndex = text.indexOfFirst { it == 'e' || it == 'E' }
                if (exponentIndex >= 0) {
                    if (text.indexOfFirst { it == 'e' || it == 'E' } != exponentIndex) return null
                    val exponentText = text.substring(exponentIndex + 1)
                    exponent = parseSignedInt(exponentText) ?: return null
                    if (exponent !in -4096..4096) return null
                    text = text.substring(0, exponentIndex)
                }
                val dot = text.indexOf('.')
                if (dot >= 0 && text.indexOf('.', dot + 1) >= 0) return null
                val whole = if (dot < 0) text else text.substring(0, dot)
                val fraction = if (dot < 0) "" else text.substring(dot + 1)
                if (whole.isEmpty() && fraction.isEmpty()) return null
                if (whole.any { it !in '0'..'9' } || fraction.any { it !in '0'..'9' }) return null
                val rawDigits = whole + fraction
                val normalized = rawDigits.trimStart('0').ifEmpty { "0" }
                val precision = normalized.length
                val rawScale = fraction.length - exponent
                val scale = rawScale
                return Decimal(normalized, scale, precision)
            }

            private fun parseSignedInt(value: String): Int? {
                if (value.isEmpty()) return null
                var index = 0
                var negative = false
                if (value[0] == '+' || value[0] == '-') {
                    negative = value[0] == '-'
                    index = 1
                }
                if (index == value.length || value.substring(index).any { it !in '0'..'9' }) return null
                var result = 0L
                while (index < value.length) {
                    result = result * 10L + (value[index] - '0')
                    if (result > Int.MAX_VALUE.toLong() + 1L) return null
                    index++
                }
                val signed = if (negative) -result else result
                return signed.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }?.toInt()
            }
        }
    }

    private fun dividePowerOfTenBy(denominatorDigits: String, power: Int): String {
        // 10^power / denominatorDigits, rounded HALF_UP, represented as an integer. A negative
        // power means 1/(denominatorDigits*10^-power), which is still handled without floating point.
        return if (power >= 0) {
            divideRounded("1" + "0".repeat(power), denominatorDigits)
        } else {
            divideRounded("1", denominatorDigits + "0".repeat(-power))
        }
    }

    private fun scaleAndRound(numerator: String, exponent: Int): Long {
        val rounded = if (exponent >= 0) {
            if (numerator == "0") "0" else numerator + "0".repeat(exponent)
        } else {
            val places = -exponent
            if (places >= numerator.length) {
                // The largest possible numerator with this digit length is below 10^places, so it
                // rounds to zero (the half-unit boundary cannot be reached when places > length).
                if (places > numerator.length) "0" else divideRounded(numerator, "1" + "0".repeat(places))
            } else {
                divideRounded(numerator, "1" + "0".repeat(places))
            }
        }
        if (rounded.length > 18 || (rounded.length == 18 && rounded > Long.MAX_VALUE.toString())) {
            throw ArithmeticException("Converted amount overflows Long")
        }
        return rounded.toLong()
    }

    private fun divideRounded(numerator: String, denominator: String): String {
        require(denominator != "0")
        if (numerator == "0") return "0"
        val quotient = StringBuilder()
        var remainder = "0"
        for (digit in numerator) {
            remainder = stripLeadingZeros(if (remainder == "0") digit.toString() else remainder + digit)
            var q = 0
            while (compareUnsigned(remainder, denominator) >= 0) {
                remainder = subtractUnsigned(remainder, denominator)
                q++
            }
            quotient.append(('0'.code + q).toChar())
        }
        var result = stripLeadingZeros(quotient.toString())
        val doubledRemainder = addUnsigned(remainder, remainder)
        if (compareUnsigned(doubledRemainder, denominator) >= 0) result = addUnsigned(result, "1")
        return result
    }

    private fun multiplyUnsigned(left: String, right: String): String {
        if (left == "0" || right == "0") return "0"
        val result = IntArray(left.length + right.length)
        for (i in left.indices.reversed()) {
            for (j in right.indices.reversed()) {
                result[i + j + 1] += (left[i] - '0') * (right[j] - '0')
            }
        }
        for (index in result.lastIndex downTo 1) {
            result[index - 1] += result[index] / 10
            result[index] %= 10
        }
        return result.joinToString("").trimStart('0').ifEmpty { "0" }
    }

    private fun addUnsigned(left: String, right: String): String {
        val result = StringBuilder()
        var i = left.lastIndex
        var j = right.lastIndex
        var carry = 0
        while (i >= 0 || j >= 0 || carry != 0) {
            val sum = (if (i >= 0) left[i--] - '0' else 0) +
                (if (j >= 0) right[j--] - '0' else 0) + carry
            result.append(('0'.code + sum % 10).toChar())
            carry = sum / 10
        }
        return result.reverse().toString()
    }

    private fun subtractUnsigned(left: String, right: String): String {
        var i = left.lastIndex
        var j = right.lastIndex
        var borrow = 0
        val result = StringBuilder()
        while (i >= 0) {
            var value = left[i--] - '0' - borrow
            val subtrahend = if (j >= 0) right[j--] - '0' else 0
            if (value < subtrahend) {
                value += 10
                borrow = 1
            } else borrow = 0
            result.append(('0'.code + value - subtrahend).toChar())
        }
        return result.reverse().toString().trimStart('0').ifEmpty { "0" }
    }

    private fun compareUnsigned(left: String, right: String): Int {
        val a = stripLeadingZeros(left)
        val b = stripLeadingZeros(right)
        return when {
            a.length != b.length -> a.length.compareTo(b.length)
            a == b -> 0
            a > b -> 1
            else -> -1
        }
    }

    private fun stripLeadingZeros(value: String): String = value.trimStart('0').ifEmpty { "0" }

    private fun parseIsoDateEpochDay(value: String): Long? {
        if (value.length != 10 || value[4] != '-' || value[7] != '-' ||
            value.indices.any { index -> index != 4 && index != 7 && value[index] !in '0'..'9' }
        ) return null
        val year = value.substring(0, 4).toIntOrNull() ?: return null
        val month = value.substring(5, 7).toIntOrNull() ?: return null
        val day = value.substring(8, 10).toIntOrNull() ?: return null
        if (month !in 1..12 || day !in 1..daysInMonth(year, month)) return null
        return daysFromCivil(year, month, day)
    }

    private fun daysInMonth(year: Int, month: Int): Int = when (month) {
        2 -> if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) 29 else 28
        4, 6, 9, 11 -> 30
        else -> 31
    }

    // Proleptic Gregorian date to days since 1970-01-01, using only integer arithmetic.
    private fun daysFromCivil(year: Int, month: Int, day: Int): Long {
        var adjustedYear = year.toLong() - if (month <= 2) 1 else 0
        val era = if (adjustedYear >= 0) adjustedYear / 400 else (adjustedYear - 399) / 400
        val yearOfEra = adjustedYear - era * 400
        val monthPart = month.toLong() + if (month > 2) -3 else 9
        val dayOfYear = (153 * monthPart + 2) / 5 + day - 1
        val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }
}
