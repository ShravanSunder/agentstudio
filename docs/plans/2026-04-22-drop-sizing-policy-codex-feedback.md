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

### 2026-04-23 06:28:18 EDT — Second review opened

Reason:

The source plan changed after the first review. The rearrangement section is no longer marked open/blocked; it is now marked resolved.

New source evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:645`
- `docs/plans/2026-04-22-drop-sizing-policy.md:677`

Impact:

The earlier finding "drawer rearrange is both required and blocked" is now partly stale. The contradiction was addressed by marking rearrange concrete, but the updated section introduces new consistency and command-contract problems.

### 2026-04-23 06:30 EDT — Superseded finding: rearrange blocked/required conflict partially resolved

Superseded earlier finding:

- `2026-04-23 05:59 EDT — Finding P2: drawer rearrange is both required and blocked`

Current assessment:

The source plan now says:

- "Rearrangement sizing — resolved 2026-04-23"
- "Rearrange is now a concrete task in Task D, not blocked."

Evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:645`
- `docs/plans/2026-04-22-drop-sizing-policy.md:677`

Updated status:

The old blocked-vs-required contradiction is no longer the right critique. Keep the historical finding for audit trail, but do not treat it as current unless the source plan reverts.

### 2026-04-23 06:31 EDT — New finding P1: target vocabulary is inconsistent inside the plan

Finding:

The plan now uses two different unified target vocabularies:

- earlier sections use `.splitZone`, `.slot`, `.newRow`
- the resolved rearrange section uses `.paneSplit`, `.paneSlot`, `.paneNewRow`

Plan evidence:

- `.splitZone`: `docs/plans/2026-04-22-drop-sizing-policy.md:164`
- `.slot`, `.newRow`: `docs/plans/2026-04-22-drop-sizing-policy.md:166`
- `.paneSplit`: `docs/plans/2026-04-22-drop-sizing-policy.md:655`
- `.paneSlot`: `docs/plans/2026-04-22-drop-sizing-policy.md:657`
- `.paneNewRow`: `docs/plans/2026-04-22-drop-sizing-policy.md:659`

Sibling plan evidence:

The unified target plan's design uses:

- `.paneSplit(paneId:side:)`
- `.paneSlot(row:index:)`
- `.paneNewRow(position:)`

Evidence:

- `docs/plans/2026-04-22-unified-drop-target-algo.md:107`
- `docs/plans/2026-04-22-unified-drop-target-algo.md:112`
- `docs/plans/2026-04-22-unified-drop-target-algo.md:117`
- `docs/plans/2026-04-22-unified-drop-target-algo.md:122`

Why it matters:

An implementer following Task B would write tests against `.splitZone`, while an implementer following the rearrange section would write tests against `.paneSplit`. That will either fail to compile or cause duplicate translation types.

Recommendation:

Normalize the sizing plan to the sibling plan's names everywhere:

- `.paneSplit(paneId:side:)`
- `.paneSlot(row:index:)`
- `.paneNewRow(position:)`

Also update the Task B tests and implementation snippet. Remove the note that says to stub `.splitZone`.

### 2026-04-23 06:33 EDT — New finding P1: rearrange needs command-level sizing, but only `insertPane` is specified

Finding:

