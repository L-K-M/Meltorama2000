package ch.lkmc.goo.ui.editor

import ch.lkmc.goo.engine.core.BrushTool
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DockStateTest {

    @Test
    fun `goovie beats funhouse beats levers beats brush`() {
        assertEquals(
            EditorPanel.GOOVIE,
            resolvePanel(goovieMode = true, showFunhouse = true, showLevers = true),
        )
        assertEquals(
            EditorPanel.GOOVIE,
            resolvePanel(goovieMode = true, showFunhouse = false, showLevers = false),
        )
        assertEquals(
            EditorPanel.FUNHOUSE,
            resolvePanel(goovieMode = false, showFunhouse = true, showLevers = true),
        )
        assertEquals(
            EditorPanel.LEVERS,
            resolvePanel(goovieMode = false, showFunhouse = false, showLevers = true),
        )
        assertEquals(
            EditorPanel.BRUSH,
            resolvePanel(goovieMode = false, showFunhouse = false, showLevers = false),
        )
    }

    @Test
    fun `every tool lands in exactly one family`() {
        val families = BrushTool.entries.groupBy { it.family() }
        assertEquals(BrushTool.entries.size, families.values.sumOf { it.size })
        // Families follow what the finger does, not the shader branch:
        // Melt shares DIRECTIONAL with Smear but is held, so it pumps.
        assertEquals(
            setOf(
                BrushTool.SMEAR, BrushTool.MOVE, BrushTool.SMUDGE, BrushTool.NUDGE,
                BrushTool.COMB, BrushTool.FAULT, BrushTool.ECHO, BrushTool.WHIP,
            ),
            families[ToolFamily.DRAG]?.toSet(),
        )
        assertEquals(
            setOf(
                BrushTool.GROW, BrushTool.SHRINK, BrushTool.SMOOTH, BrushTool.UNGOO,
                BrushTool.VORTEX, BrushTool.UNWIND, BrushTool.MELT, BrushTool.REWIND,
            ),
            families[ToolFamily.PUMP]?.toSet(),
        )
        // The mark makers: two masks, a dropped ripple, and the pin rig.
        assertEquals(
            setOf(BrushTool.FUSE, BrushTool.POND, BrushTool.FREEZE, BrushTool.PINS),
            families[ToolFamily.MARK]?.toSet(),
        )
    }

    @Test
    fun `dock rows cover the palette, one row per family, in enum order`() {
        val rows = toolDockRows()
        assertEquals(BrushTool.entries.toSet(), rows.flatten().toSet())
        assertEquals(BrushTool.entries.size, rows.flatten().size)
        rows.forEach { row ->
            // One family per row…
            assertEquals(1, row.map { it.family() }.distinct().size)
            // …its tools in palette order…
            assertEquals(row, row.sortedBy { BrushTool.entries.indexOf(it) })
        }
        // …and the rows themselves in family order, drag hand first.
        assertEquals(ToolFamily.entries, rows.map { it.first().family() })
    }

    @Test
    fun `no row outgrows the tray`() {
        // Eight 36dp beads in adaptive slots are what a 360dp tray can
        // hold with nothing scrolling — the grid's whole promise. A ninth
        // bead in some family means it is time to split that family, not
        // to shrink the beads again.
        toolDockRows().forEach { row ->
            assertTrue(row.size <= 8, "row of ${row.size} would not fit a 360dp tray")
        }
    }
}
