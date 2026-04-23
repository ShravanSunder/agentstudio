# Codex feedback time log: drop sizing policy plan

Source plan: `docs/plans/2026-04-22-drop-sizing-policy.md`

Review date: 2026-04-23

Timezone: EDT

## Review log

### 2026-04-23 05:41 EDT — Review opened

Scope reviewed:

- Product decision and implementation plan in `docs/plans/2026-04-22-drop-sizing-policy.md`
- Current layout model code
- Drawer layout and rearrange code
- Main split drag/drop commit path
- Drawer drop dispatch path
- Existing tests around layout ratios and drawer rearrangement
- Sibling unified drop-target plan where this plan references target vocabulary

Initial read:

The product decision is coherent. Option D hybrid with Shift forcing proportional sizing is a reasonable UX policy.

Implementation-soundness read:

The plan is not sound as written. It understands the current ratio behavior correctly, but the execution plan crosses architecture boundaries, assumes sibling-plan types that do not exist in this checkout, leaves removal wiring underspecified, and contradicts itself on whether drawer rearrangement is in scope.

### 2026-04-23 05:44 EDT — Current `Layout` behavior grounded

Observation:

The plan correctly describes current `Layout.inserting` and `Layout.removing`.

Evidence:

- `Sources/AgentStudio/Core/Models/Layout.swift:69`
- `Sources/AgentStudio/Core/Models/Layout.swift:101`

Details:

- `Layout.inserting` halves only the target pane ratio and inserts the new pane adjacent to it.
- `Layout.removing` gives the removed ratio to the right neighbor, or the left neighbor if the removed pane was last.

Assessment:

The plan's baseline for flat strip insertion/removal is accurate.

### 2026-04-23 05:46 EDT — Drawer inheritance grounded

Observation:

The drawer story is more nuanced than "inherits," but the drift risk is real.

Evidence:

- `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift:50`
- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift:127`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:181`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:268`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:543`

Details:

- `DrawerGridLayout.inserting` delegates horizontal left/right insertion to `Layout.inserting`.
- `DrawerGridLayout+Rearrange.insertingPreservingRatios` currently delegates to `Layout.inserting`.
- Despite the helper name, `insertingPreservingRatios` still halves an anchor pane today.
- `WorkspacePaneAtom.addDrawerPane`, `insertDrawerPane`, and `restoreDrawerPane` all eventually use drawer layout insertion.

Assessment:

The plan is right that drawer insertion/rearrange needs a single explicit sizing policy. The current code has ratio behavior hidden behind helper names that could mislead future work.

### 2026-04-23 05:49 EDT — Finding P1: unified `DropTarget` dependency is unresolved

Finding:

The plan depends on unified `DropTarget`, despite presenting itself as loosely independent from the unified drop-target algorithm plan.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:154`
- `docs/plans/2026-04-22-drop-sizing-policy.md:315`
- `docs/plans/2026-04-22-drop-sizing-policy.md:515`

Code evidence:

- Current main split drag target is `PaneDropTarget(paneId: UUID, zone: DropZone)` in `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift:4`

Sibling plan evidence:

- Unified target vocabulary is proposed in `docs/plans/2026-04-22-unified-drop-target-algo.md:103`
- Target files are listed in `docs/plans/2026-04-22-unified-drop-target-algo.md:353`

Why it matters:

The sizing plan's API uses target cases like `.splitZone`, `.slot`, and `.newRow`, but those do not exist in this checkout. The note saying to "stub" `DropTarget` if the unified plan has not shipped would create a partial duplicate of the sibling plan's core model.

Recommendation:

- Make this plan explicitly depend on the unified target model landing first, or
- Rewrite Tasks B/C/D against today's types:
  - main: `PaneDropTarget` + `DropZone`
  - drawer: `DrawerRearrangeTarget`
  - later adapt to unified `DropTarget` when the resolver plan lands

Do not stub the sibling plan's target vocabulary inside this plan.

### 2026-04-23 05:51 EDT — Finding P1: proposed placement leaks AppKit/view concepts into model/state

Finding:

The proposed `DropSizingPolicy` location and API would push AppKit/view concerns into model and state code.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:297`
- `docs/plans/2026-04-22-drop-sizing-policy.md:417`
- `docs/plans/2026-04-22-drop-sizing-policy.md:592`

Details:

Task B creates:

- `Sources/AgentStudio/Core/Views/Splits/DropSizingPolicy.swift`

and imports:

- `AppKit`
- `NSEvent.ModifierFlags`

