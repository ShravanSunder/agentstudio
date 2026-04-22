# 2026-04-22 — Drawer drag: tab-level drop capture

**Status:** draft, ready for implementation on `drawer-improvements`
**Target branch:** `drawer-improvements`
**Scratch-branch archive:** `drawer-target-debugging` (commit `6110254`)
**Linear tickets:** LUNA-368 (debug-harness infra, separate); drag-testing-harness (to be created)

## Problem

On `drawer-improvements`, dragging a drawer-child pane handle starts a SwiftUI `.draggable` session (preview appears) but no `NSDraggingDestination` callback ever fires. Drops never commit. Main-pane drag works normally.

## Root cause (proven on `drawer-target-debugging`)

The active drawer drop capture was moved from the tab-level `SplitContainerDropCaptureOverlay` to a new `DrawerSplitContainerDropCaptureOverlay` mounted inside `DrawerPanel`. The nested mount is architecturally correct for scoping targets to drawer-internal rearrangement, but AppKit's drag-destination traversal does not reach the nested `NSView` in the current hosting composition. Separately, the outer capture was gated off whenever a drawer is expanded, so zero destinations receive drags from drawer-source views.

Evidence (full data in `docs/oracle/drawer-drag-experiment-tracker.md`):

- **E1-bis** (pid=54054, probe returns `[]`): a log-only probe at tab depth fires 233 `draggingUpdated` events while the nested `DrawerSplit` stays silent for the same session.
- **E-main** (pid=85296, probe removed, main gate forced on): production `SplitContainer.draggingEntered` fires 1× with 187 updates. Confirms shallow-level reachability is probe-independent. Nested `DrawerSplit` still silent.
- **E-fix** (pid=69705, structural move applied): tab-level mount of `DrawerSplitContainerDropCaptureOverlay` fires 4× entered, 512 updates, 3 drops committed out of 3 attempts.

Apple's docs substantiate `registerForDraggedTypes(_:)` and `draggingEntered(_:)` semantics but do NOT document a depth-based exclusion rule. The mechanism by which the nested placement becomes unreachable remains inference; the observational result is confirmed.

## What goes into `drawer-improvements`

### Include (production-worthy)

| File | Change | Purpose |
|---|---|---|
| `Sources/AgentStudio/Core/Views/Drawer/DrawerDropDispatch.swift` | NEW | Extracts `shouldAcceptDrop` / `handleDrop` validation + dispatch from `DrawerPanel`. Usable from any mount point. Closes Oracle-Q8. |
| `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift` | MOD | Delete nested `DrawerSplitContainerDropCaptureOverlay` mount. Delete internal `shouldAcceptDrawerDrop` / `handleDrawerDrop` / watchdog. `dropTarget` becomes an input parameter. Publish **panel-only** frame-in-tab preference via `GeometryReader` in `body` (see coord-math correction below). |
| `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift` | MOD | Accept `drawerDropTarget` parameter, pass through to `DrawerPanel`. Keep `DrawerPanelGlobalFrameKey` emission for dismiss monitor. **Do NOT** emit `DrawerPanelFrameInTabKey` from the outer VStack — that was the coord-math bug. |
| `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift` | MOD | Mount `DrawerSplitContainerDropCaptureOverlay` at tab level via `@ViewBuilder tabLevelDrawerCapture(...)` helper. Observe `DrawerPaneFramePreferenceKey` and `DrawerPanelFrameInTabKey` at tab level. Add `drawerDropTarget` state + watchdog. |
| `Sources/AgentStudio/Core/Views/Splits/DrawerDragOwnershipPolicy.swift` | NEW | Centralize `expandedDrawerParentPaneId(...)` and `mainSplitDragEnabled(...)`. Makes the ownership rule testable. |
| `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelFrameInTabKey` (new preference) | NEW | Panel-only frame, published from `DrawerPanel.body` — NOT from `DrawerPanelOverlay`'s outer VStack. |

### Minimal tests (ship with the fix)

| File | Covers |
|---|---|
| `Tests/AgentStudioTests/Core/Views/Splits/DrawerDragOwnershipPolicyTests.swift` | Pure unit tests for the gate logic: drawer collapsed → main enabled, drawer expanded → main disabled, etc. |
| `Tests/AgentStudioTests/Core/Views/DropCaptureViewCoordinateTests.swift` | Coord-transform invariants for `DrawerSplitContainerDropCaptureView` (local ↔ drawer-local; container-bounds consistency). |
| `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorFixtureTests.swift` (NEW) | Golden-file test. Replays the 512 real resolutions captured in E-fix (pid=69705). Fails if coord math drifts. Fixture derived from log and committed as JSON/Swift literal. |
| `Tests/AgentStudioTests/Core/Views/Splits/FlatTabStripContainerDragOwnershipTests.swift` | Gate switch observed correctly; tab-level mount appears/disappears on drawer expand/collapse. |
| `Tests/AgentStudioTests/Core/Views/Drawer/DrawerTabLevelCaptureRegistrationTests.swift` (NEW) | Static view-tree invariant: when drawer is expanded, exactly one NSView registered for `.agentStudioPaneDrop` exists at tab depth; `DrawerPanel` subtree has zero. Prevents the exact regression class this plan addresses. |

### Coord-math correction (Codex P1, blocker)

Current state on `drawer-target-debugging`: `DrawerPanelFrameInTabKey` is emitted from `DrawerPanelOverlay`'s outer VStack which includes the connector height. The NSView at tab level therefore sizes/positions itself over panel + connector, but `drawerPaneFramesInDrawer` only cover the panel (published in `"drawerContainer"` space, height = `panelHeight`). Resolver receives inflated `containerBounds.height`. Target math biased (279/512 resolutions → `rowSlot(top, 1)` alone).

