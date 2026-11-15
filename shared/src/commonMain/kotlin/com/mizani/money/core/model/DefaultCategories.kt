package com.mizani.money.core.model

/** Shared built-in category definition. IDs are pinned to the Android v1 UUID values. */
data class DefaultCategory(
    val key: String,
    val name: String,
    val type: CategoryType,
    val icon: String,
    val colorHex: String,
    val essential: Boolean,
)

/** Single source for built-in category names, types, display metadata, and persisted IDs. */
object SharedDefaultCategories {
    const val FEES_KEY = "mobile_money_fees"

    val all: List<DefaultCategory> = listOf(
        DefaultCategory("housing", "Housing & rent", CategoryType.EXPENSE, "home", "#087F72", true),
        DefaultCategory("food", "Food & groceries", CategoryType.EXPENSE, "food", "#B78331", true),
        DefaultCategory("transport", "Transport", CategoryType.EXPENSE, "transport", "#3F6F76", false),
        DefaultCategory("fuel", "Fuel", CategoryType.EXPENSE, "fuel", "#7A6A4F", false),
        DefaultCategory("mobile_data", "Mobile & data", CategoryType.EXPENSE, "phone", "#4F6FA8", true),
        DefaultCategory(FEES_KEY, "Mobile money fees", CategoryType.EXPENSE, "fees", "#865C19", false),
        DefaultCategory("utilities", "Utilities", CategoryType.EXPENSE, "bolt", "#2F8F80", true),
        DefaultCategory("education", "School & education", CategoryType.EXPENSE, "school", "#7E57A8", true),
        DefaultCategory("health", "Healthcare", CategoryType.EXPENSE, "health", "#B5564F", true),
        DefaultCategory("family", "Family support", CategoryType.EXPENSE, "family", "#A0626E", false),
        DefaultCategory("debt", "Debt payments", CategoryType.EXPENSE, "debt", "#8C4A3C", true),
        DefaultCategory("savings", "Savings", CategoryType.EXPENSE, "savings", "#2F7D58", false),
        DefaultCategory("giving", "Giving & donations", CategoryType.EXPENSE, "giving", "#9A7B2E", false),
        DefaultCategory("business", "Business expenses", CategoryType.EXPENSE, "business", "#45637A", false),
        DefaultCategory("personal_care", "Personal care", CategoryType.EXPENSE, "personal", "#A8698C", false),
        DefaultCategory("entertainment", "Entertainment", CategoryType.EXPENSE, "entertainment", "#6A6FA8", false),
        DefaultCategory("other_expense", "Other", CategoryType.EXPENSE, "other", "#6D6D6D", false),
        DefaultCategory("salary", "Salary", CategoryType.INCOME, "income", "#087F72", true),
        DefaultCategory("business_income", "Business income", CategoryType.INCOME, "business", "#2F8F80", true),
        DefaultCategory("freelance", "Freelance income", CategoryType.INCOME, "freelance", "#3F6F76", true),
        DefaultCategory("gifts", "Gifts & other income", CategoryType.INCOME, "giving", "#B78331", false),
    )

    private val idsByKey = mapOf(
        "housing" to "eb92340e-1de5-3315-8bbe-5d16670e982e",
        "food" to "5aa91520-4f12-370b-a472-eb0e9f659131",
        "transport" to "d7243b06-7240-3272-b160-aa1cee17698a",
        "fuel" to "a969d816-6a85-3575-a6b0-9203fd14b704",
        "mobile_data" to "3cbe5322-3fbd-32f7-bf28-dd57175562cf",
        FEES_KEY to "e13bd703-15d1-324a-af6a-c4925065472f",
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

    fun categoryId(key: String): String =
        idsByKey[key] ?: throw IllegalArgumentException("Unknown built-in category")

    fun defaultEntityId(entity: String, key: String): String {
        require(entity == "category") { "Only category IDs are shared here" }
        return categoryId(key)
    }

    fun feesId(): String = categoryId(FEES_KEY)
}
