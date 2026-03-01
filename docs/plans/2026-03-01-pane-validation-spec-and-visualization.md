# Pane Validation Spec And Visualization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make pane drag/drop behavior deterministic by enforcing one validation contract across preview, target capture, and commit, with architecture docs and unit tests as the source of truth.

**Architecture:** `docs/architecture/pane_validation_spec.md` is canonical for validator ownership, movement matrix, modal drawer interaction, and preview/commit parity. Implementation routes tab-bar and split/drop through planner-backed decisions and enforces modal capture ownership (exactly one active drop-capture owner per pointer context).

**Tech Stack:** Swift 6.2, AppKit + SwiftUI hybrid, `@Observable`, `PaneDropPlanner`, `ActionValidator`, `PaneDragCoordinator`, Swift Testing (`import Testing`), Peekaboo.

**Execution Skills:** `@test-driven-development` `@verification-before-completion` `@peekaboo`

---

## Preconditions

### Task 0: Environment and Build Prerequisites

**Files:**
- None

**Step 1: Ensure tools and resources are present**

Run:
```bash
mise install
mise run setup
```

Expected: exit code `0` for both commands.

**Step 2: Build debug app once (required for visual checks later)**

Run:
```bash
mise run build
```

Expected: exit code `0` and `.build/debug/AgentStudio` available.

**Step 3: Set one build path for filtered tests in this session**

Run:
```bash
export SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
```

Expected: subsequent `swift test --build-path "$SWIFT_BUILD_DIR" ...` commands reuse the same path.

---

## Phase 1: Documentation and Plan Contracts

### Task 1: Add docs contract regression tests

**Files:**
- Create: `Tests/AgentStudioTests/Docs/PaneValidationSpecDocumentTests.swift`

**Step 1: Write regression tests for architecture index + spec sections**

Use `TestPathResolver.projectRoot(from: #filePath)` to read docs paths (no hardcoded relative root).

**Step 2: Run docs contract tests**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneValidationSpecDocumentTests"
```

Expected: PASS.

**Step 3: If failing, patch docs and rerun**

Re-run the same command until PASS.

---

### Task 2: Align architecture docs vocabulary and pipeline wording

**Files:**
- Modify: `docs/architecture/pane_validation_spec.md`
- Modify: `docs/architecture/README.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`

**Step 1: Normalize drop-capture owner naming**

Use `SplitContainerDropCaptureOverlay` (not `SplitContainerDropDelegate`) where split capture ownership is described.

**Step 2: Normalize execution pipeline wording**

Document commit flow as:
`PaneAction -> ActionExecutor -> PaneCoordinator -> store mutation APIs`.

**Step 3: Tighten Swift 6.2/modal-parity wording**

- UI drop-capture handling must run on `@MainActor`.
- Preview and commit both call planner with an `ActionStateSnapshot` captured at evaluation time.
- No cached eligibility reuse across events.

**Step 4: Validate section/link presence**

Run:
```bash
rg -n "Pane Validation Spec|pane_validation_spec\.md|SplitContainerDropCaptureOverlay|ActionExecutor|@MainActor|Preview and drop commit" docs/architecture/README.md docs/architecture/component_architecture.md docs/architecture/appkit_swiftui_architecture.md docs/architecture/pane_validation_spec.md
```

Expected: matches for all concepts above.

---

### Task 3: Tighten this execution plan for agent-safe execution

**Files:**
- Modify: `docs/plans/2026-03-01-pane-validation-spec-and-visualization.md`

**Step 1: Keep git write actions optional**

Replace mandatory commit instructions with checkpoint instructions (`git status`, `git diff`).

**Step 2: Ensure matrix coverage is explicit**

Require one fixture case per movement-matrix row in `pane_validation_spec.md`.

**Step 3: Ensure test filters target real suites**

Use concrete test suite names (not fixture type names).

**Step 4: Verify plan text updated**

Run:
```bash
rg -n "optional|git status|one fixture case per movement-matrix row|PaneDropPlannerMatrixTests|DropTargetOwnershipTests" docs/plans/2026-03-01-pane-validation-spec-and-visualization.md
```

Expected: matches found.

---

## Phase 2: Code and Test Fixes

### Task 4: Add shared matrix fixture covering all movement rows

**Files:**
- Create: `Tests/AgentStudioTests/Helpers/PaneValidationMatrixFixture.swift`
- Create: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerMatrixTests.swift`

**Step 1: Add fixture types and cases**

Define fixture cases that map 1:1 to each row in the movement matrix from `pane_validation_spec.md`.

**Step 2: Write matrix test using the fixture**

For each case, call `PaneDropPlanner.previewDecision(...)` and assert eligibility and expected plan kind.

