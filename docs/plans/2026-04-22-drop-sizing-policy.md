# Drop sizing policy — Product decision + implementation plan

> **Status: DECISION MADE (2026-04-22).** User selected **Option D (hybrid) with Shift modifier → Option C (proportional preservation) override.** See §"Decided policy" below. Implementation can proceed; task details in §"Implementation plan" section.

## Prerequisites

- [ ] Unified drop-target plan (`docs/plans/2026-04-22-unified-drop-target-algo.md`) Tasks 1–2 have landed: `DropTarget`, `RowID`, `DropZoneSide`, `NewRowPosition`, `DropTargetConfig` all ship in `Core/Models/`. This plan uses those types directly — no stubs, no duplicates.
- [ ] The prereq from the unified plan are met (Phase B, main-pane fixture, two-row drawer fixture). Without them, the drag-commit code path this plan wires into is in mid-refactor.

**Goal:** Decide and document how pane widths are redistributed when a pane is inserted into or removed from a row, then implement the decision as a shared `DropSizingPolicy`.

**Scope boundary:** This plan does NOT change geometry, target resolution, or the drop-capture NSViews. It touches only `Layout.inserting` / `Layout.removing` and any drawer-specific insertion paths. Sibling plan `2026-04-22-unified-drop-target-algo.md` handles geometry unification and does not depend on this plan's outcome.

**Tech Stack:** Swift 6.2, `Testing`, mise, follows AgentStudio concurrency + code-style conventions.

---

## Current behavior (confirmed from source)

### Insertion — `Layout.inserting` (`Sources/AgentStudio/Core/Models/Layout.swift:69-99`)

**Rule: halve the target pane's ratio.** When a new pane is inserted before/after `targetPaneId`:

```
old:  [A=0.50, B=0.30, C=0.20]
insert N before B:
new:  [A=0.50, N=0.15, B=0.15, C=0.20]
                ^^^^^^^ target halved, new pane takes the other half
```

Only the target pane's ratio changes. Other panes keep their ratios untouched. Sum remains 1.0.

### Removal — `Layout.removing` (`Sources/AgentStudio/Core/Models/Layout.swift:101-123`)

**Rule: adjacent absorb.** Removed pane's ratio goes to the right neighbor, or the left neighbor if removed pane was last:

```
old:  [A=0.50, B=0.30, C=0.20]
remove B:
new:  [A=0.50, C=0.50]
                ^^^^ C absorbed B's 0.30 (C was right neighbor of removed B)
```

Only one neighbor's ratio changes. Others untouched.

### Drawer — inherits

Drawer insertions delegate to the same `Layout.inserting` (via `Layout.insertingPreservingRatios`). Drawer removals similarly. Drawer uses the same rules.

### Row split (drawer n×2) — stored explicitly

`DrawerGridLayout.rowSplitRatio` is stored per drawer (default 0.5). Not touched by insertion/removal. Not affected by this plan.

## The problem

No code today calls these rules by a clean policy name. They live inline in `Layout.inserting` / `Layout.removing`. When the upcoming drawer rearrange feature (moving a pane between rows, dropping into a slot) needs to redistribute space, it either:

a) Calls `Layout.inserting` and accepts halve-target behavior (fine if that's what we want), or
b) Writes its own ad-hoc rule (drift risk — UX differs between main drag-and-drop and drawer drag-and-drop)

We want one policy. Before we codify it, we must decide which policy.

---

## Options

### Option A — Keep current (halve-target on insert, adjacent-absorb on remove)

- **Insert**: target pane loses half its width; new pane takes it. Other panes unchanged.
- **Remove**: right neighbor (or left-most-if-last) absorbs removed pane's ratio. Others unchanged.

**Pros:**
- Zero behavior change — ships as pure refactor
- Users who expect the current "split-in-place" feel keep it
- Simple mental model: "inserting here splits that pane"
- Removal feels intentional: the pane next to the one you closed expands

**Cons:**
- Repeated insertion at the same slot keeps halving one pane (0.5 → 0.25 → 0.125 → …) → pane shrinks geometrically until it's tiny
- Visually asymmetric: inserting near pane B changes B's width but not A's or C's, even though all three are now sharing narrower screen space
- Doesn't scale well when N is large (new pane gets 1/(2·N) of total which is much less than its share of screen)

### Option B — Equal redistribution after insert / equal after remove

- **Insert**: all N+1 panes (including new) get 1/(N+1) of total. Prior ratios discarded.
- **Remove**: all N-1 remaining panes get 1/(N-1) of total.

**Pros:**
- Always visually symmetric
- Easy to reason about
- New pane gets a full share immediately

**Cons:**
- Destroys user's intentional sizing: "I made pane A wider because it's my editor" → insert a terminal → now A is equal-sized
- Inconsistent with how `equalizePanes` already works as an explicit action — if equal is the default on insert, `equalizePanes` is redundant
- Large behavior change; will surprise existing users

### Option C — Proportional preservation (new pane gets 1/(N+1); existing panes scale proportionally)

