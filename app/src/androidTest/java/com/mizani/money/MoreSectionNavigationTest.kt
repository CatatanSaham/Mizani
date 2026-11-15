package com.mizani.money

import android.content.pm.ActivityInfo
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PixelMap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mizani.money.core.legal.LegalDocuments
import com.mizani.money.core.model.WalletType
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs
import kotlin.math.roundToInt
import com.mizani.money.ui.guides.FeatureGuides

/** Smoke coverage for every More destination and its wide-screen column geometry. */
@RunWith(AndroidJUnit4::class)
class MoreSectionNavigationTest {

    @get:Rule
    val compose = createEmptyComposeRule()

    private lateinit var scenario: ActivityScenario<MainActivity>

    @Before
    fun setUp() {
        TestState.reset()
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        runBlocking {
            app.container.financeRepository.createWorkspace(
                countryCode = "UG",
                currencyCode = "UGX",
                walletName = "QA wallet",
                walletType = WalletType.CASH,
                openingBalanceMinor = 0,
            )
            app.container.settingsRepository.completeOnboarding("UG", "UGX")
            app.container.settingsRepository.recordLegalAcceptance(
                LegalDocuments.TERMS_VERSION,
                LegalDocuments.PRIVACY_VERSION,
                System.currentTimeMillis(),
            )
        }
        scenario = ActivityScenario.launch(MainActivity::class.java)
        compose.waitUntil(timeoutMillis = 20_000) {
            compose.onAllNodesWithText("More").fetchSemanticsNodes().isNotEmpty()
        }
    }

    @After
    fun tearDown() {
        if (::scenario.isInitialized) {
            scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
            scenario.close()
        }
    }

    @Test
    fun everyMoreDestinationOpensAndReturnsToMoreInLandscape() {
        scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onRoot().fetchSemanticsNode().boundsInRoot.let {
                it.width > it.height
            }
        }

        openMore()

        val walletRow = compose.onNodeWithText("Wallets").fetchSemanticsNode().boundsInRoot
        val exportRow = compose.onNodeWithText("Export or back up data")
            .performScrollTo()
            .fetchSemanticsNode()
            .boundsInRoot
        val rootBounds = compose.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue(
            "More sections should occupy separate landscape columns (root=$rootBounds, wallet=$walletRow, export=$exportRow)",
            exportRow.center.x > walletRow.center.x,
        )
        assertTrue(
            "More section rows should have consistent widths in landscape",
            abs(walletRow.width - exportRow.width) <= 3f,
        )