The updated plan says `DropSizingMode` enters `PaneActionCommand.insertPane(..., sizingMode:)` at every origin, but rearrange is executed through move commands, not `insertPane`.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:651`
- `docs/plans/2026-04-22-drop-sizing-policy.md:663`
- `docs/plans/2026-04-22-drop-sizing-policy.md:665`
- `docs/plans/2026-04-22-drop-sizing-policy.md:677`

Current code evidence:

Drawer rearrange dispatches:

- `PaneActionCommand.moveDrawerPane(parentPaneId:drawerPaneId:target:)`

Evidence:

- `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift:147`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropDispatch.swift:56`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift:314`

Why it matters:

If rearrange is now concrete, then `DropSizingMode` cannot only live on `insertPane`. The move/rearrange command must carry enough information for source-side proportional removal and target-side insertion mode, especially for Shift and target-kind-dependent behavior.

Recommendation:

Add an explicit command contract for rearrange. Candidate shape:

```swift
case moveDrawerPane(
    parentPaneId: UUID,
    drawerPaneId: UUID,
    target: DrawerRearrangeTarget,
    sizingMode: DropSizingMode
)
```

If main-pane rearrange is also in scope, add the equivalent main move command or clarify that only drawer rearrange is covered.

Also update validators and `DrawerDropDispatch` so synthetic/mock/hidden-window tests can assert the sizing mode reaches execution.

### 2026-04-23 06:35 EDT — New finding P1: same-row rearrange needs index-adjustment rules

Finding:

The updated plan says same-row rearrange is cleanly handled by remove-then-insert against post-remove ratios, but it does not specify how the target insertion index is adjusted after removing the source pane from the same row.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:651`
- `docs/plans/2026-04-22-drop-sizing-policy.md:661`
- `docs/plans/2026-04-22-drop-sizing-policy.md:685`
- `docs/plans/2026-04-22-drop-sizing-policy.md:691`

Current code evidence:

Current drawer rearrange already performs remove-then-insert:

- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift:4`

Current slot insertion receives an index directly:

- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift:26`

Why it matters:

For same-row forward moves, an insertion index captured before removal may point one slot too far right after the source pane is removed. For same-row backward moves, it may remain valid. The plan calls out same-row edge cases in tests, but the implementation contract should define the adjustment rule, not leave it for tests to discover.

Recommendation:

Add a small deterministic rule to the plan:

- If source and target are the same row and `sourceIndex < originalInsertionIndex`, apply insertion to `originalInsertionIndex - 1` after removal.
- Otherwise use `originalInsertionIndex`.

Then write unit tests for:

- same-row forward move
- same-row backward move
- move to same original slot/no-op
- move to end slot

### 2026-04-23 06:37 EDT — New finding P2: no-active-pane insertion is underspecified

Finding:

The command-origin table says "No-active-pane in tab" defaults to proportional with target `.paneSlot` at the end of row, but current command and layout insertion APIs require a target pane anchor.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:667`
- `docs/plans/2026-04-22-drop-sizing-policy.md:673`

Current code evidence:

- `PaneActionCommand.insertPane` requires `targetPaneId`: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift:57`
- `WorkspaceTabArrangementAtom.insertPane` requires `targetPaneId`: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift:55`
- `Layout.inserting` requires `targetPaneId`: `Sources/AgentStudio/Core/Models/Layout.swift:69`

Why it matters:

A `.paneSlot` at end of row is not representable by today's command shape unless it is translated back to a target pane plus side. For an empty row or no active pane, there may be no anchor. This needs either a slot-based command or a specific fallback path.

Recommendation:

Choose one:

- Add slot-based insertion APIs that can insert by row/index, including empty rows.
- Keep target-pane commands and remove the no-active-pane row from this table unless a valid anchor can always be derived.

### 2026-04-23 06:39 EDT — New finding P2: five-layer rearrange test gate is likely too heavy for every combination

Finding:

The updated plan requires all five test layers green for every rearrange combination being shipped.

Plan evidence:

- `docs/plans/2026-04-22-drop-sizing-policy.md:679`
- `docs/plans/2026-04-22-drop-sizing-policy.md:681`
- `docs/plans/2026-04-22-drop-sizing-policy.md:691`
- `docs/plans/2026-04-22-drop-sizing-policy.md:693`

Why it matters:

The unit and invariant layers are appropriate for the full combination matrix. Requiring mock `NSDraggingInfo`, hidden-window UI, and golden fixtures for every combination risks making the plan expensive and brittle. It may also force UI-level tests for behavior that is pure ratio math.

Recommendation:

Scale the test gate by risk:

- Full matrix in Layer A pure unit tests.
- Random/property coverage in Layer D invariants.
- Representative high-risk paths in Layer B/C.
- Fixture coverage for captured real-user flows, not every theoretical combination.

This keeps the plan rigorous without turning every ratio case into an end-to-end drag test.

### 2026-04-23 06:41 EDT — Second review assessment

Current status after the source-plan update:

Improved:

- Rearrangement is no longer open-ended; the plan now chooses fresh-ratio via remove + insert.
- The plan now acknowledges sizing mode must be command-level, not only drag-level.
- The test strategy explicitly names same-row and cross-row rearrange risks.

Still blocking:

- The target vocabulary is inconsistent and still depends on the sibling unified-target plan.
- The AppKit/view-boundary issue remains.
- The main insertion command contract remains incomplete.
- Removal wiring remains incomplete.
- Rearrangement now needs its own command-level sizing contract, not only `insertPane(..., sizingMode:)`.
- Same-row slot index adjustment must be specified.

Updated recommendation:

Do not execute this plan yet. Revise the plan once more, mainly to make the target vocabulary and command contracts precise.

### 2026-04-23 — Sizing plan updated; all findings addressed

Applied to `docs/plans/2026-04-22-drop-sizing-policy.md` across three commits (`0448129`, `33973b3`):

**First-review findings:**
- P1-1 (unified vocabulary dependency): added Prerequisites section at top of sizing plan making dependency on unified-plan target types (DropTarget, DropZoneSide, RowID, NewRowPosition) explicit. No stubs, no duplicates. Sizing plan cannot execute before unified plan Tasks 1-2 land.
- P1-2 (AppKit leak into model/state): Task B split into two pieces. `DropSizingRatioPolicy` in `Core/Models/` is pure (Foundation only). `DropSizingModeResolver` in `Core/Views/DragAndDrop/` takes `isShiftHeld: Bool` — no AppKit imports in the resolver either; callers at AppKit boundary read `NSEvent.modifierFlags.contains(.shift)` and pass `Bool`.
- P1-3 (dispatch contract): Task C makes `sizingMode: DropSizingMode` explicit on `PaneActionCommand.insertPane` AND `PaneActionCommand.moveDrawerPane`. No default values; every construction site declares intent. Command origins enumerated (drag, plus-button, menu, merge-tab, reactivate) — keyboard split explicitly removed because it does not exist in AgentStudio.
- P1-4 (removal not wired): Task D3 added. User-initiated removal paths use `.proportional`; repair paths (`TabArrangementRepairRules`) keep `.halveTarget` (which on removal = adjacent-absorb). Asymmetry documented + inline-commented at sites.

**Second-review findings:**
- P1 (target vocabulary inconsistent): normalized to `.paneSplit` / `.paneSlot` / `.paneNewRow` throughout. All `.splitZone` / `.slot` / `.newRow` references replaced.
- P1 (rearrange needs command-level sizing): covered by P1-3 fix (`moveDrawerPane` gains `sizingMode`). Task D2 added for drawer rearrange via remove+insert composition.
- P1 (same-row index adjustment): Task C-index adds `RearrangeIndexAdjustment` pure helper with the deterministic rule (`sourceIndex < originalInsertionIndex → index - 1; else unchanged`). Unit-tested 4 scenarios (forward, backward, no-op, cross-row).
- P2 (no-active-pane underspecified): command-origins table now explicit — plus-button without active pane uses `.proportional` with `.paneSlot` at end of row; insertion APIs add slot-based path when no anchor is available.
- P2 (five-layer test gate too heavy): test pyramid scaled by risk. Layer A full matrix + Layer D property coverage required; Layers B/C/E representative only. Acceptance threshold documented.
- P2 (Shared Task A stale): replaced with baseline-confirmation (existing `LayoutFlatStripTests` are green; only add precision edge cases if gaps).

**Superseded:**
- First-review P2 "drawer rearrange is both required and blocked" was already addressed earlier by R-1 resolution; Task D scope trim in this pass finalizes the cleanup.

**No sibling-plan changes required** — the unified drop-target plan already uses the final vocabulary; no stray `⌘D` keyboard-split reference exists there.

This log remains the historical record. No further action on this file unless a 3rd review is triggered.
