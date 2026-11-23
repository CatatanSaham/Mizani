package com.mizani.money.feature.settings

import com.mizani.money.UiStr
import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings as AndroidSettings
import android.app.TimePickerDialog
import android.graphics.Color as AndroidColor
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.core.content.ContextCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Backup
import androidx.compose.material.icons.rounded.DeleteForever
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Fingerprint
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.Security
import com.mizani.money.ui.components.MizaniAlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.mizani.money.core.model.CountryPacks
import com.mizani.money.core.model.ColorTheme
import com.mizani.money.core.model.DarkThemeStyle
import com.mizani.money.core.model.ThemeMode
import com.mizani.money.R
import com.mizani.money.core.time.DateText
import com.mizani.money.core.time.DailyReminderSchedule
import com.mizani.money.domain.export.BackupSummary
import com.mizani.money.domain.export.BackupFileReader
import com.mizani.money.feature.lock.PinSetupDialog
import com.mizani.money.feature.lock.PinVerifyDialog
import com.mizani.money.feature.lock.SensitiveActionConfirmationDialog
import com.mizani.money.ui.AppUiState
import com.mizani.money.ui.AppViewModel
import com.mizani.money.ui.PIN_RETRY_MESSAGE
import com.mizani.money.ui.components.MizaniCard
import com.mizani.money.ui.components.MizaniConfirmDialog
import com.mizani.money.ui.components.MizaniInfoRow
import com.mizani.money.ui.components.MizaniInfoButton
import com.mizani.money.ui.components.MizaniPicker
import com.mizani.money.ui.components.MizaniSectionCard
import com.mizani.money.ui.components.MizaniSectionDivider
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.PickerOption
import com.mizani.money.ui.components.SectionHeader
import com.mizani.money.ui.components.Spacing
import com.mizani.money.ui.components.StatusBanner
import com.mizani.money.ui.theme.colorThemePreviewColor
import com.mizani.money.reminder.DailyReminderNotifications
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

private enum class SensitiveDataAction(val description: String) {
    CSV_EXPORT("export transactions as a CSV file"),
    EXCEL_EXPORT("export an Excel workbook"),
    ENCRYPTED_BACKUP("create an encrypted backup"),
}

