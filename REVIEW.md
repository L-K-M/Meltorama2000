# REVIEW.md — living review backlog

Findings from AI review rounds (GLM 5.2 on PRs, periodic deep reviews) and
their dispositions. Stable IDs; nothing is deleted, only resolved or
declined with reasons. Point-in-time review snapshots archive under
`docs/reviews/`.

Legend: 🐞 bug · 🔧 improvement · ✨ idea · ⬜ open · 🟢 done · ⏸️ declined/deferred

## Open

- **G-1** 🔧 🟢 Session files under `cacheDir/sessions` are never pruned.
  Resolved in roadmap #3: `ImageLoader.sweepSessions` deletes everything
  but the live session on each import.
- **G-2** 🔧 🟢 Strokes are lost on process death (the log lives only in
  the ViewModel). Resolved in PR 17: `StrokeLog.snapshot`/`restore` plus
  `ProjectStore` persist the document, and a session that has saved a
  project reopens it after process death (`KEY_PROJECT_ID` in saved
  state). Work between the last save and the death is still lost — the
  autosave follow-up under ANALYSIS SOL-34.
- **G-3** ✨ 🟢 The stamp pass renders a fullscreen quad per stamp at field
  resolution. Fine at ≤1024 fields (~5 Mpx per dozen stamps); a scissored
  sub-quad is the known optimization if device profiling ever disagrees.
  Done: the quad is now scissored to the brush disc
  (`engine/core/StampBounds`, `PingPongField.renderPassIn`). What made it
  safe to skip those fragments is that they were never doing anything —
  outside the disc the falloff is 0 and every `STAMP_FRAG` branch reduces
  to an identity copy of the fragment's own texel. Ping-pong is what made
  it *look* necessary, since the destination then keeps the state from two
  passes ago; the field now repairs exactly that difference with a blit of
  the previous stamp's rect, so per-stamp cost goes from the whole field
  to twice the brush disc. A typical radius-0.1 stamp on a 1024² field
  touches under 4% of it (`StampBoundsTest`). Not done for profiling
  reasons — profiling never disagreed — but because stamp COUNT is the
  scaling problem G-6 and the symmetry proposal both run into, and this
  is the per-stamp half of it.

