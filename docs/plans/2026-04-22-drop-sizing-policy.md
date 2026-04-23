# Drop sizing policy — Product decision + implementation plan

> **Status: DECISION MADE (2026-04-22).** User selected **Option D (hybrid) with Shift modifier → Option C (proportional preservation) override.** See §"Decided policy" below. Implementation can proceed; task details in §"Implementation plan" section.

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
enum SizingMode: Hashable, Sendable {
    case halveTarget       // Option A semantics
    case proportional      // Option C semantics
}

enum DropSizingPolicy {
    /// Selects sizing mode given target kind and modifier flags captured at
    /// drop commit time. Shift forces `.proportional` regardless of target.
    static func sizingMode(
        for target: DropTarget,
        modifiers: NSEvent.ModifierFlags
    ) -> SizingMode {
        if modifiers.contains(.shift) { return .proportional }

        switch target {
        case .splitZone:
            return .halveTarget
        case .slot, .newRow:
            return .proportional
        }
    }

    static func ratiosAfterInsertion(
        existingRatios: [Double],
        insertionIndex: Int,
        targetPaneIndex: Int?,      // non-nil only when mode == .halveTarget
        mode: SizingMode
    ) -> [Double] { ... }

    static func ratiosAfterRemoval(
        existingRatios: [Double],
        removalIndex: Int,
        mode: SizingMode             // always .proportional for now; reserved for future
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

### Shared Task A — Codify current behavior as regression tests

Before any change. Prevents accidental drift.

- [ ] **Step 1: Write regression tests for current `Layout.inserting`**

  File: `Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift` (already exists — add if missing)

  ```swift
  @Test
  func inserting_halvesTargetPaneRatio() {
      let a = UUID(), b = UUID(), c = UUID()
      let layout = Layout(
          panes: [
              .init(paneId: a, ratio: 0.5),
              .init(paneId: b, ratio: 0.3),
              .init(paneId: c, ratio: 0.2),
          ],
          dividerIds: [UUID(), UUID()]
      )
      let newPane = UUID()
      let result = layout.inserting(paneId: newPane, at: b, direction: .horizontal, position: .before)

      #expect(result.panes.map(\.paneId) == [a, newPane, b, c])
      #expect(abs(result.panes[0].ratio - 0.5) < 0.001)   // A unchanged
      #expect(abs(result.panes[1].ratio - 0.15) < 0.001)  // new pane = half of B's prior
      #expect(abs(result.panes[2].ratio - 0.15) < 0.001)  // B halved
      #expect(abs(result.panes[3].ratio - 0.2) < 0.001)   // C unchanged
  }

  @Test
  func removing_givesRatioToRightNeighbor() {
      let a = UUID(), b = UUID(), c = UUID()
      let layout = Layout(
          panes: [
              .init(paneId: a, ratio: 0.5),
              .init(paneId: b, ratio: 0.3),
              .init(paneId: c, ratio: 0.2),
          ],
          dividerIds: [UUID(), UUID()]
      )
      guard let result = layout.removing(paneId: b) else {
          Issue.record("expected removal to succeed")
          return
      }
      #expect(result.panes.map(\.paneId) == [a, c])
      #expect(abs(result.panes[0].ratio - 0.5) < 0.001)   // A unchanged
      #expect(abs(result.panes[1].ratio - 0.5) < 0.001)   // C absorbed B's 0.3 (0.2 + 0.3)
  }
  ```

- [ ] **Step 2: Run tests — they should PASS against current code**

  `mise run test --filter LayoutFlatStripTests`

  If they fail, the current code does not match the behavior I documented above. Stop. Re-read the source. Do not proceed until the tests pass against HEAD.

- [ ] **Step 3: Commit**

  ```bash
  git add Tests/AgentStudioTests/Core/Models/LayoutFlatStripTests.swift
  git commit -m "test: codify current insert/remove ratio behavior"
  ```

### Task B — Extract `SizingMode` + `DropSizingPolicy` core

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/DropSizingPolicy.swift`
- Create: `Tests/AgentStudioTests/Core/Views/Splits/DropSizingPolicyTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropSizingPolicyTests {
    // MARK: - mode selection

    @Test
    func sizingMode_splitZone_defaultsToHalveTarget() {
        let mode = DropSizingPolicy.sizingMode(
            for: .splitZone(paneId: UUID(), direction: .left),
            modifiers: []
        )
        #expect(mode == .halveTarget)
    }

    @Test
    func sizingMode_slot_defaultsToProportional() {
        let mode = DropSizingPolicy.sizingMode(
            for: .slot(row: .main, index: 1),
            modifiers: []
        )
        #expect(mode == .proportional)
    }

    @Test
    func sizingMode_shiftHeld_forcesProportional_regardlessOfTarget() {
        let splitModeWithShift = DropSizingPolicy.sizingMode(
            for: .splitZone(paneId: UUID(), direction: .left),
            modifiers: .shift
        )
        #expect(splitModeWithShift == .proportional)

        let slotModeWithShift = DropSizingPolicy.sizingMode(
            for: .slot(row: .drawerTop, index: 0),
            modifiers: .shift
        )
        #expect(slotModeWithShift == .proportional)
    }

    // MARK: - halve-target

    @Test
    func ratiosAfterInsertion_halveTarget_halvesOnlyTargetPane() {
        let result = DropSizingPolicy.ratiosAfterInsertion(
            existingRatios: [0.5, 0.3, 0.2],
            insertionIndex: 2,     // insert between index 1 (the 0.3) and index 2 (the 0.2)
            targetPaneIndex: 1,    // target is the 0.3 pane
            mode: .halveTarget
        )
        #expect(result.count == 4)
        #expect(abs(result[0] - 0.5) < 0.001)   // unchanged
        #expect(abs(result[1] - 0.15) < 0.001)  // halved from 0.3
        #expect(abs(result[2] - 0.15) < 0.001)  // new pane, took the other half
        #expect(abs(result[3] - 0.2) < 0.001)   // unchanged
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    // MARK: - proportional

    @Test
    func ratiosAfterInsertion_proportional_preservesExistingProportions() {
        let result = DropSizingPolicy.ratiosAfterInsertion(
            existingRatios: [0.6, 0.4],
            insertionIndex: 1,
            targetPaneIndex: nil,
            mode: .proportional
        )
        #expect(result.count == 3)
        // new pane gets 1/3, existing share 2/3 in 3:2 ratio
        #expect(abs(result[0] - 0.4) < 0.001)
        #expect(abs(result[1] - 1.0 / 3.0) < 0.001)
        #expect(abs(result[2] - (0.4 * 2.0 / 3.0)) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterInsertion_intoEmpty_returnsSingleFullPane() {
        let result = DropSizingPolicy.ratiosAfterInsertion(
            existingRatios: [],
            insertionIndex: 0,
            targetPaneIndex: nil,
            mode: .proportional
        )
        #expect(result == [1.0])
    }

    // MARK: - removal

    @Test
    func ratiosAfterRemoval_proportional_redistributesEquallyByProportion() {
        let result = DropSizingPolicy.ratiosAfterRemoval(
            existingRatios: [0.5, 0.25, 0.25],
            removalIndex: 0,
            mode: .proportional
        )
        #expect(result.count == 2)
        // [0.25, 0.25] scaled to sum 1.0 → [0.5, 0.5]
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter DropSizingPolicyTests`
Expected: FAIL — `DropSizingPolicy` not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Views/Splits/DropSizingPolicy.swift
import AppKit
import Foundation

enum SizingMode: Hashable, Sendable {
    case halveTarget
    case proportional
}

enum DropSizingPolicy {
    static func sizingMode(
        for target: DropTarget,
        modifiers: NSEvent.ModifierFlags
    ) -> SizingMode {
        if modifiers.contains(.shift) {
            return .proportional
        }
        switch target {
        case .splitZone:
            return .halveTarget
        case .slot, .newRow:
            return .proportional
        }
    }

    static func ratiosAfterInsertion(
        existingRatios: [Double],
        insertionIndex: Int,
        targetPaneIndex: Int?,
        mode: SizingMode
    ) -> [Double] {
        if existingRatios.isEmpty { return [1.0] }

        let clampedInsertion = max(0, min(insertionIndex, existingRatios.count))

        switch mode {
        case .halveTarget:
            guard let targetIdx = targetPaneIndex,
                  targetIdx >= 0, targetIdx < existingRatios.count
            else {
                // Fall back to proportional if caller didn't supply a target.
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
        mode: SizingMode
    ) -> [Double] {
        guard removalIndex >= 0, removalIndex < existingRatios.count else {
            return existingRatios
        }
        var updated = existingRatios
        let removed = updated.remove(at: removalIndex)

        switch mode {
        case .halveTarget:
            // Not meaningful on removal — degenerate case, reuse adjacent-absorb
            // which matches the historical Layout.removing behavior.
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

Note: `DropTarget` must have a `.splitZone(paneId:direction:)` case. If the unified-algo plan has not yet shipped that case, stub it in the `DropTarget` enum as part of this task — it's the same codebase either way.

- [ ] **Step 4: Run tests to verify pass**

Run: `mise run test --filter DropSizingPolicyTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DropSizingPolicy.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropSizingPolicyTests.swift
git commit -m "feat: DropSizingPolicy — hybrid default, shift → proportional"
```

### Task C — Wire `DropSizingPolicy` into main-pane insert path

**Files:**
- Modify: wherever `Layout.inserting` is called from drag-drop commit code paths (see grep step below)
- Modify: `Sources/AgentStudio/Core/Models/Layout.swift` — add an `inserting(..., ratios:)` overload that accepts precomputed ratios and skips the halve-target baked-in logic; OR introduce a parallel `Layout.insertedApplyingRatios(_:)` helper

- [ ] **Step 1: Find the commit path**

```bash
grep -rn "Layout.*\.inserting\(" Sources/AgentStudio/ | grep -v Tests | grep -v "//"
```

Expected: 1–3 call sites in drag-commit / command-dispatch code.

- [ ] **Step 2: For each call site, capture modifier state at drop commit**

At the `performDragOperation` / `handleDrop` boundary in the NSView layer:

```swift
let modifiers = NSEvent.modifierFlags
// pass modifiers into the dispatch layer (new field on the command or a
// separate side-channel parameter — don't smuggle through Notification)
```

- [ ] **Step 3: Before calling `Layout.inserting`, compute target ratios**

```swift
let mode = DropSizingPolicy.sizingMode(for: dropTarget, modifiers: modifiers)
let newRatios = DropSizingPolicy.ratiosAfterInsertion(
    existingRatios: currentRow.ratios,
    insertionIndex: insertionIndex,
    targetPaneIndex: targetPaneIdx,
    mode: mode
)
// Apply newRatios to the layout after insertion.
```

- [ ] **Step 4: Update any tests that asserted old halve-only behavior**

Search:
```bash
grep -rn "halved\|splitRatio\|Layout.*inserting" Tests/
```

Each assertion needs review:
- If test drops on pane-zone (default sizing): halve-target still holds
- If test drops on slot-midpoint (new coverage from unified-algo plan): proportional applies

Keep the LayoutFlatStripTests regression (Shared Task A above) as-is — it directly tests `Layout.inserting`, not the drag-drop commit path.

- [ ] **Step 5: Full test suite**

Run: `mise run test && mise run lint`
Expected: PASS. Any drag-drop tests that asserted specific ratios must either keep asserting halve (pane-zone drops) or switch to proportional (slot drops). Explicit per-test audit — do not batch-update.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "refactor: main insert path uses DropSizingPolicy"
```

### Task D — Wire `DropSizingPolicy` into drawer insert / rearrange path

Mirror Task C for drawer paths. Files to hit:
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` drawer mutations
- `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift`

Use the same steps as Task C, with the specific nuance that drawer row-slot drops and drawer newRow drops are all proportional by default (no `.splitZone` target in drawer context).

- [ ] Commit:
  ```bash
  git commit -m "refactor: drawer insert/rearrange uses DropSizingPolicy"
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
- [ ] Shared Task A regression tests are green against current code
- [ ] Task B `DropSizingPolicy` tests green (sizing-mode selection + halve + proportional + removal)
- [ ] Task C main-pane drag-insert tests green with audited per-test expectations (halve on pane-zone, proportional on slot)
- [ ] Task D drawer drag-rearrange tests green (all proportional)
- [ ] Full `mise run test` suite passes
- [ ] `mise run lint` passes (0 violations)
- [ ] Manual verification:
  - 4-pane horizontal split, drop-on-pane-zone of pane index 1: only that pane shrinks 50%, other panes unchanged
  - 4-pane horizontal split, drop-on-slot between panes 1 and 2: all four existing panes scale proportionally to 0.8x, new pane gets 0.2 share
  - 4-pane horizontal split, shift-held drop-on-pane-zone: proportional applies, not halve
  - Drawer n×1, drop onto rowSlot: proportional (since drawer doesn't use splitZone targets)
  - Drawer n×1, drag to top band: `newRow(.top)` created

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

**Shift modifier is command-level, not drag-only:**

`DropSizingMode` enters `PaneActionCommand.insertPane(..., sizingMode:)` at every origin:

| Command origin | Modifier read at | Default without shift |
|---|---|---|
| Drag drop | `performDragOperation` | target-kind-dependent (halve for split, proportional for slot) |
| Keyboard shortcut (⌘D etc.) | Key-event handler | `.halveTarget` |
| Menu item | Menu action handler | `.halveTarget` |
| Plus-button click | Click handler | `.halveTarget` (adjacent to clicked pane) |
| No-active-pane in tab | Command origin | `.proportional` (target = `.paneSlot` at end of row) |

Shift held at any origin → `.proportional`.

**Rearrange is now a concrete task in Task D, not blocked.**

## Rearrangement — test pyramid

Per the test-layer discussion (unit → mock → hidden-window → invariant → fixture), every rearrange combination must be covered:

| Layer | What it tests |
|---|---|
| A (pure unit) | `DropSizingRatioPolicy.ratiosAfterRemoval + ratiosAfterInsertion` composed. All (source-row-state × target-kind × shift) matrix. Property tests: sum-to-1.0 on both rows after any rearrange. Same-row rearrange edge cases (removal-then-insertion order correctness). |
| B (mock `NSDraggingInfo`) | Drive a synthetic rearrange drag against real coordinators with `FakeDraggingInfo`; assert commit produces expected ratios in both source and target rows. |
| C (hidden window) | Real SwiftUI view tree in off-screen NSWindow. Driven rearrange drag; verify end-state layout matches unit-test prediction. |
| D (invariant) | Random-generated rearrange scenarios: assert `|sum_source - 1.0| < ε AND |sum_target - 1.0| < ε AND pane-count conservation`. |
| E (fixture) | Golden-file from captured real-user rearrange drag sessions (captured similarly to pid=69705). Replayed against the resolver + policy. |

Every rearrange edge case — same-row forward, same-row backward, cross-row (drawer n×2 only), onto `.paneSplit`, into `.paneSlot`, with and without shift, source row collapses to empty after remove, target row was empty before insert — must appear in at least Layers A + D. Real-world scenarios additionally go into Layer E.

**No rearrange acceptance without all 5 layers green for the specific combination being shipped.**

## Non-goals

- Geometry resolution (that's the unified-algo plan)
- Drawer row-split ratio changes (`rowSplitRatio` stays as-is)
- Tab-level drawer drop capture structural fix (separate plan)
