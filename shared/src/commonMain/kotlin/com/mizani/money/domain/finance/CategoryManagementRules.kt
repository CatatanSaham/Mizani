package com.mizani.money.domain.finance

/** Shared category invariants used by the Android and iOS repository write boundaries. */
object CategoryManagementRules {
    fun canArchiveCategory(activeCategoryCount: Int): Boolean = activeCategoryCount > 1
}
