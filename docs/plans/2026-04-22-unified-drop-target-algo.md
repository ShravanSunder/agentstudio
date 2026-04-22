# Unified drop-target resolution algorithm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the drag-target *resolution* algorithm across main panes and drawer panes so both share one core resolver parameterized by config. Eliminates the fork between `PaneDragCoordinator` (main) and `DrawerPaneDragCoordinator` (drawer), keeps visual highlight and resolution in lockstep, and enforces context-specific rules (main = flat strip, drawer n×1 = strip + can-grow, drawer n×2 = two rows).

**Scope boundary (updated 2026-04-22 after adversarial review):** THIS PLAN covers *geometry + target-vocabulary unification only*. It does **not** change insertion/removal sizing behavior — that is a product decision and lives in a sibling plan: `2026-04-22-drop-sizing-policy.md`. Running both plans together was rejected in review because sizing is a product change, geometry is a refactor.

**Architecture:** Introduce a pure, config-parameterized `DropTargetResolver` that consumes a `DropTargetConfig` value and emits a shared `DropTarget` type. Main/drawer keep their own storage actions and target-type translation; the geometric resolution and visual target-rect enumeration live in one place.

**Tech Stack:** Swift 6.2, `Testing` (no XCTest), `swift-format`, mise-orchestrated `mise run build/test/lint`. No new third-party deps. Pure-value algorithm module; all SwiftUI/AppKit plumbing stays in existing overlay NSViews.

---

## Prerequisites — MUST complete before Task 1

These are hard blockers. Any attempt to execute Task 1 without satisfying them is a plan violation.

### Prereq 1 — Tab-level capture structural fix lands and is confirmed

- [ ] `docs/plans/2026-04-22-drawer-drag-tab-level-capture.md` Phase B has been applied on `drawer-improvements`
- [ ] All "Hard" acceptance criteria in that plan are green (build/lint/test/fixture/registration-invariant/manual drag)
- [ ] At least **2 calendar days of dogfooding** on `drawer-improvements` with no new drag routing / coord-math regressions reported
- [ ] The current `DrawerPaneDragCoordinator` and `PaneDragCoordinator` contracts are stable and not in mid-refactor

**Why:** Both plans touch `DrawerPanel`, `DrawerPanelOverlay`, `FlatTabStripContainer`, `DrawerPaneDragCoordinator`, `DrawerDropTargetOverlay`. Running this plan before Phase B is validated loses the signal on whether the structural fix actually solved the bug. Adversarial review (Codex-on-plan, 2026-04-22) called this out explicitly.

### Prereq 2 — Main-pane golden fixture

The riskiest part of this plan is Task 11 (main-pane adapter). Task 11 changes the main resolver from "contained-pane + tie-breaker" to "slot-midpoint" geometry. That is a subtle semantic shift that the existing unit tests do not exercise end-to-end against real user drag traces. Without an empirical replay fixture, regressions will only be caught by dogfooding — too late, too noisy.

- [ ] Capture 3 real main-pane drag sessions on a built app (`AGENTSTUDIO_RESTORE_TRACE=1 .build/debug/AgentStudio`):
  - Session A: 2-pane horizontal split, drag through middle + both edges
  - Session B: 4-pane horizontal split, drag with overlapping midpoint transitions
  - Session C: 1-pane + edge-corridor drag (confirms `edgeCorridorWidth = 24` behavior)
- [ ] Extract the `(location, resolved PaneDropTarget)` pairs into `Tests/AgentStudioTests/Fixtures/MainDrag-<session>.json` (≥ 150 resolutions per session)
- [ ] Add `MainDragFixtureReplayTests.swift` that replays all three against **the current `PaneDragCoordinator`** (pre-refactor) and proves all assertions pass
- [ ] Commit the fixtures + replay test. They become the golden baseline Task 11 must preserve.

**Why:** Codex adversarial review: "A single drawer fixture can easily go green while the main-pane adapter and two-row drawer paths are wrong." Main-pane fixture coverage is not optional.

### Prereq 3 — Two-row drawer fixture

The existing pid=69705 fixture covers drawer n×1. If Task 11 or Task 10 regresses two-row resolution, no empirical test catches it.

- [ ] Capture 1 drag session with drawer in n×2 mode covering top-row, bottom-row, and inter-row boundary transitions
- [ ] Extract to `Tests/AgentStudioTests/Fixtures/DrawerTwoRowDrag.json`
- [ ] Add to `DropTargetResolverFixtureTests.swift` alongside the n×1 pid=69705 replay

### Prereq 4 — Open design questions resolved with user

The four open design questions (§"Open design questions for review cycle" below) must have written answers before Task 1. Specifically:

- Q1 Main-pane corridor anchor: keep pane-ID anchor in adapter layer? **Default answer proposed:** YES (preserves animation hooks; adapter translates at boundary)
- Q2 Contained-target vs slot-midpoint on main: which rule wins? **Default answer proposed:** slot-midpoint everywhere (cleaner, matches drawer), accepting subtle boundary shifts; fixture from Prereq 2 must pass both before and after
- Q4 `DropZone.swift` deletion: defer? **Default answer proposed:** YES, keep `DropZone.left/.right` in `PaneActionCommand.insertPane(direction:)` for persistence stability; translate at adapter boundary only

Q3 (sizing policy) is **not** part of this plan — see scope boundary. Addressed in `2026-04-22-drop-sizing-policy.md`.

---

## Glossary

- **Row** — a horizontal strip of panes. Main has exactly one row. Drawer n×1 has one row. Drawer n×2 has two rows (`.top` + `.bottom`).
- **Slot** — an insertion position between two panes (or at either end) within a row. Indexed 0…N where N = pane count.
- **Split zone** — on main, clicking the left/right half of a specific pane requests insertion immediately before/after that pane. Semantically equivalent to `.slot(…)` — the "split" framing is legacy.
- **New row** — drawer n×1 only. Dragging to the top/bottom band of the drawer panel creates a second row.
- **Config** — static description of which target kinds are legal in a given context + which row IDs exist.

## Design — shared target vocabulary

```swift
/// Stable identifier for a row. Main has exactly one row (`.main`). Drawer
/// has one or two rows depending on its grid layout.
enum RowID: Hashable {
    case main
    case drawerTop
    case drawerBottom
}

/// Unified drop target. Produced by `DropTargetResolver`; consumed by
/// context-specific dispatchers that translate back to `PaneActionCommand`
/// variants.
enum DropTarget: Hashable {
    /// Insert at index in row. Index may be 0…paneCount; endpoint values
    /// represent insertion at the leading/trailing edge of the row.
    case slot(row: RowID, index: Int)

    /// Drawer-n×1 only: grow to n×2 by creating a new row at top or bottom
    /// with the dragged pane as its first member.
    case newRow(position: NewRowPosition)
}

enum NewRowPosition: Hashable {
    case top
    case bottom
}
```

