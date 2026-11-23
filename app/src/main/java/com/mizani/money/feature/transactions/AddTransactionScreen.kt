package com.mizani.money.feature.transactions

import com.mizani.money.UiStr
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.mizani.money.R
import com.mizani.money.core.model.CategoryType
import com.mizani.money.core.model.Ids
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.model.WalletType
import com.mizani.money.core.importing.ImportedTransactionCandidate
import com.mizani.money.core.importing.TransactionMessageParser
import com.mizani.money.core.money.CurrencyConversion
import com.mizani.money.core.money.Currencies
import com.mizani.money.core.money.MoneyFormat
import com.mizani.money.core.time.DateText
import com.mizani.money.data.local.CategoryEntity
import com.mizani.money.data.repo.ExchangeRate
import com.mizani.money.data.repo.ExchangeRateUnavailableException
import com.mizani.money.data.repo.TransactionDraft
import com.mizani.money.ui.AppUiState
import com.mizani.money.ui.AppViewModel
import com.mizani.money.ui.components.DateField
import com.mizani.money.ui.components.EmptyState
import com.mizani.money.ui.components.MizaniCelebration
import com.mizani.money.ui.components.MizaniAmountField
import com.mizani.money.ui.components.MizaniConfirmDialog
import com.mizani.money.ui.components.MizaniCurrencyPicker
import com.mizani.money.ui.components.MizaniIcons
import com.mizani.money.ui.components.MizaniInfoButton
import com.mizani.money.ui.components.MizaniPicker
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.PickerOption
import com.mizani.money.ui.components.Spacing
import com.mizani.money.ui.components.StatusBanner
import com.mizani.money.ui.components.WalletAvatar
import com.mizani.money.ui.components.parseHexColor
import com.mizani.money.ui.theme.LocalMizaniThemeTokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AddTransactionScreen(
    vm: AppViewModel,
    state: AppUiState,
    initialTransactionId: String?,
    initialType: TransactionType = TransactionType.EXPENSE,
    importCandidate: ImportedTransactionCandidate? = null,
    onDone: () -> Unit,
    onBack: () -> Unit,
) {
    val themeTokens = LocalMizaniThemeTokens.current
    val today by vm.today.collectAsStateWithLifecycle()
    val snapshot = state.snapshot
    val currency = state.currency
    val importProviderLabel = importCandidate?.let {
        TransactionMessageParser.providerLabel(it.provider)
    }
    val existing = remember(initialTransactionId, snapshot.transactions) {
        initialTransactionId?.let { id -> snapshot.transactions.firstOrNull { it.id == id } }
    }
    val scope = rememberCoroutineScope()
    val balances = remember(snapshot) { snapshot.walletBalancesOrNull() }
    val wallets = snapshot.activeWallets.ifEmpty { snapshot.wallets }

    var type by rememberSaveable(existing?.id, initialType, importCandidate?.reference) {
        mutableStateOf(existing?.type ?: importCandidate?.type ?: initialType)
    }
    var entryCurrencyCode by rememberSaveable(existing?.id, importCandidate?.reference, currency.code) {
        mutableStateOf(
            existing?.takeIf { it.type == TransactionType.EXPENSE || it.type == TransactionType.INCOME }
                ?.sourceCurrencyCode ?: importCandidate?.currencyCode ?: currency.code,
        )
    }
    var rateRefreshToken by remember(existing?.id) { mutableStateOf(0) }
    var exchangeRate by remember(existing?.id) {
        mutableStateOf(
            existing?.let { transaction ->
                val savedDate = transaction.exchangeRateDate?.let { value ->
                    runCatching { LocalDate.parse(value) }.getOrNull()
                }
                val savedRate = transaction.exchangeRate
                val sourceCode = transaction.sourceCurrencyCode
                if (savedDate != null && savedRate != null && sourceCode != null) {
                    ExchangeRate(sourceCode, currency.code, savedRate, savedDate)
                } else null
            },
        )
    }
    var isRateLoading by remember(existing?.id) { mutableStateOf(false) }
    var isRateRefreshing by remember(existing?.id) { mutableStateOf(false) }
    var rateError by remember(existing?.id) { mutableStateOf<String?>(null) }
    var amountText by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(existing?.let {
            val hasForeignAmount = (it.type == TransactionType.EXPENSE || it.type == TransactionType.INCOME) &&
                it.sourceAmountMinor != null && it.sourceCurrencyCode != null
            MoneyFormat.toInput(
                kotlin.math.abs(if (hasForeignAmount) it.sourceAmountMinor!! else it.amountMinor),
                Currencies.byCode(if (hasForeignAmount) it.sourceCurrencyCode!! else currency.code),
            )
        } ?: importCandidate?.let { MoneyFormat.toInput(it.amountMinor, Currencies.byCode(it.currencyCode)) }.orEmpty())
    }
    var feeText by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(existing?.let {
            val hasForeignAmount = (it.type == TransactionType.EXPENSE || it.type == TransactionType.INCOME) &&
                it.sourceAmountMinor != null && it.sourceCurrencyCode != null
            val sourceCurrency = Currencies.byCode(if (hasForeignAmount) it.sourceCurrencyCode!! else currency.code)
            val sourceFee = if (hasForeignAmount) it.sourceFeeMinor ?: 0L else it.feeMinor
            if (sourceFee > 0) MoneyFormat.toInput(sourceFee, sourceCurrency) else ""
        } ?: importCandidate?.takeIf { it.feeMinor > 0L }
            ?.let { MoneyFormat.toInput(it.feeMinor, Currencies.byCode(it.currencyCode)) }.orEmpty())
    }
    var walletId by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(
            existing?.walletId ?: importCandidate?.let { candidate ->
                wallets.firstOrNull { wallet ->
                    wallet.type == WalletType.MOBILE_MONEY && when (candidate.provider) {
                        "mtn_momo" -> wallet.name.contains("mtn", ignoreCase = true) || wallet.name.contains("momo", ignoreCase = true)
                        "airtel_money" -> wallet.name.contains("airtel", ignoreCase = true)
                        else -> false
                    }
                }?.id ?: wallets.firstOrNull { it.type == WalletType.MOBILE_MONEY }?.id
            } ?: wallets.firstOrNull()?.id,
        )
    }
    var toWalletId by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(existing?.toWalletId ?: wallets.firstOrNull { it.id != walletId }?.id)
    }
    var categoryId by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(
            when {
                existing?.categoryId != null -> existing.categoryId
                // An incoming message does not prove whether the money is salary,
                // a transfer, a reimbursement or a gift. Require an explicit choice
                // during import review instead of silently assigning the first income.
                importCandidate?.type == TransactionType.INCOME -> null
                else -> snapshot.transactions.firstOrNull {
                    it.type == if (type == TransactionType.INCOME) TransactionType.INCOME else TransactionType.EXPENSE
                }?.categoryId ?: snapshot.activeCategories.firstOrNull {
                    it.type == if (type == TransactionType.INCOME) CategoryType.INCOME else CategoryType.EXPENSE
                }?.id
            },
        )
    }
    var incomeSourceId by rememberSaveable(existing?.id) { mutableStateOf(existing?.incomeSourceId) }
    var linkedTransactionId by rememberSaveable(existing?.id) { mutableStateOf(existing?.linkedTransactionId) }
    var adjustmentNegative by rememberSaveable(existing?.id) {
        mutableStateOf((existing?.amountMinor ?: 0L) < 0)
    }
    var date by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(
            existing?.let { LocalDate.ofEpochDay(it.localDateEpochDay) }
                ?: importCandidate?.date ?: today,
        )
    }
    var payee by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(existing?.payee ?: importCandidate?.payee.orEmpty())
    }
    var note by rememberSaveable(existing?.id) { mutableStateOf(existing?.note ?: "") }
    var showMore by rememberSaveable(existing?.id, importCandidate?.reference) {
        mutableStateOf(
            existing?.let {
                it.note.isNotBlank() || it.payee.isNotBlank() || it.feeMinor > 0 ||
                    it.incomeSourceId != null || it.linkedTransactionId != null
            } ?: (importCandidate?.payee?.isNotBlank() == true || importCandidate?.feeMinor?.let { it > 0L } == true),
        )
    }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var showCelebration by remember { mutableStateOf(false) }
    // Advanced types stay collapsed; reveal them only on demand, or when editing one.
    var showAdvancedTypes by rememberSaveable(existing?.id) {
        mutableStateOf(
            existing?.type == TransactionType.REFUND || existing?.type == TransactionType.ADJUSTMENT,
        )
    }

    val canEnterForeignCurrency = type == TransactionType.EXPENSE || type == TransactionType.INCOME
    val entryCurrency = if (canEnterForeignCurrency) Currencies.byCode(entryCurrencyCode) else currency
    val isForeignCurrency = canEnterForeignCurrency && entryCurrency.code != currency.code

    LaunchedEffect(entryCurrency.code, currency.code, canEnterForeignCurrency, existing?.id, rateRefreshToken) {
        if (!isForeignCurrency) {
            exchangeRate = null
            rateError = null
            isRateLoading = false
            isRateRefreshing = false
            return@LaunchedEffect
        }

        val savedRate = existing?.takeIf {
            rateRefreshToken == 0 && it.sourceCurrencyCode == entryCurrency.code &&
                it.exchangeRate != null && it.exchangeRateDate != null
        }?.let { transaction ->
            runCatching {
                ExchangeRate(
                    transaction.sourceCurrencyCode!!,
                    currency.code,
                    transaction.exchangeRate!!,
                    LocalDate.parse(transaction.exchangeRateDate!!),
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
        isRateRefreshing = false
        try {
            // Show a saved observation immediately. Refresh in the background so weak or
            // unavailable connectivity does not make a cached conversion unusable.
            exchangeRate = vm.exchangeRates.cachedRate(entryCurrency.code, currency.code)
            isRateLoading = exchangeRate == null
            val shouldRefresh = rateRefreshToken > 0 ||
                vm.exchangeRates.shouldRefresh(entryCurrency.code, currency.code)
            if (shouldRefresh) {
                isRateRefreshing = true
                try {
                    exchangeRate = vm.exchangeRates.refreshRate(entryCurrency.code, currency.code)
                    rateError = null
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    rateError = rateFailureMessage(failure, hasCachedRate = exchangeRate != null)
                }
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            rateError = rateFailureMessage(failure, hasCachedRate = exchangeRate != null)
        } finally {
            isRateLoading = false
            isRateRefreshing = false
        }
    }

    val categoryType = if (type == TransactionType.INCOME) CategoryType.INCOME else CategoryType.EXPENSE
    val categories = remember(snapshot.categories, type) {
        snapshot.activeCategories.filter { it.type == categoryType }
    }
    val recentCategoryIds = remember(snapshot.transactions, type) {
        snapshot.transactions
            .asSequence()
            .filter { it.type == type || (type == TransactionType.REFUND && it.type == TransactionType.EXPENSE) }
            .mapNotNull { it.categoryId }
            .distinct()
            .take(6)
            .toList()
    }
    val orderedCategories = remember(categories, recentCategoryIds) {
        val recent = recentCategoryIds.mapNotNull { id -> categories.firstOrNull { it.id == id } }
        recent + categories.filterNot { it.id in recentCategoryIds }
    }
    val recentExpenses = remember(snapshot.transactions) {
        snapshot.transactions
            .filter { it.type == TransactionType.EXPENSE }
            .take(20)
    }

    val selectedCategory = categories.firstOrNull { it.id == categoryId }
    val enteredAmountMinor = MoneyFormat.parse(amountText, entryCurrency) ?: 0L
    val enteredFeeMinor = if (feeText.isBlank()) 0L else (MoneyFormat.parse(feeText, entryCurrency) ?: 0L)
    val validFee = feeText.isBlank() || MoneyFormat.parse(feeText, entryCurrency) != null
    val conversionRate = exchangeRate?.takeIf {
        it.baseCurrencyCode == entryCurrency.code && it.quoteCurrencyCode == currency.code
    }
    fun toWorkspaceMinor(amount: Long): Long? {
        if (!isForeignCurrency) return amount
        val rate = conversionRate?.rate?.toBigDecimalOrNull() ?: return null
        return runCatching { CurrencyConversion.convertMinorUnits(amount, entryCurrency, currency, rate) }
            .getOrNull()
    }
    val convertedAmountMinor = toWorkspaceMinor(enteredAmountMinor)
    val convertedFeeMinor = toWorkspaceMinor(enteredFeeMinor)
    val amountMinor = convertedAmountMinor ?: 0L
    val feeMinor = convertedFeeMinor ?: 0L

    fun save() {
        if (saving) return
        error = null
        if (enteredAmountMinor <= 0) {
            error = UiStr.s(R.string.ui_1e0501b4ad)
            return
        }
        if (isForeignCurrency && conversionRate == null) {
            error = rateError ?: if (isRateLoading) "Getting rate…" else UiStr.s(R.string.ui_154aa2c5d8)
            return
        }
        if (amountMinor <= 0) {
            error = "This amount is too small to record in ${currency.code}"
            return
        }
        if (walletId == null) {
            error = UiStr.s(R.string.ui_9c39244109)
            return
        }
        if (type == TransactionType.TRANSFER) {
            if (toWalletId == null || toWalletId == walletId) {
                error = UiStr.s(R.string.ui_7f3b8fdb01)
                return
            }
        }
        if ((type == TransactionType.EXPENSE || type == TransactionType.REFUND) && categoryId == null) {
            error = UiStr.s(R.string.ui_b91bf5d476)
            return
        }
        if (type == TransactionType.INCOME && importCandidate != null && categoryId == null) {
            error = UiStr.s(R.string.ui_9b284fab69)
            return
        }
        if (!validFee) {
            error = UiStr.s(R.string.ui_06d39a9bc1)
            return
        }
        val draft = TransactionDraft(
            id = existing?.id ?: Ids.newId(),
            type = type,
            amountMinor = if (type == TransactionType.ADJUSTMENT && adjustmentNegative) -amountMinor else amountMinor,
            feeMinor = feeMinor,
            walletId = walletId!!,
            toWalletId = if (type == TransactionType.TRANSFER) toWalletId else null,
            categoryId = if (type == TransactionType.TRANSFER || type == TransactionType.ADJUSTMENT) null else categoryId,
            feeCategoryId = null,
            incomeSourceId = if (type == TransactionType.INCOME) incomeSourceId else null,
            linkedTransactionId = if (type == TransactionType.REFUND) linkedTransactionId else null,
            note = note,
            payee = payee,
            date = date,
            sourceAmountMinor = enteredAmountMinor.takeIf { isForeignCurrency },
            sourceFeeMinor = enteredFeeMinor.takeIf { isForeignCurrency },
            sourceCurrencyCode = entryCurrency.code.takeIf { isForeignCurrency },
            exchangeRate = conversionRate?.rate.takeIf { isForeignCurrency },
            exchangeRateDate = conversionRate?.date?.toString().takeIf { isForeignCurrency },
            sourceProvider = existing?.sourceProvider ?: importCandidate?.provider,
            sourceReference = existing?.sourceReference ?: importCandidate?.reference,
        )
        saving = true
        scope.launch {
            val result = runCatching { vm.finance.saveTransaction(draft) }
            // Room's withTransaction resumes on its TransactionExecutor thread; hop back to the
            // main thread before touching UI state or navigating (popBackStack must be main-thread).
            withContext(Dispatchers.Main) {
                result.onSuccess {
                    // Keep saving = true until the celebration overlay finishes (its
                    // onDone navigates away) so a double-tap cannot save twice.
                    showCelebration = true
                }.onFailure {
                    saving = false
                    error = it.message ?: UiStr.s(R.string.ui_bf34b8810f)
                }
            }
        }
    }

    if (showDelete && existing != null) {
        MizaniConfirmDialog(
            title = UiStr.s(R.string.ui_7bbc0c1f35),
            body = UiStr.s(R.string.ui_70a093ad2b),
            confirmLabel = "Delete",
            dismissLabel = "Keep",
            destructive = true,
            onConfirm = {
                showDelete = false
                scope.launch {
                    val result = runCatching { vm.finance.deleteTransaction(existing.id) }
                    withContext(Dispatchers.Main) {
                        result.onSuccess { onDone() }
                            .onFailure { error = it.message }
                    }
                }
            },
            onDismiss = { showDelete = false },
        )
    }

    Box(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize().imePadding()) {
        MizaniTopBar(
            title = when {
                existing != null -> UiStr.s(R.string.ui_f6bd9c51aa)
                importCandidate != null -> UiStr.s(R.string.ui_36dd171d7a)
                else -> UiStr.s(R.string.ui_87101cf1e6)
            },
            subtitle = if (existing == null) null else DateText.medium(date),
            onBack = onBack,
            actions = {
                if (existing != null) {
                    IconButton(onClick = { showDelete = true }) {
                        Icon(Icons.Rounded.Delete, contentDescription = UiStr.s(R.string.ui_8baf937deb))
                    }
                }
            },
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            if (wallets.isEmpty()) {
                EmptyState(
                    title = UiStr.s(R.string.ui_06cc94f2fe),
                    body = UiStr.s(R.string.ui_ba845b1822),
                    iconRes = R.drawable.ic_ph_wallet,
                    actionLabel = UiStr.s(R.string.ui_e84712fbf4),
                    onAction = onBack,
                )
                return@Column
            }

            val primaryTypes = listOf(
                TransactionType.EXPENSE,
                TransactionType.INCOME,
                TransactionType.TRANSFER,
            )
            val advancedTypes = listOf(TransactionType.REFUND, TransactionType.ADJUSTMENT)
            // The advanced chips always stay visible while one of them is the current type.
            val revealAdvanced =
                showAdvancedTypes || type == TransactionType.REFUND || type == TransactionType.ADJUSTMENT
            val visibleTypes = primaryTypes + (if (revealAdvanced) advancedTypes else emptyList())
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                    maxItemsInEachRow = 3,
                ) {
                    visibleTypes.forEach { option ->
                        val icon = when (option) {
                            TransactionType.EXPENSE -> Icons.Rounded.ArrowUpward
                            TransactionType.INCOME -> Icons.Rounded.ArrowDownward
                            TransactionType.TRANSFER -> Icons.Rounded.SwapHoriz
                            TransactionType.REFUND -> Icons.AutoMirrored.Rounded.Undo
                            TransactionType.ADJUSTMENT -> Icons.Rounded.Tune
                        }
                        FilterChip(
                            selected = type == option,
                            onClick = {
                                type = option
                                if (option != TransactionType.EXPENSE && option != TransactionType.INCOME) {
                                    if (entryCurrency.code != currency.code) {
                                        amountText = amountMinor.takeIf { it > 0L }
                                            ?.let { MoneyFormat.toInput(it, currency) } ?: ""
                                        feeText = feeMinor.takeIf { it > 0L }
                                            ?.let { MoneyFormat.toInput(it, currency) } ?: ""
                                    }
                                    entryCurrencyCode = currency.code
                                }
                                val desiredCategoryType =
                                    if (option == TransactionType.INCOME) CategoryType.INCOME else CategoryType.EXPENSE
                                categoryId = if (option == TransactionType.TRANSFER || option == TransactionType.ADJUSTMENT) {
                                    null
                                } else {
                                    snapshot.activeCategories.firstOrNull { it.type == desiredCategoryType }?.id
                                }
                                error = null
                            },
                            label = { Text(option.label) },
                            leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp)) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            ),
                        )
                    }
                }
                if (type != TransactionType.REFUND && type != TransactionType.ADJUSTMENT) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { showAdvancedTypes = !showAdvancedTypes }) {
                            Text(if (showAdvancedTypes) UiStr.s(R.string.ui_43d919af17) else UiStr.s(R.string.ui_2d8abd82cf))
                            Icon(
                                imageVector = if (showAdvancedTypes) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        MizaniInfoButton(
                            infoTitle = stringResource(R.string.info_transaction_types_title),
                            infoBody = stringResource(R.string.info_transaction_types_body),
                            contentDescription = stringResource(R.string.info_transaction_types_title),
                        )
                    }
                }
            }

            if (importCandidate != null && importProviderLabel != null) {
                Text(
                    "Suggested from $importProviderLabel · Ref ${importCandidate.reference}. Check the details before saving.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (importCandidate?.type == TransactionType.INCOME) {
                Text(
                    UiStr.s(R.string.ui_3f6901b2ea),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (canEnterForeignCurrency) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(UiStr.s(R.string.ui_06b41b740f), style = MaterialTheme.typography.labelLarge)
                    MizaniCurrencyPicker(
                        selectedCode = entryCurrencyCode,
                        onSelect = {
                            entryCurrencyCode = it
                            error = null
                        },
                        fieldLabel = "Transaction currency",
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            val quickAddSteps = if (entryCurrency.minorUnits == 0) {
                listOf(1_000L, 5_000L, 10_000L)
            } else {
                listOf(10L, 50L, 100L).map { it * entryCurrency.scaleFactor }
            }
            val amountWallet = wallets.firstOrNull { it.id == walletId }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(MaterialTheme.shapes.extraLarge)
                    .background(Brush.linearGradient(listOf(themeTokens.heroStart, themeTokens.heroEnd)))
                    .padding(20.dp),
            ) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            when (type) {
                                TransactionType.TRANSFER -> UiStr.s(R.string.ui_f46cf24c23)
                                TransactionType.REFUND -> UiStr.s(R.string.ui_b7a4c981da)
                                TransactionType.ADJUSTMENT -> UiStr.s(R.string.ui_cd0528cc9f)
                                else -> "Amount"
                            },
                            style = MaterialTheme.typography.labelMedium,
                            color = Color.White,
                            modifier = Modifier.weight(1f),
                        )
                        Surface(
                            color = Color.White.copy(alpha = 0.12f),
                            shape = CircleShape,
                        ) {
                            Text(
                                type.label,
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.White,
                                modifier = Modifier.padding(horizontal = Spacing.md, vertical = 4.dp),
                            )
                        }
                    }
                    Spacer(Modifier.height(Spacing.sm))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            entryCurrency.symbol,
                            style = MaterialTheme.typography.titleMedium,
                            color = Color.White,
                        )
                        Spacer(Modifier.width(Spacing.sm))
                        Box(modifier = Modifier.weight(1f)) {
                            if (amountText.isEmpty()) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        "0",
                                        style = MaterialTheme.typography.displayMedium,
                                        color = Color.White.copy(alpha = 0.3f),
                                    )
                                    Spacer(Modifier.weight(1f))
                                    Text(
                                        UiStr.s(R.string.ui_8c9de32d19),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = Color.White,
                                    )
                                }
                            }
                            BasicTextField(
                                value = amountText,
                                onValueChange = { input ->
                                    amountText = input.filter { it.isDigit() || it == '.' || it == ',' }
                                    error = null
                                },
                                textStyle = MaterialTheme.typography.displayMedium.copy(color = Color.White),
                                cursorBrush = SolidColor(themeTokens.heroAccent),
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                singleLine = true,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .semantics { contentDescription = "Amount in ${entryCurrency.name}" },
                            )
                        }
                    }
                    if (enteredAmountMinor > 0) {
                        Text(
                            MoneyFormat.format(enteredAmountMinor, entryCurrency),
                            style = MaterialTheme.typography.labelMedium,
                            color = Color.White,
                        )
                    }
                    if (amountText.isNotBlank() && amountMinor <= 0L) {
                        Text(
                            UiStr.s(R.string.ui_7b38f2ddbd),
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFFFFB4AB),
                            modifier = Modifier.semantics {
                                contentDescription = UiStr.s(R.string.ui_08166ef087)
                            },
                        )
                    }
                    Spacer(Modifier.height(Spacing.xs))
                    Text(
                        "${amountWallet?.name ?: ""} · ${balances?.get(walletId)?.let { MoneyFormat.format(it, currency) } ?: UiStr.s(R.string.ui_ec0e50f398)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White,
                    )
                    if (type == TransactionType.ADJUSTMENT) {
                        Spacer(Modifier.height(Spacing.sm))
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            FilterChip(
                                selected = !adjustmentNegative,
                                onClick = { adjustmentNegative = false },
                                label = { Text(stringResource(R.string.ui_2272167502)) },
                                colors = FilterChipDefaults.filterChipColors(
                                    containerColor = Color.White.copy(alpha = 0.12f),
                                    labelColor = Color.White,
                                    selectedContainerColor = themeTokens.heroAccent,
                                    selectedLabelColor = themeTokens.heroAccentForeground,
                                ),
                            )
                            FilterChip(
                                selected = adjustmentNegative,
                                onClick = { adjustmentNegative = true },
                                label = { Text(stringResource(R.string.ui_633bce5aa9)) },
                                colors = FilterChipDefaults.filterChipColors(
                                    containerColor = Color.White.copy(alpha = 0.12f),
                                    labelColor = Color.White,
                                    selectedContainerColor = themeTokens.heroAccent,
                                    selectedLabelColor = themeTokens.heroAccentForeground,
                                ),
                            )
                        }
                    }
                    Spacer(Modifier.height(Spacing.sm))
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        quickAddSteps.forEach { step ->
                            Surface(
                                color = Color.White.copy(alpha = 0.10f),
                                shape = MaterialTheme.shapes.medium,
                                modifier = Modifier
                                    .clip(MaterialTheme.shapes.medium)
                                    .clickable {
                                        val current = MoneyFormat.parse(amountText, entryCurrency) ?: 0L
                                        amountText = MoneyFormat.toInput(current + step, entryCurrency)
                                        error = null
                                    },
                            ) {
                                Text(
                                    "+${MoneyFormat.formatBare(step, entryCurrency)}",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = Color.White,
                                    modifier = Modifier.padding(horizontal = Spacing.md, vertical = Spacing.sm),
                                )
                            }
                        }
                    }
                }
            }

            if (isForeignCurrency) {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(Spacing.md),
                        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
                    ) {
                        Text("Automatically converted to ${currency.code}", style = MaterialTheme.typography.labelLarge)
                        when {
                            conversionRate != null -> {
                                if (enteredAmountMinor > 0L && amountMinor > 0L) {
                                    Text(
                                        MoneyFormat.format(amountMinor, currency),
                                        style = MaterialTheme.typography.titleMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                } else if (enteredAmountMinor > 0L) {
                                    Text(
                                        "This amount cannot be recorded in ${currency.code}; try a smaller amount.",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                }
                                Text(
                                    "1 ${entryCurrency.code} = ${conversionRate.rate} ${currency.code} · ${DateText.medium(conversionRate.date)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(
                                    UiStr.s(R.string.ui_288e1312d7),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                rateError?.let {
                                    Text(
                                        it,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (isRateRefreshing) {
                                    Text(
                                        UiStr.s(R.string.ui_2817459eb0),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            isRateLoading -> Text(
                                UiStr.s(R.string.ui_4e34edd378),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            else -> {
                                Text(
                                    rateError ?: UiStr.s(R.string.ui_a595471c14),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                                TextButton(onClick = { rateRefreshToken++ }) {
                                    Text(stringResource(R.string.ui_9f5cd8a2e8))
                                }
                            }
                        }
                        if (conversionRate != null) {
                            TextButton(
                                onClick = { rateRefreshToken++ },
                                enabled = !isRateLoading && !isRateRefreshing,
                            ) {
                                Text(stringResource(R.string.ui_ff5449bf5f))
                            }
                        }
                        if (isForeignCurrency && conversionRate != null && feeText.isNotBlank() && validFee && convertedFeeMinor == null) {
                            Text(
                                "This fee exceeds the supported ${currency.code} amount range.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            }

            if (type == TransactionType.TRANSFER) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(UiStr.s(R.string.ui_758d69ffdf), style = MaterialTheme.typography.labelLarge)
                    WalletPickerRow(
                        wallets = wallets,
                        selectedId = walletId,
                        balances = balances,
                        currency = currency,
                        onSelect = { walletId = it },
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(UiStr.s(R.string.ui_4a22284d6d), style = MaterialTheme.typography.labelLarge)
                    WalletPickerRow(
                        wallets = wallets.filter { it.id != walletId },
                        selectedId = toWalletId,
                        balances = balances,
                        currency = currency,
                        onSelect = { toWalletId = it },
                    )
                }
                Text(
                    UiStr.s(R.string.ui_e16fd8819d),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(UiStr.s(R.string.ui_b60862f485), style = MaterialTheme.typography.labelLarge)
                    WalletPickerRow(
                        wallets = wallets,
                        selectedId = walletId,
                        balances = balances,
                        currency = currency,
                        onSelect = { walletId = it },
                    )
                }
            }

            if (type == TransactionType.EXPENSE || type == TransactionType.INCOME || type == TransactionType.REFUND) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (type == TransactionType.INCOME) UiStr.s(R.string.ui_284b0cbfe2) else "Category",
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.weight(1f),
                        )
                        if (recentCategoryIds.isNotEmpty()) {
                            Text(
                                UiStr.s(R.string.ui_f5efd233f4),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (importCandidate?.type == TransactionType.INCOME && categoryId == null) {
                        Text(
                            UiStr.s(R.string.ui_93233d88d0),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    val primaryCategories = orderedCategories.take(9).let { head ->
                        val selected = orderedCategories.firstOrNull { it.id == categoryId }
                        if (selected != null && head.none { it.id == selected.id }) head + selected else head
                    }
                    val primaryIds = primaryCategories.mapTo(mutableSetOf()) { it.id }
                    val extra = orderedCategories.filterNot { it.id in primaryIds }
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                        maxItemsInEachRow = 3,
                    ) {
                        primaryCategories.forEach { category ->
                            CategoryTile(
                                category = category,
                                selected = category.id == categoryId,
                                modifier = Modifier.weight(1f),
                                onClick = {
                                    categoryId = category.id
                                    error = null
                                },
                            )
                        }
                    }
                    if (extra.isNotEmpty()) {
                        var expanded by remember { mutableStateOf(false) }
                        TextButton(onClick = { expanded = !expanded }) {
                            Text(if (expanded) UiStr.s(R.string.ui_488616be7c) else "More categories (${extra.size})")
                        }
                        if (expanded) {
                            FlowRow(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                                maxItemsInEachRow = 3,
                            ) {
                                extra.forEach { category ->
                                    CategoryTile(
                                        category = category,
                                        selected = category.id == categoryId,
                                        modifier = Modifier.weight(1f),
                                        onClick = {
                                            categoryId = category.id
                                            error = null
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }

            DateField(
                label = UiStr.s(R.string.ui_eb9a4bc1c0),
                date = date,
                onDateSelected = { date = it },
                modifier = Modifier.fillMaxWidth(),
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(MaterialTheme.shapes.medium)
                    .clickable { showMore = !showMore }
                    .padding(vertical = Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (showMore) UiStr.s(R.string.ui_f8c2483312) else UiStr.s(R.string.ui_da3042ae0e),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    if (showMore) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                    contentDescription = if (showMore) UiStr.s(R.string.ui_f8c2483312) else UiStr.s(R.string.ui_42c9c9254f),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }

            if (showMore) {
                OutlinedTextField(
                    value = payee,
                    onValueChange = { payee = it },
                    label = { Text(stringResource(R.string.ui_640df0d6b1)) },
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text(stringResource(R.string.ui_4e39567064)) },
                    minLines = 2,
                    maxLines = 4,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
                MizaniAmountField(
                    value = feeText,
                    onValueChange = { input -> feeText = input },
                    label = UiStr.s(R.string.ui_d2bb1510ad),
                    currency = entryCurrency,
                    supportingText = if (isForeignCurrency) {
                        UiStr.s(R.string.ui_b659c23e65)
                    } else {
                        UiStr.s(R.string.ui_112e26a798)
                    },
                )
                if (type == TransactionType.INCOME) {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text(UiStr.s(R.string.ui_db79ac2b85), style = MaterialTheme.typography.labelLarge)
                        MizaniPicker(
                            selectedText = incomeSourceId?.let { snapshot.incomeSourceName(it) } ?: UiStr.s(R.string.ui_60f1e913db),
                            options = snapshot.incomeSources.map { PickerOption(it.id, it.name) },
                            onSelect = { incomeSourceId = it },
                            noneLabel = UiStr.s(R.string.ui_60f1e913db),
                            onSelectNone = { incomeSourceId = null },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                if (type == TransactionType.REFUND) {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text(UiStr.s(R.string.ui_807ceb398f), style = MaterialTheme.typography.labelLarge)
                        val linked = snapshot.transactions.firstOrNull { it.id == linkedTransactionId }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            MizaniPicker(
                                selectedText = linked?.let {
                                    "${it.payee.ifBlank { snapshot.categoryName(it.categoryId) }} · ${MoneyFormat.format(it.amountMinor, currency)} · ${DateText.short(LocalDate.ofEpochDay(it.localDateEpochDay))}"
                                } ?: UiStr.s(R.string.ui_53facfdcdb),
                                options = recentExpenses.map { expense ->
                                    PickerOption(
                                        id = expense.id,
                                        label = "${expense.payee.ifBlank { snapshot.categoryName(expense.categoryId) }} · ${MoneyFormat.format(expense.amountMinor, currency)} · ${DateText.short(LocalDate.ofEpochDay(expense.localDateEpochDay))}",
                                    )
                                },
                                onSelect = { id ->
                                    recentExpenses.firstOrNull { it.id == id }?.let { expense ->
                                        linkedTransactionId = expense.id
                                        categoryId = expense.categoryId
                                    }
                                },
                                modifier = Modifier.weight(1f),
                            )
                            if (linkedTransactionId != null) {
                                IconButton(onClick = { linkedTransactionId = null; categoryId = null }) {
                                    Icon(Icons.Rounded.Close, contentDescription = UiStr.s(R.string.ui_74db12659f))
                                }
                            }
                        }
                        Text(
                            UiStr.s(R.string.ui_35feba6e74),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            if (error != null) {
                StatusBanner(text = error!!, isError = true)
            }
            Spacer(Modifier.height(Spacing.lg))
        }

        Surface(
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 2.dp,
        ) {
            Column {
                HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
                Column(Modifier.padding(16.dp)) {
                    Text(
                        UiStr.s(R.string.ui_71dd77aa9f),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(Spacing.sm))
                    Button(
                        onClick = ::save,
                        enabled = !saving && amountMinor > 0 && (!isForeignCurrency || (
                            !isRateLoading && conversionRate != null && convertedFeeMinor != null
                        )),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        Text(
                            when {
                                saving -> "Saving…"
                                existing != null -> UiStr.s(R.string.ui_179359b39e)
                                type == TransactionType.TRANSFER -> UiStr.s(R.string.ui_9324b64839)
                                type == TransactionType.INCOME -> UiStr.s(R.string.ui_9c4d5fdea4)
                                type == TransactionType.REFUND -> UiStr.s(R.string.ui_34e5c4efc5)
                                type == TransactionType.ADJUSTMENT -> UiStr.s(R.string.ui_818a86d779)
                                else -> UiStr.s(R.string.ui_0402d1095c)
                            },
                        )
                    }
                }
            }
        }
    }

        if (showCelebration) {
            MizaniCelebration(onFinished = { showCelebration = false; onDone() })
        }
    }
}

private fun rateFailureMessage(error: Exception, hasCachedRate: Boolean): String = when {
    hasCachedRate -> UiStr.s(R.string.ui_cd0fdac9da)
    error is ExchangeRateUnavailableException -> UiStr.s(R.string.ui_fed145a04c)
    else -> UiStr.s(R.string.ui_3f2da1e44b)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WalletPickerRow(
    wallets: List<com.mizani.money.data.local.WalletEntity>,
    selectedId: String?,
    balances: Map<String, Long>?,
    currency: com.mizani.money.core.money.Currency,
    onSelect: (String) -> Unit,
) {
    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val itemWidth = if (wallets.size == 1) maxWidth else (maxWidth - Spacing.sm) / 2
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            maxItemsInEachRow = 2,
        ) {
            wallets.forEach { wallet ->
                val selected = wallet.id == selectedId
                Surface(
                    modifier = Modifier
                        .width(itemWidth)
                        .heightIn(min = Spacing.fieldHeight)
                        .clip(MaterialTheme.shapes.medium)
                        .border(
                            width = 1.dp,
                            color = if (selected) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outline,
                            shape = MaterialTheme.shapes.medium,
                        )
                        .clickable { onSelect(wallet.id) },
                    color = if (selected) MaterialTheme.colorScheme.primaryContainer
                    else MaterialTheme.colorScheme.surfaceContainerLowest,
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = Spacing.md, vertical = Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        WalletAvatar(wallet.type, wallet.colorHex, size = 32)
                        Spacer(Modifier.width(Spacing.sm))
                        Column {
                            Text(wallet.name, style = MaterialTheme.typography.labelLarge, maxLines = 1)
                            Text(
                                balances?.get(wallet.id)?.let { MoneyFormat.format(it, currency) } ?: "—",
                                style = MaterialTheme.typography.labelSmall,
                                color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.75f)
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CategoryTile(
    category: CategoryEntity,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val color = parseHexColor(category.colorHex)
    Column(
        modifier = modifier
            .heightIn(min = 76.dp)
            .clip(MaterialTheme.shapes.medium)
            .background(
                if (selected) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surfaceContainerLowest,
            )
            .border(
                width = 1.dp,
                color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.sm, vertical = Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(30.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                MizaniIcons.category(category.icon),
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(17.dp),
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            category.name,
            style = MaterialTheme.typography.labelSmall,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}
