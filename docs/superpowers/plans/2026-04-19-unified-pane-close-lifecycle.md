# Unified Pane Close Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The plan is structured in **two implementation phases** that share a single PR. Each phase has its own verification checkpoint — `mise run test` must pass cleanly at the Phase 1 boundary before Phase 2 begins.

**Goal:** Make pane closing safe during SwiftUI's close-transition frame, and collapse the three current close verbs (`.closePane`, `.closeTab`, `.removeDrawerPane`) into one structural primitive with undo that recreates the tab when the last pane closes.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, `Testing`, `@Observable`, Ghostty terminal surfaces

---

## Why This Exists

This plan is grounded in the crash investigation in:

- `docs/superpowers/debugging/2026-04-19-last-drawer-pane-crash.md`

That note established three facts:

1. The drawer-empty focus state is already correct.
2. The remaining crash is a stale `ViewRegistry.slot(for:)` read during SwiftUI's close-transition frame, hitting the lazy-fallback `assertionFailure`.
3. `.closePane`, `.closeTab`, and `.removeDrawerPane` encode three different close meanings for one user gesture.

This plan incorporates findings from three rounds of adversarial Codex review. Nine material issues were surfaced and are resolved by the design below:

- **Drawer-close UX bypassed the unified pipeline.** `DrawerPanel.swift:119-120` rewrote `.closePane` → `.removeDrawerPane` at dispatch time, so real drawer close never reached `executeClosePane`. Resolved in Phase 2 Task 2.1.
- **Parent-pane close hard-deleted drawer-child slots during the transition window.** An expanded drawer under a closing parent hit the same stale-slot race. Resolved in Phase 1 Task 1.3.
- **A global `retiredPaneIds` gated against a per-surface `renderedIds` re-created the exact race class.** Drawer surface could finalize a slot still being rendered by the main strip. Resolved by the surface-scoped design in Phase 1 Task 1.2.
- **Zoomed and all-minimized render modes bypassed the lifecycle hooks entirely.** Closes from those branches would leak tombstones forever. Resolved by container-level registration in Phase 1 Task 1.2.
- **Per-branch surface registration reintroduced the race at branch-switch boundaries.** The earlier iteration registered a separate surface per branch (zoomed / all-minimized / main-strip); SwiftUI's `.onDisappear`/`.onAppear` are not transactional at branch switches, so the old branch could unregister and trigger finalization in the gap before the new branch published. Resolved by moving registration up to `FlatTabStripContainer` — one stable surface per tab, whose published id set changes with mode but whose registration lifetime matches the tab.
- **Task 3's unit tests used `ensureSlot` as the observation probe, which per D6 promotes retired slots in place.** The tests could pass while the union finalization logic was silently broken. Resolved with non-promoting DEBUG probes (`peekSlotForTesting`, `isRetiredForTesting`).
- **`closeDrawerPane` command path bypassed the unified pipeline.** `PaneTabViewController.swift:1839-1847` dispatches `.removeDrawerPane` directly for command-bar/menu drawer close. Resolved in Phase 2 Task 2.1.
- **Drawer-child process termination bypassed the unified pipeline.** `PaneTabViewController.swift:1634-1639` dispatches `.removeDrawerPane` directly when a drawer-child terminal process dies. Phase 1 makes this crash-safe (since `.removeDrawerPane` case retires slot); Phase 2 routes it through `.closePane` for undo coverage.
- **`Set(minimizedPaneIds)` publication leaked tombstones when minimized bars are hidden.** `FlatTabStripContainer.swift:74-75` only renders bars when `showMinimizedBars == true`; when false, the proposed surface would claim ids that are not rendered anywhere, pinning retired slots forever. Resolved in Phase 1 Task 1.2 by deriving `renderedTabIds` from what's actually rendered.

The plan also rationalizes D6 (promote-in-place on revive): the original justification was "observer continuity," which is defeated by `FlatPaneStripContent.swift:75`'s `.id("\(uuid)-registered=\(host != nil)")` strategy that remounts the subtree when `host` toggles. The real benefit of tombstones is **making `slot(for:)` safe against the stale transition-frame read** — no lazy fallback, no `assertionFailure`. Promote-in-place is kept as a minor allocation optimization on undo revive, nothing more.

D9 is softened: calling `retireSlot` adjacent to teardown does not give SwiftUI a "head start" — both mutations land in the same `@MainActor` turn. The ordering is kept for debugging-readable call order, not as a correctness property.

D14 is added in Phase 2: `executeClosePane` must snapshot an emptying close as a `TabCloseSnapshot` **regardless of active-tab state**. The earlier draft copied the existing active-tab guard, which silently regressed auto-close of process-terminated panes in background tabs (they used to produce tab undo via validator canonicalization; under the unified path with that guard, they would produce nothing).

---

## Design Decisions

