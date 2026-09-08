# AGENTS.md — operating manual

The operational source of truth for agents (and humans) working on Goo.
When you learn something durable about how this repo behaves — a quirk, a
footgun, a changed convention — **update this document** in the same PR.

## Name

**Meltorama 2000** — shortened to **Meltorama** where length matters (the
launcher label, where Android ellipsizes past ~12 characters). "Goo"
survives as the verb, the material, and the name of the animations
(GOOvies), which is why the claim is *Goo Your Photos*.

The applicationId stays `ch.lkmc.goo`, and so does the package: changing
an applicationId breaks upgrades for everyone who sideloaded a build, and
no user ever sees it. The repository did get renamed, to
`L-K-M/Meltorama2000` — old links redirect, so hard-coded URLs go stale
silently. PLAN.md's *Renaming* section lists every file a future rename
would touch.

## What this app is

A KPT-Goo-style real-time photo-warping app. Read [PLAN.md](PLAN.md) first;
it is the constitution (product framing, engine architecture, roadmap).
Deviations from PLAN.md get recorded here as they happen.

## Build, test, lint

```sh
./gradlew testDebugUnitTest    # the whole test suite (JVM-only, by design)
./gradlew lintDebug            # hard CI gate — keep it clean
./gradlew assembleDebug        # debug APK
scripts/build.sh               # release APK staged into dist/
scripts/install.sh             # build + install + launch on a device
```

- JDK 17. Android SDK path via `local.properties` (`sdk.dir=…`) or
  `ANDROID_HOME`. Agent sessions: `.claude/setup-android.sh` bootstraps the
  SDK idempotently (wired as a SessionStart hook).
- Versions are pinned ONLY in `gradle/libs.versions.toml`. Never add an
  ad-hoc version to a build file; never restate catalog versions in docs.

## Toolchain quirks — don't "fix" these

- `compileSdkVersion("android-37.0")` (string form) is deliberately paired
  with `android.suppressUnsupportedCompileSdk=37` in `gradle.properties`.
  The two move together or not at all.
- There is NO `kotlin-android` plugin: AGP 9 provides built-in Kotlin
  support. Only android-application, kotlin-compose, kotlin-serialization,
  ksp, and hilt are applied.
- `app/debug.keystore` is checked in ON PURPOSE and signs BOTH build types
  (`.gitignore` whitelists it). Zero-secret CI, reproducible builds,
  sideload-only distribution — see `docs/decisions/0002`. Do not "rotate"
  it, do not add signing secrets without a recorded product decision.

## Architecture in one paragraph

Single module `:app`, packages first. MVVM with one immutable UiState per
screen (StateFlow from a ViewModel), Hilt DI, single activity, Compose +
Material 3 with a custom always-dark "goo table" theme. The warp engine is
a GLES 3.0 backward-mapped displacement field; brushes stamp kernels into
the field, the **stroke log is the document** (GPU state is a rebuildable
cache), exports replay the log at full resolution. Engine decision logic
lives in `engine/core` as pure JVM classes.

## Conventions and footguns

- Tool/feature proposals live in `docs/proposals/` as numbered
  pre-decision docs (same Status/Date header as ADRs); an accepted
  proposal graduates into PLAN.md's roadmap table, a declined one stays
  with its status flipped to `declined` so the reasoning isn't lost.
  A proposal argues for a tool and prices it — it is not a commitment,
  and it ships no engine code.
- **Tests are JVM-only** (`testDebugUnitTest`); keep decision logic out of
  composables and the GL renderer so it stays testable. No androidTest
  directory exists; adding one means adding the emulator CI job too.
- **"Works in debug, breaks in release"** is almost always a missing R8
  keep rule for a new reflection/serialization entry point — check
  `app/proguard-rules.pro` first.
- The shader math and `engine/core` reference implementations must stay
  trivially close; when one changes, change both, and let the unit tests
  pin the semantics.
- Brush geometry is computed in normalized source coordinates, never screen
  pixels — preview/export parity depends on it (PLAN.md §5.4).
- The editor's bottom controls are a **floating dock, not a rail**
  (`ui/editor/ToolDock.kt`): mode tabs (Brush/Levers/Lenses/GOOvies) own
  the bottom slot, the brush tab is a family-grouped palette grid plus a
  contextual strip (only what the active tool can use), and the whole
  tray collapses into a `ToolPuck` on stroke start. This refines PLAN.md
  §6.2's "candy-button arc" — the puck is the arc's seed, the dock its
  expanded form. Families derive from stamp *behavior* (drag the path /
  hold to pump / leave a mark), so a new `BrushTool` lands in its row
  with no UI edit; panel/tab/family logic is pure JVM in
  `ui/editor/DockState.kt` — keep it that way (tested by `DockStateTest`,
  which also caps any row at eight beads so nothing ever scrolls).
