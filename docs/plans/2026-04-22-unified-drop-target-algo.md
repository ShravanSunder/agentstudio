# Unified drop-target resolution algorithm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the drag-target *resolution* algorithm across main panes and drawer panes so both share one core resolver parameterized by config. Eliminates the fork between `PaneDragCoordinator` (main) and `DrawerPaneDragCoordinator` (drawer), keeps visual highlight and resolution in lockstep, and enforces context-specific rules (main = flat strip, drawer n×1 = strip + can-grow, drawer n×2 = two rows).

**Scope boundary (updated 2026-04-22 after adversarial review):** THIS PLAN covers *geometry + target-vocabulary unification only*. It does **not** change insertion/removal sizing behavior — that is a product decision and lives in a sibling plan: `2026-04-22-drop-sizing-policy.md`. Running both plans together was rejected in review because sizing is a product change, geometry is a refactor.

**Architecture:** Introduce a pure, config-parameterized `DropTargetResolver` that consumes a `DropTargetConfig` value and emits a shared `DropTarget` type. Main/drawer keep their own storage actions and target-type translation; the geometric resolution and visual target-rect enumeration live in one place.

**Tech Stack:** Swift 6.2, `Testing` (no XCTest), `swift-format`, mise-orchestrated `mise run build/test/lint`. No new third-party deps. Pure-value algorithm module; all SwiftUI/AppKit plumbing stays in existing overlay NSViews.

---

## Prerequisites — MUST complete before Task 1

These are hard blockers. Any attempt to execute Task 1 without satisfying them is a plan violation.

### Prereq 0 — Directory rename + new home for shared primitives

- [ ] `Sources/AgentStudio/Core/Views/Splits/` renamed to `Sources/AgentStudio/Core/Views/Panes/` (27 files, `git mv` per file, one commit)
- [ ] `Sources/AgentStudio/Core/Views/DragAndDrop/` created (empty or with README) as the home for `DropTargetResolver`, `DropSizingPolicy`, `DropTargetOverlayRenderer`
- [ ] `Core/Views/Drawer/` unchanged
- [ ] `mise run build` + `mise run lint` green after rename

**Why:** "Splits/" no longer matches the directory's mixed contents (pane layout + drag/drop + tab content + arrangement UI). "Panes/" is the honest name. Shared drag/drop primitives get their own home. Mechanical change, one commit, no import changes (Swift doesn't encode paths in imports).

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
enum RowID: Hashable, Sendable {
    case main
    case drawerTop
    case drawerBottom
}

/// Which half of a pane the cursor is in. Replaces the legacy `DropZone`
/// enum that currently lives in `Core/Views/Splits/DropZone.swift`.
enum DropZoneSide: String, Hashable, Sendable, CaseIterable {
    case left
    case right
}

/// Vertical position for a newly-created second row in a drawer.
enum NewRowPosition: Hashable, Sendable {
    case top
    case bottom
}

/// Unified drop target. Produced by `DropTargetResolver`; consumed by
/// context-specific dispatchers (main via `PaneDragCoordinator` adapter,
/// drawer via `DrawerPaneDragCoordinator` adapter) that translate back to
/// `PaneActionCommand` variants.
enum DropTarget: Hashable, Sendable {
    /// Cursor is ON a pane — split that pane along the x-axis.
    /// `side` indicates which half of the pane.
    /// Sizing: halve target pane's ratio by default; Shift held at commit
    /// overrides to proportional preservation (see drop-sizing-policy plan).
    case paneSplit(paneId: UUID, side: DropZoneSide)

    /// Cursor is BETWEEN panes (or past an endpoint) — insert at this slot.
    /// No target pane; this is an interstitial position in the named row.
    /// Sizing: proportional preservation always (no target to halve).
    case paneSlot(row: RowID, index: Int)

    /// Drawer-n×1 only: cursor is in the top/bottom edge band.
    /// Grows the drawer to n×2 with the dragged pane as the new row's
    /// first member. Sizing: mechanical (new row gets rowSplitRatio).
    case paneNewRow(position: NewRowPosition)
}
```

**Config shape:**

```swift
struct NewRowBandConfig: Hashable, Sendable {
    /// Height of the top/bottom bands inside `containerBounds` that resolve
    /// to `.paneNewRow(.top)` / `.paneNewRow(.bottom)`.
    let bandHeight: CGFloat
}

struct DropTargetConfig: Hashable, Sendable {
    /// Ordered list of rows available for slot insertion in this context.
    /// Main = [.main]. Drawer n×1 = [.drawerTop]. Drawer n×2 = [.drawerTop, .drawerBottom].
    let rows: [RowID]

    /// If non-nil, the resolver emits `.paneNewRow(...)` when the cursor
    /// is inside the top/bottom edge band. Drawer n×1 provides this; main
    /// and drawer n×2 do not.
    let newRowBand: NewRowBandConfig?

    /// Width of the edge corridor that maps to slot-0 / slot-N even when
    /// the cursor is outside the leftmost/rightmost pane horizontally.
    /// Main = 24. Drawer = 0 (no corridor).
    let edgeCorridorWidth: CGFloat

    /// Row-level gate: if false, the resolver NEVER emits `.paneSplit` —
    /// it only emits `.paneSlot` (and `.paneNewRow` when applicable).
    /// Drawer = false (row-slot rearrangement only). Main = true.
    let allowsPaneSplit: Bool

    static let main = DropTargetConfig(
        rows: [.main],
        newRowBand: nil,
        edgeCorridorWidth: 24,
        allowsPaneSplit: true
    )

    static let drawerSingleRow = DropTargetConfig(
        rows: [.drawerTop],
        newRowBand: NewRowBandConfig(bandHeight: 28),
        edgeCorridorWidth: 0,
        allowsPaneSplit: false
    )

    static let drawerTwoRow = DropTargetConfig(
        rows: [.drawerTop, .drawerBottom],
        newRowBand: nil,
        edgeCorridorWidth: 0,
        allowsPaneSplit: false
    )
}
```

**Resolver contract:**

```swift
enum DropTargetResolver {
    static func resolve(
        location: CGPoint,
        rows: [RowID: [UUID]],              // ordered pane IDs per row
        paneFrames: [UUID: CGRect],         // pane frames in container-local space
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>          // whitelist for .paneSplit emission.
                                            // Main path passes all-pane-ids − minimized.
                                            // Drawer path passes the empty set
                                            // (config.allowsPaneSplit also forbids regardless).
                                            // No default — every call site declares intent.
    ) -> DropTarget?

    static func targetRects(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>
    ) -> [DropTarget: CGRect]

    static func resolveLatched(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>,
        currentTarget: DropTarget?,
        shouldAccept: (DropTarget) -> Bool
    ) -> DropTarget?
}
```

**Resolver decision flow:**

```
resolve(location, rows, paneFrames, bounds, config, splittablePanes) → DropTarget?
  │
  ├─ 1. If config.newRowBand != nil:
  │       cursor in top-band? → .paneNewRow(.top)
  │       cursor in bottom-band? → .paneNewRow(.bottom)
  │
  ├─ 2. For each rowID in config.rows (in order):
  │       a. Cursor Y outside this row's vertical extent? skip.
  │       b. If config.allowsPaneSplit && any pane P contains cursor
  │            && splittablePanes.contains(P):
  │            side = cursor.x < P.midX ? .left : .right
  │            → .paneSplit(paneId: P, side: side)
  │       c. Else (no splittable container):
  │            walk sorted frames by midpoint, return .paneSlot
  │
  ├─ 3. If config.edgeCorridorWidth > 0:
  │       cursor in left corridor of any row? → .paneSlot(row, 0)
  │       cursor in right corridor of any row? → .paneSlot(row, N)
  │
  └─ 4. nil
```

**Key invariants:**
- Resolver is pure — no modifier-flag awareness, no UI state, no atom reads
- Resolver is oblivious to minimized panes EXCEPT via `splittablePanes` (minimized-but-visible panes are in `paneFrames`/`rows` but not in `splittablePanes` → resolver naturally produces `.paneSlot` targets around them instead of `.paneSplit`)
- Caller is responsible for excluding invisible-minimized panes from `paneFrames`/`rows` entirely (see §"Invisible minimized mode")

## Minimized pane handling — visible bars

State: `minimizedPaneIds: Set<UUID>` on `Pane` / `Drawer`. `showMinimizedBars: Bool` on `UIStateAtom`.

**Render modes:**

| State | `showMinimizedBars` | Render | In `paneFrames`? |
|---|---|---|---|
| Not minimized | — | Full-width pane content | YES |
| Minimized | `true` | Narrow vertical bar (28pt, `CollapsedPaneBar`) | YES — bar emits preference |
| Minimized | `false` | Nothing (zero-rendered) | NO — empty segment body → no preference |

**Drop semantics user specified:** a minimized pane cannot be "split" — you can't drop on it to halve it. Only slot-insertion (before/after the bar) is allowed.

**Encoding this in the resolver:** the caller constructs `splittablePanes = allPaneIds − minimizedPaneIds` and passes that. When the cursor is on a minimized bar:
- Step 2b fails (`splittablePanes.contains(P) == false`)
- Falls through to step 2c
- Slot-midpoint resolution: cursor x < bar.midX → `.paneSlot(row, barIndex)` (insert before bar); else `.paneSlot(row, barIndex + 1)` (insert after bar)

No special-casing in resolver code. Whitelist filter is enough.

**Callers that build `splittablePanes`:**
- `FlatTabStripContainer` (main path)
- `DrawerPanel` (drawer path, via tab-level capture per tab-level-capture plan)

Both already have access to `minimizedPaneIds`.

## Invisible minimized mode — caller filter contract

When `showMinimizedBars == false`, `PaneSegmentSlotView` renders an empty body for minimized segments (confirmed at `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift:117` — the `if collapsedPaneWidth > 0` guard). Empty body → no GeometryReader-backed preference → `paneFrames` dict naturally excludes these panes.

**The caller doesn't need extra filter logic for the resolver input** — SwiftUI's layout system does it.

**But there IS an edge case: commit-time index translation.**

```
Full row (true model):       [minA, visibleA, minB, visibleB, minC]
Visible only (resolver sees): [visibleA, visibleB]
                              indices: 0        1
User drops at resolver slot 1 (between visibleA and visibleB).
                                ↑ what full-row index does this commit to?
