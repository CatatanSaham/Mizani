package com.mizani.money.feature.commitments

import com.mizani.money.UiStr
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.Payments
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.mizani.money.R
import com.mizani.money.core.model.CategoryType
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.money.CurrencyConversion
import com.mizani.money.core.money.Currencies
import com.mizani.money.core.money.MoneyFormat
import com.mizani.money.core.time.DateText
import com.mizani.money.data.local.CommitmentEntity
import com.mizani.money.data.local.RecurringRuleEntity
import com.mizani.money.data.repo.CommitmentDraft
import com.mizani.money.data.repo.CommitmentProgress
import com.mizani.money.data.repo.ExchangeRate
import com.mizani.money.data.repo.ExchangeRateUnavailableException
import com.mizani.money.data.repo.RecurringDraft
import com.mizani.money.ui.AppUiState
import com.mizani.money.ui.AppViewModel
import com.mizani.money.ui.components.DateField
import com.mizani.money.ui.components.MizaniCard
import com.mizani.money.ui.components.MizaniAlertDialog
import com.mizani.money.ui.components.MizaniConfirmDialog
import com.mizani.money.ui.components.MizaniCurrencyPicker
import com.mizani.money.ui.components.MizaniInfoButton
import com.mizani.money.ui.components.MizaniPicker
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.PickerOption
import com.mizani.money.ui.components.ProgressBar
import com.mizani.money.ui.components.SectionHeader
import com.mizani.money.ui.components.Spacing
import com.mizani.money.ui.guides.guideTarget
import com.mizani.money.ui.guides.LocalActiveGuideTarget
import com.mizani.money.ui.guides.GuideHelpAction
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import java.time.LocalDate

