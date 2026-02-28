# Drag Target Validator Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make drag target visibility match validator-backed move semantics across split panes, drawer panes, and tab-bar insertion targets so invalid moves never show targets and valid moves always show targets.

**Architecture:** Introduce one pure, shared drop-planning layer that computes eligibility + commit plan from current state (`ActionStateSnapshot`), and wire both preview (target rendering) and commit (drop execution) to that same planner. Remove policy drift between split/drawer validation and tab-bar marker logic by routing all drag target decisions through validator-backed planning. Preserve current domain rules: drawer child panes stay within parent drawer, layout panes can move/split/merge according to existing action contracts.

**Tech Stack:** Swift 6, AppKit + SwiftUI hybrid, `@Observable`, `PaneAction` + `ActionResolver` + `ActionValidator`, Swift Testing (`import Testing`), Peekaboo for visual verification

---

## Requirements Matrix (Spec)

### Movement invariants

1. Target visibility must equal commit eligibility.
2. Drawer child panes can move only within the same parent drawer.
3. Drawer child panes cannot show tab-bar insertion targets.
4. Layout panes can show tab-bar insertion targets when resulting move is valid.
5. Split/drop target rendering must be pane-type-agnostic (terminal/webview/bridge/future).
6. Edge corridor behavior must work equally in tab and drawer containers.
7. Management mode off: no drag targets, no drag commits.
8. Losing mouse press or app active focus clears latched targets.

### Source → destination matrix

| Source | Destination | Expected target | Expected commit |
|---|---|---|---|
| Layout pane (multi-pane tab) | Tab bar insertion | Visible | `extractPaneToTab` then `moveTab` |
| Layout pane (single-pane tab) | Tab bar insertion | Visible | `moveTab` (tab reorder semantics) |
| Drawer child pane | Tab bar insertion | Hidden | Rejected |
| Drawer child pane | Drawer pane (same parent) | Visible | `moveDrawerPane` |
| Drawer child pane | Drawer pane (different parent) | Hidden | Rejected |
| Any pane | Split pane target in layout tab | Visible iff validator passes | `insertPane`/`mergeTab` |
| Any pane | Split pane target in drawer | Visible iff same parent + validator passes | `moveDrawerPane` |

---

## Test Pyramid Coverage Targets

- **Unit tests (70%)**: pure planner/validator matrix, edge corridor math, payload decoding contracts.
- **Integration tests (25%)**: controller routing + tab-bar host eligibility + action dispatch mapping.
- **Visual/E2E tests (5%)**: Peekaboo validation for marker visibility/absence and edge corridors in real UI.

### Coverage gates

- New planner has exhaustive matrix tests for all source/destination categories.
- Existing drag tests remain green:
  - `PaneDragCoordinatorTests`
  - `PaneTabViewControllerDropRoutingTests`
  - `TabBarPaneDropContractTests`
- New visual checklist screenshots captured for:
  - drawer-left edge corridor,
  - drawer-right edge corridor,
  - drawer-pane drag over tab bar (no marker),
  - layout-pane drag over tab bar (marker visible).

---

## Phase 1: Pure Planning Layer (No UI first)

### Task 1: Add Drop Planner Domain Model

**Files:**
- Create: `Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`

**Step 1: Write failing tests**

Add tests for:
- `drawerPane_toTabBar_returnsIneligible`
- `layoutPaneSingle_toTabBar_returnsMoveTabPlan`
- `layoutPaneMulti_toTabBar_returnsExtractThenMovePlan`
- `drawerPane_sameParentDrawerSplit_returnsMoveDrawerPlan`
- `drawerPane_crossParentDrawerSplit_returnsIneligible`
- `layoutPane_toSplitLayout_resolvesActionPlan`

**Step 2: Run tests to verify fail**

Run:
```bash
swift test --filter "PaneDropPlannerTests" --build-path .build-agent-planner
```
Expected: FAIL (missing symbols/types).

**Step 3: Implement minimal planner**

Create:
- `enum PaneDropPreviewDecision { case eligible(DropCommitPlan), ineligible }`
- `enum DropCommitPlan` with typed plans for:
  - `.moveTab(tabId: UUID, toIndex: Int)`
  - `.extractPaneToTabThenMove(paneId: UUID, sourceTabId: UUID, toIndex: Int)`
  - `.paneAction(PaneAction)`

Planner API:
```swift
static func previewDecision(
  payload: SplitDropPayload,
  destination: PaneDropDestination,
  state: ActionStateSnapshot
) -> PaneDropPreviewDecision
```

**Step 4: Run tests to verify pass**

Run:
```bash
swift test --filter "PaneDropPlannerTests" --build-path .build-agent-planner
```
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift \
        Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift
