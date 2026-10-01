# 0008: Restore the original native Mac presentation

- **Status:** accepted
- **Date:** 2026-10-01

## Context

The user rejected [decision 0007](0007-colorful-native-mac.md): the teal window
tint, reduced contrast, segmented mode control, changed titlebar, and
application icon in the welcome view. The
original native screenshot remains the requested presentation reference, as
preserved by `v2.0.1` at `94dc117`.

## Decision

Restore individual mode buttons, the narrow palette and plain tool rows,
neutral system surfaces, the standard titlebar, and the welcome `hand.draw`
illustration. Use local lime accents for playfulness while keeping native
controls and readable selection. Retain later document, renderer, recovery,
numeric entry, keyboard, accessibility, responsive layout, and installer fixes.
Effect enabling and disclosure remain independent. The application icon is a
photographic Golden Retriever portrait, edited from Karen Arnold's CC0 photo
with an enlarged nose, one eye, and a pulled smiling cheek. Its original source,
edited master, and exact generation prompt are retained under `macos/Artwork/`;
see its [provenance](../../macos/Artwork/README.md).

## Consequences

This supersedes 0007's tinted window and mode-control direction. The app's
identity is expressed through selective accents and separate application
artwork. Shared document and shader behavior, Android's console theme, and
native document workflows are unchanged.

[Decision 0009](0009-optional-native-mac-themes.md) later adds optional accent
palettes and replaces the real-photo icon with an invented dog and melting curl.