- **Insert**: new pane gets `1/(N+1)`. Remaining `N/(N+1)` is distributed to existing panes in proportion to their current ratios.

  ```
  old:  [A=0.50, B=0.30, C=0.20]   (N=3)
  insert N at index 1:
  new:  [A=0.375, N=0.25, B=0.225, C=0.15]
        (each old pane × 0.75 = 3/4; N gets 1/4)
  ```

- **Remove**: removed ratio distributed to remaining panes proportionally.

**Pros:**
- Respects user's relative sizing — "A is bigger than B" stays true after insert
- New pane gets a fair share (1/(N+1)) — doesn't steal disproportionately from one neighbor
- Symmetric with removal: same proportional rule

**Cons:**
- Behavior change — users who liked "split in place" notice that the target pane no longer shrinks specifically; *everyone* gets a bit smaller
- Slightly more complex mental model
- Every insertion touches every pane's ratio → more layout diff churn (cheap in practice but non-zero)

### Option D — "Respect the direction" hybrid

- **Insert** via drag: honor the `SplitDirection` direction/position hint. E.g., "drop on right half of A" → A shrinks, new pane appears to its right at A's prior width/2. Matches current Option A for split-drop.
- **Insert** via slot-midpoint in a row: use Option C proportional rule.
- **Remove**: Option C proportional rule.

**Pros:**
- Preserves the "splitting a specific pane" feel for explicit drop-on-pane actions
- Clean proportional redistribution for slot-insertions and removals (which have no obvious target pane)

**Cons:**
- Two rules to maintain
- User-visible inconsistency: same end state can feel different depending on the drop path
- More test surface

---

## Decided policy — Option D with Shift → Option C

**Default (no modifier):** Option D hybrid.

| Drop target kind | Default rule | Rationale |
|---|---|---|
| Split zone on a pane (drop on left/right half of a pane) | **Halve target** — target pane shrinks 50%, new pane takes the other half | Preserves the current "splitting this pane" UX users expect when they deliberately drop ON a pane |
| Slot midpoint (between panes in a row) | **Proportional preservation** | No single "target" to halve; proportional is the only rule that makes sense here |
| Edge corridor (main pane, left/right strip) | **Proportional preservation** | Same rationale — no obvious target |
| Drawer `newRow(top/bottom)` | **Proportional** vs existing row → new row gets the row-split ratio; intra-row starts at 1.0 for the single pane | Already the mechanical outcome; no choice needed |

**Shift held during drop:** Option C applied everywhere — proportional preservation regardless of drop target kind. Overrides the default on all four kinds above.

**Implementation shape:**

```swift
enum DropSizingMode: Hashable, Sendable {
    case halveTarget       // Option A semantics
    case proportional      // Option C semantics
}

enum DropSizingPolicy {
    /// Selects sizing mode given target kind and modifier flags captured at
    /// drop commit time. Shift forces `.proportional` regardless of target.
    static func sizingMode(
        for target: DropTarget,
        modifiers: NSEvent.ModifierFlags
    ) -> DropSizingMode {
        if modifiers.contains(.shift) { return .proportional }

        switch target {
        case .paneSplit:
            return .halveTarget
        case .paneSlot, .paneNewRow:
            return .proportional
        }
    }

    static func ratiosAfterInsertion(
        existingRatios: [Double],
        insertionIndex: Int,
        targetPaneIndex: Int?,      // non-nil only when mode == .halveTarget
        mode: DropSizingMode
    ) -> [Double] { ... }

    static func ratiosAfterRemoval(
        existingRatios: [Double],
        removalIndex: Int,
        mode: DropSizingMode             // always .proportional for now; reserved for future
    ) -> [Double] { ... }
}
```

**Modifier-state capture contract:**

Modifier flags are read ONCE, at the moment of `performDragOperation`, via `NSEvent.modifierFlags` — not tracked continuously during the drag. This matches macOS conventions (Finder copy-on-drag: shift-state at drop determines action).

Visual feedback while dragging: when shift is held, the drop-target highlight color/style should subtly indicate "proportional mode" (e.g., a slightly different stroke style). Polish item — implement after core behavior lands. Tracked as a follow-up task below.

**Discoverability:** shift-as-sizing-override is not discoverable by itself. Mitigations in priority order:
1. Document in `docs/guides/` drag-and-drop section (short paragraph)
2. Subtle visual change to drop highlight when shift is held
3. Optional future: menu item or preference to flip the default (most users never discover shift; if we see proportional telemetry > 50% via shift, flip default and inverse the modifier)

Not pursuing a tooltip during drag — macOS drag sessions don't support tooltips cleanly.

## Decision matrix (retained for reference)

| Criterion | A (halve) | B (equal) | C (proportional) | D (hybrid) |
|---|---|---|---|---|
| Behavior change | None | Large | Moderate | Small |
| User's custom sizing preserved | Partially | No | Yes | Yes (for slot) |
| New pane gets fair share | Only if target was big | Yes | Yes | Yes |
| Repeated insertion geometric shrink | Yes — target dies | No | No | Only split-drop path |
| Implementation complexity | Lowest (status quo) | Low | Low | Medium |
| Test surface | Smallest | Small | Small | Largest |
| Cohesive with drawer drag rearrange | Awkward (which pane halves on rowSlot?) | Fits | Fits | Fits |

