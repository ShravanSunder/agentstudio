# Unified Pane Close Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pane closing use one structural primitive everywhere — including drawer-close UX. The coordinator decides the undo snapshot shape up front, tears down view + runtime, removes the pane, retires its view slot, and then cleans up the enclosing container if it became empty. Slot removal is transition-safe via a surface-scoped tombstone lifecycle: each render surface publishes the ids it is currently rendering, and a retired slot is finalized only when no registered surface is rendering it.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, `Testing`, `@Observable`, Ghostty terminal surfaces

---

## Why This Exists

This plan is grounded in the crash investigation in:

- `docs/superpowers/debugging/2026-04-19-last-drawer-pane-crash.md`

That note established three facts:

1. The drawer-empty focus state is already correct.
2. The remaining crash is a stale `ViewRegistry.slot(for:)` read during SwiftUI's close-transition frame, hitting the lazy-fallback `assertionFailure`.
3. `.closePane`, `.closeTab`, and `.removeDrawerPane` encode three different close meanings for one user gesture.

This plan also incorporates findings from an adversarial Codex review of an earlier iteration of this plan. Four material issues were surfaced and are resolved by the design below:

- **Drawer-close UX bypassed the unified pipeline.** `DrawerPanel.swift:119-120` rewrote `.closePane` → `.removeDrawerPane` at dispatch time, so real drawer close never reached `executeClosePane`. Fixed in Task 1.
- **Parent-pane close hard-deleted drawer-child slots during the transition window.** An expanded drawer under a closing parent hit the same stale-slot race. Fixed in Task 2.
- **A global `retiredPaneIds` gated against a per-surface `renderedIds` re-created the exact race class.** Drawer surface could finalize a slot still being rendered by the main strip. Fixed by the surface-scoped design in Task 3.
- **Zoomed and all-minimized render modes bypassed the lifecycle hooks entirely.** Closes from those branches would leak tombstones forever. Fixed by routing lifecycle through `FlatTabStripContainer`-level registration.

The plan also updates the rationale for D6 (promote-in-place on revive): the original justification was "observer continuity," which is defeated by `FlatPaneStripContent.swift:75`'s `.id("\(uuid)-registered=\(host != nil)")` strategy that remounts the subtree when `host` toggles. The real benefit of tombstones is **making `slot(for:)` safe against the stale transition-frame read** — no lazy fallback, no `assertionFailure`. Promote-in-place is kept as a minor allocation optimization on undo revive, nothing more.

## Design Decisions

These decisions were made during design review and govern the task-level edits below.

| # | Decision | Reason |
|---|----------|--------|
| D1 | Validator stops canonicalizing `.closePane` → `.closeTab`. `.closePane` stays `.closePane`. | Canonicalization hides the coordinator's actual job. |
| D2 | Coordinator decides snapshot shape inside `executeClosePane`: if this close empties the tab, take a `TabCloseSnapshot`; otherwise take a `PaneCloseSnapshot`. | Preserves tab undo fidelity (arrangements, name, zoom) without validator-layer rewriting. |
| D3 | `.closeTab` (whole-tab user action) keeps its existing path. `executeCloseTab` is untouched. | Whole-tab close has always taken a tab snapshot; scope the unification to `.closePane`. |
| D4 | Drawer-child close keeps its full focus ladder. `executeClosePane` delegates to the `.removeDrawerPane` coordinator case for drawer children. | The focus ladder is load-bearing; delegation keeps it in one place. |
| D5 | `ViewRegistry` splits `removeSlot` (immediate delete, unchanged) from `retireSlot` (opt-in tombstone). Only close-transition-driven paths retire. Non-transition callers (rollback, undo GC, orphan purge, undo-restore cleanup) keep `removeSlot`. | Prevents tombstones from leaking at 10+ non-transition call sites. |
| D6 | `ensureSlot` on a retired id promotes the tombstone in place (same `PaneViewSlot` identity). | Minor allocation savings on undo revive. (The earlier rationale of "observer continuity" is moot because `FlatPaneStripContent.swift:75` remounts on `host != nil` toggle regardless of slot identity.) |
| D7 | Finalization is causal, not timer-driven. Each render surface publishes its rendered pane ids to `ViewRegistry`. A retired slot is finalized only when absent from the union of all surfaces' published ids. | Surface-scoped gating is the correct invariant: a tombstone cannot be deleted while any surface is still rendering it. |
| D8 | Surface registration and lifecycle methods live on `ViewRegistry` directly. No new monitor class. | `ApplicationLifecycleMonitor` earns its class because `NSNotificationCenter` needs observer-retain machinery to isolate; SwiftUI closures have no such machinery. |
| D9 | `retireSlot` is called inside `performClose` (not at transition scheduling) **before** the atom mutation that drops the paneId from the rendered segment list. | Ensures the tombstone exists before SwiftUI's reaction to the mutation fires `.onDisappear` / `.onChange`, so the finalization gate sees the retired state. |
| D10 | `PaneCloseTransitionCoordinator` gets `cancelCloseTransition(paneId:)`. `undoCloseTab` calls it for every paneId in the snapshot before restoring. | Prevents a pending `performClose` from firing after undo has already restored the pane. |
| D11 | Drawer close UX dispatches `.closePane`, not `.removeDrawerPane`. `.removeDrawerPane` becomes an internal coordinator action only. | One structural primitive at every UI entry point. Also makes drawer close undoable for the first time. |
| D12 | `executeClosePane`'s main-pane branch retires drawer-child slots (not `removeSlot`s them) when a parent pane with an expanded drawer is closed. | Drawer children render through the same `slot(for:)` path; they need tombstone protection during the same transition frame. |

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