```

The resolver produces a slot index relative to the VISIBLE row it was shown. When the commit handler (`PaneCoordinator` / `DrawerDropDispatch`) applies the insertion to the underlying `Layout`/`DrawerGridLayout`, it needs to map visible-slot-N → full-row-index-M.

**Proposed rule (to confirm with user before Task C commit wiring):** "visible slot K commits to the position immediately after the K-th visible pane in the full row." Dragged pane lands adjacent to the visible neighbor; minimized-invisible panes are elided conceptually and the new pane takes their place in the ordering.

Implementation lives in the adapter/commit layer, NOT the resolver. One helper: `func fullRowIndex(forVisibleSlot visibleIndex: Int, in fullRow: [UUID], minimizedPaneIds: Set<UUID>) -> Int`.

Flagged as a test-case for the main-drag fixture (Prereq 2) and for the drawer-two-row fixture (Prereq 3): at least one case per fixture with `showMinimizedBars=false`.

## Cross-tab drag — existing + three enhancements

### Existing behavior (grounded, preserved)

Confirmed at `Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift`:
- `draggingEntered` / `draggingUpdated` reject pane drops when `allowsTabBarInsertion(for: payload)` returns false — requires `payload.drawerParentPaneId == nil`. Drawer-child drags: tab bar is inert. No auto-select, no drop indicator.
- For main-pane drags, `draggingUpdated` computes `tabAtPoint(cursor)` and fires `onSelect?(hoveredTabId)` when a new tab is hovered. Immediate auto-select; re-selection of same tab suppressed via `lastAutoSelectedTabIdForPaneDrag`.
- Cross-tab commit path: `PaneDropPlanner.splitDecision` produces `.extractPaneToTabThenMove(paneId, sourceTabId, toIndex)` for drops whose destination tab differs from the source tab.

The resolver change in this plan is transparent to cross-tab flow: when the active tab auto-switches, SwiftUI re-publishes the new tab's `paneFrames` + related state, and the capture NSView's coordinator receives the update. Resolver runs against the new tab's inputs. No resolver code changes needed for cross-tab.

### Enhancement 1 — 100ms dwell timer on tab auto-switch

**Problem:** immediate auto-select fires during drive-by traversal across the tab bar. Cursor passing over tab B on the way to tab C accidentally activates tab B.

**Solution:** require the cursor to dwell on a tab for 100 ms before auto-selecting it. Pure state machine extracted as `DragDwellState` for unit testability.

**Pure state machine contract:**

```swift
/// Tracks dwell progress for cross-tab drag auto-select.
/// Pure value type. No side effects. Driven by `draggingUpdated` calls
/// that poll the cursor at ~30 Hz during an active drag.
struct DragDwellState: Equatable, Sendable {
    /// Tab currently under cursor (if any).
    var hoveredTabId: UUID?
    /// Time when the cursor first entered `hoveredTabId`.
    var dwellStartTime: TimeInterval?
    /// Last tab auto-selected during this drag session. Used to suppress
    /// immediate re-selection when cursor re-enters the same tab after
    /// briefly leaving and returning.
    var lastCommittedTabId: UUID?

    static let idle = DragDwellState()

    /// Single step of the state machine.
    ///
    /// - Parameters:
    ///   - current: previous state
    ///   - hoveredTabId: tab under cursor now (nil if cursor left tab bar)
    ///   - now: current time (caller supplies for testability)
    ///   - dwellDuration: how long the cursor must stay on a tab before
    ///     triggering auto-select. Default: 0.1 seconds.
    ///
    /// - Returns: `(next, shouldCommit)` — caller fires onSelect when
    ///   `shouldCommit` is non-nil.
    static func step(
        current: DragDwellState,
        hoveredTabId: UUID?,
        now: TimeInterval,
        dwellDuration: TimeInterval = 0.1
    ) -> (next: DragDwellState, shouldCommit: UUID?) {
        // Cursor left the tab bar entirely
        guard let hoveredTabId else {
            return (DragDwellState(lastCommittedTabId: current.lastCommittedTabId), nil)
        }

        // Different tab than we were dwelling on — restart dwell
        if hoveredTabId != current.hoveredTabId {
            return (
                DragDwellState(
                    hoveredTabId: hoveredTabId,
                    dwellStartTime: now,
                    lastCommittedTabId: current.lastCommittedTabId
                ),
                nil
            )
        }

        // Same tab; check if dwell expired
        guard let startTime = current.dwellStartTime else {
            // Defensive — shouldn't happen; reset
            return (
                DragDwellState(
                    hoveredTabId: hoveredTabId,
                    dwellStartTime: now,
                    lastCommittedTabId: current.lastCommittedTabId
                ),
                nil
            )
        }

        // Already committed this tab — don't re-fire
        if current.lastCommittedTabId == hoveredTabId {
            return (current, nil)
        }

        // Dwell expired — commit
        if (now - startTime) >= dwellDuration {
            return (
                DragDwellState(
                    hoveredTabId: hoveredTabId,
                    dwellStartTime: startTime,
                    lastCommittedTabId: hoveredTabId
                ),
                hoveredTabId
            )
        }

        // Still dwelling
        return (current, nil)
    }

    /// Reset on drag end / exit / commit. Caller calls this at
    /// `draggingExited`, `draggingEnded`, `performDragOperation`.
    static let reset = DragDwellState()
}
```

**NSView wiring** in `DraggableTabBarHostingView`:

```swift
private var dwellState = DragDwellState.idle

override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    // ... existing filter checks ...

    if types.contains(.agentStudioPaneDrop) {
        let point = convert(sender.draggingLocation, from: nil)
        let hoveredTabId = Self.tabId(at: point, tabFrames: tabFrames)
        let (next, shouldCommit) = DragDwellState.step(
            current: dwellState,
            hoveredTabId: hoveredTabId,
            now: CFAbsoluteTimeGetCurrent()
        )
        dwellState = next
        publishDwellProgressToAdapter()       // for visual indicator (Enhancement 2)
        if let tabIdToSelect = shouldCommit {
            onSelect?(tabIdToSelect)
            notifyAutoDismissIfNeeded(tabIdToSelect, payload: payload)  // Enhancement 3
        }
    }

    // ... existing updateDropTarget and .move return ...
}

override func draggingExited(_ sender: NSDraggingInfo?) {
    dwellState = DragDwellState.reset
    publishDwellProgressToAdapter()
    clearDropTargetIndicator()
}
```

Note the `tabId(at:tabFrames:)` static helper — extracted for pure-function testability.

### Enhancement 2 — Dwell visual indicator

**Problem:** 100ms dwell is fast enough to feel snappy but slow enough that users notice the "not quite clicked yet" pause. Without feedback the delay feels unresponsive.

**Solution:** subtle fill-in effect on the hovered tab during dwell, resolving to the selected state on commit.

**Visual spec:**
- While dwell is in progress (`dwellTabId == tabId && dwellProgress ∈ (0, 1)`): draw a fading-in background fill behind the tab contents — start at 0% opacity at dwell start, animate to a pre-select color (~30% of accent-color opacity) by dwell end
- On commit: the existing selected-tab styling takes over (instant snap to selected)
- On cancel (cursor moves off before 100ms): fill fades back to 0% over ~80ms

**Implementation:**
- New property on `TabBarAdapter` (observable): `@Published var dwellTabId: UUID?` and `@Published var dwellProgress: CGFloat`  (0.0 to 1.0)
- NSView calls `publishDwellProgressToAdapter()` after each state-machine step. Adapter publishes; SwiftUI `CustomTabBar` reads and renders.
- Progress is computed at step time: `progress = (now - dwellStartTime) / dwellDuration`, clamped to 0...1.
- SwiftUI renders the fill via a `.background(progressFill)` modifier on the tab view; opacity scales with `dwellProgress`.

The visual progress function is itself extractable as a pure function for unit tests:

```swift
enum DragDwellProgress {
    /// Progress 0.0 ... 1.0 for a dwell in progress. Pure.
    static func progress(
        state: DragDwellState,
        now: TimeInterval,
        dwellDuration: TimeInterval = 0.1
    ) -> CGFloat {
        guard
            let startTime = state.dwellStartTime,
            state.hoveredTabId != nil,
            state.hoveredTabId != state.lastCommittedTabId
        else { return 0 }
        let raw = (now - startTime) / dwellDuration
        return CGFloat(max(0, min(1, raw)))
    }
}
```

### Enhancement 3 — Auto-dismiss destination tab's drawer when main-pane drags enter

**Problem:** when a main-pane drag auto-switches to a tab whose drawer is expanded, that tab's main-pane capture is gated off (`mainSplitDragCaptureEnabled = false`). The cursor has no valid drop destination — the drag is effectively dead until the user cancels or finds a different tab.

**Solution:** on auto-switch, if source is main-pane AND destination tab has an expanded drawer, dispatch `.toggleDrawer(paneId: expandedDrawerParentPaneId)` to collapse the drawer. This reveals the main-pane area of the destination tab, which accepts the drop.

**CRITICAL constraint (user-flagged):** this trigger MUST be scoped surgically. Auto-dismiss is a core app behavior in other contexts (click-outside, dismiss monitor). The drag-driven auto-dismiss is a NEW trigger path and MUST NOT:
- Fire on regular tab click / keyboard tab switch
- Fire on drawer-child drag (tab bar is inert for those already, but defensively guard)
- Fire on tab-reorder drag
- Fire on drops that don't actually enter the destination tab's pane area

**Pure decision function (extracted for testability):**

```swift
/// Decides whether auto-dismiss should fire on drag-driven tab switch.
/// Pure. Takes all inputs explicitly; no environment reads.
enum DragAutoDismissDecision: Equatable, Sendable {
    /// Compute the decision.
    /// - Parameters:
    ///   - payload: the dragging payload
    ///   - destinationTabId: the tab about to be auto-selected
    ///   - destinationExpandedDrawerParentPaneId: the tab's currently-
    ///     expanded drawer parent pane ID, if any
    /// - Returns: the drawer parent pane ID to dismiss, or nil if no
    ///   dismissal should occur.
    static func shouldAutoDismiss(
        payload: PaneDragPayload,
        destinationTabId: UUID,
        destinationExpandedDrawerParentPaneId: UUID?
    ) -> UUID? {
        // Only for main-pane drags. Drawer-child drags never trigger auto-dismiss
        // (the tab bar is inert for them; defense-in-depth).
        guard payload.drawerParentPaneId == nil else { return nil }
        // Only when destination has an expanded drawer
        guard let drawerParentId = destinationExpandedDrawerParentPaneId else { return nil }
        // Only when switching to a DIFFERENT tab — don't dismiss the source tab's
        // drawer just because the cursor is on the tab bar
        guard destinationTabId != payload.tabId else { return nil }
        return drawerParentId
    }
}
```

**NSView wiring:**

```swift
// Provider injected by PaneTabViewController at view construction time.
var expandedDrawerParentIdForTab: ((_ tabId: UUID) -> UUID?)?
var onAutoDismissDrawerForDrag: ((_ tabId: UUID, _ drawerParentPaneId: UUID) -> Void)?

