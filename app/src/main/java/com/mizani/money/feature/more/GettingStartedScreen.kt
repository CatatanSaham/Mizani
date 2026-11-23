package com.mizani.money.feature.more

import com.mizani.money.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.mizani.money.ui.components.MizaniCard
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.Spacing
import com.mizani.money.ui.guides.FeatureGuide
import com.mizani.money.ui.guides.FeatureGuides

/** One catalogue is the entry point for every in-app feature guide. */
@Composable
fun GettingStartedScreen(
    onBack: () -> Unit,
    onStartGuide: (FeatureGuide) -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(title = "Guides for every feature", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.lg, vertical = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Text(
                "Choose what you want to learn. Each guide points out the controls on that screen and can be replayed any time.",
                modifier = Modifier.padding(bottom = Spacing.xs),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            FeatureGuides.all.forEach { guide ->
                MizaniCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(Spacing.md),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Text(guide.title, style = MaterialTheme.typography.titleMedium)
                        Text(
                            guide.summary,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(
                            onClick = { onStartGuide(guide) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { contentDescription = "Start guide: ${guide.title}" },
                        ) {
                            Text(stringResource(R.string.ui_edcb56a2bb))
                        }
                    }
                }
            }
        }
    }
}
