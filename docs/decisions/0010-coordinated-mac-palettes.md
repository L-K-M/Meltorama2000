# 0010: Coordinated palettes across the native Mac window

- **Status:** accepted
- **Date:** 2026-10-01

## Context

The optional themes in [decision 0009](0009-optional-native-mac-themes.md)
colored only side panels and accents. The user now wants the titlebar and
content area included, with themes defining multiple coordinated colors
rather than shades of a single accent.

## Decision

Keep the eight theme identifiers and the native interaction design. Define
explicit light and dark sRGB colors for titlebar chrome, panels, workspace,
and accents. Use complementary pairings where appropriate: peach and teal,
blue and coral, violet and gold. Classic retains the original native surfaces
and lime accent. Show a compact three-swatch preview in the native theme picker.

Apply background roles to the welcome area, canvas surroundings, contextual
bars, timeline, Settings, and export sheet. The photo itself continues through
the same rendering engine, unaffected by interface colors. Keep standard
native file dialogs and document commands.

Use public AppKit window background and titlebar transparency properties to
color the existing native titlebar. Retain its document title, traffic lights,
toolbar layout, and safe areas. Observe preferences and effective appearance
without replacing hosting views or changing document state. Restore the
original titlebar behavior for Classic.

Verify color contrast in both appearances and Increase Contrast, and exercise
theme changes with active field drafts, multiple documents, save/reopen,
exports, and window resizing in the actual application.

## Consequences

Themes become complete window palettes while retaining native controls and
keyboard interaction. Colors remain application preferences, separate from
projects, undo history, and exported pixels. Existing preferences and document
compatibility remain intact. Android and the generated dog icon are unchanged.
