package com.mizani.money.feature.settings

import com.mizani.money.R
import androidx.compose.ui.res.stringResource
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Feedback
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Shield
import com.google.android.gms.oss.licenses.v2.OssLicensesMenuActivity
import com.mizani.money.ui.components.MizaniAlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.mizani.money.BuildConfig
import com.mizani.money.core.legal.LegalDocumentId
import com.mizani.money.core.model.AppInfo
import com.mizani.money.data.repo.UpdateCheckResult
import com.mizani.money.data.repo.UpdateRepository
import com.mizani.money.feature.legal.LegalDocumentsDialog
import com.mizani.money.feature.legal.ThirdPartyNoticesDialog
import com.mizani.money.ui.AppUiState
import com.mizani.money.ui.components.MizaniCard
import com.mizani.money.ui.components.MizaniInfoRow
import com.mizani.money.ui.components.MizaniMark
import com.mizani.money.ui.components.MizaniPageContent
import com.mizani.money.ui.components.MizaniSectionCard
import com.mizani.money.ui.components.MizaniSectionDivider
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun AboutScreen(
    state: AppUiState,
    onBack: () -> Unit,
    onFeedback: () -> Unit,
) {
    var legalDocument by rememberSaveable { mutableStateOf<LegalDocumentId?>(null) }
    var showThirdPartyNotices by rememberSaveable { mutableStateOf(false) }
    var isCheckingForUpdate by remember { mutableStateOf(false) }
    var updateMessage by rememberSaveable { mutableStateOf<String?>(null) }
    var releasePageUrl by rememberSaveable { mutableStateOf<String?>(null) }
    var availableVersionName by rememberSaveable { mutableStateOf<String?>(null) }
    var showUpdatePrompt by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val updateRepository = remember { UpdateRepository() }
    val installedFromPlay = remember(context) { isInstalledFromPlay(context) }

    fun checkForUpdates() {
        if (isCheckingForUpdate) return
        isCheckingForUpdate = true
        updateMessage = null
        releasePageUrl = null
        availableVersionName = null
        showUpdatePrompt = false
        scope.launch {
            try {
                when (val result = withContext(Dispatchers.IO) {
                    updateRepository.checkForUpdate(BuildConfig.VERSION_CODE)
                }) {
                    UpdateCheckResult.NoReleases -> updateMessage = "No release is available yet."
                    UpdateCheckResult.UpToDate -> updateMessage = "You’re up to date."
                    is UpdateCheckResult.Available -> {
                        updateMessage = "Version ${result.release.versionName} is available."
                        releasePageUrl = result.release.pageUrl
                        availableVersionName = result.release.versionName
                        showUpdatePrompt = true
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                updateMessage = "Couldn’t check for updates. Try again later."
            } finally {
                isCheckingForUpdate = false
            }
        }
    }

    fun openReleasePage() {
        val url = releasePageUrl ?: return
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: ActivityNotFoundException) {
            updateMessage = "No browser is available to open the release."
        }
    }

    fun openPlayListing() {
        val playListingUrl = "https://play.google.com/store/apps/details?id=${context.packageName}"
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(playListingUrl)))
        } catch (_: ActivityNotFoundException) {
            updateMessage = "No browser is available to open the Play Store listing."
        }
    }

    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(title = stringResource(R.string.ui_3bdc8163b2), onBack = onBack)
        MizaniPageContent {
            Row(verticalAlignment = Alignment.CenterVertically) {
                MizaniMark(size = 56)
                Spacer(Modifier.width(Spacing.md))
                Column {
                    Text(AppInfo.NAME, style = MaterialTheme.typography.headlineSmall)
                    Text(AppInfo.TAGLINE, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
                    Text("Version ${AppInfo.VERSION} (build ${BuildConfig.VERSION_CODE})", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            MizaniSectionCard {
                MizaniInfoRow(
                    icon = Icons.Rounded.Download,
                    title = if (installedFromPlay) "App updates" else "Check for updates",
                    modifier = if (installedFromPlay) {
                        Modifier.semantics {
                            contentDescription = stringResource(R.string.ui_2651cd315e)
                        }
                    } else {
                        Modifier
                    },
                    subtitle = when {
                        installedFromPlay -> "Installed from Google Play · build ${BuildConfig.VERSION_CODE}. Play checks when online and prompts you when an update is ready."
                        isCheckingForUpdate -> "Checking for a new version…"
                        else -> "Sideloaded build ${BuildConfig.VERSION_CODE}. Play updates require a Play-installed copy; use the official release check below."
                    },
                    onClick = when {
                        installedFromPlay -> ::openPlayListing
                        isCheckingForUpdate -> null
                        else -> ::checkForUpdates
                    },
                )
                if (updateMessage != null) {
                    MizaniSectionDivider()
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = Spacing.md, vertical = Spacing.xs),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            updateMessage.orEmpty(),
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (releasePageUrl != null) {
                            TextButton(onClick = ::openReleasePage) { Text(stringResource(R.string.ui_543e94b822)) }
                        }
                    }
                }
            }

            MizaniSectionCard {
                MizaniInfoRow(
                    icon = Icons.Rounded.Feedback,
                    title = stringResource(R.string.ui_c431a26258),
                    subtitle = stringResource(R.string.ui_3b15df92b0),
                    onClick = onFeedback,
                )
            }

            MizaniCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Shield, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(Spacing.sm))
                    Text(stringResource(R.string.ui_b6713cd239), style = MaterialTheme.typography.titleMedium)
                }
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    stringResource(R.string.ui_a0dfb542d7),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            MizaniCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(Spacing.sm))
                    Text(stringResource(R.string.ui_2672be37e3), style = MaterialTheme.typography.titleMedium)
                }
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    "CSV and Excel files are unencrypted. Backups use your passphrase. Uninstalling may erase local data, " +
                        "so create a backup first.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (state.settings.lockEnabled) {
                    Spacer(Modifier.height(Spacing.sm))
                    Text(stringResource(R.string.ui_712607a31f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                }
            }

            MizaniCard {
                Text(stringResource(R.string.ui_395310b3d4), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    stringResource(R.string.ui_c2d016de30),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            MizaniSectionCard {
                MizaniInfoRow(
                    icon = Icons.Rounded.Description,
                    title = stringResource(R.string.ui_0c8a9a95e2),
                    subtitle = stringResource(R.string.ui_e21a48af56),
                    onClick = { legalDocument = LegalDocumentId.TERMS },
                )
                MizaniSectionDivider()
                MizaniInfoRow(
                    icon = Icons.Rounded.Shield,
                    title = stringResource(R.string.ui_14862f7224),
                    subtitle = stringResource(R.string.ui_7914ef8c3e),
                    onClick = { legalDocument = LegalDocumentId.PRIVACY },
                )
                MizaniSectionDivider()
                MizaniInfoRow(
                    icon = Icons.Rounded.Description,
                    title = stringResource(R.string.ui_30dced67aa),
                    subtitle = stringResource(R.string.ui_c35091dd68),
                    onClick = {
                        context.startActivity(Intent(context, OssLicensesMenuActivity::class.java))
                    },
                )
                MizaniSectionDivider()
                MizaniInfoRow(
                    icon = Icons.Rounded.Description,
                    title = stringResource(R.string.ui_a436c20f88),
                    subtitle = stringResource(R.string.ui_38f7f02a3e),
                    onClick = { showThirdPartyNotices = true },
                )
            }

        }
    }
    legalDocument?.let { document ->
        LegalDocumentsDialog(initialDocument = document, onClose = { legalDocument = null })
    }
    if (showThirdPartyNotices) {
        ThirdPartyNoticesDialog(onClose = { showThirdPartyNotices = false })
    }
    if (showUpdatePrompt && availableVersionName != null) {
        MizaniAlertDialog(
            onDismissRequest = { showUpdatePrompt = false },
            title = { Text(stringResource(R.string.ui_21f1865b4f)) },
            text = {
                Text(
                    "Mizani version $availableVersionName is available. Open the official release page to review the update and installation instructions.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showUpdatePrompt = false
                    openReleasePage()
                }) { Text(stringResource(R.string.ui_6fcad34c9e)) }
            },
            dismissButton = {
                TextButton(onClick = { showUpdatePrompt = false }) { Text(stringResource(R.string.ui_56e2f5d363)) }
            },
        )
    }
}

@Suppress("DEPRECATION")
private fun isInstalledFromPlay(context: android.content.Context): Boolean {
    val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        runCatching {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        }.getOrNull()
    } else {
        context.packageManager.getInstallerPackageName(context.packageName)
    }
    return installer == "com.android.vending"
}
