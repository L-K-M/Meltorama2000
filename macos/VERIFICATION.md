# macOS port verification

This checklist tracks the Android workflows against the native port. A source
inspection establishes implementation coverage; it does not establish that an
interaction was exercised in the installed application. The final validation
record below must distinguish automated checks from manual app checks.

## Capability checklist

| Workflow | Acceptance check |
| --- | --- |
| Open and import | Open JPEG/PNG and an Android project folder; EXIF orientation and original source bytes survive save/reopen. Both bundled procedural samples open without network access. |
| Native documents | New/open/save/save as/revert/recent documents work with standard file dialogs and keyboard commands. Closing and quitting protect edited work. Autosaved recovery restores a document after interruption. |
| Canvas navigation | Fit, actual size, pan, zoom, rotation, original comparison, window resizing, and full screen preserve brush coordinates and image aspect. Space temporarily pans without painting. |
| Brush palette | Smear, Move, Smudge, Nudge, Grow, Shrink, Smooth, UnGoo, Fusion, Vortex, Unwind, Melt, Comb, Pond, Fault, Echo, Whip, Freeze, Rewind, and Taffy Pins are selectable, usable, undoable, and persisted. |
| Brush behavior | Size and strength use normalized image geometry. Pump tools keep applying while held still. Echo plants an offset source. Whip records its release tail. Freeze protects subsequent strokes and global effects; its overlay stays out of exports. |
| Symmetry and portals | Mirror reverses directional and swirl handedness. Kaleidoscope copies rotate correctly. Portal rings produce translated twins only when a stroke begins inside a ring. Their copies combine with symmetry in the original order. |
| Taffy Pins | Holds stay fixed during a pull. A pull renders from the gesture's initial state, commits once, and replays identically after reopening. Freeze does not affect the rigid MLS solver, matching Android. |
| History and reset | Undo/redo uses the document's revision graph. New edits truncate only the redo branch; captured GOOvie pins and Rewind targets remain valid. Reset is deliberate and undoable. |
| Whole-image effects | Bulge, Twirl, Squeeze, Stretch, Spike, and Static remain independently enabled and editable. Compact inspector headers separate enabling from disclosure; collapsed sections consume no body space. |
| Wobbulator | Each lever's integer cycles and depth produce deterministic phase-based modulation. Preview and movies combine wobble with keyframe levers; export clamps rates to the actual loop's 3 Hz ceiling. |
| Funhouse lenses | Up to four positioned Bulge, Pinch, Fisheye, or Swirl lenses can be selected, moved, resized, changed, and removed. Lens interpolation follows slot order and dissolves missing slots. |
| Fusion | Import/remove image B, cover-crop it to A, paint through it, undo, save/reopen, and export without touching the original source files. |
| Crop | Freeform reframe composes into original-image coordinates. Applying a crop deliberately clears coordinate-dependent edits/keyframes. Returning to the full source remains possible. |
| Goo Me | A curated recipe creates ordinary strokes and at most one lever change. One undo restores the complete deal; saving and movie playback use the same revisions. |
| GOOvie editing | Capture/update/delete/reorder up to 64 immutable revision pins, select and scrub frames, play continuously, and resume live editing without changing an existing pin. Linear, Ease, and Boing affect the segment leaving its pin. |
| Still export | Native ImageIO PNG/JPEG renders the original source size by default, preserves upright orientation, and matches the canvas's displacement math. JPEG quality is adjustable. Oversized textures fail clearly rather than silently reducing resolution. |
| Movie export | AVFoundation H.264 MP4 and ImageIO GIF consume the same tween walk. MP4 stays at 30 fps; GIF selects 20/10/5/4/2 fps without truncating the strip. Speed changes frame count, including the exact closing pin. GIF's loop option is respected. |
| Export failures | Progress updates remain responsive, cancellation cleans staging files, and an existing destination stays intact until successful atomic finalization. Errors describe the failed operation. |
| Native sharing | The export sheet shares PNG/JPEG/MP4/GIF through system services with the same options and immutable replay. Dismissal/cancellation removes temporary outputs; a chosen service retains its output through completion even if the document closes. |
| Mac interaction | Standard menus, shortcuts, contextual commands, focus rings, tab order, selection feedback, tooltips/accessibility labels, light/dark appearance, and comfortable click targets are exercised in the actual app. |
| Distribution | A clean repeatable build produces a self-contained `.app` with shaders, samples, metadata, icon, and notices. It launches after relocation without the source checkout. |