**Recommendation for user review:** Option **C (proportional preservation)** unifies main and drawer behavior, preserves user intent, and fits slot-based drag drops naturally. Option A's halve-target is hard to generalize to row-slot drops where there's no obvious "target pane" to halve.

If you disagree, or want to preserve the current split-drop UX, pick D (hybrid) — that keeps the "splitting this pane" feel where it matters today.

---

## Resolved questions

1. **Which option?** D (hybrid) default; Shift overrides to C (proportional).
2. **Migration note in release notes?** No migration needed — existing drop-on-pane paths keep halve-target behavior. New row-slot drops use proportional, which is new functionality (no prior behavior to migrate from). Release notes can mention Shift as a power-user modifier.
3. **Which drag paths map to halve vs proportional (default)?** Drop-on-pane zone = halve-target; drop-on-slot-midpoint = proportional; edge corridor = proportional; newRow = mechanical (N/A).
4. **Visual feedback when shift held?** Subtle stroke-style change on drop highlight. Polish item — land core behavior first.

---

## Implementation plan (executes ONLY after user picks an option)

Each option has its own concrete implementation. All share the same extraction + test structure.

### Shared Task A — Confirm existing baseline coverage (no new tests)

`LayoutFlatStripTests` at `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift` already covers halve-target insertion and adjacent-absorb removal (confirmed in Codex review 2026-04-23). Running `mise run test --filter LayoutFlatStripTests` produces 2373 passing tests at baseline.

- [ ] **Step 1: Run existing tests**

  ```bash
  mise run test --filter LayoutFlatStripTests
  ```

  Expected: PASS. If it fails, stop — the baseline has drifted from documentation.

- [ ] **Step 2: Precision edge cases (only if gaps exist)**

  Audit `LayoutFlatStripTests` for:
  - Insertion into empty layout (new pane = 1.0) — add if missing
  - Insertion after removal (sum preserved across operations) — add if missing
  - Repeated insertion at same slot (geometric shrink documented) — add if missing

  Only add tests that describe missing coverage; don't duplicate.

- [ ] **Step 3: Commit (if any tests added)**

  ```bash
  git add Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift
  git commit -m "test: codify current insert/remove ratio behavior"
  ```

### Task B — Pure `DropSizingRatioPolicy` in Core/Models + AppKit adapter `DropSizingModeResolver` in Core/Views/DragAndDrop

Split into two pieces to keep model/state code AppKit-free (Codex P1-2):

**Files:**
- Create: `Sources/AgentStudio/Core/Models/DropSizingRatioPolicy.swift` — pure, Foundation only
- Create: `Tests/AgentStudioTests/Core/Models/DropSizingRatioPolicyTests.swift`
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DropSizingModeResolver.swift` — AppKit boundary
- Create: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropSizingModeResolverTests.swift`

**Dependency:** `DropTarget` (`.paneSplit`, `.paneSlot`, `.paneNewRow`) must exist — ships from the unified plan. Do NOT stub it in this plan.

- [ ] **Step 1: Write failing tests for pure ratio policy**

```swift
// Tests/AgentStudioTests/Core/Models/DropSizingRatioPolicyTests.swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropSizingRatioPolicyTests {
    // MARK: - halveTarget insertion

    @Test
    func ratiosAfterInsertion_halveTarget_halvesOnlyTargetPane() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [0.5, 0.3, 0.2],
            insertionIndex: 2,
            targetPaneIndex: 1,
            mode: .halveTarget
        )
        #expect(result.count == 4)
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.15) < 0.001)
        #expect(abs(result[2] - 0.15) < 0.001)
        #expect(abs(result[3] - 0.2) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterInsertion_halveTarget_noTargetIndex_fallsBackToProportional() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [0.6, 0.4],
            insertionIndex: 1,
            targetPaneIndex: nil,
            mode: .halveTarget
        )
        // With no target, policy falls back to proportional preservation.
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
        #expect(abs(result[1] - 1.0 / 3.0) < 0.001)
    }

    // MARK: - proportional insertion

    @Test
    func ratiosAfterInsertion_proportional_preservesExistingProportions() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [0.6, 0.4],
            insertionIndex: 1,
            targetPaneIndex: nil,
            mode: .proportional
        )
        #expect(result.count == 3)
        #expect(abs(result[0] - 0.4) < 0.001)
        #expect(abs(result[1] - 1.0 / 3.0) < 0.001)
        #expect(abs(result[2] - (0.4 * 2.0 / 3.0)) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterInsertion_intoEmpty_returnsSingleFullPane() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [],
            insertionIndex: 0,
            targetPaneIndex: nil,
            mode: .proportional
        )
        #expect(result == [1.0])
    }

    // MARK: - removal

    @Test
    func ratiosAfterRemoval_proportional_redistributesByProportion() {
        let result = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: [0.5, 0.25, 0.25],
            removalIndex: 0,
            mode: .proportional
        )
        #expect(result.count == 2)
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)
    }

    @Test
    func ratiosAfterRemoval_adjacentAbsorb_givesRatioToRightNeighbor() {
        // Repair paths use .halveTarget mode; removal falls back to adjacent-absorb,
        // which matches Layout.removing behavior today. Preserves conservative
        // repair semantics while user-path removals use .proportional.
        let result = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: [0.5, 0.3, 0.2],
            removalIndex: 1,
            mode: .halveTarget
        )
        #expect(result.count == 2)
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)  // 0.2 + 0.3 absorbed
    }
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter DropSizingRatioPolicyTests`
Expected: FAIL.