| # | Decision | Phase | Reason |
|---|----------|-------|--------|
| D1 | Validator stops canonicalizing `.closePane` → `.closeTab`. `.closePane` stays `.closePane`. | 2 | Canonicalization hides the coordinator's actual job. |
| D2 | Coordinator decides snapshot shape inside `executeClosePane`: if this close empties the tab, take a `TabCloseSnapshot`; otherwise take a `PaneCloseSnapshot`. | 2 | Preserves tab undo fidelity (arrangements, name, zoom) without validator-layer rewriting. |
| D3 | `.closeTab` (whole-tab user action) keeps its existing path. `executeCloseTab` is untouched. | 2 | Whole-tab close has always taken a tab snapshot; scope the unification to `.closePane`. |
| D4 | Drawer-child close keeps its full focus ladder. `executeClosePane` delegates to the `.removeDrawerPane` coordinator case for drawer children. | 2 | The focus ladder is load-bearing; delegation keeps it in one place. |
| D5 | `ViewRegistry` splits `removeSlot` (immediate delete, unchanged) from `retireSlot` (opt-in tombstone). Only close-transition-driven paths retire. | 1 | Prevents tombstones from leaking at 10+ non-transition call sites. |
| D6 | `ensureSlot` on a retired id promotes the tombstone in place. | 1 | Minor allocation savings on undo revive. Observer continuity is NOT the reason — `FlatPaneStripContent.swift:75` remounts on `host != nil` toggle regardless of slot identity. |
| D7 | Finalization is causal, not timer-driven. Each render surface publishes its rendered pane ids; a retired slot is finalized only when absent from the union of all surfaces' published ids. | 1 | Surface-scoped gating: a tombstone cannot be deleted while any surface is still rendering it. |
| D7.1 | Surface registration lives at the **container level** (`"tab:\(tabId)"` from `FlatTabStripContainer`, `"drawerShell:\(parentPaneId)"` from `DrawerPanel`). Mode switches update the *contents* of the published id set, not the registration itself. | 1 | SwiftUI's `.onAppear`/`.onDisappear` are not transactional at branch boundaries. Per-branch registration created a gap where unregister-before-reregister triggered finalization with an empty union. |
| D7.2 | The published id set is derived from **what is actually rendered**, not what is conceptually active. In the all-minimized branch, publish `minimizedPaneIds` only when `showMinimizedBars == true`; publish the empty set when bars are hidden. | 1 | `FlatTabStripContainer.swift:74-75` skips rendering bars when `showMinimizedBars == false`. Claiming ids that have no views would pin tombstones forever. |
| D8 | Surface registration and lifecycle methods live on `ViewRegistry` directly. No new monitor class. | 1 | `ApplicationLifecycleMonitor` earns its class because `NSNotificationCenter` needs observer-retain machinery to isolate; SwiftUI closures have no such machinery. |
| D9 | `retireSlot` is called inside `performClose`, adjacent to `teardownView`. | 1, 2 | Ordering hygiene for call-site readability. Both mutations land in the same `@MainActor` turn; this is NOT a head-start race. |
| D10 | `PaneCloseTransitionCoordinator` gets `cancelCloseTransition(paneId:)`. `undoCloseTab` calls it for every paneId in the snapshot before restoring. | 1 | Prevents a pending `performClose` from firing after undo has already restored the pane. |
| D11 | Drawer close UX dispatches `.closePane`, not `.removeDrawerPane`. `.removeDrawerPane` becomes an internal coordinator action only. This covers `DrawerPanel` leaf dispatch, `AppCommand.closeDrawerPane`, and `handleTerminalProcessTerminated`'s drawer-child branch. | 2 | One structural primitive at every UI entry point. Also makes drawer close undoable for the first time across all drawer-close trigger points. |
| D12 | `executeClosePane`'s main-pane branch retires drawer-child slots (not `removeSlot`s them) when a parent pane with an expanded drawer is closed. The existing `.removeDrawerPane` case also retires. | 1 | Drawer children render through the same `slot(for:)` path; they need tombstone protection during the same transition frame. |
| D13 | `ViewRegistry` exposes DEBUG-only `peekSlotForTesting(_:)` and `isRetiredForTesting(_:)` probes that neither promote nor create slots. Tests use these instead of `ensureSlot`. | 1 | `ensureSlot` per D6 promotes retired slots in place, which mutates the thing we are trying to observe. Using `ensureSlot` as a probe silently masks broken union logic. |
| D14 | `executeClosePane` takes a `TabCloseSnapshot` whenever the close empties the tab, **regardless of active-tab state**. The existing `shouldCreateUndoEntry` active-tab guard continues to gate pane-only snapshots only. | 2 | Under the earlier draft, auto-close of a single-pane background tab (process termination) went from validator-canonicalized `.closeTab` (tab snapshot) to plain `.closePane` with `shouldCreateUndoEntry = false` — zero undo entry. This restores undo coverage for that path. |

---

## Current Code References

- `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
- `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- `Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift`
- `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`

---

## Spec

### Close semantics after both phases

```text
closePane(tabId, paneId)                              -- one entry point for every UI
  -> decide undo snapshot shape:
       pane is drawer child               -> PaneCloseSnapshot
       closing empties the tab (active or background) -> TabCloseSnapshot
       else                               -> PaneCloseSnapshot
  -> drawer child:
       delegate to .removeDrawerPane case (focus ladder)
  -> main pane:
       teardown view + runtime
       retire pane slot
       retire drawer-child slots (if any)
       remove pane from layout
       remove pane from store if no longer owned
       if tab is now empty: remove tab
       post-removal focus reconciliation
```

### Slot lifecycle

```text
register(host, paneId)            = pane has a live PaneHostView
unregister(paneId)                = slot survives with host = nil
removeSlot(paneId)                = immediate delete (non-transition callers)
retireSlot(paneId)                = tombstone; slot.host = nil; slot survives
                                    until finalization
finalizeRetiredSlotRemoval(paneId)
                                  = retired slot is physically deleted
ensureSlot(paneId)                = creates fresh slot if missing;
                                    promotes retired slot in place if found retired;
                                    returns existing live slot otherwise
```

### Surface registration

Two kinds of surfaces. Registration lifetime = container lifetime. Mode switches change the published id set, not the registration.

- **`"tab:\(tabId)"`** — `FlatTabStripContainer`. The published id set is computed from the active render mode:
  - zoomed → `[zoomedPaneId]`
  - all-minimized with bars visible → `Set(minimizedPaneIds)`
  - all-minimized with bars hidden → `[]` (empty)
  - main-strip → `Set(metrics.paneSegments.map(\.paneId))`
- **`"drawerShell:\(parentPaneId)"`** — `DrawerPanel`. Published id set is `Set(drawer.paneIds)`.

```text
surfaceRenderedIds(surfaceId, ids:)
  = called when a surface's rendered id set changes
  = finalizes any retired id not present in the union of all surfaces' ids

unregisterSurface(surfaceId)
  = called when a surface unmounts (its container goes away)
  = removes the surface from the registration map and re-runs finalization
```

### What must stop by end of Phase 2

```text
1. Validator canonicalizing `.closePane` into `.closeTab`.
2. UI entry points pre-switching on tab pane count to choose between
   .closePane and .closeTab.
3. Drawer UI rewriting .closePane into .removeDrawerPane at dispatch.
4. Command-bar / menu dispatching .removeDrawerPane directly.
5. Process-termination dispatching .removeDrawerPane directly for drawer
   children.
6. Hard-deleting slots (via removeSlot) on the close-transition code path.
7. Finalizing a retired slot based on one surface's rendered ids while
   another surface is still rendering it.
8. Publishing ids that aren't actually rendered (e.g., minimized ids when
   minimized bars are hidden).
9. A pending close-transition task firing performClose after undo.
10. executeClosePane skipping the undo snapshot when closing a single-pane
    background tab.
```

---

## Phase Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 1 — Stale-slot crash fix                                         │
│                                                                        │
│ Adds tombstone infrastructure and wires it at existing close sites.    │
│ NO semantic changes: the three close verbs still exist. UI dispatch    │
│ sites, validator, and DrawerPanel passthrough are untouched.           │
│                                                                        │
│ Result: crash gone. Undo behavior unchanged from today.                │
│                                                                        │
│ Checkpoint: mise run lint && mise run test pass cleanly.               │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 2 — Semantic unification                                         │
│                                                                        │
│ Collapses the three close verbs into one .closePane primitive at all   │
│ UI entry points. Coordinator decides undo snapshot shape. Drawer close │
│ becomes undoable. Fixes the inactive-tab snapshot regression.          │
│                                                                        │
│ Depends on: Phase 1's tombstone infrastructure.                        │
│                                                                        │
│ Checkpoint: mise run lint && mise run test pass cleanly.               │
└────────────────────────────────────────────────────────────────────────┘
```

Both phases land in one PR. Commit each task separately so `git bisect` works if regressions appear later. The Phase 1 → Phase 2 boundary is a verified-green commit.

---

## Phase 1: Stale-slot crash fix

### Task 1.1: Add tombstone infrastructure to `ViewRegistry`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/PaneContentWiringTests.swift`

**Why:** The stale `slot(for:)` crash happens because SwiftUI renders one more transition frame reading the removed paneId after structural removal. The fix is to keep the slot object alive through the transition as a tombstone (`host = nil`) and finalize it only when no render surface is still rendering it. This task adds `retireSlot` / `finalizeRetiredSlotRemoval`, the surface registration machinery (`surfaceRenderedIds`, `unregisterSurface`), and DEBUG-only non-promoting test probes. Promote-in-place for `ensureSlot` on a retired id is included for allocation savings on undo revive.