## Export implementation invariants

- Still output uses full original upright dimensions, subject to the GPU's
  maximum texture size. An explicit maximum dimension is available to callers.
  Movie output fits within 1920 pixels; GIF within 480 pixels. Movies never
  upscale ordinary images and use even dimensions for H.264 compatibility.
- Every movie frame is derived from an immutable project snapshot, never the
  current view, selection overlays, pan/zoom, or a changing wall clock.
- A segment takes easing from its outgoing pin. Boing may extrapolate the
  field up to 1.35 while lever interpolation stays in `[0, 1]`.
- GIF delay is an exact centisecond value for every selected frame rate. The
  lower rates bound normal strips to approximately 200 frames; a maximum-length
  strip at half speed can exceed that budget at the 2 fps floor, as on Android.
- All encoders stage a sibling temporary file. Completion uses a same-volume
  atomic rename. Cancellation and failure remove the temporary output and
  preserve any preexisting destination.
- An export renderer owns a separate GL context and revision cache, keeping
  the canvas independent of a long encode. Progress handlers run off the main
  thread and UI callers dispatch their updates to the main actor.

## Validation record

Independent export validation on this Mac compiled the actual core, renderer,
and export sources into a temporary native harness. ImageIO decoded PNG/JPEG
and GIF output; AVFoundation decoded and inspected H.264 output. These checks
passed:

- Upright 320 × 240 PNG, JPEG, MP4, and GIF, checked against an asymmetric
  red/blue source fixture. MP4 reported 30 fps; GIF contained 25 frames with
  an exact 0.05-second delay for a two-pin strip.
- A deformed closing tween matched the live render byte for byte. Boing
  extrapolated the field while its lever interpolation stayed at the endpoint.
- Half-speed MP4 contained 73 frames and 4× MP4 contained 10 frames. Both
  retained nominal 30 fps. Looping GIF included the infinite-loop block;
  one-shot GIF omitted it.
- Cancelling a long GIF after its first rendered frame preserved an existing
  destination's sentinel bytes and removed its temporary staging file.
- Default PNG sizing preserved 3025 × 2017 source dimensions; MP4 sizing
  produced an even 1920 × 1280 output.

Seventeen native session regression tests passed, covering undo branches and pinned
revisions, crop undo and monotonic IDs, gesture capture, pump noise and portal
symmetry order, resampling, pin reach/rubber, easing and wobble, undo to the
saved state, first recovery creation, an active-gesture recovery snapshot,
native window undo/redo keys, field-editor focus, rejecting overlapping exports,
discarding an active gesture after a successful read/revert while preserving
it after a failed read, rejecting stale queued export progress, and grouping
a slider drag across runloop turns into one balanced undo action. The recovery-folder, saved-state, in-progress keyframe-update,
native undo-key, and active-gesture replacement tests were observed failing
before their fixes and passing afterward.

Four repeatable `ExportEncodingTests` passed on this Mac with a native GPU and
H.264 encoder, with zero skips. They decode upright 128 × 96 PNG/JPEG output,
decode every GIF frame and its exact nominal delay, inspect GIF loop extensions,
count actual half-speed and 4× H.264 samples while checking 30 fps, and cancel
both GIF and MP4 after rendering starts. Cancellation preserves existing
destination bytes and removes staging files. GPU-less processes explicitly
skip these integration checks instead of reporting encoder verification.

