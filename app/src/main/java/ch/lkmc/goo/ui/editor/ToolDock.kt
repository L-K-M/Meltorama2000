package ch.lkmc.goo.ui.editor

import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.BlurOn
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Cached
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.CompareArrows
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Dehaze
import androidx.compose.material.icons.filled.Details
import androidx.compose.material.icons.filled.FilterTiltShift
import androidx.compose.material.icons.filled.Flip
import androidx.compose.material.icons.filled.Gesture
import androidx.compose.material.icons.filled.HideImage
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.OpenWith
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RotateLeft
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.SouthEast
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import ch.lkmc.goo.R
import ch.lkmc.goo.engine.core.BrushTool
import ch.lkmc.goo.ui.components.ChromeIconButton
import ch.lkmc.goo.ui.components.chromePanel
import ch.lkmc.goo.ui.theme.MeltOnDarkDim
import ch.lkmc.goo.ui.theme.MeltVoid
import ch.lkmc.goo.ui.theme.NeonAmber
import ch.lkmc.goo.ui.theme.NeonCyan
import ch.lkmc.goo.ui.theme.NeonLime
import ch.lkmc.goo.ui.theme.NeonMagenta
import ch.lkmc.goo.ui.theme.NeonTangerine
import ch.lkmc.goo.ui.theme.NeonViolet

/**
 * The editor's bottom tray: four mode tabs (Brush / Levers / Lenses /
 * GOOvies) hosting the palette, the global rig, the lens bench, or the
 * strip. On the brush tab the palette is a family grid and everything
 * below it is contextual — only what the active tool can actually use.
 * Collapses into [ToolPuck] so the canvas gets the whole screen back.
 */
@Composable
fun ToolDock(
    panel: EditorPanel,
    leversHot: Boolean,
    onTabSelect: (EditorPanel) -> Unit,
    onCollapse: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable (EditorPanel) -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            // The tray floats over the canvas, and the canvas paints on
            // touch: without a hit target of its own, every dead spot on
            // the plate — label texts, bead gaps, the inset strip — would
            // pass the finger through to beginStroke underneath. Awaiting
            // the down (same trick as the leaving scrim) makes the whole
            // plate opaque to touch while leaving its beads and sliders,
            // which hit-test first, exactly as they were.
            .pointerInput(Unit) {
                awaitEachGesture { awaitFirstDown(requireUnconsumed = false) }
            }
            .chromePanel(RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp))
            .navigationBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            DockTab(
                icon = Icons.Filled.Brush,
                label = stringResource(R.string.dock_tab_brush),
                color = NeonMagenta,
                selected = panel == EditorPanel.BRUSH,
                dot = false,
                onClick = { onTabSelect(EditorPanel.BRUSH) },
            )
            DockTab(
                icon = Icons.Filled.Tune,
                label = stringResource(R.string.dock_tab_levers),
                color = NeonCyan,
                selected = panel == EditorPanel.LEVERS,
                // Levers are document state, not a mode: the dot says
                // "something is off-center" even from another tab.
                dot = leversHot,
                onClick = { onTabSelect(EditorPanel.LEVERS) },
            )
            DockTab(
                icon = Icons.Filled.FilterTiltShift,
                label = stringResource(R.string.dock_tab_lenses),
                color = NeonViolet,
                selected = panel == EditorPanel.FUNHOUSE,
                dot = false,
                onClick = { onTabSelect(EditorPanel.FUNHOUSE) },
            )
            DockTab(
                icon = Icons.Filled.Movie,
                label = stringResource(R.string.dock_tab_goovies),
                color = NeonAmber,
                selected = panel == EditorPanel.GOOVIE,
                dot = false,
                onClick = { onTabSelect(EditorPanel.GOOVIE) },
            )
            Spacer(modifier = Modifier.weight(1f))
            val haptics = LocalHapticFeedback.current
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = stringResource(R.string.dock_collapse),
                tint = MeltOnDarkDim,
                modifier = Modifier
                    .minimumInteractiveComponentSize()
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onCollapse()
                        },
                    )
                    .padding(8.dp),
            )
        }
        AnimatedContent(
            targetState = panel,
            transitionSpec = {
                val springIn = spring(
                    dampingRatio = Spring.DampingRatioMediumBouncy,
                    stiffness = Spring.StiffnessMediumLow,
                    visibilityThreshold = IntOffset.VisibilityThreshold,
                )
                // `using null` kills the default SizeTransform: the tray
                // floats over the canvas (the GLSurfaceView never
                // re-measures), but animating the height would still
                // jitter every panel's content mid-spring. The height
                // snaps; content slides.
                (slideInVertically(springIn) { it / 3 } + fadeIn()) togetherWith
                    (slideOutVertically { it / 3 } + fadeOut()) using null
            },
            label = "dockPanelSwap",
        ) { which ->
            content(which)
        }
    }
}