- **A GOOvie keyframe is a pin, not a canvas.** It stores
  `(revision, globals)` — the immutable `StrokeRevision` it was punched
  from — so there is no "editing keyframe 2" in place: you goo the photo
  and re-punch (`repunchSelectedKeyframe`). Two deviations from the
  original PLAN.md §4.1 wording, both recorded there:
  - Editing is NOT paused while the strip is open. The one real
    constraint is that stamps only ever reach the *live* field, so any
    edit inside the strip first flips `UiState.goovieLive` and clears the
    tween. Don't reintroduce an edit lock to "protect" the pins.
  - Pins are revisions, NOT prefix counts (and never a history cursor).
    A count indexes into `StrokeLog.strokes`, which shrinks on undo —
    that is precisely how undo used to flatten a whole strip. Revisions
    are shared, immutable, and outlive a truncated redo branch, which is
    why `rebuild` no longer invalidates the renderer's endpoint cache
    (it is keyed by `StrokeRevisionId`, which is never reused, so it
    can't lie). Don't "optimize" it back to a count.
- **GOOvie export speed scales the frame COUNT, not the frame rate**
  (`MovieSpeed`, `MovieSpec.totalFrames`). The encoder clock, the pts
  ladder and the GIF centisecond delay all stay nominal; changing that
  would mean a variable-rate MP4 and delays GIF viewers silently round.
  The strip itself still plays at 1× — speed is an export choice.
- **The GIF encoder is pure JVM on purpose** (`engine/media/GifPalette`,
  `GifEncoder`: an `OutputStream` and ARGB `IntArray`s, no Android
  types), because the LZW code-width rules are the part that can be
  subtly wrong. `GifEncoderTest` decodes the encoder's own output with an
  independent reader — keep it that way, and note that a GIF LZW decoder
  must drop its dictionary on a clear code or a stale entry answers the
  KwKwK case. Both export sinks share one tween walk
  (`GlWarpRenderer.eachTweenFrame`) so MP4 and GIF cannot disagree about
  what a GOOvie is.
- Runtime revision graphs are intentionally non-serializable. Project
  persistence stores a normalized revision table plus revision IDs rather
  than recursively serializing shared parent nodes — `StrokeLog.snapshot`
  / `restore` and `StrokeLogSnapshot`. Two rules there are load-bearing:
  `snapshot(pins)` must be given the keyframe revisions (a pin can hold a
  revision the history truncated, and it would otherwise not be written),
  and `restore` refuses a malformed table outright instead of
  half-restoring — a blank canvas over the right photo is what "lost all
  my goo" looks like.
- **A saved project's folder changes only when the user saves** (or the
  editor autosaves). Opening one copies its bytes into fresh session files
  (`ImageLoader.importFile`) because the editor treats session files as
  scratch it owns: a Fusion swap deletes the file it replaces, and
  `sweepSessions` collects whatever no session claims. Never point
  `sessionFile`/`sessionFileB` straight at `filesDir/projects/…`. Session
  files are also **write-once** — a new photo always means a new UUID
  name — which is what lets `ProjectStore.copyInto` skip re-copying a
  source of identical length and age on every autosave.
- **Everything is saved; there is no exit prompt.** Leaving the editor
  writes the document and goes (`SaveReason.LEAVE`, with a scrim while it
  runs because the first write of a session copies the photo). `ON_STOP`
  writes too — the last callback before a backgrounded process can be
  reclaimed — and a checkpoint loop (`AutosavePolicy`: quiet-after-edit,
  with a ceiling for people who never pause) covers the foreground crash
  the lifecycle can't. Throwing a goo away is a deliberate act in the In
  room, not an answer to a question on the way out.

  The dialog that used to ask, and the deliberate-vs-autosave machinery
  behind it (`projectSaved`, `discardProject`, two body strings), are
  **gone on purpose** — user-reported, PR #45. The guard only ever existed
  because the session lived in memory alone (ANALYSIS SOL-7 called it
  interim); once nothing can be lost, a prompt about losing it is a
  prompt about nothing, and the flag it needed was one more thing to get
  wrong — it did, and told users their fresh goo was "already saved".
- **`hasUnwrittenChanges` is the only saved-state question.** One property,
  read by the write-on-leave, the checkpoint loop and the Save bead. Do
  not reintroduce a second flag that stays true after a write: a
  checkpoint loop reading one would rewrite the same document forever.
  Relatedly, a checkpoint keeps the preview already on disk rather than
  re-rendering it — the replay runs on the GL thread, and a checkpoint
  fires into a pause the user is about to end.
