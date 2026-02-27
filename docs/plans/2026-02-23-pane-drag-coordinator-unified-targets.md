# Pane Drag Coordinator Unified Targets Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a pane-type-agnostic drag targeting system so split drop targets (including left-of-pane targets) behave identically for terminal, webview, bridge, and future pane types.

**Architecture:** Move drag target computation and rendering out of per-pane leaf views into a single tab-level coordinator + overlay. Keep pane content rendering generic through a shared container (`PaneLeafContainer`) and route split-drop state through one source of truth (`PaneDragCoordinator`). Preserve the existing `PaneAction -> ActionResolver -> ActionValidator -> PaneCoordinator` command path for drop commits.

**Tech Stack:** Swift 6, SwiftUI, AppKit host (`NSHostingView`), `@Observable`, Swift Testing (`import Testing`), existing split models (`DropZone`, `SplitDropPayload`, `PaneSplitTree`)

---

## Phase 1: Coordinator Domain (Pure Logic, Test First)

### Task 1: Add Drag Target Domain Types

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/PaneDragCoordinatorTests.swift`

**Step 1: Write the failing tests**

Create `PaneDragCoordinatorTests.swift` with these tests:
- `test_target_insidePane_leftHalf_returnsLeftZone`
- `test_target_insidePane_rightHalf_returnsRightZone`
- `test_target_nearLeftEdge_ofAnyPane_selectsLeftZone`
- `test_target_nearRightEdge_ofAnyPane_selectsRightZone`
- `test_target_outsideAllPanes_returnsNil`
- `test_target_resolution_isPaneTypeAgnostic` (use pane IDs only; no pane-type inputs)

Use pane frames like:
```swift
let paneA = UUID()
let paneB = UUID()
let frames: [UUID: CGRect] = [
    paneA: CGRect(x: 0, y: 0, width: 500, height: 400),
    paneB: CGRect(x: 500, y: 0, width: 500, height: 400),
]
```

**Step 2: Run tests to verify fail**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDragCoordinatorTests" -v
```
Expected: FAIL with missing `PaneDragCoordinator` symbols.

**Step 3: Implement minimal domain**

In `PaneDragCoordinator.swift`, add:
- `struct PaneDropTarget: Equatable`
  - `let paneId: UUID`
  - `let zone: DropZone`
- `struct PaneDragCoordinator`
  - pure static function:
    - `resolveTarget(location: CGPoint, paneFrames: [UUID: CGRect]) -> PaneDropTarget?`

Resolution rules:
- Find pane frame containing `location`.
- If found: zone uses existing `DropZone.calculate(at:in:)` with point translated to local pane coordinates.
- If none found: return `nil` (Phase 1 minimal behavior).
- Do not branch on pane type anywhere.

**Step 4: Run tests to verify pass**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDragCoordinatorTests" -v
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift \
        Tests/AgentStudioTests/Core/Views/Splits/PaneDragCoordinatorTests.swift
git commit -m "feat: add pane drag coordinator domain with pane-type-agnostic targeting"
```

---

### Task 2: Add Edge Corridor Behavior (Left/Right Outside Pane Frames)

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/PaneDragCoordinatorTests.swift`

**Context:** This addresses both current inconsistency and the left-of-leftmost insertion requirement.

**Step 1: Add failing tests for edge corridors**

Add tests:
- `test_target_leftOfLeftmostPane_returnsLeftZoneOfLeftmostPane`
- `test_target_rightOfRightmostPane_returnsRightZoneOfRightmostPane`

Use a fixed horizontal corridor width constant for predictability (e.g. `24` points).