/** The collapsed dock: one bead wearing the active mode's neon. */
@Composable
fun ToolPuck(
    panel: EditorPanel,
    tool: BrushTool,
    onExpand: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val (icon, color) = when (panel) {
        EditorPanel.BRUSH -> tool.icon() to tool.neonColor()
        EditorPanel.LEVERS -> Icons.Filled.Tune to NeonCyan
        EditorPanel.FUNHOUSE -> Icons.Filled.FilterTiltShift to NeonViolet
        EditorPanel.GOOVIE -> Icons.Filled.Movie to NeonAmber
    }
    ChromeIconButton(
        icon = icon,
        contentDescription = stringResource(R.string.dock_expand),
        color = color,
        selected = true,
        size = 56.dp,
        onClick = onExpand,
        modifier = modifier,
    )
}

/**
 * One mode tab: an icon pill that spells its name out only while
 * selected — four spelled-out names plus the chevron would not fit a
 * 360dp tray, and the selected tab is the one being read.
 */
@Composable
private fun DockTab(
    icon: ImageVector,
    label: String,
    color: Color,
    selected: Boolean,
    dot: Boolean,
    onClick: () -> Unit,
) {
    val background by animateColorAsState(
        targetValue = if (selected) color else Color.Transparent,
        label = "dockTabBackground",
    )
    // The content rides the same animation as the plate behind it — a
    // snapped switch leaves a dark icon on a still-transparent pill for
    // the first frames of the spring.
    val content by animateColorAsState(
        targetValue = if (selected) MeltVoid else MeltOnDarkDim,
        label = "dockTabContent",
    )
    val haptics = LocalHapticFeedback.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .minimumInteractiveComponentSize()
            .clip(RoundedCornerShape(50))
            .background(background)
            .semantics { this.selected = selected }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Tab,
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onClick()
                },
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Box {
            Icon(
                imageVector = icon,
                // Icon-only while unselected, so the name must ride the
                // icon; while selected the pill spells it out instead.
                contentDescription = if (selected) null else label,
                tint = content,
                modifier = Modifier.size(20.dp),
            )
            // Off-center levers glow through whatever tab is up. On its
            // own (selected) tab the pill already burns in this color, so
            // the dot only draws where it can be seen.
            if (dot && !selected) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(6.dp)
                        .background(color, CircleShape),
                )
            }
        }
        AnimatedVisibility(visible = selected, enter = expandHorizontally() + fadeIn(), exit = shrinkHorizontally() + fadeOut()) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = content,
                maxLines = 1,
                modifier = Modifier.padding(start = 6.dp),
            )
        }
    }
}

/**
 * The brush tab: the palette as a family grid (names live on the strip —
 * twenty lookalike labels under the beads are noise), then the contextual
 * strip with everything the ACTIVE tool can use: its name, the stamp
 * fanners (Mirror / Kaleido / Portals — hidden for Pins, which stamps
 * nothing), Punch and Update, Fusion's photo actions, and the size and
 * strength sliders. Nothing scrolls.
 */
