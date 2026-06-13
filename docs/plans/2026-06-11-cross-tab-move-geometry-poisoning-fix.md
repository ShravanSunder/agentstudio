# Cross-Tab Move Geometry Poisoning Fix

Status: implemented in `issues-with-move-render` (2026-06-12);
Plan A smoke proof refresh partially blocked by local display pipeline
(`CVDisplayLinkCreateWithCGDisplays` sees zero displays) on 2026-06-13.
Source: `tmp/debug-workflows/2026-06-11-agent-studio-issues-with-move-render-pane-move-zoom/debug-investigation.md`
Branch: `issues-with-move-render`
Companion plan: `2026-06-11-ghostty-geometry-commit-owner-and-invariants.md` (structural follow-up; depends on this plan merging first).

Execution note (2026-06-12): implementation completed the headless guard,
transition, and idempotency proof gates and passed format/lint/build/full tests.
The PID-scoped smoke launched a separate debug app and captured the AgentStudio
window without touching the live app; it did not automate the full drag repro,
which remains covered by the coordinator attach/detach regression test until a
durable drag harness exists.

Smoke refresh note (2026-06-13): after the shared observability stack landed,
an opt-in debug-only startup diagnostic for `cross-tab-move-geometry-smoke` was
added to exercise the real `movePaneAcrossTabs` command path in an isolated
debug PID and emit VictoriaLogs-proofable fixture-scoped counts. The diagnostic
is launched against a per-run scratch data root so the synthetic tabs/panes do
not contaminate the reusable worktree debug workspace. The first run under
marker `debug-observability-6zwo-1781360811-65472` recorded
`performance.pane_action.execution` for `movePaneAcrossTabs`, but the host could
not satisfy the original R6 terminal-rendering proof because Ghostty surface
creation failed before any content-scale writes:
`CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)`
followed by `embedded_window: error initializing surface err=error.OutOfMemory`.
The existing `new-tab` startup diagnostic failed the same way in PID 10236, so
the fixed diagnostic reports the command-exercised event separately from a
blocked render-proof event when fixture surfaces are unavailable. Final marker
`debug-observability-6zwo-1781363539-33960` recorded:
`app.startup_diagnostic_action.command_exercised/outcome=succeeded`,
`performance.pane_action.execution` for `movePaneAcrossTabs`, and
`app.startup_diagnostic_action.blocked/outcome=blocked` with
`agentstudio.startup_diagnostic.render_proof.succeeded=false`,
`fixture.surface.count=0`, `fixture.terminal_view.count=3`, and
`created_pane.count=4`. The missing content-scale/screenshot proof is a local
display/CoreVideo proof blocker rather than a cross-tab diagnostic failure.

## Goal

Fix the bug where dragging a pane into a tab leaves that tab's pre-existing
terminal panes rendering warped, zoomed-out text. This plan stays in the bug-fix
slice and makes three related changes:

1. Never send a NaN or degenerate content scale to ghostty.
2. Derive the cross-tab move view-effect work list from the actual state
   transition instead of treating the source tab as the destination's previous
   visibility set.
3. Make `displaySurface` idempotent for the same already-mounted surface while
   preserving the post-display side effects that are still required.

The three changes ship together because they address the same bug chain at
different failure boundaries: Task 1 prevents the C ABI poisoning, Task 2 stops
the cross-tab command from over-applying reattach effects to untouched
destination panes, and Task 3 makes duplicate same-surface display calls safe if
another view-effect path repeats this mistake later.

## Non-Goals

- Single geometry commit point / post-effect invariant counters (companion plan).
- Observability stack export (separate VictoriaMetrics work).
- Changes to resolver, validator, or the atom mutation rules beyond tests proving
  the validated command plane remains correct.
- New fault logging for unexpected `reattachForViewSwitch` calls; defer that to
  Plan B unless execution uncovers a required proof hook.

## Root Cause Summary

`executeMovePaneAcrossTabs` currently captures `previousVisiblePaneIds` from the
source tab only, then compares that source set with the destination tab's
post-move visible set. That makes every already-visible destination pane appear
"newly visible" and sends those panes through `reattachForViewSwitch` even though
they were never hidden.

For an already-mounted terminal pane, `reattachForViewSwitch` can hit
`SurfaceManager.attach`'s `alreadyActive` branch and then call
`TerminalPaneMountView.displaySurface` again with the same live surface. The
current `displaySurface` implementation unmounts and rewraps unconditionally.
During that rewrap, `TerminalSurfaceScrollView` can briefly give the surface a
zero-sized frame. If AppKit fires `viewDidChangeBackingProperties` in that
window, `Ghostty.SurfaceView` computes content scale as
`convertToBacking(frame) / frame`, which becomes `0 / 0 = NaN`. Ghostty clamps
NaN content scale to 1.0 and applies it, causing 1x cell metrics against the
2x backing framebuffer.

