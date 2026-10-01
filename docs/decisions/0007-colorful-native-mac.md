# 0007: Color around native Mac controls

- **Status:** accepted
- **Date:** 2026-10-01

## Context

The user rejected decision 0006's presentation after seeing the Mac app. The
gray console and small colored domes did not provide the intended playfulness.
The elastic photograph icon also appeared too small against a white system
backdrop. The user requested a return to the fully native interface, with fun
window color as a starting point and a colorful icon that fills its space.
Tag `v2.0.1` at `94dc117` remains the reference for the original native layout.

## Decision

Restore that native control hierarchy and layout while retaining the later
document, renderer, and installer fixes. Use a native segmented picker for
persistent modes, labeled rows for tools, and standard buttons for actions.
Keep the compact effect header and independent enabling/disclosure, selected
tool and frame checkmarks, responsive GOOvie controls, and guarded inspector
bindings. Remove the custom metal, dome, and pill button styles.

Give the window an adaptive tint from `MacTheme.swift`: mint/aqua in Light
appearance, teal in Dark, and berry for primary actions. The toolbar, palettes,
inspectors, welcome view, and timeline belong to the same color scheme. The
photo remains the central workspace. Native text, control rendering, focus,
menus, document commands, and file dialogs provide the interaction foundation.

Edit the project's original icon artwork into an opaque square filled by its
sunny landscape and glossy berry curl. The icon packager draws the checked-in
master edge to edge in every native size, with no extra inset. Keep generation
provenance in `macos/Artwork/README.md` and in the installed bundle. The original
artwork remains recoverable in Git history at `9f0f268`.

## Consequences

Character now comes from window color and the icon while controls retain their
familiar Mac appearance. Further visual exploration starts from this foundation.
This decision supersedes 0006's Mac materials; it does not change Android's
console theme or the shared document and shader semantics. No new runtime
dependency or network requirement is introduced.