- **Nothing evicts a project but the user.** The shelf had a cap
  (`ProjectShelf`: 20 projects / 256 MiB, oldest out) and it is **gone on
  purpose** — user-reported, PR #46. An app that always saves and then
  quietly deletes the oldest thing it saved is worse than one that never
  saved: the user cannot even predict which loss they are getting. In its
  place the In room prints the numbers a decision needs — how many goos,
  what they cost, what is free — beside per-goo delete and a
  throw-them-all-away. If you add a size limit back, it needs a product
  decision and a prompt, not a quiet sweep.
  The consequence is real and accepted: the shelf grows without bound,
  and every session that holds work leaves something on it. That is what
  the readout is for.
- **Saved projects stay out of backup.** The two backup allowlists name
  `datastore` and sharedprefs only; `files/projects` holds the user's
  photos, and "nothing leaves your device" is a promise the About screen
  makes out loud. Adding a project path there is a product decision.
- **User-visible wording is a string resource, everywhere.** ViewModels
  and the GL renderer have no Context and no locale, so failures travel as
  `@StringRes Int` (`ExportEvent.Failed`, `UiState.error`,
  `GlWarpRenderer.onUnsupported`) and the exception's own English text
  goes to Logcat. The app ships `values/` and `values-b+zh+Hans/`, listed
  in `res/xml/locales_config.xml` (Android 13+ per-app language) — add a
  locale to that file in the same change that adds its `values-*` folder,
  or the picker won't offer it. Lint's `MissingTranslation` is a hard CI
  gate, so brand and symbol strings carry `translatable="false"`.
- The app has **no INTERNET permission**. Keep it that way; adding any
  network dependency is a product decision requiring an ADR.
- App display name lives ONLY in `strings.xml` — `app_name` (short, for
  the launcher) plus `app_name_full`/`app_model` for the Wordmark lockup.
  Never hardcode "Meltorama" in a composable (rename checklist: PLAN.md
  "Renaming"). The applicationId stays `ch.lkmc.goo`; "goo" remains the
  verb and the material ("Goo Your Photos", GOOvies, UnGoo).
- The design language is a retro-future console: gunmetal panels with
  milled bevels (`Modifier.chromePanel`), neon domes in swept chrome rims
  (`ChromeButton`/`ChromeIconButton`), one light source for every bevel
  (above, slightly left). Colors come from `ui/theme/Color.kt` — no ad-hoc
  Color(0x…) in screens.
- Scripts follow the family house style: header comment doubles as
  `--help` via the awk one-liner; `==>` / `--` / `!!` log prefixes;
  `set -euo pipefail`.
- Sample images must be public domain / CC0 with provenance recorded in
  this file when added. Current samples (`app/src/main/assets/samples/`):
  `goo-guy.png` and `candy-blobs.png` are generated procedurally by
  `scripts/generate_samples.py` from the app's own palette — provenance is
  this repo, license is the project's (Unlicense). Regenerate with
  `python3 scripts/generate_samples.py`.

## CI/CD

Three workflows (details: [CICD.md](CICD.md)): `ci.yml` (tests + lint +
debug APK on every PR/main push), `release.yml` (v* tags → verified,
published APK), `zai-code-review.yml` (GLM 5.2 reviews every PR; respond
per [CLAUDE.md](CLAUDE.md)). Family contract on every workflow:
least-privilege permissions, explicit concurrency, timeouts, wrapper
validation.

## Releasing

`scripts/release.sh X.Y.Z --push` (shared lkm-release engine) bumps
versionName, auto-increments versionCode by exactly 1, rewrites the README
version marker, commits, tags `vX.Y.Z`, pushes. **Never hand-edit
versionCode. Never create a `v*` tag by hand.** Bump the most-minor version
component + versionCode on every non-trivial change set.

## Review process

Review-cycle limits follow the shared stopping rules below.

PRs are reviewed by GLM 5.2 automatically. Findings are triaged
apply/decline/refute per [CLAUDE.md](CLAUDE.md); declined findings and
their reasons accumulate in [REVIEW.md](REVIEW.md) so later rounds (and
later agents) don't flip-flop. Point-in-time review snapshots archive under
`docs/reviews/`.

<!-- shared-rules:start -->

## Working practices

- Follow explicit task instructions over the default workflow below.
- Before editing, inspect the branch and working tree, fetch remote updates,
  and fast-forward where safe. Never overwrite existing work to update.
- Resolve ambiguity before making consequential changes. State low-risk
  assumptions; ask when scope, safety, or expected behavior is unclear.
- Keep changes focused. Do not modify unrelated code, formatting, or comments.
- Prefer surgical edits over whole-file rewrites when the result is equivalent.
- Stage only intended files. Inspect the diff before committing.

## Communication

- Be concise, factual, and direct. Preserve necessary context and uncertainty.
- Avoid praise, motivational filler, emojis, and em dashes in new prose.
- Address the reader directly in user-facing copy.
- Report what was verified and what remains unverified. Never imply that an
  unavailable check passed.

