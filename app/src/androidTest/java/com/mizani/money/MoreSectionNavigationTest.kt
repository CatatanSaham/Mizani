package com.mizani.money

import android.content.pm.ActivityInfo
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
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
            compose.onNodeWithText("More").fetchSemanticsNode().boundsInRoot.let {
                it.width > it.height
            }
        }

        openMore()

        val walletRow = compose.onNodeWithText("Wallets").fetchSemanticsNode().boundsInRoot
        val exportRow = compose.onNodeWithText("Export or back up data")
            .performScrollTo()
            .fetchSemanticsNode()
            .boundsInRoot
        assertTrue("More sections should occupy separate landscape columns", exportRow.center.x > walletRow.center.x)
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

    private fun openMore() {
        compose.onAllNodesWithText("More").onLast().performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Manage money").fetchSemanticsNodes().isNotEmpty()
        }
    }
}