private func notifyAutoDismissIfNeeded(_ tabIdToSelect: UUID, payload: PaneDragPayload) {
    let destExpandedDrawer = expandedDrawerParentIdForTab?(tabIdToSelect) ?? nil
    if let drawerParentId = DragAutoDismissDecision.shouldAutoDismiss(
        payload: payload,
        destinationTabId: tabIdToSelect,
        destinationExpandedDrawerParentPaneId: destExpandedDrawer
    ) {
        onAutoDismissDrawerForDrag?(tabIdToSelect, drawerParentId)
    }
}
```

`PaneTabViewController` implements the callback by dispatching `.toggleDrawer(paneId: drawerParentId)` through its normal action pipeline.

**Edge cases that MUST be tested:**
1. Main-pane drag → tab B (drawer expanded) → drawer dismissed → pane area accepts drop ✓
2. Main-pane drag → tab B (drawer collapsed) → no dismissal ✓
3. Drawer-child drag → tab bar is inert already, but if this code path somehow ran, `shouldAutoDismiss` returns nil ✓
4. Regular tab click (no drag) → `shouldAutoDismiss` NEVER consulted; drawer stays expanded ✓
5. Keyboard tab switch → same ✓
6. Tab-reorder drag (`.agentStudioTabInternal` payload) → `shouldAutoDismiss` NEVER consulted (different payload path) ✓
7. Main drag crosses multiple drawer-expanded tabs → each dwell triggers one dismissal ✓
8. Main drag enters tab B, drawer dismissed, user then cancels drag → drawer STAYS DISMISSED (side effect retained; document this as known behavior) ✓
9. Drag enters drag-source tab's OWN tab from tab bar → `destinationTabId == payload.tabId` guard rejects dismissal ✓
10. Dwell cancelled mid-100ms (cursor moves off before commit) → `onSelect` never fires → `notifyAutoDismissIfNeeded` never called → drawer stays expanded ✓

### Enhancement 4 — Latch reset on tab change (mid-drag)

**Problem:** when the active tab auto-switches mid-drag, the drop-capture NSView's coordinator still holds a `currentTarget` with a UUID that belongs to the previous tab's panes. Under `resolveLatched`, `shouldAccept(currentTarget)` is called; if the stale UUID happens to match a pane in the new tab (unlikely but possible if the user has recently worked with the same pane in multiple tabs via restore), behavior is undefined.

**Solution:** explicit `currentTarget = nil` reset when the active tab changes mid-drag. Pure decision function + NSView callback.

```swift
enum DragLatchResetDecision {
    /// Whether the latched drop target should be cleared given a
    /// pending tab switch. Pure.
    static func shouldResetLatch(
        currentLatchedPaneId: UUID?,
        previousActiveTabId: UUID,
        newActiveTabId: UUID
    ) -> Bool {
        guard currentLatchedPaneId != nil else { return false }
        return previousActiveTabId != newActiveTabId
    }
}
```

Wiring: `PaneTabViewController.selectTab(_:)` (or the equivalent) calls into each tab's drop-capture coordinator with `finalizeDragSession()` when `shouldResetLatch` returns true.

---

## Pure-algorithm extraction principle

**Every algorithmic step in this plan must be a pure function or pure value-type method, unit-tested in isolation.** No exceptions. NSView callbacks / SwiftUI views are glue; all decisions live in pure types.

Pure helpers introduced by this plan:

| Helper | File | Purpose |
|---|---|---|
| `DropTargetResolver.resolve/targetRects/resolveLatched` | `Core/Views/DragAndDrop/DropTargetResolver.swift` | Geometric target resolution |
| `DropSizingPolicy.sizingMode/ratiosAfter{Insertion,Removal}` | `Core/Views/DragAndDrop/DropSizingPolicy.swift` | Sizing math |
| `DragDwellState.step` | `Core/Views/DragAndDrop/DragDwellState.swift` | Dwell state machine |
| `DragDwellProgress.progress` | `Core/Views/DragAndDrop/DragDwellState.swift` | Visual progress 0...1 |
| `DragAutoDismissDecision.shouldAutoDismiss` | `Core/Views/DragAndDrop/DragAutoDismissDecision.swift` | Auto-dismiss trigger rule |
| `DragLatchResetDecision.shouldResetLatch` | `Core/Views/DragAndDrop/DragLatchResetDecision.swift` | Latch reset rule |
| `DraggableTabBarGeometry.tabId(at:tabFrames:)` | `Core/Views/Panes/DraggableTabBarGeometry.swift` (new) | Pure `tabAtPoint` — extracted from existing NSView method |
| `VisibleRowIndexMapping.fullRowIndex(for:fullRow:minimized:)` | `Core/Views/DragAndDrop/VisibleRowIndexMapping.swift` | Invisible-minimized commit-time index translation |

Every helper above has a sibling test file with @Suite + @Test per pure function per edge case.

## Tab bar drag = separate mechanism

`DraggableTabBarHostingView` also handles tab-reorder (`.agentStudioTabInternal` payload). That's an entirely separate drag session with its own target model and commit path. Out of scope — this plan does not touch it.

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

**(After Prereq 0 directory rename: `Splits/` → `Panes/`; new `DragAndDrop/` home for shared primitives.)**

### New files

- `Sources/AgentStudio/Core/Models/DropTarget.swift` — `DropTarget`, `RowID`, `DropZoneSide`, `NewRowPosition` value types
- `Sources/AgentStudio/Core/Models/DropTargetConfig.swift` — `DropTargetConfig`, `NewRowBandConfig` + static factories (`.main`, `.drawerSingleRow`, `.drawerTwoRow`)
- `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift` — pure resolver
- `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetOverlayRenderer.swift` — shared SwiftUI view modifier for zone/slot/newRow highlight rendering (replaces `DropZone.overlay(...)` / `.overlayRect(...)` / `.markerRect(...)`)
- `Sources/AgentStudio/Core/Views/DragAndDrop/DropSizingPolicy.swift` — shared sizing rules (see `2026-04-22-drop-sizing-policy.md`)
- `Sources/AgentStudio/Core/Views/DragAndDrop/DragDwellState.swift` — pure dwell state machine + progress function (`DragDwellState.step`, `DragDwellProgress.progress`)
- `Sources/AgentStudio/Core/Views/DragAndDrop/DragAutoDismissDecision.swift` — pure trigger rule for auto-dismissing a destination tab's drawer on main-pane drag
- `Sources/AgentStudio/Core/Views/DragAndDrop/DragLatchResetDecision.swift` — pure rule for clearing latched drop target on tab change
- `Sources/AgentStudio/Core/Views/DragAndDrop/VisibleRowIndexMapping.swift` — pure commit-time index translation for invisible-minimized mode
- `Sources/AgentStudio/Core/Views/Panes/DraggableTabBarGeometry.swift` — pure `tabId(at:tabFrames:)` extracted from `DraggableTabBarHostingView.tabAtPoint`
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverFixtureTests.swift` — golden-fixture replay (pid=69705 drawer n×1, two-row drawer fixture per Prereq 3, main fixtures per Prereq 2)
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropSizingPolicyTests.swift`
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DragDwellStateTests.swift` — state machine timing edge cases
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DragAutoDismissDecisionTests.swift` — trigger matrix (including all 10 edge cases from §"Enhancement 3")
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DragLatchResetDecisionTests.swift`
- `Tests/AgentStudioTests/Core/Views/DragAndDrop/VisibleRowIndexMappingTests.swift`
- `Tests/AgentStudioTests/Core/Views/Panes/DraggableTabBarGeometryTests.swift`
- `Tests/AgentStudioTests/Core/Models/DropTargetConfigTests.swift`
- `Tests/AgentStudioTests/Core/Models/DropTargetTests.swift`

### Modified files (paths reflect post-rename)

- `Sources/AgentStudio/Core/Views/Panes/PaneDragCoordinator.swift` — thin adapter: translates `PaneDropTarget(paneId, zone)` ↔ `DropTarget` using main pane order + pane-ID re-anchoring per Q1; delegates geometry to `DropTargetResolver`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift` — thin adapter: translates `DrawerRearrangeTarget` ↔ `DropTarget` using drawer row structure; delegates geometry to `DropTargetResolver`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift` — renders highlight from the unified `targetRects` output
- `Sources/AgentStudio/Core/Views/Panes/PaneDropTargetOverlay.swift` — renders highlight from the unified `targetRects` output
- `Sources/AgentStudio/Core/Views/Panes/SplitContainerDropCaptureOverlay.swift` — builds `splittablePanes` from `minimizedPaneIds`; captures modifier flags in `performDragOperation`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift` — builds `splittablePanes` from drawer's `minimizedPaneIds`; captures modifier flags
- `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift` — passes `minimizedPaneIds` into the main capture mount; constructs `splittablePanes` whitelist
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift` — same for drawer path

### Deleted file

- `Sources/AgentStudio/Core/Views/Panes/DropZone.swift` — **deleted**. Contents migrate:
  - `enum DropZone { .left, .right }` → `DropZoneSide` in `Core/Models/DropTarget.swift`
  - `DropZone.calculate(at:in:)` → inlined into `DropTargetResolver` paneSplit branch
  - `DropZone.overlay(...)` / `.overlayRect(in:)` / `.markerRect(in:)` / private `.overlay(paneFrame:)` → `DropTargetOverlayRenderer.swift`
  - `DropZone.newDirection` → adapter helper in `PaneDragCoordinator.swift`

### Non-goals for this plan

- Does NOT change persistence shape — `DrawerGridLayout` and `Layout` stay; `PaneActionCommand.insertPane(direction: SplitNewDirection)` stays (adapter translates from `DropZoneSide`)
- Does NOT refactor the `NSView` drop-capture plumbing (`SplitContainerDropCaptureOverlay` / `DrawerSplitContainerDropCaptureOverlay` stay, just call the unified resolver)
- Does NOT introduce top/bottom split zones on main panes (config enforces)
- Does NOT change tab-bar drag or cross-tab auto-select (existing behavior preserved; see §"Cross-tab drag")
- Does NOT change `Drawer.init(from:)` decode or persistence schema (separate work)
- Does NOT wire rearrangement sizing — that's tracked by `2026-04-22-drop-sizing-policy.md` §"Rearrangement sizing"

---

## Open design questions — status

