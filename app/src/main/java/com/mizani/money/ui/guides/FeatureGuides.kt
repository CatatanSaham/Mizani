package com.mizani.money.ui.guides

import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import com.mizani.money.ui.components.Spacing

data class FeatureGuideStep(
    val targetId: String,
    val title: String,
    val explanation: String,
)

data class FeatureGuide(
    val id: String,
    val title: String,
    val summary: String,
    val route: String,
    val steps: List<FeatureGuideStep>,
)

object FeatureGuides {
    val all = listOf(
        FeatureGuide(
            id = "home",
            title = "Home",
            summary = "Read your overview and find the next useful action.",
            route = "home",
            steps = listOf(
                FeatureGuideStep("home.period", "Choose a period", "Change the date range to see the time period used by your Home summary."),
                FeatureGuideStep("home.actions", "Record or import", "Add income, an expense or a transfer, or review a mobile-money confirmation."),
                FeatureGuideStep("home.wallets", "Check your wallets", "Open Wallets to see how each current balance is derived from its starting balance and recorded activity."),
            ),
        ),
        FeatureGuide(
            id = "activity",
            title = "Activity and transactions",
            summary = "Search, filter, review and correct recorded activity.",
            route = "transactions",
            steps = listOf(
                FeatureGuideStep("activity.search", "Find a transaction", "Search notes, payees, wallet names, categories and amounts. Search stays on this device."),
                FeatureGuideStep("activity.filters", "Narrow the list", "Choose a date range or open Filters to narrow results by type, wallet, category or amount."),
                FeatureGuideStep("activity.records", "Review your activity", "Check the totals here, then tap a transaction below to inspect or edit it. Deletion is reversible, and balances recalculate from active records."),
            ),
        ),
        FeatureGuide(
            id = "wallets",
            title = "Wallets and balances",
            summary = "Understand cash, mobile-money and bank balances.",
            route = "wallets",
            steps = listOf(
                FeatureGuideStep("wallets.visibility", "Protect balances", "Balance visibility is protected by your app PIN or enabled biometrics."),
                FeatureGuideStep("wallets.total", "Understand the total", "A current balance combines its starting balance with saved activity. Transfers between your wallets do not change the combined total."),
                FeatureGuideStep("wallets.rows", "Inspect a wallet", "Open a wallet for its signed breakdown. Reconciliation adds a dated adjustment and keeps earlier transactions unchanged."),
            ),
        ),
        FeatureGuide(
            id = "mobile-money-import",
            title = "Import a mobile-money message",
            summary = "Review a confirmation before it becomes a transaction.",
            route = "import-message",
            steps = listOf(
                FeatureGuideStep(
                    "import.provider",
                    "Select a provider",
                    "Open Provider hint, search for the network, then select it. Leave Detect automatically selected if the message already names its provider.",
                ),
                FeatureGuideStep("import.message", "Paste or share the message", "The message is parsed on this device. Mizani does not read SMS in the background or save the original text."),
                FeatureGuideStep("import.review", "Review before saving", "Check the suggested type, wallet, amount, fee and date on the next screen before saving."),
            ),
        ),
        FeatureGuide(
            id = "insights",
            title = "Insights and Money Outlook",
            summary = "Understand the estimates and trends behind your summaries.",
            route = "insights",
            steps = listOf(
                FeatureGuideStep("insights.outlook", "Read Money Outlook", "This local estimate uses liquid wallet balances, recorded spending and eligible commitments. Expected income is excluded."),
                FeatureGuideStep("insights.spending", "Review spending", "Category spending is based on active ledger entries and linked refunds for the selected period."),
                FeatureGuideStep("insights.cashflow", "Check cash flow", "Compare recorded income and expenses across months. Mizani needs enough history before drawing a trend."),
            ),
        ),
        FeatureGuide(
            id = "commitments",
            title = "Bills and commitments",
            summary = "Plan upcoming costs and link payments you already recorded.",
            route = "commitments",
            steps = listOf(
                FeatureGuideStep(
                    "commitments.tabs",
                    "Choose a section",
                    "One-off bills are single payments. Recurring schedules repeat on a pattern and only remind you - they never change your balance on their own.",
                ),
                FeatureGuideStep(
                    "commitments.recurring",
                    "Understand recurring schedules",
                    "A schedule is a reminder and a forecast. When the money actually moves, record the payment; Mizani only changes balances from recorded activity.",
                ),
                FeatureGuideStep(
                    "commitments.add",
                    "Add a bill or schedule",
                    "Use the add action to create a one-off bill or a repeating item. Foreign-currency targets use a saved reference rate.",
                ),
                FeatureGuideStep(
                    "commitments.records",
                    "Link a recorded payment",
                    "Link an existing expense to update a bill's progress without creating a duplicate ledger entry.",
                ),
            ),
        ),
        FeatureGuide(
            id = "debts",
            title = "Debts",
            summary = "Track what you owe and the payments made against it.",
            route = "debts",
            steps = listOf(
                FeatureGuideStep("debts.summary", "Read the debt summary", "Debt wallets track amounts owed separately from money available in cash, bank or mobile-money wallets."),
                FeatureGuideStep("debts.add", "Add a debt", "Record the original amount and terms so you can review the outstanding balance later."),
                FeatureGuideStep("debts.records", "Review payments", "Record a payment against the debt and check its updated outstanding amount."),
            ),
        ),
        FeatureGuide(
            id = "investments",
            title = "Investments",
            summary = "Keep manual snapshots of holdings without duplicating ledger activity.",
            route = "investments",
            steps = listOf(
                FeatureGuideStep("investments.summary", "Read your portfolio", "Portfolio values are manual estimates. Mizani does not connect to providers or place orders."),
                FeatureGuideStep("investments.add", "Add a holding", "Enter the asset, where it is held, cost basis and latest value."),
                FeatureGuideStep("investments.records", "Update a value", "Edit a holding when you want to record a new snapshot. This does not create income or expense activity."),
            ),
        ),
        FeatureGuide(
            id = "categories",
            title = "Categories",
            summary = "Keep income and expense labels organized for reporting.",
            route = "categories",
            steps = listOf(
                FeatureGuideStep("categories.types", "Choose a category type", "Switch between income and expense categories; existing transactions keep their references."),
                FeatureGuideStep("categories.list", "Organize the list", "Reorder or archive categories to keep your picker useful. Archived categories remain in past records."),
                FeatureGuideStep("categories.add", "Create a category", "Use a clear name so later search and Insights are easier to understand."),
            ),
        ),
    )