The leading explanation for why the dragged pane can render correctly while
pre-existing destination panes render warped is timing: the moved pane is
entering a newly changed destination layout, while panes already mounted in the
destination are unnecessarily rewrapped in place. That asymmetry is not yet
trace-proven; the smoke gate below must capture scale/write ordering for the
current repro before the execution report treats it as fact.

Regression window: `0bcef530` "Implement pane arrangement user behaviors"
(2026-05-15) introduced the reattach-all cross-tab reconcile call site.

## Repo Evidence Inspected

- `Sources/AgentStudio/App/Coordination/PaneCoordinator+CrossTabPaneMove.swift`
  builds the wrong previous/new visibility pair and owns the post-mutation
  detach/reattach epilogue.
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
  contains `computeSwitchArrangementTransitions`, the local precedent for
  deriving view-effect work from before/after sets; `setShowsMinimizedPanes`
  already calls `reconcileVisiblePaneTransition` with a same-tab before/after
  diff and should remain unchanged.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
  owns the structural move. The public facade called by the coordinator is
  `WorkspaceTabLayoutAtom.movePaneAcrossTabs`, which also removes an emptied
  source tab and activates the destination tab.
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
  unconditionally rewraps in `displaySurface` and resets geometry/reporting
  state after each display.
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
  can set a newly embedded surface to the wrapper's current bounds before layout
  has resolved a real frame.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
  writes content scale from both `viewDidChangeBackingProperties` and
  `updateScaleFactor`; the backing-properties path has no zero-frame or
  non-finite guard today.
- Tests inspected:
  `Tests/AgentStudioTests/Core/State/MainActor/Atoms/CrossTabPaneMoveTests.swift`,
  `Tests/AgentStudioTests/Core/Actions/ActionValidatorCrossTabPaneMoveTests.swift`,
  `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`,
  and `Tests/AgentStudioTests/App/PaneCoordinatorArrangementSwitchHostTests.swift`.
  The existing arrangement-switch fixture does not directly observe
  `displaySurface`; new coordinator proof should count attach/detach requests
  instead of pretending that fixture can see a final Ghostty surface.

## Environment Gate (Task 0)

This worktree currently lacks a usable `Frameworks/GhosttyKit.xcframework`, so
SwiftPM build/test exits before compiling. Restore the local binary artifact
from a sibling worktree, then establish baseline:

```bash
cp -R ../agent-studio.bridge-start/Frameworks/GhosttyKit.xcframework Frameworks/
mise run build
mise run test
```

If build/test still fail after restoring the artifact for reasons outside this
move-render slice, stop and report the blocker with failing command output. Do
not run `mise run setup`, debug unrelated suites, or alter repo/tooling
infrastructure without explicit approval.

## Task Sequence

### Task 0 - Baseline gate

Restore `GhosttyKit.xcframework`; run `mise run build` and `mise run test`;
record exit codes and pass/fail counts. No product edits.

### Task 1 - Content-scale guard and trace

- Add an internal testable helper on `Ghostty.SurfaceView` or an adjacent
  internal helper type:
  `static func backingContentScale(frame: NSRect, backingFrame: NSRect) -> (x: Double, y: Double)?`.
- Return `nil` for degenerate frames (width/height <= 0), non-finite frame or
  backing dimensions, or non-finite computed ratios.
- `viewDidChangeBackingProperties` must skip
  `ghostty_surface_set_content_scale` when the helper returns `nil`.
- Add `RestoreTrace` coverage for every content-scale write and every skipped
  content-scale write. Include at least view identity, frame, backing frame,
  computed scale, source/reason, and whether the value was written or skipped.
  Do not add a `SurfaceManager` dependency to `Ghostty.SurfaceView` only to
  print pane IDs; correlate pane/surface identity in smoke via existing
  PID-scoped mount/attach logs plus view identity where available.
- Keep `updateScaleFactor`'s direct window-scale write traced as well.
- Tests written first:
  - zero frame -> `nil`
  - normal 2x frame -> `(2, 2)`
  - negative, NaN, or infinite input -> `nil`

### Task 2 - Full cross-tab move view-effect transitions

- Before the atom mutation, capture:
  - `sourceVisibleBefore = activeVisiblePaneIds(forTab: sourceTabId)`
  - `destVisibleBefore = activeVisiblePaneIds(forTab: destTabId)`
  - `movedPaneIds = [paneId] + drawerPaneIds`