## Spec

### Desired close semantics

```text
closePane(tabId, paneId)                              -- one entry point for every UI
  -> decide undo snapshot shape:
       pane is drawer child               -> PaneCloseSnapshot
       closing empties the tab (main)     -> TabCloseSnapshot
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

### Slot lifecycle semantics

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

```text
surfaceRenderedIds(surfaceId, ids:)
  = called by a render surface when its rendered id set changes
  = finalizes any retired id not present in the union of all surfaces'
    published ids

unregisterSurface(surfaceId)
  = called when a render surface unmounts
  = removes the surface from the registration map and re-runs the
    finalization check
```

Surface ids are stable strings tied to the surface's stable identity (e.g., `"mainStrip:\(tabId)"`, `"drawerStrip:\(parentPaneId):\(row)"`, `"zoomed:\(tabId)"`, `"minimized:\(tabId)"`). Views re-publish on body evaluation; the registry's set-replacement semantics make this idempotent.

### What must stop

```text
1. Validator canonicalizing `.closePane` into `.closeTab`.
2. UI entry points pre-switching on tab pane count to choose between
   .closePane and .closeTab (PaneTabViewController: closeTerminal(for:),
   handleTerminalProcessTerminated).
3. Drawer UI rewriting .closePane into .removeDrawerPane at dispatch
   (DrawerPanel).
4. Hard-deleting slots (via removeSlot) on the close-transition code path,
   either for the closing pane or for its drawer children.
5. Finalizing a retired slot based on one surface's rendered ids while
   another surface is still rendering it.
6. A pending close-transition task firing performClose after the user
   has already undone the close.
```

### What remains different

```text
.closeTab (whole-tab user action)     -> executeCloseTab unchanged,
                                         always TabCloseSnapshot.
.closePane on last main pane          -> executeClosePane, TabCloseSnapshot.
.closePane on non-last main pane      -> executeClosePane, PaneCloseSnapshot.
.closePane on drawer child            -> executeClosePane delegates to
                                         .removeDrawerPane coordinator case,
                                         PaneCloseSnapshot. Drawer close
                                         becomes undoable.
```

## File Structure

### Core runtime / state files

- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
  - Add `retireSlot(for:)` alongside existing `removeSlot(for:)`.
  - Add `finalizeRetiredSlotRemoval(for:)`.
  - Promote-in-place on `ensureSlot(for:)` when id is retired.
  - Add surface registration: `surfaceRenderedIds(_:ids:)`, `unregisterSurface(_:)`.

- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
  - Remove `.closePane` → `.closeTab` canonicalization.

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - `closeTerminal(for:)`: always dispatch `.closePane`.
  - `handleTerminalProcessTerminated`: always dispatch `.closePane` for the main-pane branch.

- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - Remove the `.closePane` → `.removeDrawerPane` rewrite. Dispatch `.closePane` directly.
  - Publish surface-rendered ids for each drawer row's strip to `ViewRegistry`.

- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
  - `executeClosePane` chooses snapshot shape; drawer-child path delegates to `.removeDrawerPane`; main-pane path retires pane slot **and drawer-child slots** (no hard-delete during transition); empty tab is removed after structural removal.
  - `.removeDrawerPane` case: retire the drawer-child slot (instead of removing immediately).

- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift`
  - Add `cancelCloseTransition(_ paneId: UUID)`.

- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
  - Publish `"mainStrip:\(tabId)"` or drawer-row surface ids to `ViewRegistry` on rendered-id changes and unregister on disappear.

- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
  - Publish surface ids for the zoomed-pane branch (`"zoomed:\(tabId)"`) and the all-minimized branch (`"minimized:\(tabId)"`).

- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
  - `undoCloseTab()` calls `closeTransitionCoordinator.cancelCloseTransition(paneId:)` for every paneId in the snapshot before restoring.

### Tests

- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`
- Modify: `Tests/AgentStudioTests/App/Panes/PaneCloseTransitionCoordinatorTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/PaneContentWiringTests.swift`

---

### Task 1: Collapse every `.closePane` entry point to one verb

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`

**Why:** Today, three code sites rewrite `.closePane` into something else before it reaches the coordinator: the validator (for single-pane tabs), `PaneTabViewController` at two dispatch points (for single-pane tabs, both in `closeTerminal(for:)` and `handleTerminalProcessTerminated`), and `DrawerPanel` (for every drawer close). The third is the most important — it is why real drawer close never exercised the unified pipeline in the earlier iteration of this plan. With this task, `.closePane` stays `.closePane` at every entry point; the coordinator decides what happens next. `.closeTab` (whole-tab user action) keeps its own path.

- [ ] **Step 1: Write the failing validator regression**

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

- [ ] **Step 2: Run the focused validator test and verify it fails**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'ActionValidatorTests/closePane_singlePaneTab_staysClosePane'
```

Expected:

```text
FAIL
Expectation failed because result is `.success(ValidatedAction(.closeTab(...)))`
```

- [ ] **Step 3: Remove validator canonicalization**

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

- [ ] **Step 4: Stop pre-switching on pane count in `PaneTabViewController`**

In `closeTerminal(for:)`, change:

```swift
if tab.allPaneIds.count > 1 {
    guard
        let matchedPaneId = tab.allPaneIds.first(where: { id in
            store.paneAtom.pane(id)?.worktreeId == worktreeId
        })
    else { return }
    dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
} else {
    dispatchAction(.closeTab(tabId: tab.id))
}
```

to:

```swift
guard
    let matchedPaneId = tab.allPaneIds.first(where: { id in
        store.paneAtom.pane(id)?.worktreeId == worktreeId
    })
