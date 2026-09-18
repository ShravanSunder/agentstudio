# Keyboard core implementation review and correction

Baseline review was performed at `8af534f670eb0f7396b7921b2de1ac0e03f71c15` with source/test head `10383d28f`, against the unchanged sidebar core, terminal v2 and visible-spatial ready plans. The current corrected review head is `41c427781bf9e540afa52c5af3b00921ee4c27d6`, with merged main `b52a75a92`; the bounded historical diff was `0444368a2..2c58e3484` plus `990c947db..8af534f67`.

Spec-compliance, four independent whole-file chunks, proof challenge and dispel completed. UI, navigation metadata/transport and terminal/spatial/catalog chunks found no implementation defects. Parent verified candidate anchors and source; every delivered subsystem mapped to a confirmed obligation. Review history restored from original session: one prior implementation-remediation pass (terminal nil-source guard), followed by the capture correction pass; one recovery used, never reset.

## Accepted corrections

- **PINNED-CAPTURE-1 — important, implementation owner.** Core plan says “All list-sized derivation is off MainActor.” Pinned request capture calls `RepositoryTopologyAtom.captureReadSnapshot`; main's new absence getters rebuild `Set(dictionary.keys)` on every call. Base stored the set. Parent confirms this is a main-integration regression, not a new product/design boundary. Smallest correction retains canonical absence records in the existing read snapshot and preserves keyed availability/association/path checks. No new atom, cache, store, event, coordinator or public semantic contract. Removing only set reconstruction satisfies the deletion test; deleting availability checks would weaken behavior.
- **WIP-STATUS-1 — minor, documentation owner.** The current review map and terminal discussion still opened with pre-implementation/failed-aggregate status. Reconcile those entry lines to actual implementation/review/proof, preserving historical failures and pending preview/timing.

Confirmation for capture: structural regression for no MainActor absence-set projection; permanent snapshot availability/ownership/isolation scenarios; focused topology/pinned regression, lint and fresh aggregate after code correction; marker-scoped capture/worker observation on corrected native app. No wall-clock unit threshold.

## Historical proof disposition before capture correction

`MISE_RAW=1 mise run test` passed on `10383d28f`; reviewed HEAD changes docs only. Independent proof lane ran `mise run lint` and two `git diff --check` checks, all exit0, without product/test edits. It did not rerun aggregate under its narrower no-install grant; original operator log and source freeze establish the historical aggregate result.

The proof supplement inspected original ordered CUA inputs, AX results and PNGs: terminal68-row viewport moved61/22 rows; sidebar P/R/F, filter return, groups, offscreen9, Bridge/custom and drawer reveal,250/436pt overlays and corrected focus were corroborated; mixed hidden-sidebar pinned cycle was corroborated. Exact marker query stayed8 before/after40 selection keys. These are historical native observations with current-source regression support, not a fresh post-correction run.

At that pre-correction checkpoint, fresh pinned phase/timing remained unavailable. The exact query exited0 with0 matching records because the PID86213 GUI capture was locked. Schema tests could not substitute for live measurement. Preview remained owner-pending; detached-drawer invariant and nested WebKit DOM focus remained deferred.

## Historical result and next owner before correction

Review result `blocked-input` for fresh live timing, with the two accepted corrections above routed to existing owners for independent progress. Current source coverage is invalidated when the capture correction lands; affected fresh proof and review are required. The next bounded correction is remediation pass2, not a new recovery or a design round. No PR-ready or whole-goal completion claim.

Detailed temporary receipts: `tmp/sidebar-keyboard-design/core-review-packet.md`; `/tmp/keyboard-{ui,worker,pinned,terminal}-review.md`; `/tmp/keyboard-proof-review.md`; `/tmp/keyboard-proof-native-evidence-supplement.md`; `/tmp/keyboard-core-dispel.md`. Original native and review evidence is retained in the current session, with ordinal pointers in the proof supplement.

## Remediation pass 2: scoped proof

The same-owner capture correction and WIP status corrections were applied. Expected RED:5 architecture tests,4 passed/1 failed with2 issues from derived absence getters; initial sandbox failure ran0 tests and is not RED. GREEN:19 tests/5 suites,0 issues; format, lint (SwiftLint0/2664 files, architecture and release checks) and diff-check all exit0. Source changes are one topology snapshot file and two permanent test files. Captured availability/absence, wrong-owner/missing identities, path exclusion and old-snapshot isolation pass for both repository/worktree absence. Current aggregate, corrected-source review, and live timing closure are recorded below. Logs use `tmp/sidebar-keyboard-design/pinned-capture-{red-authorized,green-*}`.

## Current correction closure

The corrected review is bound to `41c427781bf9e540afa52c5af3b00921ee4c27d6`. The exact `MISE_RAW=1 mise run test` aggregate receipt passed with exit `0` and `firstFailure: null`; the focused corrected lane passed `19` tests across `5` suites with `0` issues. Format, lint, and `git diff --check` receipts are also exit `0`. The correction source/spec/chunk/dispel review found no remaining source defect.

The independent proof challenge is complete. Raw original records close the absence-input gap with read-only counts `unavailable_repo=1` / `unavailable_worktree=1`, then `0` / `0` after restoration, and correlate each pinned CUA input with its AX result and screenshot artifact. The corrected marker-scoped sample contains `28` pinned-navigation operations represented by `56` phase records. The observed capture sample has median `0.010500 ms` and max `0.017875 ms`; the observed worker sample has median `0.123208 ms` and max `0.225750 ms`. These are observed foreground samples only, not percentiles or broad benchmarks; telemetry has no direction field. No nested Bridge WebKit DOM-focus claim is made.

The capture correction review is ready on `41c427781`, but the overall change is not whole-PR-ready: held preview remains unimplemented and its current Program Design correction is underway. PR #348 remains draft at `41c427781` against `navigation-cmds`; PR #345's prior failed CI is a distinct base-PR state.