- After `store.tabLayoutAtom.movePaneAcrossTabs(...)`, capture
  `destVisibleAfter = activeVisiblePaneIds(forTab: destTabId)`.
- Add an internal testable transition helper returning an explicit result:
  `CrossTabMoveViewTransitions(paneIdsToDetach: Set<UUID>, paneIdsToReattach: Set<UUID>)`.
- The helper must preserve both halves of the current behavior:
  - Detach moved panes and source-tab panes left behind, because the public
    layout facade activates the destination tab after the move.
  - Reattach only panes whose destination visibility actually transitioned.
    Untouched destination panes visible both before and after the move must not
    be reattached.
- Do not route this operation through `reconcileVisiblePaneTransition` with a
  source-tab previous set and destination-tab new set. Leave
  `reconcileVisiblePaneTransition` itself unchanged for same-tab callers.
- Drawer caveat: `activeVisiblePaneIds` is top-level. Do not assume it includes
  drawer children. If moved drawer panes need explicit detach/reattach handling,
  capture drawer-visible before/after sets through `drawerVisiblePaneIds` or
  prove with tests that their existing hidden/restore behavior remains correct.
- Unit tests:
  - source `{A, B}`, moved `{A}`, destination before `{C, D}`, destination after
    `{A, C, D}` -> detach `{A, B}`, reattach `{A}`, and exclude `{C, D}`
  - source drain case still detaches moved panes and handles `sourceTabClosed`
    without losing focus/active-tab expectations
  - drawer payload case does not silently treat top-level visibility as drawer
    visibility
- Coordinator-level proof is required, not best-effort:
  exercise `executeMovePaneAcrossTabs` with a counting fake surface manager and
  pre-registered terminal hosts, then assert detach/attach requests hit the
  moved/source-left-behind panes and do not hit untouched destination panes. If
  observing real `displaySurface` would require constructing a real final
  `Ghostty.SurfaceView`, count `SurfaceManager.attach`/`detach` requests
  instead.

### Task 3 - Idempotent same-surface display

- Add an early same-surface path in `TerminalPaneMountView.displaySurface` when
  the incoming surface is already the mounted surface in the current mounted
  wrapper. The predicate must be mounted-wrapper aware, not only
  `surfaceScrollView != nil`.
- Keep the guard in `displaySurface`, not only `reattachForViewSwitch`, because
  the mount view owns the "displaying the same mounted surface is safe" contract.
  Task 2 narrows the cross-tab trigger; this guard prevents future duplicate
  same-surface display calls from corrupting geometry.
- The skip path must not unmount or rewrap.
- The skip path must preserve required post-display effects:
  - restore `onCloseRequested`
  - apply the current runtime snapshot if a runtime is bound
  - keep the existing `bindRuntime` guard semantics; do not call
    `bindRuntime` again when both runtime and displayed surface are unchanged
  - reset `lastReportedSurfaceSize` or otherwise force exactly one geometry
    sync opportunity so dedupe state cannot suppress the next needed size report
- Do not reset process-termination or startup/restore flags on a same-surface
  skip unless a test proves the current re-display contract requires that reset.
- Extract testable internal seams as needed, but do not widen public API only for
  tests.
- Tests:
  - pure predicate/seam test: same mounted surface -> skip; different surface or
    stale wrapper -> rewrap
  - skip-path behavior proof: same-surface display does not replace the wrapper,
    restores callback/runtime snapshot semantics, preserves the bind guard, and
    schedules or permits one post-skip geometry sync

### Task 4 - Smoke proof (drag repro)

- Build and launch a separate debug AgentStudio process with
  `AGENTSTUDIO_RESTORE_TRACE=1`. Never manipulate the user's live AgentStudio
  process; target the debug process by PID for Peekaboo.
- Scope log assertions to the launched PID and launch timestamp. Do not rely on
  unfiltered `/tmp/agentstudio_debug.log`, which is shared and append-only.
- Repro: destination tab with two live terminal panes; drag a third pane in from
  another tab through the tab/pane drop path.
- Assert from PID-scoped trace lines:
  - no content-scale write is non-finite
  - no content-scale write for the affected surfaces differs from the window
    scale, except explicit skipped degenerate writes
  - skipped degenerate writes, if present, include frame/backing evidence
  - pre-existing destination panes keep stable `cellWidthPx`/`cellHeightPx`
    across the move; columns/rows may change because pane width legitimately
    changes
  - the moved pane vs pre-existing-pane scale/write ordering is recorded if it
    is used in the execution report as causal evidence
- Visual screenshot: the destination tab's panes have uniform terminal text
  scale after the drag.

### Task 5 - Full gates and artifact closeout