- [ ] **Step 3: Implement pure ratio policy (no AppKit)**

```swift
// Sources/AgentStudio/Core/Models/DropSizingRatioPolicy.swift
import Foundation

enum DropSizingMode: Hashable, Sendable {
    case halveTarget
    case proportional
}

enum DropSizingRatioPolicy {
    static func ratiosAfterInsertion(
        existingRatios: [Double],
        insertionIndex: Int,
        targetPaneIndex: Int?,
        mode: DropSizingMode
    ) -> [Double] {
        if existingRatios.isEmpty { return [1.0] }
        let clampedInsertion = max(0, min(insertionIndex, existingRatios.count))

        switch mode {
        case .halveTarget:
            guard let targetIdx = targetPaneIndex,
                  targetIdx >= 0, targetIdx < existingRatios.count
            else {
                return ratiosAfterInsertion(
                    existingRatios: existingRatios,
                    insertionIndex: clampedInsertion,
                    targetPaneIndex: nil,
                    mode: .proportional
                )
            }
            var updated = existingRatios
            let halved = updated[targetIdx] / 2
            updated[targetIdx] = halved
            updated.insert(halved, at: clampedInsertion)
            return updated

        case .proportional:
            let newPaneShare = 1.0 / Double(existingRatios.count + 1)
            let remaining = 1.0 - newPaneShare
            let existingSum = existingRatios.reduce(0, +)
            let scale = existingSum > 0 ? remaining / existingSum : 0
            var updated = existingRatios.map { $0 * scale }
            updated.insert(newPaneShare, at: clampedInsertion)
            return updated
        }
    }

    static func ratiosAfterRemoval(
        existingRatios: [Double],
        removalIndex: Int,
        mode: DropSizingMode
    ) -> [Double] {
        guard removalIndex >= 0, removalIndex < existingRatios.count else {
            return existingRatios
        }
        var updated = existingRatios
        let removed = updated.remove(at: removalIndex)

        switch mode {
        case .halveTarget:
            // Degenerate case: "halveTarget" has no insertion target on removal.
            // We adopt the historical adjacent-absorb rule — right neighbor
            // (or left if last) takes the removed ratio. Used for repair paths.
            if removalIndex < updated.count {
                updated[removalIndex] += removed
            } else if !updated.isEmpty {
                updated[updated.endIndex - 1] += removed
            }
            return updated

        case .proportional:
            let remainingSum = updated.reduce(0, +)
            guard remainingSum > 0 else { return updated }
            let scale = (remainingSum + removed) / remainingSum
            return updated.map { $0 * scale }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `mise run test --filter DropSizingRatioPolicyTests`
Expected: PASS.

- [ ] **Step 5: Commit (pure policy lands first)**

```bash
git add Sources/AgentStudio/Core/Models/DropSizingRatioPolicy.swift \
        Tests/AgentStudioTests/Core/Models/DropSizingRatioPolicyTests.swift
git commit -m "feat: DropSizingRatioPolicy — pure ratio math, no AppKit"
```

- [ ] **Step 6: Write failing tests for AppKit-adjacent mode resolver**

```swift
// Tests/AgentStudioTests/Core/Views/DragAndDrop/DropSizingModeResolverTests.swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropSizingModeResolverTests {
    @Test
    func mode_paneSplit_noShift_isHalveTarget() {
        let mode = DropSizingModeResolver.mode(
            for: .paneSplit(paneId: UUID(), side: .left),
            isShiftHeld: false
        )
        #expect(mode == .halveTarget)
    }

    @Test
    func mode_paneSplit_shift_isProportional() {
        let mode = DropSizingModeResolver.mode(
            for: .paneSplit(paneId: UUID(), side: .right),
            isShiftHeld: true
        )
        #expect(mode == .proportional)
    }

    @Test
    func mode_paneSlot_alwaysProportional() {
        let modeNoShift = DropSizingModeResolver.mode(
            for: .paneSlot(row: .main, index: 0),
            isShiftHeld: false
        )
        let modeShift = DropSizingModeResolver.mode(
            for: .paneSlot(row: .drawerTop, index: 2),
            isShiftHeld: true
        )
        #expect(modeNoShift == .proportional)
        #expect(modeShift == .proportional)
    }

    @Test
    func mode_paneNewRow_alwaysProportional() {
        let mode = DropSizingModeResolver.mode(
            for: .paneNewRow(position: .top),
            isShiftHeld: false
        )
        #expect(mode == .proportional)
    }
}
```

- [ ] **Step 7: Implement the mode resolver**

The resolver takes a plain `Bool` for shift state; it does NOT import AppKit. Callers (`SplitContainerDropCaptureOverlay.performDragOperation`, etc.) capture `NSEvent.modifierFlags.contains(.shift)` and pass the resulting `Bool`.

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DropSizingModeResolver.swift
import Foundation

enum DropSizingModeResolver {
    static func mode(for target: DropTarget, isShiftHeld: Bool) -> DropSizingMode {
        if isShiftHeld { return .proportional }
        switch target {
        case .paneSplit:
            return .halveTarget
        case .paneSlot, .paneNewRow:
            return .proportional
        }
    }
}
```

