package ch.lkmc.goo.ui.editor

import ch.lkmc.goo.engine.core.BrushTool
import ch.lkmc.goo.engine.core.StampMode

/** Which panel the editor's dock shows; GOOVIE follows the ViewModel. */
enum class EditorPanel { BRUSH, LEVERS, FUNHOUSE, GOOVIE }

/**
 * The dock's tabs resolve from three independent flags: goovie mode is
 * ViewModel-owned (it gates strokes and history), the funhouse and levers
 * toggles are screen-local. Goovie wins — the strip must never leave a
 * half-visible rig underneath — and funhouse outranks levers because its
 * overlay owns the canvas while its panel is up, so anything else showing
 * would pair one mode's panel with another mode's input.
 */
fun resolvePanel(
    goovieMode: Boolean,
    showFunhouse: Boolean,
    showLevers: Boolean,
): EditorPanel = when {
    goovieMode -> EditorPanel.GOOVIE
    showFunhouse -> EditorPanel.FUNHOUSE
    showLevers -> EditorPanel.LEVERS
    else -> EditorPanel.BRUSH
}

/**
 * Brush families: the dock groups the palette by what the finger does.
 * DRAG tools paint along the path, PUMP tools apply while held in place,
 * MARK tools leave state behind — masks (Fusion, Freeze), a dropped
 * ripple (Pond), or the pin rig (Pins, the one row that is a mode).
 */
enum class ToolFamily { DRAG, PUMP, MARK }

/**
 * Derived from behavior, not from name and not from [StampMode] alone:
 * Melt shares DIRECTIONAL with Smear but is held, not dragged, and the
 * grid a finger scans should follow the finger, not the shader branch.
 */
fun BrushTool.family(): ToolFamily = when {
    isPinWarp -> ToolFamily.MARK
    pumped -> ToolFamily.PUMP
    mode == StampMode.FUSE || mode == StampMode.GUARD || mode == StampMode.RIPPLE ->
        ToolFamily.MARK
    else -> ToolFamily.DRAG
}

/**
 * Palette rows for the dock: one row per family, family order, enum order
 * within a row — so a new BrushTool lands in its family row with no UI
 * edit. Computed once; the palette is a compile-time fact.
 */
private val TOOL_DOCK_ROWS: List<List<BrushTool>> = run {
    val grouped = BrushTool.entries.groupBy { it.family() }
    ToolFamily.entries.mapNotNull { family -> grouped[family]?.takeIf { it.isNotEmpty() } }
}

fun toolDockRows(): List<List<BrushTool>> = TOOL_DOCK_ROWS