        listOf(
            "Wallets",
            "Debts",
            "Investments",
            "Categories",
            "Export or back up data",
            "Settings",
            "About and privacy",
            "Guides for every feature",
            "Send feedback",
        ).forEach { destination ->
            compose.onNodeWithText(destination).performScrollTo().performClick()
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodesWithContentDescription("Back").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithContentDescription("Back").performClick()
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodesWithText("Manage money").fetchSemanticsNodes().isNotEmpty()
            }
        }
    }

    @Test
    fun featureHelpButtonsStartTheMatchingGuideOnEachScreen() {
        assertHelpStartsGuide("Help with Home", "home.period")

        openBottomTab("Activity")
        assertHelpStartsGuide("Help with Activity and transactions", "activity.search")

        openBottomTab("Insights")
        assertHelpStartsGuide("Help with Insights", "insights.outlook")

        openBottomTab("Bills")
        assertHelpStartsGuide("Help with Bills and commitments", "commitments.tabs")

        // The import form is reachable from Home's empty-ledger action.
        openBottomTab("Home")
        openMobileMoneyImportScreen()
        assertHelpStartsGuide("Help with Mobile-money import", "import.provider")
        compose.onNodeWithContentDescription("Back").performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Add your first transaction").fetchSemanticsNodes().isNotEmpty()
        }

        assertMoreFeatureHelp("Wallets", "Help with Wallets and balances", "wallets.visibility")
        assertMoreFeatureHelp("Debts", "Help with Debts", "debts.summary")
        assertMoreFeatureHelp("Investments", "Help with Investments", "investments.summary")
        assertMoreFeatureHelp("Categories", "Help with Categories", "categories.types")
    }

    @Test
    fun importSpotlightLeavesItsInstructionsUndimmed() {
        openMobileMoneyImportScreen()

        val normalHeadingBounds = compose.onNodeWithText("Transaction message")
            .fetchSemanticsNode()
            .boundsInRoot
        assertTrue("The import heading must be visible before the guide starts", !normalHeadingBounds.isEmpty)
        val normalProviderBounds = compose.onNodeWithContentDescription(
            "Provider hint (optional): Provider detected automatically",
        ).fetchSemanticsNode().boundsInRoot
        val normalScreen = compose.onRoot().captureToImage().toPixelMap()
        val normalLuminance = averageLuminance(normalScreen, normalHeadingBounds)
        val normalProviderLuminance = averageLuminance(normalScreen, normalProviderBounds)

        compose.onNodeWithContentDescription("Help with Mobile-money import").performClick()
        assertHighlighted("import.provider")
        compose.onNodeWithText("Next").performClick()
        assertHighlighted("import.message")
        compose.waitForIdle()

        // The form already fits the viewport, so its heading should remain at the same position
        // and brightness inside the cutout.
        val guidedScreen = compose.onRoot().captureToImage().toPixelMap()
        val guidedLuminance = averageLuminance(guidedScreen, normalHeadingBounds)
        val guidedProviderLuminance = averageLuminance(guidedScreen, normalProviderBounds)
        assertTrue(
            "The highlighted heading should stay at normal brightness " +
                "(before=$normalLuminance at $normalHeadingBounds, after=$guidedLuminance)",
            normalLuminance > 0.1f && abs(normalLuminance - guidedLuminance) < 0.08f,
        )
        assertTrue(
            "Content outside the active spotlight should be dimmed " +
                "(before=$normalProviderLuminance, after=$guidedProviderLuminance)",
            guidedProviderLuminance < normalProviderLuminance * 0.8f,
        )
    }

    @Test
    fun providerGuideLetsUserSelectANetworkBeforeContinuing() {
        openMobileMoneyImportScreen()
        compose.onNodeWithContentDescription("Help with Mobile-money import").performClick()
        assertHighlighted("import.provider")

        compose.onNodeWithContentDescription(
            "Provider hint (optional): Provider detected automatically",
        ).performClick()
        compose.onNodeWithText("M-Pesa").performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithContentDescription("Provider hint (optional): M-Pesa")
                .fetchSemanticsNodes().isNotEmpty()
        }

        compose.onNodeWithText("Next").performClick()
        assertHighlighted("import.message")
        compose.onNodeWithText("Exit guide").performClick()
        compose.onNodeWithText("Paste the confirmation text")
            .performTextInput("You have received UGX 1,000 from ALICE. ID: MPTST1.")
        compose.onNodeWithText("Review transaction").performScrollTo().performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Review imported transaction").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Suggested from M-Pesa", substring = true).assertExists()
    }

    @Test
    fun allFeatureGuidesHighlightEveryTargetAndSupportReplayExitBackAndFinish() {
        compose.waitUntil(timeoutMillis = 20_000) {
            compose.onAllNodesWithText("Add your first transaction").fetchSemanticsNodes().isNotEmpty()
        }

        // A page-level question mark starts the guide in place. Exit stays on Home when the
        // guide was opened from its own feature screen.
        compose.onNodeWithContentDescription("Help with Home").performClick()
        assertHighlighted("home.period")
        compose.onNodeWithText("Exit guide").performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Add your first transaction").fetchSemanticsNodes().isNotEmpty()
        }

        openMore()
        compose.onNodeWithText("Guides for every feature").performScrollTo().performClick()
        waitForGuideCatalogue()

        val homeGuide = FeatureGuides.byId("home")!!
        startGuide(homeGuide.title)
        assertHighlighted(homeGuide.steps[0].targetId)
        compose.onNodeWithText("Next").performClick()
        assertHighlighted(homeGuide.steps[1].targetId)
        compose.onNodeWithText("Back").performClick()
        assertHighlighted(homeGuide.steps[0].targetId)
        compose.onNodeWithText("Next").performClick()
        assertHighlighted(homeGuide.steps[1].targetId)
        compose.onNodeWithText("Next").performClick()
        assertHighlighted(homeGuide.steps[2].targetId)
        compose.onNodeWithText("Exit guide").performClick()
        waitForGuideCatalogue()

        // The same guide can be started again, and Android Back closes the overlay to the catalogue.
        startGuide(homeGuide.title)
        assertHighlighted(homeGuide.steps[0].targetId)
        scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        waitForGuideCatalogue()

        // Replay once more and finish all steps; then run the complete catalogue through the same
        // public entry point users use from Home and More.
        FeatureGuides.all.forEach { guide ->
            startGuide(guide.title)
            guide.steps.forEachIndexed { index, step ->
                assertHighlighted(step.targetId)
                if (step.targetId == "import.message") {
                    compose.onNodeWithText("Transaction message").fetchSemanticsNode()
                    compose.onNodeWithText(
                        "Paste the confirmation exactly as shown, including the amount and reference. You can review it before saving.",
                    ).fetchSemanticsNode()
                }
                if (index < guide.steps.lastIndex) {
                    compose.onNodeWithText("Next").performClick()
                } else {
                    compose.onNodeWithText("Finish").performClick()
                }
            }
            waitForGuideCatalogue()
        }
    }

    private fun startGuide(title: String) {
        compose.onNodeWithContentDescription("Start guide: $title")
            .performScrollTo()
            .performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Step 1 of", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun openMobileMoneyImportScreen() {
        compose.waitUntil(timeoutMillis = 20_000) {
            compose.onAllNodesWithText("Add your first transaction").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Import MoMo message").performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithContentDescription("Help with Mobile-money import")
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun assertHelpStartsGuide(helpDescription: String, targetId: String) {
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithContentDescription(helpDescription).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription(helpDescription).performClick()
        assertHighlighted(targetId)
        compose.onNodeWithText("Exit guide").performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithContentDescription(helpDescription).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun assertMoreFeatureHelp(
        destination: String,
        helpDescription: String,
        targetId: String,
    ) {
        if (compose.onAllNodesWithText("Manage money").fetchSemanticsNodes().isEmpty()) {
            openMore()
        }
        compose.onNodeWithText(destination).performScrollTo().performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithContentDescription(helpDescription).fetchSemanticsNodes().isNotEmpty()
        }
        assertHelpStartsGuide(helpDescription, targetId)
        compose.onNodeWithContentDescription("Back").performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Manage money").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun openBottomTab(label: String) {
        compose.onAllNodesWithText(label).onLast().performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText(label).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun assertHighlighted(targetId: String) {
        val description = "Guide target highlighted: $targetId"
        try {
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodesWithContentDescription(description).fetchSemanticsNodes().isNotEmpty()
            }
        } catch (timeout: Throwable) {
            val diagnostics = compose.onAllNodesWithContentDescription(
                "Preparing guide highlight: $targetId",
                substring = true,
            ).fetchSemanticsNodes().map { it.config.toString() }
            throw AssertionError(
                "Guide target '$targetId' did not produce a visible spotlight. $diagnostics",
                timeout,
            )
        }
        assertTrue(
            "Guide target '$targetId' did not produce a visible cutout",
            compose.onAllNodesWithContentDescription(description).fetchSemanticsNodes().isNotEmpty(),
        )
        // A step is only useful if the page it points at is still laid out. This fails when a guide
        // step collapses the destination - for example by taking the width of a weighted Row.
        val targetNodes = compose
            .onAllNodesWithTag("guide-target-$targetId", useUnmergedTree = true)
            .fetchSemanticsNodes()
        assertTrue(
            "Guide target '$targetId' is not laid out; the page behind the tour collapsed.",
            targetNodes.any { it.boundsInRoot.width > 0f && it.boundsInRoot.height > 0f },
        )
    }

    private fun waitForGuideCatalogue() {
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Guides for every feature").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun averageLuminance(pixels: PixelMap, bounds: androidx.compose.ui.geometry.Rect): Float {
        val left = bounds.left.roundToInt().coerceIn(0, pixels.width - 1)
        val top = bounds.top.roundToInt().coerceIn(0, pixels.height - 1)
        val right = bounds.right.roundToInt().coerceIn(left + 1, pixels.width)
        val bottom = bounds.bottom.roundToInt().coerceIn(top + 1, pixels.height)
        var total = 0f
        var count = 0
        for (y in top until bottom) {
            for (x in left until right) {
                val color: Color = pixels[x, y]
                total += (color.red + color.green + color.blue) / 3f
                count++
            }
        }
        return if (count == 0) 0f else total / count
    }

    private fun openMore() {
        compose.onAllNodesWithText("More").onLast().performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Manage money").fetchSemanticsNodes().isNotEmpty()
        }
    }
}