**Step 2: Run tests to verify fail**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDragCoordinatorTests/test_target_leftOfLeftmostPane_returnsLeftZoneOfLeftmostPane|PaneDragCoordinatorTests/test_target_rightOfRightmostPane_returnsRightZoneOfRightmostPane" -v
```
Expected: FAIL (currently `nil` for outside points).

**Step 3: Implement edge corridor logic**

Update resolver:
- Compute leftmost pane (`minX`) and rightmost pane (`maxX`) from `paneFrames`.
- If pointer is within horizontal corridor just outside the bounds:
  - left corridor -> target leftmost pane `.left`
  - right corridor -> target rightmost pane `.right`
- Keep center behavior unchanged.

Add constants in coordinator:
- `static let edgeCorridorWidth: CGFloat = 24`

**Step 4: Run tests to verify pass**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDragCoordinatorTests" -v
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift \
        Tests/AgentStudioTests/Core/Views/Splits/PaneDragCoordinatorTests.swift
git commit -m "feat: support edge corridor drop targets for outermost panes"
```

---

## Phase 2: Shared Rendering Layer (Tab-Level Overlay)

### Task 3: Introduce Tab-Level Drop Target Overlay

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/PaneDropTargetOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/DropZone.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/DropZoneTests.swift`

**Step 1: Write failing test for frame-based overlay geometry helper**

Add tests to `DropZoneTests.swift` for new helper API:
- `test_overlayRect_leftZone_anchorsToLeftEdge`
- `test_overlayRect_rightZone_anchorsToRightEdge`

Add helper signature in `DropZone`:
```swift
func overlayRect(in paneFrame: CGRect) -> CGRect
```

**Step 2: Run tests to verify fail**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "DropZoneTests/test_overlayRect_leftZone_anchorsToLeftEdge|DropZoneTests/test_overlayRect_rightZone_anchorsToRightEdge" -v
```
Expected: FAIL due to missing helper.

**Step 3: Implement overlay renderer**

In `PaneDropTargetOverlay.swift`, add a view that:
- Inputs:
  - `target: PaneDropTarget?`
  - `paneFrames: [UUID: CGRect]`
- Renders exactly one overlay for current target.
- Uses target pane frame + zone helper to draw consistent target visuals.
- Does not read pane type.

Update `DropZone` with reusable geometry helpers for frame-based rendering.

**Step 4: Run tests to verify pass**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "DropZoneTests" -v
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneDropTargetOverlay.swift \
        Sources/AgentStudio/Core/Views/Splits/DropZone.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropZoneTests.swift
git commit -m "feat: add tab-level pane drop target overlay"
```

---

### Task 4: Add Container-Level Drop Delegate (Single Input Plane)

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropDelegate.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/DragPayloadCodableTests.swift`

**Step 1: Write failing tests for payload decoding helper**

Extract payload decoding from `TerminalPaneLeaf` drop delegate into a helper in new file:
- `decodeSplitDropPayload(from providers: [NSItemProvider]) async -> SplitDropPayload?`

Add tests (using existing payload fixtures):
- `test_decodeSplitDropPayload_prefersPanePayloadWhenPresent`
- `test_decodeSplitDropPayload_decodesNewTerminalPayload`

**Step 2: Run tests to verify fail**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragPayloadCodableTests/test_decodeSplitDropPayload_prefersPanePayloadWhenPresent|DragPayloadCodableTests/test_decodeSplitDropPayload_decodesNewTerminalPayload" -v
```
Expected: FAIL (helper missing).

**Step 3: Implement container drop delegate**

Create `SplitContainerDropDelegate`:
- Receives:
  - `paneFrames`
  - `target` binding
  - `shouldAcceptDrop`
  - `onDrop`
- On `dropEntered`/`dropUpdated`:
  - call `PaneDragCoordinator.resolveTarget(...)`
  - validate with `shouldAcceptDrop(target.paneId, target.zone)`
  - publish target state
- On `performDrop`:
  - decode payload
  - route to existing `onDrop(payload, paneId, zone)`
  - clear target state

Wire in `TerminalSplitContainer`:
- Add transparent, management-mode-only drop surface above split content.
- Apply `.onDrop(delegate: SplitContainerDropDelegate(...))` to that surface.
- Render `PaneDropTargetOverlay` in same ZStack.

In `TerminalPaneLeaf`:
- Remove local `dropZone`/`isTargeted` state and per-leaf `.onDrop` delegate.
- Keep pane controls/hover behavior only.

**Step 4: Run focused tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragPayloadCodableTests|PaneDragCoordinatorTests|DropZoneTests" -v
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/SplitContainerDropDelegate.swift \
        Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift \
        Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DragPayloadCodableTests.swift
git commit -m "refactor: move split drop handling to tab-level container delegate"
```

