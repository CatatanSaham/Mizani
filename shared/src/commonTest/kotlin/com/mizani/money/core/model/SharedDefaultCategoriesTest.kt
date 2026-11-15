package com.mizani.money.core.model

import kotlin.test.Test
import kotlin.test.assertEquals

class SharedDefaultCategoriesTest {
    @Test
    fun categoryIdsPreserveAndroidNameBasedIds() {
        val expectedIds = mapOf(
            "housing" to "eb92340e-1de5-3315-8bbe-5d16670e982e",
            "food" to "5aa91520-4f12-370b-a472-eb0e9f659131",
            "transport" to "d7243b06-7240-3272-b160-aa1cee17698a",
            "fuel" to "a969d816-6a85-3575-a6b0-9203fd14b704",
            "mobile_data" to "3cbe5322-3fbd-32f7-bf28-dd57175562cf",
            "mobile_money_fees" to "e13bd703-15d1-324a-af6a-c4925065472f",
            "utilities" to "45b950c3-058a-31e1-9132-4c8109b5531a",
            "education" to "e85530b5-8daa-34b0-ab38-c355b9d7492c",
            "health" to "e24e1e71-79d0-33b9-b2d2-6b4c665a2568",
            "family" to "83d50c5f-1a68-377f-a83e-d1b6e8a7bb57",
            "debt" to "56c73ff6-15f4-3ef0-8b2a-dac97cad066e",
            "savings" to "a11933ba-2488-3194-87ef-1b5b1443ee3d",
            "giving" to "dd6635f3-7c3e-3818-8f6d-9e3c885aa453",
            "business" to "63633a73-598a-361f-8361-1fae098ae088",
            "personal_care" to "5ddcf720-cd51-3d33-8285-f0d76558fa7b",
            "entertainment" to "59535532-665c-3f86-80b8-7d15a2b22351",
            "other_expense" to "fad7a7c8-5a75-3376-ae15-2fb41783c0e8",
            "salary" to "a767d365-c1ee-3a1c-92f5-73ae4f500826",
            "business_income" to "6b628185-69bd-3785-bce3-171e2504a457",
            "freelance" to "9405608c-71b6-358c-8a8f-8673cbb85592",
            "gifts" to "b8a74c94-d755-3347-ae7f-4ba3498b0697",
        )

        assertEquals(expectedIds.keys, SharedDefaultCategories.all.map { it.key }.toSet())
        expectedIds.forEach { (key, id) ->
            assertEquals(id, SharedDefaultCategories.categoryId(key), key)
            assertEquals(id, SharedDefaultCategories.defaultEntityId("category", key), key)
        }
        assertEquals(expectedIds.getValue(SharedDefaultCategories.FEES_KEY), SharedDefaultCategories.feesId())
    }

    @Test
    fun definitionsKeepExpenseAndIncomeTypes() {
        assertEquals(17, SharedDefaultCategories.all.count { it.type == CategoryType.EXPENSE })
        assertEquals(4, SharedDefaultCategories.all.count { it.type == CategoryType.INCOME })
    }
}
