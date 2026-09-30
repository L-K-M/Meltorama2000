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

The integrated native suite passed all 96 tests on 30 September 2026 on Apple
silicon, macOS 26.7, with zero failures and zero skips. Actual GPU and encoding
tests ran. Android's unit tests, lint, and debug assembly also passed.

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
- Exported a 1200 × 900 PNG and an H.264 MP4 through the native export sheets
  and save dialogs. Independent decoder checks cover JPEG and animated GIF.
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

The UI automation connection timed out at a native save panel. A process
sample showed the application's main thread normally waiting for events.
After an approved restart, Fusion import/paint/save, compatible project open,
native tabs, full screen, and appearance were exercised successfully. Saved
Fusion source bytes matched both originals exactly. Chinese UI and VoiceOver
were not exercised manually; localization has automated coverage.
Physical Intel hardware and macOS 13 were not available for testing.

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
