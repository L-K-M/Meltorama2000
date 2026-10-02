# 0009: Optional themes for the native Mac interface

- **Status:** accepted
- **Date:** 2026-10-01

## Context

The user wants to keep the working original native layout restored by
[decision 0008](0008-original-native-mac.md), and express playfulness through
a choice of themes. They also requested an invented dog for the icon,
combined with the earlier landscape icon's bottom-right melting curl.

## Decision

Offer eight application themes independently of System, Light, or Dark
appearance. Classic preserves the original lime accents and neutral system
surfaces. Candy, Tangerine, Ocean, Grape, Mint, Sunshine, and Cherry change
accents and add a restrained color wash to the side panels.

Keep the native titlebar, controls, labeled tool rows, welcome hand, neutral
photo workspace, compact effect sections, and document workflows.
Resolve theme colors for both appearances and test readable contrast.
Persist the preference across launches and apply it to all open windows
without replacing hosting views, committing field drafts, or editing projects.
Themes never affect preview or export pixels.

Generate an invented dog in photographic style, using only the earlier
generated landscape as a curl-composition reference. Retire the real-photo
source from active artwork. Preserve the new opaque master and exact prompt
in [the artwork provenance](../../macos/Artwork/README.md).

## Consequences

This extends 0008's selective-accent direction without changing the native
interaction design. Theme selection is optional and Classic remains the
default. The previous real-photo artwork and its attribution remain in
Git history. Android's interface and launcher artwork are unchanged.

[Decision 0010](0010-coordinated-mac-palettes.md) extends these themes to
coordinated titlebar and workspace backgrounds with separate accent colors.

On 2 October 2026, the user selected Candy as the default for builds with no
saved theme preference. This supersedes the original Classic default above;
explicit choices are preserved, and unknown stored identifiers still fall
back to Classic without being overwritten.
