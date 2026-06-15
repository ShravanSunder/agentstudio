# Ghostty Geometry Commit Owner and Post-Effect Invariants

Status: planned, not executed
Depends on: `2026-06-11-cross-tab-move-geometry-poisoning-fix.md` (must merge
first; same files, and the bug fix must not wait on this refactor).
Source: debug investigation
`tmp/debug-workflows/2026-06-11-agent-studio-issues-with-move-render-pane-move-zoom/debug-investigation.md`
plus chat design decisions (2026-06-11): items "3/4" — single geometry commit
point and post-effect invariant verification.

## Goal

Close the structural class behind the cross-tab geometry bug, not just the
instance:

1. **Single geometry commit point.** One owner writes terminal geometry
   (content scale + pixel size) to a ghostty surface, always together, in a
   fixed order, with app-side dedup. Today five independent writers race with
   last-write-wins and none re-asserts scale.
2. **Post-effect invariant verification.** After any view-effect epilogue, the
   app verifies surface geometry coherence against window truth and records
   violations. This is the app-side hook the future observability stack
   (VictoriaMetrics, separate work) will export; no exporter work here.

## Non-Goals

- The cross-tab move bug fix itself (predecessor plan).
- Metrics export/dashboards (separate observability workstream).
- Changing the reconcile planes or the validated command plane.
- Any change to ghostty vendored code.

## Current Writer Inventory (verified)

Writers into one `ghostty_surface_t`'s geometry today:

| Writer | Sends | Trigger |
|--------|-------|---------|
| `Ghostty.SurfaceView.setFrameSize` → `sizeDidChange` | size | AppKit frame change |
| `TerminalPaneMountView.layout` → `sizeDidChange` | size | host layout, deduped by `lastReportedSurfaceSize` |
| `TerminalSurfaceScrollView.synchronizeCoreSurface` → `sizeDidChange` | size | wrapper layout / scroller style change |
| `TerminalPaneMountView.forceGeometrySync` → `sizeDidChange` | size | `PaneTabViewController.syncVisibleTerminalGeometry` |
| `viewDidMoveToWindow` → `updateScaleFactor` + async `sizeDidChange` | scale, size | window join |
| `viewDidChangeBackingProperties` | scale, size | backing change (post-predecessor-plan: guarded) |

Properties of the current shape: scale and size are written independently;
size has three dedup layers (mount view, ghostty `updateSize`, none in
wrapper); scale has no dedup, no re-assertion, and (pre-predecessor-plan) one
garbage-capable producer. No code path verifies the result.

## Design

### Commit point

On `Ghostty.SurfaceView`:

- `private func commitGeometry(contentSize: NSSize, reason: StaticString)` —
  the only function that calls `ghostty_surface_set_content_scale` and
  `ghostty_surface_set_size`. Reads scale from window truth
  (`window?.backingScaleFactor`, screen fallback), converts size via
  `convertToBacking`, sends scale first then size, refreshes, and records
  `lastCommittedScale` / `lastCommittedSizePx`. App-side dedup: skip identical
  (scale, sizePx) commits.
- `sizeDidChange(_:source:)` becomes a thin wrapper over `commitGeometry`
  (external callers keep their signature — mount view, scroll wrapper,
  forceGeometrySync stay source-compatible).
- `updateScaleFactor` and `viewDidChangeBackingProperties` route through
  `commitGeometry` instead of writing scale directly (backing-properties keeps
  its layer `contentsScale` handling).
- Degenerate inputs (zero/non-finite frame or scale) are rejected at the
  commit point — the predecessor plan's guard moves here as the single choke
  point.

Ordering note: verify scale-before-size against ghostty core expectations
(DeepWiki `ghostty-org/ghostty` check during execution; official macOS app
sends scale in `viewDidChangeBackingProperties` then refreshes size — mirror
that).

### Invariant verification

- `func verifyGeometryCoherence(reason: StaticString)` on
  `Ghostty.SurfaceView`: compares `lastCommittedScale` vs
  `window.backingScaleFactor` and `lastCommittedSizePx` vs
  `convertToBacking(bounds)` within tolerance; on violation logs an os.Logger
  fault + `RestoreTrace` line and increments a counter.
- Called after view-effect epilogues: end of
  `TerminalPaneMountView.displaySurface`, `forceGeometrySync`,
  `PaneTabViewController.syncVisibleTerminalGeometry`, and
  `reattachForViewSwitch`.
- `TerminalGeometryDiagnostics` (small `@MainActor` counter holder,
  Infrastructure or Features/Terminal/Diagnostics): violation counts by
  reason. This is the seam the observability stack will read later. Plain
  `assert` (compiled out in release) guards debug runs; no new `#if DEBUG`
  test hooks in production files per repo rule.

## Task Sequence

### Task 0 — Gate
Predecessor plan merged; GhosttyKit artifact present; `mise run build/test`
baseline recorded.