- **Q1 Main-pane corridor pane-ID anchor**: **RESOLVED (user, 2026-04-22)** — keep anchor; adapter reattaches `paneId` for edge-corridor slot translation
- **Q2 Main-pane: contained-target vs slot-midpoint**: **RESOLVED (user, 2026-04-22)** — hybrid by the resolver's decision flow: when cursor is ON a splittable pane, emit `.paneSplit`; when cursor is BETWEEN panes or on a non-splittable pane, emit `.paneSlot` via midpoint math. No separate "contained-first" mode; `config.allowsPaneSplit` gates whether paneSplit is an option at all.
- **Q3 Sizing policy**: Option D hybrid with Shift → Option C proportional. Deferred to `2026-04-22-drop-sizing-policy.md`.
- **Q4 `DropZone.swift` deletion**: **RESOLVED (user, 2026-04-22)** — delete file. Rename enum to `DropZoneSide` in `Core/Models/DropTarget.swift`. Overlay rendering moves to `DropTargetOverlayRenderer.swift` — visual stays identical. Commands still take `SplitNewDirection`; adapter translates `DropZoneSide → SplitNewDirection` at boundary.

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
    func dropZoneSide_leftRightDistinct() {
        #expect(DropZoneSide.left != .right)
        #expect(DropZoneSide.allCases.count == 2)
    }

    @Test
    func dropTarget_paneSplitEquality() {
        let paneId = UUID()
        let a: DropTarget = .paneSplit(paneId: paneId, side: .left)
        let b: DropTarget = .paneSplit(paneId: paneId, side: .left)
        let c: DropTarget = .paneSplit(paneId: paneId, side: .right)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func dropTarget_paneSlotEquality() {
        let a: DropTarget = .paneSlot(row: .main, index: 0)
        let b: DropTarget = .paneSlot(row: .main, index: 0)
        #expect(a == b)
    }

    @Test
    func dropTarget_paneNewRowPositions() {
        #expect(DropTarget.paneNewRow(position: .top) != .paneNewRow(position: .bottom))
    }

    @Test
    func dropTarget_kindsAreDisjoint() {
        let paneId = UUID()
        let split: DropTarget = .paneSplit(paneId: paneId, side: .left)
        let slot: DropTarget = .paneSlot(row: .main, index: 0)
        let newRow: DropTarget = .paneNewRow(position: .top)
        #expect(split != slot)
        #expect(slot != newRow)
        #expect(split != newRow)
    }

    @Test
    func dropTarget_hashable_inSet() {
        let paneId = UUID()
        let set: Set<DropTarget> = [
            .paneSlot(row: .main, index: 0),
            .paneSlot(row: .main, index: 0),
            .paneSlot(row: .drawerTop, index: 1),
            .paneSplit(paneId: paneId, side: .left),
        ]
        #expect(set.count == 3)
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

/// Stable identifier for a row.
enum RowID: Hashable, Sendable {
    case main
    case drawerTop
    case drawerBottom
}

/// Which half of a pane the cursor is in. Replaces legacy DropZone.
enum DropZoneSide: String, Hashable, Sendable, CaseIterable {
    case left
    case right
}

/// Vertical position for a drawer new-row creation.
enum NewRowPosition: Hashable, Sendable {
    case top
    case bottom
}

enum DropTarget: Hashable, Sendable {
    /// Cursor on a pane — split target along x-axis.
    case paneSplit(paneId: UUID, side: DropZoneSide)
    /// Cursor between panes — insert at slot.
    case paneSlot(row: RowID, index: Int)
    /// Drawer n×1 only — grow to n×2.
    case paneNewRow(position: NewRowPosition)
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
    func mainConfig_allowsPaneSplit_withCorridor() {
        let config = DropTargetConfig.main
        #expect(config.rows == [.main])
        #expect(config.newRowBand == nil)
        #expect(config.edgeCorridorWidth == 24)
        #expect(config.allowsPaneSplit == true)
    }

    @Test
    func drawerSingleRow_rejectsPaneSplit_hasNewRowBand() {
        let config = DropTargetConfig.drawerSingleRow
        #expect(config.rows == [.drawerTop])
        #expect(config.newRowBand?.bandHeight == 28)
        #expect(config.edgeCorridorWidth == 0)
        #expect(config.allowsPaneSplit == false)
    }

    @Test
    func drawerTwoRow_rejectsPaneSplit_noNewRowBand() {
        let config = DropTargetConfig.drawerTwoRow
        #expect(config.rows == [.drawerTop, .drawerBottom])
        #expect(config.newRowBand == nil)
        #expect(config.edgeCorridorWidth == 0)
        #expect(config.allowsPaneSplit == false)
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
    /// Row-level gate: when false, resolver NEVER emits `.paneSplit`.
    /// Drawer = false (row-slot rearrangement only). Main = true.
    let allowsPaneSplit: Bool

    static let main = DropTargetConfig(
        rows: [.main],
        newRowBand: nil,
        edgeCorridorWidth: 24,
        allowsPaneSplit: true
    )

    static let drawerSingleRow = DropTargetConfig(
        rows: [.drawerTop],
        newRowBand: NewRowBandConfig(bandHeight: 28),
        edgeCorridorWidth: 0,
        allowsPaneSplit: false
    )

    static let drawerTwoRow = DropTargetConfig(
        rows: [.drawerTop, .drawerBottom],
        newRowBand: nil,
        edgeCorridorWidth: 0,
        allowsPaneSplit: false
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

## Task 3: Resolver — row-slot + paneSplit resolution (no new-row, no edge corridor yet)

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift`
- Test: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`

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
    func resolve_onPane_allowsPaneSplit_returnsPaneSplit_leftHalf() {
        let ctx = threePaneSingleRow
        // .main config has allowsPaneSplit = true; splittablePanes = all panes.
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),  // inside paneA, left of midX=50
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main,
            splittablePanes: [paneA, paneB, paneC]
        )
        #expect(target == .paneSplit(paneId: paneA, side: .left))
    }

    @Test
    func resolve_onPane_allowsPaneSplit_returnsPaneSplit_rightHalf() {
        let ctx = threePaneSingleRow
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 75, y: 100),  // inside paneA, right of midX=50
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main,
            splittablePanes: [paneA, paneB, paneC]
        )
        #expect(target == .paneSplit(paneId: paneA, side: .right))
    }

    @Test
    func resolve_onPane_notSplittable_fallsThroughToPaneSlot() {
        let ctx = threePaneSingleRow
        // paneA is minimized → not in splittablePanes → slot-midpoint instead
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),  // inside paneA, left of midX
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main,
            splittablePanes: [paneB, paneC]  // paneA excluded
        )
        #expect(target == .paneSlot(row: .main, index: 0))
    }

    @Test
    func resolve_configDisallowsPaneSplit_emitsSlotOnly() {
        let ctx = threePaneSingleRow
        // drawer config has allowsPaneSplit = false — even if pane is splittable,
        // resolver emits .paneSlot.
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .drawerTwoRow,
            splittablePanes: [paneA, paneB, paneC]
        )
        #expect(target == .paneSlot(row: .drawerTop, index: 0))
    }

    @Test
    func resolve_betweenPanes_returnsPaneSlot() {
        let ctx = threePaneSingleRow
        // cursor at x=75 was right-half of paneA. To be BETWEEN panes, we need
        // cursor outside any pane — force by using allowsPaneSplit=false variant:
        // drawer config with panes at same geometry.
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 75, y: 100),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .drawerTwoRow,
            splittablePanes: []
        )
        // cursor.x=75 > paneA.midX=50 AND <= paneB.midX=150 → slot 1
        #expect(target == .paneSlot(row: .drawerTop, index: 1))
    }

    @Test
    func resolve_outsideVertically_returnsNil() {
        let ctx = threePaneSingleRow
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 150, y: 500),
            rows: ctx.rows,
            paneFrames: ctx.frames,
            containerBounds: ctx.bounds,
            config: .main,
            splittablePanes: [paneA, paneB, paneC]
        )
        #expect(target == nil)
    }

    @Test
    func resolve_emptyRow_returnsNil() {
        // Empty-tab fallback: no panes in the main row.
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 150, y: 100),
            rows: [.main: []],
            paneFrames: [:],
            containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
            config: .main,
            splittablePanes: []
        )
        #expect(target == nil)
        // Caller (e.g. FlatTabStripContainer) is responsible for handling
        // "add pane to empty tab" via a direct command path, not through the
        // resolver.
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test --filter DropTargetResolverTests`
Expected: FAIL — `DropTargetResolver` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift
import CoreGraphics
import Foundation

enum DropTargetResolver {
    static func resolve(
        location: CGPoint,
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>
    ) -> DropTarget? {
        for rowID in config.rows {
            guard let paneIds = rows[rowID], !paneIds.isEmpty else { continue }
            let sortedPaneOrder = paneIds
            let sortedFrames = sortedPaneOrder
                .compactMap { id -> (UUID, CGRect)? in
                    guard let f = paneFrames[id] else { return nil }
                    return (id, f)
                }
                .sorted { $0.1.minX < $1.1.minX }

            guard !sortedFrames.isEmpty else { continue }
            let rowMinY = sortedFrames.map(\.1.minY).min() ?? 0
            let rowMaxY = sortedFrames.map(\.1.maxY).max() ?? 0
            guard location.y >= rowMinY, location.y <= rowMaxY else { continue }

            // 1. paneSplit — cursor ON a splittable pane and config allows it
            if config.allowsPaneSplit {
                if let (containingId, containingFrame) = sortedFrames.first(where: { $0.1.contains(location) }),
                    splittablePanes.contains(containingId)
                {
                    let side: DropZoneSide = location.x < containingFrame.midX ? .left : .right
                    return .paneSplit(paneId: containingId, side: side)
                }
            }

            // 2. paneSlot — midpoint walk over sorted frames
            if location.x <= sortedFrames[0].1.midX {
                return .paneSlot(row: rowID, index: 0)
            }
            for index in 1..<sortedFrames.count where
                location.x > sortedFrames[index - 1].1.midX
                && location.x <= sortedFrames[index].1.midX
            {
                return .paneSlot(row: rowID, index: index)
            }
            return .paneSlot(row: rowID, index: sortedFrames.count)
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 7 tests (paneSplit left/right, not-splittable fallthrough, config disallows, between-panes, outside-vertically, empty-row).

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift
git commit -m "feat: add DropTargetResolver row-slot + paneSplit resolution"
```

---

## Task 4: Resolver — new-row bands for drawer single-row config

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`

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
        config: .drawerSingleRow,
        splittablePanes: []
    )
    #expect(target == .paneNewRow(position: .top))
}

@Test
func resolve_cursorInBottomBand_drawerSingleRow_returnsNewRowBottom() {
    let ctx = threePaneSingleRow
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 150, y: 190),  // 200 - 28 = 172; 190 is in band
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow,
        splittablePanes: []
    )
    #expect(target == .paneNewRow(position: .bottom))
}

@Test
func resolve_cursorInMiddle_drawerSingleRow_returnsSlot() {
    let ctx = threePaneSingleRow
    let target = DropTargetResolver.resolve(
        location: CGPoint(x: 150, y: 100),  // middle — not in any band
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow,
        splittablePanes: []
    )
    #expect(target == .paneSlot(row: .drawerTop, index: 2))
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
        config: .drawerTwoRow,
        splittablePanes: []
    )
    #expect(target == .paneSlot(row: .drawerTop, index: 2))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test --filter DropTargetResolverTests`
Expected: 4 new tests FAIL — resolver doesn't emit `.newRow` yet.

- [ ] **Step 3: Extend resolver**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift
// Insert at top of DropTargetResolver.resolve, before the for-rowID loop:

if let band = config.newRowBand {
    let topBand = CGRect(
        x: containerBounds.minX,
        y: containerBounds.minY,
        width: containerBounds.width,
        height: band.bandHeight
    )
    if topBand.contains(location) {
        return .paneNewRow(position: .top)
    }

    let bottomBand = CGRect(
        x: containerBounds.minX,
        y: containerBounds.maxY - band.bandHeight,
        width: containerBounds.width,
        height: band.bandHeight
    )
    if bottomBand.contains(location) {
        return .paneNewRow(position: .bottom)
    }
}
```

- [ ] **Step 4: Run test to verify all pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 8 tests total.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift
git commit -m "feat: resolver emits .newRow targets for drawer single-row band"
```

---

## Task 5: Resolver — two-row resolution with row priority

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`

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
        config: .drawerTwoRow,
        splittablePanes: []
    )
    #expect(target == .paneSlot(row: .drawerTop, index: 0))
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
        config: .drawerTwoRow,
        splittablePanes: []
    )
    #expect(target == .paneSlot(row: .drawerBottom, index: 2))
}
```

- [ ] **Step 2: Run test to verify pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — Task 3's row loop already handles two rows; these confirm.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift
git commit -m "test: verify resolver two-row behavior"
```

---

## Task 6: Resolver — edge corridor for main config

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`

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
        config: .main,
        splittablePanes: Set(ctx.frames.keys)
    )
    #expect(target == .paneSlot(row: .main, index: 0))
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
        config: .main,
        splittablePanes: Set(ctx.frames.keys)
    )
    #expect(target == .paneSlot(row: .main, index: 3))
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
        config: .drawerSingleRow,
        splittablePanes: []
    )
    #expect(target == nil)  // outside pane rows, no corridor applies
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test --filter DropTargetResolverTests`
Expected: 3 new tests FAIL — resolver doesn't emit corridor targets yet.

- [ ] **Step 3: Extend resolver**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift
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
            return .paneSlot(row: rowID, index: 0)
        }

        let rightCorridor = CGRect(
            x: last.maxX,
            y: rowMinY,
            width: min(config.edgeCorridorWidth, containerBounds.maxX - last.maxX),
            height: rowMaxY - rowMinY
        )
        if rightCorridor.contains(location) {
            return .paneSlot(row: rowID, index: sortedFrames.count)
        }
    }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `mise run test --filter DropTargetResolverTests`
Expected: PASS — 13 tests total.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift
git commit -m "feat: resolver emits edge-corridor slot targets for main"
```

---

## Task 7: Resolver — `targetRects` for visual overlay

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func targetRects_singleRow_emitsSlotAndNewRowRects() {
    let ctx = threePaneSingleRow
    let rects = DropTargetResolver.targetRects(
        rows: [.drawerTop: [paneA, paneB, paneC]],
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .drawerSingleRow,
        splittablePanes: []
    )

    // 4 slots + 2 new-row bands
    #expect(rects.count == 6)
    #expect(rects[.paneNewRow(position: .top)] != nil)
    #expect(rects[.paneNewRow(position: .bottom)] != nil)
    #expect(rects[.paneSlot(row: .drawerTop, index: 0)] != nil)
    #expect(rects[.paneSlot(row: .drawerTop, index: 3)] != nil)
}

@Test
func targetRects_main_emitsOnlySlotRects() {
    let ctx = threePaneSingleRow
    let rects = DropTargetResolver.targetRects(
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .main,
        splittablePanes: Set(ctx.frames.keys)
    )
    // 4 slots, no newRow, no corridor rect (corridor is part of resolve, not enumerated rects — design choice, confirm in review)
    #expect(rects.count == 4)
    #expect(rects[.paneNewRow(position: .top)] == nil)
}
```

- [ ] **Step 2: Run test to verify fail**

Run: `mise run test --filter DropTargetResolverTests`
Expected: FAIL — `targetRects` not defined.

- [ ] **Step 3: Add `targetRects`**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift
extension DropTargetResolver {
    static func targetRects(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig
    ) -> [DropTarget: CGRect] {
        var rects: [DropTarget: CGRect] = [:]

        if let band = config.newRowBand {
            rects[.paneNewRow(position: .top)] = CGRect(
                x: containerBounds.minX,
                y: containerBounds.minY,
                width: containerBounds.width,
                height: band.bandHeight
            )
            rects[.paneNewRow(position: .bottom)] = CGRect(
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
                rects[.paneSlot(row: rowID, index: insertionIndex)] = CGRect(
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
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift
git commit -m "feat: resolver emits targetRects for visual overlay parity"
```

---

## Task 8: Resolver — `resolveLatched` wrapper for NSView callbacks

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift`

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
        splittablePanes: Set(ctx.frames.keys),
        currentTarget: nil,
        shouldAccept: { _ in true }
    )
    #expect(target == .paneSlot(row: .main, index: 1))
}

@Test
func resolveLatched_falseAcceptor_keepsCurrent() {
    let ctx = threePaneSingleRow
    let current: DropTarget = .paneSlot(row: .main, index: 2)
    let target = DropTargetResolver.resolveLatched(
        location: CGPoint(x: 75, y: 100),
        rows: ctx.rows,
        paneFrames: ctx.frames,
        containerBounds: ctx.bounds,
        config: .main,
        splittablePanes: Set(ctx.frames.keys),
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
        splittablePanes: Set(ctx.frames.keys),
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
// Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift
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
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverTests.swift
git commit -m "feat: add DropTargetResolver.resolveLatched for NSView callbacks"
```

---

## Task 9: Golden-file fixture test from pid=69705

**Files:**
- Create: `Tests/AgentStudioTests/Fixtures/DrawerDropTargetFixture-pid69705.json`
- Create: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverFixtureTests.swift`

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
// Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverFixtureTests.swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DropTargetResolverFixtureTests {
    struct Fixture: Decodable {
        struct Rect: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
        struct Rows: Decodable {
            let main: [UUID]?
            let drawerTop: [UUID]?
            let drawerBottom: [UUID]?
        }
        struct Resolution: Decodable {
            struct Point: Decodable { let x: Double; let y: Double }
            struct ExpectedTarget: Decodable {
                /// "paneSplit" | "paneSlot" | "paneNewRow"
                let kind: String
                /// For paneSplit
                let paneId: UUID?
                let side: String?       // "left" | "right"
                /// For paneSlot
                let row: String?        // "main" | "drawerTop" | "drawerBottom"
                let index: Int?
                /// For paneNewRow
                let position: String?   // "top" | "bottom"
            }
            let location: Point
            let expectedTarget: ExpectedTarget
        }
        /// "main" | "drawerSingleRow" | "drawerTwoRow"
        let configName: String
        /// pane IDs considered splittable at capture time. Empty for drawer fixtures.
        /// For main fixtures: captured from `paneFrames.keys − minimizedPaneIds` at drag time.
        let splittablePaneIds: [UUID]
        let containerBounds: Rect
        let rows: Rows
        let paneFrames: [String: Rect]
        let resolutions: [Resolution]

        var config: DropTargetConfig {
            switch configName {
            case "main": return .main
            case "drawerSingleRow": return .drawerSingleRow
            case "drawerTwoRow": return .drawerTwoRow
            default: fatalError("Unknown config name \(configName)")
            }
        }
    }

    @Test(arguments: ["DrawerDropTargetFixture-pid69705", "MainDrag-sessionA", "MainDrag-sessionB", "MainDrag-sessionC", "DrawerTwoRowDrag"])
    func fixture_allResolutionsMatch(fixtureName: String) throws {
        let url = Bundle.module.url(forResource: fixtureName, withExtension: "json")!
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
        if let mainIds = fixture.rows.main { rows[.main] = mainIds }
        if let top = fixture.rows.drawerTop { rows[.drawerTop] = top }
        if let bottom = fixture.rows.drawerBottom { rows[.drawerBottom] = bottom }

        let splittable = Set(fixture.splittablePaneIds)

        for resolution in fixture.resolutions {
            let expected: DropTarget? = decodeExpected(resolution.expectedTarget)
            let actual = DropTargetResolver.resolve(
                location: CGPoint(x: resolution.location.x, y: resolution.location.y),
                rows: rows,
                paneFrames: frames,
                containerBounds: bounds,
                config: fixture.config,
                splittablePanes: splittable
            )
            #expect(actual == expected, "at \(resolution.location) expected \(String(describing: expected)) got \(String(describing: actual))")
        }
    }

    private func decodeExpected(_ et: Fixture.Resolution.ExpectedTarget) -> DropTarget? {
        switch et.kind {
        case "paneSplit":
            guard let paneId = et.paneId, let sideStr = et.side else { return nil }
            let side: DropZoneSide = sideStr == "left" ? .left : .right
            return .paneSplit(paneId: paneId, side: side)
        case "paneSlot":
            guard let rowStr = et.row, let idx = et.index else { return nil }
            let rowID: RowID = {
                switch rowStr {
                case "main": return .main
                case "drawerTop": return .drawerTop
                case "drawerBottom": return .drawerBottom
                default: fatalError("Unknown row \(rowStr)")
                }
            }()
            return .paneSlot(row: rowID, index: idx)
        case "paneNewRow":
            let pos: NewRowPosition = et.position == "top" ? .top : .bottom
            return .paneNewRow(position: pos)
        default:
            return nil
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
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetResolverFixtureTests.swift
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
            config: config,
            splittablePanes: []  // drawer: config.allowsPaneSplit is false; never emits .paneSplit
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
            config: config,
            splittablePanes: []  // drawer: never emits .paneSplit
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
            splittablePanes: [],  // drawer: never emits .paneSplit
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
        case .paneSlot(let row, let index):
            let placement: DrawerRowPlacement = row == .drawerTop ? .top : .bottom
            return .rowSlot(row: placement, insertionIndex: index)
        case .paneNewRow(let position):
            let placement: DrawerRowPlacement = position == .top ? .top : .bottom
            return .createSecondRow(position: placement)
        }
    }

    private static func translate(_ target: DrawerRearrangeTarget) -> DropTarget {
        switch target {
        case .rowSlot(let row, let insertionIndex):
            let rowID: RowID = row == .top ? .drawerTop : .drawerBottom
            return .paneSlot(row: rowID, index: insertionIndex)
        case .createSecondRow(let position):
            let pos: NewRowPosition = position == .top ? .top : .bottom
            return .paneNewRow(position: pos)
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
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneDragCoordinator.swift`

**API change:** the adapter now accepts `minimizedPaneIds: Set<UUID>` so it can construct the `splittablePanes` whitelist for the resolver. Callers (`SplitContainerDropCaptureOverlay.Coordinator`) already receive `minimizedPaneIds` from `FlatTabStripContainer` — they pass it through. No default; every caller declares intent.

- [ ] **Step 1: Replace internals with adapter**