@Composable
fun SettingsScreen(
    vm: AppViewModel,
    state: AppUiState,
    onBack: () -> Unit,
    dataToolsOnly: Boolean = false,
    highlightAppLock: Boolean = false,
) {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val scope = rememberCoroutineScope()
    val settings = state.settings
    val reminderScheduleError = stringResource(R.string.settings_reminder_schedule_error)
    val reminderPermissionDenied = stringResource(R.string.settings_reminder_permission_denied)
    val reminderNotificationsDisabled = stringResource(R.string.settings_reminder_notifications_disabled)
    val reminderTestSent = stringResource(R.string.settings_reminder_test_sent)
    val reminderTestLabel = stringResource(R.string.settings_send_test_reminder)
    val dailyReminderTitle = stringResource(R.string.settings_daily_reminder_title)
    val habitNotificationTitle = stringResource(R.string.settings_habit_notifications_title)

    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingSensitiveAction by remember { mutableStateOf<SensitiveDataAction?>(null) }
    var showSensitiveActionConfirmation by remember { mutableStateOf(false) }
    var showPinRequiredForSensitiveAction by remember { mutableStateOf(false) }
    var settingUpPinForSensitiveAction by remember { mutableStateOf(false) }
    var showPinSetup by remember { mutableStateOf(false) }
    var showDisablePin by remember { mutableStateOf(false) }
    var showVerifyForChange by remember { mutableStateOf(false) }
    var showCountryDialog by remember { mutableStateOf(false) }
    var showAccentColorPicker by rememberSaveable { mutableStateOf(false) }
    var showCsvWarning by remember { mutableStateOf(false) }
    var showExcelWarning by remember { mutableStateOf(false) }
    var showBackupPassphrase by remember { mutableStateOf(false) }
    var showRestorePassphrase by remember { mutableStateOf(false) }
    var showRestoreConfirm by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var backupPassphrase by remember { mutableStateOf("") }
    var backupPassphraseConfirm by remember { mutableStateOf("") }
    var pendingBackupPassphrase by remember { mutableStateOf("") }
    var restorePassphrase by remember { mutableStateOf("") }
    var pendingRestoreBytes by remember { mutableStateOf<ByteArray?>(null) }
    var pendingSummary by remember { mutableStateOf<BackupSummary?>(null) }
    var creatingBackup by remember { mutableStateOf(false) }
    var checkingBackup by remember { mutableStateOf(false) }
    var restoringBackup by remember { mutableStateOf(false) }
    var reminderStatus by rememberSaveable { mutableStateOf<String?>(null) }
    var habitStatus by rememberSaveable { mutableStateOf<String?>(null) }
    var showReminderNotificationSettings by rememberSaveable { mutableStateOf(false) }
    var notificationSettingsRevision by remember { mutableStateOf(0) }
    var pendingNotificationEnable by rememberSaveable { mutableStateOf("daily") }

    fun requestSensitiveAction(action: SensitiveDataAction) {
        error = null
        if (!settings.hasPin) {
            showPinRequiredForSensitiveAction = true
            return
        }
        pendingSensitiveAction = action
        showSensitiveActionConfirmation = true
    }

    fun clearSensitiveActionConfirmation() {
        showSensitiveActionConfirmation = false
        pendingSensitiveAction = null
    }

    fun authorizeSensitiveAction() {
        val action = pendingSensitiveAction
        clearSensitiveActionConfirmation()
        when (action) {
            SensitiveDataAction.CSV_EXPORT -> showCsvWarning = true
            SensitiveDataAction.EXCEL_EXPORT -> showExcelWarning = true
            SensitiveDataAction.ENCRYPTED_BACKUP -> showBackupPassphrase = true
            null -> Unit
        }
    }

    fun discardBackupPassphrase() {
        showBackupPassphrase = false
        backupPassphrase = ""
        backupPassphraseConfirm = ""
        pendingBackupPassphrase = ""
    }

    fun discardPendingRestore() {
        showRestorePassphrase = false
        showRestoreConfirm = false
        restorePassphrase = ""
        pendingRestoreBytes = null
        pendingSummary = null
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) notificationSettingsRevision += 1
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    DisposableEffect(Unit) {
        onDispose {
            pendingRestoreBytes?.fill(0)
            backupPassphrase = ""
            backupPassphraseConfirm = ""
            pendingBackupPassphrase = ""
            restorePassphrase = ""
        }
    }
    val notificationsAvailable = remember(notificationSettingsRevision) {
        DailyReminderNotifications.canPost(context)
    }

    val enableDailyReminder: () -> Unit = {
        scope.launch {
            vm.setDailyReminderEnabled(true)
                .onSuccess {
                    reminderStatus = null
                    showReminderNotificationSettings = false
                }
                .onFailure {
                    reminderStatus = reminderScheduleError
                }
        }
    }
    val enableHabitNotifications: () -> Unit = {
        scope.launch {
            vm.setHabitNotificationsEnabled(true)
                .onSuccess {
                    habitStatus = null
                    showReminderNotificationSettings = false
                }
                .onFailure {
                    habitStatus = reminderScheduleError
                }
        }
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        notificationSettingsRevision += 1
        if (granted) {
            if (pendingNotificationEnable == "habit") enableHabitNotifications()
            else enableDailyReminder()
        } else {
            if (pendingNotificationEnable == "habit") habitStatus = reminderPermissionDenied
            else reminderStatus = reminderPermissionDenied
            showReminderNotificationSettings = true
        }
    }
    val openReminderNotificationSettings: () -> Unit = {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(AndroidSettings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(
                AndroidSettings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            )
        }
        runCatching { context.startActivity(intent) }
    }
    val requestDailyReminderNotificationAccess: () -> Unit = {
        pendingNotificationEnable = "daily"
        reminderStatus = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            openReminderNotificationSettings()
        }
    }
    val onDailyReminderChanged: (Boolean) -> Unit = { enabled ->
        pendingNotificationEnable = "daily"
        reminderStatus = null
        showReminderNotificationSettings = false
        if (!enabled) {
            scope.launch {
                vm.setDailyReminderEnabled(false)
                    .onFailure { reminderStatus = reminderScheduleError }
            }
        } else {
            DailyReminderNotifications.ensureChannel(context)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else if (!DailyReminderNotifications.canPost(context)) {
                reminderStatus = reminderNotificationsDisabled
                showReminderNotificationSettings = true
            } else {
                enableDailyReminder()
            }
        }
    }
    val onHabitNotificationsChanged: (Boolean) -> Unit = { enabled ->
        pendingNotificationEnable = "habit"
        habitStatus = null
        showReminderNotificationSettings = false
        if (!enabled) {
            scope.launch {
                vm.setHabitNotificationsEnabled(false)
                    .onFailure { habitStatus = reminderScheduleError }
            }
        } else {
            DailyReminderNotifications.ensureChannel(context)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else if (!DailyReminderNotifications.canPost(context)) {
                habitStatus = reminderNotificationsDisabled
                showReminderNotificationSettings = true
            } else {
                enableHabitNotifications()
            }
        }
    }

    val canBiometric = remember {
        BiometricManager.from(context)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
            BiometricManager.BIOMETRIC_SUCCESS
    }

    val createCsv = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri ->
        if (uri != null) {
            scope.launch {
                runCatching {
                    val csv = withContext(Dispatchers.IO) { vm.exporter.buildCsv() }
                    writeBytes(context, uri, csv.toByteArray(Charsets.UTF_8))
                }.onSuccess {
                    message = UiStr.s(R.string.ui_550302309f)
                    error = null
                }.onFailure {
                    error = it.message ?: "Could not write the CSV"
                }
            }
        }
    }

    val createExcel = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    ) { uri ->
        if (uri != null) {
            scope.launch {
                runCatching {
                    withContext(Dispatchers.IO) {
                        context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                            vm.exporter.writeExcel(output)
                        } ?: throw IOException("Could not open the selected file for writing")
                    }
                }.onSuccess {
                    message = UiStr.s(R.string.ui_56c4e5c4bd)
                    error = null
                }.onFailure {
                    error = it.message ?: "Could not create the Excel workbook"
                }
            }
        }
    }

    val createBackup = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream"),
    ) { uri ->
        val passphrase = pendingBackupPassphrase
        pendingBackupPassphrase = ""
        if (uri == null) {
            backupPassphrase = ""
            backupPassphraseConfirm = ""
        } else {
            backupPassphrase = ""
            backupPassphraseConfirm = ""
            scope.launch {
                creatingBackup = true
                message = UiStr.s(R.string.ui_19d4048ffb)
                try {
                    runCatching {
                        if (passphrase.isBlank()) throw IOException("The passphrase was cleared. Please try again.")
                        val bytes = vm.exporter.buildBackup(passphrase)
                        writeBytes(context, uri, bytes)
                    }.onSuccess {
                        message = UiStr.s(R.string.ui_b94f2c706c)
                        error = null
                    }.onFailure {
                        message = null
                        error = it.message ?: "Could not create the backup"
                    }
                } finally {
                    creatingBackup = false
                }
            }
        }
    }

    val openRestore = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri != null) {
            scope.launch {
                runCatching {
                    withContext(Dispatchers.IO) {
                        context.contentResolver.openInputStream(uri)?.use { BackupFileReader.read(it) }
                            ?: throw IOException("Could not open the selected file")
                    }
                }.onSuccess { bytes ->
                    pendingRestoreBytes = bytes
                    restorePassphrase = ""
                    showRestorePassphrase = true
                    error = null
                }.onFailure {
                    discardPendingRestore()
                    error = it.message ?: "Could not read the selected file"
                }
            }
        }
    }

    if (showSensitiveActionConfirmation) {
        val action = pendingSensitiveAction
        if (action != null) {
            SensitiveActionConfirmationDialog(
                actionDescription = action.description,
                allowBiometrics = settings.biometricEnabled && canBiometric,
                verifyPin = { pin -> vm.settingsRepository.verifyPin(pin) },
                pinBackoffRemainingMs = { vm.settingsRepository.pinBackoffRemainingMs() },
                onAuthorized = ::authorizeSensitiveAction,
                onDismiss = ::clearSensitiveActionConfirmation,
            )
        }
    }

    if (showPinRequiredForSensitiveAction) {
        MizaniAlertDialog(
            onDismissRequest = { showPinRequiredForSensitiveAction = false },
            shape = MaterialTheme.shapes.large,
            title = { Text(stringResource(R.string.ui_e83ca02ac6)) },
            text = {
                Text(
                    "A 6-digit app PIN is required to confirm exports and encrypted backup creation. " +
                        "Setting one up also turns on app lock when you reopen Mizani. " +
                        "After setup, choose the action again and confirm with your PIN or enabled biometrics.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showPinRequiredForSensitiveAction = false
                    settingUpPinForSensitiveAction = true
                    showPinSetup = true
                }) { Text(stringResource(R.string.ui_fdcdb9c6b8)) }
            },
            dismissButton = {
                TextButton(onClick = { showPinRequiredForSensitiveAction = false }) { Text(stringResource(R.string.ui_77dfd2135f)) }
            },
        )
    }

    if (showPinSetup) {
        PinSetupDialog(
            onDismiss = {
                showPinSetup = false
                settingUpPinForSensitiveAction = false
            },
            onConfirm = { pin ->
                scope.launch {
                    // enableLock returns a Result rather than throwing, so handle it directly:
                    // wrapping it in runCatching would report failures as success.
                    vm.enableLock(pin)
                        .onSuccess {
                            showPinSetup = false
                            message = if (settingUpPinForSensitiveAction) {
                                "PIN set up. Choose the export or backup again and confirm your identity."
                            } else {
                                "App lock is on."
                            }
                            settingUpPinForSensitiveAction = false
                            error = null
                        }
                        .onFailure {
                            // Close the dialog so the banner behind it is visible, and keep the
                            // message user-safe (no raw exception details).
                            showPinSetup = false
                            settingUpPinForSensitiveAction = false
                            error = "App lock could not be turned on. Your data is unchanged — try again."
                        }
                }
            },
        )
    }

    if (showDisablePin) {
        PinVerifyDialog(
            title = UiStr.s(R.string.ui_322eafd991),
            onDismiss = { showDisablePin = false },
            onSubmit = { pin ->
                scope.launch {
                    // verifyPin enforces the same persisted failed-attempt
                    // backoff as the lock screen: while blocked it refuses the
                    // attempt without hashing, so this path cannot be used to
                    // keep guessing either.
                    val ok = vm.settingsRepository.verifyPin(pin)
                    showDisablePin = false
                    if (ok) {
                        vm.disableLock()
                        message = UiStr.s(R.string.ui_de90f01c15)
                        error = null
                    } else if (vm.settingsRepository.pinBackoffRemainingMs() > 0L) {
                        error = PIN_RETRY_MESSAGE
                    } else {
                        error = "Incorrect PIN"
                    }
                }
            },
        )
    }

    if (showVerifyForChange) {
        PinVerifyDialog(
            title = UiStr.s(R.string.ui_fe0cd5b5c5),
            onDismiss = { showVerifyForChange = false },
            onSubmit = { pin ->
                scope.launch {
                    val ok = vm.settingsRepository.verifyPin(pin)
                    showVerifyForChange = false
                    when {
                        ok -> showPinSetup = true
                        vm.settingsRepository.pinBackoffRemainingMs() > 0L -> error = PIN_RETRY_MESSAGE
                        else -> error = "Incorrect PIN"
                    }
                }
            },
        )
    }

    if (showCountryDialog) {
        CountryCurrencyDialog(
            initialCountry = settings.countryCode,
            workspaceCurrency = state.snapshot.currencyCode,
            onDismiss = { showCountryDialog = false },
            onSave = { countryCode ->
                scope.launch {
                    runCatching { vm.setCountry(countryCode, state.snapshot.currencyCode) }
                        .onSuccess {
                            showCountryDialog = false
                            message = UiStr.s(R.string.ui_86ece351bb)
                            error = null
                        }
                        .onFailure { error = it.message ?: "Could not update your region. Try again." }
                }
            },
        )
    }

    if (showCsvWarning) {
        MizaniAlertDialog(
            onDismissRequest = { showCsvWarning = false },
            shape = MaterialTheme.shapes.large,
            title = { Text(stringResource(R.string.ui_4570ffb20f)) },
            text = {
                Text(stringResource(R.string.ui_ed9b4f36a8))
            },
            confirmButton = {
                TextButton(onClick = {
                    showCsvWarning = false
                    createCsv.launch(vm.exporter.suggestedCsvName())
                }) { Text(stringResource(R.string.ui_eb7eb7a819)) }
            },
            dismissButton = { TextButton(onClick = { showCsvWarning = false }) { Text(stringResource(R.string.ui_77dfd2135f)) } },
        )
    }

    if (showExcelWarning) {
        MizaniAlertDialog(
            onDismissRequest = { showExcelWarning = false },
            shape = MaterialTheme.shapes.large,
            title = { Text(stringResource(R.string.ui_3d7a236365)) },
            text = {
                Text(stringResource(R.string.ui_56120d2372))
            },
            confirmButton = {
                TextButton(onClick = {
                    showExcelWarning = false
                    createExcel.launch(vm.exporter.suggestedExcelName())
                }) { Text(stringResource(R.string.ui_eb7eb7a819)) }
            },
            dismissButton = { TextButton(onClick = { showExcelWarning = false }) { Text(stringResource(R.string.ui_77dfd2135f)) } },
        )
    }

    if (showBackupPassphrase) {
        MizaniAlertDialog(
            onDismissRequest = ::discardBackupPassphrase,
            shape = MaterialTheme.shapes.large,
            title = { Text(stringResource(R.string.ui_3656e612dd)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(
                        "Encrypted with a key derived from this passphrase. " +
                            "A memorable phrase of 12 or more characters is easier to remember. " +
                            "There is no recovery if you forget it.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = backupPassphrase,
                        onValueChange = { backupPassphrase = it },
                        label = { Text(stringResource(R.string.ui_fc5ecb58fb)) },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = backupPassphraseConfirm,
                        onValueChange = { backupPassphraseConfirm = it },
                        label = { Text(stringResource(R.string.ui_ebaac0cff7)) },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    when {
                        backupPassphrase.length < 12 -> error = "Use at least 12 characters"
                        backupPassphrase != backupPassphraseConfirm -> error = "Passphrases do not match"
                        else -> {
                            error = null
                            pendingBackupPassphrase = backupPassphrase
                            backupPassphrase = ""
                            backupPassphraseConfirm = ""
                            showBackupPassphrase = false
                            createBackup.launch(vm.exporter.suggestedBackupName())
                        }
                    }
                }) { Text(stringResource(R.string.ui_eb7eb7a819)) }
            },
            dismissButton = { TextButton(onClick = ::discardBackupPassphrase) { Text(stringResource(R.string.ui_77dfd2135f)) } },
        )
    }

    if (showRestorePassphrase) {
        MizaniAlertDialog(
            onDismissRequest = { if (!checkingBackup) discardPendingRestore() },
            shape = MaterialTheme.shapes.large,
            title = { Text(stringResource(R.string.ui_73e7e06187)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(
                        UiStr.s(R.string.ui_efab1a5ac8),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = restorePassphrase,
                        onValueChange = { restorePassphrase = it },
                        label = { Text(stringResource(R.string.ui_a68524bf69)) },
                        singleLine = true,
                        enabled = !checkingBackup,
                        visualTransformation = PasswordVisualTransformation(),
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (!checkingBackup) {
                        val bytes = pendingRestoreBytes
                        val passphrase = restorePassphrase
                        if (bytes == null) {
                            error = "Choose a backup file first"
                        } else {
                            checkingBackup = true
                            scope.launch {
                                try {
                                    val summary = vm.exporter.inspectBackup(bytes, passphrase)
                                    if (showRestorePassphrase && pendingRestoreBytes === bytes) {
                                        pendingSummary = summary
                                        showRestorePassphrase = false
                                        showRestoreConfirm = true
                                        error = null
                                    }
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (failure: Exception) {
                                    if (showRestorePassphrase) {
                                        error = failure.message ?: "Could not read this backup"
                                    }
                                } finally {
                                    checkingBackup = false
                                }
                            }
                        }
                    }
                }, enabled = !checkingBackup) {
                    Text(if (checkingBackup) "Checking…" else "Check backup")
                }
            },
            dismissButton = {
                TextButton(onClick = ::discardPendingRestore, enabled = !checkingBackup) { Text(stringResource(R.string.ui_77dfd2135f)) }
            },
        )
    }

    val summary = pendingSummary
    if (showRestoreConfirm && summary != null) {
        MizaniAlertDialog(
            onDismissRequest = { if (!restoringBackup) discardPendingRestore() },
            shape = MaterialTheme.shapes.large,
            title = { Text(stringResource(R.string.ui_2dc2ae29ce)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(
                        "Created ${Instant.ofEpochMilli(summary.createdAt).atZone(ZoneId.systemDefault()).let { DateText.medium(it.toLocalDate()) }}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text("Currency: ${summary.currencyCode}")
                    Text("Wallets: ${summary.walletCount}")
                    Text("Investments: ${summary.investmentCount}")
                    Text("Categories: ${summary.categoryCount}")
                    Text("Transactions: ${summary.transactionCount}")
                    Text(
                        "Date range: ${summary.firstDate?.let { DateText.medium(it) } ?: "—"} to ${summary.lastDate?.let { DateText.medium(it) } ?: "—"}",
                    )
                    Spacer(Modifier.height(Spacing.sm))
                    Text(
                        "This replaces every wallet, transaction, and other saved record on this phone. " +
                            "Create a backup first if you want to keep your current data.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (!restoringBackup) {
                        val bytes = pendingRestoreBytes ?: return@TextButton
                        val passphrase = restorePassphrase
                        restorePassphrase = ""
                        restoringBackup = true
                        scope.launch {
                            try {
                                vm.restoreBackup(bytes, passphrase).getOrThrow()
                                discardPendingRestore()
                                message = UiStr.s(R.string.ui_0b7861d098)
                                error = null
                                try {
                                    vm.finance.currentWorkspace()?.let { workspace ->
                                        vm.setCountry(workspace.countryCode, workspace.currencyCode)
                                    }
                                } catch (failure: Exception) {
                                    error = "Backup restored, but settings could not refresh. Restart the app to reload them."
                                }
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (failure: Exception) {
                                error = failure.message ?: "Could not restore this backup"
                                discardPendingRestore()
                            } finally {
                                restoringBackup = false
                            }
                        }
                    }
                }, enabled = !restoringBackup) {
                    Text(if (restoringBackup) "Restoring…" else "Restore backup")
                }
            },
            dismissButton = {
                TextButton(onClick = ::discardPendingRestore, enabled = !restoringBackup) { Text(stringResource(R.string.ui_77dfd2135f)) }
            },
        )
    }

    if (showDeleteConfirm) {
        MizaniConfirmDialog(
            title = UiStr.s(R.string.ui_87bf3ef2aa),
            body = "This deletes all wallets, transactions, and other saved records on this phone. Without a backup, you cannot restore them. App lock and settings also reset.",
            confirmLabel = "Delete everything",
            destructive = true,
            onConfirm = {
                scope.launch {
                    vm.deleteAllData()
                        .onSuccess {
                            showDeleteConfirm = false
                            message = UiStr.s(R.string.ui_eb80ff83a7)
                            error = null
                        }
                        .onFailure {
                            // Close so the failure banner is visible instead of hidden behind the dialog.
                            showDeleteConfirm = false
                            error = it.message ?: "Could not delete local data. Nothing was removed."
                        }
                }
            },
            onDismiss = { showDeleteConfirm = false },
        )
    }

    if (dataToolsOnly) {
        Column(Modifier.fillMaxSize()) {
            MizaniTopBar(title = UiStr.s(R.string.ui_f6da5a2df0), onBack = onBack)
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.TopCenter,
            ) {
                Column(
                    modifier = Modifier
                        .widthIn(max = 680.dp)
                        .fillMaxWidth()
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = Spacing.lg)
                        .padding(bottom = Spacing.bottom),
                    verticalArrangement = Arrangement.spacedBy(Spacing.lg),
                ) {
                message?.let {
                    StatusBanner(text = it, isError = false, onDismiss = { message = null })
                }
                if (error != null && !showBackupPassphrase && !showRestorePassphrase) {
                    StatusBanner(text = error!!, isError = true, onDismiss = { error = null })
                }
                Text(
                    UiStr.s(R.string.ui_dbb92ab15c),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                MizaniSectionCard {
                    MizaniInfoRow(
                        icon = Icons.Rounded.Download,
                        title = UiStr.s(R.string.ui_781c987361),
                        subtitle = UiStr.s(R.string.ui_ac350ad5a7),
                        onClick = { requestSensitiveAction(SensitiveDataAction.EXCEL_EXPORT) },
                    )
                    MizaniSectionDivider()
                    MizaniInfoRow(
                        icon = Icons.Rounded.Download,
                        title = UiStr.s(R.string.ui_74ba6a524e),
                        subtitle = UiStr.s(R.string.ui_ce4d1690e0),
                        onClick = { requestSensitiveAction(SensitiveDataAction.CSV_EXPORT) },
                    )
                    MizaniSectionDivider()
                    MizaniInfoRow(
                        icon = Icons.Rounded.Backup,
                        title = if (creatingBackup) "Creating encrypted backup…" else "Create encrypted backup",
                        subtitle = if (creatingBackup) "Keep Mizani open while the backup is saved" else "Protect the file with a passphrase",
                        onClick = {
                            if (!creatingBackup) requestSensitiveAction(SensitiveDataAction.ENCRYPTED_BACKUP)
                        },
                    )
                    MizaniSectionDivider()
                    MizaniInfoRow(
                        icon = Icons.Rounded.Restore,
                        title = UiStr.s(R.string.ui_b7a851cb91),
                        subtitle = UiStr.s(R.string.ui_abf594ad14),
                        onClick = {
                            discardPendingRestore()
                            error = null
                            openRestore.launch(arrayOf("application/octet-stream", "application/zip", "*/*"))
                        },
                    )
                }

                }
            }
        }
        return
    }

    // Focused entry from the balance-visibility control: scroll the Security card into
    // view so the "Set up app lock" button is reachable without hunting through Settings.
    val appLockRequester = remember { BringIntoViewRequester() }
    LaunchedEffect(highlightAppLock) {
        if (highlightAppLock) {
            Toast.makeText(
                context,
                "Set up an app PIN below to view wallet balances.",
                Toast.LENGTH_LONG,
            ).show()
            delay(180)
            appLockRequester.bringIntoView()
        }
    }

    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(title = UiStr.s(R.string.ui_c7f73bb54d), onBack = onBack)
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 680.dp)
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Spacing.lg)
                    .padding(bottom = Spacing.bottom),
                verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            message?.let {
                StatusBanner(text = it, isError = false, onDismiss = { message = null })
            }
            if (error != null && !showBackupPassphrase && !showRestorePassphrase) {
                StatusBanner(text = error!!, isError = true, onDismiss = { error = null })
            }

            SectionHeader(
                title = UiStr.s(R.string.ui_41def7a0fe),
                accent = true,
                // Labels stay outside their card; +4dp keeps 16dp between groups, 12dp label-to-card.
                modifier = Modifier.padding(top = Spacing.xs),
            )
            MizaniCard {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(UiStr.s(R.string.ui_a797e30923), style = MaterialTheme.typography.titleSmall)
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                    ) {
                        ThemeMode.entries.forEach { mode ->
                            FilterChip(
                                selected = settings.themeMode == mode,
                                onClick = { scope.launch { vm.setTheme(mode) } },
                                label = { Text(mode.label, maxLines = 1) },
                                modifier = Modifier.heightIn(min = 48.dp),
                            )
                        }
                    }
                    Text(
                        UiStr.s(R.string.ui_73a6986649),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Spacer(Modifier.height(Spacing.md))
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Spacer(Modifier.height(Spacing.md))
                Text(UiStr.s(R.string.ui_e49578edcf), style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    UiStr.s(R.string.ui_c8b3e73f2f),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(Spacing.sm))
                val accentHex = settings.customAccentColorHex
                    ?: colorThemePreviewColor(settings.colorTheme).toHexString()
                val accentColor = ComposeColor(AndroidColor.parseColor(accentHex))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedButton(
                        onClick = { showAccentColorPicker = true },
                        modifier = Modifier.weight(1f).heightIn(min = 60.dp),
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                Modifier
                                    .size(24.dp)
                                    .clip(CircleShape)
                                    .background(accentColor),
                            )
                            Column(Modifier.weight(1f)) {
                                Text(UiStr.s(R.string.ui_09b969bbf9), maxLines = 1)
                                Text(
                                    accentHex,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                    if (
                        settings.customAccentColorHex != null ||
                        settings.colorTheme != ColorTheme.MIZANI
                    ) {
                        TextButton(
                            onClick = { scope.launch { vm.resetAccentColor() } },
                            modifier = Modifier.heightIn(min = 48.dp),
                        ) { Text(stringResource(R.string.ui_44c57abd88)) }
                    }
                }

                if (showAccentColorPicker) {
                    AccentColorPickerDialog(
                        initialColorHex = accentHex,
                        onDismiss = { showAccentColorPicker = false },
                        onApply = { hex ->
                            scope.launch {
                                vm.setCustomAccentColor(hex)
                                showAccentColorPicker = false
                            }
                        },
                    )
                }

                Spacer(Modifier.height(Spacing.md))
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Spacer(Modifier.height(Spacing.md))
                Text(UiStr.s(R.string.ui_f229ed4543), style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    UiStr.s(R.string.ui_ee78ae0933),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(Spacing.md))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    DarkThemeStyle.entries.forEach { style ->
                        FilterChip(
                            selected = settings.darkThemeStyle == style,
                            onClick = { scope.launch { vm.setDarkThemeStyle(style) } },
                            label = { Text(style.label, maxLines = 1) },
                            modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                        )
                    }
                }
            }

            SectionHeader(
                title = UiStr.s(R.string.ui_f25ce1b8a3),
                accent = true,
                modifier = Modifier.padding(top = Spacing.xs),
            )
            MizaniCard(
                modifier = Modifier.bringIntoViewRequester(appLockRequester),
            ) {
                if (highlightAppLock) {
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        shape = MaterialTheme.shapes.medium,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier.padding(Spacing.md),
                            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Rounded.Lock,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp),
                            )
                            Text(
                                UiStr.s(R.string.ui_f47a4d8250),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                    Spacer(Modifier.height(Spacing.md))
                }
                MizaniInfoRow(
                    icon = Icons.Rounded.Lock,
                    title = UiStr.s(R.string.ui_a34fa2ead1),
                    subtitle = if (settings.lockEnabled) "On · 6-digit PIN" else "Off",
                )
                if (settings.hasPin) {
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        OutlinedButton(
                            onClick = { showVerifyForChange = true },
                            shape = MaterialTheme.shapes.medium,
                        ) { Text(stringResource(R.string.ui_ef2c76f483)) }
                        OutlinedButton(
                            onClick = { showDisablePin = true },
                            shape = MaterialTheme.shapes.medium,
                        ) {
                            Icon(Icons.Rounded.LockOpen, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(stringResource(R.string.ui_8807c2b3fd))
                        }
                        if (settings.lockEnabled) {
                            TextButton(onClick = { vm.lockNow() }) { Text(stringResource(R.string.ui_9217b30d55)) }
                        }
                    }
                } else {
                    OutlinedButton(
                        onClick = { showPinSetup = true },
                        shape = MaterialTheme.shapes.medium,
                    ) { Text(stringResource(R.string.ui_da9927b1cd)) }
                }
                if (settings.lockEnabled && canBiometric) {
                    Spacer(Modifier.height(Spacing.sm))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Fingerprint, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(Spacing.md))
                        Column(Modifier.weight(1f)) {
                            Text(UiStr.s(R.string.ui_1197e4d653), style = MaterialTheme.typography.titleSmall)
                            Text(
                                UiStr.s(R.string.ui_032efc484f),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = settings.biometricEnabled,
                            onCheckedChange = { enabled -> vm.setBiometric(enabled) {} },
                            modifier = Modifier.semantics { contentDescription = "Biometric unlock" },
                        )
                    }
                }
                Text(
                    UiStr.s(R.string.ui_85e1bf89df),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SectionHeader(
                title = UiStr.s(R.string.ui_0f21717994),
                accent = true,
                modifier = Modifier.padding(top = Spacing.xs),
            )
            MizaniCard {
                MizaniInfoRow(
                    icon = Icons.Rounded.Language,
                    title = UiStr.s(R.string.ui_c8a5b225b1),
                    subtitle = "${CountryPacks.byCode(settings.countryCode).name} · ${state.snapshot.currencyCode}",
                    onClick = { showCountryDialog = true },
                )
                Text(
                    UiStr.s(R.string.ui_ed0cbbe511),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SectionHeader(
                title = stringResource(R.string.settings_reminders_title),
                accent = true,
                modifier = Modifier.padding(top = Spacing.xs),
            )
            MizaniCard {
                val reminderTimeLabel = DailyReminderSchedule.formatForDisplay(
                    settings.dailyReminderMinuteOfDay,
                    locale,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.settings_daily_reminder_title),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            stringResource(R.string.settings_daily_reminder_description, reminderTimeLabel),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = settings.dailyReminderEnabled,
                        onCheckedChange = onDailyReminderChanged,
                        modifier = Modifier.semantics {
                            contentDescription = dailyReminderTitle
                        },
                    )
                }
                if (settings.dailyReminderEnabled) {
                    Spacer(Modifier.height(Spacing.sm))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.settings_reminder_time_label), style = MaterialTheme.typography.bodyMedium)
                        OutlinedButton(
                            onClick = {
                                TimePickerDialog(
                                    context,
                                    { _, hour, minute ->
                                        scope.launch {
                                            vm.setDailyReminderMinuteOfDay(hour * 60 + minute)
                                                .onSuccess { reminderStatus = null }
                                                .onFailure {
                                                    reminderStatus = reminderScheduleError
                                                }
                                        }
                                    },
                                    settings.dailyReminderMinuteOfDay / 60,
                                    settings.dailyReminderMinuteOfDay % 60,
                                    false,
                                ).apply {
                                    window?.setFlags(
                                        WindowManager.LayoutParams.FLAG_SECURE,
                                        WindowManager.LayoutParams.FLAG_SECURE,
                                    )
                                }.show()
                            },
                            shape = MaterialTheme.shapes.medium,
                        ) {
                            Text(reminderTimeLabel)
                        }
                    }
                    Text(
                        stringResource(R.string.settings_reminder_local_note),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (notificationsAvailable) {
                        TextButton(
                            onClick = {
                                if (DailyReminderNotifications.postTest(context)) {
                                    message = reminderTestSent
                                    error = null
                                    reminderStatus = null
                                } else {
                                    notificationSettingsRevision += 1
                                    reminderStatus = reminderNotificationsDisabled
                                    showReminderNotificationSettings = true
                                }
                            },
                            modifier = Modifier.semantics {
                                contentDescription = reminderTestLabel
                            },
                        ) {
                            Text(reminderTestLabel)
                        }
                    }
                    if (!notificationsAvailable) {
                        Text(
                            stringResource(R.string.settings_reminder_notifications_disabled),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                        TextButton(onClick = requestDailyReminderNotificationAccess) {
                            Text(
                                stringResource(
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                        ContextCompat.checkSelfPermission(
                                            context,
                                            Manifest.permission.POST_NOTIFICATIONS,
                                        ) != android.content.pm.PackageManager.PERMISSION_GRANTED
                                    ) {
                                        R.string.settings_allow_notifications
                                    } else {
                                        R.string.settings_open_notification_settings
                                    },
                                ),
                            )
                        }
                    }
                }
                reminderStatus?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
                if (showReminderNotificationSettings && !settings.dailyReminderEnabled) {
                    TextButton(onClick = openReminderNotificationSettings) {
                        Text(stringResource(R.string.settings_open_notification_settings))
                    }
                }
            }

            MizaniCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.settings_habit_notifications_title),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            stringResource(R.string.settings_habit_notifications_description),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    MizaniInfoButton(
                        infoTitle = stringResource(R.string.info_personalised_checkins_title),
                        infoBody = stringResource(R.string.info_personalised_checkins_body),
                        contentDescription = stringResource(R.string.info_personalised_checkins_title),
                    )
                    Switch(
                        checked = settings.habitNotificationsEnabled,
                        onCheckedChange = onHabitNotificationsChanged,
                        modifier = Modifier.semantics {
                            contentDescription = habitNotificationTitle
                        },
                    )
                }
                if (settings.habitNotificationsEnabled) {
                    Spacer(Modifier.height(Spacing.md))
                    Text(
                        stringResource(R.string.settings_habit_notifications_choose),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    Spacer(Modifier.height(Spacing.xs))
                    HabitNotificationToggle(
                        title = stringResource(R.string.settings_habit_spending_title),
                        description = stringResource(R.string.settings_habit_spending_description),
                        checked = settings.habitSpendingNotificationsEnabled,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                vm.setHabitSpendingNotificationsEnabled(enabled)
                                    .onFailure { reminderStatus = reminderScheduleError }
                            }
                        },
                    )
                    HabitNotificationToggle(
                        title = stringResource(R.string.settings_habit_income_title),
                        description = stringResource(R.string.settings_habit_income_description),
                        checked = settings.habitIncomeNotificationsEnabled,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                vm.setHabitIncomeNotificationsEnabled(enabled)
                                    .onFailure { reminderStatus = reminderScheduleError }
                            }
                        },
                    )
                    HabitNotificationToggle(
                        title = stringResource(R.string.settings_habit_investment_title),
                        description = stringResource(R.string.settings_habit_investment_description),
                        checked = settings.habitInvestmentNotificationsEnabled,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                vm.setHabitInvestmentNotificationsEnabled(enabled)
                                    .onFailure { reminderStatus = reminderScheduleError }
                            }
                        },
                    )
                    HabitNotificationToggle(
                        title = stringResource(R.string.settings_habit_debt_title),
                        description = stringResource(R.string.settings_habit_debt_description),
                        checked = settings.habitDebtNotificationsEnabled,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                vm.setHabitDebtNotificationsEnabled(enabled)
                                    .onFailure { reminderStatus = reminderScheduleError }
                            }
                        },
                    )
                    HabitNotificationToggle(
                        title = stringResource(R.string.settings_habit_goal_title),
                        description = stringResource(R.string.settings_habit_goal_description),
                        checked = settings.habitGoalNotificationsEnabled,
                        onCheckedChange = { enabled ->
                            scope.launch {
                                vm.setHabitGoalNotificationsEnabled(enabled)
                                    .onFailure { reminderStatus = reminderScheduleError }
                            }
                        },
                    )
                    Spacer(Modifier.height(Spacing.xs))
                    Text(
                        stringResource(R.string.settings_habit_notifications_note),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                habitStatus?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
                if (habitStatus != null && showReminderNotificationSettings && !settings.habitNotificationsEnabled) {
                    TextButton(onClick = openReminderNotificationSettings) {
                        Text(stringResource(R.string.settings_open_notification_settings))
                    }
                }
            }

            SectionHeader(
                title = UiStr.s(R.string.ui_cf01481f62),
                accent = true,
                modifier = Modifier.padding(top = Spacing.xs),
            )
            MizaniSectionCard {
                MizaniInfoRow(
                    icon = Icons.Rounded.Security,
                    title = UiStr.s(R.string.ui_f6ebb9bde3),
                    subtitle = UiStr.s(R.string.ui_f3e763a79b),
                )
            }

            SectionHeader(
                title = UiStr.s(R.string.ui_cfbcfa19af),
                accent = true,
                modifier = Modifier.padding(top = Spacing.xs),
            )
            MizaniSectionCard {
                MizaniInfoRow(
                    icon = Icons.Rounded.DeleteForever,
                    title = UiStr.s(R.string.ui_600b409c87),
                    subtitle = UiStr.s(R.string.ui_b76cc50249),
                    danger = true,
                    onClick = { showDeleteConfirm = true },
                )
            }

        }
        }
    }
}

