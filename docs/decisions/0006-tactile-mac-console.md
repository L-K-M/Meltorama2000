# 0006: A tactile Mac photo-warping console

- **Status:** superseded by [0007](0007-colorful-native-mac.md)
- **Date:** 2026-10-01

## Context

The first native Mac port established the editor's document, input, persistence,
and export behavior. The user accepted that version and requested a release
reference before giving its presentation more of the Delicious Generation's
character. Tag `v2.0.1` preserves that baseline at commit `94dc117`.

## Decision

The interface now treats the editing surface as a physical console. A satin
metal tool rack holds glossy colored brush domes, grouped by how they work.
Modes occupy one inset rail; selected tools have a distinct rim and checkmark.
One-time actions use raised pills or compact metal buttons. The neutral photo
workspace has a recessed bezel. Effects keep one compact checkbox/disclosure/
title/actions header, with independent enabling and expansion. The GOOvie
strip uses dark film stock, perforations, image windows, and selection marks.
The welcome surface uses the app icon and mounted sample cards.

SwiftUI draws all new materials and control states. No image from the references
is copied into the app, and no new runtime library or downloaded asset is needed.
One light source above-left keeps bevels and reflections consistent. Materials
are opaque and adapt to light/dark appearance. Selection does not depend on
color alone. Focus, disabled states, increased contrast, and reduced motion
remain part of the controls rather than being painted over.

## Consequences

AppKit still owns windows, menus, file dialogs, undo, the input canvas, and
buffered numeric editing. Sliders, checkboxes, and pickers remain native.
Decorative layers are excluded from hit testing and accessibility. New Button
styles retain standard actions and keyboard semantics. The document model,
renderer, save/recovery, sharing, and export rules do not change.

The references guide material and personality, rather than prescribing their
window behavior: [Rogue Amoeba's Delicious Generation essay](https://weblog.rogueamoeba.com/2006/11/06/the-delicious-generation/)
and [Gruber's AppZapper 3000 article](https://daringfireball.net/2026/09/appzapper_3000).
The provided Kai's Power Goo, Disco, Delicious Library, and AppZapper images
are visual study material only.