- [ ] **Step 8: Run tests to verify pass**

Run: `mise run test --filter DropSizingModeResolverTests`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropSizingModeResolver.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropSizingModeResolverTests.swift
git commit -m "feat: DropSizingModeResolver — Bool-in/DropSizingMode-out, no AppKit import"
```

### Task C — Extend command contracts with `sizingMode`

Both `PaneActionCommand.insertPane` and `PaneActionCommand.moveDrawerPane` carry `sizingMode: DropSizingMode` explicitly. (Codex P1-3 + 2nd-review finding: rearrange needs command-level sizing too, not just `insertPane`.) No implicit defaults — every construction site declares intent.

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift` — add `sizingMode` to both cases
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift` — propagate through validation
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift` — `insertPane` accepts and uses the mode
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` — `moveDrawerPane` accepts and uses the mode
- Modify: every construction site of `insertPane` / `moveDrawerPane`:
  - `SplitContainerDropCaptureOverlay.Coordinator.performDrop` — captures `NSEvent.modifierFlags.contains(.shift)`, resolves mode via `DropSizingModeResolver.mode(for:, isShiftHeld:)`, passes mode in
  - `DrawerDropDispatch.handleDrop` — same pattern
  - `PaneDropPlanner.splitDecision` — plumbs mode through `DropCommitPlan`
  - `PaneTabViewController.handleSplitDrop` — consumes
  - Drawer plus-button action handler — constructs with `.halveTarget` when active drawer pane exists, else `.proportional`
  - Merge tab / reactivate paths — construct with `.halveTarget` (conservative)

- [ ] **Step 1: Update command cases**

```swift
case insertPane(
    source: PaneSource,
    targetTabId: UUID,
    targetPaneId: UUID,
    direction: SplitNewDirection,
    sizingMode: DropSizingMode
)

case moveDrawerPane(
    parentPaneId: UUID,
    drawerPaneId: UUID,
    target: DrawerRearrangeTarget,
    sizingMode: DropSizingMode
)
```

- [ ] **Step 2: Update every construction site explicitly**

No default values. Build the codebase with the new cases and let the compiler list every missing `sizingMode:` — then decide the right value for each.

- [ ] **Step 3: Plumb through validation + dispatch**

`ActionValidator`, `DropCommitPlan`, command-bar command builders — pass the mode through without inspecting.

- [ ] **Step 4: Build + test**

```bash
mise run build && mise run test
```

Expected: build compiles cleanly (every call site gave explicit mode); all tests that used the old command shape either updated or re-express intent with explicit mode.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "feat: PaneActionCommand.insertPane + moveDrawerPane gain explicit sizingMode"
```

### Task C-index — `RearrangeIndexAdjustment` pure helper

**Files:**
- Create: `Sources/AgentStudio/Core/Models/RearrangeIndexAdjustment.swift`
- Create: `Tests/AgentStudioTests/Core/Models/RearrangeIndexAdjustmentTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct RearrangeIndexAdjustmentTests {
    @Test
    func sameRow_sourceBeforeTarget_shiftsByMinusOne() {
        let adjusted = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: .main, sourceIndex: 1,
            targetRow: .main, originalInsertionIndex: 3
        )
        #expect(adjusted == 2)
    }

    @Test
    func sameRow_sourceAfterTarget_unchanged() {
        let adjusted = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: .main, sourceIndex: 3,
            targetRow: .main, originalInsertionIndex: 1
        )
        #expect(adjusted == 1)
    }

    @Test
    func sameRow_sourceEqualsTargetSlot_becomesNoOp() {
        let adjusted = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: .main, sourceIndex: 2,
            targetRow: .main, originalInsertionIndex: 3
        )
        #expect(adjusted == 2)  // after removing index 2, original 3 becomes 2 (same position)
    }

    @Test
    func crossRow_unchanged() {
        let adjusted = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: .drawerTop, sourceIndex: 0,
            targetRow: .drawerBottom, originalInsertionIndex: 2
        )
        #expect(adjusted == 2)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `mise run test --filter RearrangeIndexAdjustmentTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Models/RearrangeIndexAdjustment.swift
import Foundation