The integrated native suite passed all 122 tests on 1 October 2026 on Apple
silicon, macOS 26.7, with zero failures and zero skips. Actual GPU and encoding
tests ran. Android's unit tests, lint, and debug assembly also passed.

Ten sharing tests verify all four output formats, committed immutable PNG pixel
parity, unique owner-only staging directories, cancellation and failure cleanup,
picker dismissal, retained file lifetime after closing the source window,
selected-service cancellation, interrupted presentation, and flipped-view
popover placement. Lifecycle tests use inert services and send nothing.

Five canvas keyboard tests cover international Option-generated brackets,
Command/Control responder routing, non-bracket Option combinations, and normal
tool, pan, Escape, and Delete commands. International brackets and modified
letters reproduced failures before their fixes and passed afterward. Native
document and field-editor undo-routing regressions also remained green.

The universal release bundle contains arm64 and x86_64 executables with a
macOS 13 minimum deployment target and only Apple/system dynamic dependencies.
Strict code-signature validation, ZIP integrity, SHA-256, shader synchronization,
and shell syntax checks passed. After copying the app to a fresh directory with
spaces outside the checkout, its bundled smoke test passed on both Apple silicon
and Intel through Rosetta. It checks GPU identity, a brush edit, project
save/reopen, and pinned revisions using resources physically inside the app.

The installed app was launched and exercised through its real windows:

- Imported the procedural sample and a real Android serializer fixture package
  containing all twenty tools, four lenses, Fusion, effects, crop, and two pins.
  Painted Smear and Fusion strokes, captured GOOvie
  pins, selected them, played and paused the strip, and used native undo/redo.
- Expanded a disabled Bulge section without enabling it, typed its amount,
  enabled it, and confirmed the effect and setting survived save/reopen. In the
  final build, entered `45%`, used native text undo, committed with Return and
  Tab, and saved an active effect edit with Command-S before pressing Return.
  The saved JSON and reopened inspector both retained the exact 0.45 amount.
- Saved a `.meltorama` package with the native save panel and reopened it with
  Command-O. Original source bytes and pinned revisions survived.
  Save As created an independent project while retaining the original source
  bytes in both. Command-Option-Shift-S opened AppKit's Save As panel.
- Exported a 1200 × 900 PNG and an H.264 MP4 through the native export sheets
  and save dialogs. Independent decoder checks cover JPEG and animated GIF.
  The native sharing picker displayed encoded PNG and MP4 previews and services
  after the export sheet dismissed. The final picker anchored beneath the
  toolbar. Escape dismissed both and removed their private temporary outputs;
  no external service was invoked or sent anything.
- Placed and selected a lens, cropped a document containing a selected frame,
  and used Undo to restore its image dimensions and captured pin. The crop
  check reproduced a stale SwiftUI binding crash before the fix; the same
  interaction passed afterward.
- Resized a 1240 × 820 window to approximately 902 × 612. The palette,
  workspace, inspector, and frame strip remained usable. Inspected both
  dark and light appearance, including rendered frame thumbnails. Entered and
  left full screen with Control-Command-F and restored System appearance in
  Settings. Native document tabs kept two open projects distinct. Command-1
  reported 100% on the Retina display. The Android fixture's fractional crop
  opened as exactly 960 × 720 pixels, matching Android's rounding.
  Rechecked the final inspector at 1240 × 820 and approximately 904 × 614 with
  an expanded effect and persistent scrollbar; percentage labels and controls
  stayed visible. Tab committed Strength and moved to the next number field.
- On the Swiss keyboard, Option-5 reduced brush size from 12% to 10.43% and
  Option-6 restored 12%. Command-C and Option-C kept Brush selected, while
  ordinary H/C/L/B selected Hand/Crop/Lenses/Brush. The bracket and Command-C
  failures were reproduced in the app before the fix and passed afterward.