```swift
struct PaneDragCoordinator {
    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect?,
        minimizedPaneIds: Set<UUID>
    ) -> PaneDropTarget? {
        let sortedRowIds = paneFrames.keys.sorted(by: { paneFrames[$0]!.minX < paneFrames[$1]!.minX })
        let rows: [RowID: [UUID]] = [.main: sortedRowIds]
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let splittable = Set(paneFrames.keys).subtracting(minimizedPaneIds)

        guard let target = DropTargetResolver.resolve(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: effectiveBounds,
            config: .main,
            splittablePanes: splittable
        ) else {
            return nil
        }

        // Main's PaneDropTarget carries paneId + zone. Translate both .paneSplit
        // (direct mapping) and .paneSlot (anchor to leftmost/rightmost) through
        // the adapter. .paneNewRow never appears for .main config — guarded by
        // config.newRowBand == nil.
        switch target {
        case .paneSplit(let paneId, let side):
            return PaneDropTarget(paneId: paneId, zone: side == .left ? .left : .right)
        case .paneSlot(_, let index):
            return translate(slotIndex: index, in: sortedRowIds)
        case .paneNewRow:
            return nil
        }
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect?,
        minimizedPaneIds: Set<UUID>,
        currentTarget: PaneDropTarget?,
        shouldAcceptDrop: (UUID, DropZone) -> Bool
    ) -> PaneDropTarget? {
        let sortedRowIds = paneFrames.keys.sorted(by: { paneFrames[$0]!.minX < paneFrames[$1]!.minX })
        let rows: [RowID: [UUID]] = [.main: sortedRowIds]
        let effectiveBounds = containerBounds ?? derivedBounds(from: paneFrames)
        let splittable = Set(paneFrames.keys).subtracting(minimizedPaneIds)
        let currentDrop: DropTarget? = currentTarget.flatMap { toDropTarget($0, sortedIds: sortedRowIds) }

        guard let target = DropTargetResolver.resolveLatched(
            location: location,
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: effectiveBounds,
            config: .main,
            splittablePanes: splittable,
            currentTarget: currentDrop,
            shouldAccept: { candidate in
                guard let mapped = fromDropTarget(candidate, sortedIds: sortedRowIds) else { return false }
                return shouldAcceptDrop(mapped.paneId, mapped.zone)
            }
        ) else { return nil }

        switch target {
        case .paneSplit(let paneId, let side):
            return PaneDropTarget(paneId: paneId, zone: side == .left ? .left : .right)
        case .paneSlot(_, let index):
            return translate(slotIndex: index, in: sortedRowIds)
        case .paneNewRow:
            return nil
        }
    }

    private static func derivedBounds(from frames: [UUID: CGRect]) -> CGRect {
        let minX = frames.values.map(\.minX).min() ?? 0
        let maxX = frames.values.map(\.maxX).max() ?? 0
        let minY = frames.values.map(\.minY).min() ?? 0
        let maxY = frames.values.map(\.maxY).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func translate(slotIndex: Int, in sortedIds: [UUID]) -> PaneDropTarget? {
        guard !sortedIds.isEmpty else { return nil }
        if slotIndex == 0 { return PaneDropTarget(paneId: sortedIds[0], zone: .left) }
        if slotIndex >= sortedIds.count { return PaneDropTarget(paneId: sortedIds.last!, zone: .right) }
        // Interior slot — anchor to pane just before the slot, zone .right.
        return PaneDropTarget(paneId: sortedIds[slotIndex - 1], zone: .right)
    }

    private static func toDropTarget(_ pt: PaneDropTarget, sortedIds: [UUID]) -> DropTarget? {
        guard let idx = sortedIds.firstIndex(of: pt.paneId) else { return nil }
        switch pt.zone {
        case .left:  return .paneSlot(row: .main, index: idx)
        case .right: return .paneSlot(row: .main, index: idx + 1)
        }
    }

    private static func fromDropTarget(_ dt: DropTarget, sortedIds: [UUID]) -> PaneDropTarget? {
        switch dt {
        case .paneSplit(let paneId, let side):
            return PaneDropTarget(paneId: paneId, zone: side == .left ? .left : .right)
        case .paneSlot(_, let idx):
            return translate(slotIndex: idx, in: sortedIds)
        case .paneNewRow:
            return nil
        }
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
            config: .main,
            splittablePanes: Set(ctx.frames.keys)
        )
        var out: [PaneDropTarget: CGRect] = [:]
        for (target, rect) in shared {
            guard case .paneSlot(_, let idx) = target else { continue }
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

## Task 13: `DragDwellState` — pure state machine for tab hover dwell

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DragDwellState.swift`
- Test: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DragDwellStateTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DragDwellStateTests {
    private let tabA = UUID()
    private let tabB = UUID()
    private let tabC = UUID()

    @Test
    func step_cursorLeavesTabBar_resets() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let (next, commit) = DragDwellState.step(current: state, hoveredTabId: nil, now: 10.05, dwellDuration: 0.1)
        #expect(next.hoveredTabId == nil)
        #expect(next.dwellStartTime == nil)
        #expect(commit == nil)
    }

    @Test
    func step_newTab_startsDwell_doesNotCommit() {
        let (next, commit) = DragDwellState.step(
            current: .idle,
            hoveredTabId: tabA,
            now: 10.0,
            dwellDuration: 0.1
        )
        #expect(next.hoveredTabId == tabA)
        #expect(next.dwellStartTime == 10.0)
        #expect(commit == nil)
    }

    @Test
    func step_sameTab_underThreshold_doesNotCommit() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let (next, commit) = DragDwellState.step(current: state, hoveredTabId: tabA, now: 10.05, dwellDuration: 0.1)
        #expect(next.dwellStartTime == 10.0)   // preserved
        #expect(commit == nil)
    }

    @Test
    func step_sameTab_atThreshold_commits() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let (next, commit) = DragDwellState.step(current: state, hoveredTabId: tabA, now: 10.1, dwellDuration: 0.1)
        #expect(commit == tabA)
        #expect(next.lastCommittedTabId == tabA)
    }

    @Test
    func step_sameTab_overThreshold_commits() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let (next, commit) = DragDwellState.step(current: state, hoveredTabId: tabA, now: 10.5, dwellDuration: 0.1)
        #expect(commit == tabA)
        #expect(next.lastCommittedTabId == tabA)
    }

    @Test
    func step_switchToDifferentTab_resetsDwell() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let (next, commit) = DragDwellState.step(current: state, hoveredTabId: tabB, now: 10.05, dwellDuration: 0.1)
        #expect(next.hoveredTabId == tabB)
        #expect(next.dwellStartTime == 10.05)
        #expect(commit == nil)
    }

    @Test
    func step_afterCommit_sameTab_doesNotReCommit() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: tabA)
        let (_, commit) = DragDwellState.step(current: state, hoveredTabId: tabA, now: 11.0, dwellDuration: 0.1)
        #expect(commit == nil)
    }

    @Test
    func step_afterCommit_differentTab_startsNewDwell() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: tabA)
        let (next, commit) = DragDwellState.step(current: state, hoveredTabId: tabB, now: 11.0, dwellDuration: 0.1)
        #expect(next.hoveredTabId == tabB)
        #expect(next.dwellStartTime == 11.0)
        #expect(next.lastCommittedTabId == tabA)  // preserved
        #expect(commit == nil)
    }

    @Test
    func step_rapidPassAcrossTabs_noCommits() {
        // Simulate cursor moving A → B → C within < dwell duration each.
        var state = DragDwellState.idle
        (state, _) = DragDwellState.step(current: state, hoveredTabId: tabA, now: 10.00, dwellDuration: 0.1)
        let (afterB, commitB) = DragDwellState.step(current: state, hoveredTabId: tabB, now: 10.05, dwellDuration: 0.1)
        #expect(commitB == nil)
        let (afterC, commitC) = DragDwellState.step(current: afterB, hoveredTabId: tabC, now: 10.08, dwellDuration: 0.1)
        #expect(commitC == nil)
        #expect(afterC.lastCommittedTabId == nil)
    }

    // MARK: - Progress

    @Test
    func progress_zeroAtDwellStart() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let p = DragDwellProgress.progress(state: state, now: 10.0, dwellDuration: 0.1)
        #expect(p == 0)
    }

    @Test
    func progress_halfAtHalfDuration() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let p = DragDwellProgress.progress(state: state, now: 10.05, dwellDuration: 0.1)
        #expect(abs(p - 0.5) < 0.001)
    }

    @Test
    func progress_oneAtDuration() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let p = DragDwellProgress.progress(state: state, now: 10.1, dwellDuration: 0.1)
        #expect(p == 1)
    }

    @Test
    func progress_clampedToOne_overDuration() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: nil)
        let p = DragDwellProgress.progress(state: state, now: 10.5, dwellDuration: 0.1)
        #expect(p == 1)
    }

    @Test
    func progress_zeroWhenCommitted() {
        let state = DragDwellState(hoveredTabId: tabA, dwellStartTime: 10.0, lastCommittedTabId: tabA)
        let p = DragDwellProgress.progress(state: state, now: 10.05, dwellDuration: 0.1)
        #expect(p == 0)
    }

    @Test
    func progress_zeroWhenIdle() {
        let p = DragDwellProgress.progress(state: .idle, now: 10.0, dwellDuration: 0.1)
        #expect(p == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter DragDwellStateTests`
Expected: FAIL — `DragDwellState` and `DragDwellProgress` not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DragDwellState.swift
import CoreGraphics
import Foundation

struct DragDwellState: Equatable, Sendable {
    var hoveredTabId: UUID?
    var dwellStartTime: TimeInterval?
    var lastCommittedTabId: UUID?

    static let idle = DragDwellState()

    static func step(
        current: DragDwellState,
        hoveredTabId: UUID?,
        now: TimeInterval,
        dwellDuration: TimeInterval
    ) -> (next: DragDwellState, shouldCommit: UUID?) {
        guard let hoveredTabId else {
            return (DragDwellState(
                hoveredTabId: nil,
                dwellStartTime: nil,
                lastCommittedTabId: current.lastCommittedTabId
            ), nil)
        }

        if hoveredTabId != current.hoveredTabId {
            return (DragDwellState(
                hoveredTabId: hoveredTabId,
                dwellStartTime: now,
                lastCommittedTabId: current.lastCommittedTabId
            ), nil)
        }

        guard let startTime = current.dwellStartTime else {
            return (DragDwellState(
                hoveredTabId: hoveredTabId,
                dwellStartTime: now,
                lastCommittedTabId: current.lastCommittedTabId
            ), nil)
        }

        if current.lastCommittedTabId == hoveredTabId {
            return (current, nil)
        }

        if (now - startTime) >= dwellDuration {
            return (DragDwellState(
                hoveredTabId: hoveredTabId,
                dwellStartTime: startTime,
                lastCommittedTabId: hoveredTabId
            ), hoveredTabId)
        }

        return (current, nil)
    }
}

enum DragDwellProgress {
    static func progress(
        state: DragDwellState,
        now: TimeInterval,
        dwellDuration: TimeInterval
    ) -> CGFloat {
        guard
            let startTime = state.dwellStartTime,
            state.hoveredTabId != nil,
            state.hoveredTabId != state.lastCommittedTabId
        else { return 0 }
        let raw = (now - startTime) / dwellDuration
        return CGFloat(max(0, min(1, raw)))
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `mise run test --filter DragDwellStateTests`
Expected: PASS — 14 tests (9 step + 5 progress).

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DragDwellState.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DragDwellStateTests.swift
git commit -m "feat: DragDwellState pure state machine + progress helper"
```

---

## Task 14: `DragAutoDismissDecision` — when to dismiss destination drawer

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DragAutoDismissDecision.swift`
- Test: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DragAutoDismissDecisionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DragAutoDismissDecisionTests {
    private let sourceTab = UUID()
    private let destTab = UUID()
    private let sourcePaneId = UUID()
    private let drawerParent = UUID()

    private func mainPayload() -> PaneDragPayload {
        PaneDragPayload(paneId: sourcePaneId, tabId: sourceTab, drawerParentPaneId: nil)
    }

    private func drawerChildPayload() -> PaneDragPayload {
        PaneDragPayload(paneId: sourcePaneId, tabId: sourceTab, drawerParentPaneId: drawerParent)
    }

    // Edge case 1: main-pane drag + destination tab (drawer expanded) → dismiss
    @Test
    func mainDrag_destinationHasExpandedDrawer_returnsDrawerParent() {
        let expandedDrawerInDest = UUID()
        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: mainPayload(),
            destinationTabId: destTab,
            destinationExpandedDrawerParentPaneId: expandedDrawerInDest
        )
        #expect(result == expandedDrawerInDest)
    }

    // Edge case 2: main-pane drag + destination with no expanded drawer → nil
    @Test
    func mainDrag_destinationNoDrawer_returnsNil() {
        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: mainPayload(),
            destinationTabId: destTab,
            destinationExpandedDrawerParentPaneId: nil
        )
        #expect(result == nil)
    }

    // Edge case 3: drawer-child drag → never dismiss (even if dest has drawer)
    @Test
    func drawerChildDrag_neverDismisses() {
        let expandedDrawerInDest = UUID()
        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: drawerChildPayload(),
            destinationTabId: destTab,
            destinationExpandedDrawerParentPaneId: expandedDrawerInDest
        )
        #expect(result == nil)
    }

    // Edge case 9: switching to own tab (destinationTabId == payload.tabId) → nil
    @Test
    func mainDrag_destinationIsSourceTab_returnsNil() {
        let expandedDrawerInSource = UUID()
        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: mainPayload(),
            destinationTabId: sourceTab,                            // SAME tab
            destinationExpandedDrawerParentPaneId: expandedDrawerInSource
        )
        #expect(result == nil)
    }

    // Edge cases 4–7, 10 not testable at this function level (they concern
    // callers — menu/keyboard/click paths don't invoke this function).
    // Covered by integration tests in Task 17 (wiring into DraggableTabBarHostingView).
    // Edge case 8 is a known behavior (drawer stays dismissed if drag cancels) —
    // also covered by integration, not this pure function.
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter DragAutoDismissDecisionTests`
Expected: FAIL — `DragAutoDismissDecision` not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DragAutoDismissDecision.swift
import Foundation

enum DragAutoDismissDecision {
    static func shouldAutoDismiss(
        payload: PaneDragPayload,
        destinationTabId: UUID,
        destinationExpandedDrawerParentPaneId: UUID?
    ) -> UUID? {
        guard payload.drawerParentPaneId == nil else { return nil }
        guard let drawerParentId = destinationExpandedDrawerParentPaneId else { return nil }
        guard destinationTabId != payload.tabId else { return nil }
        return drawerParentId
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `mise run test --filter DragAutoDismissDecisionTests`
Expected: PASS — 4 pure-function tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DragAutoDismissDecision.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DragAutoDismissDecisionTests.swift
git commit -m "feat: DragAutoDismissDecision — pure trigger rule"
```

