package com.mizani.money

import androidx.room.withTransaction
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mizani.money.core.model.BudgetPeriodType
import com.mizani.money.core.model.CategoryType
import com.mizani.money.core.model.DefaultCategories
import com.mizani.money.core.model.Frequency
import com.mizani.money.core.model.IncomeSourceKind
import com.mizani.money.core.model.InvestmentAssetType
import com.mizani.money.core.model.RecurringType
import com.mizani.money.core.model.RolloverRule
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.model.WalletType
import com.mizani.money.core.money.MoneyLimits
import com.mizani.money.core.time.DateRange
import com.mizani.money.core.time.Periods
import com.mizani.money.data.local.TransactionEntity
import com.mizani.money.data.local.WalletEntity
import com.mizani.money.data.repo.BudgetLineInput
import com.mizani.money.data.repo.CommitmentDraft
import com.mizani.money.data.repo.InvestmentHoldingDraft
import com.mizani.money.data.repo.RecurringDraft
import com.mizani.money.data.repo.TransactionDraft
import com.mizani.money.domain.analytics.AnalyticsEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate

/** Exercises the real encrypted Room/SQLCipher write boundary and DAO mappings end to end. */
@RunWith(AndroidJUnit4::class)
class RepositoryIntegrationTest {

    @Before
    fun reset() {
        TestState.reset()
    }