else { return }
dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
```

In `handleTerminalProcessTerminated`, change:

```swift
if let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) {
    if tab.allPaneIds.count > 1 {
        dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
    } else {
        dispatchAction(.closeTab(tabId: tab.id))
    }
    return
}
```

to:

```swift
if let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) {
    dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
    return
}
```

- [ ] **Step 5: Stop rewriting `.closePane` to `.removeDrawerPane` in `DrawerPanel`**

In `DrawerPanel.swift`, the command handler rewrites `.closePane`:

```swift
case .closePane(_, let paneId):
    action(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
```

Replace with a passthrough that preserves the original `tabId` from the dispatch context:

```swift
case .closePane(let tabId, let paneId):
    action(.closePane(tabId: tabId, paneId: paneId))
```

(Note: the receiver of `action` must have the tabId in scope. If the current closure signature drops it, thread the tabId through so the drawer can dispatch a valid `.closePane`. If the drawer does not know the tabId, resolve it via `store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id` before dispatch.)

- [ ] **Step 6: Re-run the focused validator test**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'ActionValidatorTests/closePane_singlePaneTab_staysClosePane'
```

Expected:

```text
PASS
```

- [ ] **Step 7: Commit**

```bash
git add \
  Sources/AgentStudio/Core/Actions/ActionValidator.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
  Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift
git commit -F - <<'EOF'
refactor: one .closePane entry point at every UI dispatch site

Validator no longer rewrites single-pane .closePane into .closeTab.
PaneTabViewController stops pre-switching on pane count at both
dispatch sites. DrawerPanel stops rewriting .closePane into
.removeDrawerPane, routing drawer close through the unified pipeline
so it participates in undo and cancel-on-undo semantics.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 2: Make `executeClosePane` the one structural close path; retire drawer-child slots on parent close

**Files:**
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`

**Why:** Three changes in one atomic place. (1) The coordinator chooses the undo snapshot shape: tab-emptying close takes a `TabCloseSnapshot`; everything else takes a `PaneCloseSnapshot`. (2) Drawer-child close delegates to the `.removeDrawerPane` case so its focus ladder is preserved in one place. (3) The main-pane branch retires the closing pane's slot **and every drawer-child slot** rather than immediate-deleting children — drawer children render through the same `slot(for:)` path, so they need the same tombstone protection during the transition frame. `executeCloseTab` is not touched.

- [ ] **Step 1: Failing regression — last-pane main close produces a tab snapshot**

```swift
@Test("closePane on the last pane in a tab produces a TabCloseSnapshot")
func closePane_lastPane_producesTabSnapshot() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let pane = harness.store.createPane(
        source: .floating(launchDirectory: nil, title: "Solo")
    )
    let tab = Tab(paneId: pane.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: pane.id))

    #expect(harness.store.pane(pane.id) == nil)
    #expect(harness.store.tab(tab.id) == nil)
    #expect(harness.coordinator.undoStack.count == 1)
    if case .tab = harness.coordinator.undoStack.last {
        // expected
    } else {
        Issue.record("expected TabCloseSnapshot for last-pane close")
    }
}
```

- [ ] **Step 2: Failing regression — non-last main pane close produces a pane snapshot**

```swift
@Test("closePane on a non-last pane in a tab produces a PaneCloseSnapshot")
func closePane_nonLastPane_producesPaneSnapshot() {
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
    if case .pane = harness.coordinator.undoStack.last {
        // expected
    } else {
        Issue.record("expected PaneCloseSnapshot for non-last close")
    }
}
```

- [ ] **Step 3: Failing regression — drawer child close leaves empty expanded drawer**

```swift
@Test("closePane on the final drawer child leaves an empty expanded drawer")
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

- [ ] **Step 4: Failing regression — closing a main pane with an expanded drawer retires (does not remove) drawer-child slots**

```swift
@Test("closing a main pane with drawer children retires the child slots")
func closePane_parentWithDrawerChildren_retiresChildSlots() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let child = try #require(harness.store.addDrawerPane(to: parent.id))
    _ = harness.viewRegistry.ensureSlot(for: parent.id)
    _ = harness.viewRegistry.ensureSlot(for: child.id)

    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: parent.id))

    // Slot entries must survive until finalization for both parent and child.
    // ViewRegistry exposes a testing hook (slotPaneIdsForTesting) in DEBUG.
    #expect(harness.viewRegistry.slotPaneIdsForTesting.contains(parent.id))
    #expect(harness.viewRegistry.slotPaneIdsForTesting.contains(child.id))
}
```

- [ ] **Step 5: Run the focused coordinator tests and verify they fail**

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
    // Main panes produce a tab snapshot iff closing leaves the tab with no
    // remaining main panes. Drawer children are lifecycle-owned by their
    // parent and do not count toward tab emptiness.
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

    let shouldCreateUndoEntry: Bool
    if tab.id == store.tabLayoutAtom.activeTabId {
        if isDrawerChild {
            shouldCreateUndoEntry = closingPane.parentPaneId
                .map { tab.activePaneIds.contains($0) } ?? false
        } else {
            shouldCreateUndoEntry = tab.activePaneIds.contains(paneId)
        }
    } else {
        shouldCreateUndoEntry = false
    }

    if shouldCreateUndoEntry {
        if closingEmptiesTab {
            if let snapshot = store.mutationCoordinator.snapshotForClose(tabId: tabId) {
                appendUndoEntry(.tab(snapshot))
            } else {
                Self.logger.warning(
                    "closePane: tab snapshot failed for last-pane close in tab \(tabId)"
                )
            }
        } else {
            if let snapshot = store.mutationCoordinator.snapshotForPaneClose(
                paneId: paneId, inTab: tabId
            ) {
                appendUndoEntry(.pane(snapshot))
            } else {
                Self.logger.warning(
                    "closePane: pane snapshot failed for pane \(paneId) in tab \(tabId)"
                )
            }
        }
    }

    // D4: drawer-child close must preserve the prerefocus / clear-first-responder
    // focus ladder. Delegate to the existing .removeDrawerPane coordinator case.
    if isDrawerChild {
        if let parentPaneId = closingPane.parentPaneId {
            execute(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
        } else {
            teardownView(for: paneId)
            store.mutationCoordinator.removePane(paneId)
            viewRegistry.removeSlot(for: paneId)
        }
        expireOldUndoEntries()
        return
    }

    // Main-pane close path.
    // D9: retire the pane slot and every drawer-child slot BEFORE the atom
    // mutation that drops the ids from the rendered segment list, so that
    // SwiftUI's reaction to the mutation observes the retired state.
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

Then update the `.removeDrawerPane` case inside the big `execute(_:)` switch. Locate the line:

```swift
viewRegistry.removeSlot(for: drawerPaneId)
```

and replace it with:

```swift
viewRegistry.retireSlot(for: drawerPaneId)
```

Keep the rest of that case (focus ladder + store mutation) exactly as-is.

- [ ] **Step 7: Re-run the focused coordinator tests**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCoordinatorTests|PaneCoordinatorHardeningTests'
```