@Composable
fun BrushDockContent(
    tool: BrushTool,
    mirrored: Boolean,
    sectors: Int,
    /** A keyframe is selected, so Rewind has something to read from. */
    rewindReady: Boolean,
    portalsOn: Boolean,
    /** 0 = link live or off; 1 = waiting for ring A; 2 = waiting for B. */
    portalsPlacing: Int,
    radius: Float,
    strength: Float,
    showFusionActions: Boolean,
    fusionLoading: Boolean,
    keyframeCount: Int,
    /** 1-based keyframe the Update bead would re-pin; 0 hides the bead. */
    updateKeyframe: Int,
    onToolChange: (BrushTool) -> Unit,
    onMirrorToggle: () -> Unit,
    onCycleSectors: () -> Unit,
    onPortalsToggle: () -> Unit,
    onRadiusChange: (Float) -> Unit,
    onStrengthChange: (Float) -> Unit,
    onAdjustingChange: (Boolean) -> Unit,
    onPunch: () -> Unit,
    onRepunch: () -> Unit,
    onFusionPick: () -> Unit,
    onFusionRemove: () -> Unit,
) {
    // A slider dragged off-screen (tab swap, tray collapse) never delivers
    // its onValueChangeFinished — clear the adjusting flag on the way out.
    DisposableEffect(Unit) {
        onDispose { onAdjustingChange(false) }
    }
    // Saveable for the same reason the tray's own state is: a rotation
    // mid-read must not swallow the dialog.
    var showInfo by rememberSaveable { mutableStateOf(false) }
    if (showInfo) {
        AlertDialog(
            onDismissRequest = { showInfo = false },
            title = { Text(stringResource(tool.labelRes())) },
            text = {
                Column(
                    // Seven lines at a 200% font scale outgrow a dialog;
                    // the glossary scrolls rather than clips.
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = stringResource(tool.infoRes()),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    // Only the beads actually on the strip right now:
                    // explaining a control that is not there is how a
                    // glossary lies.
                    val beadLines = buildList {
                        if (!tool.isPinWarp) {
                            add(R.string.info_mirror)
                            add(R.string.info_sectors)
                            add(R.string.info_portals)
                        }
                        if (showFusionActions) add(R.string.info_fusion)
                        add(R.string.info_punch)
                        if (updateKeyframe > 0) add(R.string.info_update)
                    }
                    beadLines.forEach { line ->
                        Text(
                            text = stringResource(line),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showInfo = false }) {
                    Text(stringResource(R.string.about_close))
                }
            },
        )
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        BoxWithConstraints {
            val rows = toolDockRows()
            val widest = rows.maxOf { it.size }
            // Every bead of the widest row must fit with no scroll — the
            // whole point of the grid. The slot squeezes below the stock
            // 48dp minimum only when the tray is narrower than the row
            // wants (348dp of slots on a 360dp screen leaves none), and
            // never below the bead itself.
            val slot = (maxWidth / widest).coerceIn(BEAD_SIZE, 44.dp)
            CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides slot) {
                Column {
                    rows.forEach { row ->
                        Row {
                            row.forEach { entry ->
                                ChromeIconButton(
                                    icon = entry.icon(),
                                    contentDescription = stringResource(entry.labelRes()),
                                    color = entry.neonColor(),
                                    selected = tool == entry,
                                    selectable = true,
                                    size = BEAD_SIZE,
                                    // Rewind reads FROM a keyframe, so
                                    // without one selected there is
                                    // nothing for it to paint; greying
                                    // the bead reuses the strip's
                                    // selection instead of adding a
                                    // second picker.
                                    enabled = when (entry) {
                                        BrushTool.FUSE -> !fusionLoading
                                        BrushTool.REWIND -> rewindReady
                                        else -> true
                                    },
                                    onClick = { onToolChange(entry) },
                                )
                            }
                        }
                    }
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    // A mode that silently eats the next two taps has to
                    // say so where the user is looking — the strip's name
                    // slot. Except under Pins, whose overlay owns the
                    // canvas: a prompt to tap rings no tap can place is
                    // worse than none.
                    text = stringResource(
                        when (if (tool.isPinWarp) 0 else portalsPlacing) {
                            1 -> R.string.tool_portals_place_a
                            2 -> R.string.tool_portals_place_b
                            else -> tool.labelRes()
                        },
                    ),
                    style = MaterialTheme.typography.titleSmall,
                    color = tool.neonColor(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    // fill=false: the name yields to the (i) beside it
                    // instead of shoving it into the beads, and the (i)
                    // rides the name's end instead of drifting right.
                    modifier = Modifier.weight(1f, fill = false),
                )
                // The glossary, on the name it glosses: what this brush
                // does, and what the beads beside it do. Quiet ink, not a
                // chrome bead — it is a label, not an instrument.
                CompositionLocalProvider(
                    LocalMinimumInteractiveComponentSize provides STRIP_SLOT,
                ) {
                    val haptics = LocalHapticFeedback.current
                    Icon(
                        imageVector = Icons.Outlined.Info,
                        contentDescription = stringResource(R.string.dock_tool_info),
                        tint = MeltOnDarkDim,
                        modifier = Modifier
                            .minimumInteractiveComponentSize()
                            .clip(CircleShape)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                role = Role.Button,
                                onClick = {
                                    haptics.performHapticFeedback(
                                        HapticFeedbackType.TextHandleMove,
                                    )
                                    showInfo = true
                                },
                            )
                            .padding(9.dp),
                    )
                }
            }
            CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides STRIP_SLOT) {
                // Pins is the one row that is a mode, not a brush: it
                // emits no stamps, so the stamp-fanning modifiers would
                // be dead switches while it is up.
                if (!tool.isPinWarp) {
                    ChromeIconButton(
                        icon = Icons.Filled.Flip,
                        contentDescription = stringResource(R.string.tool_mirror),
                        color = NeonViolet,
                        selected = mirrored,
                        selectable = true,
                        size = BEAD_SIZE,
                        onClick = onMirrorToggle,
                    )
                    // Beside Mirror because the two compose: sectors alone
                    // give a pinwheel, sectors with Mirror give the mirror
                    // lines a real kaleidoscope has.
                    BadgedBead(badge = if (sectors > 1) "$sectors" else null, color = NeonTangerine) {
                        ChromeIconButton(
                            icon = Icons.Filled.Details,
                            contentDescription = if (sectors > 1) {
                                stringResource(R.string.tool_sectors_count, sectors)
                            } else {
                                stringResource(R.string.tool_sectors)
                            },
                            color = NeonTangerine,
                            selected = sectors > 1,
                            selectable = true,
                            size = BEAD_SIZE,
                            onClick = onCycleSectors,
                        )
                    }
                    // Portals sits with the other two stamp fanners,
                    // because that is what it is: Mirror without the
                    // assumption that the relation is centred, vertical
                    // and reflective.
                    ChromeIconButton(
                        icon = Icons.Filled.SwapHoriz,
                        contentDescription = stringResource(R.string.tool_portals),
                        color = NeonMagenta,
                        selected = portalsOn,
                        selectable = true,
                        size = BEAD_SIZE,
                        onClick = onPortalsToggle,
                    )
                }
                if (showFusionActions) {
                    ChromeIconButton(
                        icon = Icons.Filled.Collections,
                        contentDescription = stringResource(R.string.fusion_change_photo),
                        color = NeonViolet,
                        selected = false,
                        enabled = !fusionLoading,
                        size = BEAD_SIZE,
                        onClick = onFusionPick,
                    )
                    ChromeIconButton(
                        icon = Icons.Filled.HideImage,
                        contentDescription = stringResource(R.string.fusion_remove_photo),
                        color = NeonTangerine,
                        selected = false,
                        enabled = !fusionLoading,
                        size = BEAD_SIZE,
                        onClick = onFusionRemove,
                    )
                }
                // The KPT loop is goo → punch → goo → punch; punching
                // never needed the strip open (pins are stroke counts,
                // safe to grab mid-edit), so the bead lives on the brush
                // tab. The badge is the punch confirmation.
                BadgedBead(badge = if (keyframeCount > 0) "$keyframeCount" else null, color = NeonAmber) {
                    ChromeIconButton(
                        icon = Icons.Filled.AddAPhoto,
                        contentDescription = if (keyframeCount > 0) {
                            stringResource(R.string.goovie_punch_count, keyframeCount)
                        } else {
                            stringResource(R.string.goovie_capture)
                        },
                        color = NeonAmber,
                        selected = false,
                        enabled = keyframeCount < EditorViewModel.MAX_KEYFRAMES,
                        size = BEAD_SIZE,
                        onClick = onPunch,
                    )
                }
                // The only way goo made AFTER a punch reaches an existing
                // keyframe; appears exactly while the selected pin lags
                // the goo on screen, which is the moment "why didn't my
                // keyframe change?" gets asked.
                if (updateKeyframe > 0) {
                    BadgedBead(badge = "$updateKeyframe", color = NeonAmber) {
                        ChromeIconButton(
                            icon = Icons.Filled.Cached,
                            contentDescription = stringResource(
                                R.string.goovie_update_count,
                                updateKeyframe,
                            ),
                            color = NeonAmber,
                            selected = false,
                            size = BEAD_SIZE,
                            onClick = onRepunch,
                        )
                    }
                }
            }
        }
        if (fusionLoading) {
            Text(
                text = stringResource(R.string.fusion_loading_photo),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val sizeLabel = stringResource(R.string.editor_brush_size)
        val strengthLabel = stringResource(R.string.editor_brush_strength)
        // One label column, measured from the labels themselves rather
        // than pinned at a width that happened to fit "Size": at 64dp,
        // "Strength" wrapped to "Strengt" + "h". Measuring keeps the two
        // sliders aligned in every language and at every font scale.
        val measurer = rememberTextMeasurer()
        val labelStyle = MaterialTheme.typography.labelLarge
        val density = LocalDensity.current
        val labelWidth = remember(sizeLabel, strengthLabel, labelStyle, density) {
            with(density) {
                listOf(sizeLabel, strengthLabel)
                    .maxOf { measurer.measure(it, labelStyle).size.width }
                    .toDp()
            }
        }
        LabeledSlider(
            label = sizeLabel,
            labelWidth = labelWidth,
            value = radius,
            onValueChange = onRadiusChange,
            valueRange = EditorViewModel.MIN_RADIUS..EditorViewModel.MAX_RADIUS,
            onAdjustingChange = onAdjustingChange,
        )
        LabeledSlider(
            label = strengthLabel,
            labelWidth = labelWidth,
            value = strength,
            onValueChange = onStrengthChange,
            valueRange = EditorViewModel.MIN_STRENGTH..EditorViewModel.MAX_STRENGTH,
            onAdjustingChange = onAdjustingChange,
        )
        Spacer(modifier = Modifier.size(4.dp))
    }
}

/** A count riding a bead's shoulder; decorative — the bead's own
 *  contentDescription carries the number for accessibility. */
@Composable
private fun BadgedBead(
    badge: String?,
    color: Color,
    content: @Composable () -> Unit,
) {
    Box {
        content()
        if (badge != null) {
            Text(
                text = badge,
                style = MaterialTheme.typography.labelSmall,
                color = MeltVoid,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .background(color, CircleShape)
                    .padding(horizontal = 5.dp, vertical = 1.dp)
                    .clearAndSetSemantics { },
            )
        }
    }
}

@Composable
private fun LabeledSlider(
    label: String,
    labelWidth: Dp,
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    onAdjustingChange: (Boolean) -> Unit = {},
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = label,
            modifier = Modifier.width(labelWidth),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            // The column is measured to fit, so wrapping can only mean
            // the measurement disagreed with the layout — clip a hair
            // rather than break a word across two lines again.
            maxLines = 1,
            softWrap = false,
        )
        Slider(
            modifier = Modifier.weight(1f),
            value = value,
            onValueChange = {
                onAdjustingChange(true)
                onValueChange(it)
            },
            onValueChangeFinished = { onAdjustingChange(false) },
            valueRange = valueRange,
            colors = SliderDefaults.colors(
                thumbColor = NeonMagenta,
                activeTrackColor = NeonMagenta.copy(alpha = 0.6f),
                inactiveTrackColor = MeltVoid,
            ),
        )
    }
}