@Composable
fun CommitmentsScreen(
    vm: AppViewModel,
    state: AppUiState,
    onRecordExpense: () -> Unit,
    onOpenGuide: () -> Unit,
) {
    val snapshot = state.snapshot
    val currency = state.currency
    val today by vm.today.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var selectedSection by rememberSaveable { mutableIntStateOf(0) }
    // The guided tour walks through both tabs, so the active step selects the matching section
    // before its spotlight is measured. Without this the guide would only ever explain the tab
    // the user happened to leave open.
    val activeGuideTarget = LocalActiveGuideTarget.current
    LaunchedEffect(activeGuideTarget) {
        when (activeGuideTarget) {
            "commitments.recurring" -> selectedSection = 1
            "commitments.add", "commitments.records" -> selectedSection = 0
            else -> Unit
        }
    }
    var editor by remember { mutableStateOf<CommitmentEntity?>(null) }
    var editorOpen by remember { mutableStateOf(false) }
    var editError by remember { mutableStateOf<String?>(null) }
    var savingId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<Pair<String, String>?>(null) }
    var deleteTarget by remember { mutableStateOf<CommitmentEntity?>(null) }
    var pendingDelete by remember { mutableStateOf(false) }
    var recurringEditor by remember { mutableStateOf<RecurringRuleEntity?>(null) }
    var recurringEditorOpen by remember { mutableStateOf(false) }
    var recurringEditError by remember { mutableStateOf<String?>(null) }
    var recurringSaving by remember { mutableStateOf(false) }
    var recurringBusyId by remember { mutableStateOf<String?>(null) }
    var recurringActionError by remember { mutableStateOf<String?>(null) }
    var recurringDeleteTarget by remember { mutableStateOf<RecurringRuleEntity?>(null) }
    var recurringDeleteBusy by remember { mutableStateOf(false) }

    val progress = remember(snapshot.commitments, snapshot.commitmentPayments, snapshot.transactions) {
        snapshot.commitmentProgress().sortedWith(
            compareBy<CommitmentProgress> { it.commitment.archived }
                .thenBy { it.commitment.dueEpochDay }
                .thenBy { it.commitment.name.lowercase() },
        )
    }
    val active = progress.filterNot { it.commitment.archived }
    val archived = progress.filter { it.commitment.archived }
    val alreadyLinkedIds = remember(snapshot.commitmentPayments) {
        snapshot.commitmentPayments.mapTo(mutableSetOf()) { it.transactionId }
    }
    val linkedTransactionsById = remember(snapshot.transactions) { snapshot.transactions.associateBy { it.id } }
    val netExpenseMinorById = remember(snapshot.transactions) { snapshot.netExpenseMinorById() }
    val unlinkedExpenseCandidates = remember(snapshot.transactions, alreadyLinkedIds) {
        snapshot.transactions
            .filter { it.type == TransactionType.EXPENSE && it.id !in alreadyLinkedIds }
    }
    val unlinkedExpenses = remember(snapshot.transactions, alreadyLinkedIds, snapshot.currencyCode) {
        snapshot.transactions
            .filter {
                it.type == TransactionType.EXPENSE &&
                    it.id !in alreadyLinkedIds &&
                    it.currencyCode == snapshot.currencyCode &&
                    (netExpenseMinorById[it.id] ?: 0L) > 0L
            }
            .sortedWith(compareByDescending<com.mizani.money.data.local.TransactionEntity> { it.localDateEpochDay }
                .thenByDescending { it.occurredAt })
    }
    val linkableExpensesByCommitment = remember(active, unlinkedExpenses, netExpenseMinorById) {
        active.associate { item ->
            item.commitment.id to unlinkedExpenses.filter { expense ->
                (netExpenseMinorById[expense.id] ?: 0L) <= item.remainingWorkspaceMinor
            }
        }
    }

    if (editorOpen) {
        CommitmentEditorDialog(
            initial = editor,
            state = state,
            vm = vm,
            busy = savingId == "__editor__",
            error = editError,
            onDismiss = {
                if (savingId != "__editor__") {
                    editorOpen = false
                    editor = null
                    editError = null
                }
            },
            onSave = { draft ->
                savingId = "__editor__"
                editError = null
                scope.launch {
                    runCatching { vm.finance.saveCommitment(editor?.id, draft) }
                        .onSuccess {
                            editorOpen = false
                            editor = null
                            editError = null
                        }
                        .onFailure { editError = it.message ?: UiStr.s(R.string.ui_218fc09ce8) }
                    savingId = null
                }
            },
        )
    }

    if (recurringEditorOpen) {
        RecurringEditorDialog(
            initial = recurringEditor,
            state = state,
            busy = recurringSaving,
            error = recurringEditError,
            onDismiss = {
                if (!recurringSaving) {
                    recurringEditorOpen = false
                    recurringEditor = null
                    recurringEditError = null
                }
            },
            onSave = { draft ->
                recurringSaving = true
                recurringEditError = null
                scope.launch {
                    runCatching { vm.finance.saveRecurring(recurringEditor?.id, draft) }
                        .onSuccess {
                            recurringEditorOpen = false
                            recurringEditor = null
                            recurringEditError = null
                        }
                        .onFailure { recurringEditError = it.message ?: UiStr.s(R.string.ui_26e8429eae) }
                    recurringSaving = false
                }
            },
        )
    }

    if (deleteTarget != null) {
        MizaniConfirmDialog(
            title = "Hapus ${deleteTarget?.name}?",
            body = UiStr.s(R.string.ui_1a7b6c2ca9),
            confirmLabel = UiStr.s(R.string.ui_5b4c991c33),
            destructive = true,
            dismissLabel = UiStr.s(R.string.ui_d9f3692497),
            onDismiss = { if (!pendingDelete) deleteTarget = null },
            onConfirm = {
                val selected = deleteTarget ?: return@MizaniConfirmDialog
                pendingDelete = true
                scope.launch {
                    runCatching { vm.finance.deleteCommitment(selected.id) }
                        .onSuccess { deleteTarget = null; error = null }
                        .onFailure { error = it.message ?: UiStr.s(R.string.ui_918d317e74) }
                    pendingDelete = false
                }
            },
        )
    }

    if (recurringDeleteTarget != null) {
        MizaniConfirmDialog(
            title = "Hapus ${recurringDeleteTarget?.name}?",
            body = UiStr.s(R.string.ui_d346c03911),
            confirmLabel = UiStr.s(R.string.ui_e41c880e70),
            destructive = true,
            dismissLabel = UiStr.s(R.string.ui_d9f3692497),
            onDismiss = { if (!recurringDeleteBusy) recurringDeleteTarget = null },
            onConfirm = {
                val selected = recurringDeleteTarget ?: return@MizaniConfirmDialog
                recurringDeleteBusy = true
                scope.launch {
                    runCatching { vm.finance.deleteRecurring(selected.id) }
                        .onSuccess { recurringDeleteTarget = null; recurringActionError = null }
                        .onFailure { recurringActionError = it.message ?: UiStr.s(R.string.ui_da8ed664fd) }
                    recurringDeleteBusy = false
                }
            },
        )
    }

    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(
            title = UiStr.s(R.string.ui_39ff9c58e8),
            subtitle = if (selectedSection == 0) {
                UiStr.s(R.string.ui_758b4ab640)
            } else {
                UiStr.s(R.string.ui_735db0f097)
            },
            actions = {
                GuideHelpAction("Tagihan dan komitmen", onOpenGuide)
                IconButton(
                    modifier = Modifier.guideTarget("commitments.add"),
                    onClick = {
                        if (selectedSection == 0) {
                            editor = null
                            editError = null
                            editorOpen = true
                        } else {
                            recurringEditor = null
                            recurringEditError = null
                            recurringEditorOpen = true
                        }
                    },
                ) {
                    Icon(
                        Icons.Rounded.Add,
                        contentDescription = if (selectedSection == 0) UiStr.s(R.string.ui_bdde4b16f8) else "Tambah item berulang",
                    )
                }
            },
        )
        PrimaryTabRow(
            selectedTabIndex = selectedSection,
            modifier = Modifier.fillMaxWidth().guideTarget("commitments.tabs"),
        ) {
            Tab(
                selected = selectedSection == 0,
                onClick = { selectedSection = 0 },
                text = { Text(stringResource(R.string.ui_7e6f949566)) },
            )
            Tab(
                selected = selectedSection == 1,
                onClick = { selectedSection = 1 },
                text = { Text(stringResource(R.string.ui_349f0e5ffd)) },
            )
        }
        if (selectedSection == 0) {
            Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.lg)
                .padding(top = Spacing.lg)
                .padding(bottom = Spacing.bottom),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            Text(
                UiStr.s(R.string.ui_33f41ec50e),
                style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 23.sp, letterSpacing = 0.1.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (error != null) {
                Text(error.orEmpty(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            if (active.isEmpty()) {
                MizaniCard(modifier = Modifier.fillMaxWidth().guideTarget("commitments.records")) {
                    Text(
                        if (archived.isEmpty()) UiStr.s(R.string.ui_991417d99e)
                        else UiStr.s(R.string.ui_53254fc510),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Spacer(Modifier.height(Spacing.xs))
                    Text(
                        if (archived.isEmpty()) {
                            UiStr.s(R.string.ui_a4a3438d0b)
                        } else {
                            UiStr.s(R.string.ui_0f0840f243)
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 22.sp),
                    )
                    Spacer(Modifier.height(Spacing.md))
                    Button(
                        onClick = { editor = null; editError = null; editorOpen = true },
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        Icon(Icons.Rounded.Add, contentDescription = null)
                        Spacer(Modifier.padding(horizontal = 2.dp))
                        Text(stringResource(R.string.ui_1dad429dae))
                    }
                }
            } else {
                active.forEach { item ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .then(if (item == active.firstOrNull()) Modifier.guideTarget("commitments.records") else Modifier),
                    ) {
                        CommitmentCard(
                            item = item,
                            state = state,
                            linkedTransactions = linkedTransactionsById,
                            linkableExpenses = linkableExpensesByCommitment[item.commitment.id].orEmpty(),
                            hasRecordedExpenses = unlinkedExpenseCandidates.isNotEmpty(),
                            netExpenseMinorById = netExpenseMinorById,
                            actionError = actionError?.takeIf { it.first == item.commitment.id }?.second,
                            busy = savingId == item.commitment.id,
                            onRecordExpense = onRecordExpense,
                            onEdit = { editor = item.commitment; editError = null; editorOpen = true },
                            onArchive = { archivedValue ->
                                savingId = item.commitment.id
                                scope.launch {
                                    runCatching { vm.finance.setCommitmentArchived(item.commitment.id, archivedValue) }
                                        .onFailure { error = it.message ?: UiStr.s(R.string.ui_e50da42c32) }
                                    savingId = null
                                }
                            },
                            onDelete = { deleteTarget = item.commitment },
                            onLink = { transactionId ->
                                savingId = item.commitment.id
                                error = null
                                actionError = null
                                scope.launch {
                                    runCatching { vm.finance.linkExpenseToCommitment(item.commitment.id, transactionId) }
                                        .onFailure {
                                            actionError = item.commitment.id to commitmentActionMessage(
                                                it,
                                                UiStr.s(R.string.ui_1efc1f55eb),
                                            )
                                        }
                                    savingId = null
                                }
                            },
                            onUnlink = { paymentId ->
                                savingId = item.commitment.id
                                error = null
                                actionError = null
                                scope.launch {
                                    runCatching { vm.finance.unlinkCommitmentPayment(paymentId) }
                                        .onFailure {
                                            actionError = item.commitment.id to commitmentActionMessage(
                                                it,
                                                UiStr.s(R.string.ui_6c4e86c7f8),
                                            )
                                        }
                                    savingId = null
                                }
                            },
                        )
                    }
                }
            }
            if (archived.isNotEmpty()) {
                SectionHeader("Diarsipkan")
                archived.forEach { item ->
                    CommitmentCard(
                        item = item,
                        state = state,
                        linkedTransactions = linkedTransactionsById,
                        linkableExpenses = emptyList(),
                        hasRecordedExpenses = false,
                        netExpenseMinorById = netExpenseMinorById,
                        actionError = actionError?.takeIf { it.first == item.commitment.id }?.second,
                        busy = savingId == item.commitment.id,
                        onRecordExpense = onRecordExpense,
                        onEdit = { editor = item.commitment; editError = null; editorOpen = true },
                        onArchive = { archivedValue ->
                            savingId = item.commitment.id
                            scope.launch {
                                runCatching { vm.finance.setCommitmentArchived(item.commitment.id, archivedValue) }
                                    .onFailure { error = it.message ?: UiStr.s(R.string.ui_e50da42c32) }
                                savingId = null
                            }
                        },
                        onDelete = { deleteTarget = item.commitment },
                        onLink = {},
                        onUnlink = { paymentId ->
                            savingId = item.commitment.id
                            actionError = null
                            scope.launch {
                                runCatching { vm.finance.unlinkCommitmentPayment(paymentId) }
                                    .onFailure {
                                        actionError = item.commitment.id to commitmentActionMessage(
                                            it,
                                            UiStr.s(R.string.ui_6c4e86c7f8),
                                        )
                                    }
                                savingId = null
                            }
                        },
                    )
                }
            }
            }
        } else {
            RecurringSchedulesPanel(
                state = state,
                today = today,
                busyId = recurringBusyId ?: if (recurringSaving) "__editor__" else null,
                message = recurringActionError,
                modifier = Modifier.weight(1f),
                onAdd = {
                    recurringEditor = null
                    recurringEditError = null
                    recurringEditorOpen = true
                },
                onEdit = { rule ->
                    recurringEditor = rule
                    recurringEditError = null
                    recurringEditorOpen = true
                },
                onArchive = { rule, archivedValue ->
                    recurringActionError = null
                    recurringBusyId = rule.id
                    scope.launch {
                        runCatching { vm.finance.setRecurringArchived(rule.id, archivedValue) }
                            .onFailure { recurringActionError = it.message ?: UiStr.s(R.string.ui_23f5b48053) }
                        recurringBusyId = null
                    }
                },
                onRecord = { rule ->
                    recurringActionError = null
                    recurringBusyId = rule.id
                    scope.launch {
                        runCatching { vm.finance.markRecurringPaid(rule.id, today) }
                            .onFailure { recurringActionError = it.message ?: UiStr.s(R.string.ui_1acfccd2bc) }
                        recurringBusyId = null
                    }
                },
                onDelete = { rule -> recurringDeleteTarget = rule },
            )
        }
    }
}