- Inspected the final accessibility tree: effect reset, Fusion add, playback,
  timeline hiding, frame ordering, and frame deletion expose localized action
  names rather than SF Symbol identifiers. This verifies labels, not a complete
  manual VoiceOver workflow.

The UI automation connection timed out at a native save panel. A process
sample showed the application's main thread normally waiting for events.
After an approved restart, Fusion import/paint/save, compatible project open,
native tabs, full screen, and appearance were exercised successfully. Saved
Fusion source bytes matched both originals exactly. Chinese UI and VoiceOver
were not exercised manually; localization has automated coverage.
Physical Intel hardware and macOS 13 were not available for testing.

Extreme-input regressions use real 65,535 × 1 and 1 × 65,535 PNGs accepted by
ImageIO. At 10% Fit and 1% brush size, a 100-point off-photo drag previously
required millions of stamps and could stall Float accumulation indefinitely.
A safely bounded pre-fix segment reproduced the missing work limit; the exact
plateau was established arithmetically without hanging the app. An isolated
pre-fix core process also reproduced the out-of-Int32 noise conversion trap.
The repaired paths preserve ordinary output bit for bit, limit oversized
segments to 4,096 samples before copies, keep their first responsive stamp and
endpoint, and ignore nonfinite input. Twelve core input tests pass, including
continuation, pending movement, Float overflow/underflow, and noise bounds.
Two native extreme-image tests verify GPU preview, 24-way symmetry, exact
undo/redo, original image bytes, and atomic project save/reopen. Four zoom tests
cover repeated steps, gesture bounds, invalid multipliers, and Actual Size.
In the rebuilt app, the extreme horizontal image accepted a 100-point drag at
minimum zoom and brush size, remained responsive, and supported keyboard
undo/redo and Save. The saved stroke reopened successfully after relaunch.
Thirty Zoom Out and forty Zoom In shortcuts stopped at usable bounds; Actual
Size still reported 100%. The final minimum-zoom readout showed 0.20% with no
clipping. Small zoom percentages now retain decimal precision.

Additional regressions were observed failing before their fixes: native close
approved an unfinished gesture without saving it; active numeric text was
serialized too late or reapplied after Revert; Copy Image copied a small cached
preview and replaced the clipboard on failure; imported fractional crops used
different pixels from Android. Automated boundaries now verify pending brush
and lens autosave before close, synchronous numeric commit, separate native text
undo, partial-text preservation during background autosave, success/failure
Revert behavior, full-resolution clipboard/export parity, clipboard preservation
on failure, and Android's exact crop rounding. Resource fixtures cover both
SwiftPM bundle layouts and relocated path aliases.

Two more GPU regressions verify recovery after rejected source/Fusion decoding,
including retained revision identity and Fusion cover geometry after a crop.
Both reproduced stale or missing pixels before the fixes and now match a fresh
replay. Native read/Revert also completes bounded pixel decoding before replacing
live work. A metadata-success/decoder-rejection fixture could not be reproduced:
ImageIO accepts many partial images and supplies recovered pixels. That read
change is defensive hardening, with existing read/revert boundaries verified.

## Tactile console preview, 1 October 2026

Tag `v2.0.1` preserves the previously exercised native interface at `94dc117`.
The following presentation changes build on that baseline: glossy brush domes,
opaque satin panels, inset modes, raised actions, a recessed workspace, mounted
sample cards, and a graphite filmstrip. Effect enabling and expansion remain
independent. AppKit documents, canvas input, buffered numeric fields, and export
code are unchanged.

All 122 native tests passed with zero failures and zero skips after integration.
The universal release bundle built, passed strict signature validation, and
passed relocated GPU/document smoke tests on arm64 and x86_64 through Rosetta.
A source and native font-metrics audit checked pane widths, compact effect
headers, disabled/focus states, opaque fills, reduced-motion handling, and
contrast. It led to smaller tool cards and a wider minimum palette to retain
long tool labels with persistent scrollbars.

