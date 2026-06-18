# Minimized Pane Divider Resize Test And Fix Plan

## Goal

Fix divider dragging when minimized panes are present, with tests strong enough to prevent regressions in the visual/model coordinate boundary.

The bug is not just "drag feels weird." The failure is that divider drag math currently measures visual widths that include fixed collapsed chrome, then dispatches a structural resize that mutates hidden minimized-pane ratios. Tests must prove that minimized chrome remains fixed, drag deltas map to the intended visible panes, and every input path that resizes pane splits uses the same minimized-pane contract.

## Source Coverage

- Debug source fully loaded: `tmp/debug-workflows/2026-06-17-agent-studio-fix-drag-minimized-minimized-divider-resize/debug-investigation.md`, 48 lines.
- Plan review swarm completed against the first draft. Accepted findings are incorporated in this revision.
- Current test/source evidence inspected:
  - `Tests/AgentStudioTests/Core/Views/FlatPaneDividerResizeTests.swift`, 151 lines.
  - `Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift`, 267 lines.
  - `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift`, 224 lines.
  - `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`, 2602 lines.
  - `Tests/AgentStudioTests/App/ActionExecutorTests.swift`, 862 lines.
  - `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`.
  - `Tests/AgentStudioTests/Core/Actions/ActionValidatorVisiblePanePairTests.swift`.
  - `Tests/AgentStudioTests/Core/Actions/ActionValidatorStructuralCommandTests.swift`.
  - `Sources/AgentStudio/Core/Models/FlatTabStripMetrics.swift`, 145 lines.
  - `Sources/AgentStudio/Core/Views/Panes/FlatPaneStripContent.swift`, 304 lines.
  - `Sources/AgentStudio/Core/Models/Layout.swift`, 280 lines.
  - `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`, 917 lines.
  - `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`.
  - `Sources/AgentStudio/Core/Actions/ActionValidator.swift`.
  - `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`.

## Current Test Diagnosis

Existing coverage is useful but underspecified for this bug:

- `FlatPaneDividerResizeTests` proves pure two-pane drag ratio math and guards against the old cumulative-translation feedback loop.
- `MinimizeLayoutIntegrationTests` proves minimized panes render as collapsed bars and that divider segments exist or disappear in some minimized cases.
- `LayoutFlatStripTests`, `WorkspaceStoreTests`, `ActionExecutorTests`, `ActionValidatorTests`, and
  `ActionValidatorVisiblePanePairTests` prove ordinary structural resizing and validation.

Missing coverage:

- No test composes gesture ratio -> layout mutation -> recomputed metrics.
- No test proves a minimized pane's fixed collapsed width is excluded from the resizable model pair.
- No test proves the left and right handles around a minimized middle pane resolve consistently.
- No test covers consecutive minimized panes between visible panes.
- No test covers unrelated visible panes that must not be resized.
- No test covers minimized panes at the strip edge where there is no visible pair to resize.
- No test proves hidden minimized-pane ratios remain stable during adjacent visible resize.
- No test proves validator parity for a minimized-aware resize command.
- No test proves keyboard `resizePaneByDelta` does not keep mutating hidden minimized structural neighbors.

## Decisions

The reviewed implementation path is now concrete:

- Metrics/view-facing code resolves a resize contract for each divider.
- The contract includes both resize intent and the effective resizable width baseline.
- Durable mutation is owned by tab arrangement state, because that owner has both `layout` and `minimizedPaneIds`.
- `Layout` may receive a pure explicit-pane ratio helper, but it must not discover minimized visibility.
- Pointer drag uses a first-class command/action path, not a view-local mutation.
- Edge minimized separators preserve the current divider-sized gutter as non-interactive chrome. They do not dispatch resize and do not show resize affordance.
- Keyboard `resizePaneByDelta` is in scope for minimized-neighbor behavior because otherwise pointer and keyboard resize would have divergent store-layer semantics.

## Non-Goals

- Do not redesign pane minimization, tab persistence, drawer grid layout, or drag/drop capture.
- Do not add wall-clock UI tests for drag behavior.
- Do not change visual styling of collapsed bars beyond non-interactive resize affordance behavior.
- Do not weaken existing ordinary two-pane resize behavior.
- Do not remove current gutter spacing around visible/minimized boundaries in this slice.

## Requirements And Proof Matrix