git commit -m "feat: add validator-backed pane drop planner domain"
```

---

### Task 2: Bind Planner to ActionValidator Contracts

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift` (helper only if needed)
- Test: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`

**Step 1: Add failing validator-coupling tests**

Add tests ensuring planner eligibility flips to ineligible when:
- source tab missing,
- destination pane missing,
- self-insert/self-merge cases,
- management mode inactive in snapshot.

**Step 2: Run tests to verify fail**

Run:
```bash
swift test --filter "PaneDropPlannerTests" --build-path .build-agent-planner
```

**Step 3: Implement validator coupling**

- Resolve candidate `PaneAction` through `ActionResolver` where appropriate.
- Validate candidate through `ActionValidator.validate(...)`.
- Return `.eligible` only on `.success`.
- Keep planner pure (no store mutation, no NotificationCenter).

**Step 4: Run tests to verify pass**

Run:
```bash
swift test --filter "PaneDropPlannerTests" --build-path .build-agent-planner
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift \
        Sources/AgentStudio/Core/Actions/ActionValidator.swift \
        Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift
git commit -m "feat: enforce validator semantics in pane drop planner"
```

---

## Phase 2: Split + Drawer Preview/Commit Wiring

### Task 3: Replace Split Acceptance Branching with Planner

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`

**Step 1: Add failing tests**

Add tests for:
- split preview and commit both use same planner outcome.
- drawer move acceptance mirrors commit eligibility.
- invalid drawer cross-parent shows no target.

**Step 2: Run tests to verify fail**

Run:
```bash
swift test --filter "PaneTabViewControllerDropRoutingTests" --build-path .build-agent-routing
```

**Step 3: Implement minimal integration**

- In `evaluateDropAcceptance`, call planner and check `.eligible`.
- In `handleSplitDrop`, resolve planner once and execute returned plan.
- Remove duplicated if/else acceptance logic that can diverge.

**Step 4: Run tests to verify pass**

Run:
```bash
swift test --filter "PaneTabViewControllerDropRoutingTests" --build-path .build-agent-routing
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
git commit -m "refactor: route split and drawer drop acceptance through unified planner"
```

---

### Task 4: Keep Edge Corridor Rules Uniform for Drawer + Tab

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift` (only if needed)
- Test: `Tests/AgentStudioTests/Core/Views/Splits/PaneDragCoordinatorTests.swift`

**Step 1: Add failing regression tests**

Add explicit drawer-like bounds test cases:
- left corridor in panel bounds works.
- right corridor in panel bounds works.
- pane-union bounds must not be used for drawer edge corridors.

**Step 2: Run tests to verify fail (if missing coverage)**

Run:
```bash
swift test --filter "PaneDragCoordinatorTests" --build-path .build-agent-coordinator
```

**Step 3: Implement/confirm**

- Ensure drawer drop overlay always uses full panel geometry bounds.
- Keep `PaneDragCoordinator` pure and unchanged unless bug discovered by tests.

**Step 4: Run tests to verify pass**

Run:
```bash
swift test --filter "PaneDragCoordinatorTests" --build-path .build-agent-coordinator
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
        Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift \
        Tests/AgentStudioTests/Core/Views/Splits/PaneDragCoordinatorTests.swift
git commit -m "fix: keep drawer edge corridor targeting consistent with tab container"
```

---

## Phase 3: Tab-Bar Marker Semantics = Planner Semantics

### Task 5: Inject Planner-Based Eligibility into Tab Bar Host

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift`

**Step 1: Add failing tests**

Add tests for:
- drawer pane payload returns no tab-bar target eligibility.
- layout pane payload returns eligibility for valid insertion.
- marker visibility logic delegates to injected eligibility closure.

**Step 2: Run tests to verify fail**

Run:
```bash
swift test --filter "TabBarPaneDropContractTests" --build-path .build-agent-tabbar
```

**Step 3: Implement minimal integration**

- Add closure hooks in host view:
  - `canPreviewPaneDropAtIndex(payload:index) -> Bool`
  - `commitPaneDropAtIndex(payload:index) -> Bool`
- Remove direct hardcoded policy from `DraggableTabBarHostingView`.
- In `PaneTabViewController`, provide closures that call planner with live snapshot.

**Step 4: Run tests to verify pass**

Run:
```bash
swift test --filter "TabBarPaneDropContractTests" --build-path .build-agent-tabbar
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift \
        Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift
git commit -m "refactor: drive tab-bar pane drop targets from unified planner eligibility"
```

---