**Config shape:**

```swift
struct DropTargetConfig {
    /// Ordered list of rows available for slot insertion in this context.
    /// Main = [.main]. Drawer n×1 = [.drawerTop]. Drawer n×2 = [.drawerTop, .drawerBottom].
    let rows: [RowID]

    /// If non-nil, the resolver will produce `.newRow(...)` targets when
    /// the cursor is inside the edge band of `containerBounds`. Drawer n×1
    /// provides this; main and drawer n×2 do not.
    let newRowBand: NewRowBandConfig?

    /// Width of the edge corridor that maps to slot-0 / slot-N even when
    /// the cursor is outside the leftmost/rightmost pane horizontally.
    /// Main uses 24pt; drawer currently 0 (no corridor). Configurable so
    /// behavior stays consistent if we unify on one number.
    let edgeCorridorWidth: CGFloat
}

struct NewRowBandConfig {
    /// Height of the top/bottom bands inside `containerBounds` that resolve
    /// to `.newRow(.top)` / `.newRow(.bottom)`.
    let bandHeight: CGFloat
}
```

**Resolver contract:**

```swift
struct DropTargetResolver {
    static func resolve(
        location: CGPoint,
        rows: [RowID: [UUID]],         // ordered pane IDs per row
        paneFrames: [UUID: CGRect],    // pane frames in container-local space
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> DropTarget?

    static func targetRects(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> [DropTarget: CGRect]

    static func resolveLatched(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        currentTarget: DropTarget?,
        shouldAccept: (DropTarget) -> Bool
    ) -> DropTarget?
}
```

## Sizing policy — shared

Currently drawer and main diverge on how space is allocated when a pane is inserted. Pull both into `DropSizingPolicy`:

```swift
struct DropSizingPolicy {
    /// Given the row currently containing `existingPaneIds` (with current
    /// ratios) and a new pane being inserted at `insertionIndex`, return
    /// the new ratios for the row after insertion.
    ///
    /// Current main rule: equal redistribution among all N+1 panes.
    /// Current drawer rule: equal redistribution.
    /// We standardize on: preserve existing ratios proportionally, carve
    /// out `1/(N+1)` for the new pane. This makes movement feel
    /// lightweight — existing panes keep relative proportions.
    static func ratiosAfterInsertion(
        existingRatios: [Double],
        insertionIndex: Int
    ) -> [Double]

    /// When a pane is removed from a row, redistribute its share among
    /// remaining panes proportionally (not equally). Keeps relative sizes.
    static func ratiosAfterRemoval(
        existingRatios: [Double],
        removalIndex: Int
    ) -> [Double]

    /// Row-split ratio for drawer n×2: what fraction of panel height the
    /// top row gets. Default 0.5; tracked per-drawer (already persisted in
    /// DrawerGridLayout.rowSplitRatio).
    static let defaultRowSplitRatio: Double = 0.5
}
```

## File Structure

### New files

- `Sources/AgentStudio/Core/Models/DropTarget.swift` — `DropTarget`, `RowID`, `NewRowPosition` value types
- `Sources/AgentStudio/Core/Models/DropTargetConfig.swift` — `DropTargetConfig`, `NewRowBandConfig` + static factories (`.main`, `.drawerSingleRow`, `.drawerTwoRow`)
- `Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift` — pure resolver (extracted from `PaneDragCoordinator` + `DrawerPaneDragCoordinator`)
- `Sources/AgentStudio/Core/Views/Splits/DropSizingPolicy.swift` — shared sizing rules
- `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift` — unit tests (core geometry) including golden fixtures derived from pid=69705's 512 resolutions
- `Tests/AgentStudioTests/Core/Views/Splits/DropSizingPolicyTests.swift` — sizing invariant tests
- `Tests/AgentStudioTests/Core/Models/DropTargetConfigTests.swift` — factory/config invariant tests

### Modified files

- `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift` — thin adapter: translates `PaneDropTarget(paneId, zone)` ↔ `DropTarget.slot(row: .main, index)` using main pane order; delegates geometry to `DropTargetResolver`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift` — thin adapter: translates `DrawerRearrangeTarget` ↔ `DropTarget` using drawer row structure; delegates geometry to `DropTargetResolver`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift` — renders highlight from the unified `targetRects` output, no separate rect calc
- `Sources/AgentStudio/Core/Views/Splits/PaneDropTargetOverlay.swift` — same: renders from unified `targetRects`
- `Sources/AgentStudio/Core/Views/Splits/DropZone.swift` — (eventually) deleted; `.left`/`.right` zone becomes a slot-index adapter. Defer deletion until all call sites migrated (last task).
- Callers: `SplitContainerDropCaptureOverlay.swift`, `DrawerSplitContainerDropCaptureOverlay.swift`, `PaneTabViewController.swift` insertion paths, `WorkspacePaneAtom.swift` insertion paths

### Non-goals for this plan

- Does NOT change persistence shape (`DrawerGridLayout` stays; `Layout` stays). Migration is a separate concern already handled (see `Drawer.init(from:)`).
- Does NOT refactor `SplitContainerDropCaptureOverlay` / `DrawerSplitContainerDropCaptureOverlay` NSView plumbing. Those NSViews stay, they just call a unified resolver underneath.
- Does NOT introduce top/bottom split zones on main panes. User explicitly ruled these out; config enforces.
- Does NOT wire into Phase B of `2026-04-22-drawer-drag-tab-level-capture.md`. This plan is orthogonal — the structural fix there can land first or after.

---

## Open design questions for review cycle

These require user + adversarial review before Task 1 is touched:

1. **Exact main-pane corridor semantics.** Current `PaneDragCoordinator` has `edgeCorridorWidth = 24`. When the cursor is in the left corridor, target is `PaneDropTarget(paneId: leftmost, zone: .left)`. Under the unified model this becomes `.slot(row: .main, index: 0)`. **Question:** Do we keep the pane-ID anchor (for animation) or drop it since `.slot` is pane-agnostic? Proposed: keep `edgeCorridorWidth` config but the adapter layer reattaches `paneId` at translation time.
2. **"Contained target" vs "slot target"** on main. Main currently picks a contained pane first, then zone within. Drawer uses slot midpoints directly. Under unification, we need one rule. Proposed: slot midpoints everywhere (cleaner, fewer tiebreakers). Tradeoff: main behavior shifts subtly near pane boundaries — need golden tests to catch regressions.
3. **Sizing: equal vs proportional insertion.** Main currently equalizes; drawer also equalizes. Proposed policy is proportional preservation (new pane gets `1/(N+1)`, existing panes keep relative ratios). This is a **behavior change** user should sign off on before implementation. Alternative: keep equalization rule, just share code. User-preference decision.
4. **`DropZone.swift` deletion.** Currently `.left`/`.right` are still referenced in `PaneActionCommand.insertPane` direction. Do we collapse the direction into slot-index at the action layer too, or keep the direction enum and translate at the boundary? Proposed: keep direction in `PaneActionCommand` (stable command schema, persistence-adjacent); translate only at resolver/overlay boundary.

---

## Task 1: Introduce `DropTarget` + `RowID` value types

**Files:**
- Create: `Sources/AgentStudio/Core/Models/DropTarget.swift`
- Test: `Tests/AgentStudioTests/Core/Models/DropTargetTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropTargetTests {
    @Test
    func rowID_mainIsNotDrawer() {
        #expect(RowID.main != .drawerTop)
        #expect(RowID.main != .drawerBottom)
    }

    @Test
    func dropTarget_slotEquality() {
        let a: DropTarget = .slot(row: .main, index: 0)
        let b: DropTarget = .slot(row: .main, index: 0)
        #expect(a == b)
    }

    @Test
    func dropTarget_newRowPositions() {
        #expect(DropTarget.newRow(position: .top) != .newRow(position: .bottom))
    }

    @Test
    func dropTarget_hashable_inSet() {
        let set: Set<DropTarget> = [
            .slot(row: .main, index: 0),
            .slot(row: .main, index: 0),
            .slot(row: .drawerTop, index: 1),
        ]
        #expect(set.count == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test --filter DropTargetTests`
Expected: FAIL — `DropTarget` and `RowID` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AgentStudio/Core/Models/DropTarget.swift
import Foundation

enum RowID: Hashable, Sendable {
    case main
    case drawerTop
    case drawerBottom
}

enum NewRowPosition: Hashable, Sendable {
    case top
    case bottom
}