### Task 1 — Commit point, behavior-preserving
Introduce `commitGeometry` + `lastCommitted*` state; route `sizeDidChange`,
`updateScaleFactor`, `viewDidChangeBackingProperties` through it. No caller
signature changes. Verify the resize-event profile is unchanged (trace
comparison: same set_size sequence for a scripted resize before/after).

### Task 2 — Invariant verification + diagnostics counter
Add `verifyGeometryCoherence`, `TerminalGeometryDiagnostics`, and the four
epilogue call sites. Tolerances: scale exact within 0.001; size within 1px
(rounding from `convertToBacking`).

### Task 3 — Tests
- Pure unit tests: dedup decision (identical commit skipped), degenerate
  rejection, coherence comparator (match, scale drift, size drift, no-window).
- Existing suites green: `TerminalSurfaceScrollViewTests`, hosting/coordinator
  suites, full `mise run test`.

### Task 4 — Smoke
Debug build + `AGENTSTUDIO_RESTORE_TRACE=1`: scripted split resize, cross-tab
move, arrangement switch, minimized toggle. Assert zero coherence violations
in the log and stable cell metrics throughout.

## Requirements / Proof Matrix

| # | Requirement | Task | Proof gate | Layer | Red/green | Sized to pass? |
|---|-------------|------|-----------|-------|-----------|----------------|
| R1 | Exactly one code path writes surface geometry | T1 | grep gate: `ghostty_surface_set_content_scale\|ghostty_surface_set_size` appears only inside `commitGeometry`; build green | static + build | n/a (structural) | yes |
| R2 | Scale and size always committed together, fixed order, deduped | T1/T3 | unit tests on commit decision logic | unit | yes (test-first) | yes |
| R3 | Degenerate geometry rejected at the choke point | T1/T3 | unit tests (zero frame, NaN, no window) | unit | yes | yes |
| R4 | Behavior preserved for normal resize flows | T1/T4 | trace-profile comparison before/after on scripted resize; existing suites green | integration + smoke | n/a (regression hold) | yes; split trigger below |
| R5 | Geometry incoherence is detected and counted after epilogues | T2/T3 | unit tests on comparator; smoke shows zero violations on healthy flows; injected drift (test-only seam via comparator inputs) shows detection | unit + smoke | yes | yes |
| R6 | Repo health | all | `mise run format/lint/test` exit 0, counts | build/lint/test | n/a | yes |

Highest layer not run: e2e drag harness (does not exist); T4 Peekaboo smoke is
the highest real layer and is named as such.

## Write Surfaces

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift` (caller only)
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` (epilogue call sites)
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` (epilogue call site)
- New: `Sources/AgentStudio/Features/Terminal/Diagnostics/TerminalGeometryDiagnostics.swift`
- Tests under `Tests/AgentStudioTests/Features/Terminal/`

## Validation Gates

1. Per-task filtered tests; grep gate for R1.
2. Plan-wide `mise run format` → `lint` → `test`.
3. T4 smoke with trace assertions.

## Split / Replan Triggers

- If routing `viewDidChangeBackingProperties` through the commit point changes
  the resize-event profile (R4 trace comparison diverges), stop and re-converge
  on ordering semantics before continuing — do not paper over with extra
  refreshes.
- If epilogue verification call sites exceed the four named locations, split a
  follow-up rather than spreading the change.

## Risks / Rollback

- Risk: consolidating writers changes PTY resize timing (zmx reflow churn,
  TUI redraw storms). Mitigation: dedup semantics mirror current ghostty-side
  dedup; R4 trace comparison is the gate.
- Risk: scroll wrapper width nuance (`scrollView.contentSize.width` vs surface
  bounds with overlay scrollers) gets canonicalized wrong. Mitigation: keep the
  wrapper's measured value as the input to `sizeDidChange`; the commit point
  converts, it does not re-measure.
- Risk: `assert` in coherence check fires on legitimate transient states
  (mid-reparent). Mitigation: verification runs only at epilogue completion
  points, never inside layout; log-first, assert only on debug.
- Rollback: `git revert`; no persistence/schema impact.

## Security Notes

Hardens the app→libghostty C ABI seam (single validated entry for geometry).
No new external surface.

## Open Questions

1. Scale-then-size vs size-then-scale ordering — confirm against ghostty core
   during execution (DeepWiki + official app source).
2. Should coherence verification also run on a debounced post-layout tick
   (catches drift outside epilogues) or stay epilogue-only? Default:
   epilogue-only this plan; revisit with observability work.
3. Counter surface shape for the future exporter (names/labels) — coordinate
   with the observability workstream when it starts.

## Recommended Next

`plan-review-swarm` on both plans together (shared files, ordering
constraint), then `implementation-execute-plan` for the predecessor plan
first.
