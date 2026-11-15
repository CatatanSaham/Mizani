package com.mizani.money.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class SharedCountryCatalogTest {
    @Test
    fun `featured countries have unique codes and usable default wallets`() {
        val packs = SharedCountryCatalog.selectablePacks
        val codes = packs.map { it.code }

        assertEquals(codes.size, codes.toSet().size)
        assertTrue(packs.all { it.walletSuggestions.isNotEmpty() })
        assertEquals("UGX", SharedCountryCatalog.byCode("ug").currencyCode)
        assertEquals("USD", SharedCountryCatalog.byCode("unknown").currencyCode)
    }

    @Test
    fun `country defaults remain independently selectable from the workspace currency`() {
        val nigeria = SharedCountryCatalog.byCode("NG")

        assertEquals("NGN", nigeria.currencyCode)
        assertNotEquals(nigeria.currencyCode, SharedCountryCatalog.other.currencyCode)
        assertTrue(nigeria.walletSuggestions.any { it.type == WalletType.MOBILE_MONEY })
    }
}
