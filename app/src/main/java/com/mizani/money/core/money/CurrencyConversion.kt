package com.mizani.money.core.money

import com.mizani.money.R
import com.mizani.money.UiStr
import java.math.BigDecimal
import java.math.RoundingMode

/** Decimal conversion rules for Android/JVM exchange-rate responses. */
object CurrencyConversion {
    /** Converts minor units using target major units per source major unit. */
    fun convertMinorUnits(
        amountMinor: Long,
        source: Currency,
        target: Currency,
        rate: BigDecimal,
    ): Long {
        require(amountMinor >= 0L) { UiStr.s(R.string.ui_92590f9e4e) }
        require(rate.signum() > 0) { UiStr.s(R.string.ui_566bda951b) }

        return BigDecimal.valueOf(amountMinor)
            .multiply(rate)
            .multiply(BigDecimal.valueOf(target.scaleFactor))
            .divide(BigDecimal.valueOf(source.scaleFactor), 0, RoundingMode.HALF_UP)
            .longValueExact()
    }
}
