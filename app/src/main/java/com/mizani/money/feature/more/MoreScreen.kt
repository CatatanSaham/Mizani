package com.mizani.money.feature.more

import com.mizani.money.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.AccountBalance
import androidx.compose.material.icons.rounded.Category
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Feedback
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.automirrored.rounded.ShowChart
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mizani.money.ui.AdaptiveLayout
import com.mizani.money.ui.components.MizaniInfoRow
import com.mizani.money.ui.components.MizaniSectionCard
import com.mizani.money.ui.components.MizaniSectionDivider
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.SectionHeader
import com.mizani.money.ui.components.Spacing

/** Cap for the two-column More layout so wide screens never stretch cards. */
private val MoreContentMaxWidth = 1180.dp
private val MoreTwoColumnMinWidth = 640.dp

@Composable
fun MoreScreen(
    onNavigate: (String) -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(title = stringResource(R.string.ui_4bab2d8fe1))
        Box(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.lg)
                .padding(bottom = Spacing.bottomFab),
        ) {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                // More sections are compact enough to split at a narrower width than Home's cards.
                // This keeps landscape phones in two columns after the navigation rail and gutters.
                val twoColumn = maxWidth >= MoreTwoColumnMinWidth
                val contentMaxWidth = if (twoColumn) {
                    MoreContentMaxWidth
                } else {
                    AdaptiveLayout.SINGLE_COLUMN_MAX_WIDTH_DP.dp
                }
                Column(
                    modifier = Modifier
                        .widthIn(max = contentMaxWidth)
                        .fillMaxWidth()
                        .align(Alignment.Center),
                    verticalArrangement = Arrangement.spacedBy(Spacing.lg),
                ) {
                    if (twoColumn) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(Spacing.lg),
                        ) {
                            ManageMoneySection(
                                onNavigate = onNavigate,
                                modifier = Modifier.weight(1f),
                            )
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(Spacing.lg),
                            ) {
                                YourDataSection(onNavigate)
                                AppSection(onNavigate)
                                GettingStartedSection(onNavigate)
                            }
                        }
                    } else {
                        ManageMoneySection(onNavigate)
                        YourDataSection(onNavigate)
                        AppSection(onNavigate)
                        GettingStartedSection(onNavigate)
                    }
                }
            }
        }
    }
}

@Composable
private fun ManageMoneySection(
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(Spacing.lg),
    ) {
        SectionHeader(title = stringResource(R.string.ui_bd2c53e62e), accent = true)
        MizaniSectionCard {
            MizaniInfoRow(
                icon = Icons.Rounded.AccountBalanceWallet,
                title = stringResource(R.string.ui_98d5a197e5),
                subtitle = stringResource(R.string.ui_29ec9bfe65),
                onClick = { onNavigate("wallets") },
            )
            MizaniSectionDivider()
            MizaniInfoRow(
                icon = Icons.Rounded.AccountBalance,
                title = stringResource(R.string.ui_787aab25f6),
                subtitle = stringResource(R.string.ui_f36e0e2ded),
                onClick = { onNavigate("debts") },
            )
            MizaniSectionDivider()
            MizaniInfoRow(
                icon = Icons.AutoMirrored.Rounded.ShowChart,
                title = stringResource(R.string.ui_5de64aff09),
                subtitle = stringResource(R.string.ui_59e4f1e47a),
                onClick = { onNavigate("investments") },
            )
            MizaniSectionDivider()
            MizaniInfoRow(
                icon = Icons.Rounded.Category,
                title = stringResource(R.string.ui_6ccb60071b),
                subtitle = stringResource(R.string.ui_12a240e8cc),
                onClick = { onNavigate("categories") },
            )
        }
    }
}

@Composable
private fun YourDataSection(
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(Spacing.lg),
    ) {
        SectionHeader(title = stringResource(R.string.ui_48cd18dabc), accent = true)
        MizaniSectionCard {
            MizaniInfoRow(
                icon = Icons.Rounded.Download,
                title = stringResource(R.string.ui_871fa14e52),
                subtitle = stringResource(R.string.ui_4fab22e59e),
                onClick = { onNavigate("export") },
            )
        }
    }
}

@Composable
private fun AppSection(
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(Spacing.lg),
    ) {
        SectionHeader(title = stringResource(R.string.ui_fc4a695f02), accent = true)
        MizaniSectionCard {
            MizaniInfoRow(
                icon = Icons.Rounded.Settings,
                title = stringResource(R.string.ui_c7f73bb54d),
                subtitle = stringResource(R.string.ui_a902552e5e),
                onClick = { onNavigate("settings") },
            )
            MizaniSectionDivider()
            MizaniInfoRow(
                icon = Icons.Rounded.Info,
                title = stringResource(R.string.ui_57fc3d5cbd),
                subtitle = stringResource(R.string.ui_295096b14e),
                onClick = { onNavigate("about") },
            )
            MizaniSectionDivider()
            MizaniInfoRow(
                icon = Icons.Rounded.Feedback,
                title = stringResource(R.string.ui_c431a26258),
                subtitle = stringResource(R.string.ui_df329ec8d8),
                onClick = { onNavigate("feedback") },
            )
        }
    }
}

@Composable
private fun GettingStartedSection(onNavigate: (String) -> Unit) {
    SectionHeader(title = stringResource(R.string.ui_c47ae15370), accent = true)
    MizaniSectionCard {
        MizaniInfoRow(
            icon = Icons.Rounded.Info,
            title = stringResource(R.string.ui_822622bb5c),
            subtitle = stringResource(R.string.ui_8f69f08520),
            onClick = { onNavigate("getting-started") },
        )
    }
}