enum DropTarget: Hashable, Sendable {
    case slot(row: RowID, index: Int)
    case newRow(position: NewRowPosition)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test --filter DropTargetTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/DropTarget.swift \
        Tests/AgentStudioTests/Core/Models/DropTargetTests.swift
git commit -m "feat: introduce unified DropTarget value type"
```

---

## Task 2: Introduce `DropTargetConfig` with three factory configs

**Files:**
- Create: `Sources/AgentStudio/Core/Models/DropTargetConfig.swift`
- Test: `Tests/AgentStudioTests/Core/Models/DropTargetConfigTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropTargetConfigTests {
    @Test
    func mainConfig_hasSingleMainRowAndNoNewRowBand() {
        let config = DropTargetConfig.main
        #expect(config.rows == [.main])
        #expect(config.newRowBand == nil)
        #expect(config.edgeCorridorWidth == 24)
    }

    @Test
    func drawerSingleRowConfig_hasDrawerTopAndNewRowBand() {
        let config = DropTargetConfig.drawerSingleRow
        #expect(config.rows == [.drawerTop])
        #expect(config.newRowBand?.bandHeight == 28)
        #expect(config.edgeCorridorWidth == 0)
    }

    @Test
    func drawerTwoRowConfig_hasBothRowsAndNoNewRowBand() {
        let config = DropTargetConfig.drawerTwoRow
        #expect(config.rows == [.drawerTop, .drawerBottom])
        #expect(config.newRowBand == nil)
        #expect(config.edgeCorridorWidth == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test --filter DropTargetConfigTests`
Expected: FAIL — `DropTargetConfig` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AgentStudio/Core/Models/DropTargetConfig.swift
import CoreGraphics
import Foundation

struct NewRowBandConfig: Hashable, Sendable {
    let bandHeight: CGFloat
}

struct DropTargetConfig: Hashable, Sendable {
    let rows: [RowID]
    let newRowBand: NewRowBandConfig?
    let edgeCorridorWidth: CGFloat

    static let main = DropTargetConfig(
        rows: [.main],
        newRowBand: nil,
        edgeCorridorWidth: 24
    )

    static let drawerSingleRow = DropTargetConfig(
        rows: [.drawerTop],
        newRowBand: NewRowBandConfig(bandHeight: 28),
        edgeCorridorWidth: 0
    )

    static let drawerTwoRow = DropTargetConfig(
        rows: [.drawerTop, .drawerBottom],
        newRowBand: nil,
        edgeCorridorWidth: 0
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test --filter DropTargetConfigTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/DropTargetConfig.swift \
        Tests/AgentStudioTests/Core/Models/DropTargetConfigTests.swift
git commit -m "feat: add DropTargetConfig with main/drawer factories"
```

---

## Task 3: Resolver — row-slot resolution (no new-row, no edge corridor yet)

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropTargetResolverTests {
    private let paneA = UUID()
    private let paneB = UUID()
    private let paneC = UUID()

    // Three panes in a row, each 100pt wide, container 300×200
    private var threePaneSingleRow: (rows: [RowID: [UUID]], frames: [UUID: CGRect], bounds: CGRect) {
        (
            rows: [.main: [paneA, paneB, paneC]],
            frames: [
                paneA: CGRect(x: 0, y: 0, width: 100, height: 200),
                paneB: CGRect(x: 100, y: 0, width: 100, height: 200),
                paneC: CGRect(x: 200, y: 0, width: 100, height: 200),
            ],
            bounds: CGRect(x: 0, y: 0, width: 300, height: 200)
        )
    }

    @Test
    func resolve_leftHalfOfFirstPane_returnsSlotZero() {
        let ctx = threePaneSingleRow
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main
        )
        #expect(target == .slot(row: .main, index: 0))
    }

    @Test
    func resolve_rightHalfOfFirstPane_returnsSlotOne() {
        let ctx = threePaneSingleRow
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 75, y: 100),
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main
        )
        #expect(target == .slot(row: .main, index: 1))
    }

    @Test
    func resolve_rightHalfOfLastPane_returnsTrailingSlot() {
        let ctx = threePaneSingleRow
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 275, y: 100),
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main
        )
        #expect(target == .slot(row: .main, index: 3))
    }

    @Test
    func resolve_outsideVertically_returnsNil() {
        let ctx = threePaneSingleRow
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 150, y: 500),
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main
        )
        #expect(target == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test --filter DropTargetResolverTests`
Expected: FAIL — `DropTargetResolver` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift
import CoreGraphics
import Foundation

enum DropTargetResolver {
    static func resolve(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> DropTarget? {
        for rowID in config.rows {
            guard let paneIds = rows[rowID], !paneIds.isEmpty else { continue }
            if let slot = resolveRowSlot(
                location: location,
                rowID: rowID,
                paneIds: paneIds,
                paneFrames: paneFrames
            ) {
                return slot
            }
        }
        return nil
    }

    private static func resolveRowSlot(
        location: CGPoint,
        rowID: RowID,
        paneIds: [UUID],
        paneFrames: [UUID: CGRect]
    ) -> DropTarget? {
        let sortedFrames = paneIds.compactMap { paneFrames[$0] }.sorted { $0.minX < $1.minX }
        guard !sortedFrames.isEmpty else { return nil }

        let rowMinY = sortedFrames.map(\.minY).min() ?? 0
        let rowMaxY = sortedFrames.map(\.maxY).max() ?? 0
        guard location.y >= rowMinY, location.y <= rowMaxY else { return nil }

        if location.x <= sortedFrames[0].midX {
            return .slot(row: rowID, index: 0)
        }
        for index in 1..<sortedFrames.count {
            if location.x > sortedFrames[index - 1].midX,
                location.x <= sortedFrames[index].midX
            {
                return .slot(row: rowID, index: index)
            }
        }
        return .slot(row: rowID, index: sortedFrames.count)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift
git commit -m "feat: add DropTargetResolver row-slot resolution"
```

---

## Task 4: Resolver — new-row bands for drawer single-row config

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift`

- [ ] **Step 1: Write the failing test (append to existing suite)**

```swift
@Test
func resolve_cursorInTopBand_drawerSingleRow_returnsNewRowTop() {
    let ctx = threePaneSingleRow  // reuse 300×200 setup
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 150, y: 14),  // inside 28pt top band
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow
    )
    #expect(target == .newRow(position: .top))
}

@Test
func resolve_cursorInBottomBand_drawerSingleRow_returnsNewRowBottom() {
    let ctx = threePaneSingleRow
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 150, y: 190),  // 200 - 28 = 172; 190 is in band
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow
    )
    #expect(target == .newRow(position: .bottom))
}

@Test
func resolve_cursorInMiddle_drawerSingleRow_returnsSlot() {
    let ctx = threePaneSingleRow
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 150, y: 100),  // middle — not in any band
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow
    )
    #expect(target == .slot(row: .drawerTop, index: 2))
}

@Test
func resolve_bandIgnored_whenConfigLacksNewRowBand() {
    let ctx = threePaneSingleRow
    // config .drawerTwoRow has no newRowBand → bands should be ignored,
    // cursor falls through to slot resolution.
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 150, y: 14),
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerTwoRow
    )
    #expect(target == .slot(row: .drawerTop, index: 2))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test --filter DropTargetResolverTests`
Expected: 4 new tests FAIL — resolver doesn't emit `.newRow` yet.

- [ ] **Step 3: Extend resolver**

```swift
// Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift
// Insert at top of DropTargetResolver.resolve, before the for-rowID loop:

if let band = config.newRowBand {
    let topBand = CGRect(
        x: containerBounds.minX,
        y: containerBounds.minY,
        width: containerBounds.width,
        height: band.bandHeight
    )
    if topBand.contains(location) {
        return .newRow(position: .top)
    }

    let bottomBand = CGRect(
        x: containerBounds.minX,
        y: containerBounds.maxY - band.bandHeight,
        width: containerBounds.width,
        height: band.bandHeight
    )
    if bottomBand.contains(location) {
        return .newRow(position: .bottom)
    }
}
```

- [ ] **Step 4: Run test to verify all pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 8 tests total.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift
git commit -m "feat: resolver emits .newRow targets for drawer single-row band"
```

---

## Task 5: Resolver — two-row resolution with row priority

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift`

Note: Task 3 already loops over `config.rows` in order — this task just adds tests proving two-row behavior. No new implementation unless tests fail.

- [ ] **Step 1: Write the failing test**

```swift
@Test
func resolve_twoRowDrawer_cursorInTopRow_returnsTopSlot() {
    let paneD = UUID()
    let frames: [UUID: CGRect] = [
        paneA: CGRect(x: 0, y: 0, width: 150, height: 100),       // top row
        paneB: CGRect(x: 150, y: 0, width: 150, height: 100),     // top row
        paneC: CGRect(x: 0, y: 100, width: 150, height: 100),     // bottom row
        paneD: CGRect(x: 150, y: 100, width: 150, height: 100),   // bottom row
    ]
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 75, y: 50),  // top row, left of paneA midX
        rows: [.drawerTop: [paneA, paneB], .drawerBottom: [paneC, paneD]],
        paneFrames: frames,
        containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
        config: .drawerTwoRow
    )
    #expect(target == .slot(row: .drawerTop, index: 0))
}

@Test
func resolve_twoRowDrawer_cursorInBottomRow_returnsBottomSlot() {
    let paneD = UUID()
    let frames: [UUID: CGRect] = [
        paneA: CGRect(x: 0, y: 0, width: 150, height: 100),
        paneB: CGRect(x: 150, y: 0, width: 150, height: 100),
        paneC: CGRect(x: 0, y: 100, width: 150, height: 100),
        paneD: CGRect(x: 150, y: 100, width: 150, height: 100),
    ]
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 225, y: 150),  // bottom row, right half of paneD
        rows: [.drawerTop: [paneA, paneB], .drawerBottom: [paneC, paneD]],
        paneFrames: frames,
        containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
        config: .drawerTwoRow
    )
    #expect(target == .slot(row: .drawerBottom, index: 2))
}
```

- [ ] **Step 2: Run test to verify pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — Task 3's row loop already handles two rows; these confirm.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift
git commit -m "test: verify resolver two-row behavior"
```

---

## Task 6: Resolver — edge corridor for main config

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func resolve_leftCorridor_main_returnsSlotZero() {
    let ctx = threePaneSingleRow
    // Container 300 wide, panes start at x=0. Cursor at x=-10 is OUTSIDE
    // pane frames but INSIDE container (containerBounds starts at x=-10?).
    // Easier setup: expand container so corridor exists INSIDE bounds but
    // OUTSIDE pane frames.
    let corridorBounds = CGRect(x: -24, y: 0, width: 324, height: 200)
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: -12, y: 100),
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: corridorBounds,
        config: .main
    )
    #expect(target == .slot(row: .main, index: 0))
}

@Test
func resolve_rightCorridor_main_returnsTrailingSlot() {
    let ctx = threePaneSingleRow
    let corridorBounds = CGRect(x: 0, y: 0, width: 324, height: 200)
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 310, y: 100),
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: corridorBounds,
        config: .main
    )
    #expect(target == .slot(row: .main, index: 3))
}

@Test
func resolve_corridorIgnored_whenConfigCorridorIsZero() {
    let ctx = threePaneSingleRow
    let corridorBounds = CGRect(x: -24, y: 0, width: 324, height: 200)
    // drawerSingleRow has edgeCorridorWidth = 0 — no corridor honored.
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: -12, y: 100),
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: corridorBounds,
        config: .drawerSingleRow
    )
    #expect(target == nil)  // outside pane rows, no corridor applies
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test --filter DropTargetResolverTests`
Expected: 3 new tests FAIL — resolver doesn't emit corridor targets yet.

- [ ] **Step 3: Extend resolver**

```swift
// Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift
// After the for-rowID slot loop in `resolve`, before returning nil,
// add corridor handling:

if config.edgeCorridorWidth > 0 {
    for rowID in config.rows {
        guard let paneIds = rows[rowID], !paneIds.isEmpty else { continue }
        let sortedFrames = paneIds.compactMap { paneFrames[$0] }.sorted { $0.minX < $1.minX }
        guard let first = sortedFrames.first, let last = sortedFrames.last else { continue }

        let rowMinY = sortedFrames.map(\.minY).min() ?? 0
        let rowMaxY = sortedFrames.map(\.maxY).max() ?? 0
        guard location.y >= rowMinY, location.y <= rowMaxY else { continue }

        let leftCorridor = CGRect(
            x: max(containerBounds.minX, first.minX - config.edgeCorridorWidth),
            y: rowMinY,
            width: min(config.edgeCorridorWidth, first.minX - containerBounds.minX),
            height: rowMaxY - rowMinY
        )
        if leftCorridor.contains(location) {
            return .slot(row: rowID, index: 0)
        }

        let rightCorridor = CGRect(
            x: last.maxX,
            y: rowMinY,
            width: min(config.edgeCorridorWidth, containerBounds.maxX - last.maxX),
            height: rowMaxY - rowMinY
        )
        if rightCorridor.contains(location) {
            return .slot(row: rowID, index: sortedFrames.count)
        }
    }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 13 tests total.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift
git commit -m "feat: resolver emits edge-corridor slot targets for main"
```

---

## Task 7: Resolver — `targetRects` for visual overlay

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func targetRects_singleRow_emitsSlotAndNewRowRects() {
    let ctx = threePaneSingleRow
    let rects = DropTargetResolver.targetRects(
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow
    )

    // 4 slots + 2 new-row bands
    #expect(rects.count == 6)
    #expect(rects[.newRow(position: .top)] != nil)
    #expect(rects[.newRow(position: .bottom)] != nil)
    #expect(rects[.slot(row: .drawerTop, index: 0)] != nil)
    #expect(rects[.slot(row: .drawerTop, index: 3)] != nil)
}

@Test
func targetRects_main_emitsOnlySlotRects() {
    let ctx = threePaneSingleRow
    let rects = DropTargetResolver.targetRects(
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .main
    )
    // 4 slots, no newRow, no corridor rect (corridor is part of resolve, not enumerated rects — design choice, confirm in review)
    #expect(rects.count == 4)
    #expect(rects[.newRow(position: .top)] == nil)
}
```

- [ ] **Step 2: Run test to verify fail**

Run: `mise run test --filter DropTargetResolverTests`
Expected: FAIL — `targetRects` not defined.

- [ ] **Step 3: Add `targetRects`**

```swift
// Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift
extension DropTargetResolver {
    static func targetRects(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> [DropTarget: CGRect] {
        var rects: [DropTarget: CGRect] = [:]

        if let band = config.newRowBand {
            rects[.newRow(position: .top)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.minY,
                width: containerBounds.width,
                height: band.bandHeight
            )
            rects[.newRow(position: .bottom)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.maxY - band.bandHeight,
                width: containerBounds.width,
                height: band.bandHeight
            )
        }

        for rowID in config.rows {
            guard let paneIds = rows[rowID], !paneIds.isEmpty else { continue }
            let sorted = paneIds.compactMap { paneFrames[$0] }.sorted { $0.minX < $1.minX }
            guard let first = sorted.first, let last = sorted.last else { continue }

            let rowMinY = sorted.map(\.minY).min() ?? 0
            let rowMaxY = sorted.map(\.maxY).max() ?? 0

            var boundaries: [CGFloat] = [first.minX, first.midX]
            if sorted.count > 1 {
                for i in 1..<(sorted.count - 1) { boundaries.append(sorted[i].midX) }
                boundaries.append(last.midX)
            }
            boundaries.append(last.maxX)

            for insertionIndex in 0...sorted.count {
                let minX = boundaries[insertionIndex]
                let maxX = boundaries[insertionIndex + 1]
                rects[.slot(row: rowID, index: insertionIndex)] = CGRect(
                    x: minX,
                    y: rowMinY,
                    width: max(maxX - minX, 1),
                    height: rowMaxY - rowMinY
                )
            }
        }

        return rects
    }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 15 tests total.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift
git commit -m "feat: resolver emits targetRects for visual overlay parity"
```

---

## Task 8: Resolver — `resolveLatched` wrapper for NSView callbacks

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func resolveLatched_acceptsResolvedTarget() {
    let ctx = threePaneSingleRow
    let target = DropTargetResolver.resolveLatched(
        location: CGPoint(x: 75, y: 100),
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .main,
        currentTarget: nil,
        shouldAccept: { _ in true }
    )
    #expect(target == .slot(row: .main, index: 1))
}

@Test
func resolveLatched_falseAcceptor_keepsCurrent() {
    let ctx = threePaneSingleRow
    let current: DropTarget = .slot(row: .main, index: 2)
    let target = DropTargetResolver.resolveLatched(
        location: CGPoint(x: 75, y: 100),
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .main,
        currentTarget: current,
        shouldAccept: { $0 == current }  // only accept the latched one
    )
    #expect(target == current)
}

@Test
func resolveLatched_falseAcceptor_noCurrent_returnsNil() {
    let ctx = threePaneSingleRow
    let target = DropTargetResolver.resolveLatched(
        location: CGPoint(x: 75, y: 100),
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .main,
        currentTarget: nil,
        shouldAccept: { _ in false }
    )
    #expect(target == nil)
}
```

- [ ] **Step 2: Run test to verify fail**

Run: `mise run test --filter DropTargetResolverTests`
Expected: FAIL — `resolveLatched` not defined.

- [ ] **Step 3: Add `resolveLatched`**

```swift
// Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift
extension DropTargetResolver {
    static func resolveLatched(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        currentTarget: DropTarget?,
        shouldAccept: (DropTarget) -> Bool
    ) -> DropTarget? {
        if let resolved = resolve(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config
        ), shouldAccept(resolved) {
            return resolved
        }
        if let currentTarget, shouldAccept(currentTarget) {
            return currentTarget
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 18 tests total.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverTests.swift
git commit -m "feat: add DropTargetResolver.resolveLatched for NSView callbacks"
```

---

## Task 9: Golden-file fixture test from pid=69705

**Files:**
- Create: `Tests/AgentStudioTests/Fixtures/DrawerDropTargetFixture-pid69705.json`
- Create: `Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverFixtureTests.swift`

- [ ] **Step 1: Build the fixture**

Extract the 512 resolutions from `/tmp/agentstudio_debug.log` (pid=69705 session) and convert to a JSON fixture. Expected shape:

```json
{
  "pid": 69705,
  "containerBounds": {"x": 0, "y": 0, "width": 2800, "height": 800},
  "rows": {
    "drawerTop": ["<uuid-a>", "<uuid-b>", "<uuid-c>"],
    "drawerBottom": null
  },
  "paneFrames": {
    "<uuid-a>": {"x": 0, "y": 0, "width": 900, "height": 800},
    "<uuid-b>": {"x": 900, "y": 0, "width": 900, "height": 800},
    "<uuid-c>": {"x": 1800, "y": 0, "width": 1000, "height": 800}
  },
  "resolutions": [
    {"location": {"x": 1158.86, "y": 461.58}, "expectedTarget": {"kind": "slot", "row": "drawerTop", "index": 1}},
    ...
  ]
}
```

Script to build fixture (one-off — keep in `Scripts/build-drop-target-fixture.swift` or similar):

```bash
# Filter log for pid=69705 DrawerSplit.routeDragUpdate lines with targets
grep "pid=69705" /tmp/agentstudio_debug.log \
  | grep "DrawerSplit.routeDragUpdate converted=" \
  | awk -F'converted=|target=' '{print $2, $3}' \
  > /tmp/resolutions.raw
# ... further processing into JSON
```

Note: exact scripting is a separate micro-task; the point is the fixture file exists in `Tests/AgentStudioTests/Fixtures/`.

- [ ] **Step 2: Write the fixture-replay test**

```swift
// Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverFixtureTests.swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropTargetResolverFixtureTests {
    struct Fixture: Decodable {
        struct Rect: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
        struct Rows: Decodable { let drawerTop: [UUID]?; let drawerBottom: [UUID]? }
        struct Resolution: Decodable {
            struct Point: Decodable { let x: Double; let y: Double }
            struct ExpectedTarget: Decodable { let kind: String; let row: String?; let index: Int?; let position: String? }
            let location: Point
            let expectedTarget: ExpectedTarget
        }
        let containerBounds: Rect
        let rows: Rows
        let paneFrames: [String: Rect]
        let resolutions: [Resolution]
    }

    @Test
    func replaysPid69705_allResolutionsMatch() throws {
        let url = Bundle.module.url(forResource: "DrawerDropTargetFixture-pid69705", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)

        let bounds = CGRect(
            x: fixture.containerBounds.x, y: fixture.containerBounds.y,
            width: fixture.containerBounds.width, height: fixture.containerBounds.height
        )
        let frames: [UUID: CGRect] = fixture.paneFrames.reduce(into: [:]) { acc, pair in
            guard let uuid = UUID(uuidString: pair.key) else { return }
            acc[uuid] = CGRect(x: pair.value.x, y: pair.value.y, width: pair.value.width, height: pair.value.height)
        }
        var rows: [RowID: [UUID]] = [:]
        if let top = fixture.rows.drawerTop { rows[.drawerTop] = top }
        if let bottom = fixture.rows.drawerBottom { rows[.drawerBottom] = bottom }
        let config: DropTargetConfig = fixture.rows.drawerBottom == nil ? .drawerSingleRow : .drawerTwoRow

        for resolution in fixture.resolutions {
            let expected: DropTarget? = {
                switch resolution.expectedTarget.kind {
                case "slot":
                    guard let row = resolution.expectedTarget.row, let idx = resolution.expectedTarget.index else { return nil }
                    let rowID: RowID = row == "drawerTop" ? .drawerTop : .drawerBottom
                    return .slot(row: rowID, index: idx)
                case "newRow":
                    let pos: NewRowPosition = resolution.expectedTarget.position == "top" ? .top : .bottom
                    return .newRow(position: pos)
                default:
                    return nil
                }
            }()
            let actual = DropTargetResolver.resolve(
                location: CGPoint(x: resolution.location.x, y: resolution.location.y),
                rows: rows,
                paneFrames: frames,
                containerBounds: bounds,
                config: config
            )
            #expect(actual == expected, "at \(resolution.location) expected \(String(describing: expected)) got \(String(describing: actual))")
        }
    }
}
```

- [ ] **Step 3: Run and verify**

Run: `mise run test --filter DropTargetResolverFixtureTests`
Expected: PASS — all 512 resolutions replay.

**If this fails:** the resolver implementation has drifted from the drawer-target-debugging observation. Inspect failing cases, correct the resolver or the fixture (understand which is wrong before editing).

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentStudioTests/Fixtures/DrawerDropTargetFixture-pid69705.json \
        Tests/AgentStudioTests/Core/Views/Splits/DropTargetResolverFixtureTests.swift
git commit -m "test: golden fixture — pid=69705 drawer resolutions replay"
```

---

## Task 10: Migrate `DrawerPaneDragCoordinator` to adapter

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
- Add regression test: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorTests.swift` (if missing equivalent coverage)

- [ ] **Step 1: Verify existing drawer tests still capture the behavior**

Run: `mise run test --filter DrawerPaneDragCoordinator`
Expected: existing tests describe the current API (`resolveTarget`, `targetRects`, `resolveLatchedTarget`). Note any gaps.

- [ ] **Step 2: Replace `DrawerPaneDragCoordinator` internals with adapter**

```swift
import CoreGraphics
import Foundation

struct DrawerPaneDragCoordinator {
    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> DrawerRearrangeTarget? {
        let rows = rowsDictionary(from: layout)
        let config: DropTargetConfig = layout.bottomRow == nil ? .drawerSingleRow : .drawerTwoRow
        guard let target = DropTargetResolver.resolve(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config
        ) else { return nil }
        return translate(target)
    }

    static func targetRects(
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> [DrawerRearrangeTarget: CGRect] {
        let rows = rowsDictionary(from: layout)
        let config: DropTargetConfig = layout.bottomRow == nil ? .drawerSingleRow : .drawerTwoRow
        let rects = DropTargetResolver.targetRects(
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config
        )
        var translated: [DrawerRearrangeTarget: CGRect] = [:]
        for (target, rect) in rects {
            translated[translate(target)] = rect
        }
        return translated
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect,
        currentTarget: DrawerRearrangeTarget?,
        shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
    ) -> DrawerRearrangeTarget? {
        let rows = rowsDictionary(from: layout)
        let config: DropTargetConfig = layout.bottomRow == nil ? .drawerSingleRow : .drawerTwoRow
        let current = currentTarget.map(translate)
        guard let target = DropTargetResolver.resolveLatched(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config,
            currentTarget: current,
            shouldAccept: { shouldAcceptDrop(translate($0)) }
        ) else { return nil }
        return translate(target)
    }

    // MARK: - Translation

    private static func rowsDictionary(from layout: DrawerGridLayout) -> [RowID: [UUID]] {
        var rows: [RowID: [UUID]] = [.drawerTop: layout.topRow.paneIds]
        if let bottom = layout.bottomRow {
            rows[.drawerBottom] = bottom.paneIds
        }
        return rows
    }

    private static func translate(_ target: DropTarget) -> DrawerRearrangeTarget {
        switch target {
        case .slot(let row, let index):
            let placement: DrawerRowPlacement = row == .drawerTop ? .top : .bottom
            return .rowSlot(row: placement, insertionIndex: index)
        case .newRow(let position):
            let placement: DrawerRowPlacement = position == .top ? .top : .bottom
            return .createSecondRow(position: placement)
        }
    }

    private static func translate(_ target: DrawerRearrangeTarget) -> DropTarget {
        switch target {
        case .rowSlot(let row, let insertionIndex):
            let rowID: RowID = row == .top ? .drawerTop : .drawerBottom
            return .slot(row: rowID, index: insertionIndex)
        case .createSecondRow(let position):
            let pos: NewRowPosition = position == .top ? .top : .bottom
            return .newRow(position: pos)
        }
    }
}
```

- [ ] **Step 3: Run full test suite**

Run: `mise run test`
Expected: PASS — all existing drawer tests green, fixture test green.

**If drawer tests fail:** the translation layer is wrong. Do not modify resolver; fix adapter only.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift
git commit -m "refactor: DrawerPaneDragCoordinator adapts to shared DropTargetResolver"
```

---

## Task 11: Migrate `PaneDragCoordinator` to adapter

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift`

- [ ] **Step 1: Replace internals with adapter**

```swift
struct PaneDragCoordinator {
    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect? = nil
    ) -> PaneDropTarget? {
        let rows: [RowID: [UUID]] = [.main: paneFrames.keys.sorted(by: { paneFrames[$0]!.minX < paneFrames[$1]!.minX })]
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        guard let target = DropTargetResolver.resolve(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: effectiveBounds,
            config: .main
        ), case .slot(_, let index) = target else {
            return nil
        }
        return translate(slotIndex: index, in: rows[.main] ?? [], frames: paneFrames)
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect? = nil,
        currentTarget: PaneDropTarget?,
        shouldAcceptDrop: (UUID, DropZone) -> Bool
    ) -> PaneDropTarget? {
        // Translate current PaneDropTarget -> DropTarget for latched lookup, then back.
        let sortedRowIds = paneFrames.keys.sorted(by: { paneFrames[$0]!.minX < paneFrames[$1]!.minX })
        let rows: [RowID: [UUID]] = [.main: sortedRowIds]
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let currentDrop: DropTarget? = currentTarget.flatMap { toDropTarget($0, sortedIds: sortedRowIds) }

        guard let target = DropTargetResolver.resolveLatched(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: effectiveBounds,
            config: .main,
            currentTarget: currentDrop,
            shouldAccept: { candidate in
                guard let mapped = fromDropTarget(candidate, sortedIds: sortedRowIds, frames: paneFrames) else { return false }
                return shouldAcceptDrop(mapped.paneId, mapped.zone)
            }
        ), case .slot(_, let index) = target else {
            return nil
        }
        return translate(slotIndex: index, in: sortedRowIds, frames: paneFrames)
    }

    private static func derivedBounds(from frames: [UUID: CGRect]) -> CGRect {
        let minX = frames.values.map(\.minX).min() ?? 0
        let maxX = frames.values.map(\.maxX).max() ?? 0
        let minY = frames.values.map(\.minY).min() ?? 0
        let maxY = frames.values.map(\.maxY).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func translate(slotIndex: Int, in sortedIds: [UUID], frames: [UUID: CGRect]) -> PaneDropTarget? {
        guard !sortedIds.isEmpty else { return nil }
        if slotIndex == 0 { return PaneDropTarget(paneId: sortedIds[0], zone: .left) }
        if slotIndex >= sortedIds.count { return PaneDropTarget(paneId: sortedIds.last!, zone: .right) }
        // Interior slot — anchor to pane just before the slot, zone .right.
        return PaneDropTarget(paneId: sortedIds[slotIndex - 1], zone: .right)
    }

    private static func toDropTarget(_ pt: PaneDropTarget, sortedIds: [UUID]) -> DropTarget? {
        guard let idx = sortedIds.firstIndex(of: pt.paneId) else { return nil }
        switch pt.zone {
        case .left:  return .slot(row: .main, index: idx)
        case .right: return .slot(row: .main, index: idx + 1)
        }
    }

    private static func fromDropTarget(_ dt: DropTarget, sortedIds: [UUID], frames: [UUID: CGRect]) -> PaneDropTarget? {
        guard case .slot(_, let idx) = dt else { return nil }
        return translate(slotIndex: idx, in: sortedIds, frames: frames)
    }
}
```

- [ ] **Step 2: Run full test suite**

Run: `mise run test`
Expected: PASS — existing main-pane drag tests green.

**Watch for regression in**:
- `SplitContainerDropCaptureOverlayTests` (if present)
- `PaneDropPlannerTests`
- `DropCaptureViewCoordinateTests`

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift
git commit -m "refactor: PaneDragCoordinator adapts to shared DropTargetResolver"
```

---

## Tasks 12 & 13 — MOVED

Sizing policy (extraction + wiring) has been split into its own plan:
**`docs/plans/2026-04-22-drop-sizing-policy.md`**.

That plan is a product-decision spec — current behavior in `Layout.inserting` is
"halve the target pane's ratio," NOT equal redistribution (Codex adversarial
review caught this baseline error in v1 of this plan). The sizing plan enumerates
options (keep-halving / equal-redistribution / proportional-preservation) with
tradeoffs and requires user sign-off before any code lands.

Do NOT add sizing changes to this plan. If insertion behavior appears to need
a change to make a task in this plan work, that is a signal to revisit the
sizing plan, not to shortcut it here.

---

## Task 12: Unify visual overlay via shared target rects

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneDropTargetOverlay.swift`

- [ ] **Step 1: Confirm `DrawerDropTargetOverlay` already consumes `DrawerPaneDragCoordinator.targetRects`**

Read current file. It does — caller (DrawerPanel) computes targetRects and passes in.

- [ ] **Step 2: Confirm `PaneDropTargetOverlay` can consume `DropTargetResolver.targetRects` OR an equivalent from `PaneDragCoordinator`**

If it currently computes rects inline, refactor to take a `targetRects: [PaneDropTarget: CGRect]` input. Add a call-site helper on `PaneDragCoordinator`:

```swift
extension PaneDragCoordinator {
    static func targetRects(
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect
    ) -> [PaneDropTarget: CGRect] {
        let sortedIds = paneFrames.keys.sorted(by: { paneFrames[$0]!.minX < paneFrames[$1]!.minX })
        let rows: [RowID: [UUID]] = [.main: sortedIds]
        let shared = DropTargetResolver.targetRects(
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: .main
        )
        var out: [PaneDropTarget: CGRect] = [:]
        for (target, rect) in shared {
            guard case .slot(_, let idx) = target else { continue }
            if idx == 0, let first = sortedIds.first {
                out[PaneDropTarget(paneId: first, zone: .left)] = rect
            } else if idx >= sortedIds.count, let last = sortedIds.last {
                out[PaneDropTarget(paneId: last, zone: .right)] = rect
            } else {
                out[PaneDropTarget(paneId: sortedIds[idx - 1], zone: .right)] = rect
            }
        }
        return out
    }
}
```

- [ ] **Step 3: Verify manually — run app**

```bash
mise run build
AGENTSTUDIO_RESTORE_TRACE=1 .build/debug/AgentStudio
```

Drag in both main and drawer; confirm highlight rects match where drops actually land.

- [ ] **Step 4: Run full test suite**

Run: `mise run test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "refactor: overlays consume targetRects from shared resolver"
```

---

## Task 13: Remove dead code + final audit

**Files:**
- Audit: `Sources/AgentStudio/Core/Views/Splits/DropZone.swift`
- Audit: any ratio-computation code still living inline

- [ ] **Step 1: Audit for remaining inline geometry / sizing**

```bash
grep -rn "DrawerPaneDragCoordinator\.\|PaneDragCoordinator\." Sources/AgentStudio/ | grep -v "Resolver\|SizingPolicy"
grep -rn "creationBandHeight\|edgeCorridorWidth" Sources/AgentStudio/ | grep -v "DropTargetConfig\|DropTargetResolver"
```

Expected: only adapter files reference old coordinators; no inline duplication remains.

- [ ] **Step 2: If `DropZone.swift` is no longer emitting anything beyond `.left`/`.right` adapter purposes, consider deleting**

Only delete if `PaneActionCommand.insertPane(direction:)` is also migrated to slot-index. Per open question #4 this is probably deferred.

- [ ] **Step 3: Final full-suite run**

Run: `mise run test && mise run lint`
Expected: both green, no violations.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "chore: clean up drop-target legacy geometry"
```

---

## Self-review — ran against plan (post-revision 2026-04-22)

**Spec coverage:**
- User req (1) drag-to-top/bottom only in n×2: enforced by `.drawerTwoRow` config having both rows (no `.newRowBand`), `.drawerSingleRow` having only `.drawerTop` + `.newRowBand`. ✓
- User req (2) main doesn't allow top/bottom semantics: `.main` config has only `[.main]` row and no `newRowBand`. ✓
- User req (3) sizing/movement fits algo: DELEGATED to `2026-04-22-drop-sizing-policy.md`. This plan does not change sizing behavior. ✓
- Shared algo + config parameterization: Tasks 1–3, covered by resolver tests + fixtures. ✓
- Visual overlay sync with resolution: Task 7 (`targetRects`) + Task 12 (overlay wiring). ✓
- Sequencing with Phase B: Prereq 1 explicit. ✓
- Main-pane fixture coverage: Prereq 2 explicit. ✓
- Two-row drawer fixture coverage: Prereq 3 explicit. ✓

**Adversarial review findings addressed:**
- [HIGH] Sizing baseline wrong (current is halving, not equalize): removed from this plan, moved to sizing-policy plan with correct baseline. ✓
- [HIGH] Adapter Tasks 10/11 premature: retained in this plan but now gated behind Prereq 2 (main fixture) and Prereq 4 (open questions resolved). ✓
- [MED] Fixture coverage too narrow: Prereqs 2 + 3 add main + two-row fixtures as blocking prereqs. ✓
- [P1] Not orthogonal to Phase B: Prereq 1 now explicit. ✓
- [P1] Plan too wide: split into this plan + sizing plan. ✓

**Placeholder scan:** No "TBD" / "implement later" / "add validation" / bare "similar to Task N" references. Every code step contains the actual Swift.

**Type consistency:** `DropTarget.slot(row:index:)` used consistently. `DropTargetResolver` method names stable: `resolve`, `targetRects`, `resolveLatched`. Config factory names (`.main`, `.drawerSingleRow`, `.drawerTwoRow`) stable.

---

## Execution handoff

**Plan revised and saved to `docs/plans/2026-04-22-unified-drop-target-algo.md`.**

Do NOT start Task 1 until all four Prereqs are green. Specifically: Phase B of `2026-04-22-drawer-drag-tab-level-capture.md` must land and be dogfooded, the main-pane and two-row fixtures must exist and replay-test against the CURRENT coordinators, and the four open design questions need user answers.

After Prereqs are met, two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, adversarial review between tasks, fast iteration
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