Actual appearance and interaction checks for this new presentation are still
pending. UI automation reports that the Mac is locked and cannot be unlocked
automatically. This preview must not inherit the baseline's visual QA claims;
welcome/editor appearance, pointer targets, focus, selection, disclosure,
typing, save/reopen, export, and resizing need another pass after manual unlock.

## Elastic photograph icon, 1 October 2026

The new original icon master is checked in with its generation provenance and
complete prompt. Native packaging produces all ten standard iconset slots in
sRGB, with alpha preserved. Apple's icon compiler successfully encoded ICNS
and decoded all ten slots again. The artwork was inspected on light and dark
backgrounds at 16, 32, 64, 128, and 512 pixels. At 32 pixels its white frame,
bright photograph, and berry curl remain distinct. The installed app packages
the ICNS, license, notices, and provenance rather than relying on a development
asset path. Actual Dock appearance remains unverified while the Mac is locked.

## Build entry point and installation, 1 October 2026

`scripts/build.sh --install` built the release app and installed version 2.0.4
into `/Applications/Meltorama.app`, returning exit status zero. Strict signature
verification passed on the installed bundle. Its noninteractive smoke test used
the installed resources, rendered through the native GPU, and saved/reopened a
project successfully. All 122 native tests passed with no failures or skips.

Twelve isolated CLI regressions passed after reproducing the original failures.
Some tests cover several scenarios. They exercise first installation,
replacement, absolute-path validation, debug forwarding, paths with
spaces, unrelated working directories, dry runs, copy/signature failures,
publication failure, interruption, failed rollback, destination races, and
optional launch failure. Replacement is verified on the destination volume
before moving the old app; failed rollback retains and reports its backup.
These tests are included in the hosted macOS CI job. They do not substitute for
actual window/Dock appearance checks, which remain pending manual unlock.

## Native controls and colorful icon, 1 October 2026

The layout and native controls from `v2.0.1` were restored, with an adaptive
mint/aqua window tint in Light appearance and teal in Dark. The custom metal
panels, domes, and film decoration were removed. Later document, renderer,
recovery, and installation fixes remain. Effect reset, Fusion add, and timeline
close have explicit 24-point click targets within the compact layout.

All 130 native tests passed with zero failures and zero skips outside the
filesystem sandbox, including GPU replay, document input, and encoders. All
twelve isolated build/install regressions passed. The shader translation check
and `git diff --check` passed. The icon packager produced all ten exact-sized
sRGB representations; Apple's ICNS compiler encoded and decoded them, and every
decoded pixel was verified opaque.

`scripts/build.sh --install` built the release app and installed version 2.0.6
(build 10) in `/Applications/Meltorama.app` with exit status zero. Strict
signature verification and the installed GPU/edit/save/reopen smoke test
passed. The universal archive's checksum and signature passed, and a relocated
copy in a folder with spaces passed the same smoke test on arm64 and x86_64
through Rosetta. Both Mach-O slices retain a macOS 13 deployment target.

The debug app launched with the restored controls. Its actual Dark welcome
window and system-rendered application icon were inspected: the picture fills
the rounded icon without the previous white surround, and the welcome divider
reserves only its horizontal line. Accessibility exposes descriptive names for
all four segmented modes. Further interactive checks paused when the Mac
locked; Light appearance, editing, file dialogs, export, and resizing need a
fresh pass on this presentation after manual unlock.

The first completed PR review led to native bordered frame buttons for system
press/focus feedback and contrast-aware selection outlines, plus stable caption
spacing. The request to shrink the icon onto an inset legacy tile was declined
against the user's full-picture direction. Older macOS icon corner treatment
remains visually unverified; the artwork documentation now states that limit.

## Original native presentation restored, 1 October 2026