- **G-4** ✨ ⏸️ Pool the per-batch stamp lists in the touch path (GLM 5.2
  round 1, PR #2, info-level). Each batch crosses the UI→GL thread
  boundary, so per-batch ownership is inherent; eliminating allocation for
  real means a pooled ring buffer of primitive arrays. Revisit if frame
  traces on a low-end device show GC pressure during fast drags.

- **G-5** ✨ ⬜ True full-resolution export above the 4096 budget cap
  (`ExportSize.EXPORT_MAX_DIM`). Needs tiled rendering with
  displacement-bounded source tiles — the output tile must sample source
  up to max|D| beyond its edges, so the tiler needs a field-magnitude
  bound first. Today >12 MP sources export at ~12 MP; revisit when a real
  user asks for native 48 MP output.

- **G-6** ⚠️ 🟢 Pumped tools (Grow/Shrink/Smooth/UnGoo) emit ~60
  stamps/s while held, so long holds inflate the stroke log and the
  full-replay cost undo/redo/export pay (a 5 s hold ≈ 300 field passes).
  Stamps can't be naively merged — warp-of-warp compounding is the pump
  feel — so the real fix is field snapshot checkpoints every N strokes
  (replay from nearest checkpoint instead of identity). Do when replay
  latency becomes user-visible.
  Done for the interactive path: `rebuild` (undo/redo/Reset) now starts
  from a `FieldSnapshot` when one still covers a prefix of the log,
  `engine/core/ReplayCheckpoints` deciding when a snapshot is worth its
  blit. Two departures from the sketch above, both because "every N
  strokes" measures the wrong thing: the trigger is **stamps**, since
  the whole motivating case is a single stroke carrying 300 of them, and
  the checkpoint deliberately lags the head by `TAIL_STROKES` so the
  first undo doesn't destroy the thing that makes undo fast. Undoing
  deeper than the tail invalidates it and pays one full replay, after
  which a new checkpoint forms — the cache is pure optimization, and
  every way of being wrong about it costs only the replay that used to
  happen unconditionally.
  Not done: export and keyframe endpoint materialization still replay
  from identity. Export builds its own field at a different size (so a
  preview checkpoint cannot apply), and endpoints are already cached by
  revision id. Revisit if a 64-keyframe strip over a heavy log becomes
  the complaint.

- **G-7** ⚠️ ⬜ `renderMovie` runs as one GL runnable, and
  `GLSurfaceView`'s `onPause()`/`surfaceDestroyed()` block the MAIN
  thread until the GL event queue drains (AOSP-verified), so
  backgrounding mid-export freezes the app for the export remainder.
  Typical 2–8-keyframe GOOvies ≈ 0.5–3 s — fine; a 64-keyframe strip
  over a heavy stroke log ≈ 15–45 s — ANR/kill territory. Fix is
  chunked rendering: per-export state in a renderer-held MovieSession,
  ~30 frames per runnable, self-requeue via a view-provided queueEvent
  hook, end-of-chunk restore tolerating dead preview surfaces. Do
  before raising movie length or promoting long strips.

## Won't do (for now)

- **G-W2** ⏸️ Direct unit tests for `EditorViewModel` verbs
  (`repunchSelectedKeyframe` et al; GLM on PR #26, info-level). The
  constructor takes five injected collaborators and `init` decodes an
  image through `ImageLoader` off a `SavedStateHandle` route, so a real
  test needs a mocking framework plus `coroutines-test` — neither is on
  the classpath, and "keep dead deps for future tests" is already an
  explicitly declined position (ANALYSIS.md). The fragile logic was
  pushed down into pure types instead and IS covered:
  `KeyframePinTest` (a pin survives undo/redo/reset/branch truncation —
  the actual reported bug), `KeyframeStalenessTest` (the Update
  affordance's trigger), `GoovieHintTest` (the nudge wording).
  Reconsider as a whole when a coroutine-level VM test is genuinely
  needed; adding the deps is one catalog edit at that point.

- **G-W1** ⏸️ Packed-RGBA8 displacement-field fallback for GLES3 devices
  without renderable float formats (`EXT_color_buffer_half_float` /
  `EXT_color_buffer_float`). Such hardware is essentially nonexistent in
  practice; the engine surfaces a clear error instead. Reopen if a real
  device report shows the error string.

## Sol PR review dispositions

- **PR #118: relative install folder and Python tracebacks — applied.** The
  install override must be an absolute path, including dry-run validation.
  Expected rename failures print a concise error while retaining rollback.
  The quick start uses one install command, and the fixture asserts its
  default-path safety substitution. Its twelve tests cover multiple scenarios.
- **PR #118: repeat dependency checks — already verified.** The stale catalog
  header was removed with #112. Both action pins were checked against their
  upstream tags. Wrapper pinning/version policy remains the existing deferred
  concern; this install change does not upgrade the Gradle actions.
- **PR #118: signal and fixture semantics — verified/deferred.** The interrupt
  mock signals the transaction subshell that owns the real EXIT/TERM rollback
  traps. Intentional false-return helpers are called in condition contexts.
  Fixture install/failure variables override the host, and the mock builder
  does not read signing variables. Additional symlink/mode assertions are
  deferred; the real installed bundle passed strict signature verification.

- **PR #111: pin the CI Java setup action — applied.** The native integration
  pins the same verified upstream commit already used by the release workflow.
  The adjacent wrapper-action pinning suggestion concerns existing behavior;
  it is deferred rather than widening this dependency update.
- **PR #115: add Android instrumentation and screenshot suites — declined.**
  This repository deliberately uses JVM-only tests and has no emulator CI job.
  The Navigation release notes were checked against the typed routes (no deep
  links), and all updated dependencies compile and pass existing unit tests and
  lint in CI. Android navigation restoration and appearance still require
  device verification; do not claim that compilation exercised them.
- **PR #112: KSP must match a specific Kotlin compiler version — refuted.**
  KSP's release notes document that its version is independent of the Kotlin
  compiler since KSP 2.3.0. The current PR's Android CI completed both
  `kspDebugKotlin` and `kspDebugUnitTestKotlin`, compilation, tests, lint, and
  APK assembly. KSP 2.3.12 requires AGP 8.12 or later, which this project
  satisfies. Sources: [KSP 2.3.0](https://github.com/google/ksp/releases/tag/2.3.0)
  and [KSP 2.3.12](https://github.com/google/ksp/releases/tag/2.3.12).
- **PR #113: the AGP update requires a newer wrapper — refuted.** The
  [official AGP compatibility table](https://developer.android.com/build/releases/agp-9-4-0-release-notes)
  specifies a minimum Gradle version below the wrapper already committed when
  this PR was reviewed. Its Android CI passed. The stale pairing comment was
  replaced with a compatibility instruction so independent updates cannot
  leave contradictory version numbers in prose.
- **PR #114: the wrapper JAR was not regenerated — refuted.** The PR changes
  the JAR, whose SHA-256 matches Gradle's official distribution checksum. The
  Windows safety-net block matches the upstream wrapper script. Unchanged
  distribution URL validation and checksum policy are outside this update;
  wrapper-validation CI passed and Android CI executed successfully.

- **PR #117: shrink the bootstrap or retrigger with labels — refuted.** The
  pinned action has no completed-chunk checkpoint. Incremental/hybrid scope
  requires a completed baseline; PR #116's failed bootstrap has none and
  therefore restarts full coverage. The workflow does not subscribe to the
  `labeled` event, so a label alone cannot retrigger it. Push or reopen after
  the trusted workflow update merges. The port had one completed timeout;
  superseded cancellations are not failed review rounds.
- **PR #117: lower reasoning effort instead of smaller chunks — declined.**
  The input already exists and is set to high. Keep the established review
  depth, start with sections the failed run successfully completed, and budget
  for their measured timing. The pinned splitter plans 49 requests for the
  final port. Eleven successful fallback requests averaged 5.903 minutes;
  their projection is 289.27 minutes, so the revised 330-minute step leaves
  about 41 minutes. This estimate is not a completed port review. Chunk size
  and reasoning are trusted workflow inputs, not per-PR label overrides.

- **PR #24: per-revision lazy materialized lists — declined.** The repeated
  active-state read concern was valid and fixed with one active-revision cache.
  Caching every historical prefix would restore the quadratic retained-reference
  behavior SOL-6 removes.
- **PR #32: make `MovieEncoder.finish()` idempotent — declined.** The encoder
  lifecycle requires exactly one finish. Marking a failed muxer stop as complete
  and returning from a retry can turn a prior finalization failure into apparent
  success; the render already fails and release remains best-effort.
- **PR #37: release files missing from the publisher — refuted.** The original
  `dist/*.apk` and `dist/*.sha256` inputs remain in the release step. A named
  `actions/download-artifact` download extracts contents directly into its
  requested path; an artifact-name subdirectory is the multi-artifact behavior.

## PR #42 review dispositions (GOOvie speed + GIF)

- **Non-exhaustive `when (format)` wedges the UI — refuted.** The claim was
  that Kotlin does not enforce exhaustiveness for `when` *statements*, so a
  future `MovieFormat` entry would silently skip both branches and leave
  `exportingMovie` stuck on "Filming…". Kotlin has made that a compile
  ERROR since 1.7, and this repo is on 2.4.10. Verified by adding a third
  enum entry locally: `compileDebugKotlin` fails with "'when' expression
  must be exhaustive. Add the 'WEBM' branch or an 'else' branch" at
  `EditorViewModel.kt` AND at `MovieExportSheet.labelRes` — the review
  asserted only the latter would fail. The suggested `else -> onResult(false)`
  would DELETE that compile-time guard and turn a build failure into a
  runtime one. Do not add it.
- **Tighten `GifEncoder.addFrame` to `delayCentis >= 2` — declined.**
  `GifEncoder` is a format writer; 0 is a legal GIF delay ("as fast as the
  viewer can"). The ≥2 floor is *pacing policy* and belongs to
  `MovieSpec.gifDelayCentis`, which owns it and is tested for it. Moving the
  policy into the writer would make the encoder refuse valid GIFs.
- **`renderGif` should delete its partial file on failure — declined.**
  The work file's lifecycle belongs to the caller by contract
  (`MovieSaver.createWorkFile`: "caller owns deletion"), and
  `EditorViewModel.onMovieRendered` deletes it in a `finally` on every path,
  failure included; `createWorkFile` also clears the directory before the
  next export. A second owner of that delete would be duplication, not
  safety. The review itself notes this matches `renderMovie` and is not a
  regression.
- **Plurals resource for `movie_length` — declined (non-issue).** The value
  is always a decimal string ("1.0", "3.6"), and English takes the plural
  form for decimals regardless of value; the app ships one locale. Revisit
  with the first translation, not before.

## PR #119 review dispositions (native Mac restoration)

- **Timeline feedback and contrast — applied.** Frame thumbnails now use
  native bordered buttons for press/focus feedback. Only selection adds an
  outline, which widens with Increase Contrast; captions reserve the checkmark
  space. No custom material or ButtonStyle is restored.
- **Legacy icon inset — declined.** The user rejected the small picture on a
  system backdrop and asked for the picture to fill the icon. The current
  macOS 26 system-rendered icon was inspected with that composition. Keep it
  edge to edge; do not substitute an unverified 824/1024 inset recipe. Older
  macOS corner treatment is explicitly unverified. A separate tested legacy
  variant remains future work. Current [Apple icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)
  asks for square unmasked layers; it does not prove older ICNS masking.
- **Original artwork link — applied.** Provenance now links both the original
  master and prompt at the verified commit `9f0f268`.
- **Reset requires two Undo commands — refuted.** Both synchronous edit calls
  are unchanged from `v2.0.1` and use AppKit's event grouping. An independent
  Foundation harness verified that both registrations undo together with
  `groupsByEvent` enabled. Consolidating the mutations is optional cleanup.
- **Canvas can paint over neighboring panes — refuted.** PhotoCanvas draws
  inside NSView's default drawing clip and never overrides
  `wantsDefaultClipping`. AppKit clips to the view bounds before calling draw,
  as documented by [Apple](https://developer.apple.com/documentation/appkit/nsview/wantsdefaultclipping).
- **Conditional packaging/model/tint claims — verified.** The generator fills
  all ten slots, the master and provenance are committed, root tint is set,
  NSColor providers are dynamic, the smoke command uses dist, and the reviewer
  workflow runs GLM 5.3. No deleted Goo types remain in application sources;
  local builds, all 130 native tests, and Android/Mac CI pass.
- **Deal Goo width and mixed button bezels — declined.** Native action sizing
  and bordered actions distinguish one-time commands from tool rows and the
  borderless panel-close control. Removing native bezels is not this task.
- **Opacity metadata guard — deferred.** The current master and decoded ICNS
  pixels were verified opaque. The proposed no-alpha guard would also reject
  fully opaque RGBA artwork; it does not test pixel transparency. A future
  asset-validation change should check pixels rather than alpha metadata.
- **Stable keyframe UUID and conditional scroller gutter — deferred.** These
  pre-existing concerns do not justify changing the compatible document model
  or the scrollbar protection during a presentation restoration.
- **Segment hover help and remaining appearance checks — unverified.** Actual
  AX inspection confirmed descriptive labels for all four native segments.
  Hover, Light appearance, Increase Contrast, focus, file dialogs, export, and
  resizing await manual unlock; no interactive pass is claimed for them.
- **Tool-color dots and effect surfaces — declined.** Removing those materials
  is the user's requested return to native controls. Effects retain independent
  enabling/disclosure and reserve no body space when collapsed.

## PR #120 review dispositions (original Mac presentation)

The completed full review covered `6ebfdd2`; binary artwork was unavailable to
the reviewer. No important correctness, build, or data-loss defect was confirmed.

- **Mode width and palette scroller overlap — refuted/declined.** Actual
  minimum-width testing with persistent scrollbars showed all four mode buttons
  inside the 142-point palette. The restored row layout reserves horizontal
  padding; re-adding a second 15-point gutter would reduce the available width.
  Long labels can truncate at the minimum, with full help and accessibility
  names retained. The inspector keeps its separate numeric-field clearance.
- **Selection outlines — deferred.** The user explicitly requested the original
  mode buttons and plain tool rows. Their selected backgrounds and accessibility
  selected traits are restored. Extra palette outlines or checkmarks would
  change that chosen reference. An Increase Contrast refinement remains a
  worthwhile separate accessibility change; the current manual checks do not
  establish a complete low-vision or VoiceOver pass.
- **Light accent below 3:1 — refuted.** An AppKit harness resolved Aqua's
  `controlBackgroundColor` to sRGB white and measured the solid light accent at
  5.3342:1. This verifies accent text/outline contrast, not the translucent
  selection wash; the proposed darker accent is unnecessary.
- **Command-modifier mode shortcuts — declined.** Command-C and Command-H are
  native Copy and Hide. Canvas B/L/C/H already route through the responder and
  leave text entry and modified native commands intact. Do not override those
  document commands to reproduce segmented-picker navigation.
- **Remove full-size content layout — declined.** The window and toolbar
  configuration match `94dc117`, and actual Light/Dark titlebar, toolbar, and
  resizing checks passed. There is no top-edge `ignoresSafeArea` dependency.
  Removing another baseline window flag is outside the requested restoration.
- **Tagline lost original callout font — refuted.** At `94dc117`, the tagline
  uses the default body font; only the sample hint uses callout. The current
  welcome hierarchy intentionally restores that reference.
- **Missing artwork, stale hashes, or deleted theme references — refuted.** Both
  binaries are committed and their SHA-256 values match provenance. The icon
  packager reads the master; it does not regenerate it. Removed theme symbols
  have zero source references, and local/hosted native builds pass.
- **Prominent Deal Goo — declined.** Its standard native button restores the
  requested original interface. The user rejected the prior prominent berry
  action alongside the rest of the tinted presentation.
- **Prose wrapping and ADR backlink — applied.** Long prose was rewrapped and
  decision 0008 now links back to 0007. The proposed checksum-heading expansion
  is optional wording; the existing file paths and hashes are unambiguous.
