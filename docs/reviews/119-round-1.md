## GLM 5.3 Code Review

> [!NOTE]
> Review scope: **full PR** at `ab047c0`.  hybrid mode is bootstrapping without prior completed state.

> [!NOTE]
> Review coverage was limited for some files:
> - no patch returned by GitHub: `macos/Artwork/MeltoramaIcon.png`

> [!NOTE]
> Model routing: 2 deep (glm-5.3), 5 fast (glm-5.3-flash).

**Actionable suggestions identified: 4**

> [!NOTE]
> Inline suggestions are posted on a best-effort basis; GitHub may reject invalid or outdated diff anchors.

<details>
<summary>🟠 Major comments (2)</summary><blockquote>

**macos/Artwork/README.md:33 - "OS applies the native app-icon mask" only holds on macOS 26; the icon will ship with hard square corners earlier**
**Problem:** The new prompt (and the doc's "draws the picture edge to edge, with no canvas inset or transparent margin" at lines 17–19) assumes the operating system will mask the full-bleed opaque square into the standard squircle. Classic macOS app icons packaged via `iconutil`/`.icns` are rendered **as-is** by the Dock and Finder — the system mask/Liquid Glass treatment only applies on macOS 26 (Tahoe). On Big Sur through Sequoia, this icon appears as a full-bleed square with 90° corners, unlike every neighboring icon.
**Impact:** The Dock icon is the most-seen pixel of the app; hard square corners on all supported pre-Tahoe macOS versions will look visibly out of place. This also silently undoes the old 1/16 inset that kept the Dock footprint comfortable.
**Suggested fix:**
Either confirm the deployment target is macOS 26+ and adjust the doc wording, or bake Apple's icon grid into the packager (script not in this diff):
```diff
  // scripts/generate-macos-icon.swift — after loading the full-bleed master
+ // The Dock shows classic .icns artwork unmasked before macOS 26, so apply
+ // Apple's Big Sur grid here: 1024 canvas -> centered 824x824 rounded square,
+ // corner radius ~= 185.4 px, transparent surroundings.
+ let rounded = try maskToSquircle(master, side: 824, cornerRadius: 185.4, canvas: 1024)
- let scaled = resize(master, to: size)
+ let scaled = resize(rounded, to: size)
```
**Prompt for AI Agents:**
```
Open scripts/generate-macos-icon.swift. Check whether any corner rounding or canvas inset is applied to the full-bleed master before downsampling. Decode the generated 512png slot and inspect the corner pixels: if alpha == 255 at (0,0), the icon is unmasked. Check Package.swift / build-macos.sh for the deployment target. If target < macOS 26, add a squircle mask step (824/1024 side, ~185.4 px corner radius on a 1024 canvas, centered) before resampling, regenerate the iconset and .icns, and visually verify in the Dock. If target is macOS 26 only, instead soften the README claim to say the mask is applied by macOS 26+.
```

**macos/Sources/MeltoramaMac/TimelineView.swift:109-125 - Frame buttons lost press feedback, focus ring, and Increased Contrast support**
**Problem:** The removed `GooFrameButtonStyle` handled three affordances that the new modifier-based styling doesn't replicate: (1) a pressed-state fill driven by `configuration.isPressed`, (2) an explicit 3pt focus ring via `@Environment(\.isFocused)`, and (3) contrast-adaptive stroke widths via `@Environment(\.colorSchemeContrast)`. The new code attaches `background`/`overlay` *outside* the button style, so there's no access to the pressed state, no focus tracking, and the unselected border is a fixed 1pt at `0.25` opacity.
**Impact:** Frames give no tactile feedback when clicked, keyboard users (especially with Full Keyboard Access) may lose a clearly visible focus indicator on this control cluster, and users with Increased Contrast enabled see no adaptation — an accessibility regression versus the previous build.
**Suggested fix:**
```diff
+    @Environment(\.colorSchemeContrast) private var contrast
+
     private func frameButton(_ index: Int) -> some View {
         let selected = session.selectedKeyframe == index
         return Button { session.selectFrame(index) } label: {
@@
-        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? MacTheme.accent : .secondary.opacity(0.25), lineWidth: selected ? 2 : 1)
+        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? MacTheme.accent : .primary.opacity(contrast == .increased ? 0.6 : 0.25), lineWidth: selected ? (contrast == .increased ? 3 : 2) : (contrast == .increased ? 2 : 1))
             .allowsHitTesting(false).accessibilityHidden(true))
```
**Prompt for AI Agents:**
```
In macos/Sources/MeltoramaMac/TimelineView.swift: 1) Add @Environment(\.colorSchemeContrast) to GoovieTimelineView and use it to widen frame-button strokes (3pt selected / 2pt unselected) when contrast == .increased. 2) Verify with Full Keyboard Access enabled that tabbing through filmstrip frames shows a visible focus indicator; if the system ring is not drawn around the borderless button, re-introduce a ring using @Environment(\.isFocused) like the removed GooFrameButtonStyle. 3) Confirm pressed-state behavior: since the accent background/overlay sit outside the ButtonStyle, configuration.isPressed is unavailable — if press feedback is desired, move the background into a minimal custom ButtonStyle that reads configuration.isPressed.
```

</blockquote></details>

<details>
<summary>🟡 Minor comments (8)</summary><blockquote>

**macos/Artwork/README.md:13 - Git-history link points at the README, not the original master artwork**
**Problem:** The sentence "The original master and prompt remain in Git history" links only to `README.md` at commit 9f0f268. The replaced master PNG (the thing the surrounding paragraph is about, e.g. for provenance/licensing checks) isn't directly linked. Also note the hard-coded `github.com/...` URL will 404 if the repo is renamed, transferred, or viewed off-GitHub.
**Impact:** Readers verifying "no historical artwork was copied" can't reach the original master in one click; they must know to browse the tree at that commit.
**Suggested fix:**
```diff
-remain in Git history at [commit 9f0f268](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/README.md).
+remain in Git history: [master](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/MeltoramaIcon.png) and [prompt](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/README.md).
```
[[suggestion:path:macos/Artwork/README.md:line:13:Link both the original master PNG and the original prompt README in Git history:remain in Git history: [master](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/MeltoramaIcon.png) and [prompt](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/README.md).]]
**Prompt for AI Agents:**
```
Verify that commit 9f0f268 contains macos/Artwork/MeltoramaIcon.png (i.e., it is the pre-change master, not the new opaque one). Confirm both rewritten links resolve on github.com and update the hashes/paths if the commit ID is wrong.
```

**macos/Sources/MeltoramaMac/EditorView.swift:59-60 - "Deal Goo" button lost its full-width frame**
**Problem:** The old button had `.frame(maxWidth: .infinity)` so it stretched to the palette width. The migration to `.borderedProminent` dropped that frame, so the button now hugs its content while the tool rows above it (which use `Spacer(minLength: 0)` + full-width padding) stretch edge-to-edge.
**Impact:** Visual misalignment in the left palette; the primary action looks weaker and inconsistent with the redesigned rows.
**Suggested fix:**
```diff
-                Button { session.dealGoo() } label: { Label(L("Deal Goo"), systemImage: "dice") }
+                Button { session.dealGoo() } label: { Label(L("Deal Goo"), systemImage: "dice").frame(maxWidth: .infinity) }
                     .buttonStyle(.borderedProminent).tint(MacTheme.berry).disabled(!session.hasPhoto)
```
**Prompt for AI Agents:**
```
In macos/Sources/MeltoramaMac/EditorView.swift, locate the Deal Goo button in the toolPalette. Add .frame(maxWidth: .infinity) to the Label inside the button so it fills the palette width, matching the tool rows. Also consider .buttonStyle(.bordered) for the adjacent "Reset Goo…" button if a plain text button looks underweighted next to it. Build for macOS and visually confirm both action buttons align with the tool list edges.
[[suggestion:path:macos/Sources/MeltoramaMac/EditorView.swift:line:59:Restore full-width Deal Goo button:Button { session.dealGoo() } label: { Label(L("Deal Goo"), systemImage: "dice").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(MacTheme.berry).disabled(!session.hasPhoto)]]
```

**macos/Sources/MeltoramaMac/EditorView.swift:67-68 - Per-mode tooltips likely won't render in the segmented Picker**
**Problem:** The old `modeButton`s attached `.help(L(label))` directly to real buttons, so hovering each mode showed a tooltip. In the new segmented `Picker`, `.help()` is applied to the segment's content `Image`. On macOS, segmented pickers are backed by `NSSegmentedControl`, which does not pick up per-segment help from SwiftUI content views — the tooltips will most likely disappear silently.
**Impact:** Quiet UX regression: users lose hover hints explaining what each mode icon does. Accessibility labels usually survive (AppKit derives segment labels from content), but that should be verified with VoiceOver/Accessibility Inspector.
**Suggested fix:**
```diff
-        Image(systemName: symbol).help(L(label)).accessibilityLabel(L(label))
+        Image(systemName: symbol)
+            .accessibilityLabel(L(label))
+            .accessibilityHint(L(label))
```
Note: this only preserves the assistive-tech path; if hover tooltips matter, the reliable options are keeping the previous buttons or accepting the loss (SwiftUI offers no per-segment tooltip API for segmented pickers).
**Prompt for AI Agents:**
```
In macos/Sources/MeltoramaMac/EditorView.swift, verify whether .help() on Picker segment content (modeLabel helper) produces tooltips on macOS 14+. Run the app, hover each segment of the mode picker, and confirm whether tooltips appear. Test each segment with Accessibility Inspector to confirm the localized label is announced. If tooltips are gone and are considered required, report back; do not re-introduce custom buttons without confirmation.

**macos/Sources/MeltoramaMac/EditorView.swift:21 - Canvas lost its explicit clipping when the inset frame was removed**
**Problem:** The canvas previously had `.clipShape(RoundedRectangle(...))` plus 12pt padding, which guaranteed that pan/zoom-transformed content stayed inside the editor area. That modifier was removed along with the inset design, and now only the dividers bound the region.
**Impact:** If `CanvasView` renders content via transforms (e.g., `scaleEffect`/`offset` for the zoom/pan feature in the status bar) without internal clipping, zoomed content can bleed past the pane edges under `HSplitView`.
**Suggested fix:**
```diff
                         CanvasView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
+                            .clipped()
```
If `CanvasView` already clips internally (e.g., it uses SwiftUI `Canvas`, which self-clips), skip this — but verify first.
**Prompt for AI Agents:**
```
Inspect the CanvasView implementation in the macOS target. Determine whether it clips its own drawing (uses SwiftUI Canvas, .clipped(), masks, or a layer-hosting view). If it relies on external clipping for zoomed/panned content, add .clipped() after CanvasView(session:).frame(maxWidth: .infinity, maxHeight: .infinity) in EditorView.swift. Test by zooming to 400% and panning to an edge; confirm nothing draws over the toolbar, dividers, or status bar.

**macos/Sources/MeltoramaMac/EditorView.swift:244 - Reset button creates two undo entries for one action**
**Problem:** The reset button calls `setValue(0)` (which internally performs `session.edit("Adjust \(titles[index])")` to zero the global) followed immediately by a second `session.edit("Still \(titles[index])")` to clear the lever wobble. A single click on "Reset" therefore pushes two separate undoable edits.
**Impact:** One ⌘Z only reverts half of the reset (e.g., the amount snaps back but the wobble lever stays cleared, or vice versa). Undo history also gets cluttered with paired entries for what the user perceives as one action.
**Suggested fix:**
```diff
-                Button {setValue(0);session.edit("Still \(titles[index])") {$0.wobble.levers[index]=LeverWobble()}} label:{Image(systemName:"arrow.counterclockwise").font(.caption).frame(width: 24, height: 24).contentShape(Rectangle())}.buttonStyle(.borderless).help(LF("Reset %@",L(titles[index]))).accessibilityLabel(LF("Reset %@",L(titles[index])))
+                Button {session.edit("Reset \(titles[index])") {$0.globals[index]=0;$0.wobble.levers[index]=LeverWobble()}} label:{Image(systemName:"arrow.counterclockwise").font(.caption).frame(width: 24, height: 24).contentShape(Rectangle())}.buttonStyle(.borderless).help(LF("Reset %@",L(titles[index]))).accessibilityLabel(LF("Reset %@",L(titles[index])))
```
**Prompt for AI Agents:**
```
In EditorView.swift, the effect-section reset button currently calls setValue(0) followed by a separate session.edit that resets the wobble lever, producing two undo entries. Replace both calls with a single session.edit labeled "Reset \(titles[index])" whose mutation closure sets $0.globals[index]=0 and $0.wobble.levers[index]=LeverWobble(). Keep the label, help, and accessibility modifiers unchanged. Verify that a single undo after clicking reset restores both the amount and the wobble lever.
```
[[suggestion:path:macos/Sources/MeltoramaMac/EditorView.swift:line:244:Coalesce reset into a single undoable edit:Button {session.edit("Reset \(titles[index])") {$0.globals[index]=0;$0.wobble.levers[index]=LeverWobble()}} label:{Image(systemName:"arrow.counterclockwise").font(.caption).frame(width: 24, height: 24).contentShape(Rectangle())}.buttonStyle(.borderless).help(LF("Reset %@",L(titles[index]))).accessibilityLabel(LF("Reset %@",L(titles[index])))]

**macos/Sources/MeltoramaMac/TimelineView.swift:115 - Caption shifts horizontally when selection moves**
**Problem:** The checkmark glyph is conditionally inserted (`if selected { ... }`), so when the selection changes the caption text in every affected cell reflows — the newly selected cell's "Frame N" jumps right, the deselected one jumps left.
**Impact:** Small layout jiggle on every selection change; looks unpolished during playback/scrubbing when selection updates rapidly. It's also slightly harder for VoiceOver users to correlate the caption position.
**Suggested fix:**
```diff
-                    if selected { Image(systemName: "checkmark").font(.caption2.weight(.semibold)).accessibilityHidden(true) }
+                    Image(systemName: "checkmark")
+                        .font(.caption2.weight(.semibold))
+                        .opacity(selected ? 1 : 0)
+                        .accessibilityHidden(true)
```
**Prompt for AI Agents:**
```
In frameButton(_:), replace the conditional checkmark insertion with an always-present image whose opacity toggles on `selected`, so the caption column stays aligned across all frame buttons. Verify that selecting different frames no longer shifts the "Frame N" labels and that the hidden checkmark does not affect the accessibility label/traits.
```
[[suggestion:path:macos/Sources/MeltoramaMac/TimelineView.swift:line:115:Stabilize caption layout by toggling checkmark opacity instead of presence:Image(systemName: "checkmark")
    .font(.caption2.weight(.semibold))
    .opacity(selected ? 1 : 0)
    .accessibilityHidden(true)]]

**macos/Sources/MeltoramaMac/TimelineView.swift:102 - ForEach keyed by indices misbehaves when frames are deleted (pre-existing, touched line)**
**Problem:** `ForEach(session.state.keyframes.indices, id: \.self)` uses the array position as identity. The context menu supports deleting and moving frames, so when a frame is removed every subsequent button keeps the same SwiftUI identity (`index`) while representing a different keyframe.
**Impact:** Since `FrameThumbnail` re-renders from the index, content self-corrects, but delete/insert animations will be wrong (views mutate in place instead of the removed row animating out), and any future per-row `@State` would leak across frames. This predates the PR, but the line is touched here so it's worth fixing now.
**Suggested fix:**
```diff
-                ForEach(session.state.keyframes.indices, id: \.self) { index in
-                    frameButton(index)
-                }
+                // Key off a stable per-keyframe identifier when available so
+                // deleting a frame doesn't shift SwiftUI identity across rows.
+                ForEach(Array(session.state.keyframes.enumerated()), id: \.element.id) { index, _ in
+                    frameButton(index)
+                }
```
(Note: this assumes the keyframe model exposes an `id`; if it doesn't, add a stable UUID to the model rather than using `\.offset`, which is equivalent to the current code.)
**Prompt for AI Agents:**
```
Inspect the keyframe model used by session.state.keyframes. If it lacks a stable identifier, add one (e.g., UUID assigned at capture) and rewrite the filmstrip ForEach to iterate the models, passing the derived index to frameButton(_:). Test: capture 4 frames, delete frame 2 via context menu, and confirm the removal animates correctly and remaining thumbnails still map to the right keyframes.
```

**File: scripts/generate-macos-icon.swift:20 - Master opacity no longer validated after removing the alpha guard**
**Problem:** The old guard required the master PNG to have an alpha channel (transparent edges). It was removed because the new artwork is an opaque square, but nothing replaced it — the script now accepts any square PNG, including one with transparent edges, and will happily emit an icns with transparent regions.
**Impact:** VERIFICATION.md states "every decoded pixel was verified opaque," but that check lives outside this script. If a future artwork swap reintroduces transparency, the packager will silently regress to exactly the irregular-icon/white-surround problem this change was meant to fix, and only manual inspection would catch it. The pipeline previously enforced an input invariant at this spot; it now enforces none.
**Suggested fix:**
```diff
 guard let source = CGImageSourceCreateWithURL(artwork as CFURL, nil),
       image.width == image.height, image.width >= 1024 else {
     fail("The Mac icon master must be a readable square PNG of at least 1024 pixels: \(artwork.path)")
 }
+guard [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) else {
+    fail("The Mac icon master must be fully opaque now that every representation fills the square: \(artwork.path)")
+}
```
[[suggestion:path:scripts/generate-macos-icon.swift:line:20:Require an opaque icon master:guard let source = CGImageSourceCreateWithURL(artwork as CFURL, nil),
      image.width == image.height, image.width >= 1024 else {
    fail("The Mac icon master must be a readable square PNG of at least 1024 pixels: \(artwork.path)")
}
guard [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) else {
    fail("The Mac icon master must be fully opaque now that every representation fills the square: \(artwork.path)")
}]]
**Prompt for AI Agents:**
```
1. Confirm the current icon master PNG decodes with an alphaInfo in the "none" family (e.g. `sips -g hasAlpha` or CGImageSource inspection) and contains no transparent pixels.
2. Add the opacity guard shown above immediately after the existing size guard in scripts/generate-macos-icon.swift.
3. Run the script against the current artwork and confirm it still succeeds; run it against a transparent test PNG and confirm it fails with the new message.
4. Ensure no other callers of this script depend on accepting alpha-channel masters.
```

</blockquote></details>

<details>
<summary>ℹ️ Info comments (6)</summary><blockquote>

**macos/Sources/MeltoramaMac/EditorView.swift:13 - Removed brush-tint status dot**
**Problem:** The deleted `Circle().fill(session.mode == .brush ? GooTint.brush(session.tool).color : GooTint.aqua.color)` was the only place the active tool's tint color was surfaced in the header. The new tool rows tint every icon with the same `MacTheme.accent`, so per-tool color identity no longer appears anywhere in the main UI.
**Impact:** Cosmetic only, but if per-tool color coding matters elsewhere in the app (e.g., cursor tint, stroke preview), the header is now inconsistent with it.
**Suggested fix:**
```diff
                             HStack(spacing: 12) {
+                                if session.mode == .brush { Circle().fill(GooTint.brush(session.tool).color).frame(width: 7, height: 7).accessibilityHidden(true) }
                                 Text(L(session.mode == .brush ? session.tool.title : session.mode.rawValue)).font(.headline)
```
**Prompt for AI Agents:**
```
Confirm with the design intent whether the per-tool tint color (GooTint.brush) is still used anywhere user-visible in the macOS app after this refactor. If the tint is meant to remain part of the mode identity, re-add a small color dot in the header HStack before the tool title, only shown in brush mode. Otherwise document that GooTint.brush is now decorative/legacy.
```

**macos/Sources/MeltoramaMac/EditorView.swift:257 - Removing the per-row surface and padding shifts layout metrics**
**Problem:** Dropping `.padding(.vertical, 2).background(GooPanelSurface(cornerRadius: 6, inset: expanded)).padding(.horizontal, 8).padding(.bottom, 5)` changes the effective geometry: the reset row's total horizontal inset goes from 16pt (8 outer + 8 inner) to 14pt (inner only), and the explicit 5pt bottom gap between effect sections disappears. The `inset: expanded` variant of the old surface also provided visual grouping when a section was expanded, which a flat `MacTheme.window` background doesn't replicate.
**Impact:** Likely intentional as part of the theme migration, but worth a visual pass — expanded sections may now blend together, and the reset buttons sit 2pt closer to the leading edge than before.
**Suggested fix:**
No code change suggested; verify in the running app that inter-section spacing is covered by the parent `VStack` spacing and that expanded sections still read as distinct groups.
**Prompt for AI Agents:**
```
After the GooPanelSurface-to-MacTheme migration in EditorView.swift's EffectSection, run the app and compare the effect section rows against the previous design: check leading alignment of the reset button (was 16pt inset, now 14pt), spacing between collapsed rows (was 5pt bottom padding), and visual separation when a section is expanded. If sections blend together when expanded, propose adding spacing or a subtle divider at the parent level rather than reintroducing per-row backgrounds.
```

**macos/Sources/MeltoramaMac/EditorView.swift:291 - Accent tint applied only to ExportSheet, not the inspector's buttons**
**Problem:** `.tint(MacTheme.accent)` is added to the `ExportSheet`, which makes sense now that buttons use system default styles instead of `GooActionButtonStyle(tint:)`. However, the inspector's "Save Project…" and "Export…" buttons in this same file also lost their custom styles without an accompanying tint in this diff.
**Impact:** If `MacTheme.accent` isn't already applied at the window/root level, the inspector buttons will render with the system default accent while the export sheet uses the app accent — an inconsistency between the two surfaces.
**Suggested fix:**
No inline change suggested; confirm whether tint is set app-wide. If not, apply `.tint(MacTheme.accent)` to the inspector's root view as well.
**Prompt for AI Agents:**
```
Check whether MacTheme.accent is applied at the window or root view level of the macOS app. If it is, no change is needed. If it is not, the ExportSheet's explicit .tint(MacTheme.accent) in EditorView.swift will diverge from the inspector's "Save Project…" and "Export…" buttons, which use default styling without a tint; in that case add .tint(MacTheme.accent) to the inspector container so both surfaces match.
```

**macos/Sources/MeltoramaMac/MacTheme.swift:9 - Verify MacTheme.accent can't drift from the system accent color**
**Problem:** The deleted button styles drew focus rings with `Color.accentColor`; `MacTheme.accent` now hardcodes a teal. If the app also declares an AccentColor asset (or follows the user's system accent), you now have two independent sources of truth for "the accent."
**Impact:** Native focus rings and highlights won't necessarily match custom surfaces painted with `MacTheme.accent`, which reads as a subtle visual bug rather than a design choice.
**Suggested fix:**
```diff
+ # Audit how the accent is sourced across the app:
+ rg -n "AccentColor|accentColor|MacTheme.accent" macos/ 
```
**Prompt for AI Agents:**
```
Check whether the Xcode project or Assets.xcassets defines an AccentColor, and list every use of Color.accentColor versus MacTheme.accent. If both exist, report whether they can render differently in light/dark mode, and recommend either aliasing MacTheme.accent to the asset color or documenting why a hardcoded brand color is intentional.
```

**macos/Sources/MeltoramaMac/MacTheme.swift:12 - Increased Contrast handling is now fully delegated to native controls**
**Problem:** The removed chrome explicitly adapted to `\.colorSchemeContrast == .increased` (stroke widths 1→2, border opacity 0.38→0.8). `MacTheme.adaptive` only branches on light/dark; there are no high-contrast color variants. The dark/light detection itself is safe — `bestMatch(from: [.aqua, .darkAqua])` still resolves `.darkAqua` under high-contrast appearances — but colors never change for HC users.
**Impact:** That's fine for native controls, which handle Increase Contrast themselves. But if any custom drawing uses these colors (window vs. welcome backgrounds, text painted in `berry`/`accent`), HC users may lose separation or legibility with no compensation.
**Suggested fix:**
```diff
+ # Verification checklist (System Settings → Accessibility → Display → Increase contrast):
+ # 1. Window and welcome backgrounds remain distinguishable from inset surfaces.
+ # 2. Any text or strokes drawn in MacTheme.accent/berry still pass WCAG AA against their background.
```
**Prompt for AI Agents:**
```
Enumerate every usage of MacTheme.window, MacTheme.welcome, MacTheme.accent, and MacTheme.berry in the repo. For each, classify it as native-control styling (handles Increase Contrast automatically) or custom drawing. Flag any custom-drawn surface, stroke, or text where a `.colorSchemeContrast == .increased` variant would be needed, and report those file:line locations.
```

**macos/Sources/MeltoramaMac/TimelineView.swift:65-80 - Icon-only play/capture/update buttons now render with the default bordered bezel**
**Problem:** Removing `GooActionButtonStyle`/`GooUtilityButtonStyle` without a replacement means these icon-only buttons fall back to the default macOS style, which draws a standard bezel. The close button two screens down explicitly uses `.buttonStyle(.borderless)`, so the toolbar will mix chrome-less and beveled icon buttons.
**Impact:** Mostly visual consistency — but if the intent of this refactor was a flatter, more native look, the mixed bezels will read as unintended.
**Suggested fix:**
```diff
         .help(L("Play or pause the animation"))
         .accessibilityLabel(L("Play or pause the animation"))
         .disabled(session.state.keyframes.count < 2)
+        .buttonStyle(.borderless)
```
**Prompt for AI Agents:**
```
Decide the intended look for the timeline controls. If bezel-less icons are desired, apply .buttonStyle(.borderless) to playButton, captureButton, and updateButton (and the context-menu chevron/trash buttons at the bottom of frameButton) to match closeButton, and verify hit targets remain reasonable. If standard bezels are intended, no change needed — just confirm visually in both light and dark mode.
```

</blockquote></details>


<details>
<summary>⚠️ Outside diff range comments (7)</summary><blockquote>

<details>
<summary>.github/workflows/zai-code-review.yml (1)</summary><blockquote>

## [Minor] (outside diff) .github/workflows/zai-code-review.yml - Docs claim GLM 5.3; verify the workflow actually runs it
**Problem:** AGENTS.md (two places) and PLAN.md now state PRs are reviewed by GLM 5.3, but the workflow file that pins the reviewer model is not part of this diff chunk.
**Impact:** If the workflow still pins GLM 5.2, the documentation misleads contributors and the CLAUDE.md triage flow references a reviewer version that doesn't exist in CI; review provenance in REVIEW.md would also record the wrong model.
**Suggested fix:**
```diff
-      model: glm-5.2
+      model: glm-5.3
```
**Prompt for AI Agents:**
```
Open .github/workflows/zai-code-review.yml and locate the model identifier (search for "glm" or "5.2"). If any reference still says GLM 5.2 while AGENTS.md/PLAN.md say 5.3, update the workflow model reference to match the docs. Also grep the repo (CLAUDE.md, CICD.md, REVIEW.md templates) for any other "5.2" reviewer references that must be bumped together.
```


</blockquote></details>

<details>
<summary>scripts/generate-macos-icon.swift (1)</summary><blockquote>

## [Minor] (outside diff) scripts/generate-macos-icon.swift - Script must implement the new edge-to-edge icon spec
**Problem:** AGENTS.md and decision 0007 now mandate an opaque, edge-to-edge square icon with "no transparent margins or a canvas inset," replacing the previous "1/16 canvas inset" spec, but the generator script is not in this diff chunk.
**Impact:** If the script still applies the old inset, the checked-in iconset and the docs disagree; regenerating the icon would silently reintroduce the "small on a system backdrop" appearance the decision explicitly rejects. Unlike shaders, there is no stated CI drift check for icons.
**Suggested fix:**
```diff
-    let inset = side / 16
-    let rect = CGRect(x: inset, y: inset, width: side - 2*inset, height: side - 2*inset)
+    let rect = CGRect(x: 0, y: 0, width: side, height: side)
```
**Prompt for AI Agents:**
```
Read scripts/generate-macos-icon.swift. Verify it draws the master edge to edge into all ten iconset slots with no transparent margin, inset, or padding, and that output is opaque sRGB. If any inset logic remains, remove it and regenerate the iconset. Consider adding a CI step that fails if the generated iconset differs from the committed one, mirroring the shader drift check.
```


</blockquote></details>

<details>
<summary>scripts/test-macos.sh (1)</summary><blockquote>

## [Info] (outside diff) scripts/test-macos.sh - Smoke test must target the new `dist/Meltorama.app` path
**Problem:** AGENTS.md changes the smoke-test description from "the installed app" to "the built `dist/Meltorama.app`," but the script is not in this diff chunk.
**Impact:** If `test-macos.sh --smoke` still resolves the app via `/Applications` or another path, the documented workflow fails or tests a stale build.
**Suggested fix:**
```diff
-    APP="/Applications/Meltorama.app"
+    APP="${ROOT}/dist/Meltorama.app"
```
**Prompt for AI Agents:**
```
Open scripts/test-macos.sh and confirm the --smoke path resolves the app bundle produced by scripts/build-macos.sh under dist/. If it looks in /Applications or elsewhere, update it to use the dist/ artifact (and confirm build-macos.sh actually writes dist/Meltorama.app).
```


</blockquote></details>

<details>
<summary>macos/Artwork/ (1)</summary><blockquote>

## [Info] (outside diff) macos/Artwork/ - New 1254-px master and provenance must be committed
**Problem:** AGENTS.md and decision 0007 state the new landscape/berry-curl master and its generation/edit provenance live in `macos/Artwork/` with the old artwork recoverable only via `9f0f268`, but no artwork changes appear in this diff chunk.
**Impact:** If the new master and `macos/Artwork/README.md` provenance aren't committed, builds can't regenerate the icon and the docs reference files that don't exist.
**Suggested fix:**
```diff
+ macos/Artwork/meltorama-icon-master.png      (new 1254-px sRGB master, opaque)
+ macos/Artwork/README.md                      (updated generation/edit provenance)
- macos/Artwork/elastic-photo-master.png       (removable; preserved at 9f0f268)
```
**Prompt for AI Agents:**
```
List macos/Artwork/ in this PR. Confirm the new opaque 1254-px master and an updated README.md with generation/edit provenance are committed, the old elastic-photograph master is removed, and git show 9f0f268 still contains the original artwork for recovery. Verify the committed iconset matches what generate-macos-icon.swift produces from the new master.
```

</blockquote></details>

<details>
<summary>macos/Sources/MeltoramaMac/App.swift (1)</summary><blockquote>

## [Minor] (outside diff) macos/Sources/MeltoramaMac/App.swift:256 - Ensure `MacTheme.windowNSColor` is appearance-dynamic before making the titlebar transparent
**Problem:** With `titlebarAppearsTransparent = true`, the titlebar paints `window.backgroundColor` instead of the system material. The matching README text promises "mint/aqua in Light appearance and teal in Dark" — that only works if `MacTheme.windowNSColor` is a dynamic `NSColor` (e.g. `NSColor(name:) { appearance in ... }` or an asset-catalog color with both appearances). A fixed sRGB mint would leave a bright bar over a dark window.
**Impact:** Wrong titlebar color/contrast in Dark mode (or after an appearance switch while a document window is open), which contradicts the documented behavior.
**Suggested fix** (in `MacTheme`, not shown in this diff — pattern only):
```diff
- static let windowNSColor = NSColor(srgbRed: 0.80, green: 1.00, blue: 0.94, alpha: 1)
+ static let windowNSColor = NSColor(name: nil) { appearance in
+     appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
+         ? NSColor(srgbRed: 0.07, green: 0.25, blue: 0.28, alpha: 1)   // teal (Dark)
+         : NSColor(srgbRed: 0.80, green: 1.00, blue: 0.94, alpha: 1)   // mint/aqua (Light)
+ }
```
**Prompt for AI Agents:**
```
Locate MacTheme.windowNSColor. If it is a single fixed sRGB/calibrated color rather than a dynamic provider or dual-appearance asset color, convert it to NSColor(name:){appearance in ...} with the mint/aqua Light and teal Dark values the README documents. Then build, open a document window, and toggle System Settings appearance Light->Dark while the window is visible to confirm the titlebar re-tints live.
```

</blockquote></details>

<details>
<summary>macos/Sources/MeltoramaMac/EditorView.swift (1)</summary><blockquote>

## [Minor] (outside diff) macos/Sources/MeltoramaMac/EditorView.swift:64 - Hardcoded legacy scroller padding applies even with overlay scrollers
**Problem:** `.padding(.trailing, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))` unconditionally reserves a legacy-scroller gutter. When the system is set to overlay scrollbars (the macOS default), the legacy width query still returns ~11pt, leaving dead space on the right of the palette and inspector.
**Impact:** Permanent visual gutter that serves no purpose for most users; interacts with the new narrower palette (minWidth 178) by shrinking usable row width further.
**Suggested fix:**
```diff
-                .padding(.trailing, NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
+                .padding(.trailing, NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
```
**Prompt for AI Agents:**
```
In macos/Sources/MeltoramaMac/EditorView.swift, the toolPalette ScrollView applies an unconditional trailing padding using NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy). Change it to only apply when NSScroller.preferredScrollerStyle == .legacy, otherwise 0. Verify in System Settings that toggling "Show scroll bars: Always / When scrolling" switches the layout without clipping content under a visible scroller.


</blockquote></details>

<details>
<summary>macos/Sources/MeltoramaMac/GooChrome.swift (1)</summary><blockquote>

## [Minor] (outside diff) macos/Sources/MeltoramaMac/GooChrome.swift:1 - Confirm no dangling references to the deleted Goo* types
**Problem:** This diff deletes `GooTint`, `GooPanelSurface`, `GooWellSurface`, `GooScrew`, `GooWordmark`, `GooDome`, and all five button styles in one go. The call sites that used them (tool buttons, dome toolbar, wordmark, mode switcher, action/utility buttons) aren't visible in this section, so there's no proof they've all been migrated to `MacTheme` + native controls.
**Impact:** A single surviving reference in Swift, an `.xib`/`.storyboard`, or a `#Preview` breaks the build — or worse, crashes at nib-load time.
**Suggested fix:**
```diff
+ # From the repo root — expected result: zero matches.
+ rg -n "Goo(Tint|PanelSurface|WellSurface|Screw|Wordmark|Dome|ToolButtonStyle|ModeButtonStyle|ActionButtonStyle|UtilityButtonStyle)" macos/
```
**Prompt for AI Agents:**
```
Search the entire repository (including .xib/.storyboard files) for any identifier defined in the deleted GooChrome.swift: GooTint, GooPanelSurface, GooWellSurface, GooScrew, GooWordmark, GooDome, GooToolButtonStyle, GooModeButtonStyle, GooActionButtonStyle, GooUtilityButtonStyle. Report each match as file:line. Migrate matches to MacTheme colors with native AppKit/SwiftUI styling, or delete them. Also check Localizable.strings for now-unused keys "Meltorama", "2000", and "Meltorama 2000" (previously wrapped in L(...)) and confirm the macOS target compiles.


</blockquote></details>

</blockquote></details>

<!-- zai-code-review-state:{"version":1,"lastReviewedSha":"ab047c060e053c5fe3e02d3b23e228ef71e11f5e","lastFullReviewSha":"ab047c060e053c5fe3e02d3b23e228ef71e11f5e","auditCursor":0,"mode":"full"} -->
<!-- zai-code-review -->