- `mise run format`
- `mise run lint`
- `mise run test`
- Update the debug artifact status section with the final proof and any
  remaining gaps.

## Requirements / Proof Matrix

| # | Requirement | Task | Proof gate | Layer | Red/green | Sized to pass? |
|---|-------------|------|------------|-------|-----------|----------------|
| R1 | NaN/degenerate content scale is never sent to ghostty | T1/T4 | helper unit tests + PID-scoped smoke trace with write/skip lines | unit + smoke | yes | yes |
| R2 | Cross-tab move detaches the source-side panes that stop being visible | T2 | transition-helper unit test + coordinator attach/detach-count test | unit + integration | yes | yes |
| R3 | Untouched destination panes are not reattached on cross-tab move | T2 | transition-helper unit test + coordinator attach-count test proving destination `{C,D}` untouched | unit + integration | yes | yes |
| R4 | Re-displaying an already-mounted surface does not rewrap and keeps required side effects | T3 | predicate/seam tests + skip-path behavior proof for callback/runtime/geometry sync | unit + integration | yes | yes |
| R5 | Same-tab arrangement/minimized flows are not intentionally changed | T2/T3/T5 | leave same-tab reconciler unchanged; existing arrangement/minimized tests plus full `mise run test`; do not claim manual smoke unless explicit steps are added | unit/integration | n/a | yes, with honest scope |
| R6 | Bug visually fixed in the real app | T4 | PID-targeted Peekaboo drag repro + scoped trace assertions + screenshot | smoke | n/a | yes |
| R7 | Repo health | T0/T5 | `mise run build/lint/test` exit 0, counts reported | build/lint/test | n/a | yes, unless baseline blocker is unrelated |

E2E layer beyond the smoke repro is not run: no durable automated e2e harness
exists for multi-tab drag flows. The Peekaboo smoke (T4) is the highest real
layer available and must be reported as smoke, not as automated e2e.

## Write Surfaces

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+CrossTabPaneMove.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- New/extended tests under `Tests/AgentStudioTests/App/` and
  `Tests/AgentStudioTests/Features/Terminal/`
- `tmp/debug-workflows/2026-06-11-agent-studio-issues-with-move-render-pane-move-zoom/debug-investigation.md`
- `Frameworks/GhosttyKit.xcframework` (local untracked build artifact, Task 0)

## Validation Gates

Task-local filtered tests should use direct SwiftPM commands from the repo root.
Do not use `mise run test -- --filter`, because the current `mise` test task
does not forward trailing filter arguments.

Example task-local pattern:

```bash
source scripts/swift-build-slot.sh debug
env AGENT_STUDIO_BENCHMARK_MODE=off swift test \
  --filter '<SuiteOrTestName>' \
  --build-path "$SWIFT_BUILD_DIR"
```

Plan-wide gates:

1. `mise run format`
2. `mise run lint`
3. `mise run test`
4. Task 4 PID-scoped smoke trace + visual screenshot

## Split / Replan Triggers

- If Task 0 build/test fails after artifact restore for unrelated reasons, stop
  and report the baseline blocker without editing unrelated code.
- If the coordinator attach/detach-count proof cannot be expressed with a
  counting fake surface manager and one focused helper/test file, stop and split
  the proof work before product edits widen.
- If same-surface skip requires changing `Ghostty.SurfaceView.bindRuntime`,
  observer architecture, or terminal runtime ownership, stop and reconverge.
- If drawer-pane visibility semantics are unclear during Task 2, add the
  smallest proof for drawer behavior or split drawer handling before shipping a
  top-level-only fix that silently drops drawer panes.

## Risks / Rollback

- Risk: a flow depended on redundant rewrap to repair stale geometry. Mitigation:
  Task 3 preserves a post-skip geometry sync opportunity, Task 4 covers the
  cross-tab drag repro, and full tests cover same-tab flows.
- Risk: the same-surface skip path misses a binding or close callback.
  Mitigation: skip-path tests cover callback/runtime/geometry semantics and keep
  the existing `bindRuntime` guard.
- Risk: trace greps pick up stale or unrelated process lines. Mitigation:
  PID/timestamp-scoped smoke logs only.
- Rollback: pure `git revert` of the implementation commits; no
  persistence/schema/state format changes.

## Security Notes

The NaN guard is input hardening at a local AppKit-geometry -> libghostty C ABI
seam. No new network, filesystem parser, subprocess, secret, auth, or
persistence surface is introduced.

## Open Questions

None blocking. If execution uncovers a need for broader geometry ownership,
stop and route it to the companion Plan B rather than folding it into Plan A.

## Recommended Next

After this revised plan-review result is accepted, run
`implementation-execute-plan` on this file only. Do not implement code during
plan review.