    fun byId(id: String): FeatureGuide? = all.firstOrNull { it.id == id }
}

/** Small, on-demand help entry for feature toolbars. */
@Composable
fun GuideHelpAction(featureName: String, onClick: () -> Unit) {
    IconButton(onClick = onClick) {
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.HelpOutline,
            contentDescription = "Help with $featureName",
        )
    }
}

typealias GuideTargetReporter = (targetId: String, boundsInRoot: Rect) -> Unit

val LocalGuideTargetReporter = staticCompositionLocalOf<GuideTargetReporter?> { null }
val LocalActiveGuideTarget = compositionLocalOf<String?> { null }

/** Reports target and overlay positions in the same Compose root for reliable cutout geometry. */
fun Modifier.guideTarget(targetId: String): Modifier = composed {
    val reporter = LocalGuideTargetReporter.current
    val activeTargetId = LocalActiveGuideTarget.current
    val bringIntoViewRequester = remember { BringIntoViewRequester() }
    var isPlaced by remember { mutableStateOf(false) }
    var lastBoundsInRoot by remember { mutableStateOf<Rect?>(null) }
    if (reporter == null) {
        this
    } else {
        LaunchedEffect(activeTargetId == targetId, isPlaced) {
            if (activeTargetId == targetId && isPlaced) {
                // Scroll the active step into view before reporting its final bounds. This is
                // especially useful for targets lower in a long feature screen.
                bringIntoViewRequester.bringIntoView()
                withFrameNanos { }
                lastBoundsInRoot?.let { reporter(targetId, it) }
            }
        }
        this
            .bringIntoViewRequester(bringIntoViewRequester)
            .onGloballyPositioned { coordinates: LayoutCoordinates ->
                val bounds = coordinates.boundsInRoot()
                // During Navigation transitions a retained destination can briefly report a
                // zero-sized layout. Never let that transient value erase a valid highlight.
                if (bounds.isEmpty) return@onGloballyPositioned
                lastBoundsInRoot = bounds
                reporter(targetId, bounds)
                if (!isPlaced) isPlaced = true
            }
            .testTag("guide-target-$targetId")
    }
}