---

## Phase 3: Common Container Naming + Future Pane Type Safety

### Task 5: Rename `TerminalPaneLeaf` to `PaneLeafContainer`

**Files:**
- Move: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift` -> `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerLayout.swift`
- Modify: any in-repo comments referencing `TerminalPaneLeaf`

**Step 1: Add compatibility shim first**

Before rename, add:
```swift
@available(*, deprecated, renamed: "PaneLeafContainer")
typealias TerminalPaneLeaf = PaneLeafContainer
```

**Step 2: Perform rename and update references**

Update instantiations in split rendering paths and comments so architecture language matches reality (shared pane container, not terminal-specific).

**Step 3: Run build**

Run:
```bash
mise run build
```
Expected: PASS.

**Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift \
        Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerLayout.swift
git commit -m "refactor: rename terminal leaf to pane leaf container for pane-type agnostic model"
```

---

### Task 6: Add Regression Tests for Mixed Pane Types

**Files:**
- Create: `Tests/AgentStudioTests/Core/Views/Splits/PaneDropTargetResolutionTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropZoneTests.swift` (if helper fixtures needed)

**Step 1: Write failing tests**

Add tests with mixed pane IDs representing terminal/webview/bridge conceptually:
- `test_mixedPaneSet_leftTargetResolution_isIdenticalAcrossKinds`
- `test_mixedPaneSet_rightTargetResolution_isIdenticalAcrossKinds`
- `test_mixedPaneSet_edgeCorridor_usesOuterPaneRegardlessOfKind`

Important: test inputs only use frames + pane IDs; no pane-kind branching.

**Step 2: Run tests to verify fail/pending**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropTargetResolutionTests" -v
```
Expected: FAIL if any pane-kind assumptions remain.

**Step 3: Implement minimal fixes**

Adjust coordinator/overlay only if needed. Do not add pane-type conditionals.

**Step 4: Run tests to verify pass**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropTargetResolutionTests|PaneDragCoordinatorTests|DropZoneTests" -v
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/Views/Splits/PaneDropTargetResolutionTests.swift \
        Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift \
        Sources/AgentStudio/Core/Views/Splits/PaneDropTargetOverlay.swift
git commit -m "test: add mixed-pane regression coverage for unified split drop targets"
```

---

## Phase 4: Verification + Docs

### Task 7: Full Verification Loop

**Files:**
- Modify: none (verification only)

**Step 1: Run formatter/lint**

Run:
```bash
mise run format
mise run lint
```
Expected: PASS with 0 lint violations.

**Step 2: Run full tests**

Run:
```bash
mise run test
```
Expected: PASS for full suite.

**Step 3: Visual verification with Peekaboo**

Run:
```bash
pkill -9 -f "AgentStudio" || true
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio" | head -n 1)
peekaboo app switch --to "PID:$PID"
peekaboo see --app "PID:$PID" --json
```

Manual checks:
- Management mode ON: dragging over left side of webview pane shows left target.
- Same behavior over terminal pane (must match).
- Left-of-leftmost and right-of-rightmost corridor targets appear.
- Management mode OFF: normal webview interaction restored.

**Step 4: Commit verification notes**

```bash
git add -A
git commit -m "chore: verify unified pane drag coordinator behavior and regression coverage"
```

---

### Task 8: Architecture Documentation Alignment

