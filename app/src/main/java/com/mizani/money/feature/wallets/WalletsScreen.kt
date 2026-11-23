package com.mizani.money.feature.wallets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Unarchive
import com.mizani.money.ui.components.MizaniAlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mizani.money.R
import com.mizani.money.core.model.WalletType
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.money.Currency
import com.mizani.money.core.money.MoneyFormat
import com.mizani.money.data.repo.TransactionDraft
import com.mizani.money.domain.finance.LedgerBalanceRules
import com.mizani.money.domain.finance.WalletBalanceBreakdown
import com.mizani.money.feature.lock.ProtectedBalanceValue
import com.mizani.money.feature.lock.WalletBalanceVisibilityControl
import com.mizani.money.data.local.WalletEntity
import com.mizani.money.ui.AppUiState
import com.mizani.money.ui.AppViewModel
import com.mizani.money.ui.components.EmptyState
import com.mizani.money.ui.components.MizaniAmountField
import com.mizani.money.ui.components.MizaniCard
import com.mizani.money.ui.components.MizaniPicker
import com.mizani.money.ui.components.MizaniStatCard
import com.mizani.money.ui.components.MizaniStatRow
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.MizaniPageContent
import com.mizani.money.ui.components.PickerOption
import com.mizani.money.ui.components.Spacing
import com.mizani.money.ui.guides.guideTarget
import com.mizani.money.ui.guides.GuideHelpAction
import com.mizani.money.ui.components.StatusBanner
import com.mizani.money.ui.components.WalletAvatar
import com.mizani.money.ui.components.parseHexColor
import com.mizani.money.ui.theme.BrandPalette
import kotlinx.coroutines.launch