- [ ] **Step 1: Failing regression — retire keeps slot readable until finalized**

```swift
@Test("retireSlot keeps the same slot readable until finalized")
func viewRegistry_retireSlot_keepsSameSlotUntilFinalized() {
    let registry = ViewRegistry()
    let paneId = UUID()

    let live = registry.ensureSlot(for: paneId)
    registry.retireSlot(for: paneId)

    let retired = registry.slot(for: paneId)
    #expect(retired === live)
    #expect(retired.host == nil)

    registry.finalizeRetiredSlotRemoval(for: paneId)

    let recreated = registry.ensureSlot(for: paneId)
    #expect(recreated !== live)
}
```

- [ ] **Step 2: Failing regression — `removeSlot` keeps immediate-delete semantics**

```swift
@Test("removeSlot immediately deletes the slot (non-transition call sites)")
func viewRegistry_removeSlot_deletesImmediately() {
    let registry = ViewRegistry()
    let paneId = UUID()

    let original = registry.ensureSlot(for: paneId)
    registry.removeSlot(for: paneId)

    let recreated = registry.ensureSlot(for: paneId)
    #expect(recreated !== original)
}
```

- [ ] **Step 3: Failing regression — `ensureSlot` promotes a retired slot in place**

```swift
@Test("ensureSlot on a retired slot promotes it in place (D6)")
func viewRegistry_ensureSlot_promotesRetiredInPlace() {
    let registry = ViewRegistry()
    let paneId = UUID()

    let original = registry.ensureSlot(for: paneId)
    registry.retireSlot(for: paneId)

    let promoted = registry.ensureSlot(for: paneId)
    #expect(promoted === original)
}
```

- [ ] **Step 4: Failing regression — surface-scoped finalization (D7)**

Uses the non-promoting probes `peekSlotForTesting` and `isRetiredForTesting` instead of `ensureSlot`. Using `ensureSlot` as the probe would clear the retired flag and silently mask a broken union check.

```swift
@Test("a retired slot is finalized only when no surface renders it")
func viewRegistry_retiredSlot_requiresUnionAbsence() {
    let registry = ViewRegistry()
    let paneId = UUID()
    let originalSlot = registry.ensureSlot(for: paneId)

    registry.surfaceRenderedIds("tab:tab1", ids: [paneId])
    registry.surfaceRenderedIds("drawerShell:parent1", ids: [])
    registry.retireSlot(for: paneId)

    registry.surfaceRenderedIds("drawerShell:parent1", ids: [])
    #expect(registry.isRetiredForTesting(paneId) == true)
    #expect(registry.peekSlotForTesting(paneId) === originalSlot)

    registry.surfaceRenderedIds("tab:tab1", ids: [])
    #expect(registry.isRetiredForTesting(paneId) == false)
    #expect(registry.peekSlotForTesting(paneId) == nil)
}
```

- [ ] **Step 5: Failing regression — `unregisterSurface` triggers a finalization re-check**

```swift
@Test("unregisterSurface re-runs finalization for ids no longer rendered anywhere")
func viewRegistry_unregisterSurface_finalizesOrphanedRetired() {
    let registry = ViewRegistry()
    let paneId = UUID()
    let originalSlot = registry.ensureSlot(for: paneId)

    registry.surfaceRenderedIds("tab:tab1", ids: [paneId])
    registry.retireSlot(for: paneId)

    #expect(registry.isRetiredForTesting(paneId) == true)
    #expect(registry.peekSlotForTesting(paneId) === originalSlot)

    registry.unregisterSurface("tab:tab1")
    #expect(registry.isRetiredForTesting(paneId) == false)
    #expect(registry.peekSlotForTesting(paneId) == nil)
}
```

- [ ] **Step 6: Failing regression — container-level publication survives mode switches without transient finalization (D7.1)**

```swift
@Test("container-level surface survives render-mode switches without finalizing tombstones")
func viewRegistry_containerSurface_modeSwitch_doesNotFinalize() {
    let registry = ViewRegistry()
    let zoomedPaneId = UUID()
    let otherPaneId = UUID()
    let zoomedSlot = registry.ensureSlot(for: zoomedPaneId)
    _ = registry.ensureSlot(for: otherPaneId)

    registry.surfaceRenderedIds("tab:tab1", ids: [zoomedPaneId, otherPaneId])
    registry.retireSlot(for: otherPaneId)

    // Mode switch: same surface id, new id set that drops otherPaneId.
    // otherPaneId was retired and is now absent from any surface → finalize.
    // zoomedPaneId's slot must survive.
    registry.surfaceRenderedIds("tab:tab1", ids: [zoomedPaneId])
    #expect(registry.peekSlotForTesting(zoomedPaneId) === zoomedSlot)
    #expect(registry.isRetiredForTesting(otherPaneId) == false)
    #expect(registry.peekSlotForTesting(otherPaneId) == nil)
}
```

- [ ] **Step 7: Run the focused registry tests and verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneContentWiringTests'
```

- [ ] **Step 8: Extend `ViewRegistry`**

In `ViewRegistry.swift`, add state and methods:

```swift
private var slots: [UUID: PaneViewSlot] = [:]
private var retiredPaneIds: Set<UUID> = []
private var renderedIdsBySurface: [String: Set<UUID>] = [:]

@discardableResult
func ensureSlot(for paneId: UUID) -> PaneViewSlot {
    if let existing = slots[paneId] {
        if retiredPaneIds.contains(paneId) {
            retiredPaneIds.remove(paneId)
        }
        return existing
    }
    let slot = PaneViewSlot()
    slots[paneId] = slot
    return slot
}

/// Retire the slot: keep the object alive with host = nil so SwiftUI's
/// transition frame can safely complete its final read. The slot is physically
/// removed only when no render surface publishes the id in its rendered set.
func retireSlot(for paneId: UUID) {
    guard let slot = slots[paneId] else { return }
    slot.host = nil
    retiredPaneIds.insert(paneId)
}

/// Promote a retired slot to physically deleted. Idempotent.
func finalizeRetiredSlotRemoval(for paneId: UUID) {
    guard retiredPaneIds.remove(paneId) != nil else { return }
    slots.removeValue(forKey: paneId)
}

/// Immediate slot deletion. Used by non-transition call sites (rollback on
/// failed creation, undo expiration GC, orphan purge, undo-restore cleanup).
func removeSlot(for paneId: UUID) {
    retiredPaneIds.remove(paneId)
    slots.removeValue(forKey: paneId)
}

// MARK: - Surface registration

func surfaceRenderedIds(_ surfaceId: String, ids: Set<UUID>) {
    let previous = renderedIdsBySurface[surfaceId]
    guard previous != ids else { return }
    renderedIdsBySurface[surfaceId] = ids
    finalizeRetiredSlotsNotRenderedByAnySurface()
}

func unregisterSurface(_ surfaceId: String) {
    guard renderedIdsBySurface.removeValue(forKey: surfaceId) != nil else { return }
    finalizeRetiredSlotsNotRenderedByAnySurface()
}