The document window and toolbar configuration match `v2.0.1` at `94dc117`.
The transparent titlebar and blanket window tint were removed. The original
four mode buttons, plain monochrome tool rows, narrow palette, neutral system
surfaces, and 48-point welcome hand were restored. A local lime accent marks
selection and the welcome illustration. Later document/input/recovery fixes,
compact effect headers, 24-point secondary actions, and responsive welcome
and GOOvie views remain.

All 130 native tests passed with zero failures and zero skips, including GPU
replay, document input, and encoders. The debug application built with its
bundled photographic icon and provenance. Apple's icon compiler encoded and
decoded all ten representations; dimensions, sRGB, and every pixel's opacity
passed validation. The 128- and 32-pixel artwork was inspected.

The icon is edited from Karen Arnold's real CC0 photograph. Its source,
license record, exact edit prompt, and source/master hashes are retained in
`macos/Artwork/`. This is a photo-derived edit, not an untouched photograph.

The actual app was inspected in Light and Dark appearance. Its opaque titlebar
and toolbar align, the four independent mode buttons and monochrome tools are
restored, and the welcome hand is 48 points with a lime accent. Resizing from
1240 × 820 to 908 × 614 with persistent palette/inspector scrollbars retained
all four modes at the 142-point palette minimum. Taffy Pins truncates there;
its localized help and full accessibility name remain available.

Native text undo and Return/Tab commits were exercised. Bulge expanded while
disabled, then enabled at 45% and retained that value when collapsed. A Smear
stroke, two captured pins, keyboard undo/redo, Command-S, and native save/reopen
retained revision 1, both pins, and Bulge 0.45. Native PNG export decoded as
1200 × 900. Playback and pause worked. Native bordered frame buttons reproduced
clipped thumbnails; plain frame cards displayed the complete thumbnails at both
window sizes in Light appearance.

Closing and reopening Settings failed twice before setting
`isReleasedWhenClosed = false` on the delegate's cached window. After rebuilding,
Command-comma, close, Command-comma reopened Settings successfully. This manual
regression covers the delegate's private window lifetime. Light → Dark → System
switching worked and System was restored.
The standard About panel displayed the photographic icon as a full rounded
picture without a separate plate on macOS 26.7. Dock appearance, older macOS
icon treatment, Chinese labels, and manual VoiceOver operation remain unverified.

`scripts/build.sh --install` built and installed release 2.0.7 (build 11) with
exit status zero. The installed signature and GPU/edit/save/reopen smoke test
passed; its real welcome window and About panel confirmed the final version
and artwork. The universal ZIP passed its checksum and integrity checks. A
relocated copy in a folder with spaces passed strict signature validation and
the same smoke test on arm64 and x86_64 through Rosetta. Both slices retain a
macOS 13 minimum deployment target. All 130 native tests passed again after
the Settings lifetime and thumbnail fixes.

## Optional themes and generated dog icon, 1 October 2026

All 134 native tests passed with zero failures and zero skips, including GPU
replay and export encoders. Four new theme tests cover persisted-value fallback,
the exact Classic palette, accent contrast, and selection text contrast.
All eight themes pass 4.5:1 on their native and washed surfaces under Aqua,
Dark Aqua, and both Increase Contrast appearances. Localization covers every
theme name. All twelve build/install script regression tests also passed.

In the actual app, each of Classic, Candy, Tangerine, Ocean, Grape, Mint,
Sunshine, and Cherry was selected under Light and Dark appearance. Native radio
dots, swatches, localized accessibility names, and the complete wrapped Settings
copy rendered correctly. Settings closed and reopened successfully.
Candy survived quitting and relaunching the app.

A live theme change preserved an uncommitted `45%` effect draft and its
field focus while the model still held zero. Native text Undo restored zero;
Redo and Return committed 0.45. The original titlebar, tool rows, independent
effect disclosure, and welcome hand remained intact. Theme changes reached
both open document tabs and an already-open export sheet without resetting
its PNG/original-resolution options.