Expected:

```text
PASS
```

- [ ] **Step 8: Commit**

```bash
git add \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift
git commit -F - <<'EOF'
refactor: unify structural pane close, retire drawer-child slots on parent close

- Coordinator decides undo snapshot shape (tab vs pane) based on
  whether the close leaves the tab with no remaining main panes.
- Drawer-child close delegates to the .removeDrawerPane coordinator
  case so its focus ladder stays load-bearing in one place.
- Main-pane close retires every drawer-child slot (not removeSlot) so
  the expanded drawer under a closing parent is tombstone-protected
  through the same transition frame as the parent.
- retireSlot happens before atom mutation so SwiftUI's reaction to the
  mutation observes the retired state.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 3: Add surface-scoped tombstone lifecycle to `ViewRegistry`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/PaneContentWiringTests.swift`

**Why:** The stale `slot(for:)` crash happens because SwiftUI renders one more transition frame reading the removed paneId after structural removal. The fix is to keep the slot object alive through the transition as a tombstone (`host = nil`) and finalize it only when no render surface is still rendering it. This requires the finalization gate to be **surface-scoped**, not global: an earlier iteration of this plan tried a global `retiredPaneIds` against one surface's `renderedIds`, which let the drawer surface's `.onChange` finalize a slot still being rendered by the main strip. The fix is each surface publishes the ids it is currently rendering; finalization requires the union across all surfaces to exclude the id. Surfaces are tracked by stable string id. `removeSlot` keeps its immediate-delete semantics for the ten-plus non-transition call sites. Every render surface that reads `slot(for:)` must participate — including the zoomed and all-minimized branches of `FlatTabStripContainer` that an earlier iteration of this plan missed entirely.

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

- [ ] **Step 4: Failing regression — surface-scoped finalization (the core design property)**

```swift
@Test("a retired slot is finalized only when no surface renders it")
func viewRegistry_retiredSlot_requiresUnionAbsence() {
    let registry = ViewRegistry()
    let paneId = UUID()
    let originalSlot = registry.ensureSlot(for: paneId)

    registry.surfaceRenderedIds("mainStrip:tab1", ids: [paneId])
    registry.surfaceRenderedIds("drawerStrip:parent1", ids: [])
    registry.retireSlot(for: paneId)

    // Main strip still renders paneId; drawer update MUST NOT finalize.
    registry.surfaceRenderedIds("drawerStrip:parent1", ids: [])
    let afterDrawerUpdate = registry.ensureSlot(for: paneId)
    #expect(afterDrawerUpdate === originalSlot)

    // Only when the main strip also drops the id does finalization happen.
    registry.surfaceRenderedIds("mainStrip:tab1", ids: [])
    let afterMainUpdate = registry.ensureSlot(for: paneId)
    #expect(afterMainUpdate !== originalSlot)
}
```

- [ ] **Step 5: Failing regression — unregistering a surface triggers a finalization re-check**

```swift
@Test("unregisterSurface re-runs finalization for ids no longer rendered anywhere")
func viewRegistry_unregisterSurface_finalizesOrphanedRetired() {
    let registry = ViewRegistry()
    let paneId = UUID()
    let originalSlot = registry.ensureSlot(for: paneId)

    registry.surfaceRenderedIds("zoomed:tab1", ids: [paneId])
    registry.retireSlot(for: paneId)

    // While the zoomed surface is registered and renders paneId, the slot
    // cannot be finalized.
    #expect(registry.slot(for: paneId) === originalSlot)

    registry.unregisterSurface("zoomed:tab1")
    let afterUnregister = registry.ensureSlot(for: paneId)
    #expect(afterUnregister !== originalSlot)
}
```

- [ ] **Step 6: Run the focused registry tests and verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneContentWiringTests'
```

- [ ] **Step 7: Extend `ViewRegistry` with tombstones and surface registration**

In `ViewRegistry.swift`, add state and methods:

```swift
private var slots: [UUID: PaneViewSlot] = [:]
private var retiredPaneIds: Set<UUID> = []
private var renderedIdsBySurface: [String: Set<UUID>] = [:]

/// Create the slot proactively when a pane enters workspace structure.
/// If the id is retired (tombstoned), promote it in place — the slot object
/// is reused, freeing the allocation that a replacement would need. Observer
/// continuity is NOT the reason for in-place promotion: FlatPaneStripContent's
/// .id("\(uuid)-registered=\(host != nil)") strategy remounts the subtree on
/// host toggle regardless of slot identity. In-place promotion is a minor
/// allocation optimization.
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