/** Palette and strip beads draw at this size; their slots stretch to the
 *  grid's computed pitch. */
private val BEAD_SIZE = 36.dp

/** Strip beads keep a fixed near-minimum slot — the strip never holds
 *  more than seven, so it is never the row that decides the width. */
private val STRIP_SLOT = 40.dp

/** One breath per brush for the strip's (i) dialog. */
@StringRes
internal fun BrushTool.infoRes(): Int = when (this) {
    BrushTool.SMEAR -> R.string.tool_info_smear
    BrushTool.MOVE -> R.string.tool_info_move
    BrushTool.SMUDGE -> R.string.tool_info_smudge
    BrushTool.NUDGE -> R.string.tool_info_nudge
    BrushTool.GROW -> R.string.tool_info_grow
    BrushTool.SHRINK -> R.string.tool_info_shrink
    BrushTool.SMOOTH -> R.string.tool_info_smooth
    BrushTool.UNGOO -> R.string.tool_info_ungoo
    BrushTool.FUSE -> R.string.tool_info_fuse
    BrushTool.VORTEX -> R.string.tool_info_vortex
    BrushTool.UNWIND -> R.string.tool_info_unwind
    BrushTool.MELT -> R.string.tool_info_melt
    BrushTool.COMB -> R.string.tool_info_comb
    BrushTool.POND -> R.string.tool_info_pond
    BrushTool.FAULT -> R.string.tool_info_fault
    BrushTool.ECHO -> R.string.tool_info_echo
    BrushTool.FREEZE -> R.string.tool_info_freeze
    BrushTool.WHIP -> R.string.tool_info_whip
    BrushTool.REWIND -> R.string.tool_info_rewind
    BrushTool.PINS -> R.string.tool_info_pins
}

