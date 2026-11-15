package com.mizani.money.domain.finance

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CategoryManagementRulesTest {
    @Test
    fun keepsAtLeastOneActiveCategoryOfEachType() {
        assertFalse(CategoryManagementRules.canArchiveCategory(0))
        assertFalse(CategoryManagementRules.canArchiveCategory(1))
        assertTrue(CategoryManagementRules.canArchiveCategory(2))
    }
}