**Files:**
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/directory_structure.md` (only if file map names changed)

**Step 1: Update docs for new split targeting model**

Document:
- `PaneLeafContainer` is pane-type-agnostic wrapper.
- Drag target computation is container-level (`PaneDragCoordinator`).
- Overlay is tab-level (`PaneDropTargetOverlay`).
- No pane-type conditionals in split target logic.

**Step 2: Run docs sanity check**

Run:
```bash
rg -n "TerminalPaneLeaf|PaneLeafContainer|PaneDragCoordinator|PaneDropTargetOverlay" docs/architecture
```
Expected: references updated, no stale naming where the new model should be canonical.

**Step 3: Commit**

```bash
git add docs/architecture/appkit_swiftui_architecture.md \
        docs/architecture/component_architecture.md \
        docs/architecture/directory_structure.md
git commit -m "docs: align architecture docs with unified pane drag coordinator model"
```

---

### Task 9: Investigate and Fix NSTableView Reentrant Delegate Warning (End-of-Plan Gate)

**Files:**
- Investigate: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Investigate: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Investigate: `Sources/AgentStudio/Core/Views/CustomTabBar.swift`
- Investigate: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Modify: only files identified by evidence
- Test: add/update targeted tests if root cause is deterministic in unit tests

**Context:**

Observed runtime warning to eliminate:
```text
2026-02-23 16:27:34.586 AgentStudio[44343:140102997] WARNING: Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.
```

This must be treated as a release-blocking warning because AppKit indicates future assert behavior.

**Step 1: Reproduce at end of refactor work**

Run after completing Tasks 1-8:
```bash
pkill -9 -f "AgentStudio" || true
.build/debug/AgentStudio 2>&1 | tee /tmp/agentstudio-reentrant.log
```

Drive the UI paths related to recent branch changes (management mode toggles, pane drag/drop, sidebar interactions), then stop app.

**Step 2: Confirm warning presence/absence**

Run:
```bash
rg -n "reentrant operation in its NSTableView delegate" /tmp/agentstudio-reentrant.log
```

Expected:
- If no matches: mark as verified-resolved and continue.
- If matches: proceed to Step 3 root-cause isolation.

**Step 3: Root-cause isolate with evidence**

Gather stack traces/logging around table delegate callbacks and any model mutation/reload calls performed synchronously from delegate methods.

Likely anti-patterns to remove:
- Calling `reloadData`, `noteNumberOfRowsChanged`, or selection mutation synchronously from delegate callback chains.
- Triggering store mutations that synchronously feed back into table update during delegate execution.

**Step 4: Implement minimal safe fix**

Use one of:
- defer table updates to next runloop turn (`Task { @MainActor in ... }` or equivalent deferral)
- guard against reentrant delegate-entry with scoped state flags
- move mutation out of delegate callback into coordinator event path

Avoid introducing new behavior outside reentrancy fix scope.

**Step 5: Verify warning is gone**

Re-run reproduction command and UI flow:
```bash
pkill -9 -f "AgentStudio" || true
.build/debug/AgentStudio 2>&1 | tee /tmp/agentstudio-reentrant-after.log
rg -n "reentrant operation in its NSTableView delegate" /tmp/agentstudio-reentrant-after.log
```

Expected: no matches.

**Step 6: Commit**

```bash
git add <root-cause files> <tests-if-added>
git commit -m "fix: eliminate NSTableView delegate reentrant operation warning"
```

---

## Final Acceptance Checklist

- Split target visibility is identical across pane types (terminal/webview/bridge/future panes).
- Split target rendering is centralized (tab-level overlay), not per-pane-type behavior.
- Drag targeting logic is pure, testable, and pane-type-agnostic.
- Existing action pipeline unchanged for drop commits (`PaneAction -> ActionResolver -> ActionValidator -> PaneCoordinator`).
- Full lint + tests pass.
- Visual verification completed on debug build by PID-targeted Peekaboo.
- No runtime warnings for `reentrant operation in its NSTableView delegate` in debug session logs.