@Composable
private fun AccentColorPickerDialog(
    initialColorHex: String,
    onDismiss: () -> Unit,
    onApply: (String) -> Unit,
) {
    val initialHsv = remember(initialColorHex) {
        FloatArray(3).also { AndroidColor.colorToHSV(AndroidColor.parseColor(initialColorHex), it) }
    }
    var hue by rememberSaveable(initialColorHex) { mutableStateOf(initialHsv[0]) }
    var saturation by rememberSaveable(initialColorHex) { mutableStateOf(initialHsv[1]) }
    var brightness by rememberSaveable(initialColorHex) { mutableStateOf(initialHsv[2]) }
    var hexText by rememberSaveable(initialColorHex) { mutableStateOf(initialColorHex) }
    val selectedColor = remember(hue, saturation, brightness) {
        ComposeColor(AndroidColor.HSVToColor(floatArrayOf(hue, saturation, brightness)))
    }
    val selectedHex = selectedColor.toHexString()

    fun setHsv(newHue: Float = hue, newSaturation: Float = saturation, newBrightness: Float = brightness) {
        hue = newHue
        saturation = newSaturation
        brightness = newBrightness
        hexText = ComposeColor(AndroidColor.HSVToColor(floatArrayOf(newHue, newSaturation, newBrightness)))
            .toHexString()
    }

    MizaniAlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.large,
        title = { Text(stringResource(R.string.ui_83bbbe3efd)) },
        text = {
            Column(
                modifier = Modifier.heightIn(max = 440.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Box(
                        Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(selectedColor)
                            .semantics { contentDescription = "Selected accent color $selectedHex" },
                    )
                    Text(selectedHex, style = MaterialTheme.typography.titleSmall)
                }

                Text(UiStr.s(R.string.ui_7e58a6e8d8), style = MaterialTheme.typography.labelMedium)
                Slider(
                    value = hue,
                    onValueChange = { setHsv(newHue = it) },
                    valueRange = 0f..360f,
                    colors = SliderDefaults.colors(
                        thumbColor = selectedColor,
                        activeTrackColor = selectedColor,
                    ),
                )

                Text(UiStr.s(R.string.ui_20a32bc870), style = MaterialTheme.typography.labelMedium)
                Slider(
                    value = saturation,
                    onValueChange = { setHsv(newSaturation = it) },
                    valueRange = 0f..1f,
                    colors = SliderDefaults.colors(
                        thumbColor = selectedColor,
                        activeTrackColor = selectedColor,
                    ),
                )

                Text(UiStr.s(R.string.ui_e1a2b65df8), style = MaterialTheme.typography.labelMedium)
                Slider(
                    value = brightness,
                    onValueChange = { setHsv(newBrightness = it) },
                    valueRange = 0f..1f,
                    colors = SliderDefaults.colors(
                        thumbColor = selectedColor,
                        activeTrackColor = selectedColor,
                    ),
                )

                OutlinedTextField(
                    value = hexText,
                    onValueChange = { value ->
                        if (value.length <= 7) {
                            hexText = value
                            normalizedPickerHex(value)?.let { normalized ->
                                val hsv = FloatArray(3)
                                AndroidColor.colorToHSV(AndroidColor.parseColor(normalized), hsv)
                                hue = hsv[0]
                                saturation = hsv[1]
                                brightness = hsv[2]
                            }
                        }
                    },
                    label = { Text(stringResource(R.string.ui_1ba7b1495f)) },
                    supportingText = { Text(stringResource(R.string.ui_fbb0f01026)) },
                    singleLine = true,
                    isError = normalizedPickerHex(hexText) == null,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { normalizedPickerHex(hexText)?.let(onApply) },
                enabled = normalizedPickerHex(hexText) != null,
            ) { Text(stringResource(R.string.ui_3895109dfa)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.ui_77dfd2135f)) } },
    )
}

