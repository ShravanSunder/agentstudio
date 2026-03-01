# Pane Drop Rejection Reason Propagation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve and surface planner rejection reasons (including `ActionValidationError`) so preview and commit paths can explain why a drop was rejected without changing behavior.

**Architecture:** Keep `PaneDropPlanner` as the single eligibility engine, but add a richer evaluation API that returns both eligibility and structured rejection reason. Preserve the existing `previewDecision(...)` API as a compatibility projection so call sites can migrate incrementally. Commit-path handlers in `PaneTabViewController` and `DrawerPanel` should use the richer evaluation for diagnostics while still executing only eligible `DropCommitPlan` values.

**Tech Stack:** Swift 6.2, AppKit + SwiftUI hybrid, `PaneDropPlanner`, `ActionValidator`, `ActionStateSnapshot`, Swift Testing (`import Testing`), `OSLog`.

**Execution Skills:** `@test-driven-development` `@verification-before-completion`

---

## Preconditions

### Task 0: Session setup for deterministic filtered tests

**Files:**
- None

**Step 1: Ensure dependencies are installed**

Run:
```bash
mise install
```
Expected: exit code `0`.

**Step 2: Set a unique build path for this execution session**

Run:
```bash
export SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
```
Expected: `$SWIFT_BUILD_DIR` is non-empty and reused for all `swift test --build-path` commands below.

**Step 3: Baseline targeted suites before edits**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropPlannerTests|PaneTabViewControllerDropRoutingTests"
```
Expected: PASS (or known baseline failures documented before continuing).

**Step 4: Checkpoint (no commit yet)**

Run:
```bash
git status --short
```
Expected: clean working tree before implementation starts.

---

## Phase 1: Planner API and Unit Tests (TDD)

### Task 1: Add failing tests for explicit ineligibility reasons

**Files:**
- Create: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerRejectionReasonTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`

**Step 1: Write failing tests for new evaluation API**

Add a new suite that asserts reason payloads for representative failure paths:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneDropPlannerRejectionReasonTests")
struct PaneDropPlannerRejectionReasonTests {
    @Test
    func managementModeOff_returnsModeGateReason() {
        // Arrange state with isManagementModeActive = false
        // Act PaneDropPlanner.previewEvaluation(...)
        // Assert .ineligible(.managementModeInactive)
    }

    @Test
    func selfInsert_split_returnsActionValidationFailedReason() {
        // Arrange sourcePaneId == targetPaneId
        // Act PaneDropPlanner.previewEvaluation(...)
        // Assert .ineligible(.actionValidationFailed(.selfPaneInsertion(...)))
    }
}
```

**Step 2: Run only new suite to verify failure**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropPlannerRejectionReasonTests"
```
Expected: FAIL with missing symbols for new reason/evaluation API.

**Step 3: Add parity assertion in existing planner tests**

In `PaneDropPlannerTests.swift`, add one test ensuring legacy API still projects correctly:

```swift
let evaluation = PaneDropPlanner.previewEvaluation(payload: payload, destination: destination, state: state)
#expect(PaneDropPlanner.previewDecision(payload: payload, destination: destination, state: state) == evaluation.decision)
```

**Step 4: Re-run planner suites**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropPlannerRejectionReasonTests|PaneDropPlannerTests"
```
Expected: FAIL until implementation lands.

**Step 5: Checkpoint**

Run:
```bash
git status --short
```
Expected: only test files changed.

---

### Task 2: Implement richer planner evaluation with compatibility projection

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift`

**Step 1: Introduce typed rejection reason model**

Add a new public-in-module enum and evaluation wrapper:

```swift
enum PaneDropIneligibilityReason: Equatable {
    case managementModeInactive
    case payloadKindUnsupportedForTabBar
    case sourceIsDrawerChildForTabBar
    case sourceTabNotFound(sourceTabId: UUID)
    case drawerParentMismatch(sourcePaneId: UUID, expectedParentPaneId: UUID)
    case actionResolutionFailed
    case actionValidationFailed(ActionValidationError)
}

struct PaneDropPreviewEvaluation: Equatable {
    let decision: PaneDropPreviewDecision
    let ineligibilityReason: PaneDropIneligibilityReason?
}
```

**Step 2: Add new planner entrypoint**

Implement:

```swift
static func previewEvaluation(
    payload: SplitDropPayload,
    destination: PaneDropDestination,
    state: ActionStateSnapshot
) -> PaneDropPreviewEvaluation
```

The function should:
- enforce management mode gate first
- keep split vs tab-bar branch behavior unchanged
- return `.decision == .eligible(plan)` for accepted cases
- return `.decision == .ineligible` plus a non-nil `ineligibilityReason` for rejected cases

**Step 3: Preserve existing API as projection**

Change `previewDecision(...)` to call `previewEvaluation(...)` and return only `.decision`.

**Step 4: Preserve `ActionValidationError` details**

Replace boolean helper:

```swift
private static func validatedActionResult(
    _ action: PaneAction,
    state: ActionStateSnapshot
) -> Result<ValidatedAction, ActionValidationError>
```

Map `.failure(error)` to `.actionValidationFailed(error)` in the new evaluation path.

