package com.mizani.money.feature.settings

import com.mizani.money.R
import androidx.compose.ui.res.stringResource
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.BugReport
import androidx.compose.material.icons.rounded.Email
import androidx.compose.material.icons.rounded.Feedback
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mizani.money.BuildConfig
import com.mizani.money.core.legal.LegalDocuments
import com.mizani.money.ui.components.MizaniCard
import com.mizani.money.ui.components.MizaniPageContent
import com.mizani.money.ui.components.MizaniTopBar
import com.mizani.money.ui.components.Spacing
import com.mizani.money.ui.components.StatusBanner

enum class FeedbackTopic(
    val title: String,
    val subjectLabel: String,
) {
    SUGGESTION("Saran", "suggestion"),
    PROBLEM("Laporkan masalah", "problem report"),
    QUESTION("Pertanyaan", "question"),
    OTHER("Lainnya", "feedback"),
}

data class FeedbackValidationResult(
    val message: String? = null,
)

/** Builds the user-confirmed email handoff without adding a network client or app secret. */
object FeedbackComposer {
    const val MAX_MESSAGE_LENGTH = 4_000
    const val OFFICIAL_EMAIL = LegalDocuments.PRIVACY_CONTACT

    fun validate(topic: FeedbackTopic?, message: String): FeedbackValidationResult {
        if (topic == null) return FeedbackValidationResult("Pilih apa yang ingin kamu bagikan.")
        if (message.isBlank()) return FeedbackValidationResult("Tulis beberapa kata agar kami tahu cara membantu.")
        if (message.length > MAX_MESSAGE_LENGTH) {
            return FeedbackValidationResult("Batasi masukanmu hingga $MAX_MESSAGE_LENGTH karakter.")
        }
        return FeedbackValidationResult()
    }

    fun subject(topic: FeedbackTopic): String = "Mizani feedback: ${topic.subjectLabel}"

    fun body(
        topic: FeedbackTopic,
        message: String,
        appVersion: String,
        androidVersion: String,
    ): String = buildString {
        appendLine(message.trim())
        appendLine()
        appendLine("---")
        appendLine("Topic: ${topic.subjectLabel}")
        appendLine("Mizani version: $appVersion")
        appendLine("Android version: $androidVersion")
        appendLine()
        append("Please do not reply with balances, transaction details, PINs, or backup passphrases.")
    }

    fun createIntent(
        topic: FeedbackTopic,
        message: String,
        appVersion: String,
        androidVersion: String,
    ): Intent = Intent(Intent.ACTION_SENDTO).apply {
        // Keep the data URI at the mailto scheme so email clients consume the standard extras.
        // Some clients accept the recipient from mailto:address but silently drop EXTRA_SUBJECT
        // and EXTRA_TEXT when the address is also embedded in the URI.
        data = Uri.parse("mailto:")
        putExtra(Intent.EXTRA_EMAIL, arrayOf(OFFICIAL_EMAIL))
        putExtra(Intent.EXTRA_SUBJECT, subject(topic))
        putExtra(Intent.EXTRA_TEXT, body(topic, message, appVersion, androidVersion))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FeedbackScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var selectedTopicName by rememberSaveable { mutableStateOf(FeedbackTopic.SUGGESTION.name) }
    var message by remember { mutableStateOf("") }
    var status by rememberSaveable { mutableStateOf<String?>(null) }
    var statusIsError by rememberSaveable { mutableStateOf(false) }
    val selectedTopic = FeedbackTopic.entries.firstOrNull { it.name == selectedTopicName }
        ?: FeedbackTopic.SUGGESTION

    fun openEmail() {
        val validation = FeedbackComposer.validate(selectedTopic, message)
        if (validation.message != null) {
            status = validation.message
            statusIsError = true
            return
        }

        val intent = FeedbackComposer.createIntent(
            topic = selectedTopic,
            message = message,
            appVersion = "${BuildConfig.VERSION_NAME} (build ${BuildConfig.VERSION_CODE})",
            androidVersion = android.os.Build.VERSION.RELEASE ?: "unknown",
        )
        if (intent.resolveActivity(context.packageManager) == null) {
            status = "Tidak ada aplikasi email di perangkat ini. Pasang satu untuk melanjutkan."
            statusIsError = true
            return
        }
        runCatching { context.startActivity(intent) }
            .onSuccess {
                status = "Aplikasi emailmu siap. Tinjau pesannya lalu ketuk Kirim."
                statusIsError = false
            }
            .onFailure {
                status = "Aplikasi email tidak bisa dibuka. Coba lagi untuk melanjutkan."
                statusIsError = true
            }
    }

    Column(Modifier.fillMaxSize()) {
        MizaniTopBar(title = "Kirim masukan", onBack = onBack)
        MizaniPageContent {
            MizaniCard(containerColor = MaterialTheme.colorScheme.primaryContainer) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Rounded.Feedback,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.size(30.dp),
                    )
                    Spacer(Modifier.width(Spacing.sm))
                    Text(
                        "Bantu bentuk Catatan Keuangan",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    "Beri tahu kami apa yang sudah baik, apa yang bisa lebih jelas, atau bagian mana yang membuatmu macet. Masukanmu dikirim ke tim Catatan Keuangan.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text("Apa yang ingin kamu bagikan?", style = MaterialTheme.typography.titleMedium)
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    FeedbackTopic.entries.forEach { topic ->
                        FilterChip(
                            selected = topic == selectedTopic,
                            onClick = {
                                selectedTopicName = topic.name
                                status = null
                            },
                            label = { Text(topic.title) },
                            leadingIcon = {
                                Icon(
                                    imageVector = when (topic) {
                                        FeedbackTopic.SUGGESTION -> Icons.Rounded.Lightbulb
                                        FeedbackTopic.PROBLEM -> Icons.Rounded.BugReport
                                        FeedbackTopic.QUESTION -> Icons.AutoMirrored.Rounded.HelpOutline
                                        FeedbackTopic.OTHER -> Icons.Rounded.Feedback
                                    },
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                            },
                        )
                    }
                }
            }

            OutlinedTextField(
                value = message,
                onValueChange = {
                    if (it.length <= FeedbackComposer.MAX_MESSAGE_LENGTH) {
                        message = it
                        if (statusIsError) status = null
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.ui_4284d1d7a5)) },
                placeholder = { Text(stringResource(R.string.ui_69ffbb8e90)) },
                supportingText = {
                    Text(
                        "${message.length}/${FeedbackComposer.MAX_MESSAGE_LENGTH}",
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.End,
                    )
                },
                minLines = 6,
                maxLines = 10,
            )

            MizaniCard {
                Row(verticalAlignment = Alignment.Top) {
                    Icon(
                        Icons.Rounded.Email,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(22.dp),
                    )
                    Spacer(Modifier.width(Spacing.sm))
                    Text(
                        "Catatan Keuangan membuka aplikasi email dengan alamat dan pesan yang sudah terisi. Tinjau sebelum mengirim. Pengiriman dan filter spam diatur oleh penyedia email kamu.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.height(Spacing.sm))
                Text(
                    "Demi privasimu, jangan sertakan saldo, detail transaksi, PIN, atau frasa sandi cadangan.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (status != null) {
                StatusBanner(text = status.orEmpty(), isError = statusIsError)
            }

            Button(
                onClick = ::openEmail,
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.medium,
            ) {
                Icon(Icons.AutoMirrored.Rounded.Send, contentDescription = null)
                Spacer(Modifier.width(Spacing.sm))
                Text(stringResource(R.string.ui_bc54c27885))
            }
        }
    }
}