private func finalizeRetiredSlotsNotRenderedByAnySurface() {
    guard !retiredPaneIds.isEmpty else { return }
    var union: Set<UUID> = []
    for surfaceIds in renderedIdsBySurface.values {
        union.formUnion(surfaceIds)
    }
    let toFinalize = retiredPaneIds.subtracting(union)
    for paneId in toFinalize {
        finalizeRetiredSlotRemoval(for: paneId)
    }
}

#if DEBUG
    // D13: non-promoting, non-creating test probes.
    func peekSlotForTesting(_ paneId: UUID) -> PaneViewSlot? {
        slots[paneId]
    }

    func isRetiredForTesting(_ paneId: UUID) -> Bool {
        retiredPaneIds.contains(paneId)
    }
#endif
```

- [ ] **Step 9: Re-run the focused tests**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneContentWiringTests'
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add \
  Sources/AgentStudio/App/Panes/ViewRegistry.swift \
  Tests/AgentStudioTests/Core/Stores/PaneContentWiringTests.swift
git commit -F - <<'EOF'
feat: tombstone lifecycle + surface-scoped finalization in ViewRegistry (phase 1/1)

- retireSlot / finalizeRetiredSlotRemoval / surfaceRenderedIds /
  unregisterSurface added.
- ensureSlot promotes retired slots in place (D6).
- removeSlot keeps immediate-delete semantics (D5) for non-transition
  call sites.
- DEBUG-only peekSlotForTesting / isRetiredForTesting probes (D13)
  for tests that observe tombstone state without promoting it.

Nothing calls retireSlot yet. Wired in the next task.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 1.2: Wire container-level surface registration

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`

**Why:** The tombstone infrastructure from Task 1.1 needs callers. Surfaces publish what they are rendering so the union check can finalize tombstones only when no surface claims the id. Registration lives at the container level (D7.1) so SwiftUI's non-transactional `.onAppear`/`.onDisappear` at branch boundaries cannot create a finalization gap. The published id set is derived from **what is actually rendered** (D7.2) — critically, the all-minimized branch must publish an empty set when `showMinimizedBars == false`.

- [ ] **Step 1: Wire the tab-level surface in `FlatTabStripContainer`**

Compute the rendered id set at the top of the body (outside the `if / else if / else` branch switch):

```swift
let tabSurfaceId = "tab:\(tabId)"

let renderedTabIds: Set<UUID> = {
    if let zoomedPaneId {
        return [zoomedPaneId]
    } else if metrics.allMinimized {
        // D7.2: only publish ids that are actually rendered. Bars hidden → no views.
        return showMinimizedBars ? Set(layout.paneIds) : []
    } else {
        return Set(metrics.paneSegments.map(\.paneId))
    }
}()
```

Attach the lifecycle hooks to the container body:

```swift
containerBody
    .onAppear {
        viewRegistry.surfaceRenderedIds(tabSurfaceId, ids: renderedTabIds)
    }
    .onChange(of: renderedTabIds) { _, newIds in
        viewRegistry.surfaceRenderedIds(tabSurfaceId, ids: newIds)
    }
    .onDisappear {
        viewRegistry.unregisterSurface(tabSurfaceId)
    }
```

Mode switches (zoomed ↔ all-minimized ↔ main-strip) update `renderedTabIds`, which triggers `.onChange` with the same `tabSurfaceId`. The registration is never toggled.

- [ ] **Step 2: Wire the drawer-shell surface in `DrawerPanel`**

```swift
let drawerSurfaceId = "drawerShell:\(parentPaneId)"
let renderedDrawerIds: Set<UUID> = Set(drawer.paneIds)

drawerShellBody
    .onAppear {
        viewRegistry.surfaceRenderedIds(drawerSurfaceId, ids: renderedDrawerIds)
    }
    .onChange(of: renderedDrawerIds) { _, newIds in
        viewRegistry.surfaceRenderedIds(drawerSurfaceId, ids: newIds)
    }
    .onDisappear {
        viewRegistry.unregisterSurface(drawerSurfaceId)
    }
```

- [ ] **Step 3: Commit**

```bash
git add \
  Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift
git commit -F - <<'EOF'
feat: container-level surface registration for ViewRegistry finalization (phase 1/2)

- FlatTabStripContainer publishes "tab:\(tabId)" from a single body-
  level lifecycle hook. The published id set derives from the active
  render mode. Mode switches update the publication, not the surface
  registration (D7.1).
- all-minimized branch publishes the empty set when bars are hidden
  (D7.2) so retired slots in that state can finalize.
- DrawerPanel publishes "drawerShell:\(parentPaneId)" as a separate
  surface from its own container tree.

No close sites retire yet. Wired in the next task.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 1.3: Retire slots at existing close sites (no semantic changes)

**Files:**
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`

**Why:** This is the task that actually makes the crash go away. Existing close sites currently call `viewRegistry.removeSlot(for:)` — immediate delete. Replace with `retireSlot(for:)` at the two transition-driven sites: `executeClosePane`'s main-pane path (including its drawer-child cleanup loop) and the `.removeDrawerPane` coordinator case. Every other `removeSlot` caller stays unchanged (D5) because those are rollback / undo GC / orphan purge paths that have no concurrent SwiftUI transition.

Because this task makes no semantic changes (validator, dispatch sites, and snapshot-shape decisions are all untouched), all existing tests should continue to pass. The regression test added below pins the tombstone behavior.

- [ ] **Step 1: Failing regression — closing a main pane with drawer children retires the child slots (not deletes them)**

```swift
@Test("closing a main pane with drawer children retires child slots so drawer panel renders safely during transition")
func closeMainPane_withDrawerChildren_retiresChildSlots() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let child = try #require(harness.store.addDrawerPane(to: parent.id))
    _ = harness.viewRegistry.ensureSlot(for: parent.id)
    _ = harness.viewRegistry.ensureSlot(for: child.id)

    // Phase 1 still goes through the current close path (including the
    // validator's canonicalization of single-pane tabs to .closeTab). To
    // isolate the retire behavior, drive the main-pane close via the
    // coordinator directly with a non-canonicalized closePane call for a
    // multi-pane test state.
    let sibling = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Sibling"))
    harness.store.insertPane(sibling.id, inTab: tab.id, at: parent.id, direction: .horizontal, position: .after)

    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: parent.id))

    // Parent slot must be retired, not deleted, while the drawer surface
    // may still be rendering during the transition frame.
    #expect(harness.viewRegistry.isRetiredForTesting(parent.id))
    #expect(harness.viewRegistry.isRetiredForTesting(child.id))
    #expect(harness.viewRegistry.peekSlotForTesting(parent.id) != nil)
    #expect(harness.viewRegistry.peekSlotForTesting(child.id) != nil)
}
```

- [ ] **Step 2: Failing regression — `.removeDrawerPane` retires the drawer child slot**

```swift
@Test(".removeDrawerPane retires the slot rather than deleting it immediately")
func removeDrawerPane_retiresSlot() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let child = try #require(harness.store.addDrawerPane(to: parent.id))
    _ = harness.viewRegistry.ensureSlot(for: child.id)

    harness.coordinator.execute(.removeDrawerPane(parentPaneId: parent.id, drawerPaneId: child.id))

    #expect(harness.viewRegistry.isRetiredForTesting(child.id))
    #expect(harness.viewRegistry.peekSlotForTesting(child.id) != nil)
}
```