/// Promote a retired slot to physically deleted. Idempotent; no-op if the
/// slot is not retired. Normally called internally by surfaceRenderedIds /
/// unregisterSurface; exposed for tests and explicit cleanup.
func finalizeRetiredSlotRemoval(for paneId: UUID) {
    guard retiredPaneIds.remove(paneId) != nil else { return }
    slots.removeValue(forKey: paneId)
}

/// Immediate slot deletion. Used by non-transition call sites (rollback on
/// failed creation, undo expiration GC, orphan purge, undo-restore cleanup).
/// Tombstones are opt-in via retireSlot; removeSlot never creates one.
func removeSlot(for paneId: UUID) {
    retiredPaneIds.remove(paneId)
    slots.removeValue(forKey: paneId)
}

// MARK: - Surface registration

/// Publish the current rendered pane id set for a render surface. A retired
/// slot is finalized when the union of all surfaces' rendered ids no longer
/// contains it. Idempotent: same ids → no change.
func surfaceRenderedIds(_ surfaceId: String, ids: Set<UUID>) {
    let previous = renderedIdsBySurface[surfaceId]
    guard previous != ids else { return }
    renderedIdsBySurface[surfaceId] = ids
    finalizeRetiredSlotsNotRenderedByAnySurface()
}

/// Called when a render surface unmounts (its container goes away). Removes
/// the surface from the registration map and re-runs finalization so any
/// tombstones held alive only by this surface get cleaned up.
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
```

- [ ] **Step 8: Wire surface registration in `FlatPaneStripContent`**

At the top of the strip body, declare a surface id derived from the tab id (and a drawer row discriminator when used inside a drawer). Replace the existing `ForEach` enclosure with a version that publishes on change and unregisters on disappear:

```swift
// surfaceId is injected by the container so the same FlatPaneStripContent
// reused for drawer rows gets a distinct id from the main strip:
//   main strip                -> "mainStrip:\(tabId)"
//   drawer strip, first row   -> "drawerStrip:\(parentPaneId):0"
//   drawer strip, second row  -> "drawerStrip:\(parentPaneId):1"
let renderedIds: Set<UUID> = Set(metrics.paneSegments.map(\.paneId))

content
    .onChange(of: metrics.paneSegments.map(\.paneId)) { _, newIds in
        viewRegistry.surfaceRenderedIds(surfaceId, ids: Set(newIds))
    }
    .onAppear {
        viewRegistry.surfaceRenderedIds(surfaceId, ids: renderedIds)
    }
    .onDisappear {
        viewRegistry.unregisterSurface(surfaceId)
    }
```

Pass `surfaceId: String` as a new initializer parameter on `FlatPaneStripContent` and thread it from every call site (main strip call in `FlatTabStripContainer`, drawer-row calls in `DrawerPanel`). The array-based `onChange` (not `Set(...)`) avoids the per-body Set allocation that a raw `Set(...)` comparison would incur.

- [ ] **Step 9: Wire surface registration for zoomed + all-minimized branches in `FlatTabStripContainer`**

In the zoomed branch (currently `.id(zoomedPaneId)`), publish the single zoomed id:

```swift
zoomedContent
    .onChange(of: zoomedPaneId) { _, newId in
        if let newId {
            viewRegistry.surfaceRenderedIds("zoomed:\(tabId)", ids: [newId])
        } else {
            viewRegistry.unregisterSurface("zoomed:\(tabId)")
        }
    }
    .onAppear {
        if let zoomedPaneId {
            viewRegistry.surfaceRenderedIds("zoomed:\(tabId)", ids: [zoomedPaneId])
        }
    }
    .onDisappear {
        viewRegistry.unregisterSurface("zoomed:\(tabId)")
    }
```

In the all-minimized branch, publish the minimized id set:

```swift
allMinimizedContent
    .onAppear {
        viewRegistry.surfaceRenderedIds("minimized:\(tabId)", ids: minimizedPaneIds)
    }
    .onChange(of: minimizedPaneIds) { _, newIds in
        viewRegistry.surfaceRenderedIds("minimized:\(tabId)", ids: newIds)
    }
    .onDisappear {
        viewRegistry.unregisterSurface("minimized:\(tabId)")
    }