Smear painting, frame capture, Command-S, native close, and Command-O reopening
retained revision 1, one pin, and Bulge 0.45. The saved JSON hash remained
unchanged through theme switches, and contained no theme preference.
PNG exports under Candy and Ocean both decoded as 1200 × 900 and had the
same SHA-256: `a33772980bf70dac368b6a88cd760ecd5fc230b2b2bcd58935a1308b9ea55e80`.
Resizing from 1240 × 820 to approximately 910 × 614 retained the tool modes,
expanded effect, native titlebar/toolbar alignment, and complete frame card.
Classic and System appearance were restored after testing.

The invented dog icon was generated without a real pet photograph, using the
previous generated landscape only as a melting-curl composition reference.
The master and exact prompt are recorded in `Artwork/README.md`. Apple's
icon compiler encoded and decoded all ten iconset slots. Dimensions, sRGB,
and full opacity passed validation; 128- and 32-pixel artwork was inspected.
Manual VoiceOver, Chinese UI, and theme-picker keyboard navigation with macOS
Keyboard Navigation enabled remain unverified; this Mac's normal Tab setting
skipped non-text controls.

`scripts/build.sh --install` installed 2.0.8 (build 12) successfully.
The installed app's actual About panel confirmed the version and displayed
the complete generated dog and melting curl. The universal arm64/x86_64
bundle passed strict signing, ZIP integrity, and checksum checks; both slices
declare macOS 13 and passed bundled GPU/edit/save/reopen/pinned-revision smoke
tests on Apple silicon and through Rosetta.
The same smoke tests and strict signature verification passed after relocating
the bundle to a fresh folder with spaces outside the checkout. The installed
icon provenance matched the checked-in artwork record.

## Coordinated window palettes, 1 October 2026

The 2.0.9 candidate defines separate opaque sRGB colors for chrome, panels,
workspace, and accents in seven authored themes. Classic retains the original
native surfaces. All four appearance variants pass the palette tests,
including accent/primary-text contrast, secondary-text opacity, selected rows,
and distinct background roles. English and Chinese localization tests pass.

The final local run passed all 144 native tests with no skips (113 Mac,
31 core), including GPU replay and export. All 12 installer regression tests
passed. A new integration test verified real Foundation defaults-notification
delivery to an existing window using an isolated suite, without a synthetic
notification or changes to standard application preferences.

A real PhotoCanvas test also confirmed that AppKit invalidates its background
on inherited appearance changes without a SwiftUI bridge or window-theme
controller. Actual drawing into an explicit sRGB buffer matched Candy and
Ocean through light, dark, and light appearances. The review's stale-repaint
concern was not reproduced, so no application redraw override was added.

The first actual preview exposed content beneath the colored native titlebar.
The regression then reproduced a 66-point overlap before correction. A retained
content container now constrains the editor host to `NSWindow.contentLayoutGuide`;
the regression passes across theme changes and resizing, while retaining host,
toolbar, document title, field draft, focus, and undo identities.

`scripts/build.sh --install` installed 2.0.9 (build 13) successfully, and the
installed signature passed strict verification. The preserved universal
candidate passed ZIP integrity, strict signing, and GPU/edit/save/reopen/pinned
revision smoke tests on Apple silicon and through Rosetta. Both slices declare
minimum macOS 13. The generated dog artwork is unchanged.

On 2 October, the unlocked Mac completed the corrected installed app's visual
and interaction pass. All eight themes were inspected in Light and Dark:
native titles, traffic lights, aligned toolbar items, panels, workspace, and
the original welcome hand remained visible. Settings displayed every palette
and its three swatches, including after repeated closing and reopening.

The Candy Blobs sample accepted brush edits, keyboard undo/redo, percentage
entry committed by Tab and Return, and Command-K frame capture. Bulge's
disclosure expanded independently of its checkbox; collapsing an enabled
45% effect removed its body while retaining the value. The native Save panel
wrote a new test package, and the native Open panel reopened its two stroke
revisions, 45% Bulge, and animation pin. Brush strength resets to its normal
session default on reopen; it is not a serialized document property.

