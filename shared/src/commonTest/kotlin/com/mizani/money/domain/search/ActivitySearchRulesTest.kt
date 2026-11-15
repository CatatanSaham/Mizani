package com.mizani.money.domain.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ActivitySearchRulesTest {
    @Test
    fun normalizesCaseAndSurroundingWhitespaceConsistently() {
        assertEquals("cafe in kampala", ActivitySearchRules.normalizeSearchText("  Cafe in Kampala  "))
    }

    @Test
    fun matchesNormalizedQueryAndKeepsEmptySearchUnfiltered() {
        val searchableText = ActivitySearchRules.normalizeSearchText("Income at Cash Wallet")

        assertTrue(ActivitySearchRules.containsNormalized(searchableText, "cash wallet"))
        assertTrue(ActivitySearchRules.containsNormalized(searchableText, ""))
        assertFalse(ActivitySearchRules.containsNormalized(searchableText, "savings"))
    }
}