```

- [ ] **Step 10: Wire surface registration in `DrawerPanel`**

Each row that embeds a `FlatPaneStripContent` passes its own drawer-row surface id. If `DrawerPanel` also renders any direct `slot(for:)` readers outside of nested strips, publish an additional surface id for the drawer shell itself:

```swift
drawerShell
    .onAppear {
        viewRegistry.surfaceRenderedIds("drawerShell:\(parentPaneId)", ids: renderedDrawerPaneIds)
    }
    .onChange(of: renderedDrawerPaneIds) { _, newIds in
        viewRegistry.surfaceRenderedIds("drawerShell:\(parentPaneId)", ids: newIds)
    }
    .onDisappear {
        viewRegistry.unregisterSurface("drawerShell:\(parentPaneId)")
    }
```

- [ ] **Step 11: Re-run the focused registry tests**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneContentWiringTests'
```

Expected:

```text
PASS
```

- [ ] **Step 12: Commit**

```bash
git add \
  Sources/AgentStudio/App/Panes/ViewRegistry.swift \
  Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift \
  Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
  Tests/AgentStudioTests/Core/Stores/PaneContentWiringTests.swift
git commit -F - <<'EOF'
fix: surface-scoped tombstone lifecycle in ViewRegistry

- Split removeSlot (immediate) from retireSlot (opt-in tombstone).
- Each render surface publishes its rendered id set; a retired slot
  is finalized only when no surface renders it. Fixes the cross-surface
  race where one surface's .onChange could delete a slot still being
  rendered by another.
- Main strip, drawer rows, zoomed branch, and all-minimized branch all
  participate. No render mode can orphan a tombstone.
- ensureSlot promotes retired slots in place for allocation savings.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 4: Cancel pending close transitions on undo

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
- Test: `Tests/AgentStudioTests/App/Panes/PaneCloseTransitionCoordinatorTests.swift`

**Why:** `PaneCloseTransitionCoordinator.beginClosingPane` schedules a task that fires `performClose` after the animation delay. If the user hits ⌘Z inside the animation window, today nothing cancels that task. After undo restores the pane, the pending `performClose` fires and closes it a second time — a ghost close. The tombstone lifecycle does not address this on its own; it only makes the stale-read safe. Undo must explicitly cancel any pending transitions for the paneIds it is restoring.

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

- [ ] **Step 2: Run the focused transition-coordinator test and verify it fails**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCloseTransitionCoordinatorTests/paneCloseTransitionCoordinator_cancel_stopsPerformClose'
```

- [ ] **Step 3: Add `cancelCloseTransition` to `PaneCloseTransitionCoordinator`**

In `PaneCloseTransitionCoordinator.swift`, add:

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

In `PaneCoordinator+Undo.swift`, update `undoCloseTab()` to cancel pending transitions before dispatching to either `undoTabClose` or `undoPaneClose`:

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

- [ ] **Step 5: Re-run the focused transition-coordinator test**

```bash
SWIFT_BUILD_DIR=".build-agent-$$" mise run test -- \
  --filter 'PaneCloseTransitionCoordinatorTests/paneCloseTransitionCoordinator_cancel_stopsPerformClose'
```

Expected:

```text
PASS
```

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift \
  Tests/AgentStudioTests/App/Panes/PaneCloseTransitionCoordinatorTests.swift
git commit -F - <<'EOF'
fix: cancel pending close transition on undo

Without cancel-on-undo, a performClose scheduled before the user hit
undo fires after the pane has been restored and closes it a second
time as a ghost close. Undo now cancels any pending transition for
every paneId it is about to restore.

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 5: Run the full verification loop

**Files:** none (repo-wide)

**Why:** This change cuts across validator semantics, coordinator close semantics, slot lifecycle, surface registration across four render modes, close-transition timing, and undo. Focused tests are necessary but not sufficient. Full lint + full test is the only acceptable done state.

- [ ] **Step 1: Run lint**

```bash
mise run lint
```

Expected:

```text
swift-format: OK
swiftlint: OK
Core boundary import check passed
```

- [ ] **Step 2: Run full tests**

```bash
mise run test
```

Expected:

```text
PASS
parallel non-serialized suite passes
serialized WebKit suites pass
E2E / Zmx E2E remain skipped unless explicitly enabled
```

- [ ] **Step 3: Commit final verification state**