private fun normalizedPickerHex(value: String): String? {
    val digits = value.trim().removePrefix("#")
    if (
        digits.length != 6 ||
        digits.any { it !in '0'..'9' && it.lowercaseChar() !in 'a'..'f' }
    ) return null
    return "#${digits.uppercase(Locale.ROOT)}"
}

private fun ComposeColor.toHexString(): String =
    String.format(Locale.ROOT, "#%06X", 0xFFFFFF and toArgb())

@Composable
private fun HabitNotificationToggle(
    title: String,
    description: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.semantics { contentDescription = title },
        )
    }
}

@Composable
private fun CountryCurrencyDialog(
    initialCountry: String,
    workspaceCurrency: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var countryCode by rememberSaveable { mutableStateOf(initialCountry) }
    MizaniAlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.large,
        title = { Text(stringResource(R.string.ui_c8a5b225b1)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(UiStr.s(R.string.ui_d523ebbd10), style = MaterialTheme.typography.labelMedium)
                MizaniPicker(
                    selectedText = CountryPacks.byCode(countryCode).name,
                    options = CountryPacks.all.map { PickerOption(it.code, it.name) },
                    onSelect = { countryCode = it },
                    searchable = true,
                    searchHint = stringResource(R.string.search_countries),
                    emptyResultsLabel = stringResource(R.string.no_countries_match),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(UiStr.s(R.string.ui_73076f0d94), style = MaterialTheme.typography.labelMedium)
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        workspaceCurrency,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(horizontal = Spacing.md, vertical = Spacing.md),
                    )
                }
                Text(
                        UiStr.s(R.string.ui_8eed134b30),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onSave(countryCode) }) { Text(stringResource(R.string.ui_efc007a393)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.ui_77dfd2135f)) } },
    )
}

private suspend fun writeBytes(context: Context, uri: Uri, bytes: ByteArray) {
    try {
        withContext(Dispatchers.IO) {
            context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw IOException("Could not open the selected file for writing")
        }
    } finally {
        // The helper consumes a caller-owned buffer so clear both encrypted backups and CSV copies.
        bytes.fill(0)
    }
}