- [ ] **Step 3: Run focused coordinator tests and verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCoordinatorHardeningTests'
```

- [ ] **Step 4: Change `removeSlot` → `retireSlot` at the two close-transition sites**

In `PaneCoordinator+ActionExecution.swift`:

**Site A — `executeClosePane` main-pane path.** Locate the two calls to `viewRegistry.removeSlot` inside `executeClosePane` (one in the drawer-children cleanup loop, one for the closing pane itself) and replace both with `viewRegistry.retireSlot`:

```swift
// Before (two sites):
//   viewRegistry.removeSlot(for: drawerPaneId)  (inside the drawer-children loop)
//   viewRegistry.removeSlot(for: paneId)         (at the end, after ownership check)
// After:
//   viewRegistry.retireSlot(for: drawerPaneId)
//   viewRegistry.retireSlot(for: paneId)
```

**Site B — `.removeDrawerPane` case** inside the big `execute(_:)` switch. Change:

```swift
viewRegistry.removeSlot(for: drawerPaneId)
```

to:

```swift
viewRegistry.retireSlot(for: drawerPaneId)
```

Do not touch any other `viewRegistry.removeSlot` call sites. Those are rollback / undo GC / orphan purge paths and must stay immediate-delete (D5).

- [ ] **Step 5: Re-run focused coordinator tests**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCoordinatorHardeningTests'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift
git commit -F - <<'EOF'
fix: retire slots (not remove) at close-transition sites (phase 1/3)

- executeClosePane main-pane path retires the closing pane slot and
  every drawer-child slot (D12).
- .removeDrawerPane case retires the drawer child slot.
- All other removeSlot call sites (rollback, undo GC, orphan purge,
  undo-restore cleanup) stay unchanged per D5.

This is the commit that actually closes the ViewRegistry.slot(for:)
lazy-fallback crash window. The tombstones are bounded by the
surface-scoped finalization wired in Task 1.2.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 1.4: Cancel pending close transitions on undo

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
- Test: `Tests/AgentStudioTests/App/Panes/PaneCloseTransitionCoordinatorTests.swift`

**Why:** `PaneCloseTransitionCoordinator.beginClosingPane` schedules a task that fires `performClose` after the animation delay. If the user hits ⌘Z inside the animation window, today nothing cancels that task. After undo restores the pane, the pending `performClose` fires and closes it a second time — a ghost close. The tombstone lifecycle does not fix this; it only makes the stale read safe. Undo must explicitly cancel any pending transitions for the paneIds it is restoring.

- [ ] **Step 1: Failing regression — `cancelCloseTransition` prevents `performClose` from firing**

```swift
@Test("cancelCloseTransition stops the pending performClose")
func paneCloseTransitionCoordinator_cancel_stopsPerformClose() async {
    let clock = TestPushClock()
    let coordinator = PaneCloseTransitionCoordinator(clock: clock)
    let paneId = UUID()
    var performCloseRan = false

    coordinator.beginClosingPane(paneId, delay: .milliseconds(120)) {
        performCloseRan = true
    }

    await clock.waitForPendingSleepCount()
    coordinator.cancelCloseTransition(paneId)
    clock.advance(by: .milliseconds(120))
    for _ in 0..<5 { await Task.yield() }

    #expect(performCloseRan == false)
    #expect(coordinator.closingPaneIds.contains(paneId) == false)
}
```

- [ ] **Step 2: Run test and verify fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCloseTransitionCoordinatorTests/paneCloseTransitionCoordinator_cancel_stopsPerformClose'
```

- [ ] **Step 3: Add `cancelCloseTransition` to `PaneCloseTransitionCoordinator`**

```swift
/// Cancel any pending close transition for the given pane id.
/// Used by undo to prevent a scheduled performClose from firing after
/// the pane has already been restored.
func cancelCloseTransition(_ paneId: UUID) {
    guard let task = pendingCloseTasks.removeValue(forKey: paneId) else { return }
    task.cancel()
    closingPaneIds.remove(paneId)
}
```

- [ ] **Step 4: Call `cancelCloseTransition` from the undo path**

In `PaneCoordinator+Undo.swift`'s `undoCloseTab()`, cancel pending transitions for every paneId in the snapshot before restoring:

```swift
func undoCloseTab() {
    while let entry = popLastUndoEntry() {
        switch entry {
        case .tab(let snapshot):
            for pane in snapshot.panes {
                closeTransitionCoordinator.cancelCloseTransition(pane.id)
            }
            undoTabClose(snapshot)
            return

        case .pane(let snapshot):
            guard store.tabLayoutAtom.tab(snapshot.tabId) != nil else {
                Self.logger.info("undoClose: tab \(snapshot.tabId) gone — skipping pane entry")
                continue
            }
            if snapshot.pane.isDrawerChild,
                let parentId = snapshot.anchorPaneId,
                store.paneAtom.pane(parentId) == nil
            {
                Self.logger.info("undoClose: parent pane \(parentId) gone — skipping drawer child entry")
                continue
            }
            closeTransitionCoordinator.cancelCloseTransition(snapshot.pane.id)
            for child in snapshot.drawerChildPanes {
                closeTransitionCoordinator.cancelCloseTransition(child.id)
            }
            undoPaneClose(snapshot)
            return
        }
    }
    Self.logger.info("No entries to restore from undo stack")
}
```

If `PaneCoordinator` does not already hold a reference to `closeTransitionCoordinator`, thread it through the initializer the same way `PaneTabViewController` receives it.

- [ ] **Step 5: Re-run focused test**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCloseTransitionCoordinatorTests/paneCloseTransitionCoordinator_cancel_stopsPerformClose'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift \
  Tests/AgentStudioTests/App/Panes/PaneCloseTransitionCoordinatorTests.swift
git commit -F - <<'EOF'
fix: cancel pending close transition on undo (phase 1/4)

Without cancel-on-undo, a performClose scheduled before the user hit
undo fires after the pane has been restored and closes it a second
time as a ghost close. Undo now cancels any pending transition for
every paneId it is about to restore.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 1.5: Phase 1 verification

**Files:** none (repo-wide)

**Why:** Phase 1 is a complete increment. It must pass full lint and full test before Phase 2 begins. This is the designated bisect-safe boundary.

- [ ] **Step 1: Run lint**

```bash
mise run lint
```

- [ ] **Step 2: Run full tests**

```bash
mise run test
```

- [ ] **Step 3: Commit the verified-green boundary**

```bash
git add -A
git commit --allow-empty -F - <<'EOF'
chore: phase 1 verified — stale-slot crash eliminated

End of Phase 1. Tombstone lifecycle and surface-scoped finalization
in place. Existing three-close-verb semantics preserved. Full lint
and test suites pass. Safe bisect boundary.
EOF
```

---

## Phase 2: Semantic unification