```bash
git add -A
git commit -F - <<'EOF'
test: verify unified pane close lifecycle end to end

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

## Self-Review

### Spec coverage

| Spec item | Covered by |
|-----------|------------|
| One `.closePane` entry point at every UI dispatch site (D1, D11) | Task 1 |
| Validator stops canonicalizing `.closePane` → `.closeTab` | Task 1 |
| Drawer UI stops rewriting `.closePane` → `.removeDrawerPane` | Task 1 |
| Coordinator chooses undo snapshot shape (D2) | Task 2 |
| Tab undo fidelity preserved for last-pane close | Task 2 |
| Drawer-child focus ladder preserved (D4) | Task 2 (delegates to `.removeDrawerPane`) |
| Main-pane close retires drawer-child slots (D12) | Task 2 |
| Empty drawer stays expanded after last child | Task 2 (via existing `WorkspacePaneAtom.removeDrawerPane`) |
| Slot tombstone protects stale transition reads (D5) | Task 3 |
| Surface-scoped finalization (D7) | Task 3 |
| Every render mode participates (D8) | Task 3 (main strip, drawer rows, zoomed, minimized) |
| retireSlot before atom mutation (D9) | Task 2 (main-pane path ordering) |
| No ghost close after undo (D10) | Task 4 |
| Full verification | Task 5 |

### Invariants protected

1. **Tombstones are bounded.** A retired slot exists only while at least one registered surface renders its id. When the last surface drops it, finalization runs. Zoomed, minimized, main strip, and drawer rows all publish — no render mode can leak.
2. **Cross-surface finalization is impossible.** Finalization gates on the union of all surfaces' rendered ids, not on any single surface's callback. A drawer surface's `.onChange` cannot delete a tombstone that the main strip is still rendering.
3. **Undo fidelity is preserved.** Tab-level snapshots continue for any close that empties a tab, regardless of which action initiated it. Pane snapshots cover everything else, including drawer children (new: drawer close becomes undoable).
4. **zmx is independent.** Daemon and surface live in `SurfaceManager.undoStack` with their own TTL. Slot tombstones do not touch them.
5. **Focus ordering is preserved.** Drawer-child close keeps its prerefocus / clear-first-responder / post-removal ladder via delegation to `.removeDrawerPane`.
6. **Cancellation is clean.** `retireSlot` runs inside `performClose`. A cancelled transition never creates a tombstone. Undo additionally cancels pending transitions for restored paneIds.
7. **No new bus traffic.** All ingress is direct `@MainActor` method calls on `ViewRegistry`. No `AppEventBus`, no command dispatch, no async hops.

### Non-transition call sites (unchanged semantics)

These sites continue to call `removeSlot` for immediate deletion. No tombstone, no finalize:

- `PaneCoordinator+ActionExecution.swift` — `openWebview`, `openContextualWebviewInPane`, `openContextualWebviewInDrawer` (rollback on failed view creation)
- `PaneCoordinator+ActionExecution.swift` — `.purgeOrphanedPane` case
- `PaneCoordinator+ActionExecution.swift` — `expireOldUndoEntries` (GC of expired undo entries)
- `PaneCoordinator+Undo.swift` — `removeFailedRestoredPane` (undo-restore cleanup)

Opt-in tombstone sites:

- `PaneCoordinator+ActionExecution.swift` — `executeClosePane` main-pane path (pane + drawer children)
- `PaneCoordinator+ActionExecution.swift` — `.removeDrawerPane` case (drawer child)

### D6 rationale (updated)

The earlier iteration of this plan justified `ensureSlot` promote-in-place by "observer continuity." That reasoning is defeated by `FlatPaneStripContent.swift:75`:

```swift
.id("\(segment.paneId.uuidString)-registered=\(paneSlot.host != nil)")
```

SwiftUI view identity flips every time `host` toggles between `nil` and non-`nil`, so the subtree is remounted on every register/unregister/retire transition regardless of slot identity. Promote-in-place is kept for one concrete reason only: it avoids the `PaneViewSlot` allocation a replacement would need on undo revive. That is a minor optimization, not a correctness property.

The correctness property that makes tombstones work is different: `slot(for:)` returns a valid `PaneViewSlot` (with `host = nil`) during the stale transition-frame read, so the lazy-fallback `assertionFailure` path is never reached.

### Debugging note linkage

- Task 1 removes every `.closePane` rewrite across validator, tab controller, and drawer UI so the unified pipeline fires on real drawer close UX — the miss the adversarial review caught.
- Task 2 makes `executeClosePane` the one structural close path, preserves the drawer focus ladder, and retires drawer-child slots on parent close (the second adversarial miss).
- Task 3 directly addresses the `ViewRegistry.slot(for:)` stale-read crash documented in `docs/superpowers/debugging/2026-04-19-last-drawer-pane-crash.md`, with surface-scoped finalization so the drawer/strip cross-surface race cannot recur and the zoomed/minimized branches cannot leak.
- Task 4 closes the cancel-on-undo race the tombstone alone does not fix.

### Placeholder scan

- No `TODO`, `TBD`, or "similar to above"
- All file paths are exact
- All code-changing steps include concrete Swift code
- All commands are explicit