Task D then wires the same policy into:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift`

Why it matters:

Those model/state layers should not depend on a view file that imports AppKit. The pure ratio math belongs below the UI boundary.

Recommendation:

Split the policy into two pieces:

1. Pure model-layer ratio math, no AppKit:

   ```swift
   enum DropSizingMode: Hashable, Sendable {
       case halveTarget
       case proportional
   }

   enum DropSizingRatioPolicy {
       static func ratiosAfterInsertion(...)
       static func ratiosAfterRemoval(...)
   }
   ```

2. UI/drop-boundary adapter near AppKit drag code:

   ```swift
   enum DropSizingModeResolver {
       static func mode(for targetKind: ..., isShiftHeld: Bool) -> DropSizingMode
   }
   ```

At `performDragOperation`, read `NSEvent.modifierFlags`, convert to plain `Bool` or a pure mode, then pass pure values downward.

### 2026-04-23 05:53 EDT — Finding P1: dispatch contract is under-specified

Finding:

The plan does not define how sizing mode enters the validated command/action path.

Current main drop flow:

- `SplitContainerDropCaptureOverlay.performDragOperation` calls `coordinator.performDrop`
- `SplitContainerDropCaptureOverlay.Coordinator.performDrop` calls `actionDispatcher.handleDrop(payload, destinationPaneId, zone)`
- `PaneTabViewController.handleSplitDrop` builds a `DropCommitPlan`
- the plan becomes a `PaneActionCommand.insertPane(...)`
- `PaneCoordinator` and atoms eventually call `WorkspaceTabArrangementAtom.insertPane`
- `WorkspaceTabArrangementAtom.insertPane` calls `Layout.inserting`

Evidence:

- `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift:283`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift:889`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift:942`
- `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift:57`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift:55`

Current command shape:

```swift
case insertPane(
    source: PaneSource,
    targetTabId: UUID,
    targetPaneId: UUID,
    direction: SplitNewDirection
)
```

Why it matters:

The command has no sizing mode. The plan says "pass modifiers into the dispatch layer," but does not choose a concrete action shape or define how validation/execution receives that mode.

Recommendation:

Make the contract explicit. Candidate shape:

```swift
case insertPane(
    source: PaneSource,
    targetTabId: UUID,
    targetPaneId: UUID,
    direction: SplitNewDirection,
    sizingMode: DropSizingMode
)
```

Alternative:

- Carry a `PaneInsertionSizing` value in `DropCommitPlan` before execution.

Either way, the mode should be part of the validated command path, not a side channel.

Open behavior to name:

- keyboard/menu split right/left
- contextual webview-in-pane
- merge tab
- reactivate/backgrounded pane insertion

Those currently also call insertion paths. If the policy is drag-only, say that explicitly. If all insertions use the policy, every route needs a mode.

### 2026-04-23 05:55 EDT — Finding P1: removal policy is decided but not wired

Finding:

The plan decides proportional removal, but implementation tasks do not wire main or drawer removal.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:116`
- `docs/plans/2026-04-22-drop-sizing-policy.md:120`

Current main removal evidence:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementRepairRules.swift:4`
- `Sources/AgentStudio/Core/Models/Layout.swift:101`

Current drawer removal evidence:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:341`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:367`
- `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift:157`

Details:

Option D says removal should use proportional redistribution. Current main removal still uses adjacent-absorb through `TabArrangementRepairRules.removingPane` and `Layout.removing`. Current drawer removal also uses adjacent-absorb through `WorkspacePaneAtom` and `DrawerGridLayout.removing`.

Recommendation:

Add a dedicated removal task before acceptance:

- introduce a layout-removal helper that can apply proportional removal
- wire main pane close/background/extract paths intentionally
- wire drawer remove/detach/stale cleanup intentionally
- add tests proving removed ratio is redistributed proportionally

Open behavior to name:

- Should non-user repair/pruning paths use proportional removal too, or preserve conservative adjacent-absorb behavior?

Do not silently change repair behavior without naming it.

### 2026-04-23 05:56 EDT — Verification run started

Command:

```bash
mise run test --filter LayoutFlatStripTests
```

Purpose:

Check whether the plan's "add regression tests first" step is stale and whether current baseline layout behavior is already covered and green.

### 2026-04-23 05:56:48 EDT — Swift test runner timestamp observed

Observed from test output:

```text
Test Suite 'Selected tests' started at 2026-04-23 05:56:48.146.
```

Note:

The mise task built the package and then ran the non-E2E Swift Testing suites plus WebKit serialized groups. The command was filtered, but this project's mise test wrapper still ran a broad test pass.

### 2026-04-23 05:57 EDT — Finding P2: Shared Task A is stale

Finding:

The plan asks to add regression tests for current `Layout.inserting` and `Layout.removing`, but those behaviors already have coverage.

Evidence:

- `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift:21`
- `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift:51`
- `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift:72`
- `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift:95`

Recommendation:

Replace Shared Task A with:

- confirm existing `LayoutFlatStripTests` cover halve-target and adjacent-absorb behavior
- add missing precision/edge-case tests only if needed
- add new tests for `DropSizingRatioPolicy`, not duplicate baseline tests

### 2026-04-23 05:59 EDT — Finding P2: drawer rearrange is both required and blocked

Finding:

The plan simultaneously treats drawer rearrange as required and blocked.

Plan evidence:

- Task D says drawer insert/rearrange should use `DropSizingPolicy`: `docs/plans/2026-04-22-drop-sizing-policy.md:592`
- Hard acceptance requires "Task D drawer drag-rearrange tests green (all proportional)": `docs/plans/2026-04-22-drop-sizing-policy.md:630`
- Later, R-1 is unresolved and implementation is blocked: `docs/plans/2026-04-22-drop-sizing-policy.md:645`
- Later, only insertion tasks are concrete until R-1 is confirmed: `docs/plans/2026-04-22-drop-sizing-policy.md:670`

Current code evidence:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:314`
- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift:4`
- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift:127`

Recommendation:

Pick one:

- Resolve R-1 now and make rearrange a concrete task, or
- Move rearrange out of hard acceptance and keep Task D to drawer insertion/removal only

Do not leave "drawer rearrange tests green" as a hard gate while saying rearrange is blocked.

### 2026-04-23 06:02 EDT — Verification run completed

Command:

```bash
mise run test --filter LayoutFlatStripTests
```

Result:

- Exit code: 0
- Current baseline behavior is green
- Non-E2E Swift Testing run reported 2373 tests passed
- WebKit serialized test groups passed
- E2E and Zmx E2E were skipped by current environment/config

Interpretation:

This was not a full implementation verification. It was a grounding check for the existing layout baseline and existing regression coverage.

### 2026-04-23 06:04 EDT — Revised implementation shape recommended

Recommended implementation sequence:

1. Add pure ratio policy

   Suggested home:

   - `Sources/AgentStudio/Core/Models/DropSizingPolicy.swift`
   - `Tests/AgentStudioTests/Core/Models/DropSizingPolicyTests.swift`

   The policy should operate only on ratios, indices, and modes.

2. Add layout helpers that apply explicit ratios

   `Layout.inserting` currently always performs halve-target. Add a helper that takes pane order plus ratios, or a focused insertion helper with an explicit sizing mode.

   Avoid inserting with `Layout.inserting` and then mutating ratios afterward if a cleaner constructor/helper can preserve invariants in one step.

3. Decide command contract

   Candidate:

   ```swift
   case insertPane(
       source: PaneSource,
       targetTabId: UUID,
       targetPaneId: UUID,
       direction: SplitNewDirection,
       sizingMode: DropSizingMode
   )
   ```

   Then update all construction sites explicitly. This forces the codebase to reveal which paths are product drag behavior and which are command/default behavior.

4. Wire main insertion

   At `performDragOperation`, capture modifier state once and convert it to a pure sizing mode.

   For today's code, main drop only knows `PaneDropTarget`. Until unified targets land, every main drop is effectively split-zone/edge-corridor anchored, not a true slot target. If slot behavior depends on the sibling resolver, gate this task behind that plan.

5. Wire removal explicitly

   Implement proportional removal for the chosen user-facing removal paths.

   Open decision:

   - Should non-user repair/pruning paths use proportional removal too, or preserve current adjacent-absorb behavior?

6. Resolve or defer rearrange

   If R-1 is unresolved, rearrange cannot be a hard acceptance criterion.

   If R-1 is resolved, implement one atomic rearrange API that returns source-row and target-row ratios together. Avoid composing `remove` and `insert` in a way that creates transient wrong ratios or makes same-row moves depend on intermediate layout artifacts.

### 2026-04-23 06:06 EDT — Final review assessment

Final assessment:

The plan's product direction is usable, but the implementation section should be revised before execution.

Required edits before implementation:

- Clarify dependency on unified `DropTarget` or rewrite against current target types.
- Move pure sizing math out of `Core/Views/Splits` and remove AppKit from model/state-facing policy.
- Define the command/dispatch contract for carrying sizing mode.
- Add explicit proportional-removal wiring tasks.
- Resolve the drawer rearrange R-1 question or remove rearrange from hard acceptance.
- Replace duplicate baseline-test task with confirmation of existing coverage.

### 2026-04-23 06:10:27 EDT — Feedback file converted to time log format

Action:

Converted this artifact into a timestamped review log.

File:

- `docs/plans/2026-04-22-drop-sizing-policy-codex-feedback.md`
