package com.mizani.money.data.repo

import com.mizani.money.core.model.Frequency
import com.mizani.money.core.model.Ids
import com.mizani.money.core.model.InvestmentAssetType
import com.mizani.money.core.model.RecurringType
import com.mizani.money.core.model.RolloverRule
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.model.WalletType
import com.mizani.money.domain.finance.LedgerBalanceRules
import com.mizani.money.domain.finance.InvestmentRules
import com.mizani.money.domain.finance.TransactionBalanceInput
import com.mizani.money.domain.finance.WalletBalanceBreakdown
import com.mizani.money.domain.finance.WalletBalanceInput
import com.mizani.money.data.local.BudgetEntity
import com.mizani.money.data.local.BudgetLineEntity
import com.mizani.money.data.local.CategoryEntity
import com.mizani.money.data.local.CommitmentEntity
import com.mizani.money.data.local.CommitmentPaymentEntity
import com.mizani.money.data.local.DebtEntity
import com.mizani.money.data.local.GoalContributionEntity
import com.mizani.money.data.local.GoalEntity
import com.mizani.money.data.local.IncomeSourceEntity
import com.mizani.money.data.local.InvestmentHoldingEntity
import com.mizani.money.data.local.RecurringRuleEntity
import com.mizani.money.data.local.TransactionEntity
import com.mizani.money.data.local.WalletEntity
import com.mizani.money.data.local.WorkspaceEntity
import java.time.LocalDate