@StringRes
internal fun BrushTool.labelRes(): Int = when (this) {
    BrushTool.SMEAR -> R.string.tool_smear
    BrushTool.MOVE -> R.string.tool_move
    BrushTool.SMUDGE -> R.string.tool_smudge
    BrushTool.NUDGE -> R.string.tool_nudge
    BrushTool.GROW -> R.string.tool_grow
    BrushTool.SHRINK -> R.string.tool_shrink
    BrushTool.SMOOTH -> R.string.tool_smooth
    BrushTool.UNGOO -> R.string.tool_ungoo
    BrushTool.FUSE -> R.string.tool_fuse
    BrushTool.VORTEX -> R.string.tool_vortex
    BrushTool.UNWIND -> R.string.tool_unwind
    BrushTool.MELT -> R.string.tool_melt
    BrushTool.COMB -> R.string.tool_comb
    BrushTool.POND -> R.string.tool_pond
    BrushTool.FAULT -> R.string.tool_fault
    BrushTool.ECHO -> R.string.tool_echo
    BrushTool.FREEZE -> R.string.tool_freeze
    BrushTool.WHIP -> R.string.tool_whip
    BrushTool.REWIND -> R.string.tool_rewind
    BrushTool.PINS -> R.string.tool_pins
}

internal fun BrushTool.icon(): ImageVector = when (this) {
    BrushTool.SMEAR -> Icons.Filled.Gesture
    BrushTool.MOVE -> Icons.Filled.OpenWith
    BrushTool.SMUDGE -> Icons.Filled.BlurOn
    BrushTool.NUDGE -> Icons.Filled.TouchApp
    BrushTool.GROW -> Icons.Filled.ZoomIn
    BrushTool.SHRINK -> Icons.Filled.ZoomOut
    BrushTool.SMOOTH -> Icons.Filled.Waves
    BrushTool.UNGOO -> Icons.Filled.AutoFixHigh
    BrushTool.FUSE -> Icons.Filled.PhotoLibrary
    BrushTool.VORTEX -> Icons.Filled.RotateRight
    BrushTool.UNWIND -> Icons.Filled.RotateLeft
    BrushTool.MELT -> Icons.Filled.SouthEast
    BrushTool.COMB -> Icons.Filled.Dehaze
    BrushTool.POND -> Icons.Filled.RadioButtonChecked
    BrushTool.FAULT -> Icons.Filled.CompareArrows
    BrushTool.ECHO -> Icons.Filled.ContentCopy
    BrushTool.FREEZE -> Icons.Filled.AcUnit
    BrushTool.WHIP -> Icons.Filled.Bolt
    BrushTool.REWIND -> Icons.Filled.History
    BrushTool.PINS -> Icons.Filled.PushPin
}