@Composable
fun WalletsScreen(
    vm: AppViewModel,
    state: AppUiState,
    onBack: () -> Unit,
    onSetupPin: () -> Unit,
    onOpenGuide: () -> Unit,
) {
    val snapshot = state.snapshot
    val currency = state.currency
    val balances = remember(snapshot) { snapshot.walletBalancesOrNull() }
    val balanceBreakdowns = remember(snapshot) { snapshot.walletBalanceBreakdownsOrNull() }
    val active = snapshot.wallets.filter { !it.archived && it.deletedAt == null }
    val archived = snapshot.wallets.filter { it.archived && it.deletedAt == null }
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf<WalletEntity?>(null) }
    var showDialog by remember { mutableStateOf(false) }
    var reconcilingWallet by remember { mutableStateOf<WalletEntity?>(null) }
    var reconciliationError by remember { mutableStateOf<String?>(null) }
    var savingReconciliation by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(state.walletBalancesVisible) {
        if (!state.walletBalancesVisible) reconcilingWallet = null
    }

    val total = balances?.let { values -> active.sumOf { values[it.id] ?: 0L } }
    val liquid = balances?.let { values -> active.filter { it.type != WalletType.DEBT }.sumOf { values[it.id] ?: 0L } }

    if (showDialog) {
        WalletDialog(
            initial = editing,
            currency = currency,
            balanceVisible = state.walletBalancesVisible,
            currentBalance = editing?.let { balances?.get(it.id) },
            breakdown = editing?.let { balanceBreakdowns?.get(it.id) },
            canArchive = active.size > 1,
            onDismiss = { showDialog = false; editing = null },
            onReconcile = { wallet ->
                showDialog = false
                editing = null
                reconciliationError = null
                reconcilingWallet = wallet
            },
            onSave = { name, type, opening, color, icon ->
                val walletToUpdate = editing
                scope.launch {
                    runCatching {
                        if (walletToUpdate == null) {
                            vm.finance.addWallet(name, type, opening, color, icon)
                        } else {
                            vm.finance.updateWallet(walletToUpdate.id, name, type, opening, color, icon)
                        }
                    }.onSuccess {
                        showDialog = false
                        editing = null
                        error = null
                    }.onFailure { error = it.message ?: "Could not save this wallet. Try again." }
                }
            },
            onArchive = { wallet, archived ->
                scope.launch {
                    runCatching { vm.finance.setWalletArchived(wallet.id, archived) }
                        .onSuccess { showDialog = false; editing = null }
                        .onFailure { error = it.message ?: "Could not update this wallet. Try again." }
                }
            },
        )
    }

    reconcilingWallet?.let { wallet ->
        val currentBalance = balances?.get(wallet.id)
        if (currentBalance != null && state.walletBalancesVisible) {
            ReconcileBalanceDialog(
                wallet = wallet,
                currency = currency,
                currentBalanceMinor = currentBalance,
                error = reconciliationError,
                saving = savingReconciliation,
                onDismiss = { if (!savingReconciliation) reconcilingWallet = null },
                onConfirm = { targetBalanceMinor ->
                    val adjustment = runCatching {
                        LedgerBalanceRules.adjustmentToTarget(currentBalance, targetBalanceMinor)
                    }.getOrElse {
                        reconciliationError = "The difference is outside the supported range."
                        return@ReconcileBalanceDialog
                    }
                    if (adjustment == 0L) return@ReconcileBalanceDialog
                    savingReconciliation = true
                    scope.launch {
                        runCatching {
                            vm.finance.saveTransaction(
                                TransactionDraft(
                                    type = TransactionType.ADJUSTMENT,
                                    amountMinor = adjustment,
                                    walletId = wallet.id,
                                    note = "Balance reconciliation",
                                ),
                            )
                        }.onSuccess {
                            reconcilingWallet = null
                            reconciliationError = null
                        }.onFailure {
                            reconciliationError = it.message ?: "Could not save the balance adjustment. Try again."
                        }
                        savingReconciliation = false
                    }
                },
            )
        }
    }

    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(
            title = stringResource(R.string.ui_98d5a197e5),
            subtitle = "${active.size} active",
            onBack = onBack,
            actions = {
                GuideHelpAction(featureName = "Wallets and balances", onClick = onOpenGuide)
                Box(Modifier.guideTarget("wallets.visibility")) {
                    WalletBalanceVisibilityControl(vm, state, onSetupPin)
                }
                IconButton(onClick = { editing = null; showDialog = true }) {
                    Icon(Icons.Rounded.Add, contentDescription = stringResource(R.string.ui_6fe27a1a61))
                }
            },
        )
        MizaniPageContent {
            if (error != null) {
                StatusBanner(
                    text = error!!,
                    isError = true,
                    onDismiss = { error = null },
                )
            }
            if (balances == null) {
                StatusBanner(
                    text = stringResource(R.string.ui_d5e075810a),
                    isError = true,
                )
            }

            Box(Modifier.fillMaxWidth().guideTarget("wallets.total")) {
            MizaniStatRow {
                MizaniStatCard(
                    label = stringResource(R.string.ui_d746faee9c),
                    value = when {
                        total == null -> "—"
                        state.walletBalancesVisible -> MoneyFormat.format(total, currency)
                        else -> "••••••"
                    },
                    labelRowMinHeight = 48.dp,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    valueContentDescription = when {
                        total == null -> "Across wallet balance unavailable; review Activity"
                        state.walletBalancesVisible -> "Across wallets ${MoneyFormat.format(total, currency)}"
                        else -> "Across wallet balances hidden"
                    },
                )
                MizaniStatCard(
                    label = stringResource(R.string.ui_4ad3e2141b),
                    value = when {
                        liquid == null -> "—"
                        state.walletBalancesVisible -> MoneyFormat.format(liquid, currency)
                        else -> "••••••"
                    },
                    labelRowMinHeight = 48.dp,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    accent = MaterialTheme.colorScheme.primary,
                    infoTitle = stringResource(R.string.info_liquid_title),
                    infoBody = stringResource(R.string.info_liquid_body),
                    valueContentDescription = when {
                        liquid == null -> "Liquid balance unavailable; review Activity"
                        state.walletBalancesVisible -> "Liquid balance ${MoneyFormat.format(liquid, currency)}"
                        else -> "Liquid balance hidden"
                    },
                )
            }
            }

            Text(
                stringResource(R.string.ui_67be2e7398),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (active.isEmpty()) {
                Box(Modifier.fillMaxWidth().guideTarget("wallets.rows")) {
                    EmptyState(
                        title = stringResource(R.string.ui_e5c8318756),
                        body = "Create a cash, mobile-money, bank, card or savings wallet to start.",
                        iconRes = R.drawable.ic_ph_wallet,
                        actionLabel = stringResource(R.string.ui_6fe27a1a61),
                        onAction = { editing = null; showDialog = true },
                    )
                }
            } else {
                active.forEachIndexed { index, wallet ->
                    WalletCard(
                        wallet = wallet,
                        balance = balances?.get(wallet.id),
                        currency = currency,
                        balanceVisible = state.walletBalancesVisible,
                        modifier = if (index == 0) Modifier.guideTarget("wallets.rows") else Modifier,
                        onClick = { editing = wallet; showDialog = true },
                    )
                }
            }

            if (archived.isNotEmpty()) {
                Spacer(Modifier.height(Spacing.sm))
                Text(stringResource(R.string.ui_eddc813f35), style = MaterialTheme.typography.titleSmall)
                archived.forEach { wallet ->
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.medium)
                            .clickable { editing = wallet; showDialog = true },
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        Row(
                            modifier = Modifier.padding(Spacing.md),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            WalletAvatar(wallet.type, wallet.colorHex, size = 34)
                            Spacer(Modifier.width(Spacing.md))
                            Text(wallet.name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                            Text(
                                text = when {
                                    balances == null -> "—"
                                    state.walletBalancesVisible -> MoneyFormat.format(balances[wallet.id] ?: 0, currency)
                                    else -> "••••••"
                                },
                                modifier = Modifier.semantics {
                                    contentDescription = when {
                                        balances == null -> "Balance unavailable; review Activity"
                                        state.walletBalancesVisible -> "Balance ${MoneyFormat.format(balances[wallet.id] ?: 0, currency)}"
                                        else -> "Balance hidden"
                                    }
                                },
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            Text(
                "A wallet is a place money lives, not an online account. Mizani does not connect to banks or " +
                    "mobile-money APIs; you record transactions yourself.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun WalletCard(
    wallet: WalletEntity,
    balance: Long?,
    currency: Currency,
    balanceVisible: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val color = parseHexColor(wallet.colorHex)
    MizaniCard(modifier = modifier.fillMaxWidth(), onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            WalletAvatar(wallet.type, wallet.colorHex, size = 44)
            Spacer(Modifier.width(Spacing.md))
            Column(Modifier.weight(1f)) {
                Text(wallet.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (wallet.name != wallet.type.label) {
                    Text(wallet.type.label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                if (balance == null) {
                    Text("—", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error)
                } else {
                    ProtectedBalanceValue(
                        amountMinor = balance,
                        currency = currency,
                        visible = balanceVisible,
                        style = MaterialTheme.typography.titleSmall,
                        color = if (balance < 0) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                }
                Text("balance", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.width(Spacing.sm))
            Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WalletDialog(
    initial: WalletEntity?,
    currency: Currency,
    balanceVisible: Boolean,
    currentBalance: Long?,
    breakdown: WalletBalanceBreakdown?,
    canArchive: Boolean,
    onDismiss: () -> Unit,
    onReconcile: (WalletEntity) -> Unit,
    onSave: (String, WalletType, Long, String, String) -> Unit,
    onArchive: (WalletEntity, Boolean) -> Unit,
) {
    var name by rememberSaveable { mutableStateOf(initial?.name ?: "") }
    var type by rememberSaveable { mutableStateOf(initial?.type ?: WalletType.CASH) }
    var openingText by rememberSaveable {
        mutableStateOf(initial?.let { MoneyFormat.toInput(kotlin.math.abs(it.openingBalanceMinor), currency) } ?: "")
    }
    var colorHex by rememberSaveable { mutableStateOf(initial?.colorHex ?: "#087F72") }
    var iconKey by rememberSaveable { mutableStateOf(initial?.icon ?: "wallet") }
    var error by remember { mutableStateOf<String?>(null) }
    val colors = remember(initial?.colorHex) {
        (BrandPalette.swatches + listOfNotNull(initial?.colorHex)).distinct()
    }
    val typeOptions = WalletType.entries.filter {
        it != WalletType.DEBT || initial?.type == WalletType.DEBT
    }
    val opening = if (initial != null && !balanceVisible) {
        kotlin.math.abs(initial.openingBalanceMinor)
    } else {
        MoneyFormat.parse(openingText, currency) ?: 0L
    }

    MizaniAlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.large,
        title = { Text(if (initial == null) "Add wallet" else "Edit wallet") },
        text = {
            Column(
                modifier = Modifier
                    .heightIn(max = 460.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(stringResource(R.string.ui_33ba81c027)) },
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(stringResource(R.string.ui_3deb745651), style = MaterialTheme.typography.labelMedium)
                MizaniPicker(
                    selectedText = type.label,
                    options = typeOptions.map { PickerOption(it.name, it.label) },
                    onSelect = { id -> type = WalletType.valueOf(id) },
                    modifier = Modifier.fillMaxWidth(),
                )
                if (initial != null && !balanceVisible) {
                    Text(
                        stringResource(R.string.ui_2b9b7725df),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    MizaniAmountField(
                        value = openingText,
                        onValueChange = { openingText = it },
                        label = when {
                            type == WalletType.DEBT -> "Amount owed when tracking began"
                            initial != null -> "Starting balance"
                            else -> "Opening balance"
                        },
                        currency = currency,
                    )
                }
                Text(
                    if (type == WalletType.DEBT) {
                        "Debt is stored as a negative balance. This is what you owed when tracking began; saved activity is added to it."
                    } else {
                        "This is the amount in the wallet when you began tracking. Saved activity is added to it; changing it does not set today's balance."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (initial != null) {
                    HorizontalDivider()
                    Text(stringResource(R.string.ui_7afe01c00b), style = MaterialTheme.typography.labelLarge)
                    if (!balanceVisible) {
                        Text(
                            stringResource(R.string.ui_9a78ee5f7c),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else if (currentBalance != null) {
                        Text(
                            MoneyFormat.format(currentBalance, currency),
                            style = MaterialTheme.typography.titleMedium,
                            color = if (currentBalance < 0L) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                        )
                        if (breakdown != null) {
                            BalanceBreakdownRows(breakdown = breakdown, currency = currency)
                        } else {
                            Text(
                                stringResource(R.string.ui_d284186adf),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (!initial.archived) {
                            TextButton(
                                onClick = { onReconcile(initial) },
                                modifier = Modifier.align(Alignment.Start),
                            ) {
                                Icon(Icons.Rounded.Tune, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(Modifier.width(4.dp))
                                Text(stringResource(R.string.ui_a5c4f97cc8))
                            }
                        }
                    } else {
                        Text(
                            stringResource(R.string.ui_cea5f85741),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
                Text(stringResource(R.string.ui_f28563a477), style = MaterialTheme.typography.labelMedium)
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    colors.forEach { hex ->
                        ColorDot(
                            hex = hex,
                            selected = colorHex == hex,
                            index = colors.indexOf(hex),
                            onClick = { colorHex = hex },
                        )
                    }
                }
                if (error != null) {
                    Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                if (initial != null && initial.archived) {
                    TextButton(
                        onClick = { onArchive(initial, false) },
                        modifier = Modifier.align(Alignment.Start),
                    ) {
                        Icon(Icons.Rounded.Unarchive, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(stringResource(R.string.ui_4950237261))
                    }
                } else if (initial != null && canArchive) {
                    TextButton(
                        onClick = { onArchive(initial, true) },
                        modifier = Modifier.align(Alignment.Start),
                    ) {
                        Icon(Icons.Rounded.Archive, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(stringResource(R.string.ui_0e0f7ea460))
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (name.isBlank()) {
                    error = "Give this wallet a name"
                } else {
                    val signedOpening = if (type == WalletType.DEBT) -opening else opening
                    onSave(name, type, signedOpening, colorHex, iconKey)
                }
            }) { Text(if (initial == null) "Add" else "Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.ui_77dfd2135f)) } },
    )
}

@Composable
private fun BalanceBreakdownRows(
    breakdown: WalletBalanceBreakdown,
    currency: Currency,
) {
    val rows = listOf(
        "Starting balance" to breakdown.openingBalanceMinor,
        "Income after fees" to breakdown.incomeNetMinor,
        "Expenses and fees" to breakdown.expenseOutflowMinor,
        "Transfers in" to breakdown.transferInMinor,
        "Transfers out and fees" to breakdown.transferOutMinor,
        "Refunds after fees" to breakdown.refundNetMinor,
        "Balance adjustments" to breakdown.adjustmentMinor,
    )
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        rows.filter { (_, amount) -> amount != 0L }.forEach { (label, amount) ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(MoneyFormat.format(amount, currency), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun ReconcileBalanceDialog(
    wallet: WalletEntity,
    currency: Currency,
    currentBalanceMinor: Long,
    error: String?,
    saving: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (Long) -> Unit,
) {
    var targetText by rememberSaveable(wallet.id) { mutableStateOf("") }
    val targetAmount = MoneyFormat.parse(targetText, currency)
    val targetBalance = targetAmount?.let { amount ->
        if (wallet.type == WalletType.DEBT) -amount else amount
    }
    val adjustment = targetBalance?.let { target ->
        runCatching { LedgerBalanceRules.adjustmentToTarget(currentBalanceMinor, target) }.getOrNull()
    }

    MizaniAlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.large,
        title = { Text("Reconcile ${wallet.name}") },
        text = {
            Column(
                modifier = Modifier
                    .heightIn(max = 480.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                Text(
                    "Current recorded balance: ${MoneyFormat.format(currentBalanceMinor, currency)}",
                    style = MaterialTheme.typography.bodyMedium,
                )
                MizaniAmountField(
                    value = targetText,
                    onValueChange = { targetText = it },
                    label = if (wallet.type == WalletType.DEBT) "Amount you currently owe" else "Balance shown by MoMo or your provider",
                    currency = currency,
                )
                when {
                    targetText.isBlank() -> Text(
                        stringResource(R.string.ui_89f4035a51),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    targetAmount == null -> Text(
                        "Enter a valid amount in ${currency.code}.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    adjustment == null -> Text(
                        stringResource(R.string.ui_965d15a2ef),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    adjustment == 0L -> Text(
                        stringResource(R.string.ui_8b7cb344fc),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    else -> Text(
                        "Adjustment to record: ${MoneyFormat.format(adjustment, currency)}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (adjustment < 0L) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                    )
                }
                Text(
                    stringResource(R.string.ui_fcc2fa5f80),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (error != null) {
                    Text(error, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = adjustment != null && adjustment != 0L && !saving,
                onClick = { targetBalance?.let(onConfirm) },
            ) {
                Text(if (saving) "Saving…" else "Record adjustment")
            }
        },
        dismissButton = {
            TextButton(enabled = !saving, onClick = onDismiss) { Text(stringResource(R.string.ui_77dfd2135f)) }
        },
    )
}

@Composable
private fun ColorDot(hex: String, selected: Boolean, index: Int, onClick: () -> Unit) {
    Box(
        // 48dp touch target; the visible swatch keeps its original size.
        modifier = Modifier
            .size(48.dp)
            .clip(CircleShape)
            .selectable(
                selected = selected,
                onClick = onClick,
                role = Role.Button,
            )
            // TalkBack needs a name and selection state; colour alone is not accessible.
            .semantics { contentDescription = "Colour option ${index + 1}" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(parseHexColor(hex)),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) {
                Box(Modifier.size(12.dp).clip(CircleShape).background(Color.White))
            }
        }
    }
}