Live switching from Candy to Ocean retained the photo, effect, frame, and
clean saved state. Full-resolution PNGs exported through the native dialogs
under those two themes were byte-identical: 1200 by 900 pixels, 312136 bytes,
SHA-256 `31b8ae5641df3779cc6387a1faa87fe1cf195e27c5cfa089529d48a0d0cac109`.
The palette changes only the surrounding workspace, not exported pixels.

Resizing from 1240-point width to 871 points retained the native toolbar,
readable percentage suffixes, scrollable inspector, and complete frame card;
the timeline placed capture actions on a second row. Creating a second
document used native tabs. Both tabs adopted Candy/Dark without content
overlapping the toolbar or tab bar. About reported 2.0.9 (13). The app was
left on a clean welcome document with Candy/Dark restored, and the saved test
package was retained. Uncommitted field-draft, focus, and undo identity during
theme changes remain covered by the AppKit integration test rather than a
claim that activating Settings preserves text-field focus.

PR #122 completed two review rounds without a confirmed important application
defect. A mistaken documentation statement about the public
`NSWindow.layoutIfNeeded` category was corrected. Physical Intel hardware,
macOS 13 runtime, larger accessibility text sizes, VoiceOver navigation, and
an interactive Chinese-language pass remain unverified.

## Interactive preview and toolbar boundary, 2 October 2026

The previous preview scheduler rejected every frame superseded by a newer
request. Deterministic completion-controlled regressions reproduced the canvas
starvation during continuous stroke and effect input before the fix. Eight
tests now cover progressive publication, one pending latest snapshot, animation
progress, incompatible content transitions, same-source Revert, undo/reset,
stale errors, and closed-session completions. The full native suite passed
153 tests with zero failures and zero skips on this Mac, including GPU and
export checks. The native titlebar separator regression failed before the fix
and passes across all eight themes in light and dark appearance.

Isolated optimized ARM measurements used the procedural 1200 by 900 Candy
Blobs source with 15 committed strokes and Stretch/Spike enabled. Median
cached rendering took about 1 ms; incremental batches of 16, 64, and 256
stamps took about 2, 5, and 17.5 ms. Initial replay of 4000 stamps took about
256 ms. GPU-to-CPU readback cost roughly 1 ms. These are engine measurements,
not window FPS or a measured comparison with an Android device.

An optimized benchmark using the existing Stroke, Portals, and Symmetry code
reproduced repeated array copying when the stamp loop retained the entire
active stroke. Appending 32000 stamps took approximately 395 ms with the old
loop and 3.5 ms when retaining only the tool, with identical resulting strokes.
The input loop now uses that scalar capture. Small uniform-cache and GL-state
experiments showed no consistent benefit and were left out of the change.

## Remaining limitations

- The native app uses Apple's system frameworks and the original GLSL kernels.
  OpenGL is deprecated on macOS; migrating the content renderer to Metal is
  future work. The surrounding windows and controls are native.
- Interactive rendering uses a 1400-pixel longest-edge preview. Larger photos
  retain their original bytes and export resolution, but zooming cannot reveal
  source detail beyond that preview.
- Still images whose upright cropped dimensions exceed the Mac's maximum GL
  texture size require an explicit smaller export size. Tiled full-resolution
  export is not implemented; no automatic resolution loss is presented as a
  full-resolution result.
- GIF is a palette format and is limited to 480 pixels. H.264 output is limited
  to a 1920-pixel longest edge, matching the Android movie sizing policy.
- An unsigned or ad hoc signed local `.app` is installable by copying it to
  Applications. Public distribution with Developer ID notarization requires
  the owner's Apple signing identity; it is not inferred from a local build.

- Android's private project shelf is adapted to normal Finder documents,
  AppKit save/close commands, and durable recovery drafts. Android has no
  user-facing project-transfer command; compatibility is verified at the
  existing on-disk package format.