## Code design

- Prefer early returns and shallow nesting. Separate logical blocks with
  blank lines.
- Use descriptive constants or enums for meaningful or repeated values.
  Use existing standard definitions for protocol/specification constants.
  Keep obvious, one-off values inline.
- Use enums for behavioral modes that would otherwise require ambiguous
  boolean arguments.
- Default members to private. Widen visibility only for required consumers,
  and review the change as an API design decision.
- Follow the repository's declared dependency boundaries. UI and controllers
  must use application services rather than directly accessing databases,
  subprocesses, sockets, or other low-level mechanisms.
- Encapsulate low-level mechanics behind domain-oriented interfaces.
- Reuse genuinely shared logic. Avoid speculative abstractions and layers
  that only forward calls.
- Prefer pure functions for business rules and immutable data where practical.
  Isolate side effects; document non-obvious state ownership or synchronization.
- Explain non-obvious intent, constraints, and tradeoffs in comments.
  Do not narrate obvious code. Add examples or diagrams when they clarify it.

## Validation and errors

- Validate untrusted input at entry points. Where practical, represent valid
  states in types and enforce persistent invariants in database schemas.
- Represent absence and failure explicitly.
- Use assertions for internal programming invariants, not external-input
  validation or required runtime error handling.
- Prefer explicit, actionable errors over silent failure or undocumented
  fallback. Document intentional recovery behavior.
- Never report a skipped or failed operation as successful.

## Bug fixes

1. Identify the root cause and define an observable success criterion.
2. Add a regression test and observe the relevant failure before fixing it.
3. Implement the fix and observe the test passing.
4. Check surrounding behavior for regressions and architectural consistency.

If an automated regression test is impractical, document the reproduction
and verification procedure. State any inability to reproduce the failure.

## Verification

- Run relevant tests and lint after changes.
- Choose coverage by affected behavior and risk, not patch size.
- Use integration or end-to-end tests for critical workflows and boundaries;
  test isolated business rules at the lowest effective level.
- Run broader suites for cross-cutting or high-risk changes, and the full
  required release checks before releasing.
- Validate the requested command, options, platform, and configuration.
  Unrelated green CI is not proof that the reported problem is fixed.
- Recheck after the final edit. Distinguish local checks from CI results.

## Commit messages

- Use a capitalized, imperative subject without a final period.
- Target 50 characters; never exceed 72.
- Separate the subject and body with one blank line.
- Wrap body text at 72 characters.
- Explain what changed and why. Leave implementation mechanics to the code.

## Implementation and review

Unless explicitly instructed otherwise:

1. Work on a focused branch and open a PR against main.
2. Inspect CI results and completed review feedback for the latest commit.
   A successful reviewer job does not mean the review found no problems.
3. Address important findings or explain why they do not apply. Handle minor
   findings according to the stopping rules below.
4. Evaluate each fix in the surrounding project, add regression coverage,
   and rerun affected checks before pushing.
5. Repeat until a stopping criterion is met.
6. Merge without asking again once the stopping criterion is met, required
   checks pass on the latest commit, and no unresolved blockers or required
   human review requests remain.

### Automated review stopping rules

Judge findings by verified impact, not the reviewer's severity label.
Important findings concern correctness, security, data loss, broken builds,
or materially degraded behavior/performance.

Track completed review rounds and consecutive rounds without important
findings. Reruns of the same revision and integration failures do not count.

- No applicable actionable feedback: finish immediately.
- First minor-only round: optionally fix worthwhile, low-risk findings.
  Do not manufacture another push merely to obtain another review.
- Two consecutive rounds without important findings: stop responding to
  automated nitpicks, even if actionable minor suggestions remain.
  Defer worthwhile leftovers rather than continuing the cycle.
- A confirmed important finding resets the minor-only streak. Address it
  and verify the fix before continuing.

After ten completed rounds, enter stabilization:

- Stop optional cleanup, refactoring, and nitpick fixes.
- One completed review without confirmed important findings is sufficient
  to finish, even if minor suggestions remain.
- Continue only for confirmed important defects. If resolving them stalls,
  report the blockers rather than continuing indefinitely.

These limits end optional automated-feedback work. They do not waive
confirmed blockers, unresolved human review requests, or required checks.

### Reviewer integration failures

After two consecutive reviewer-integration failures, stop and report the
review gap. Do not treat failures as approval. An explicit user instruction
may waive review; report that waiver rather than claiming review passed.

## Completion checklist

- The requested behavior is implemented without unrelated changes.
- Relevant checks pass for the latest code.
- Important review findings are addressed or rejected with reasons.
- Deferred suggestions, remaining risks, and validation gaps are disclosed.
- The final response accurately states whether work is committed, pushed,
  and merged.

<!-- shared-rules:end -->
