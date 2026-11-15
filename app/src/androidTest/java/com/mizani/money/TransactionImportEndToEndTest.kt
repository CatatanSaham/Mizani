package com.mizani.money

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.assertIsEnabled
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.content.Intent
import com.mizani.money.core.legal.LegalDocuments
import com.mizani.money.core.model.CategoryType
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.model.WalletType
import com.mizani.money.core.time.DateRange
import com.mizani.money.data.repo.TransactionDraft
import com.mizani.money.domain.analytics.AnalyticsEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate

/** Drives the real import screen and verifies review-before-save category behavior. */
@RunWith(AndroidJUnit4::class)
class TransactionImportEndToEndTest {

    private companion object {
        const val LARGE_LEDGER_SEED_COUNT = 250
        const val SHARED_MESSAGE = "You have received UGX 10000 from MTN MOMO VIRTUAL CARD on 2026-10-28 13:45:16. fee:500. Reason: Card offload. New balance: UGX 37570. ID: 44604050982."
    }

    @get:Rule
    val compose = createEmptyComposeRule()

    private lateinit var app: MizaniApplication
    private lateinit var scenario: ActivityScenario<MainActivity>

    @Before
    fun setUp() {
        TestState.reset()
        app = ApplicationProvider.getApplicationContext()
        runBlocking {
            app.container.financeRepository.createWorkspace(
                countryCode = "UG",
                currencyCode = "UGX",
                walletName = "MTN MoMo",
                walletType = WalletType.MOBILE_MONEY,
                openingBalanceMinor = 50_000,
            )
            app.container.settingsRepository.completeOnboarding("UG", "UGX")
            app.container.settingsRepository.recordLegalAcceptance(
                LegalDocuments.TERMS_VERSION,
                LegalDocuments.PRIVACY_VERSION,
                System.currentTimeMillis(),
            )
            val walletId = app.container.financeRepository.snapshot.first().wallets.single().id
            repeat(LARGE_LEDGER_SEED_COUNT) { index ->
                app.container.financeRepository.saveTransaction(
                    TransactionDraft(
                        type = TransactionType.EXPENSE,
                        amountMinor = 100L,
                        walletId = walletId,
                        note = "Regression seed",
                        // Keep the load-test rows outside the receipt's October 2026 analytics
                        // period so this test isolates the imported fee totals.
                        date = LocalDate.of(2026, 9, 15).minusDays((index % 10).toLong()),
                    ),
                )
            }
        }
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }

    @After
    fun tearDown() {
        scenario.close()
    }

    @Test
    fun sharedIncomingMessageWithLargeLedgerSavesAndReturnsToHome() {
        compose.waitUntil(timeoutMillis = 20_000) {
            compose.onAllNodesWithText("Record activity").fetchSemanticsNodes().isNotEmpty() &&
                compose.onAllNodesWithText("Regression seed").fetchSemanticsNodes().isNotEmpty()
        }
        val sharedIntent = Intent(app, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, SHARED_MESSAGE)
        }
        // Exercise the common share handler used by both onCreate and onNewIntent without
        // starting a second task that would make ActivityScenario lifecycle cleanup flaky.
        scenario.onActivity { activity -> activity.consumeSharedText(sharedIntent) }
        compose.waitUntil(timeoutMillis = 20_000) {
            compose.onAllNodesWithText("Review imported transaction").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Suggested from MTN MoMo", substring = true).assertExists()
        compose.onNodeWithText("Confirm what this receipt represents", substring = true).assertExists()

        compose.onNodeWithText("Save income").performClick()
        compose.onNodeWithText("Choose an income category so we can classify this received money").assertExists()
        compose.onNodeWithText("Gifts & other income").performScrollTo().performClick()
        compose.onNodeWithText("Choose an income category so we can classify this received money").assertDoesNotExist()
        compose.onNodeWithText("Save income").assertIsEnabled()
        compose.onNodeWithText("Save income").performClick()

        // Saving shows a short success celebration before the import-review destination pops.
        // Wait for the destination to leave the composition so ActivityScenario teardown never
        // races Navigation Compose's back-stack lifecycle transition.
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Review imported transaction").fetchSemanticsNodes().isEmpty()
        }
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Activity").fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithContentDescription("Saved").fetchSemanticsNodes().isEmpty()
        }
        compose.onAllNodesWithText("Home").onFirst().performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Record activity").fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitForIdle()
        val snapshot = runBlocking { app.container.financeRepository.snapshot.first() }
        val transaction = snapshot.transactions.single { it.sourceReference == "44604050982" }
        assertEquals(LARGE_LEDGER_SEED_COUNT + 1, snapshot.transactions.size)
        assertEquals(TransactionType.INCOME, transaction.type)
        assertEquals("mtn_momo", transaction.sourceProvider)
        assertEquals("44604050982", transaction.sourceReference)
        assertEquals(10_000L, transaction.amountMinor)
        assertEquals(500L, transaction.feeMinor)
        assertNotNull(transaction.categoryId)
        assertEquals(CategoryType.INCOME, snapshot.category(transaction.categoryId!!)?.type)
        assertEquals(34_500L, snapshot.walletBalances().values.single())
        val summary = AnalyticsEngine(snapshot).let { engine ->
            val period = DateRange(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 31))
            Triple(engine.incomeMinor(period), engine.expenseMinor(period), engine.netMinor(period))
        }
        assertEquals(10_000L, summary.first)
        assertEquals(500L, summary.second)
        assertEquals(9_500L, summary.third)
    }
}