@Composable
fun GuidedTourOverlay(
    guide: FeatureGuide,
    stepIndex: Int,
    targetBoundsInRoot: Rect?,
    overlayBoundsInRoot: Rect,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onExit: () -> Unit,
) {
    val step = guide.steps[stepIndex]
    // Convert root-relative bounds into this overlay's own space and intersect. Clamping each
    // edge independently used to collapse an oversized or partly offscreen target into a
    // full-screen rectangle, which erased the entire scrim and left no visible spotlight.
    val localTarget = targetBoundsInRoot?.let { target ->
        target.translate(-overlayBoundsInRoot.left, -overlayBoundsInRoot.top)
            .intersect(Rect(0f, 0f, overlayBoundsInRoot.width, overlayBoundsInRoot.height))
            .takeUnless { it.isEmpty || it.width < 1f || it.height < 1f }
    }
    // Move the coach card out of the spotlight's way when the target sits in the lower half.
    val cardAtTop = localTarget != null &&
        (localTarget.top + localTarget.bottom) / 2f > overlayBoundsInRoot.height / 2f
    val targetLeft = remember(guide.id) { Animatable(localTarget?.left ?: 0f) }
    val targetTop = remember(guide.id) { Animatable(localTarget?.top ?: 0f) }
    val targetWidth = remember(guide.id) { Animatable(localTarget?.width ?: 0f) }
    val targetHeight = remember(guide.id) { Animatable(localTarget?.height ?: 0f) }
    LaunchedEffect(localTarget) {
        val target = localTarget ?: return@LaunchedEffect
        coroutineScope {
            launch { targetLeft.animateTo(target.left, tween(durationMillis = 220)) }
            launch { targetTop.animateTo(target.top, tween(durationMillis = 220)) }
            launch { targetWidth.animateTo(target.width, tween(durationMillis = 220)) }
            launch { targetHeight.animateTo(target.height, tween(durationMillis = 220)) }
        }
    }
    val animatedTarget = localTarget?.let {
        Rect(
            left = targetLeft.value,
            top = targetTop.value,
            right = targetLeft.value + targetWidth.value,
            bottom = targetTop.value + targetHeight.value,
        )
    }
    val highlightColor = MaterialTheme.colorScheme.primary

    Box(
        modifier = Modifier
            .fillMaxSize()
            .semantics { contentDescription = "${guide.title} guide" },
    ) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .semantics {
                    contentDescription = if (localTarget != null) {
                        "Guide target highlighted: ${step.targetId}"
                    } else {
                        "Preparing guide highlight: ${step.targetId}"
                    }
                    liveRegion = LiveRegionMode.Polite
                },
        ) {
            if (animatedTarget != null) {
                drawGuideScrim(animatedTarget, highlightColor)
            } else {
                // Keep page context visible while a newly selected target is being measured.
                drawGuideScrim(null, highlightColor)
            }
        }

        Surface(
            modifier = Modifier
                .align(if (cardAtTop) Alignment.TopCenter else Alignment.BottomCenter)
                .widthIn(max = 560.dp)
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 12.dp)
                .navigationBarsPadding(),
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 6.dp,
            shadowElevation = 12.dp,
        ) {
            Column(
                modifier = Modifier.padding(Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Step ${stepIndex + 1} of ${guide.steps.size}",
                        modifier = Modifier
                            .weight(1f)
                            .semantics {
                                contentDescription = "Step ${stepIndex + 1} of ${guide.steps.size}"
                                liveRegion = LiveRegionMode.Polite
                            },
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    TextButton(onClick = onExit) { Text("Exit guide") }
                }
                Text(step.title, style = MaterialTheme.typography.titleLarge)
                Text(
                    step.explanation,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    guide.steps.indices.forEach { index ->
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(4.dp)
                                .clip(MaterialTheme.shapes.small)
                                .background(
                                    if (index <= stepIndex) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.surfaceVariant,
                                ),
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.End,
                ) {
                    TextButton(onClick = onPrevious, enabled = stepIndex > 0) { Text("Back") }
                    Spacer(Modifier.width(Spacing.xs))
                    // Navigation must never depend on measurement; a missing target used to
                    // trap the user on a step whose Next button stayed disabled forever.
                    Button(onClick = onNext) {
                        Text(if (stepIndex == guide.steps.lastIndex) "Finish" else "Next")
                    }
                }
            }
        }
    }
}

private fun DrawScope.drawGuideScrim(target: Rect?, highlightColor: Color) {
    val scrimColor = Color.Black.copy(alpha = 0.42f)
    if (target == null) {
        // Page context stays visible while the next target is being measured.
        drawRect(color = scrimColor)
        return
    }
    val cutoutRadius = 14.dp.toPx()
    val cutout = target.inflate(6.dp.toPx())
    val scrim = Path().apply {
        fillType = PathFillType.EvenOdd
        addRect(Rect(Offset.Zero, size))
        addRoundRect(RoundRect(cutout, cutoutRadius, cutoutRadius))
    }
    drawPath(path = scrim, color = scrimColor)
    drawRoundRect(
        color = highlightColor,
        topLeft = Offset(cutout.left, cutout.top),
        size = Size(cutout.width, cutout.height),
        cornerRadius = CornerRadius(cutoutRadius, cutoutRadius),
        style = Stroke(width = 2.dp.toPx()),
    )
}

private fun Rect.inflate(amount: Float) = Rect(
    left = left - amount,
    top = top - amount,
    right = right + amount,
    bottom = bottom + amount,
)