data class LedgerSnapshot(
    val workspace: WorkspaceEntity? = null,
    val wallets: List<WalletEntity> = emptyList(),
    val investments: List<InvestmentHoldingEntity> = emptyList(),
    val categories: List<CategoryEntity> = emptyList(),
    val incomeSources: List<IncomeSourceEntity> = emptyList(),
    val transactions: List<TransactionEntity> = emptyList(),
    val budgets: List<BudgetEntity> = emptyList(),
    val budgetLines: List<BudgetLineEntity> = emptyList(),
    val goals: List<GoalEntity> = emptyList(),
    val contributions: List<GoalContributionEntity> = emptyList(),
    val recurring: List<RecurringRuleEntity> = emptyList(),
    val debts: List<DebtEntity> = emptyList(),
    val commitments: List<CommitmentEntity> = emptyList(),
    val commitmentPayments: List<CommitmentPaymentEntity> = emptyList(),
) {
    val currencyCode: String get() = workspace?.currencyCode ?: "UGX"

    val activeWallets: List<WalletEntity>
        get() = wallets.filter { !it.archived && it.deletedAt == null }

    val activeInvestments: List<InvestmentHoldingEntity>
        get() = investments.filter { !it.archived && it.deletedAt == null }

    fun investmentSummary(): InvestmentSummary {
        val summary = InvestmentRules.summarize(
            costBasisMinor = investments.map { it.costBasisMinor },
            currentValueMinor = investments.map { it.currentValueMinor },
            active = investments.map { !it.archived && it.deletedAt == null },
        ) ?: throw ArithmeticException("Invalid or overflowing investment summary")
        return InvestmentSummary(
            holdingCount = summary.holdingCount,
            costBasisMinor = summary.costBasisMinor,
            currentValueMinor = summary.currentValueMinor,
        )
    }

    val activeCategories: List<CategoryEntity>
        get() = categories.filter { !it.archived && it.deletedAt == null }

    fun wallet(id: String?): WalletEntity? = id?.let { key -> wallets.firstOrNull { it.id == key } }

    fun category(id: String?): CategoryEntity? = id?.let { key -> categories.firstOrNull { it.id == key } }

    fun incomeSource(id: String?): IncomeSourceEntity? =
        id?.let { key -> incomeSources.firstOrNull { it.id == key } }

    fun walletName(id: String?): String = wallet(id)?.name ?: "Wallet"

    fun categoryName(id: String?): String = category(id)?.name ?: "Uncategorised"

    fun incomeSourceName(id: String?): String = incomeSource(id)?.name ?: "Income"

    /**
     * Returns the spendable value of each active expense after recorded refunds.
     *
     * Commitment links use the same net value: a refunded expense must not be offered as a
     * payment, and a partially refunded expense can only contribute its remaining amount. Keeping
     * this calculation on the canonical snapshot prevents screens from accidentally treating a
     * refunded ledger row as a full payment.
     */
    fun netExpenseMinorById(): Map<String, Long> {
        val refundsByExpenseId = transactions.asSequence()
            .filter { it.type == TransactionType.REFUND && it.linkedTransactionId != null }
            .groupingBy { it.linkedTransactionId!! }
            .fold(0L) { total, refund -> Math.addExact(total, refund.amountMinor) }
        return transactions.asSequence()
            .filter { it.type == TransactionType.EXPENSE }
            .associate { expense ->
                expense.id to (expense.amountMinor - (refundsByExpenseId[expense.id] ?: 0L))
                    .coerceAtLeast(0L)
            }
    }

    fun budgetLinesFor(budgetId: String?): List<BudgetLineEntity> =
        budgetId?.let { id -> budgetLines.filter { it.budgetId == id } } ?: emptyList()

    /** Balances derived from a single canonical ledger; transfers preserve total net worth. */
    fun walletBalances(): Map<String, Long> = LedgerBalanceRules.walletBalances(
        wallets = wallets.map { WalletBalanceInput(it.id, it.openingBalanceMinor) },
        transactions = transactions.map {
            TransactionBalanceInput(
                type = it.type,
                amountMinor = it.amountMinor,
                feeMinor = it.feeMinor,
                walletId = it.walletId,
                toWalletId = it.toWalletId,
                deleted = it.deletedAt != null,
            )
        },
    )

    /** Best-effort signed breakdown for explaining a wallet total without changing its calculation. */
    fun walletBalanceBreakdownsOrNull(): Map<String, WalletBalanceBreakdown>? = try {
        LedgerBalanceRules.walletBalanceBreakdowns(
            wallets = wallets.map { WalletBalanceInput(it.id, it.openingBalanceMinor) },
            transactions = transactions.map {
                TransactionBalanceInput(
                    type = it.type,
                    amountMinor = it.amountMinor,
                    feeMinor = it.feeMinor,
                    walletId = it.walletId,
                    toWalletId = it.toWalletId,
                    deleted = it.deletedAt != null,
                )
            },
        )
    } catch (_: ArithmeticException) {
        null
    }

    /**
     * Returns balances only when every wallet and active aggregate can be represented exactly.
     * A null result keeps older invalid ledgers readable so Activity can offer a repair path.
     */
    fun walletBalancesOrNull(): Map<String, Long>? = try {
        val balances = walletBalances()
        var allActiveTotal = 0L
        var activeLiquidTotal = 0L
        wallets.asSequence()
            .filter { !it.archived && it.deletedAt == null }
            .sortedWith(compareBy<WalletEntity> { it.sortOrder }.thenBy { it.createdAt }.thenBy { it.id })
            .forEach { wallet ->
                val balance = balances[wallet.id] ?: 0L
                allActiveTotal = Math.addExact(allActiveTotal, balance)
                if (wallet.type != WalletType.DEBT) {
                    activeLiquidTotal = Math.addExact(activeLiquidTotal, balance)
                }
            }
        balances
    } catch (_: ArithmeticException) {
        null
    }

    fun liquidBalance(): Long {
        val balances = walletBalances()
        return wallets
            .filter { it.type != WalletType.DEBT && !it.archived && it.deletedAt == null }
            .fold(0L) { total, wallet -> Math.addExact(total, balances[wallet.id] ?: 0L) }
    }

    /** Paid totals are derived from linked, active expense transactions; links never duplicate ledger rows. */
    fun commitmentProgress(): List<CommitmentProgress> {
        val transactionsById = transactions.associateBy { it.id }
        val refundsByExpenseId = transactions.asSequence()
            .filter { it.type == TransactionType.REFUND && it.linkedTransactionId != null }
            .groupingBy { it.linkedTransactionId!! }
            .fold(0L) { total, refund -> Math.addExact(total, refund.amountMinor) }
        val paymentsByCommitment = commitmentPayments.asSequence()
            .groupBy { it.commitmentId }

        return commitments.asSequence()
            .filter { it.deletedAt == null }
            .map { commitment ->
                val paidWorkspace = paymentsByCommitment[commitment.id].orEmpty().fold(0L) { total, payment ->
                    val transaction = transactionsById[payment.transactionId]
                    if (transaction == null || transaction.type != TransactionType.EXPENSE) {
                        total
                    } else {
                        val netPayment = (transaction.amountMinor - (refundsByExpenseId[transaction.id] ?: 0L))
                            .coerceAtLeast(0L)
                        Math.addExact(total, netPayment)
                    }
                }
                val targetWorkspace = commitment.targetWorkspaceMinor.coerceAtLeast(1L)
                val remainingWorkspace = (targetWorkspace - paidWorkspace).coerceAtLeast(0L)
                val rate = commitment.exchangeRate?.toBigDecimalOrNull()
                val paid = CommitmentCurrencyRules.workspaceToCommitmentMinor(
                    amountMinor = paidWorkspace,
                    workspaceCurrencyCode = currencyCode,
                    commitmentCurrencyCode = commitment.currencyCode,
                    exchangeRate = rate,
                ).coerceAtMost(commitment.targetMinor)
                // Convert the remaining base-currency amount directly so a fully paid
                // commitment always displays zero in its target currency, even when
                // inverse-rate rounding would otherwise leave a stray minor unit.
                val remaining = CommitmentCurrencyRules.workspaceToCommitmentMinor(
                    amountMinor = remainingWorkspace,
                    workspaceCurrencyCode = currencyCode,
                    commitmentCurrencyCode = commitment.currencyCode,
                    exchangeRate = rate,
                )
                CommitmentProgress(
                    commitment = commitment,
                    paidMinor = paid,
                    remainingMinor = remaining,
                    paidWorkspaceMinor = paidWorkspace,
                    remainingWorkspaceMinor = remainingWorkspace,
                )
            }
            .toList()
    }

    private fun <T> List<T>.sumExact(selector: (T) -> Long): Long =
        fold(0L) { total, item -> Math.addExact(total, selector(item)) }
}