### Task 6: Remove Notification Drift for Pane-to-Tab Commit Path

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`

**Step 1: Add failing tests**

Add tests proving:
- same planner plan used for preview and commit.
- commit result matches previewed eligibility.

**Step 2: Run tests to verify fail**

Run:
```bash
swift test --filter "PaneTabViewControllerDropRoutingTests" --build-path .build-agent-routing
```

**Step 3: Implement minimal change**

- Prefer typed closure callback commit over posting ad-hoc `NotificationCenter` payloads in the tab host.
- Keep legacy notification observer only as fallback (temporary) with TODO for removal.

**Step 4: Run tests to verify pass**

Run:
```bash
swift test --filter "PaneTabViewControllerDropRoutingTests" --build-path .build-agent-routing
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift \
        Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
git commit -m "refactor: unify pane-to-tab commit path with preview planner"
```

---

## Phase 4: Regression Safety Net + Visual Verification

### Task 7: Expand Matrix Tests (No Blind Spots)

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`

**Step 1: Add matrix-driven test cases**

Add table-driven tests covering:
- source kind (`layout`, `drawerChild`)
- source cardinality (`single-pane tab`, `multi-pane tab`)
- destination kind (`layout split`, `drawer split`, `tab bar`)
- expected preview/commit eligibility

**Step 2: Run targeted tests**

Run:
```bash
swift test --filter "PaneDropPlannerTests|TabBarPaneDropContractTests|PaneTabViewControllerDropRoutingTests" --build-path .build-agent-matrix
```

**Step 3: Fix minimum code needed**

Address only failing matrix deltas; avoid behavior expansion outside spec.

**Step 4: Re-run targeted tests**

Run same command, expected PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift \
        Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift \
        Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
git commit -m "test: add full pane drag eligibility matrix coverage"
```

---

### Task 8: Visual Verification with Peekaboo

**Files:**
- Modify: `docs/plans/2026-02-26-drag-target-validator-unification.md` (append evidence links/notes)

**Step 1: Launch correct debug app**

Run:
```bash
pkill -9 -f "AgentStudio" || true
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
```

**Step 2: Capture required states**

Run:
```bash
peekaboo app switch --to "PID:$PID"
peekaboo see --app "PID:$PID" --json
```

Capture and verify:
- Drawer pane drag over tab bar: no insertion marker.
- Layout pane drag over tab bar: insertion marker appears.
- Drawer left-edge corridor target visible.
- Drawer right-edge corridor target visible.

**Step 3: Record verification notes**

Append a short verification section in this plan with timestamp and observed pass/fail.

**Step 4: Commit**

```bash
git add docs/plans/2026-02-26-drag-target-validator-unification.md
git commit -m "docs: add peekaboo verification evidence for drag target semantics"
```

---

## Phase 5: Ticket + Docs + Full Validation

### Task 9: Update Architecture + Ticket Scope

**Files:**
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `docs/architecture/component_architecture.md`
- Optional external: Linear ticket comment/status update

**Step 1: Document the contract**

Add explicit section:
- “Target Visibility Contract: preview eligibility MUST be planner/validator backed and equal commit semantics.”
- Include drawer vs layout pane movement constraints.

**Step 2: Add ticket update payload (copy/paste)**

Prepare update text:
- what changed,
- validator unification status,
- test pyramid counts,
- remaining risk.

**Step 3: Post ticket update**

If issue id is known, post via Linear MCP; otherwise save the payload in this plan for manual posting.

**Step 4: Commit**

```bash
git add docs/architecture/appkit_swiftui_architecture.md \
        docs/architecture/component_architecture.md \
        docs/plans/2026-02-26-drag-target-validator-unification.md
git commit -m "docs: formalize drag target validator contract and rollout notes"
```

---

### Task 10: Full Quality Gate (No shortcuts)

**Files:**
- No new files expected

**Step 1: Format**

Run:
```bash
mise run format
```
Expected: exit 0.

**Step 2: Lint**

Run:
```bash
mise run lint
```
Expected: exit 0 (or document pre-existing unrelated failures explicitly).

**Step 3: Full test suite**

Run:
```bash
mise run test
```
Expected: all suites pass.

**Step 4: Final regression checklist**

- No drawer pane tab target shown.
- Drawer edge corridors work.
- Layout pane tab targets still work.
- No pane-type-specific divergence (webview/terminal/bridge).

**Step 5: Commit final stabilization**

```bash
git add -A
git commit -m "chore: finalize validator-driven drag target unification"
```

---

## Rollback Plan

If a regression appears in tab-bar interactions:
1. Revert only `DraggableTabBarHostingView` planner integration commit.
2. Keep planner + split/drawer integration commits (safe, pure validation path).
3. Re-enable legacy path behind a temporary feature flag while preserving tests.

---

## Definition of Done

- All preview targets are backed by unified planner + validator semantics.
- Drawer pane drag to tab bar shows no marker and does not commit.
- Valid layout pane drag flows remain unchanged and pass matrix tests.
- Full `mise run test` passes.
- Architecture docs and ticket update are completed.