@Composable
private fun CommitmentCard(
    item: CommitmentProgress,
    state: AppUiState,
    linkedTransactions: Map<String, com.mizani.money.data.local.TransactionEntity>,
    linkableExpenses: List<com.mizani.money.data.local.TransactionEntity>,
    hasRecordedExpenses: Boolean,
    netExpenseMinorById: Map<String, Long>,
    actionError: String?,
    busy: Boolean,
    onRecordExpense: () -> Unit,
    onEdit: () -> Unit,
    onArchive: (Boolean) -> Unit,
    onDelete: () -> Unit,
    onLink: (String) -> Unit,
    onUnlink: (String) -> Unit,
) {
    val commitment = item.commitment
    val workspaceCurrency = state.currency
    val currency = Currencies.byCode(commitment.currencyCode)
    val categoryName = state.snapshot.categoryName(commitment.categoryId)
    val date = LocalDate.ofEpochDay(commitment.dueEpochDay)
    val fraction = if (commitment.targetMinor > 0L) {
        (item.paidMinor.toDouble() / commitment.targetMinor.toDouble()).coerceIn(0.0, 1.0).toFloat()
    } else 0f
    val links = state.snapshot.commitmentPayments.filter { it.commitmentId == commitment.id }

    MizaniCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(commitment.name, style = MaterialTheme.typography.titleMedium)
                Text(
                    "Jatuh tempo ${DateText.medium(date)} · $categoryName · ${currency.code}${if (commitment.reminderDaysBefore > 0) " · ${commitment.reminderDaysBefore}-hari pengingat" else ""}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            IconButton(onClick = onEdit, enabled = !busy) {
                Icon(Icons.Rounded.Edit, contentDescription = "Ubah ${commitment.name}")
            }
        }
        Spacer(Modifier.height(Spacing.md))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(UiStr.s(R.string.ui_dc9d4584a5), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(MoneyFormat.format(item.paidMinor, currency), style = MaterialTheme.typography.titleSmall)
            }
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                Text(UiStr.s(R.string.ui_cc632b5e2f), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(MoneyFormat.format(item.remainingMinor, currency), style = MaterialTheme.typography.titleSmall)
            }
        }
        Spacer(Modifier.height(Spacing.sm))
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            ProgressBar(
                fraction = fraction,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f)
                        contentDescription = "${(fraction * 100).toInt()} percent paid toward ${commitment.name}"
                    },
            )
            Text(
                "${MoneyFormat.format(item.paidMinor, currency)} of ${MoneyFormat.format(commitment.targetMinor, currency)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (commitment.currencyCode != workspaceCurrency.code) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Target perencanaan terkonversi: ${MoneyFormat.format(commitment.targetWorkspaceMinor, workspaceCurrency)} · rate ${commitment.exchangeRate ?: "not saved"} · ${commitment.exchangeRateDate ?: "reference date unavailable"}",
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    MizaniInfoButton(
                        infoTitle = stringResource(R.string.info_commitment_rate_title),
                        infoBody = stringResource(R.string.info_commitment_rate_body),
                        contentDescription = stringResource(R.string.info_commitment_rate_title),
                    )
                }
            }
        }
        if (links.isNotEmpty()) {
            Spacer(Modifier.height(Spacing.sm))
            Text(UiStr.s(R.string.ui_082fd49d49), style = MaterialTheme.typography.labelLarge)
            links.forEach { link ->
                val transaction = linkedTransactions[link.transactionId] ?: return@forEach
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Icon(Icons.Rounded.Payments, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            transaction.payee.ifBlank { state.snapshot.categoryName(transaction.categoryId) },
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            "${DateText.medium(LocalDate.ofEpochDay(transaction.localDateEpochDay))} · ${MoneyFormat.format(transaction.amountMinor, workspaceCurrency)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    TextButton(onClick = { onUnlink(link.id) }, enabled = !busy) { Text(stringResource(R.string.ui_0dc2913c6e)) }
                }
            }
        }
        if (!commitment.archived && item.remainingMinor > 0L && linkableExpenses.isNotEmpty()) {
            Spacer(Modifier.height(Spacing.xs))
            Text(
                UiStr.s(R.string.ui_8c4af8d98d),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            MizaniPicker(
                selectedText = if (busy) "Memperbarui…" else UiStr.s(R.string.ui_97ab8e44bc),
                options = linkableExpenses.map { expense ->
                    val label = expense.payee.ifBlank { state.snapshot.categoryName(expense.categoryId) }
                    PickerOption(
                        id = expense.id,
                        label = "$label - ${MoneyFormat.format(netExpenseMinorById[expense.id] ?: expense.amountMinor, workspaceCurrency)} - ${DateText.short(LocalDate.ofEpochDay(expense.localDateEpochDay))}",
                    )
                },
                onSelect = onLink,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
        } else if (!commitment.archived && item.remainingMinor > 0L) {
            Spacer(Modifier.height(Spacing.xs))
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    if (hasRecordedExpenses) {
                        "Tidak ada pengeluaran tercatat yang cocok dengan sisa ${MoneyFormat.format(item.remainingMinor, currency)}. Catat pembayaran dalam ${currency.code}, atau pilih pengeluaran dalam target yang sudah dikonversi."
                    } else {
                        UiStr.s(R.string.ui_a4fb02d63d)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = onRecordExpense, enabled = !busy) {
                    Icon(Icons.Rounded.Add, contentDescription = null)
                    Text(stringResource(R.string.ui_7db0e7e66e))
                }
            }
        }
        actionError?.let { message ->
            Text(
                message,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
            )
        }
        Spacer(Modifier.height(Spacing.xs))
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            TextButton(onClick = { onArchive(!commitment.archived) }, enabled = !busy) {
                Icon(Icons.Rounded.Archive, contentDescription = null)
                Text(if (commitment.archived) "Pulihkan" else "Arsipkan")
            }
            TextButton(onClick = onDelete, enabled = !busy) {
                Icon(Icons.Rounded.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text(UiStr.s(R.string.ui_f6fdbe48dc), color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun commitmentActionMessage(error: Throwable, fallback: String): String = when (error.message) {
    UiStr.s(R.string.ui_ccaddd144b) ->
        UiStr.s(R.string.ui_d8207b6623)
    UiStr.s(R.string.ui_1b4ef264ce) ->
        UiStr.s(R.string.ui_88ab34f81f)
    UiStr.s(R.string.ui_137e53ecf1) ->
        UiStr.s(R.string.ui_9c5a7618d7)
    UiStr.s(R.string.ui_8d1e1cc000) ->
        UiStr.s(R.string.ui_25f1c34439)
    else -> fallback
}

private fun commitmentRateFailureMessage(error: Exception, hasCachedRate: Boolean): String = when {
    hasCachedRate -> UiStr.s(R.string.ui_cd0fdac9da)
    error is ExchangeRateUnavailableException -> UiStr.s(R.string.ui_fed145a04c)
    else -> UiStr.s(R.string.ui_3f2da1e44b)
}

@Composable
private fun CommitmentEditorDialog(
    initial: CommitmentEntity?,
    state: AppUiState,
    vm: AppViewModel,
    busy: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onSave: (CommitmentDraft) -> Unit,
) {
    val workspaceCurrency = state.currency
    var targetCurrencyCode by remember(initial?.id) {
        mutableStateOf(initial?.currencyCode ?: workspaceCurrency.code)
    }
    val targetCurrency = Currencies.byCode(targetCurrencyCode)
    val isForeignCurrency = targetCurrency.code != workspaceCurrency.code
    var name by remember(initial?.id) { mutableStateOf(initial?.name.orEmpty()) }
    var amount by remember(initial?.id) {
        mutableStateOf(initial?.targetMinor?.let { MoneyFormat.toInput(it, targetCurrency) }.orEmpty())
    }
    var dueDate by remember(initial?.id) {
        mutableStateOf(initial?.let { LocalDate.ofEpochDay(it.dueEpochDay) } ?: LocalDate.now())
    }
    var categoryId by remember(initial?.id) { mutableStateOf(initial?.categoryId) }
    var reminderDays by remember(initial?.id) {
        mutableStateOf(initial?.reminderDaysBefore?.toString() ?: "0")
    }
    var exchangeRate by remember(initial?.id) { mutableStateOf<ExchangeRate?>(null) }
    var isRateLoading by remember(initial?.id) { mutableStateOf(false) }
    var rateError by remember(initial?.id) { mutableStateOf<String?>(null) }
    var validationError by remember(initial?.id) { mutableStateOf<String?>(null) }
    val nameFocusRequester = remember(initial?.id) { FocusRequester() }
    val amountFocusRequester = remember(initial?.id) { FocusRequester() }
    val reminderFocusRequester = remember(initial?.id) { FocusRequester() }
    val nameError = validationError?.takeIf { it.startsWith(UiStr.s(R.string.ui_7e5fe97f0e)) }
    val amountError = validationError?.takeIf { it.startsWith(UiStr.s(R.string.ui_65472fb06d)) }
    val reminderError = validationError?.takeIf { it.startsWith(UiStr.s(R.string.ui_c8fd4cdcd0)) }

    LaunchedEffect(targetCurrency.code, workspaceCurrency.code, initial?.id) {
        if (!isForeignCurrency) {
            exchangeRate = null
            rateError = null
            isRateLoading = false
            return@LaunchedEffect
        }

        val savedRate = initial?.takeIf {
            it.currencyCode == targetCurrency.code && it.exchangeRate != null && it.exchangeRateDate != null
        }?.let { commitment ->
            runCatching {
                ExchangeRate(
                    commitment.currencyCode,
                    workspaceCurrency.code,
                    commitment.exchangeRate!!,
                    LocalDate.parse(commitment.exchangeRateDate!!),
                )
            }.getOrNull()
        }
        if (savedRate != null) {
            exchangeRate = savedRate
            rateError = null
            isRateLoading = false
            return@LaunchedEffect
        }

        exchangeRate = null
        rateError = null
        isRateLoading = true
        try {
            exchangeRate = vm.exchangeRates.cachedRate(targetCurrency.code, workspaceCurrency.code)
            val shouldRefresh = vm.exchangeRates.shouldRefresh(targetCurrency.code, workspaceCurrency.code)
            if (shouldRefresh) {
                try {
                    exchangeRate = vm.exchangeRates.refreshRate(targetCurrency.code, workspaceCurrency.code)
                    rateError = null
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    rateError = commitmentRateFailureMessage(failure, exchangeRate != null)
                }
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            rateError = commitmentRateFailureMessage(failure, exchangeRate != null)
        } finally {
            isRateLoading = false
        }
    }

    MizaniAlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(if (initial == null) UiStr.s(R.string.ui_9aaf28de93) else UiStr.s(R.string.ui_04d8501263)) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 560.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.md),
            ) {
                Text(
                    UiStr.s(R.string.ui_09870b9fcc),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(80); validationError = null },
                    label = { Text(stringResource(R.string.ui_709a23220f)) },
                    isError = nameError != null,
                    supportingText = { nameError?.let { message ->
                        Text(message, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                    } },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(nameFocusRequester),
                )
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it; validationError = null },
                    label = { Text("Nominal target (${targetCurrency.code})") },
                    isError = amountError != null,
                    supportingText = { amountError?.let { message ->
                        Text(message, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                    } },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(amountFocusRequester),
                )
                MizaniCurrencyPicker(
                    selectedCode = targetCurrencyCode,
                    onSelect = {
                        if (it != targetCurrencyCode) {
                            // Do not silently reinterpret an amount under a new currency.
                            // Clear it so the user enters a value with the new currency label.
                            amount = ""
                        }
                        targetCurrencyCode = it
                        validationError = null
                        rateError = null
                    },
                    fieldLabel = UiStr.s(R.string.ui_3da2599f1c),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (isForeignCurrency) {
                    val rate = exchangeRate
                    Text(
                        when {
                            isRateLoading && rate == null -> UiStr.s(R.string.ui_683961e638)
                            rate != null -> buildString {
                                append("1 ${rate.baseCurrencyCode} = ${rate.rate} ${rate.quoteCurrencyCode} · ${DateText.medium(rate.date)}. The target will be saved using this rate.")
                                rateError?.let { append(" $it") }
                            }
                            else -> rateError ?: UiStr.s(R.string.ui_fed145a04c)
                        },
                        color = if (rate == null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.semantics {
                            if (rate == null) liveRegion = LiveRegionMode.Polite
                        },
                    )
                }
                DateField(label = UiStr.s(R.string.ui_4c1aeebc43), date = dueDate, onDateSelected = { dueDate = it }, modifier = Modifier.fillMaxWidth())
                val categories = state.snapshot.categories.filter {
                    it.type == CategoryType.EXPENSE && !it.archived || it.id == initial?.categoryId
                }
                val selectedCategory = categories.firstOrNull { it.id == categoryId }
                MizaniPicker(
                    selectedText = selectedCategory?.name ?: UiStr.s(R.string.ui_fdc24c707e),
                    options = categories.map { PickerOption(it.id, it.name) },
                    onSelect = { categoryId = it; validationError = null },
                    modifier = Modifier.fillMaxWidth(),
                    noneLabel = UiStr.s(R.string.ui_fdc24c707e),
                    onSelectNone = { categoryId = null; validationError = null },
                    searchable = categories.size > 6,
                    searchHint = UiStr.s(R.string.ui_bdfb85040a),
                    fieldLabel = "Kategori",
                )
                OutlinedTextField(
                    value = reminderDays,
                    onValueChange = { value -> reminderDays = value.filter(Char::isDigit).take(2); validationError = null },
                    label = { Text(stringResource(R.string.ui_6d438fda8f)) },
                    isError = reminderError != null,
                    supportingText = {
                        Text(
                            reminderError ?: UiStr.s(R.string.ui_a95d0a3dfb),
                            modifier = if (reminderError != null) Modifier.semantics {
                                liveRegion = LiveRegionMode.Polite
                            } else Modifier,
                        )
                    },
                    leadingIcon = { Icon(Icons.Rounded.NotificationsActive, contentDescription = null) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(reminderFocusRequester),
                )
                error?.let { message ->
                    Text(
                        message,
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !busy,
                onClick = {
                    val parsedAmount = MoneyFormat.parse(amount, targetCurrency)
                    val conversionRate = exchangeRate?.rate?.toBigDecimalOrNull()
                    val convertedTargetWorkspace = parsedAmount?.let { value ->
                        if (!isForeignCurrency) value else conversionRate?.let { rate ->
                            runCatching {
                                CurrencyConversion.convertMinorUnits(
                                    value,
                                    targetCurrency,
                                    workspaceCurrency,
                                    rate,
                                )
                            }.getOrNull()
                        }
                    }
                    val days = reminderDays.toIntOrNull()
                    when {
                        name.isBlank() -> {
                            validationError = UiStr.s(R.string.ui_2d0fa53fca)
                            nameFocusRequester.requestFocus()
                        }
                        parsedAmount == null || parsedAmount <= 0L -> {
                            validationError = UiStr.s(R.string.ui_7a670b3aea)
                            amountFocusRequester.requestFocus()
                        }
                        isForeignCurrency && isRateLoading -> {
                            validationError = UiStr.s(R.string.ui_170a741cb4)
                        }
                        isForeignCurrency && conversionRate == null -> {
                            validationError = rateError ?: UiStr.s(R.string.ui_fed145a04c)
                        }
                        convertedTargetWorkspace == null || convertedTargetWorkspace <= 0L -> {
                            validationError = "Nominal ini terlalu kecil untuk dikonversi ke ${workspaceCurrency.code}."
                            amountFocusRequester.requestFocus()
                        }
                        days == null || days !in 0..30 -> {
                            validationError = UiStr.s(R.string.ui_e26682f70f)
                            reminderFocusRequester.requestFocus()
                        }
                        else -> {
                            validationError = null
                            onSave(
                                CommitmentDraft(
                                    name = name,
                                    targetMinor = parsedAmount,
                                    dueDate = dueDate,
                                    categoryId = categoryId,
                                    reminderDaysBefore = days,
                                    currencyCode = targetCurrency.code,
                                    targetWorkspaceMinor = convertedTargetWorkspace,
                                    exchangeRate = exchangeRate?.rate,
                                    exchangeRateDate = exchangeRate?.date,
                                ),
                            )
                        }
                    }
                },
            ) {
                if (busy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp).semantics {
                            contentDescription = UiStr.s(R.string.ui_4554b57e5b)
                        },
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.padding(horizontal = 2.dp))
                    Text(stringResource(R.string.ui_ae7e887517))
                } else Text(if (initial == null) UiStr.s(R.string.ui_e6532c4f56) else UiStr.s(R.string.ui_179359b39e))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !busy) { Text(stringResource(R.string.ui_77dfd2135f)) }
        },
    )
}
