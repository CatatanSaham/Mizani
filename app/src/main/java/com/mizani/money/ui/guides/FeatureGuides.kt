package com.mizani.money.ui.guides

import com.mizani.money.UiStr
import com.mizani.money.R
import androidx.compose.ui.res.stringResource
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
            title = UiStr.s(R.string.ui_70f8bb9a8a),
            summary = UiStr.s(R.string.ui_9eb8b365ec),
            route = "home",
            steps = listOf(
                FeatureGuideStep("home.period", "Choose a period", UiStr.s(R.string.ui_b45a36d01d)),
                FeatureGuideStep("home.actions", UiStr.s(R.string.ui_17f40256d3), UiStr.s(R.string.ui_8c9acb6fbd)),
                FeatureGuideStep("home.wallets", UiStr.s(R.string.ui_15d30b98d5), UiStr.s(R.string.ui_ae82d0d823)),
            ),
        ),
        FeatureGuide(
            id = "activity",
            title = UiStr.s(R.string.ui_f6bbf9b0f8),
            summary = UiStr.s(R.string.ui_adbb992f98),
            route = "transactions",
            steps = listOf(
                FeatureGuideStep("activity.search", UiStr.s(R.string.ui_19d6038f88), UiStr.s(R.string.ui_7a69c9b648)),
                FeatureGuideStep("activity.filters", UiStr.s(R.string.ui_c38f1b9ff3), UiStr.s(R.string.ui_effe7d11f2)),
                FeatureGuideStep("activity.records", UiStr.s(R.string.ui_6b126e12e8), UiStr.s(R.string.ui_45556db5b6)),
            ),
        ),
        FeatureGuide(
            id = "wallets",
            title = UiStr.s(R.string.ui_a6965c4605),
            summary = UiStr.s(R.string.ui_966bea7cde),
            route = "wallets",
            steps = listOf(
                FeatureGuideStep("wallets.visibility", UiStr.s(R.string.ui_a649953643), UiStr.s(R.string.ui_a598f2e5ac)),
                FeatureGuideStep("wallets.total", UiStr.s(R.string.ui_6829957221), UiStr.s(R.string.ui_eabcb0ef36)),
                FeatureGuideStep("wallets.rows", UiStr.s(R.string.ui_4621b815c0), UiStr.s(R.string.ui_d299fec863)),
            ),
        ),
        FeatureGuide(
            id = "mobile-money-import",
            title = UiStr.s(R.string.ui_76bacbb550),
            summary = UiStr.s(R.string.ui_54b9e04738),
            route = "import-message",
            steps = listOf(
                FeatureGuideStep(
                    "import.provider",
                    UiStr.s(R.string.ui_7829c2bdd0),
                    UiStr.s(R.string.ui_f0eb681597),
                ),
                FeatureGuideStep("import.message", UiStr.s(R.string.ui_665b75b1f4), UiStr.s(R.string.ui_e0ff2ec4b9)),
                FeatureGuideStep("import.review", UiStr.s(R.string.ui_6f92b7e4df), UiStr.s(R.string.ui_f1f2dc2a3d)),
            ),
        ),
        FeatureGuide(
            id = "insights",
            title = UiStr.s(R.string.ui_53dadff4ef),
            summary = UiStr.s(R.string.ui_c52567fb2c),
            route = "insights",
            steps = listOf(
                FeatureGuideStep("insights.outlook", UiStr.s(R.string.ui_8c07506efc), UiStr.s(R.string.ui_51240dc795)),
                FeatureGuideStep("insights.spending", UiStr.s(R.string.ui_8a230bbab1), UiStr.s(R.string.ui_fddfef03c8)),
                FeatureGuideStep("insights.cashflow", UiStr.s(R.string.ui_cb906bda11), UiStr.s(R.string.ui_bbe726b052)),
            ),
        ),
        FeatureGuide(
            id = "commitments",
            title = UiStr.s(R.string.ui_2715438949),
            summary = UiStr.s(R.string.ui_30f0ab1cb7),
            route = "commitments",
            steps = listOf(
                FeatureGuideStep(
                    "commitments.tabs",
                    UiStr.s(R.string.ui_87f5255ac0),
                    UiStr.s(R.string.ui_ae01b7b9a2),
                ),
                FeatureGuideStep(
                    "commitments.recurring",
                    UiStr.s(R.string.ui_942026267f),
                    UiStr.s(R.string.ui_1231bd1553),
                ),
                FeatureGuideStep(
                    "commitments.add",
                    UiStr.s(R.string.ui_027f6b9763),
                    UiStr.s(R.string.ui_fb739f135a),
                ),
                FeatureGuideStep(
                    "commitments.records",
                    UiStr.s(R.string.ui_48f5ff2fe9),
                    UiStr.s(R.string.ui_a9dea3fb60),
                ),
            ),
        ),
        FeatureGuide(
            id = "debts",
            title = UiStr.s(R.string.ui_787aab25f6),
            summary = UiStr.s(R.string.ui_65845a065b),
            route = "debts",
            steps = listOf(
                FeatureGuideStep("debts.summary", UiStr.s(R.string.ui_d10d11817e), UiStr.s(R.string.ui_4f17d77402)),
                FeatureGuideStep("debts.add", UiStr.s(R.string.ui_59cdbe5227), UiStr.s(R.string.ui_a3558c987d)),
                FeatureGuideStep("debts.records", UiStr.s(R.string.ui_50c69cd70d), UiStr.s(R.string.ui_bbb4e8cd83)),
            ),
        ),
        FeatureGuide(
            id = "investments",
            title = UiStr.s(R.string.ui_5de64aff09),
            summary = UiStr.s(R.string.ui_79a7610c4b),
            route = "investments",
            steps = listOf(
                FeatureGuideStep("investments.summary", UiStr.s(R.string.ui_66cb2dab9d), UiStr.s(R.string.ui_18f1748f21)),
                FeatureGuideStep("investments.add", UiStr.s(R.string.ui_e8cbedd2f3), UiStr.s(R.string.ui_3c56262c70)),
                FeatureGuideStep("investments.records", UiStr.s(R.string.ui_b82c2f4f1b), UiStr.s(R.string.ui_095bf282fa)),
            ),
        ),
        FeatureGuide(
            id = "categories",
            title = UiStr.s(R.string.ui_6ccb60071b),
            summary = UiStr.s(R.string.ui_50a1caf511),
            route = "categories",
            steps = listOf(
                FeatureGuideStep("categories.types", UiStr.s(R.string.ui_b52c67084c), UiStr.s(R.string.ui_db8da7eee6)),
                FeatureGuideStep("categories.list", UiStr.s(R.string.ui_ba323a4fca), UiStr.s(R.string.ui_d50524d2e5)),
                FeatureGuideStep("categories.add", UiStr.s(R.string.ui_a9a0451350), UiStr.s(R.string.ui_bff4e2559a)),
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
                    TextButton(onClick = onExit) { Text(stringResource(R.string.ui_fc14936197)) }
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
                    TextButton(onClick = onPrevious, enabled = stepIndex > 0) { Text(stringResource(R.string.ui_b52b36b726)) }
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