**Step 5: Run planner suites**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropPlannerRejectionReasonTests|PaneDropPlannerTests"
```
Expected: PASS.

---

### Task 3: Route controller/drop helpers through evaluation for diagnostics

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController+DropPlanning.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`

**Step 1: Add nonisolated helper returning evaluation**

In `PaneTabViewController+DropPlanning.swift`, add:

```swift
nonisolated static func tabBarDropPreviewEvaluation(
    payload: PaneDragPayload,
    targetTabIndex: Int,
    state: ActionStateSnapshot
) -> PaneDropPreviewEvaluation
```

`tabBarDropCommitPlan(...)` should derive from this evaluation and keep existing return type (`DropCommitPlan?`).

**Step 2: Add split helper returning evaluation**

In `PaneTabViewController.swift`, add:

```swift
nonisolated static func splitDropPreviewEvaluation(
    payload: SplitDropPayload,
    destinationPane: Pane?,
    destinationPaneId: UUID,
    zone: DropZone,
    activeTabId: UUID?,
    state: ActionStateSnapshot
) -> PaneDropPreviewEvaluation
```

`splitDropCommitPlan(...)` should project from this helper.

**Step 3: Improve commit-path logs with reason**

When commit plan is nil, include `evaluation.ineligibilityReason` in debug logs for:
- `handleSplitDrop(...)`
- `commitTabBarPaneDrop(...)`
- `DrawerPanel.handleDrawerDrop(...)` (optional debug-only logging, same reason type)

No behavior change: rejected commits still return early.

**Step 4: Add/extend tests for projection parity**

In `PaneTabViewControllerDropRoutingTests.swift`, assert:
- helper evaluation `.decision` matches planner `.previewDecision`
- rejection reason is non-nil for known invalid cases (drawer-child-to-tab-bar, management mode off)
- commit-plan helper remains nil for those cases

**Step 5: Run routing suites**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerDropRoutingTests|TabBarPaneDropContractTests"
```
Expected: PASS.

---

## Phase 2: Architecture Docs and Verification

### Task 4: Update architecture contracts for rejection-reason semantics

**Files:**
- Modify: `docs/architecture/pane_validation_spec.md`
- Modify: `docs/architecture/component_architecture.md`

**Step 1: Extend validator ownership table**

In `pane_validation_spec.md`, update planning row output to include reason-bearing evaluation:

```markdown
`PaneDropPreviewEvaluation` (`decision` + `ineligibilityReason`)
```

**Step 2: Add rejection taxonomy subsection**

Add a short table listing:
- management mode gate
- payload/destination mismatch gates
- `ActionValidator` failures (`ActionValidationError` preserved)

**Step 3: Clarify logging boundary**

In `component_architecture.md`, add one sentence: planner remains pure and side-effect free; UI/controller layers are responsible for optional diagnostics using the structured reason.

**Step 4: Validate docs wiring**

Run:
```bash
rg -n "PaneDropPreviewEvaluation|ineligibilityReason|ActionValidationError|side-effect free" docs/architecture/pane_validation_spec.md docs/architecture/component_architecture.md
```
Expected: matches found for all terms.

**Step 5: Checkpoint (optional commit)**

Run:
```bash
git status --short
git diff -- docs/architecture Sources/AgentStudio Tests/AgentStudioTests
```
Expected: diffs reflect planner reason propagation + doc updates only.

Optional commit (only if user asked):
```bash
git add docs/architecture/pane_validation_spec.md docs/architecture/component_architecture.md Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift Sources/AgentStudio/App/Panes/PaneTabViewController+DropPlanning.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Tests/AgentStudioTests/Core/Actions/PaneDropPlannerRejectionReasonTests.swift Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
git commit -m "feat: propagate pane drop rejection reasons through planner evaluation"
```

---

### Task 5: Full verification gate (required before completion)

**Files:**
- All files modified in Tasks 1-4

**Step 1: Format**

Run:
```bash
mise run format
```
Expected: exit code `0`.

**Step 2: Lint**

Run:
```bash
mise run lint
```
Expected: exit code `0`.

**Step 3: Full test suite**

Run:
```bash
mise run test
```
Expected: exit code `0`.

**Step 4: Focused regression suites**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropPlannerRejectionReasonTests|PaneDropPlannerTests|PaneTabViewControllerDropRoutingTests|TabBarPaneDropContractTests|PaneDropPlannerMatrixTests|DropTargetOwnershipTests"
```
Expected: PASS.

**Step 5: Evidence block for execution report**

Capture for each command:
- exit code
- test pass/fail counts
- any flaky test notes (with suite name)

---

## Acceptance Criteria

1. Planner exposes a reason-bearing evaluation API without changing eligibility behavior.
2. Existing `PaneDropPlanner.previewDecision(...)` remains available and behaviorally compatible.
3. `ActionValidationError` details are preserved in planner ineligibility reasons (not collapsed to boolean).
4. Commit-path handlers can log structured rejection reasons for split/tab-bar/drawer drop rejections.
5. Architecture docs define rejection-reason semantics and logging boundary.
6. `mise run format`, `mise run lint`, and `mise run test` all pass.