### Task 2.1: Collapse every `.closePane` entry point to one verb

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift`

**Why:** Today, five code sites rewrite `.closePane` into something else before it reaches the coordinator: the validator, `PaneTabViewController.closeTerminal(for:)`, `PaneTabViewController.handleTerminalProcessTerminated` (main branch AND drawer branch), `PaneTabViewController`'s `.closeDrawerPane` command handler, and `DrawerPanel`. All five must change. `.closePane` is the single entry point; the coordinator decides what happens next.

- [ ] **Step 1: Failing validator regression**

```swift
@Test("closePane on a single-pane tab remains closePane")
func closePane_singlePaneTab_staysClosePane() {
    let tabId = UUID()
    let paneId = UUID()
    let snapshot = ActionStateSnapshot(
        tabs: [
            TabSnapshot(
                id: tabId,
                visiblePaneIds: [paneId],
                ownedPaneIds: [paneId],
                activePaneId: paneId
            )
        ],
        activeTabId: tabId,
        isManagementLayerActive: false
    )

    let result = WorkspaceCommandValidator.validate(
        .closePane(tabId: tabId, paneId: paneId),
        state: snapshot
    )

    #expect(result == .success(ValidatedAction(.closePane(tabId: tabId, paneId: paneId))))
}
```

- [ ] **Step 2: Failing controller regression — command-bar drawer close routes `.closePane`**

```swift
@Test("AppCommand.closeDrawerPane dispatches .closePane for the active drawer pane")
func closeDrawerPane_command_dispatchesClosePane() {
    let harness = makeDrawerCommandHarness()
    // setup: active tab with a parent pane that has an expanded drawer with one child
    let captured = harness.captureDispatchedActions {
        harness.controller.handleAppCommand(.closeDrawerPane)
    }
    let last = try #require(captured.last)
    if case .closePane(let tabId, let paneId) = last {
        #expect(tabId == harness.activeTabId)
        #expect(paneId == harness.activeDrawerChildPaneId)
    } else {
        Issue.record("expected .closePane but got \(last)")
    }
}
```

- [ ] **Step 3: Run focused tests and verify fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'ActionValidatorTests|PaneTabViewControllerDrawerCommandTests'
```

- [ ] **Step 4: Remove validator canonicalization (D1)**

In `ActionValidator.swift`, the `.closePane` branch currently ends with:

```swift
if tab.ownedPaneCount <= 1 {
    return .success(ValidatedAction(.closeTab(tabId: tabId)))
}
return .success(ValidatedAction(action))
```

Replace with:

```swift
return .success(ValidatedAction(action))
```

- [ ] **Step 5: Fix `PaneTabViewController.closeTerminal(for:)`**

```swift
// Before:
if tab.allPaneIds.count > 1 {
    guard let matchedPaneId = tab.allPaneIds.first(where: { ... }) else { return }
    dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
} else {
    dispatchAction(.closeTab(tabId: tab.id))
}
// After:
guard let matchedPaneId = tab.allPaneIds.first(where: { ... }) else { return }
dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
```

- [ ] **Step 6: Fix `PaneTabViewController.handleTerminalProcessTerminated` — both branches**

Main-pane branch:

```swift
// Before:
if tab.allPaneIds.count > 1 {
    dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
} else {
    dispatchAction(.closeTab(tabId: tab.id))
}
// After:
dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
```

Drawer-child branch (at `PaneTabViewController.swift:1634-1639`):

```swift
// Before:
if let parentPaneId = pane.parentPaneId,
    let parentTab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)
{
    dispatchAction(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
    return
}
// After:
if let parentPaneId = pane.parentPaneId,
    let parentTab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)
{
    dispatchAction(.closePane(tabId: parentTab.id, paneId: paneId))
    return
}
```

(Capture the parent tab id so `.closePane` can be constructed correctly. `store.tabLayoutAtom.tabContaining(paneId:)` already returns the full `Tab`, so `.id` is available.)

- [ ] **Step 7: Fix `PaneTabViewController`'s `.closeDrawerPane` command handler at line 1839-1847**

```swift
// Before:
case .closeDrawerPane:
    guard let tabId = store.tabLayoutAtom.activeTabId,
        let tab = store.tabLayoutAtom.tab(tabId),
        let paneId = tab.activePaneId,
        let pane = store.paneAtom.pane(paneId),
        let drawer = pane.drawer,
        let activeDrawerPaneId = drawer.activePaneId
    else { break }
    dispatchAction(.removeDrawerPane(parentPaneId: paneId, drawerPaneId: activeDrawerPaneId))
// After:
case .closeDrawerPane:
    guard let tabId = store.tabLayoutAtom.activeTabId,
        let tab = store.tabLayoutAtom.tab(tabId),
        let paneId = tab.activePaneId,
        let pane = store.paneAtom.pane(paneId),
        let drawer = pane.drawer,
        let activeDrawerPaneId = drawer.activePaneId
    else { break }
    dispatchAction(.closePane(tabId: tabId, paneId: activeDrawerPaneId))
```

- [ ] **Step 8: Fix `DrawerPanel.swift:119-120` passthrough**

```swift
// Before:
case .closePane(_, let paneId):
    action(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
// After:
case .closePane(let tabId, let paneId):
    action(.closePane(tabId: tabId, paneId: paneId))
```

Scope check before editing: confirm `tabId` is available in the incoming `.closePane` payload and reachable in this closure. If any outer dispatch site constructs `.closePane` without a valid tabId, resolve it at that site via `store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id` before dispatch. A dispatch with a missing or stale tabId will fail validation and silently no-op.

- [ ] **Step 9: Re-run focused tests**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'ActionValidatorTests|PaneTabViewControllerDrawerCommandTests'
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add \
  Sources/AgentStudio/Core/Actions/ActionValidator.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
  Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift
git commit -F - <<'EOF'
refactor: route every pane-close UI entry point through .closePane (phase 2/1)

- Validator no longer rewrites single-pane .closePane into .closeTab.
- PaneTabViewController dispatches .closePane from all four sites:
  closeTerminal(for:), both branches of handleTerminalProcessTerminated,
  and the .closeDrawerPane command handler.
- DrawerPanel passes through .closePane instead of rewriting to
  .removeDrawerPane.

.removeDrawerPane remains as an internal coordinator action only,
invoked by executeClosePane's drawer-child delegation path in the
next task.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 2.2: Unified `executeClosePane` with snapshot-shape decision

