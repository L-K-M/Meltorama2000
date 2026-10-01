# PR #116 native review integration failures

Status: review incomplete
Date: 2026-10-01

Two full-review attempts failed at their workflow timeouts. There are zero
completed native review rounds and no posted findings. The repository's
two-integration-failure stopping rule applies; no third full review is requested.
Merging requires an explicit user waiver and passing CI for the final head.

The first attempt exhausted 170 minutes. After the trusted workflow repair in
PR #117, run 36768932869 completed all 49 initial chunks in 327.235 minutes but
exhausted the 330-minute step during a security escalation for chunk 4,
`macos/Sources/MeltoramaCore/InputMath.swift`. The actual flagged finding is
absent from logs, artifacts, inline comments, and posted reviews. The escalation
was never confirmed. This run must not be described as a clean review.

The second attempt had 53 successful requests averaging 5.669 minutes. Two
failed parent requests added 26.787 minutes and caused six smaller retries.
The security escalation ran for approximately 2.751 minutes before termination.
The earlier estimate based on an ordinary request mean did not account for
this retry cost or the escalation. No timeout or reasoning reduction is made
to obtain a passing status.

Independent inspection of the flagged file found a reachable native input
defect: extreme image aspect ratios could cause a Float resampling accumulator
to stop advancing while appending stamps indefinitely. Repeated native menu
zoom actions also had no lower or upper bound; Melt's unchecked Int32 noise
conversion could then trap. The fixes add a per-segment sampling budget,
finite progress guards, saturating noise lattice conversion, and shared menu/
gesture zoom bounds. Ordinary brush and noise output remains bit-identical.
These verified defects were addressed without claiming they reproduce the
unavailable reviewer finding. Regression and native validation are recorded in
`macos/VERIFICATION.md`.
