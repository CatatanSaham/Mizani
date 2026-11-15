package com.mizani.money.domain.search

/** Text normalization and matching shared by the native Android and iOS Activity screens. */
object ActivitySearchRules {
    fun normalizeSearchText(text: String): String = text.trim().lowercase()

    fun containsNormalized(searchableText: String, normalizedQuery: String): Boolean =
        normalizedQuery.isEmpty() || searchableText.contains(normalizedQuery)
}