**Files:**
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`

**Why:** Three changes in one place. (1) The coordinator chooses the undo snapshot shape (D2): tab-emptying close takes `TabCloseSnapshot`; everything else takes `PaneCloseSnapshot`. (2) The snapshot decision applies **regardless of active-tab state** (D14) — the existing `shouldCreateUndoEntry` active-tab guard only gates pane-only snapshots, not tab snapshots. This fixes the regression where single-pane background tabs (auto-close via process termination) used to produce tab undo via validator canonicalization but would lose it under the unified path. (3) Drawer-child close delegates to the `.removeDrawerPane` case so its focus ladder is preserved in one place (D4).

Phase 1 already retires drawer-child slots when a main pane with an expanded drawer closes (Task 1.3). That wiring stays; this task does not re-touch it.

- [ ] **Step 1: Failing regression — last-pane close in active tab produces a tab snapshot**

```swift
@Test("closePane on the last pane in an active tab produces a TabCloseSnapshot")
func closePane_lastPaneActive_producesTabSnapshot() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Solo"))
    let tab = Tab(paneId: pane.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: pane.id))

    #expect(harness.store.pane(pane.id) == nil)
    #expect(harness.store.tab(tab.id) == nil)
    #expect(harness.coordinator.undoStack.count == 1)
    if case .tab = harness.coordinator.undoStack.last { } else {
        Issue.record("expected TabCloseSnapshot")
    }
}
```

- [ ] **Step 2: Failing regression — last-pane close in BACKGROUND tab ALSO produces a tab snapshot (D14)**

```swift
@Test("closePane on the last pane in a background tab still produces a TabCloseSnapshot (D14)")
func closePane_lastPaneBackground_stillProducesTabSnapshot() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let activePane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Active"))
    let activeTab = Tab(paneId: activePane.id)
    harness.store.appendTab(activeTab)
    harness.store.setActiveTab(activeTab.id)

    let backgroundPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Background"))
    let backgroundTab = Tab(paneId: backgroundPane.id)
    harness.store.appendTab(backgroundTab)
    // NOTE: background tab is NOT set active.

    harness.coordinator.execute(.closePane(tabId: backgroundTab.id, paneId: backgroundPane.id))

    #expect(harness.store.tab(backgroundTab.id) == nil)
    #expect(harness.coordinator.undoStack.count == 1)
    if case .tab = harness.coordinator.undoStack.last { } else {
        Issue.record("expected TabCloseSnapshot for background last-pane close — this test pins D14 against the inactive-tab regression")
    }
}
```

- [ ] **Step 3: Failing regression — non-last-pane close in active tab produces a pane snapshot**

```swift
@Test("closePane on a non-last pane in an active tab produces a PaneCloseSnapshot")
func closePane_nonLastPaneActive_producesPaneSnapshot() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let paneA = harness.store.createPane(source: .floating(launchDirectory: nil, title: "A"))
    let paneB = harness.store.createPane(source: .floating(launchDirectory: nil, title: "B"))
    var tab = Tab(paneId: paneA.id)
    tab.insertPane(paneB.id, at: paneA.id, direction: .horizontal, position: .after)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: paneB.id))

    #expect(harness.store.tab(tab.id) != nil)
    #expect(harness.coordinator.undoStack.count == 1)
    if case .pane = harness.coordinator.undoStack.last { } else {
        Issue.record("expected PaneCloseSnapshot")
    }
}
```

- [ ] **Step 4: Failing regression — drawer-child close leaves an empty expanded drawer via delegation**

```swift
@Test("closePane on the final drawer child delegates through .removeDrawerPane and leaves an empty expanded drawer")
func closePane_lastDrawerChild_leavesEmptyExpandedDrawer() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let child = try #require(harness.store.addDrawerPane(to: parent.id))

    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: child.id))

    let drawer = try #require(harness.store.pane(parent.id)?.drawer)
    #expect(drawer.isExpanded)
    #expect(drawer.paneIds.isEmpty)
    #expect(drawer.activePaneId == nil)
}
```

- [ ] **Step 5: Run focused tests and verify fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCoordinatorTests|PaneCoordinatorHardeningTests'
```

- [ ] **Step 6: Rewrite `executeClosePane`**

Replace the existing `executeClosePane` in `PaneCoordinator+ActionExecution.swift` with:

```swift
private func executeClosePane(tabId: UUID, paneId: UUID) {
    guard let closingPane = store.paneAtom.pane(paneId) else {
        Self.logger.warning("closePane: pane \(paneId) not found")
        return
    }
    guard let tab = store.tabLayoutAtom.tab(tabId) else {
        Self.logger.warning("closePane: tab \(tabId) not found")
        return
    }

    // D2: coordinator decides snapshot shape.
    // Drawer children always produce a pane snapshot (handled below).
    // Main panes produce a tab snapshot iff closing leaves the tab with
    // no remaining main panes. Drawer children are lifecycle-owned by
    // their parent and do not count toward tab emptiness.
    let isDrawerChild = closingPane.isDrawerChild
    let closingEmptiesTab: Bool = {
        guard !isDrawerChild else { return false }
        let remainingMainPanes = tab.allPaneIds.filter { otherId in
            guard otherId != paneId else { return false }
            guard let other = store.paneAtom.pane(otherId) else { return false }
            return !other.isDrawerChild
        }
        return remainingMainPanes.isEmpty
    }()

    // D14: tab snapshot fires when the close empties the tab, regardless
    // of active-tab state. This preserves undo for auto-close in background
    // tabs that previously got canonicalized to .closeTab by the validator.
    if closingEmptiesTab {
        if let snapshot = store.mutationCoordinator.snapshotForClose(tabId: tabId) {
            appendUndoEntry(.tab(snapshot))
        } else {
            Self.logger.warning("closePane: tab snapshot failed for last-pane close in tab \(tabId)")
        }
    } else {
        // Pane snapshot keeps the existing active-tab guard: non-visible
        // panes already had no undo under the old validator-canonicalized path.
        let shouldSnapshotPane: Bool
        if tab.id == store.tabLayoutAtom.activeTabId {
            if isDrawerChild {
                shouldSnapshotPane = closingPane.parentPaneId
                    .map { tab.activePaneIds.contains($0) } ?? false
            } else {
                shouldSnapshotPane = tab.activePaneIds.contains(paneId)
            }
        } else {
            shouldSnapshotPane = false
        }
        if shouldSnapshotPane {
            if let snapshot = store.mutationCoordinator.snapshotForPaneClose(
                paneId: paneId, inTab: tabId
            ) {
                appendUndoEntry(.pane(snapshot))
            } else {
                Self.logger.warning("closePane: pane snapshot failed for pane \(paneId) in tab \(tabId)")
            }
        }
    }

    // D4: drawer-child close preserves the focus ladder by delegating to
    // the .removeDrawerPane coordinator case. The pane snapshot (if any)
    // is already captured above.
    if isDrawerChild {
        if let parentPaneId = closingPane.parentPaneId {
            execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
        } else {
            teardownView(for: paneId)
            store.mutationCoordinator.removePane(paneId)
            viewRegistry.retireSlot(for: paneId)
        }
        expireOldUndoEntries()
        return
    }

    // Main-pane close path. Phase 1 already changed removeSlot → retireSlot
    // here and in the drawer-child cleanup loop; preserved as-is.
    let drawerChildIds = closingPane.drawer?.paneIds ?? []
    teardownDrawerPanes(for: paneId)
    teardownView(for: paneId)

    viewRegistry.retireSlot(for: paneId)
    for drawerPaneId in drawerChildIds {
        viewRegistry.retireSlot(for: drawerPaneId)
    }

    store.tabLayoutAtom.removePaneFromLayout(paneId, inTab: tabId)
    for drawerPaneId in drawerChildIds {
        store.paneAtom.removeDrawerPane(drawerPaneId, from: paneId)
    }

    let allOwnedPaneIds = currentOwnedPaneIds()
    if !allOwnedPaneIds.contains(paneId) {
        store.mutationCoordinator.removePane(paneId)
    }

    if store.tabLayoutAtom.tab(tabId)?.allPaneIds.isEmpty == true {
        store.tabLayoutAtom.removeTab(tabId)
    }

    expireOldUndoEntries()
}
```