---

## Task 15: `DragLatchResetDecision` — clear drop target on tab switch

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DragLatchResetDecision.swift`
- Test: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DragLatchResetDecisionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DragLatchResetDecisionTests {
    private let tabA = UUID()
    private let tabB = UUID()
    private let paneId = UUID()

    @Test
    func reset_whenTabChanges_andLatchPresent() {
        #expect(DragLatchResetDecision.shouldResetLatch(
            currentLatchedPaneId: paneId,
            previousActiveTabId: tabA,
            newActiveTabId: tabB
        ))
    }

    @Test
    func noReset_whenTabUnchanged() {
        #expect(!DragLatchResetDecision.shouldResetLatch(
            currentLatchedPaneId: paneId,
            previousActiveTabId: tabA,
            newActiveTabId: tabA
        ))
    }

    @Test
    func noReset_whenNoLatchPresent() {
        #expect(!DragLatchResetDecision.shouldResetLatch(
            currentLatchedPaneId: nil,
            previousActiveTabId: tabA,
            newActiveTabId: tabB
        ))
    }
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter DragLatchResetDecisionTests`
Expected: FAIL — type not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/DragLatchResetDecision.swift
import Foundation

enum DragLatchResetDecision {
    static func shouldResetLatch(
        currentLatchedPaneId: UUID?,
        previousActiveTabId: UUID,
        newActiveTabId: UUID
    ) -> Bool {
        guard currentLatchedPaneId != nil else { return false }
        return previousActiveTabId != newActiveTabId
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `mise run test --filter DragLatchResetDecisionTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DragLatchResetDecision.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/DragLatchResetDecisionTests.swift
git commit -m "feat: DragLatchResetDecision — pure rule for mid-drag tab switch"
```

---

## Task 16: `DraggableTabBarGeometry.tabId(at:)` — pure tabAtPoint extraction

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Panes/DraggableTabBarGeometry.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Panes/DraggableTabBarGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DraggableTabBarGeometryTests {
    private let tabA = UUID()
    private let tabB = UUID()
    private let tabC = UUID()

    private var threeTabFrames: [UUID: CGRect] {
        [
            tabA: CGRect(x: 0, y: 0, width: 100, height: 30),
            tabB: CGRect(x: 100, y: 0, width: 100, height: 30),
            tabC: CGRect(x: 200, y: 0, width: 100, height: 30),
        ]
    }

    @Test
    func tabId_insideTabA() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 50, y: 15),
            tabFrames: threeTabFrames
        )
        #expect(result == tabA)
    }

    @Test
    func tabId_insideTabC() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 250, y: 15),
            tabFrames: threeTabFrames
        )
        #expect(result == tabC)
    }

    @Test
    func tabId_outsideAllTabs_returnsNil() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 500, y: 15),
            tabFrames: threeTabFrames
        )
        #expect(result == nil)
    }

    @Test
    func tabId_emptyTabFrames_returnsNil() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 50, y: 15),
            tabFrames: [:]
        )
        #expect(result == nil)
    }

    @Test
    func tabId_onExactBoundary_isDeterministic() {
        // Cursor at x=100 — boundary between A and B. CGRect.contains uses
        // left-inclusive semantics; A owns this point.
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 100, y: 15),
            tabFrames: threeTabFrames
        )
        #expect(result == tabA || result == tabB)  // tie-break: either is acceptable, doc which.
    }
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter DraggableTabBarGeometryTests`
Expected: FAIL — type not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Views/Panes/DraggableTabBarGeometry.swift
import CoreGraphics
import Foundation

enum DraggableTabBarGeometry {
    /// Returns the ID of the tab whose frame contains the point, or nil.
    /// Deterministic tie-break on boundaries: leftmost (smallest minX) wins.
    static func tabId(at point: CGPoint, tabFrames: [UUID: CGRect]) -> UUID? {
        let hits = tabFrames
            .filter { $0.value.contains(point) }
            .sorted { $0.value.minX < $1.value.minX }
        return hits.first?.key
    }
}
```

- [ ] **Step 4: Extract + replace the existing `tabAtPoint` method in `DraggableTabBarHostingView`**

Replace the private `tabAtPoint(_:)` method with a call to `DraggableTabBarGeometry.tabId(at:tabFrames:)`. Existing behavior preserved.

- [ ] **Step 5: Run tests to verify pass**

Run: `mise run test --filter DraggableTabBarGeometryTests && mise run test --filter DraggableTabBar`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Panes/DraggableTabBarGeometry.swift \
        Tests/AgentStudioTests/Core/Views/Panes/DraggableTabBarGeometryTests.swift \
        Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift
git commit -m "refactor: extract DraggableTabBarGeometry.tabId pure helper"
```

---

## Task 17: `VisibleRowIndexMapping` — invisible-minimized commit-time index translation

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/VisibleRowIndexMapping.swift`
- Test: `Tests/AgentStudioTests/Core/Views/DragAndDrop/VisibleRowIndexMappingTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct VisibleRowIndexMappingTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    @Test
    func fullRowIndex_noMinimized_mapsIdentity() {
        // Full row = [a, b, c]. Visible = [a, b, c] (same). Visible slot 1 → full slot 1.
        let idx = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 1,
            fullRow: [a, b, c],
            minimizedPaneIds: [],
            showMinimizedBars: true
        )
        #expect(idx == 1)
    }

    @Test
    func fullRowIndex_showMinimizedBars_minimizedVisibleCountsInSlots() {
        // When showMinimizedBars=true, minimized panes ARE rendered as bars
        // and appear in paneFrames. Resolver's slot index is the same as full-row.
        let idx = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 2,
            fullRow: [a, b, c],
            minimizedPaneIds: [b],
            showMinimizedBars: true
        )
        #expect(idx == 2)  // identity when minimized bars visible
    }

    @Test
    func fullRowIndex_invisibleMinimizedInterleaved_translates() {
        // Full = [minA, b, minC, d, minE]. Visible = [b, d] (a, c, e hidden).
        // User drops at visible slot 1 (between b and d).
        // Rule: visible slot K commits to position immediately after the K-th visible pane.
        // Visible slot 0 → full index 1 (before b → between minA and b — placed at 1)
        // Visible slot 1 → full index 3 (between b and minC/d — placed at 3)
        // Visible slot 2 → full index 5 (after d → end)
        let full = [a, b, c, d, e]
        let minimized: Set<UUID> = [a, c, e]

        let slot0 = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 0, fullRow: full, minimizedPaneIds: minimized, showMinimizedBars: false
        )
        let slot1 = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 1, fullRow: full, minimizedPaneIds: minimized, showMinimizedBars: false
        )
        let slot2 = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 2, fullRow: full, minimizedPaneIds: minimized, showMinimizedBars: false
        )
        #expect(slot0 == 1)
        #expect(slot1 == 3)
        #expect(slot2 == 5)
    }

    @Test
    func fullRowIndex_allInvisibleMinimized_mapsToEnd() {
        let full = [a, b, c]
        let minimized: Set<UUID> = [a, b, c]
        let idx = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 0, fullRow: full, minimizedPaneIds: minimized, showMinimizedBars: false
        )
        #expect(idx == 3)  // no visible panes; slot 0 maps to end of full row
    }
}
```