data class InvestmentSummary(
    val holdingCount: Int,
    val costBasisMinor: Long,
    val currentValueMinor: Long,
) {
    val gainLossMinor: Long
        get() = Math.subtractExact(currentValueMinor, costBasisMinor)
}

data class TransactionDraft(
    val id: String = Ids.newId(),
    val type: TransactionType,
    val amountMinor: Long,
    val feeMinor: Long = 0L,
    val walletId: String,
    val toWalletId: String? = null,
    val categoryId: String? = null,
    val feeCategoryId: String? = null,
    val incomeSourceId: String? = null,
    val linkedTransactionId: String? = null,
    val note: String = "",
    val payee: String = "",
    val date: LocalDate = LocalDate.now(),
    val sourceAmountMinor: Long? = null,
    val sourceFeeMinor: Long? = null,
    val sourceCurrencyCode: String? = null,
    val exchangeRate: String? = null,
    val exchangeRateDate: String? = null,
    val sourceProvider: String? = null,
    val sourceReference: String? = null,
)

data class CommitmentDraft(
    val name: String,
    val targetMinor: Long,
    val dueDate: LocalDate,
    val categoryId: String? = null,
    val reminderDaysBefore: Int = 0,
    /** Null keeps existing callers and old saved commitments in the workspace currency. */
    val currencyCode: String? = null,
    val targetWorkspaceMinor: Long? = null,
    val exchangeRate: String? = null,
    val exchangeRateDate: LocalDate? = null,
)

data class InvestmentHoldingDraft(
    val name: String,
    val provider: String,
    val assetType: InvestmentAssetType,
    val costBasisMinor: Long,
    val currentValueMinor: Long,
    val valuationDate: LocalDate,
    val note: String = "",
)

data class CommitmentProgress(
    val commitment: CommitmentEntity,
    val paidMinor: Long,
    val remainingMinor: Long,
    /** Workspace-currency values used for balances, Outlook and link validation. */
    val paidWorkspaceMinor: Long = paidMinor,
    val remainingWorkspaceMinor: Long = remainingMinor,
)

data class BudgetLineInput(
    val categoryId: String,
    val plannedMinor: Long,
    val fundedMinor: Long = 0L,
    val essential: Boolean,
    val rolloverRule: RolloverRule = RolloverRule.NONE,
    val priority: Int = 2,
    val note: String = "",
)

data class RecurringDraft(
    val name: String,
    val type: RecurringType,
    val amountMinor: Long,
    val categoryId: String?,
    val walletId: String?,
    val frequency: Frequency,
    val nextDue: LocalDate,
    val essential: Boolean = true,
    val note: String = "",
)

data class RestoreBundle(
    val workspace: WorkspaceEntity,
    val wallets: List<WalletEntity>,
    val investments: List<InvestmentHoldingEntity> = emptyList(),
    val categories: List<CategoryEntity>,
    val incomeSources: List<IncomeSourceEntity>,
    val transactions: List<TransactionEntity>,
    val budgets: List<BudgetEntity>,
    val budgetLines: List<BudgetLineEntity>,
    val goals: List<GoalEntity>,
    val contributions: List<GoalContributionEntity>,
    val recurring: List<RecurringRuleEntity>,
    val debts: List<DebtEntity>,
    val commitments: List<CommitmentEntity> = emptyList(),
    val commitmentPayments: List<CommitmentPaymentEntity> = emptyList(),
)

internal data class CorePart(
    val workspace: WorkspaceEntity?,
    val wallets: List<WalletEntity>,
    val investments: List<InvestmentHoldingEntity>,
    val categories: List<CategoryEntity>,
    val incomeSources: List<IncomeSourceEntity>,
    val transactions: List<TransactionEntity>,
)

internal data class PlanPart(
    val budgets: List<BudgetEntity>,
    val lines: List<BudgetLineEntity>,
    val goals: List<GoalEntity>,
    val contributions: List<GoalContributionEntity>,
)

internal data class OtherPart(
    val recurring: List<RecurringRuleEntity>,
    val debts: List<DebtEntity>,
    val commitments: List<CommitmentEntity>,
    val commitmentPayments: List<CommitmentPaymentEntity>,
)