- [ ] **Step 7: Re-run focused tests**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCoordinatorTests|PaneCoordinatorHardeningTests'
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift
git commit -F - <<'EOF'
refactor: unified executeClosePane with snapshot-shape decision (phase 2/2)

- D2: coordinator decides undo snapshot shape (tab vs pane) based on
  whether the close leaves the tab with no remaining main panes.
- D14: tab snapshot fires for any tab-emptying close, active or
  background. Fixes the regression where single-pane background tab
  auto-close lost its undo entry under the unified path.
- D4: drawer-child close delegates to .removeDrawerPane so its focus
  ladder stays load-bearing in one place.

With this task landed, drawer close becomes undoable for the first
time across every drawer-close trigger (leaf button, command bar,
menu, process termination).

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 2.3: Phase 2 verification

**Files:** none (repo-wide)

**Why:** End-to-end verification of the unified pipeline. Full lint + full test.

- [ ] **Step 1: Run lint**

```bash
mise run lint
```

- [ ] **Step 2: Run full tests**

```bash
mise run test
```

- [ ] **Step 3: Commit the verified-green final state**

```bash
git add -A
git commit --allow-empty -F - <<'EOF'
chore: phase 2 verified — unified close lifecycle complete

Single .closePane primitive at every UI entry point. Coordinator
decides undo snapshot shape. Drawer close is undoable. All tests pass.
EOF
```

---

## Self-Review

### Spec coverage

| Spec item | Covered by |
|-----------|------------|
| Stale-slot crash eliminated | Phase 1 Tasks 1.1 + 1.2 + 1.3 |
| Tombstones are bounded (no memory leaks) | Phase 1 Tasks 1.1 + 1.2 (D5 split; surface-scoped finalization) |
| No branch-handoff race (D7.1) | Phase 1 Task 1.2 (container-level registration) |
| No hidden-bars tombstone leak (D7.2) | Phase 1 Task 1.2 (publish empty set when bars hidden) |
| Cross-surface finalization impossible | Phase 1 Task 1.1 (union-of-surfaces gate) |
| Non-promoting test probes (D13) | Phase 1 Task 1.1 |
| Drawer-child slots protected during parent close (D12) | Phase 1 Task 1.3 |
| Cancel-on-undo, no ghost close (D10) | Phase 1 Task 1.4 |
| Phase 1 is shippable alone | Phase 1 Task 1.5 verification |
| One .closePane entry point at every UI dispatch site (D11) | Phase 2 Task 2.1 |
| Validator stops canonicalizing (D1) | Phase 2 Task 2.1 |
| Drawer UI stops rewriting .closePane → .removeDrawerPane | Phase 2 Task 2.1 |
| closeDrawerPane command dispatches .closePane | Phase 2 Task 2.1 |
| Drawer-child process termination dispatches .closePane | Phase 2 Task 2.1 |
| Coordinator chooses undo snapshot shape (D2) | Phase 2 Task 2.2 |
| Tab snapshot regardless of active-tab state (D14) | Phase 2 Task 2.2 |
| Drawer-child focus ladder preserved (D4) | Phase 2 Task 2.2 (delegates to .removeDrawerPane) |
| Drawer close becomes undoable | Phase 2 Task 2.2 |
| Full verification | Task 1.5 + Task 2.3 |

### Invariants protected

1. **Tombstones are bounded.** A retired slot exists only while at least one registered surface renders its id. When the last surface drops it, finalization runs.
2. **No branch-handoff race.** Registration is at the container level, not the branch level. Mode switches update the *contents* of the published id set, not the registration itself.
3. **Cross-surface finalization is impossible.** Finalization gates on the union of all surfaces' rendered ids.
4. **Published ids match rendered views.** All-minimized-with-bars-hidden publishes the empty set. Tombstones cannot be pinned by ids that aren't being rendered.
5. **Undo fidelity is preserved — and extended.** Tab-level snapshots continue for any close that empties a tab (active OR background). Pane snapshots cover everything else, including drawer children (new: drawer close becomes undoable).
6. **zmx is independent.** Daemon and surface live in `SurfaceManager.undoStack` with their own TTL. Slot tombstones do not touch them.
7. **Focus ordering is preserved.** Drawer-child close keeps its prerefocus / clear-first-responder / post-removal ladder via delegation to `.removeDrawerPane`.
8. **Cancellation is clean.** `retireSlot` runs inside `performClose`; a cancelled transition never creates a tombstone. Undo additionally cancels pending transitions for restored paneIds.
9. **No new bus traffic.** All ingress is direct `@MainActor` method calls on `ViewRegistry`.
10. **Phase 1 ships alone.** At the Phase 1 boundary, the crash is fixed, all tests pass, and existing semantic splits are preserved. Phase 2 is a pure layering.

### Non-transition call sites (unchanged semantics)

These sites continue to call `removeSlot` for immediate deletion. No tombstone, no finalize:

- `PaneCoordinator+ActionExecution.swift` — `openWebview`, `openContextualWebviewInPane`, `openContextualWebviewInDrawer` (rollback on failed view creation)
- `PaneCoordinator+ActionExecution.swift` — `.purgeOrphanedPane` case
- `PaneCoordinator+ActionExecution.swift` — `expireOldUndoEntries` (GC of expired undo entries)
- `PaneCoordinator+Undo.swift` — `removeFailedRestoredPane` (undo-restore cleanup)

Opt-in tombstone sites (wired in Phase 1 Task 1.3):

- `PaneCoordinator+ActionExecution.swift` — `executeClosePane` main-pane path (pane + drawer children)
- `PaneCoordinator+ActionExecution.swift` — `.removeDrawerPane` case (drawer child)

### D6 rationale

The `ensureSlot` promote-in-place behavior saves one `PaneViewSlot` allocation on undo revive. It is NOT a correctness property. `FlatPaneStripContent.swift:75`'s `.id("\(uuid)-registered=\(host != nil)")` strategy remounts the subtree on every register/unregister/retire transition regardless of slot identity. The correctness property that makes tombstones work is different: `slot(for:)` returns a valid `PaneViewSlot` (with `host = nil`) during the stale transition-frame read, so the lazy-fallback `assertionFailure` path is never reached.

### Debugging note linkage

- Phase 1 directly addresses the `ViewRegistry.slot(for:)` stale-read crash documented in `docs/superpowers/debugging/2026-04-19-last-drawer-pane-crash.md`. Container-level surface registration closes the cross-surface race, the drawer/strip handoff race, the zoomed/minimized leak, and the hidden-bars leak. Retiring drawer-child slots on parent close closes the parent-close drawer-child race. Cancel-on-undo closes the ghost-close race.
- Phase 2 completes the semantic unification the debug note flagged as secondary: one close verb at every UI entry point, coordinator-driven snapshot shape, drawer close becomes undoable, and the inactive-tab snapshot regression is fixed.

### Placeholder scan

- No `TODO`, `TBD`, or "similar to above"
- All file paths are exact
- All code-changing steps include concrete Swift code
- All commands are explicit