    @Test
    fun encryptedRepositoryCrudAndAnalyticsInvariants() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val today = LocalDate.now()
        val month = Periods.monthOf(today)

        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0)
        val workspace = repo.currentWorkspace()
        assertNotNull(workspace)
        val cash = repo.snapshot.first().wallets.first()
        val momo = repo.addWallet("MTN MoMo", WalletType.MOBILE_MONEY, 0, "#245B8A")
        val food = DefaultCategories.defaultEntityId("category", "food")
        val housing = DefaultCategories.defaultEntityId("category", "housing")
        val fees = DefaultCategories.defaultEntityId("category", DefaultCategories.FEES_KEY)

        val incomeId = repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.INCOME,
                amountMinor = 100_000,
                walletId = cash.id,
                categoryId = repo.snapshot.first().categories.first { it.type == com.mizani.money.core.model.CategoryType.INCOME }.id,
                date = month.start,
            ),
        )
        val expenseId = repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.EXPENSE,
                amountMinor = 25_000,
                walletId = cash.id,
                categoryId = food,
                date = minOf(month.start.plusDays(1), today),
            ),
        )
        repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.TRANSFER,
                amountMinor = 30_000,
                feeMinor = 1_500,
                walletId = cash.id,
                toWalletId = momo,
                date = today,
            ),
        )
        repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.REFUND,
                amountMinor = 5_000,
                walletId = cash.id,
                categoryId = food,
                linkedTransactionId = expenseId,
                date = today,
            ),
        )
        repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.ADJUSTMENT,
                amountMinor = 2_000,
                walletId = cash.id,
                date = today,
            ),
        )

        val snapshot = repo.snapshot.first()
        assertEquals(5, snapshot.transactions.size)
        val balances = snapshot.walletBalances()
        assertEquals(100_000L - 25_000L - 30_000L - 1_500L + 5_000L + 2_000L, balances[cash.id])
        assertEquals(30_000L, balances[momo])
        assertEquals(80_500L, snapshot.liquidBalance())

        val engine = AnalyticsEngine(snapshot)
        val period = DateRange(month.start, month.end)
        assertEquals(100_000L, engine.incomeMinor(period))
        assertEquals(21_500L, engine.expenseMinor(period)) // 25,000 - 5,000 refund + 1,500 fee
        assertEquals(1_500L, engine.feesMinor(period))
        assertEquals(fees, engine.categorySlices(period).first { it.amountMinor == 1_500L }.categoryId)

        val budgetId = repo.saveBudget(
            budgetId = null,
            name = "Test plan",
            periodType = BudgetPeriodType.MONTHLY,
            start = month.start,
            end = month.end,
            lines = listOf(
                BudgetLineInput(food, 100_000, 80_000, true, RolloverRule.POSITIVE, 1),
                BudgetLineInput(housing, 200_000, 150_000, true, RolloverRule.NONE, 1),
            ),
        )
        val withBudget = repo.snapshot.first()
        assertTrue(withBudget.budgets.any { it.id == budgetId })
        val progress = AnalyticsEngine(withBudget).budgetProgress(period, withBudget.budgets.first { it.id == budgetId }, today)
        assertNotNull(progress)
        assertEquals(20_000L, progress!!.spentMinor) // food 25,000 - 5,000 refund

        val goalId = repo.saveGoal(null, "School fees", 500_000, today.plusMonths(3), null, 1, "Term 2")
        repo.contributeToGoal(goalId, 50_000, cash.id, today)
        val withGoal = repo.snapshot.first()
        assertEquals(50_000L, withGoal.goals.first { it.id == goalId }.allocatedMinor)
        assertEquals(1, withGoal.contributions.count { it.goalId == goalId })

        val ruleId = repo.saveRecurring(
            null,
            RecurringDraft(
                name = "Data",
                type = RecurringType.BILL,
                amountMinor = 10_000,
                categoryId = food,
                walletId = cash.id,
                frequency = Frequency.MONTHLY,
                nextDue = today,
                essential = true,
            ),
        )
        repo.markRecurringPaid(ruleId, today)
        val afterBill = repo.snapshot.first()
        assertTrue(afterBill.transactions.any { it.type == TransactionType.EXPENSE && it.amountMinor == 10_000L })
        assertTrue(afterBill.recurring.first { it.id == ruleId }.nextDueEpochDay > today.toEpochDay())

        val debtId = repo.saveDebt(null, "Phone loan", "Lender", 100_000, 200_000, 20_000, today.plusDays(7), 3.0, "")
        repo.recordDebtPayment(debtId, cash.id, 20_000, today)
        val afterDebt = repo.snapshot.first()
        assertEquals(80_000L, afterDebt.debts.first { it.id == debtId }.currentBalanceMinor)

        repo.deleteTransaction(incomeId)
        assertEquals(6, repo.snapshot.first().transactions.size)
        val tombstone = repo.exportBundle()
        assertTrue(tombstone.transactions.none { it.id == incomeId })

        repo.restoreTransaction(incomeId)
        assertEquals(7, repo.snapshot.first().transactions.size)
    }

    @Test
    fun categoryArchiveKeepsAtLeastOneActiveCategoryPerType() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)

        val initial = repo.snapshot.first()
        val activeExpenseCategories = initial.categories.filter {
            it.type == CategoryType.EXPENSE && !it.archived && it.deletedAt == null
        }
        assertTrue("Test catalog must contain multiple active expense categories", activeExpenseCategories.size > 1)

        val categoriesToArchive = activeExpenseCategories.dropLast(1)
        categoriesToArchive.forEach { category -> repo.setCategoryArchived(category.id, true) }
        assertTrue(
            "Categories selected for archival must be archived",
            repo.snapshot.first().categories.filter { it.id in categoriesToArchive.map { category -> category.id } }
                .all { it.archived },
        )

        val remainingActiveCategory = repo.snapshot.first().categories.single {
            it.type == CategoryType.EXPENSE && !it.archived && it.deletedAt == null
        }
        assertRejected(
            { repo.setCategoryArchived(remainingActiveCategory.id, true) },
            "at least one active category",
        )
        assertTrue(
            "Rejected archival must leave the final active category unchanged",
            repo.snapshot.first().categories.first { it.id == remainingActiveCategory.id }.let {
                !it.archived && it.deletedAt == null
            },
        )
    }

    @Test
    fun incomeSourcesCanOnlyBeLinkedToIncomeTransactions() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val initial = repo.snapshot.first()
        val wallet = initial.wallets.single()
        val expenseCategoryId = initial.categories.first { it.type == CategoryType.EXPENSE }.id
        val sourceId = repo.saveIncomeSource(null, "Weekend work", IncomeSourceKind.GIG)

        assertRejected(
            {
                repo.saveTransaction(
                    TransactionDraft(
                        type = TransactionType.EXPENSE,
                        amountMinor = 100,
                        walletId = wallet.id,
                        categoryId = expenseCategoryId,
                        incomeSourceId = sourceId,
                    ),
                )
            },
            "only be assigned to income",
        )
        assertTrue("Rejected source assignment must not write a transaction", repo.snapshot.first().transactions.isEmpty())
    }

    private fun assertRejected(action: suspend () -> Unit, message: String) = runBlocking {
        try {
            action()
            fail("Expected rejection: $message")
        } catch (e: IllegalArgumentException) {
            assertTrue(
                "Error '${e.message}' should mention '$message'",
                e.message?.contains(message, ignoreCase = true) == true,
            )
        }
    }

    @Test
    fun openingBalancesMustStayWithinSupportedMoneyLimits() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val aboveLimit = MoneyLimits.MAX_MINOR_AMOUNT + 1L
        val belowLimit = -MoneyLimits.MAX_MINOR_AMOUNT - 1L

        assertRejected(
            { repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, aboveLimit) },
            "opening balance",
        )
        assertTrue("Rejected workspace creation must not persist a workspace", repo.currentWorkspace() == null)

        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val cash = repo.snapshot.first().wallets.single()
        assertRejected(
            { repo.addWallet("Out of range", WalletType.SAVINGS, aboveLimit, "#000") },
            "opening balance",
        )
        assertRejected(
            {
                repo.updateWallet(
                    cash.id,
                    cash.name,
                    cash.type,
                    belowLimit,
                    cash.colorHex,
                    cash.icon,
                )
            },
            "opening balance",
        )

        val after = repo.snapshot.first()
        assertEquals(1, after.wallets.size)
        assertEquals(0L, after.wallets.single().openingBalanceMinor)
    }

    @Test
    fun transactionInsertAndEditRejectWalletBalanceOverflowWithoutChangingLedger() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val walletDao = app.container.database.walletDao()

        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val initial = repo.snapshot.first()
        val cash = initial.wallets.single()
        val food = initial.categories.first { it.type == CategoryType.EXPENSE }.id
        val salary = initial.categories.first { it.type == CategoryType.INCOME }.id
        walletDao.upsert(cash.copy(openingBalanceMinor = Long.MAX_VALUE))

        assertRejected(
            {
                repo.saveTransaction(
                    TransactionDraft(
                        type = TransactionType.INCOME,
                        amountMinor = 1L,
                        walletId = cash.id,
                        categoryId = salary,
                    ),
                )
            },
            "wallet balance",
        )
        assertTrue(repo.snapshot.first().transactions.isEmpty())

        val expenseId = repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.EXPENSE,
                amountMinor = 1L,
                walletId = cash.id,
                categoryId = food,
            ),
        )
        assertEquals(Long.MAX_VALUE - 1L, repo.snapshot.first().walletBalances()[cash.id])

        assertRejected(
            {
                repo.saveTransaction(
                    TransactionDraft(
                        id = expenseId,
                        type = TransactionType.INCOME,
                        amountMinor = 1L,
                        walletId = cash.id,
                        categoryId = salary,
                    ),
                )
            },
            "wallet balance",
        )
        val after = repo.snapshot.first()
        assertEquals(TransactionType.EXPENSE, after.transactions.single { it.id == expenseId }.type)
        assertEquals(Long.MAX_VALUE - 1L, after.walletBalances()[cash.id])
    }

    @Test
    fun replacingSameTimeTransactionKeepsStableLedgerBalanceOrder() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val walletDao = app.container.database.walletDao()

        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val initial = repo.snapshot.first()
        val cash = initial.wallets.single()
        val food = initial.categories.first { it.type == CategoryType.EXPENSE }.id
        val salary = initial.categories.first { it.type == CategoryType.INCOME }.id
        walletDao.upsert(cash.copy(openingBalanceMinor = Long.MAX_VALUE))
        val historicalDate = LocalDate.of(2020, 1, 1)

        val expenseId = repo.saveTransaction(
            TransactionDraft(
                id = "a-historical-expense",
                type = TransactionType.EXPENSE,
                amountMinor = 1L,
                walletId = cash.id,
                categoryId = food,
                date = historicalDate,
            ),
        )
        val incomeId = repo.saveTransaction(
            TransactionDraft(
                id = "b-historical-income",
                type = TransactionType.INCOME,
                amountMinor = 1L,
                walletId = cash.id,
                categoryId = salary,
                date = historicalDate,
            ),
        )
        assertEquals(Long.MAX_VALUE, repo.snapshot.first().walletBalances()[cash.id])

        repo.saveTransaction(
            TransactionDraft(
                id = expenseId,
                type = TransactionType.EXPENSE,
                amountMinor = 1L,
                walletId = cash.id,
                categoryId = food,
                note = "Edited without changing date",
                date = historicalDate,
            ),
        )

        val afterEdit = repo.snapshot.first()
        assertEquals(listOf(expenseId, incomeId), afterEdit.transactions.map { it.id })
        assertEquals(Long.MAX_VALUE, afterEdit.walletBalances()[cash.id])
    }

    @Test
    fun repeatedDeletesCanRepairLegacyOverflowButRestoreRemainsGuarded() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val database = app.container.database
        val day = LocalDate.now().toEpochDay()

        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val cash = repo.snapshot.first().wallets.single()
        database.walletDao().upsert(cash.copy(openingBalanceMinor = Long.MAX_VALUE))
        val now = System.currentTimeMillis()
        val transactionIds = listOf("legacy-overflow-one", "legacy-overflow-two")
        transactionIds.forEachIndexed { index, id ->
            database.transactionDao().upsert(
                TransactionEntity(
                    id = id,
                    type = TransactionType.INCOME,
                    amountMinor = 1L,
                    currencyCode = "UGX",
                    walletId = cash.id,
                    localDateEpochDay = day,
                    occurredAt = now + index,
                    createdAt = now,
                    updatedAt = now,
                ),
            )
        }

        repo.deleteTransaction(transactionIds[0])
        // The remaining income still overflows; the second user-requested delete must be allowed.
        repo.deleteTransaction(transactionIds[1])
        assertEquals(Long.MAX_VALUE, repo.snapshot.first().walletBalances()[cash.id])

        assertRejected({ repo.restoreTransaction(transactionIds[0]) }, "wallet balance")
        assertTrue(database.transactionDao().getById(transactionIds[0])?.deletedAt != null)
        assertTrue(database.transactionDao().getById(transactionIds[1])?.deletedAt != null)
    }

    @Test
    fun backupRestoreRejectsOverflowBeforeReplacingExistingLedger() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val initial = repo.snapshot.first()
        val cash = initial.wallets.single()
        val salary = initial.categories.first { it.type == CategoryType.INCOME }.id
        val currentId = repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.INCOME,
                amountMinor = 100L,
                walletId = cash.id,
                categoryId = salary,
            ),
        )
        val before = repo.snapshot.first()
        val backup = repo.exportBundle()
        val template = backup.transactions.single()
        val overflowingTransactions = (0 until 1_025).map { index ->
            template.copy(
                id = "backup-overflow-$index",
                type = TransactionType.INCOME,
                amountMinor = MoneyLimits.MAX_MINOR_AMOUNT,
                feeMinor = 0L,
                walletId = cash.id,
                toWalletId = null,
                categoryId = salary,
                linkedTransactionId = null,
                localDateEpochDay = LocalDate.now().toEpochDay(),
                occurredAt = index.toLong(),
            )
        }

        assertRejected(
            { repo.restoreBundle(backup.copy(transactions = overflowingTransactions)) },
            "wallet balance",
        )

        val after = repo.snapshot.first()
        assertEquals(before.workspace?.id, after.workspace?.id)
        assertEquals(setOf(currentId), after.transactions.map { it.id }.toSet())
        assertEquals(before.walletBalances(), after.walletBalances())
    }

    @Test
    fun activeWalletAggregateOverflowIsRejectedAndLegacyStateCanBeRepaired() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val database = app.container.database
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0L)
        val cash = repo.snapshot.first().wallets.single()
        val walletDao = database.walletDao()
        val transactionDao = database.transactionDao()
        val now = System.currentTimeMillis()

        database.withTransaction {
            walletDao.upsert(cash.copy(openingBalanceMinor = MoneyLimits.MAX_MINOR_AMOUNT))
            repeat(1_023) { index ->
                walletDao.upsert(
                    WalletEntity(
                        id = "aggregate-wallet-$index",
                        name = "Wallet $index",
                        type = WalletType.SAVINGS,
                        openingBalanceMinor = MoneyLimits.MAX_MINOR_AMOUNT,
                        currencyCode = "UGX",
                        colorHex = "#000000",
                        icon = "wallet",
                        sortOrder = index + 1,
                        createdAt = now + index,
                        updatedAt = now + index,
                    ),
                )
            }
            transactionDao.upsert(
                TransactionEntity(
                    id = "legacy-aggregate-overflow",
                    type = TransactionType.INCOME,
                    amountMinor = MoneyLimits.MAX_MINOR_AMOUNT,
                    currencyCode = "UGX",
                    walletId = cash.id,
                    localDateEpochDay = LocalDate.now().toEpochDay(),
                    occurredAt = now,
                    createdAt = now,
                    updatedAt = now,
                ),
            )
        }

        // This delete returns the total to 1,024 legal opening balances after repairing a legacy row.
        repo.deleteTransaction("legacy-aggregate-overflow")
        assertEquals(MoneyLimits.MAX_MINOR_AMOUNT * 1_024L, repo.snapshot.first().liquidBalance())

        assertRejected(
            { repo.addWallet("Overflow", WalletType.SAVINGS, MoneyLimits.MAX_MINOR_AMOUNT, "#000") },
            "wallet balance",
        )
        assertEquals(1_024, repo.snapshot.first().wallets.size)

        val archivedWallet = WalletEntity(
            id = "archived-aggregate-wallet",
            name = "Archived wallet",
            type = WalletType.SAVINGS,
            openingBalanceMinor = MoneyLimits.MAX_MINOR_AMOUNT,
            currencyCode = "UGX",
            colorHex = "#000000",
            icon = "wallet",
            sortOrder = 1_024,
            archived = true,
            createdAt = now,
            updatedAt = now,
        )
        walletDao.upsert(archivedWallet)
        assertRejected({ repo.setWalletArchived(archivedWallet.id, false) }, "wallet balance")
        assertTrue(walletDao.getById(archivedWallet.id)?.archived == true)
    }

    @Test
    fun repositoryWriteBoundaryRejectsInvalidReferences() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository

        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0)
        val snap = repo.snapshot.first()
        val cash = snap.wallets.first()
        val food = DefaultCategories.defaultEntityId("category", "food")
        val salary = snap.categories.first { it.type == CategoryType.INCOME }.id

        // Expense using an income-category must be rejected (wrong category type).
        assertRejected(
            {
                repo.saveTransaction(
                    TransactionDraft(
                        type = TransactionType.EXPENSE,
                        amountMinor = 1_000,
                        walletId = cash.id,
                        categoryId = salary,
                    ),
                )
            },
            "expense",
        )

        // Transfer to an archived destination must be rejected.
        val savings = repo.addWallet("Savings", WalletType.SAVINGS, 0, "#000")
        repo.setWalletArchived(savings, true)
        assertRejected(
            {
                repo.saveTransaction(
                    TransactionDraft(
                        type = TransactionType.TRANSFER,
                        amountMinor = 1_000,
                        walletId = cash.id,
                        toWalletId = savings,
                    ),
                )
            },
            "archived",
        )

        // Recurring bill with an income-category must be rejected.
        assertRejected(
            {
                repo.saveRecurring(
                    null,
                    RecurringDraft(
                        name = "Bad bill",
                        type = RecurringType.BILL,
                        amountMinor = 1_000,
                        categoryId = salary,
                        walletId = cash.id,
                        frequency = Frequency.MONTHLY,
                        nextDue = LocalDate.now(),
                    ),
                )
            },
            "bill",
        )

        // Budget line with an income-category must be rejected.
        val month = Periods.monthOf(LocalDate.now())
        assertRejected(
            {
                repo.saveBudget(
                    budgetId = null,
                    name = "Bad plan",
                    periodType = BudgetPeriodType.MONTHLY,
                    start = month.start,
                    end = month.end,
                    lines = listOf(BudgetLineInput(salary, 10_000, 0, true)),
                )
            },
            "budget line",
        )
    }

    @Test
    fun debtWriteBoundaryRejectsInvalidAmountsAndWallets() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 0)
        val snapshot = repo.snapshot.first()
        val cash = snapshot.wallets.single()
        val debtWallet = repo.addWallet("Debt wallet", WalletType.DEBT, 0, "#8C4A3C")

        assertRejected(
            {
                repo.saveDebt(null, "Invalid", "Lender", 10_000, -1, 0, null, null, "")
            },
            "original",
        )
        assertRejected(
            {
                repo.saveDebt(null, "Invalid", "Lender", 10_000, null, -1, null, null, "")
            },
            "periodic",
        )
        assertRejected(
            {
                repo.saveDebt(null, "Invalid", "Lender", 10_000, null, 0, null, Double.NaN, "")
            },
            "interest",
        )

        val debtId = repo.saveDebt(null, "Phone loan", "Lender", 10_000, 20_000, 2_000, null, null, "")
        assertRejected(
            { repo.recordDebtPayment(debtId, cash.id, 10_001, LocalDate.now()) },
            "exceed",
        )
        assertRejected(
            { repo.recordDebtPayment(debtId, debtWallet, 1_000, LocalDate.now()) },
            "non-debt",
        )
    }

    @Test
    fun importedReferencesStayUniqueAndCommitmentLinksDoNotDuplicateExpenses() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val today = LocalDate.now()
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 10_000)
        val wallet = repo.snapshot.first().wallets.single()
        val category = DefaultCategories.defaultEntityId("category", "education")
        val transactionId = repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.EXPENSE,
                amountMinor = 600,
                walletId = wallet.id,
                categoryId = category,
                date = today,
                sourceProvider = "MTN_MOMO",
                sourceReference = "abc-123",
            ),
        )
        assertTrue(repo.hasImportedReference("mtn_momo", "ABC-123"))

        try {
            repo.saveTransaction(
                TransactionDraft(
                    type = TransactionType.EXPENSE,
                    amountMinor = 600,
                    walletId = wallet.id,
                    categoryId = category,
                    date = today,
                    sourceProvider = "mtn_momo",
                    sourceReference = "ABC-123",
                ),
            )
            fail("A duplicate provider reference must be rejected")
        } catch (_: IllegalArgumentException) {
            // Expected duplicate rejection.
        }

        val commitmentId = repo.saveCommitment(
            id = null,
            draft = CommitmentDraft(
                name = "School fees",
                targetMinor = 1_000,
                dueDate = today.plusDays(10),
                categoryId = category,
                reminderDaysBefore = 7,
            ),
        )
        repo.linkExpenseToCommitment(commitmentId, transactionId)
        val linked = repo.snapshot.first()
        assertEquals(1, linked.transactions.size)
        assertEquals(600L, linked.commitmentProgress().single().paidMinor)
        assertEquals(400L, linked.commitmentProgress().single().remainingMinor)
        repo.saveTransaction(
            TransactionDraft(
                type = TransactionType.REFUND,
                amountMinor = 100,
                walletId = wallet.id,
                categoryId = category,
                linkedTransactionId = transactionId,
                date = today,
            ),
        )
        val refunded = repo.snapshot.first()
        assertEquals(500L, refunded.commitmentProgress().single().paidMinor)
        assertEquals(500L, refunded.commitmentProgress().single().remainingMinor)
        val balanceBeforeUnlink = refunded.walletBalances()[wallet.id]

        repo.unlinkCommitmentPayment(refunded.commitmentPayments.single().id)
        val unlinked = repo.snapshot.first()
        assertEquals(2, unlinked.transactions.size)
        assertEquals(balanceBeforeUnlink, unlinked.walletBalances()[wallet.id])
        assertEquals(0L, unlinked.commitmentProgress().single().paidMinor)

        repo.deleteTransaction(transactionId)
        assertTrue(repo.snapshot.first().commitmentPayments.isEmpty())
        repo.restoreTransaction(transactionId)
        assertTrue(repo.snapshot.first().commitmentPayments.isEmpty())
        assertTrue(repo.hasImportedReference("mtn_momo", "ABC-123"))
    }

    @Test
    fun investmentSnapshotsDoNotCreateLedgerActivityAndArchiveCleanly() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<MizaniApplication>()
        val repo = app.container.financeRepository
        val today = LocalDate.now()
        repo.createWorkspace("UG", "UGX", "Cash", WalletType.CASH, 50_000)
        val before = repo.snapshot.first()
        val walletId = before.wallets.single().id
        val investmentId = repo.saveInvestmentHolding(
            null,
            InvestmentHoldingDraft(
                name = "Balanced fund",
                provider = "Example fund manager",
                assetType = InvestmentAssetType.FUNDS,
                costBasisMinor = 20_000,
                currentValueMinor = 21_500,
                valuationDate = today,
                note = "Manual monthly check",
            ),
        )

        val saved = repo.snapshot.first()
        assertEquals(0, saved.transactions.size)
        assertEquals(50_000L, saved.walletBalances()[walletId])
        assertEquals(1, saved.activeInvestments.size)
        assertEquals(1_500L, saved.investmentSummary().gainLossMinor)
        assertEquals(investmentId, saved.activeInvestments.single().id)

        repo.saveInvestmentHolding(
            investmentId,
            InvestmentHoldingDraft(
                name = "Balanced fund",
                provider = "Example fund manager",
                assetType = InvestmentAssetType.FUNDS,
                costBasisMinor = 20_000,
                currentValueMinor = 19_000,
                valuationDate = today,
            ),
        )
        assertEquals(-1_000L, repo.snapshot.first().investmentSummary().gainLossMinor)

        repo.setInvestmentHoldingArchived(investmentId, true)
        val archived = repo.snapshot.first()
        assertTrue(archived.activeInvestments.isEmpty())
        assertEquals(1, archived.investments.size)
        assertEquals(0, archived.transactions.size)
    }
}
