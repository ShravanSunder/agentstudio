# Drop sizing policy — Product decision + implementation plan

> **Status: PRODUCT-DECISION PENDING.** This is a product-behavior change. No code can ship until the user signs off on one of the three options below.

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

## Decision matrix

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

## Open questions for user

1. Which option?
2. If Option C: do we want a migration note in release notes ("repeated inserts no longer shrink the target pane geometrically")?
3. If Option D: which drag paths map to "split" (halve-target) vs "slot" (proportional)? Proposed: drag-onto-pane-zone = split; drag-onto-slot-midpoint = slot. Edge corridors = slot.

No code lands until (1) is answered.

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

### Option-specific tasks — chosen after user answers

Filled in after the user picks A, B, C, or D. Until then this section is intentionally empty to prevent forward-planning that assumes an outcome.

---

## Acceptance criteria

- [ ] User has signed off on one of A / B / C / D
- [ ] Shared Task A regression tests are green against current code
- [ ] New `DropSizingPolicy` (if extracted) is fully covered by unit tests
- [ ] Existing `mise run test` suite passes (any tests that assert current behavior are either kept as-is (Option A), updated explicitly (B/C/D) with a commit message calling out the UX change, or deleted if they were over-specifying implementation detail)
- [ ] `mise run lint` passes (0 violations)
- [ ] Manual verification: insert / remove panes in a 4-pane horizontal split; confirm resulting widths match the chosen option

## Non-goals

- Geometry resolution (that's the unified-algo plan)
- Drawer row-split ratio changes (`rowSplitRatio` stays as-is)
- Tab-level drawer drop capture structural fix (separate plan)