enum RearrangeIndexAdjustment {
    static func adjustedInsertionIndex(
        sourceRow: RowID,
        sourceIndex: Int,
        targetRow: RowID,
        originalInsertionIndex: Int
    ) -> Int {
        guard sourceRow == targetRow else { return originalInsertionIndex }
        return sourceIndex < originalInsertionIndex
            ? originalInsertionIndex - 1
            : originalInsertionIndex
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `mise run test --filter RearrangeIndexAdjustmentTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/RearrangeIndexAdjustment.swift \
        Tests/AgentStudioTests/Core/Models/RearrangeIndexAdjustmentTests.swift
git commit -m "feat: RearrangeIndexAdjustment — pure rule for same-row slot shift"
```

### Task D — Wire `DropSizingRatioPolicy` into main-pane + drawer INSERTION paths

(Codex P2-1: rearrange moved out of this task scope — rearrange is Task D2 below. Task D covers insertion only. Drawer rearrange composes remove + insert against the same policy.)

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Layout.swift` — add `inserting(paneId:, atIndex:, ratios:)` overload that takes precomputed ratios rather than halving-in-place.
- Modify: `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift` — equivalent helper for drawer rows.
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.insertPane(...)` — accepts `sizingMode`; computes `ratiosAfterInsertion` via `DropSizingRatioPolicy`; applies via new Layout helper.
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.addDrawerPane / insertDrawerPane / restoreDrawerPane` — same pattern.

- [ ] **Step 1: Find all insertion call sites**

```bash
grep -rn "Layout.*\.inserting\(" Sources/AgentStudio/ | grep -v Tests | grep -v "//"
grep -rn "DrawerGridLayout\.inserting\|insertingPreservingRatios" Sources/AgentStudio/ | grep -v Tests
```

- [ ] **Step 2: Add the new Layout helper**

```swift
// Sources/AgentStudio/Core/Models/Layout.swift (added)
func inserting(paneId: UUID, atIndex insertionIndex: Int, ratios: [Double]) -> Self {
    precondition(ratios.count == panes.count + 1, "ratios must include the new pane")
    let clampedIndex = max(0, min(insertionIndex, panes.count))
    var updatedPanes = panes.map { PaneEntry(paneId: $0.paneId, ratio: 0) }
    updatedPanes.insert(PaneEntry(paneId: paneId, ratio: 0), at: clampedIndex)
    for (i, r) in ratios.enumerated() { updatedPanes[i].ratio = r }
    var updatedDividers = dividerIds
    updatedDividers.insert(UUID(), at: max(clampedIndex - 1, 0))
    return Self(panes: updatedPanes, dividerIds: updatedDividers)
}
```

(Note: `PaneEntry.ratio` currently `let`; may need a mutable init or a single-shot init that accepts ratios. Adjust signature accordingly.)

- [ ] **Step 3: Update insertion atoms to compute ratios + call new helper**

```swift
// In WorkspaceTabArrangementAtom.insertPane:
let existingRatios = layout.ratios
let newRatios = DropSizingRatioPolicy.ratiosAfterInsertion(
    existingRatios: existingRatios,
    insertionIndex: insertionIndex,
    targetPaneIndex: targetPaneIndex,
    mode: sizingMode
)
let updatedLayout = layout.inserting(paneId: newPaneId, atIndex: insertionIndex, ratios: newRatios)
```

- [ ] **Step 4: Tests — audit every ratio-asserting test**

Every drag-drop test in `Tests/AgentStudioTests/App/` and `Tests/AgentStudioTests/Core/` that asserts specific post-insertion ratios needs explicit review:
- Tests for drop-on-pane-zone: must pass `sizingMode: .halveTarget`, assert halve behavior
- Tests for drop-on-slot: must pass `sizingMode: .proportional`, assert proportional behavior
- Tests for plus-button insertion: `.halveTarget` (active pane) OR `.proportional` (no active pane)

Explicit per-test audit. No batch update.

- [ ] **Step 5: Full suite**

```bash
mise run build && mise run test && mise run lint
```

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "refactor: insertion paths use DropSizingRatioPolicy via sizingMode"
```

### Task D2 — Wire drawer rearrange through remove+insert with `RearrangeIndexAdjustment`

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.moveDrawerPane(...)` — accepts `sizingMode`; uses remove+insert composition.
- Modify: `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift` — remove the halving-based `insertingPreservingRatios`; replace with a rearrange that composes `ratiosAfterRemoval` + `ratiosAfterInsertion` via policy.

- [ ] **Step 1: Reshape `moveDrawerPane`**

Accepts the `sizingMode` from the command, executes atomic remove-then-insert:

```swift
func moveDrawerPane(parentPaneId: UUID, drawerPaneId: UUID, target: DrawerRearrangeTarget, sizingMode: DropSizingMode) {
    // 1. Locate source: which row, what index.
    // 2. Compute source-side ratios via ratiosAfterRemoval(..., mode: .proportional)
    //    — rearrange source always proportional, matches "moving out" semantic.
    // 3. Compute adjusted target index via RearrangeIndexAdjustment.adjustedInsertionIndex.
    // 4. Compute target-side ratios via ratiosAfterInsertion(..., mode: sizingMode).
    // 5. Apply both updates atomically.
}
```

- [ ] **Step 2: Drop the misleading helper name**

Delete `DrawerGridLayout+Rearrange.insertingPreservingRatios` — the name claims to preserve ratios but currently halves the anchor pane (confirmed in Codex 2nd review). Replace call sites with explicit remove+insert composition.

- [ ] **Step 3: Tests**

- Same-row forward move — assert adjusted index; assert both rows sum to 1.0
- Same-row backward move — assert unchanged index
- Cross-row move (drawer n×2) — assert source row sums to 1.0 post-remove, target row sums to 1.0 post-insert
- Move with shift: assert target-side uses `.proportional` regardless of target kind

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: drawer rearrange via RearrangeIndexAdjustment + remove+insert"
```

### Task D3 — Wire user-initiated removal paths through proportional policy

(Codex P1-4: removal decided but not wired.)

**In scope (user paths — use `.proportional`):**
- `WorkspacePaneAtom.removeDrawerPane` — user closes a drawer pane
- `WorkspacePaneAtom.detachDrawerPane` — user detaches a drawer pane
- Main pane close / extract paths in `WorkspaceTabArrangementAtom.removing` call sites

**Out of scope (repair paths — keep adjacent-absorb, i.e., `.halveTarget` mode on `ratiosAfterRemoval`):**
- `TabArrangementRepairRules.removingPane` — orphan cleanup / crash recovery / stale-state pruning

**Why the asymmetry:** user-path removal is a deliberate action; proportional keeps relative sizing intent. Repair paths are reactive to inconsistent state (crash recovery, restore with dangling references) — conservative adjacent-absorb preserves the closest-to-prior layout shape. User confirmed 2026-04-23.

- [ ] **Step 1: Grep for removal call sites**

```bash
grep -rn "Layout.removing\|DrawerGridLayout.removing" Sources/AgentStudio/ | grep -v Tests
```

- [ ] **Step 2: For each user-path call site, compute ratios via policy**

```swift
let newRatios = DropSizingRatioPolicy.ratiosAfterRemoval(
    existingRatios: layout.ratios,
    removalIndex: idx,
    mode: .proportional
)
```

- [ ] **Step 3: Leave repair-path call sites calling `.halveTarget` on policy (adjacent-absorb)**

Document the asymmetry with an inline comment referencing this plan.

- [ ] **Step 4: Tests**

- User close: assert removed pane's ratio is redistributed proportionally
- Repair path: assert adjacent-absorb preserved (same as current behavior)

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: user-path removal proportional, repair-path adjacent-absorb"
```

### Task E — Visual feedback when shift is held (polish)

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneDropTargetOverlay.swift`

Pipe an `isProportionalMode: Bool` (derived from live modifier tracking during drag) into both overlays; render the highlight stroke with a slightly different style when true (e.g., dashed stroke, or a second-color ring).

Keep this as a follow-on after core behavior is validated. If modifier-during-drag polling is fragile, defer to a future polish pass.

- [ ] Commit:
  ```bash
  git commit -m "feat: drop target overlay hints at proportional mode when shift held"
  ```

---

## Acceptance criteria

### Hard — gate for landing sizing policy

- [x] User has signed off on one of A / B / C / D → **D with Shift→C override**
- [ ] Shared Task A: existing `LayoutFlatStripTests` confirmed green at baseline
- [ ] Task B: `DropSizingRatioPolicy` + `DropSizingModeResolver` tests green
- [ ] Task C: command contracts updated; every `insertPane` / `moveDrawerPane` construction site declares `sizingMode` explicitly
- [ ] Task C-index: `RearrangeIndexAdjustment` pure helper tests green
- [ ] Task D: main-pane + drawer insertion paths use `DropSizingRatioPolicy`; affected tests reviewed per-test
- [ ] Task D2: drawer rearrange uses remove+insert via policy; `insertingPreservingRatios` helper deleted
- [ ] Task D3: user-initiated removal paths proportional; repair paths keep adjacent-absorb (inline-commented)
- [ ] Full `mise run test` suite passes
- [ ] `mise run lint` passes (0 violations)
- [ ] Manual verification:
  - 4-pane horizontal split, drop-on-pane-zone of pane index 1: only that pane shrinks 50%, other panes unchanged
  - 4-pane horizontal split, drop-on-slot between panes 1 and 2: all four existing panes scale proportionally to 0.8×, new pane gets 0.2 share
  - 4-pane horizontal split, shift-held drop-on-pane-zone: proportional applies, not halve
  - Drawer n×1, drop onto rowSlot: proportional
  - Drawer n×1, drag to top band: `.paneNewRow(.top)` created
  - User closes a main pane: remaining ratios proportional
  - Crash-recovery drops a stale pane: remaining ratios via adjacent-absorb (unchanged from today)

### Soft — polish

- [ ] Task E visual indicator when shift held
- [ ] One-line mention of shift modifier in `docs/guides/` drag-and-drop docs

## Rearrangement sizing — resolved 2026-04-23

User observation that collapsed the question: rearrange IS just remove + insert. The 3 target kinds already tell us how the arriving pane sizes — no separate "rearrange rule" is needed.

**Resolution — fresh-ratio via mechanism reuse:**

Rearrangement (move-existing-pane) = atomic `ratiosAfterRemoval(source)` composed with `ratiosAfterInsertion(target)`, using the existing insertion policy for the target side based on target kind:

| Target kind | Target-side sizing | Source-side sizing |
|---|---|---|
| `.paneSplit(paneId, side)` (no shift) | halve target pane; arriving pane takes the halved slot | source row redistributes removed pane's ratio proportionally |
| `.paneSplit(paneId, side)` + shift | proportional insertion in target row | source row proportional removal |
| `.paneSlot(row, index)` | proportional insertion in target row (arriving pane gets 1/(N+1)) | source row proportional removal |
| `.paneSlot(row, index)` + shift | same (shift is no-op for slot — no target to halve) | same |
| `.paneNewRow(position)` (drawer only) | arriving pane takes 1.0 of new row; new row gets `rowSplitRatio` of panel height | source row proportional removal |

**Key implication:** no new `ratiosForRearrange` method. `DropSizingRatioPolicy` exposes only `ratiosAfterInsertion` + `ratiosAfterRemoval`; rearrange callers compose them. Source and target can be the same row (same-row rearrange) — policy still applies cleanly because remove-then-insert against the post-remove ratios is well-defined.

**Same-row rearrange — index adjustment rule (P1 from codex 2nd review):**

For same-row rearranges the insertion index captured BEFORE removal may shift after the source pane is removed from that row. Deterministic rule, tested as a pure helper (`RearrangeIndexAdjustment.adjustedInsertionIndex(...)`):

```
if sourceRow == targetRow && sourceIndex < originalInsertionIndex:
    adjustedIndex = originalInsertionIndex - 1
else:
    adjustedIndex = originalInsertionIndex
```

This is applied AFTER `ratiosAfterRemoval` returns the new source-row ratios, BEFORE `ratiosAfterInsertion` is called against the target row. Cross-row rearranges bypass (source and target rows differ → no shift).

Test cases the pure helper must pass:
- same-row forward move (source before target): index shifts by -1
- same-row backward move (source after target): index unchanged
- no-op (source == target slot): index shifts by -1 → effectively same position
- move to end slot: still shifts correctly when source is earlier

**Shift modifier is command-level, not drag-only:**

`DropSizingMode` enters both `PaneActionCommand.insertPane(..., sizingMode:)` AND `PaneActionCommand.moveDrawerPane(..., sizingMode:)` (and equivalent main-pane rearrange commands when added). Origins that actually exist today:

| Command origin | Modifier read at | Default without shift |
|---|---|---|
| Drag drop (main + drawer) | `performDragOperation` in capture NSView | target-kind-dependent (halve for `.paneSplit`, proportional for `.paneSlot` / `.paneNewRow`) |
| Plus-button in drawer icon bar (creates new drawer pane) | Click handler | `.halveTarget` if active drawer pane exists; `.proportional` otherwise (target = end-of-row `.paneSlot`) |
| Menu item / programmatic add-drawer-pane | Action origin | Same as plus-button |
| Merge tab / reactivate backgrounded pane | Action origin | `.halveTarget` (conservative — matches existing behavior) |

Explicitly NOT in this list (confirmed with user 2026-04-23): there is no ⌘D keyboard split command in AgentStudio. No split-right/split-left keyboard shortcuts exist.

Shift held at any origin → `.proportional` (runtime-read from `NSEvent.modifierFlags` at the originating UI event).

**Rearrange is now a concrete task in Task D, not blocked.**

## Rearrangement — test pyramid (scaled by risk, Codex P2 2nd review)

Per the test-layer discussion (unit → mock → hidden-window → invariant → fixture), test coverage is scaled by risk — NOT every layer for every combination.

| Layer | Scope for rearrange |
|---|---|
| **A (pure unit) — FULL MATRIX** | Every (source-row-state × target-kind × shift) combination. Same-row forward/backward, cross-row, onto `.paneSplit`, into `.paneSlot`, with and without shift, source-empties-after-remove, target-empty-before-insert. Fast, cheap, comprehensive. Includes `RearrangeIndexAdjustment` edge cases. |
| **B (mock `NSDraggingInfo`) — REPRESENTATIVE HIGH-RISK** | A small handful of paths chosen for their plumbing risk: same-row forward (index adjustment), cross-row shift-held, empty-source edge. Not the full matrix. |
| **C (hidden window) — REPRESENTATIVE ONLY** | 1–2 end-to-end rearranges that verify SwiftUI preference propagation + real NSView drag routing land the expected ratios. Does not duplicate Layer A matrix. |
| **D (invariant) — PROPERTY TEST** | Random-generated rearrange scenarios: `∀ source ∀ target ∀ shift: |sum_source - 1.0| < ε ∧ |sum_target - 1.0| < ε ∧ pane-count conserved`. Covers combinations Layer A doesn't enumerate. |
| **E (fixture) — CAPTURED REAL-USER ONLY** | Golden-file from recorded rearrange drag sessions. Covers paths users actually exercise. NOT every theoretical combination. |

**Acceptance threshold for rearrange:**
- Full matrix coverage in Layer A (pure unit) required
- Property coverage in Layer D required
- Layers B / C / E cover representative + real-world paths, not full matrix — gating on "every combination in every layer" makes the test surface brittle and expensive (Codex-flagged).

## Non-goals

- Geometry resolution (that's the unified-algo plan)
- Drawer row-split ratio changes (`rowSplitRatio` stays as-is)
- Tab-level drawer drop capture structural fix (separate plan)