Fix:

1. **Remove** the `DrawerPanelFrameInTabKey` `.preference(...)` call from `DrawerPanelOverlay.swift`'s outer background GeometryReader. Keep `DrawerPanelGlobalFrameKey` (dismiss-monitor needs global flipped frame including connector).
2. **Add** a `GeometryReader`-backed background inside `DrawerPanel.body` (NOT the outer VStack) that emits:
   ```swift
   .background(
       GeometryReader { geo in
           Color.clear.preference(
               key: DrawerPanelFrameInTabKey.self,
               value: geo.frame(in: .named("tabContainer"))
           )
       }
   )
   ```
   This captures panel-only geometry in tab coords, matching the drawer-local pane frames.
3. **Verify** `FlatTabStripContainer`'s `tabLevelDrawerCapture` still sizes from `drawerPanelFrameInTab` — no change needed, the preference's meaning is what shifts.

Acceptance: in a real drag, drops land at the slot the visual overlay highlights. The target distribution histogram over 50+ resolutions is visibly spread across slots instead of concentrated on one.

### Exclude (diagnostic-only, do NOT promote)

| File / change | Why |
|---|---|
| `Sources/AgentStudio/Core/Views/Splits/DrawerDragProbeOverlay.swift` | E1/E1-bis experimental scaffold. Useful for future debugging but belongs in a test / debug-only module or absorbed into LUNA-368's `DragEventTracer`. |
| `Sources/AgentStudio/Infrastructure/Diagnostics/DragEventTracer.swift` | Stub not yet implemented. Moves into LUNA-368 work. |
| `docs/oracle/*.md` | Archaeology — stays on `drawer-target-debugging`. Include `docs/plans/2026-04-22-drawer-drag-tab-level-capture.md` (this file) as the production-branch artifact. |
| Verbose diagnostic logs in `DrawerSplitContainerDropCaptureOverlay.swift` (ancestor-chain dump, etc.) | Keep session IDs + owner tags. Drop the ancestor-chain and heavy registration-detail logs — they served E1 and are redundant once the fix is in. |
| `DragSession` enum in `RestoreTrace.swift` | Keep — it's small, useful for any future drag debugging, costs nothing. |
| `PaneLeafContainer.swift` DragHandleDragPreview logging | Keep `.onAppear` session tag and source classification — useful ongoing. Drop verbose `.init` spam. |

### Open (do NOT block on)

- Drag-testing harness (Layers A–D from session discussion). Separate Linear ticket. Headless tests above are the first clients.
- Debug overlay (`⌥⌘D` drag-destinations visualizer). Separate ticket, under LUNA-368 scope.
- Tracer refactor (subsystem-tagged JSONL, ring buffer, etc.). LUNA-368.

## Implementation order on `drawer-improvements`

1. Cherry-pick production files from `drawer-target-debugging` (curated subset above). Do NOT cherry-pick the whole archive commit.
2. Apply the coord-math correction (move `DrawerPanelFrameInTabKey` emission from `DrawerPanelOverlay` → `DrawerPanel`).
3. Add the two new test files (`DrawerPaneDragCoordinatorFixtureTests`, `DrawerTabLevelCaptureRegistrationTests`) — both are headless, no launch.
4. Run `mise run build && mise run lint && mise run test` — all must pass.
5. Manual verification: one drag per case, assert drops land at highlighted slot. If still off, iterate on coord math; do not ship.
6. Single commit on `drawer-improvements` with the full curated set. Commit message references `drawer-target-debugging` SHA for the archaeology link.

## Acceptance criteria

- [ ] `mise run build` passes
- [ ] `mise run lint` passes (0 violations)
- [ ] `mise run test` passes (2384+ tests)
- [ ] New fixture test from pid=69705's resolutions passes
- [ ] New registration-invariant test passes
- [ ] Manual drag: drop-to-slot mapping visually correct in all quadrants of the drawer panel (top-left, top-right, bottom-left, bottom-right, top-row, bottom-row, createSecondRow regions)
- [ ] Main-pane drag still works (regression check — positive control)
- [ ] No diagnostic-only files present on the branch (no `DrawerDragProbeOverlay.swift`, no `DragEventTracer.swift`)
- [ ] No `oracle/` docs on the branch (this plan file only)

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Coord-math correction introduces a different bias | Medium | Fixture test from real data fails loudly; manual drag catches remaining issues in minutes |
| Removing the nested mount breaks something we haven't seen yet | Low | E-fix ran on `drawer-target-debugging` without any unexpected fallout; 2384 tests passed |
| `DrawerDropDispatch` extraction drifts from `PaneTabViewController.shouldHandleSplitDragPayload` | Low | Dispatch logic is pure — lives alongside validator. No duplication. |
| Coord space of preference emission misunderstood | Low-Medium | This plan explicitly names the panel-only vs outer-VStack distinction; reviewer can check by diff |

## Backport mechanics

Not cherry-pickable as-is (archive commit has too much that should NOT ship). Plan:

1. `git checkout drawer-improvements`
2. `git checkout drawer-target-debugging -- <path>` for each file in the Include list
3. Manually edit `DrawerPanelOverlay.swift` to remove the `DrawerPanelFrameInTabKey` emission
4. Manually edit `DrawerPanel.swift` to add the new GeometryReader emission
5. Add the two new test files
6. Build / lint / test; iterate
7. Commit