**Step 3: Run planner matrix tests**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropPlannerMatrixTests"
```

Expected: PASS.

---

### Task 5: Enforce tab-bar preview/commit planner parity

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController+DropPlanning.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift`

**Step 1: Add planner-backed callbacks to tab bar host**

Add injected closures for tab-bar pane-drop preview/commit:
- preview eligibility callback `(PaneDragPayload, Int) -> Bool`
- commit callback `(PaneDragPayload, Int) -> Bool`

**Step 2: Route both preview and commit through planner in controller**

Add helper in `PaneTabViewController+DropPlanning.swift` for tab-bar planner decision:
- Convert `PaneDragPayload` -> `SplitDropPayload`
- Evaluate `PaneDropPlanner.previewDecision(... .tabBarInsertion(...), state: snapshot)`
- Return `DropCommitPlan?`

**Step 3: Use same helper for preview and commit**

Preview and commit must both call the same planner helper (with fresh snapshot at evaluation time).

**Step 4: Add/extend tests for parity**

Add tests asserting tab-bar path matches planner result for:
- single-pane source tab -> `.moveTab`
- multi-pane source tab -> `.extractPaneToTabThenMove`
- drawer child -> ineligible
- management mode off -> ineligible

**Step 5: Run focused tests**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerDropRoutingTests|TabBarPaneDropContractTests"
```

Expected: PASS.

---

### Task 6: Enforce drawer-modal gating and drop-capture ownership exclusivity

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetOwnershipTests.swift`

**Step 1: Disable tab-level split capture while drawer modal is active**

In `TerminalSplitContainer`, derive drawer modal active state for the active tab and gate tab-level:
- `PaneDropTargetOverlay`
- `SplitContainerDropCaptureOverlay`

**Step 2: Gate background pane affordances in modal**

In `PaneLeafContainer`, suppress management hover/drag/split/button/context interactions for background panes while drawer modal is active. Drawer panel content remains interactive.

**Step 3: Keep frame ownership scoped**

Ensure drawer-rendered pane leaves publish only drawer frame preferences used by drawer capture; avoid publishing drawer pane frames into tab-level frame preferences.

**Step 4: Add ownership/gating tests**

Create tests for pure helper logic used by:
- tab-level split capture enabled/disabled decision
- background interaction suppression decision

**Step 5: Run ownership tests**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "DropTargetOwnershipTests|PaneDragCoordinatorTests"
```

Expected: PASS.

---

### Task 7: Visual verification checklist artifact

**Files:**
- Create: `docs/guides/pane_validation_visual_checklist.md`

**Step 1: Write checklist with exact scenarios**

Include:
1. Drawer open + management mode on: background panes do not show hover affordances.
2. First outside click dismisses drawer; background interactions resume only after dismiss.
3. Drawer same-parent drag: marker shown + commit succeeds.
4. Drawer cross-parent drag: no marker, no commit.
5. Layout pane over tab bar: marker only when planner-eligible.
6. Drawer pane over tab bar: no marker, no commit.

**Step 2: Add mandatory Peekaboo runbook**

Use PID-targeted debug build commands as required by project docs.

**Step 3: Verify checklist sections**

Run:
```bash
rg -n "background panes|outside click|same-parent|cross-parent|tab bar|Peekaboo|PID" docs/guides/pane_validation_visual_checklist.md
```

Expected: all required checks found.

---

### Task 8: Full verification and evidence capture

**Files:**
- All modified files from Tasks 1-7.

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

**Step 3: Full tests**

Run:
```bash
mise run test
```

Expected: exit code `0`.

**Step 4: Focused validator/ownership/doc suites**

Run:
```bash
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneValidationSpecDocumentTests|PaneDropPlannerMatrixTests|PaneTabViewControllerDropRoutingTests|TabBarPaneDropContractTests|DropTargetOwnershipTests"
```

Expected: PASS.

**Step 5: Evidence block (required in execution report)**

Capture and report:
- command
- exit code
- pass/fail counts
- screenshot/json evidence paths from Peekaboo

---

## Acceptance Criteria

1. Architecture docs use consistent ownership terms and execution pipeline wording.
2. `pane_validation_spec.md` remains canonical for validator ownership, movement matrix, and parity contract.
3. Tab-bar pane-drop preview and commit are planner-backed using the same helper semantics.
4. Drawer modal suppresses background pane interactions in management mode.
5. Tab-level and drawer-level drop-capture ownership are exclusive in modal drawer context.
6. Movement matrix has 1:1 fixture/test coverage.
7. `mise run format`, `mise run lint`, `mise run test` all pass.
8. Visual checklist exists and includes reproducible Peekaboo workflow.

## Checkpoints Instead of Commits

Use these checkpoints between tasks:

```bash
git status --short
git diff -- docs/architecture docs/plans Sources/AgentStudio Tests/AgentStudioTests
```

Commit only when explicitly requested by the user.