/** Each tool wears its own tube of neon — families share a color. */
internal fun BrushTool.neonColor(): Color = when (this) {
    BrushTool.SMEAR -> NeonMagenta
    BrushTool.MOVE -> NeonCyan
    BrushTool.SMUDGE -> NeonMagenta
    BrushTool.NUDGE -> NeonCyan
    BrushTool.GROW -> NeonTangerine
    BrushTool.SHRINK -> NeonAmber
    BrushTool.SMOOTH -> NeonLime
    BrushTool.UNGOO -> NeonLime
    BrushTool.FUSE -> NeonViolet
    BrushTool.VORTEX -> NeonTangerine
    BrushTool.UNWIND -> NeonAmber
    BrushTool.MELT -> NeonMagenta
    BrushTool.COMB -> NeonLime
    BrushTool.POND -> NeonCyan
    BrushTool.FAULT -> NeonViolet
    BrushTool.ECHO -> NeonCyan
    // Its own tube: the varnish is the palette's only brake, and a
    // brake that looks like the accelerators is a brake nobody reaches
    // for.
    BrushTool.FREEZE -> NeonViolet
    BrushTool.WHIP -> NeonTangerine
    // Lime, with Smooth and UnGoo: Rewind is the third dissolver, and
    // the only difference between them is WHAT they dissolve toward.
    BrushTool.REWIND -> NeonLime
    // Its own tube, like Freeze: Pins is the only row that is a MODE
    // rather than a brush, and a mode that looks like a brush is a mode
    // people tap expecting to paint.
    BrushTool.PINS -> NeonViolet
}
