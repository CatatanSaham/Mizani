package com.mizani.money.feature.legal

import com.mizani.money.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.PrivacyTip
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mizani.money.core.legal.LegalDocumentId
import com.mizani.money.ui.components.MizaniMark

/** Re-consent gate for an installed version that has not accepted the current legal documents. */
@Composable
fun LegalConsentScreen(
    accepting: Boolean,
    error: String?,
    onAgree: () -> Unit,
) {
    var openedDocument by rememberSaveable { mutableStateOf<LegalDocumentId?>(null) }

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .heightIn(min = maxHeight)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            MizaniMark(size = 58)
            Spacer(Modifier.height(20.dp))
            Icon(
                Icons.Rounded.Shield,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(30.dp),
            )
            Spacer(Modifier.height(10.dp))
            Text(stringResource(R.string.ui_54193ce965), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.ui_90eef4b544),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(20.dp))

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    LegalLinkRow(
                        icon = Icons.Rounded.Description,
                        title = stringResource(R.string.ui_0c8a9a95e2),
                        subtitle = stringResource(R.string.ui_a4ed4ccff8),
                        onClick = { openedDocument = LegalDocumentId.TERMS },
                    )
                    LegalLinkRow(
                        icon = Icons.Rounded.PrivacyTip,
                        title = stringResource(R.string.ui_14862f7224),
                        subtitle = stringResource(R.string.ui_e4a6978a9b),
                        onClick = { openedDocument = LegalDocumentId.PRIVACY },
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            Text(
                stringResource(R.string.ui_5426ca56ab),
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(14.dp))
            Button(
                onClick = onAgree,
                enabled = !accepting,
                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                shape = MaterialTheme.shapes.medium,
            ) {
                if (accepting) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                }
                Text(stringResource(R.string.ui_b812e8fecc), fontWeight = FontWeight.SemiBold)
            }
            if (!error.isNullOrBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
            }
        }
    }

    openedDocument?.let { document ->
        LegalDocumentsDialog(initialDocument = document, onClose = { openedDocument = null })
    }
}

@Composable
private fun LegalLinkRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
    ) {
        Icon(icon, contentDescription = null)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