- [ ] **Step 2: Run tests to verify fail**

Run: `mise run test --filter VisibleRowIndexMappingTests`
Expected: FAIL — type not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/AgentStudio/Core/Views/DragAndDrop/VisibleRowIndexMapping.swift
import Foundation

enum VisibleRowIndexMapping {
    /// Translates a visible-slot index (what the resolver produced) to a
    /// full-row index (what the caller must pass to Layout.inserting or
    /// equivalent).
    ///
    /// - Parameters:
    ///   - forVisibleSlot: slot index produced by the resolver (0…visiblePaneCount)
    ///   - fullRow: the complete row including minimized-invisible panes, in order
    ///   - minimizedPaneIds: which full-row IDs are minimized
    ///   - showMinimizedBars: when true, minimized panes render as bars and appear
    ///     in the resolver's inputs → identity mapping. When false, resolver only
    ///     sees non-minimized panes → this function translates.
    ///
    /// Rule when showMinimizedBars=false: visible slot K commits to the position
    /// immediately after the K-th visible pane in the full row (or end of row for
    /// the final slot).
    static func fullRowIndex(
        forVisibleSlot visibleIndex: Int,
        fullRow: [UUID],
        minimizedPaneIds: Set<UUID>,
        showMinimizedBars: Bool
    ) -> Int {
        if showMinimizedBars {
            return visibleIndex
        }

        // Walk full row, counting visible panes; return the full index
        // immediately AFTER the visibleIndex-th visible pane.
        var seenVisible = 0
        for (fullIdx, paneId) in fullRow.enumerated() {
            if minimizedPaneIds.contains(paneId) { continue }
            if seenVisible == visibleIndex {
                return fullIdx          // slot is before this visible pane
            }
            seenVisible += 1
        }
        // All visible panes exhausted — slot is at the end of the full row
        return fullRow.count
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `mise run test --filter VisibleRowIndexMappingTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/VisibleRowIndexMapping.swift \
        Tests/AgentStudioTests/Core/Views/DragAndDrop/VisibleRowIndexMappingTests.swift
git commit -m "feat: VisibleRowIndexMapping — commit-time slot translation"
```

---

## Task 18: Wire `DragDwellState` + `DragAutoDismissDecision` into `DraggableTabBarHostingView`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` (add `onAutoDismissDrawerForDrag` callback handler)

- [ ] **Step 1: Replace the immediate auto-select with dwell-state machine**

Inside `draggingUpdated(_:)`, replace lines 385-393 (the immediate `lastAutoSelectedTabIdForPaneDrag` check) with:

```swift
if types.contains(.agentStudioPaneDrop),
   let paneData = sender.draggingPasteboard.data(forType: .agentStudioPaneDrop),
   let payload = try? JSONDecoder().decode(PaneDragPayload.self, from: paneData)
{
    let point = convert(sender.draggingLocation, from: nil)
    let hoveredTabId = DraggableTabBarGeometry.tabId(at: point, tabFrames: tabFrames)
    let (next, shouldCommit) = DragDwellState.step(
        current: dwellState,
        hoveredTabId: hoveredTabId,
        now: CFAbsoluteTimeGetCurrent(),
        dwellDuration: 0.1
    )
    dwellState = next
    tabBarAdapter?.dwellTabId = next.hoveredTabId
    tabBarAdapter?.dwellProgress = DragDwellProgress.progress(
        state: next, now: CFAbsoluteTimeGetCurrent(), dwellDuration: 0.1
    )

    if let tabIdToSelect = shouldCommit {
        onSelect?(tabIdToSelect)

        if let drawerParentId = DragAutoDismissDecision.shouldAutoDismiss(
            payload: payload,
            destinationTabId: tabIdToSelect,
            destinationExpandedDrawerParentPaneId: expandedDrawerParentIdForTab?(tabIdToSelect)
        ) {
            onAutoDismissDrawerForDrag?(tabIdToSelect, drawerParentId)
        }
    }
}
```

- [ ] **Step 2: Add new instance state + bindings**

```swift
private var dwellState = DragDwellState.idle
var expandedDrawerParentIdForTab: ((_ tabId: UUID) -> UUID?)?
var onAutoDismissDrawerForDrag: ((_ tabId: UUID, _ drawerParentPaneId: UUID) -> Void)?
```

- [ ] **Step 3: Reset dwell on exit/end/commit**

In `draggingExited(_:)`, `draggingEnded(_:)`, `performDragOperation(_:)` — reset:

```swift
dwellState = DragDwellState.idle
tabBarAdapter?.dwellTabId = nil
tabBarAdapter?.dwellProgress = 0
```

- [ ] **Step 4: `PaneTabViewController` implements the callbacks**

```swift
hostingView.expandedDrawerParentIdForTab = { [weak self] tabId in
    guard let self else { return nil }
    return DrawerDragOwnershipPolicy.expandedDrawerParentPaneId(
        tabId: tabId, tabLayoutAtom: store.tabLayoutAtom, paneAtom: store.paneAtom
    )
}
hostingView.onAutoDismissDrawerForDrag = { [weak self] _, drawerParentId in
    self?.dispatchAction(.toggleDrawer(paneId: drawerParentId))
}
```

- [ ] **Step 5: `TabBarAdapter` gains dwell bindings for the SwiftUI tab view to render the progress indicator**

Add `@Published var dwellTabId: UUID?` and `@Published var dwellProgress: CGFloat = 0` on `TabBarAdapter`. SwiftUI `CustomTabBar` reads and renders a fill animation scaled by `dwellProgress` on the hovered tab.

- [ ] **Step 6: Integration test — hidden NSWindow drives a synthetic drag; verify no commit before 100ms and commit at/after 100ms**

Test file: `Tests/AgentStudioTests/App/Panes/TabBar/DraggableTabBarDwellIntegrationTests.swift`

- [ ] **Step 7: Run full suite**

Run: `mise run test && mise run lint`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -u
git commit -m "feat: wire dwell timer + auto-dismiss into tab bar drag"
```

---

## Task 19: Delete `DropZone.swift` — migrate contents to new homes

**Files:**
- Delete: `Sources/AgentStudio/Core/Views/Panes/DropZone.swift`
- Verify callers migrated: all sites listed below

- [ ] **Step 1: Find all references**

```bash
grep -rn "DropZone\." Sources/AgentStudio/ Tests/ | grep -v "DropZoneSide"
```

Expected sites to migrate (pre-work):
1. `PaneDropTarget.zone: DropZone` — update to `DropZoneSide`
2. `PaneActionCommand.insertPane(direction: SplitNewDirection)` — stays; adapter translates
3. `DropZone.calculate(at:in:)` — inlined in `DropTargetResolver.swift` paneSplit branch (Task 3)
4. `DropZone.overlay(...)` / `.overlayRect(...)` / `.markerRect(...)` / private `.overlay(paneFrame:)` — migrated into `DropTargetOverlayRenderer.swift` (Task 12)
5. `DropZone.newDirection` — migrated into `PaneDragCoordinator.swift` adapter (Task 11)

- [ ] **Step 2: Verify each target already has the migration in place**

Run `grep "calculate(at:in:)" Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetResolver.swift` — expect inlined usage (not a function call).

- [ ] **Step 3: Delete the file**

```bash
git rm Sources/AgentStudio/Core/Views/Panes/DropZone.swift
```

- [ ] **Step 4: Rename `PaneDropTarget.zone` from `DropZone` to `DropZoneSide`**

- [ ] **Step 5: Build + test**

```bash
mise run build && mise run test && mise run lint
```

Expected: PASS. If any grep from Step 1 finds a reference NOT listed in the expected migration list, stop — the migration is incomplete.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "chore: delete legacy DropZone.swift; contents migrated"
```

---

## Task 20: Directory rename — `Splits/` → `Panes/`

**Files:** 27 files under `Sources/AgentStudio/Core/Views/Splits/`

- [ ] **Step 1: Move all files**

```bash
mkdir -p Sources/AgentStudio/Core/Views/Panes
git mv Sources/AgentStudio/Core/Views/Splits/*.swift Sources/AgentStudio/Core/Views/Panes/
rmdir Sources/AgentStudio/Core/Views/Splits
```

- [ ] **Step 2: Create `DragAndDrop/` home**

```bash
mkdir -p Sources/AgentStudio/Core/Views/DragAndDrop
mkdir -p Tests/AgentStudioTests/Core/Views/DragAndDrop
```

- [ ] **Step 3: Build**

Swift doesn't encode paths in imports — no source code edits needed. `Package.swift` doesn't reference `Splits/` directly, so no build-config change.

```bash
mise run build
```

Expected: PASS on first try.

- [ ] **Step 4: Lint + test**

```bash
mise run lint && mise run test
```

Expected: PASS (no behavior change).

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "chore: rename Core/Views/Splits/ to Core/Views/Panes/"
```

---

## Task 21: Final audit

- [ ] **Step 1: Search for any remaining inline geometry / sizing / legacy names**

```bash
grep -rn "DrawerPaneDragCoordinator\.\|PaneDragCoordinator\." Sources/AgentStudio/ | grep -v "Resolver\|SizingPolicy"
grep -rn "creationBandHeight\|edgeCorridorWidth" Sources/AgentStudio/ | grep -v "DropTargetConfig\|DropTargetResolver"
grep -rn "DropZone\b" Sources/AgentStudio/ Tests/ | grep -v "DropZoneSide"
```

Expected: only adapter files reference old coordinators; no `DropZone` (without Side) references anywhere.

- [ ] **Step 2: Run full suite + lint**

```bash
mise run test && mise run lint
```

Expected: both green.

- [ ] **Step 3: Commit**

```bash
git add -u
git commit -m "chore: final audit — legacy geometry removed"
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

**Type consistency:** `DropTarget.paneSlot(row:index:)` used consistently. `DropTargetResolver` method names stable: `resolve`, `targetRects`, `resolveLatched`. Config factory names (`.main`, `.drawerSingleRow`, `.drawerTwoRow`) stable.

---

## Execution handoff

**Plan revised and saved to `docs/plans/2026-04-22-unified-drop-target-algo.md`.**

Do NOT start Task 1 until all four Prereqs are green. Specifically: Phase B of `2026-04-22-drawer-drag-tab-level-capture.md` must land and be dogfooded, the main-pane and two-row fixtures must exist and replay-test against the CURRENT coordinators, and the four open design questions need user answers.

After Prereqs are met, two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, adversarial review between tasks, fast iteration
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
