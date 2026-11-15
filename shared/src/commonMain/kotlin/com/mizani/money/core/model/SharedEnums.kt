package com.mizani.money.core.model

/**
 * Stable finance and preference enums used by both clients.
 *
 * Persisted names are part of Room, DataStore, and backup compatibility. Keep existing entries
 * unchanged; add migrations before removing or renaming an entry.
 */
enum class WalletType(val label: String) {
    CASH("Cash"),
    MOBILE_MONEY("Mobile money"),
    BANK("Bank"),
    CARD("Card"),
    SAVINGS("Savings"),
    DEBT("Debt"),
    OTHER("Other"),
}

/** Broad, user-entered investment categories; this app does not execute trades or give advice. */
enum class InvestmentAssetType(val label: String) {
    STOCKS("Stocks"),
    BONDS("Bonds"),
    FUNDS("Funds"),
    REAL_ESTATE("Real estate"),
    BUSINESS("Business"),
    CASH_EQUIVALENT("Cash equivalent"),
    OTHER("Other"),
}

enum class CategoryType(val label: String) {
    EXPENSE("Expense"),
    INCOME("Income"),
}

enum class TransactionType(val label: String) {
    EXPENSE("Expense"),
    INCOME("Income"),
    TRANSFER("Transfer"),
    REFUND("Refund"),
    ADJUSTMENT("Adjustment"),
}

enum class BudgetPeriodType(val label: String) {
    WEEKLY("Weekly"),
    MONTHLY("Monthly"),
    FOUR_WEEK("Four weeks"),
    CUSTOM("Custom dates"),
}

enum class RolloverRule(val label: String) {
    NONE("Do not roll over"),
    POSITIVE("Roll over leftover only"),
    BOTH("Roll over leftover and overspend"),
}

enum class RecurringType(val label: String) {
    BILL("Bill or commitment"),
    INCOME("Expected income"),
}

enum class Frequency(val label: String) {
    WEEKLY("Every week"),
    BIWEEKLY("Every 2 weeks"),
    MONTHLY("Every month"),
    QUARTERLY("Every 3 months"),
    YEARLY("Every year"),
}

enum class IncomeSourceKind(val label: String) {
    SALARY("Salary"),
    BUSINESS("Business"),
    FREELANCE("Freelance"),
    GIG("Casual / gig work"),
    REMITTANCE("Remittance"),
    FARMING("Farming"),
    OTHER("Other"),
}

enum class ThemeMode(val label: String) {
    SYSTEM("Follow system"),
    LIGHT("Light"),
    DARK("Dark"),
}

enum class ColorTheme(val label: String) {
    MIZANI("Mizani"),
    OCEAN("Ocean"),
    VIOLET("Violet"),
    FOREST("Forest"),
    ROSE("Rose"),
}

enum class DarkThemeStyle(val label: String) {
    SOFT_CHARCOAL("Soft charcoal"),
    WARM_SLATE("Warm slate");

    companion object {
        val DEFAULT = SOFT_CHARCOAL

        /** Old deep-teal and OLED selections resolve to the current neutral dark palette. */
        fun fromStoredValue(value: String?): DarkThemeStyle =
            entries.firstOrNull { it.name == value } ?: DEFAULT
    }
}

enum class InsightKind {
    FEE_TREND,
    INCOME_CONCENTRATION,
    SPENDING_TREND,
    DATA_COMPLETENESS,
}

enum class InsightTone {
    NEUTRAL,
    POSITIVE,
    ATTENTION,
}