| Requirement / Claim | Owning Task | Proof Owner | Proof Gate | Layer | Stale-Proof Guard | Red/Green Required | Sized To Pass |
|---|---|---|---|---|---|---|---|
| Current bug is reproducible headlessly for `A | minimized B | C` | Task 1 | `MinimizedPaneDividerResizeTests` | `mise run test-fast -- --filter MinimizedPaneDividerResizeTests` | Unit/model | Command must discover the new suite; tests must fail on current code because visual divider movement exceeds requested drag delta | Yes | Yes |
| Minimized collapsed bar width stays fixed during adjacent resize | Task 1/3 | `MinimizedPaneDividerResizeTests` | targeted suite plus full fast lane | Unit/model | Assert exact collapsed width before and after resize | Yes | Yes |
| Divider resize contract includes effective resizable widths, not only pane ids | Task 2 | `MinimizedPaneDividerResizeTests` | targeted suite | Unit/model | Both separators around a collapsed run expose the same visible-pair baseline | Yes | Yes |
| Left handle before minimized middle pane resizes the visible pair, not hidden minimized ratio | Task 3 | `MinimizedPaneDividerResizeTests` | targeted suite plus full fast lane | Unit/model | Assert hidden minimized pane ratio is unchanged and visible movement matches translation tolerance | Yes | Yes |
| Right handle after minimized middle pane has symmetric behavior | Task 3 | `MinimizedPaneDividerResizeTests` | targeted suite plus full fast lane | Unit/model | Mirror the left-handle case; do not infer symmetry from implementation | Yes | Yes |
| Consecutive minimized panes between visible panes behave as one fixed collapsed run | Task 3 | `MinimizedPaneDividerResizeTests` | targeted suite plus full fast lane | Unit/model | `A | minimized B | minimized C | D` keeps both hidden ratios stable and resizes A/D | Yes | Yes |
| Unrelated visible panes do not jump | Task 3 | `MinimizedPaneDividerResizeTests` | targeted suite plus full fast lane | Unit/model | `A | minimized B | C | D` changes only A/C while D remains stable | Yes | Yes |
| Minimized pane at left or right edge preserves gutter but does not resize | Task 2/4 | `MinimizedPaneDividerResizeTests` or dispatch helper tests | targeted suite plus full fast lane | Unit/model | Assert divider/gutter presence, no resize intent, no resize dispatch, and stable pane widths | Yes | Yes |
| Overdrag clamps match ordinary resize bounds | Task 3/5 | `MinimizedPaneDividerResizeTests`, `ActionValidatorVisiblePanePairTests` | targeted suite plus validator filter | Unit/integration | Aggressive left/right drag clamps to the same lower/upper ratio bounds as structural resize | Yes | Yes |
| `collapsedPaneWidth == 0` mode remains unchanged | Task 3 | Existing minimize metrics tests plus added regression | `mise run test-fast -- --filter MinimizeLayoutIntegrationTests` | Unit/model | Existing zero-width minimized pane behavior remains no-divider/no-space | No new red if current behavior is already right | Yes |
| Ordinary visible two-pane resize remains unchanged | Task 3 | Existing divider/layout/store/action tests | targeted filters plus full fast lane | Unit/integration | Existing ratio assertions still pass; no compatibility shim | No new red needed | Yes |
| New visible-pair command validates at the action boundary | Task 5 | `ActionValidatorVisiblePanePairTests` and, if structural hidden-pane expectations change, `ActionValidatorStructuralCommandTests` | `mise run test-fast -- --filter ActionValidatorVisiblePanePairTests` | Unit/integration | Valid case succeeds; invalid ratios, missing tabs, single-pane/no-pair, minimized endpoints, and non-bracketing panes fail | Yes | Yes |
| Store/action path owns durable mutation | Task 5 | `WorkspaceStoreTests`, `ActionExecutorTests` | targeted filters | Integration | Test through command/executor/store path, not only a helper | Yes | Yes |
| Keyboard resize follows minimized-visible-pair semantics | Task 6 | `WorkspaceStoreTests` or focused tab arrangement tests | targeted filter plus full fast lane | Integration | `resizePaneByDelta` skips collapsed runs, preserves hidden minimized ratios, and is no-op when no visible pair exists | Yes | Yes |
| Intent-to-dispatch mapping is proven without UI automation | Task 7 | `MinimizedPaneDividerResizeTests` or extracted dispatch helper tests | targeted suite | Unit/model | Structural divider dispatches structural resize; minimized visible pair dispatches visible-pair resize; edge none dispatches nothing | Yes | Yes |
| No formatting/lint/architecture regressions | Task 8 | Repo lint tasks | `mise run format`, then `mise run lint` | Quality | Lint includes swift-format, architecture SwiftLint, and release script checks | No | Yes |
| Full relevant suite remains healthy | Task 8 | Repo test tasks | `mise run test-fast`; then `mise run test` | Integration/smoke-ish repo gate | `mise run test` default skips opt-in E2E/Zmx unless env enables them; report that explicitly | No | Yes |

## Task Sequence

### Task 1: Add the full red semantic reproduction suite

Create a dedicated suite/file:

- `Tests/AgentStudioTests/Core/Views/MinimizedPaneDividerResizeTests.swift`
- Suite name: `MinimizedPaneDividerResizeTests`

Before production changes, add red tests for:

- `A | minimized B | C`, left handle.
- `A | minimized B | C`, right handle.
- `A | minimized B | minimized C | D`.
- `A | minimized B | C | D`, where D is an unrelated visible pane.
- `minimized A | B | C`, edge minimized left boundary.
- `A | B | minimized C`, edge minimized right boundary.
- aggressive left and right overdrag against a minimized run.

Each pointer-style test composes:

1. Build a deterministic `Layout`.
2. Mark minimized pane ids.
3. Compute `FlatTabStripMetrics`.
4. Resolve divider resize intent and effective resizable baseline.
5. Simulate drag ratio computation.
6. Apply the command/store mutation path once it exists.
7. Recompute metrics.
8. Assert pointer delta ~= visible handle movement, hidden minimized ratios unchanged, fixed collapsed widths unchanged, and unrelated visible panes stable.

Capture the red result with:

```bash
mise run test-fast -- --filter MinimizedPaneDividerResizeTests
```

### Task 2: Add the minimized-aware divider resize contract

Introduce a testable resize contract for divider segments. The contract must distinguish visual placement from resize semantics.

Required shape:

- Structural divider intent for ordinary adjacent visible panes.
- Visible-pair intent for visible panes separated by one or more minimized bars.
- None intent for all-minimized and edge minimized boundaries with no visible pair.
- Effective resizable left width and right width for the selected intent.
- Visual frame/gutter data remains separate from resizable width data.

Do not overload `leftPaneWidth` and `rightPaneWidth` to mean both immediate visual neighbor widths and effective resizable widths. Rename or nest fields so an implementer cannot accidentally compute the visible-pair ratio from collapsed-bar widths.

Edge minimized boundaries preserve current divider/gutter spacing as non-interactive chrome. Tests must assert the chosen gutter behavior.

### Task 3: Implement the pure visible-pair ratio operation

Add the smallest pure operation that can update two explicit visible pane ids while preserving non-target ratios.

Ownership rules:

- `Layout` may own a pure helper such as "resizing explicit pane pair by ratio" because it owns pane ordering and ratios.
- `Layout` must not know which panes are minimized.
- `WorkspaceTabArrangementAtom` owns deciding whether a visible-pair resize is legal in the active arrangement because it owns the active arrangement's `layout` plus `minimizedPaneIds`.

Required invariants:

- Existing ratio sum remains stable.
- Non-target pane ratios remain unchanged after normalization/rounding tolerance.
- Hidden minimized pane ratios remain unchanged.
- Only the selected visible pair receives the ratio change.
- Ratio clamp behavior matches structural resize bounds.
- Ordinary `Layout.resizing(splitId:ratio:)` remains unchanged for adjacent structural dividers.

### Task 4: Add a first-class visible-pair command path

Add a concrete command/action seam instead of a view-local mutation. Preferred command:

```swift
case resizeVisiblePanePair(tabId: UUID, leftPaneId: UUID, rightPaneId: UUID, ratio: Double)
```

Required write surfaces if this command name is used:

- `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`

Validation contract:

- Tab exists.
- Active arrangement has at least two visible panes.
- Ratio is within the accepted resize range.
- Both pane ids exist in the active arrangement.
- Both endpoint panes are visible, not minimized.
- The endpoints are distinct and form a valid visible pair in layout order after skipping one or more minimized panes.
- No resize occurs for edge minimized boundaries or all-minimized cases.

### Task 5: Add validator/store/executor coverage

Add tests for the command/action seam:

- `ActionValidatorVisiblePanePairTests`: valid visible-pair resize succeeds.
- `ActionValidatorVisiblePanePairTests`: invalid ratios fail.
- `ActionValidatorVisiblePanePairTests`: missing tab fails.
- `ActionValidatorVisiblePanePairTests`: single visible pane/no visible pair fails.
- `ActionValidatorVisiblePanePairTests`: minimized endpoint fails.
- `ActionValidatorVisiblePanePairTests`: endpoints that do not bracket a minimized run or are not a valid visible pair fail.
- `WorkspaceStoreTests` or focused atom tests: visible-pair mutation preserves hidden ratios and unrelated visible panes.
- `ActionExecutorTests`: command reaches the store and mutates the expected pane pair.

If the existing structural hidden-pane command tests are affected, update `ActionValidatorStructuralCommandTests` in the same hard cutover and explain the contract shift in test names.

### Task 6: Align keyboard resize with minimized-visible-pair semantics

Update `resizePaneByDelta` behavior so keyboard resize and pointer resize share the same minimized-pane model:

- When the immediate structural neighbor is visible, existing behavior remains.
- When the immediate structural neighbor is minimized but a visible pane exists beyond the collapsed run, resize the effective visible pair.
- When no visible pane exists beyond the collapsed run, no-op.
- Hidden minimized pane ratios remain unchanged.
- Zoomed tabs remain no-op as today.

Add targeted tests before or alongside the implementation so this does not remain an execution-time judgment call.

### Task 7: Wire pointer resize dispatch

Update `FlatPaneDivider` / `FlatTabStripMetrics` wiring so:

- ordinary adjacent visible divider dispatches existing structural resize;
- a divider adjacent to a minimized run dispatches visible-pair resize using the effective resizable width baseline;
- an edge minimized divider preserves current gutter as non-interactive chrome and dispatches nothing;
- `.none` intent does not show resize cursor or install a resize drag gesture.

Prefer extracting a small pure helper for intent-to-command mapping so tests can prove dispatch behavior without SwiftUI UI automation.

### Task 8: Run validation gates and report proof by layer

Required commands:

```bash
mise run test-fast -- --filter MinimizedPaneDividerResizeTests
mise run test-fast -- --filter FlatPaneDividerResizeTests
mise run test-fast -- --filter MinimizeLayoutIntegrationTests
mise run test-fast -- --filter LayoutFlatStripTests
mise run test-fast -- --filter ActionValidatorTests
mise run test-fast -- --filter ActionValidatorVisiblePanePairTests
mise run test-fast -- --filter ActionValidatorStructuralCommandTests
mise run test-fast -- --filter WorkspaceStoreTests
mise run test-fast -- --filter ActionExecutorTests
mise run test-fast
mise run format
mise run lint
mise run test
```

If a broad gate fails outside the changed surface, stop code edits and report:

- targeted changed-surface pass/fail status;
- broad gate command, exit code, and failure summary;
- why the failure is outside scope;
- whether the next step is infrastructure/debugging or product fix.

## Write Surfaces

Likely source files:

- `Sources/AgentStudio/Core/Models/FlatTabStripMetrics.swift`
- `Sources/AgentStudio/Core/Views/Panes/FlatPaneStripContent.swift`
- `Sources/AgentStudio/Core/Models/Layout.swift`
- `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`

Likely test files:

- `Tests/AgentStudioTests/Core/Views/MinimizedPaneDividerResizeTests.swift`
- `Tests/AgentStudioTests/Core/Views/FlatPaneDividerResizeTests.swift`
- `Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift`
- `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift`
- `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- `Tests/AgentStudioTests/Core/Actions/ActionValidatorVisiblePanePairTests.swift`
- `Tests/AgentStudioTests/Core/Actions/ActionValidatorStructuralCommandTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`
- `Tests/AgentStudioTests/App/ActionExecutorTests.swift`

## Risks

- Making metrics own mutation policy would blur view geometry and state ownership.
- Mutating only visible ratios may surprise code that assumes every divider id maps to adjacent structural panes.
- Keeping non-interactive edge gutters preserves current spacing but may still feel visually like an affordance if cursor/gesture behavior is not proven.
- Adding a new action command has broader validation surface, but it is cleaner than encoding visible-pair behavior inside a structural split id.
- Including keyboard resize increases scope, but avoids a worse split where pointer and keyboard resize mutate minimized layouts differently.

## Rollback / Recovery

- If the visible-pair action grows too large, split the work:
  1. pure model operation and tests;
  2. metrics resize intent plus effective width baseline and tests;
  3. action/store/UI wiring;
  4. keyboard resize alignment.
- If the UI still feels wrong after headless proofs pass, add temporary debug-only logging around divider intent and recomputed segment frames, then remove it before final validation.
- If broad tests fail outside this lane, keep changed-surface proof separate and ask before changing unrelated infrastructure.

## Review Findings Addressed

Accepted plan-review findings incorporated:

- Removed the infeasible "keep it internal to `FlatPaneDivider`" fallback.
- Made tab arrangement/store the durable owner for visible-pair mutation.
- Required effective resizable width baseline in the divider contract.
- Required a dedicated `MinimizedPaneDividerResizeTests` suite so targeted proof cannot miss tests.
- Moved broad semantic cases into the red-first test task.
- Added validator coverage and targeted validator gates.
- Added intent-to-dispatch proof so helper-only tests cannot pass while live dispatch remains wrong.
- Added overdrag/clamp coverage.
- Added unrelated visible pane coverage.
- Made edge gutter behavior explicit.
- Promoted keyboard resize from open question to in-scope task.

Rejected findings:

- None. All validated blocker/important review findings were accepted.

Deferred:

- None.

## Recommended Next Step

This revised plan is ready for `shravan-dev-workflow:implementation-execute-plan` after one quick sanity reread by the executing agent. Do not implement code until execution mode is explicitly requested.
