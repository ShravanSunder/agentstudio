# Per-Pane Observable View Slots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `viewRevision` manual invalidation counter with per-pane `@Observable` slots in ViewRegistry, so that registering a PaneHostView automatically triggers a scoped SwiftUI re-render — tab-local invalidation, pane-local diff result — with no manual bridge, no cross-tab blast radius, and no rootView replacement.

**Architecture:** ViewRegistry gets a nested `@Observable PaneViewSlot` class. Each pane gets its own slot with an independently observable `host` property. Slots are created proactively when a pane enters workspace structure and persist for the pane's lifetime. SwiftUI views read `viewRegistry.slot(for: paneId).host` instead of `viewRegistry.view(for: paneId)`. When `register()` sets a slot's `host`, the tab-local `FlatPaneStripContent` body re-evaluates, and SwiftUI's diff isolates the change to the affected pane segment. The `viewRevision` property on WorkspaceStore, all `bumpViewRevision()` calls, and the `refreshTabContentHostsIfNeeded()` rootView-replacement machinery in PaneTabViewController are all deleted.

**Tech Stack:** Swift 6.2, `@Observable` (Observation framework), SwiftUI, AppKit

---

## Why This Change Exists

### The problem: late ViewRegistry registration

The app has a split architecture for pane rendering:

```
WorkspaceStore (@Observable)        ViewRegistry (NOT observable)
holds tab/layout structure          holds actual NSViews
        │                                   │
        ▼                                   ▼
SingleTabContent reads              FlatPaneStripContent reads
store.tab(tabId)                    viewRegistry.view(for: paneId)
        │                                   │
        └───────────── both needed ─────────┘
                        │
                        ▼
              PaneLeafContainer renders pane
```

SwiftUI automatically re-renders when `WorkspaceStore` properties change (layout, focus, minimize, etc.) because it's `@Observable`. But SwiftUI has **no idea** when `ViewRegistry` changes because it's a plain class.

This creates a "late registration" problem:

```
TIME 1: SwiftUI builds tab subtree
    FlatPaneStripContent asks viewRegistry.view(for: paneC)
    → nil (not registered yet)
    → renders Color.clear

TIME 2: AppKit registers the host later
    viewRegistry.register(hostC, for: paneC)
    → ViewRegistry mutates
    → SwiftUI doesn't know
    → Color.clear stays forever
```

### The old workaround: viewRevision counter

To bridge this gap, the codebase used a manual invalidation counter:

```
PaneCoordinator:
    viewRegistry.register(host, for: paneId)   ← actual change
    store.bumpViewRevision()                    ← manual signal

WorkspaceStore:
    private(set) var viewRevision: Int = 0      ← counter
    func bumpViewRevision() { viewRevision += 1 }

SingleTabContent.body:
    let _ = store.viewRevision                  ← must remember to read

FlatPaneStripContent.body:
    let _ = viewRevision                        ← threaded down as parameter
```

**Problems with this approach:**

1. **Must remember to read it.** The per-tab-hosting refactor accidentally dropped the `viewRevision` read from `SingleTabContent`, breaking late registration. Any new SwiftUI root view would need to remember too.

2. **Sledgehammer invalidation.** Bumping `viewRevision` on `WorkspaceStore` invalidates ALL SwiftUI views that read it — every tab's `SingleTabContent`, every `DrawerPanelOverlay`, even tabs where nothing changed.

3. **rootView replacement.** The current fix (`refreshTabContentHostsIfNeeded`) works by replacing the entire `hostingView.rootView`, forcing SwiftUI to diff the complete subtree to find the one leaf that changed.

4. **Placeholder bumps are wasted.** 2 of 9 `bumpViewRevision()` calls are for placeholder mode changes — internal AppKit subview swaps that don't need SwiftUI invalidation at all.

### The fix: per-pane `@Observable` slots

Instead of a global counter, each pane gets its own observable signal:

```
ViewRegistry
  slots: [UUID: PaneViewSlot]

  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
  │ PaneViewSlot │ │ PaneViewSlot │ │ PaneViewSlot │
  │ (@Observable)│ │ (@Observable)│ │ (@Observable)│
  │ paneA        │ │ paneB        │ │ paneC        │
  │ host: hostA  │ │ host: hostB  │ │ host: nil    │
  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
  tracked independently   │        tracked independently
         │                │                │
         ▼                ▼                ▼
  Tab A reads         Tab B reads      Tab C reads
  slot(paneA).host    slot(paneB).host slot(paneC).host
  ✅ not invalidated  ✅ not invalidated  ← only this fires
  when paneC changes  when paneC changes  when register(hostC)
```

When `viewRegistry.register(hostC, for: paneC)` runs:
- `slot(paneC).host = hostC`
- `@Observable` fires for **only** that slot
- Tab C's `FlatPaneStripContent` body re-evaluates (tab-local invalidation)
- SwiftUI diffs the ForEach — same pane IDs — only pane C's segment actually changes (pane-local diff result)
- Tab A and Tab B: untouched

---

## Invalidation Scope: Tab-Local Invalidation, Pane-Local Diff

**Important:** The slot change does NOT mean "only the single pane leaf re-renders." What actually happens:

```
slot(paneC).host changes
        ▼
FlatPaneStripContent.body for tab C re-evaluates    ← tab-local body
        ▼
ForEach diffs: same pane IDs, same structure
        ▼
only pane C's PaneViewRepresentable actually changes ← pane-local diff result
other pane segments in tab C: diffed but unchanged
        ▼
other tabs (A, B): completely untouched
```

This is scoped invalidation with two levels:
- **Tab-local invalidation:** only the tab that owns the changed pane re-evaluates its `FlatPaneStripContent` body
- **Pane-local diff result:** within that tab, SwiftUI's structural diff isolates the actual change to the one pane segment

This is much better than `viewRevision`, which invalidates all tabs' `SingleTabContent` from the root down.

---

## Slot Lifecycle Contract

Slots have **pane-lifetime identity**, not host-lifetime identity. This is critical for correctness.

```
┌──────────────────────────────────────────────────────────────┐
│ SLOT LIFECYCLE                                               │
│                                                              │
│ CREATED:  proactively, when pane enters workspace structure  │
│           PaneCoordinator calls viewRegistry.ensureSlot()    │
│           before any SwiftUI body can read it                │
│                                                              │
│ HOST SET: when PaneHostView is registered                    │
│           register() → slot.host = view                      │
│           @Observable fires → SwiftUI picks it up            │
│                                                              │
│ HOST CLEARED: when view is torn down or unregistered         │
│           unregister() → slot.host = nil                     │
│           SLOT OBJECT SURVIVES with stable identity          │
│                                                              │
│ REMOVED:  when pane is permanently removed from workspace    │
│           viewRegistry.removeSlot() called AFTER BOTH:       │
│             1. pane removed from store layout (ForEach drops  │
│                the segment → SwiftUI no longer observes slot) │
│             2. pane removed from canonical store structure    │
│                (store.removePane)                             │
│           Called in the same synchronous @MainActor method.   │
└──────────────────────────────────────────────────────────────┘
```

### Why slot identity must be stable (not deleted on unregister)

```
BAD: delete slot on unregister

  SwiftUI holds reference to PaneViewSlot (identity: 0x1)
    → unregister() deletes slot
    → later register() creates NEW slot (identity: 0x2)
    → SwiftUI still observing 0x1 which is now dead
    → late re-registration doesn't fire
    → SAME BUG WE'RE TRYING TO FIX

GOOD: keep slot, clear host

  SwiftUI holds reference to PaneViewSlot (identity: 0x1)
    → unregister() sets 0x1.host = nil
    → later register() sets 0x1.host = newHost
    → SwiftUI still observing 0x1
    → @Observable fires on 0x1.host
    → re-render picks up the new host ✅
```

### removeSlot ordering contract

`removeSlot()` deletes the slot object entirely. It is safe **only when both conditions are true**:

1. **Pane is no longer in any tab's layout** — the store layout mutation has already fired, SwiftUI's ForEach has dropped the segment, and no view is observing the slot anymore.
2. **Pane is removed from canonical WorkspaceStore structure** — `store.removePane(paneId)` has been called.

```
SAFE ordering (what PaneCoordinator does):

  store.removePaneFromLayout(paneId, inTab: tabId)
    → store @Observable fires synchronously
    → ForEach drops pane segment
    → SwiftUI dismantles PaneViewRepresentable
    → no SwiftUI view observes slot(paneId) anymore

  viewRegistry.unregister(paneId)           ← slot.host = nil (harmless)
  store.removePane(paneId)                  ← pane gone from store
  viewRegistry.removeSlot(for: paneId)      ← slot object deleted (safe)

  All four steps are in the same synchronous @MainActor method.
  SwiftUI cannot observe the slot between layout removal and
  slot deletion because there is no yield point.

UNSAFE (would break):

  viewRegistry.removeSlot(for: paneId)      ← slot deleted
  store.removePaneFromLayout(paneId, ...)   ← ForEach still has segment
  → SwiftUI reads slot(paneId) → lazy fallback creates NEW slot
  → identity split → observation broken
```

**Close transitions (animated close):** During the animation, `PaneViewRepresentable` is still mounted but it holds the `PaneHostView` directly (from the initial `makeNSView`), not through the slot. The slot is not re-read during animation. `removeSlot` is called after the close action completes and the segment is dismantled, so it is safe.

**Undo close:** Close removes the slot. Undo creates a new pane entry in the store, which triggers `ensureSlot` → creates a fresh slot. SwiftUI creates a new ForEach segment which reads the fresh slot. No identity collision because it's a new structural position.

### All slot-seeding entry points

Panes enter workspace structure through four paths. Each path must call `ensureSlot` before any SwiftUI body can read the slot.

```
┌──────────────────────────────────────────────────────────────┐
│ ENTRY POINT 1: Normal creation (split, new tab, new drawer)  │
│                                                              │
│ PaneCoordinator:                                             │
│   store.createPane(...)                                      │
│   viewRegistry.ensureSlot(for: pane.id)  ← explicit          │
│   ensureTerminalPaneView(pane)           ← calls register()  │
│                                                              │
│ Ordering: ensureSlot runs synchronously before register().   │
│ SwiftUI body runs after store @Observable fires, by which    │
│ time the slot already exists.                                │
├──────────────────────────────────────────────────────────────┤
│ ENTRY POINT 2: App launch / workspace hydration              │
│                                                              │
│ store.restore() loads panes from persisted JSON.             │
│ Panes exist in store BEFORE PaneCoordinator runs.            │
│ SwiftUI body may run BETWEEN store.restore() and             │
│ restoreAllViews().                                           │
│                                                              │
│ Fix: add bulk ensureSlot at the top of restoreAllViews():    │
│                                                              │
│ PaneCoordinator.restoreAllViews():                           │
│   // Seed slots for all panes before creating any views      │
│   for paneId in allPaneIds {                                 │
│     viewRegistry.ensureSlot(for: paneId)                     │
│   }                                                          │
│   // Then create views (register sets slot.host)             │
│   for pane in orderedPanes {                                 │
│     createViewForContent(pane: pane, ...)                     │
│   }                                                          │
│                                                              │
│ This ensures slots exist before the first SwiftUI body read  │
│ during restore. Without this, the lazy fallback would fire   │
│ for every pane on launch — correct but noisy.                │
├──────────────────────────────────────────────────────────────┤
│ ENTRY POINT 3: Undo close (tab or pane)                      │
│                                                              │
│ PaneCoordinator.undoCloseTab():                              │
│   restores pane to store                                     │
│   creates new view → register() → ensureSlot internally      │
│                                                              │
│ Covered: register() calls ensureSlot() as belt-and-suspenders│
├──────────────────────────────────────────────────────────────┤
│ ENTRY POINT 4: Repair / recreate surface                     │
│                                                              │
│ PaneCoordinator.executeRepair():                             │
│   tears down old view (unregister, slot.host = nil)          │
│   creates new view → register() → ensureSlot internally      │
│                                                              │
│ Covered: slot already exists from original creation.          │
│ register() finds existing slot and sets host.                │
└──────────────────────────────────────────────────────────────┘
```

**Lazy fallback:** If a slot is somehow missed by all four paths, `slot(for:)` creates one lazily with a `RestoreTrace` warning. This is a safety net, not a design path. If the warning fires during normal operation, it means an `ensureSlot` call was missed and should be added.

### Why proactive creation (not lazy-on-read)

```
LAZY: slot(for:) creates on first SwiftUI body read

  Problem: SwiftUI body evaluation mutates ViewRegistry.
  Reads should not allocate. This is architecturally impure.

PROACTIVE: slot created when pane enters workspace structure

  PaneCoordinator path:
    1. store.createPane()               ← pane enters store
    2. viewRegistry.ensureSlot(paneId)   ← slot ready before render
    3. (SwiftUI body reads slot.host)    ← pure read, no mutation
    4. viewRegistry.register(host, ...)  ← sets slot.host

  Ordering is guaranteed because:
    store.createPane() runs first
    → store @Observable fires → SwiftUI builds ForEach
    → ForEach body reads slot(paneId).host
    → slot already exists from step 2

  Restore path:
    1. store.restore()                  ← panes loaded from disk
    2. restoreAllViews() bulk ensureSlot ← all slots ready
    3. (SwiftUI body reads slot.host)    ← pure read
    4. createViewForContent() → register ← sets slot.host
```

### API summary

```
ViewRegistry:
  ensureSlot(for: paneId)     ← proactive creation, called by PaneCoordinator
                                 in all four entry points listed above
  register(host, for: paneId) ← sets slot.host (calls ensureSlot internally)
  unregister(paneId)          ← sets slot.host = nil, slot survives
  removeSlot(for: paneId)     ← deletes slot AFTER layout removal + store removal
  slot(for: paneId)           ← returns existing slot (lazy fallback with warning)
  view(for: paneId)           ← imperative accessor, no observation, unchanged API
```

---

## Two Independent Mechanisms

After this change, pane rendering is driven by two independent observation mechanisms. Understanding when each fires is critical.

### Mechanism 1: WorkspaceStore `@Observable` — structure and layout

```
Drives: what panes exist, where they are arranged, which is active/zoomed
Signal: WorkspaceStore property mutations (tabs, layout, activePaneId, etc.)
Tracked by: SingleTabContent reads store.tab(tabId)
```

This handles: resize, close pane, new pane (layout change), focus, minimize/expand, zoom, move pane between tabs, tab creation/deletion.

### Mechanism 2: PaneViewSlot `@Observable` — host availability

```
Drives: whether the actual NSView is available for a pane
Signal: PaneViewSlot.host mutation
Tracked by: FlatPaneStripContent reads slot(paneId).host
```

This handles: late registration (restore, repair, placeholder retry), new pane host creation.

### When each fires

```
┌────────────────────────┬───────────────────┬──────────────────┐
│ Action                 │ Store @Observable  │ Slot @Observable  │
│                        │ (structure)        │ (host available)  │
├────────────────────────┼───────────────────┼──────────────────┤
│ Resize pane            │ YES (layout ratio) │ NO               │
│ Close pane             │ YES (layout)       │ YES (harmless*)  │
│ New pane (split)       │ YES (layout)       │ YES (mounts it)  │
│ Late registration      │ NO                 │ YES (this is the │
│ (restore/repair)       │                    │  whole point)    │
│ Focus / minimize       │ YES (tab state)    │ NO               │
│ Zoom / unzoom          │ YES (tab state)    │ NO               │
│ Tab switch             │ AppKit show/hide   │ NO               │
│ Move pane A→B          │ YES (both layouts) │ NO               │
│ Placeholder mode change│ NO                 │ NO (correct!)    │
└────────────────────────┴───────────────────┴──────────────────┘

* Close pane: slot fires (host=nil) but segment already gone from ForEach
```

### Resize in detail (slot NOT involved)

```
User drags split divider → store.resizeSplit(ratio: 0.6, inTab: A)
                                │
                                ▼ store @Observable fires
SingleTabContent.body:
  store.tab(tabId) changed → re-evaluates
    → FlatTabStripContainer gets new layout
    → FlatTabStripMetrics.compute() produces new frame sizes
    → FlatPaneStripContent ForEach:
        SAME pane IDs → same SwiftUI identity
        .frame(width: newWidth) ← only modifiers change
        slot(paneId).host ← same value, NOT invalidated
        PaneLeafContainer ← same paneHost, NOT recreated

ViewRegistry: untouched. Slots: silent.
Result: frame sizes update, no mount/unmount, no slot fires.
```

### Late registration in detail (slot IS the fix)

```
TIME 1: SwiftUI builds tab C's subtree

  FlatPaneStripContent.body:
    viewRegistry.slot(for: paneC).host → nil
    @Observable records: "this view depends on slot(paneC).host"
    Renders: Color.clear

TIME 2: AppKit registers the host

  viewRegistry.register(hostC, for: paneC)
    → slot(for: paneC).host = hostC
    → @Observable fires for slot(paneC).host ONLY

  Tab A's FlatPaneStripContent: observes slot(paneA) → NOT paneC → NOTHING
  Tab B's FlatPaneStripContent: observes slot(paneB) → NOT paneC → NOTHING
  Tab C's FlatPaneStripContent: body re-evaluates (tab-local invalidation)
    → ForEach diffs same pane IDs
    → only pane C segment changed (pane-local diff result)
    → slot(paneC).host = hostC → PaneLeafContainer mounts it ✅

  No bumpViewRevision(). No rootView replacement. No cross-tab work.
```

### Close pane in detail (store drives it, slot is harmless)

```
User closes pane B in tab A (tab has panes [A, B, C])

PaneCoordinator:
  1. store.removePaneFromLayout(paneB, inTab: A)  → store @Observable fires
  2. viewRegistry.unregister(paneB)                → slot(paneB).host = nil
  3. viewRegistry.removeSlot(for: paneB)           → slot object removed

Signal 1 (store): tab A's layout changes [A,B,C] → [A,C]
  → SingleTabContent re-evaluates
  → ForEach segments: [A, C] — pane B segment is gone
  → SwiftUI dismantles PaneViewRepresentable for pane B
  → Panes A and C: same ForEach identity, NOT recreated, get new frames

Signal 2 (slot): slot(paneB).host = nil
  → But pane B's segment is already gone from ForEach
  → No SwiftUI view is observing slot(paneB) anymore
  → This is a no-op. Harmless.

Result: pane B removed, panes A and C reframed, no unnecessary work.
```

### What should NEVER cause a mount/unmount

```
These actions must NEVER trigger PaneViewRepresentable make/dismantle:

✗ Tab switch       → AppKit show/hide on PersistentTabHostView
✗ Resize           → store @Observable, same ForEach identity
✗ Focus change     → store @Observable, same ForEach identity
✗ Minimize/expand  → store @Observable, same ForEach identity
✗ Zoom/unzoom      → .id(zoomedPaneId) handles identity correctly

These actions correctly trigger mount/unmount:

✓ New pane         → new ForEach segment + slot mounts the host
✓ Close pane       → segment removed from ForEach
✓ Close tab        → PersistentTabHostView removed entirely
✓ Move pane A→B    → unmount from A (segment gone) + mount in B (segment added)
                     only pane X remounts, other panes in both tabs untouched
✓ Late registration→ slot fires, Color.clear → PaneLeafContainer
```

---

## What Gets Deleted

```
DELETED from WorkspaceStore:
  private(set) var viewRevision: Int = 0
  func bumpViewRevision()

DELETED from PaneCoordinator (9 call sites):
  store.bumpViewRevision()  ×9

DELETED from PaneTabViewController:
  lastRenderedViewRevision
  refreshTabContentHostsIfNeeded()
  tabContentHostNeedsRefresh()
  buildTabContentRoot()
  observeForAppKitState tracking of viewRevision

DELETED from PersistentTabHostView:
  update(rootView:)

DELETED from view chain (viewRevision parameter threading):
  SingleTabContent → FlatTabStripContainer →
  FlatPaneStripContent → DrawerPanel → DrawerPanelOverlay

ADDED:
  PaneViewSlot (@Observable inner class): ~3 lines
  ensureSlot(for:) method: ~3 lines
  removeSlot(for:) method: ~1 line
  slot(for:) method with lazy fallback + warning: ~8 lines
  slot(for:).host reads in 2 SwiftUI views (replacing view(for:) calls)
  ensureSlot calls in PaneCoordinator pane creation paths

Net: massive deletion, small addition.
```

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/.../App/Panes/ViewRegistry.swift` | Modify | Add `PaneViewSlot` inner type, `ensureSlot`, `removeSlot`, slot-based storage |
| `Sources/.../Core/Stores/WorkspaceStore.swift` | Modify | Delete `viewRevision` property and `bumpViewRevision()` method |
| `Sources/.../Core/Views/Splits/SingleTabContent.swift` | Modify | Remove `viewRevision` read and threading |
| `Sources/.../Core/Views/Splits/FlatTabStripContainer.swift` | Modify | Remove `viewRevision` parameter, use `slot(for:).host` for zoom |
| `Sources/.../Core/Views/Splits/FlatPaneStripContent.swift` | Modify | Remove `viewRevision` parameter, use `slot(for:).host` for pane lookup |
| `Sources/.../Core/Views/Splits/ActiveTabContent.swift` | Modify | Remove `viewRevision` read (deprecated file) |
| `Sources/.../Core/Views/Drawer/DrawerPanel.swift` | Modify | Remove `viewRevision` parameter |
| `Sources/.../Core/Views/Drawer/DrawerPanelOverlay.swift` | Modify | Remove `viewRevision` read |
| `Sources/.../App/Panes/PaneTabViewController.swift` | Modify | Delete `refreshTabContentHostsIfNeeded()`, `tabContentHostNeedsRefresh()`, `lastRenderedViewRevision`, `buildTabContentRoot()`, remove `viewRevision` from `observeForAppKitState` |
| `Sources/.../App/Panes/PersistentTabHostView.swift` | Modify | Delete `update(rootView:)` method |
| `Sources/.../App/PaneCoordinator+ViewLifecycle.swift` | Modify | Delete `bumpViewRevision()` calls (×4), add `ensureSlot` in pane creation paths |
| `Sources/.../App/PaneCoordinator+ActionExecution.swift` | Modify | Delete `bumpViewRevision()` calls (×2), add `ensureSlot` in pane creation paths |
| `Sources/.../App/PaneCoordinator+TerminalPlaceholders.swift` | Modify | Delete `bumpViewRevision()` calls (×3) |
| `Tests/.../App/PaneTabViewControllerTabRetentionTests.swift` | Modify | Update late-registration test to not use `bumpViewRevision()` |
| `Tests/.../Architecture/CoordinationPlaneArchitectureTests.swift` | Modify | Update assertions for removed viewRevision, add slot assertions |

---

### Task 1: Add PaneViewSlot to ViewRegistry

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`

This is the core change. ViewRegistry gets per-pane `@Observable` slots with proactive creation, stable pane-lifetime identity, and a lazy fallback with warning.

**Why two read APIs:** `view(for:)` does a plain dictionary lookup — no observation overhead for imperative code that runs once and returns (PaneCoordinator, PaneTabViewController). `slot(for:).host` creates `@Observable` tracking — exactly what SwiftUI needs to auto-invalidate when a host is registered.

**Why proactive slot creation:** `ensureSlot(for:)` is called by PaneCoordinator when a pane enters workspace structure, before any SwiftUI body can read it. This avoids mutating ViewRegistry during SwiftUI body evaluation. `slot(for:)` has a lazy fallback that logs a warning if `ensureSlot` was missed — safe but noisy, signals a bug in the creation path.

**Why `removeSlot` is separate from `unregister`:** `unregister()` clears `slot.host = nil` but keeps the slot object alive. This preserves slot identity for SwiftUI observers across unregister/re-register cycles (repair, undo). `removeSlot()` deletes the slot entirely when the pane is permanently removed from workspace structure.

- [ ] **Step 1: Replace ViewRegistry implementation with slot-based storage**

Replace the entire file with:

```swift
import AppKit
import Observation

/// Maps pane IDs to live PaneHostView instances via per-pane observable slots.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
///
/// ## Observation contract
///
/// Each pane gets its own `@Observable PaneViewSlot`. SwiftUI views read
/// `slot(for: paneId).host` to get automatic, scoped invalidation when
/// `register()` fires. Imperative callers (PaneCoordinator, PaneTabViewController)
/// use `view(for:)` which does a plain lookup with no observation overhead.
///
/// ## Slot lifecycle
///
/// - `ensureSlot(for:)`: creates a slot proactively when a pane enters workspace structure
/// - `register(_, for:)`: sets `slot.host` — auto-invalidates SwiftUI observers
/// - `unregister(_)`: clears `slot.host = nil` — slot object survives with stable identity
/// - `removeSlot(for:)`: deletes the slot when the pane is permanently removed
///
/// Slots have pane-lifetime identity, not host-lifetime identity. This ensures
/// SwiftUI observers survive across unregister/re-register cycles (repair, undo).
@MainActor
final class ViewRegistry {
    /// Per-pane observable slot. SwiftUI views read `slot(for:).host`
    /// to get automatic, scoped invalidation when `register()` fires.
    @Observable
    final class PaneViewSlot {
        private(set) var host: PaneHostView?
    }

    private var slots: [UUID: PaneViewSlot] = [:]

    /// Create the slot proactively when a pane enters workspace structure.
    /// Called by PaneCoordinator before any SwiftUI body can read the slot.
    /// Idempotent — safe to call multiple times for the same paneId.
    @discardableResult
    func ensureSlot(for paneId: UUID) -> PaneViewSlot {
        if let existing = slots[paneId] {
            return existing
        }
        let newSlot = PaneViewSlot()
        slots[paneId] = newSlot
        return newSlot
    }

    /// Get the observable slot for a pane.
    /// SwiftUI views read `slot(for: paneId).host` to get per-pane observation.
    /// Falls back to lazy creation with a warning if `ensureSlot` was not called.
    func slot(for paneId: UUID) -> PaneViewSlot {
        if let existing = slots[paneId] {
            return existing
        }
        // Safety net: slot should have been created proactively via ensureSlot().
        // If we get here, the pane creation path missed the ensureSlot call.
        RestoreTrace.log(
            "ViewRegistry.slot(for:) lazy fallback paneId=\(paneId) — ensureSlot was not called"
        )
        let newSlot = PaneViewSlot()
        slots[paneId] = newSlot
        return newSlot
    }

    /// Register a view for a pane. Automatically invalidates only
    /// SwiftUI views observing this pane's slot.
    func register(_ view: PaneHostView, for paneId: UUID) {
        ensureSlot(for: paneId).host = view
    }

    /// Unregister a view for a pane. Clears host but preserves slot identity
    /// so SwiftUI observers survive across unregister/re-register cycles.
    func unregister(_ paneId: UUID) {
        slots[paneId]?.host = nil
    }

    /// Remove the slot entirely when a pane is permanently removed from workspace structure.
    /// Called after all references to the pane are gone.
    func removeSlot(for paneId: UUID) {
        slots.removeValue(forKey: paneId)
    }

    /// Get the view for a pane, if registered.
    /// Imperative callers use this — no observation tracking.
    func view(for paneId: UUID) -> PaneHostView? {
        slots[paneId]?.host
    }

    /// Get the terminal view for a pane, if it is a terminal.
    func terminalView(for paneId: UUID) -> TerminalPaneMountView? {
        guard let view = slots[paneId]?.host else { return nil }
        return view.mountedContent(as: TerminalPaneMountView.self)
    }

    /// Get the terminal status placeholder view for a pane, if it is present.
    func terminalStatusPlaceholderView(for paneId: UUID) -> TerminalStatusPlaceholderView? {
        guard let view = slots[paneId]?.host else { return nil }
        return view.mountedContent(as: TerminalPaneMountView.self)?.placeholderViewForTesting
    }

    /// Get the webview for a pane, if it is a webview.
    func webviewView(for paneId: UUID) -> WebviewPaneMountView? {
        guard let view = slots[paneId]?.host else { return nil }
        return view.mountedContent(as: WebviewPaneMountView.self)
    }

    /// All registered webview pane views, keyed by pane ID.
    var allWebviewViews: [UUID: WebviewPaneMountView] {
        slots.compactMapValues { slot in
            slot.host?.mountedContent(as: WebviewPaneMountView.self)
        }
    }

    /// All registered terminal pane views, keyed by pane ID.
    var allTerminalViews: [UUID: TerminalPaneMountView] {
        slots.compactMapValues { slot in
            slot.host?.mountedContent(as: TerminalPaneMountView.self)
        }
    }

    /// All currently registered pane IDs.
    var registeredPaneIds: Set<UUID> {
        Set(slots.compactMap { $0.value.host != nil ? $0.key : nil })
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `mise run build`
Expected: PASS — `view(for:)` API is unchanged so all existing callers compile.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/App/Panes/ViewRegistry.swift
git commit -m "feat: add per-pane @Observable PaneViewSlot to ViewRegistry

Each pane gets its own observable slot with pane-lifetime identity.
register()/unregister() mutate slot.host; unregister preserves the
slot object for stable SwiftUI observation across cycles.
ensureSlot() for proactive creation; slot() has lazy fallback with warning.
Existing view(for:) API preserved for imperative callers.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add proactive ensureSlot/removeSlot calls in PaneCoordinator

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`

**Why:** Slots must exist before SwiftUI reads them. The proactive path ensures `ensureSlot` runs in every code path that creates or restores a pane, before `register()` and before any SwiftUI body evaluation. `removeSlot` must run after both layout removal and store removal, in the same synchronous `@MainActor` method.

There are four entry points where panes enter workspace structure (see "All slot-seeding entry points" above). This task covers all four.

- [ ] **Step 1: Add bulk ensureSlot at the top of restoreAllViews (Entry Point 2: hydration)**

In `PaneCoordinator+ViewLifecycle.swift`, in `restoreAllViews()`, add a bulk seeding loop **before** any view creation. This is the most important seeding point because panes exist in the store (from `store.restore()`) before `restoreAllViews()` runs, and SwiftUI may read slot(for:) between those two steps.

Find the beginning of `restoreAllViews()` and add before the first view creation loop:

```swift
// Seed slots for all panes before creating any views.
// Panes already exist in the store from store.restore().
// SwiftUI body may run before restoreAllViews completes,
// so slots must exist before the first createViewForContent call.
let allPaneIds = store.tabs.flatMap(\.paneIds)
for paneId in allPaneIds {
    viewRegistry.ensureSlot(for: paneId)
}
// Also seed drawer pane slots
for pane in store.panes.values {
    if let drawer = pane.drawer {
        for drawerPaneId in drawer.layout.paneIds {
            viewRegistry.ensureSlot(for: drawerPaneId)
        }
    }
}
```

- [ ] **Step 2: Add ensureSlot calls in pane creation paths (Entry Point 1: normal creation)**

Find every code path where a new pane is created via `store.createPane()` and add `viewRegistry.ensureSlot(for: pane.id)` immediately after. The `register()` call in `registerHostedView` also calls `ensureSlot` internally (belt-and-suspenders), but the explicit call documents the intent and ensures the slot exists even if view creation is deferred.

In `PaneCoordinator+ActionExecution.swift`, in `executeInsertPane` (~line 530-557), after each `store.createPane()` and before `ensureTerminalPaneView()`:
```swift
viewRegistry.ensureSlot(for: pane.id)
```

Search for all `store.createPane()` call sites across the coordinator and add `viewRegistry.ensureSlot(for: pane.id)` after each one.

Entry Points 3 (undo) and 4 (repair) are covered automatically because `register()` calls `ensureSlot` internally, and the slot either already exists (repair) or is freshly created by `register` (undo creates a new pane).

- [ ] **Step 3: Add removeSlot calls in pane permanent removal paths**

Find every code path where `store.removePane(paneId)` is called and add `viewRegistry.removeSlot(for: paneId)` **after** the unregister call and **after** `store.removePane()`. The ordering must be:

```
store.removePaneFromLayout(paneId, inTab:)   ← ForEach drops segment
viewRegistry.unregister(paneId)               ← slot.host = nil
store.removePane(paneId)                      ← pane gone from store
viewRegistry.removeSlot(for: paneId)          ← slot object deleted (LAST)
```

All four steps must be in the same synchronous `@MainActor` method with no yield points between them.

In `PaneCoordinator+ViewLifecycle.swift` (~lines 210, 324, 372), after `viewRegistry.unregister(pane.id)` and after any `store.removePane()`:
```swift
viewRegistry.removeSlot(for: pane.id)
```

In `PaneCoordinator+ActionExecution.swift`, in pane close paths where `store.removePane(paneId)` is called (~lines 434, 478, 495):
```swift
viewRegistry.removeSlot(for: paneId)
```

**Important:** Do NOT add `removeSlot` after plain `unregister()` calls that are part of repair/teardown-for-recreation flows. Only add it when the pane is being **permanently** removed (the code path also calls `store.removePane`).

- [ ] **Step 4: Verify build compiles**

Run: `mise run build`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
       Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift
git commit -m "feat: add proactive ensureSlot/removeSlot calls in PaneCoordinator

Slots are seeded in all four pane entry points:
1. Normal creation: ensureSlot after store.createPane()
2. App launch hydration: bulk ensureSlot at top of restoreAllViews()
3. Undo restore: covered by register() calling ensureSlot internally
4. Repair: covered by existing slot surviving unregister()

removeSlot runs only on permanent removal, after both layout removal
and store.removePane(), in the same synchronous @MainActor method.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire SwiftUI views to read from slots

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`

**Why:** SwiftUI views must read `viewRegistry.slot(for: paneId).host` instead of `viewRegistry.view(for: paneId)` so that `@Observable` tracking fires at the per-pane level. The `view(for:)` method intentionally does NOT create observation tracking — it's for imperative callers only.

- [ ] **Step 1: Update FlatPaneStripContent to use slots**

In `FlatPaneStripContent.swift`:

Remove the `viewRevision` property:
```swift
let viewRevision: Int
```

In `body`, remove:
```swift
let _ = viewRevision
```

In `paneSegmentView`, change:
```swift
} else if let paneHost = viewRegistry.view(for: segment.paneId) {
```
to:
```swift
} else if let paneHost = viewRegistry.slot(for: segment.paneId).host {
```

In `paneSegmentIdentity`, change:
```swift
let hasRegisteredPaneView = viewRegistry.view(for: paneId) != nil
```
to:
```swift
let hasRegisteredPaneView = viewRegistry.slot(for: paneId).host != nil
```

- [ ] **Step 2: Update FlatTabStripContainer to use slots and remove viewRevision**

In `FlatTabStripContainer.swift`:

Remove:
```swift
let viewRevision: Int
```

In `zoomedPaneLeafContainer()`, change:
```swift
guard let zoomedPaneId, let zoomedView = viewRegistry.view(for: zoomedPaneId) else {
```
to:
```swift
guard let zoomedPaneId, let zoomedView = viewRegistry.slot(for: zoomedPaneId).host else {
```

Remove `viewRevision:` from the `FlatPaneStripContent` init call.

- [ ] **Step 3: Verify build compiles**

Run: `mise run build`
Expected: Build errors in callers that still pass `viewRevision` — fixed in Task 4.

---

### Task 4: Remove viewRevision threading from all view chains

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`

**Why:** `viewRevision` was threaded from `SingleTabContent` → `FlatTabStripContainer` → `FlatPaneStripContent` → `DrawerPanel` as a parameter chain. Now that `FlatPaneStripContent` reads `slot(for:).host` directly, this entire parameter chain is unnecessary.

- [ ] **Step 1: Update SingleTabContent**

Remove the `viewRevision` read and parameter threading. The file becomes:

```swift
import SwiftUI

struct SingleTabContent: View {
    let tabId: UUID
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching

    private static func traceMissingTab(tabId: UUID) -> Int {
        RestoreTrace.log("SingleTabContent.body missingTab tabId=\(tabId)")
        return 0
    }

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = store.tab(tabId) == nil ? Self.traceMissingTab(tabId: tabId) : 0
        if let tab = store.tab(tabId) {
            FlatTabStripContainer(
                layout: tab.layout,
                tabId: tabId,
                activePaneId: tab.activePaneId,
                zoomedPaneId: tab.zoomedPaneId,
                minimizedPaneIds: tab.minimizedPaneIds,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore
            )
            .background(AppStyle.chromeBackground)
        }
    }
}
```

- [ ] **Step 2: Update ActiveTabContent**

Remove `let currentViewRevision = store.viewRevision` and the `viewRevision:` parameter from the `FlatTabStripContainer` init call. Remove `viewRevision` from the `traceBody` method signature and call. This is a deprecated file so keep changes minimal.

- [ ] **Step 3: Update DrawerPanelOverlay**

Remove line `let _ = store.viewRevision` and remove the `viewRevision:` argument from the `DrawerPanel` init call.

- [ ] **Step 4: Update DrawerPanel**

Remove the `viewRevision` stored property, the `viewRevision` init parameter, the `self.viewRevision = viewRevision` assignment, and the `viewRevision:` argument in the `FlatPaneStripContent` init call. Also remove the `viewRevision: 0` in the preview.

- [ ] **Step 5: Verify build compiles**

Run: `mise run build`
Expected: PASS — all viewRevision threading removed from the view chain.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift \
       Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift \
       Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift \
       Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift \
       Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift \
       Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift
git commit -m "refactor: remove viewRevision threading from SwiftUI view chain

SwiftUI views now read viewRegistry.slot(for: paneId).host which
auto-tracks per-pane. No manual invalidation counter needed.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Delete viewRevision from WorkspaceStore and all bumpViewRevision() call sites

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift` (lines ~608, 631, 637, 801)
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift` (lines ~637, 655)
- Modify: `Sources/AgentStudio/App/PaneCoordinator+TerminalPlaceholders.swift` (lines ~52, 61, 76)

**Why `viewRevision` is fully redundant now:** Every `bumpViewRevision()` call either follows a `viewRegistry.register()` (which now auto-invalidates via the slot) or bumps after a placeholder mode change (which is internal AppKit state that never needed SwiftUI invalidation).

**Why each call site is safe to delete:**

- **ViewLifecycle (×4):** Follow `registerHostedView()` or `createViewForContent()` → `register()` auto-invalidates via slot. Bump was the manual bridge.
- **ActionExecution (×2):** Follow repair actions that call `register()` → same.
- **TerminalPlaceholders line ~76:** Follows `registerHostedView()` → redundant.
- **TerminalPlaceholders lines ~52, 61:** Bump after placeholder MODE changes on already-registered views. No ViewRegistry mutation occurs. These were always wasted work.

- [ ] **Step 1: Delete viewRevision property and bumpViewRevision method from WorkspaceStore**

Remove the property (~line 35-39) and the method (~line 1630-1635).

- [ ] **Step 2: Delete bumpViewRevision calls in PaneCoordinator+ViewLifecycle.swift**

Remove these 4 lines. For the batched restore pattern:
```swift
if index.isMultiple(of: 2) {
    store.bumpViewRevision()  // DELETE this line
    await Task.yield()        // KEEP — yield is still useful
}
```

For the guard patterns, keep the `if` block only if it has other side effects.

- [ ] **Step 3: Delete bumpViewRevision calls in PaneCoordinator+ActionExecution.swift**

Remove the 2 lines after `recreateSurface` and `createMissingView` repairs.

- [ ] **Step 4: Delete bumpViewRevision calls in PaneCoordinator+TerminalPlaceholders.swift**

Remove all 3 lines.

- [ ] **Step 5: Verify build compiles**

Run: `mise run build`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceStore.swift \
       Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
       Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
       Sources/AgentStudio/App/PaneCoordinator+TerminalPlaceholders.swift
git commit -m "refactor: delete viewRevision counter and all bumpViewRevision() calls

ViewRegistry.register() now auto-invalidates via per-pane @Observable
slots. The manual invalidation bridge is no longer needed.

Removes: viewRevision property, bumpViewRevision() method, 9 call sites.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Delete rootView replacement machinery from PaneTabViewController

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/PersistentTabHostView.swift`

**Why:** The `refreshTabContentHostsIfNeeded()` approach existed because ViewRegistry wasn't observable. It worked by replacing `hostingView.rootView`, which forces SwiftUI to diff the entire tab subtree to find one changed leaf. With per-pane slots, SwiftUI discovers the change at the leaf directly — no rootView replacement needed.

- [ ] **Step 1: Delete refresh machinery from PaneTabViewController**

Remove `lastRenderedViewRevision` property (~line 113).

Remove `refreshTabContentHostsIfNeeded()` method (~lines 429-439).

Remove `tabContentHostNeedsRefresh()` method (~lines 441-447).

Remove `buildTabContentRoot()` method (~lines 392-402).

Update `buildTabContentHost()` to inline the SingleTabContent construction:
```swift
private func buildTabContentHost(for tabId: UUID) -> PersistentTabHostView {
    let contentView = SingleTabContent(
        tabId: tabId,
        store: store,
        repoCache: repoCache,
        viewRegistry: viewRegistry,
        appLifecycleStore: appLifecycleStore,
        closeTransitionCoordinator: closeTransitionCoordinator,
        actionDispatcher: actionDispatcher
    )
    return PersistentTabHostView(tabId: tabId, rootView: contentView)
}
```

Remove `refreshTabContentHostsIfNeeded()` calls from `viewWillLayout()` and `handleAppKitStateChange()`.

Remove `_ = self.store.viewRevision` from `observeForAppKitState()` `withObservationTracking` block.

- [ ] **Step 2: Delete update(rootView:) from PersistentTabHostView**

In `PersistentTabHostView.swift`, remove:
```swift
func update(rootView: SingleTabContent) {
    hostingView.rootView = rootView
}
```

- [ ] **Step 3: Verify build compiles**

Run: `mise run build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
       Sources/AgentStudio/App/Panes/PersistentTabHostView.swift
git commit -m "refactor: delete rootView replacement machinery

refreshTabContentHostsIfNeeded(), tabContentHostNeedsRefresh(),
buildTabContentRoot(), lastRenderedViewRevision, and
PersistentTabHostView.update(rootView:) are all deleted.

Per-pane @Observable slots handle late registration automatically
without needing to replace the hosting view's root.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Update tests

**Files:**
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Update late-registration test**

The test `latePaneHostRegistration_mountsIntoExistingTabHostAfterViewRevisionBump` no longer needs `bumpViewRevision()`. The `register()` call itself triggers invalidation via the slot. Rename and update:

```swift
@Test
func latePaneHostRegistration_mountsIntoExistingTabHost() async throws {
    let harness = makeHarness()
    defer {
        PaneViewRepresentable.onDismantleForTesting = nil
        try? FileManager.default.removeItem(at: harness.tempDir)
    }

    let pane = harness.store.createPane(
        source: .floating(workingDirectory: harness.tempDir, title: "Late"),
        provider: .zmx
    )
    let tab = Tab(paneId: pane.id, name: "Late")
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    harness.controller.view.layoutSubtreeIfNeeded()

    let latePaneHost = PaneHostView(paneId: pane.id)
    #expect(latePaneHost.window == nil)

    // register() auto-invalidates via @Observable slot — no bumpViewRevision needed
    harness.viewRegistry.register(latePaneHost, for: pane.id)
    for _ in 0..<50 {
        harness.controller.view.layoutSubtreeIfNeeded()
        if latePaneHost.window != nil {
            break
        }
        await Task.yield()
    }

    #expect(latePaneHost.window != nil)
}
```

- [ ] **Step 2: Update withinTabStateChanges test**

This test currently uses `store.bumpViewRevision()` as the mutation trigger. Replace with a benign store mutation that triggers a SwiftUI body re-evaluation (e.g., `store.setActivePaneId(pane.id, inTab: tab.id)` or toggling a store field). The test's purpose is proving re-renders don't cause dismantle — any store mutation that triggers re-evaluation works.

- [ ] **Step 3: Update architecture tests**

In `CoordinationPlaneArchitectureTests.swift`:
- Remove assertions checking for `viewRevision` or `bumpViewRevision` in source files
- Add `viewRegistrySource` to `LifecycleCompositionSources` struct and `loadLifecycleCompositionSources` method (load `Sources/AgentStudio/App/Panes/ViewRegistry.swift`)
- Add assertions:
  - `sources.viewRegistrySource.contains("PaneViewSlot")`
  - `sources.viewRegistrySource.contains("@Observable")`
  - `sources.viewRegistrySource.contains("ensureSlot")`
  - `sources.viewRegistrySource.contains("removeSlot")`

- [ ] **Step 4: Run all tests**

Run: `mise run test`
Expected: ALL PASS

- [ ] **Step 5: Run lint**

Run: `mise run lint`
Expected: ZERO errors

- [ ] **Step 6: Commit**

```bash
git add Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift \
       Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "test: update tests for per-pane @Observable slots

Late-registration test no longer needs bumpViewRevision().
Architecture tests verify PaneViewSlot, ensureSlot, removeSlot.
withinTabStateChanges test uses benign store mutation instead of bump.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Final verification

- [ ] **Step 1: Full build**

Run: `mise run build`
Expected: PASS

- [ ] **Step 2: Full test suite**

Run: `mise run test`
Expected: ALL PASS — show pass/fail counts

- [ ] **Step 3: Lint**

Run: `mise run lint`
Expected: ZERO errors

- [ ] **Step 4: Grep for any remaining viewRevision references**

Run: `grep -r "viewRevision\|bumpViewRevision" Sources/ Tests/ --include="*.swift" | grep -v "\.build/"`
Expected: ZERO matches (or only in comments explaining the removal)

- [ ] **Step 5: Verify slot lifecycle correctness**

Grep for `removeSlot` and `ensureSlot` calls. Verify that:
- Every `store.createPane()` has a corresponding `viewRegistry.ensureSlot(for:)` nearby
- Every permanent pane removal path (`store.removePane()`) has a corresponding `viewRegistry.removeSlot(for:)` nearby
- `unregister()` is NOT followed by `removeSlot()` unless the pane is being permanently removed

- [ ] **Step 6: Verify no unnecessary reparenting**

Manually trace the signal flow for these scenarios and confirm expected behavior:

1. **Late registration:** Register a pane host after tab is mounted → tab-local `FlatPaneStripContent` body re-evaluates, SwiftUI diffs to the one changed pane segment. Other panes in the same tab: diffed but unchanged. Other tabs: untouched.

2. **Resize:** Drag a split divider → store `@Observable` fires (layout change) → `FlatPaneStripContent` ForEach updates frame sizes. ViewRegistry slots: silent. No mount/unmount.

3. **Tab switch:** AppKit show/hide on `PersistentTabHostView`. No SwiftUI work at all.

4. **Close pane:** Store layout change drives ForEach to drop the segment. Slot fires (host=nil) but is harmless — segment already gone. `removeSlot` cleans up.

5. **New pane (split):** `ensureSlot` creates slot proactively. Store layout change adds ForEach segment. Slot fires to mount the host into the new segment.

6. **Move pane A→B:** Store layout changes for both tabs. Pane X unmounts from tab A (segment removed), mounts in tab B (segment added). Only pane X remounts — other panes in both tabs untouched. ViewRegistry unchanged.

- [ ] **Step 7: Commit if any fixes were needed**

---

## Invariants

After this plan is complete:

1. **No viewRevision anywhere** — the counter, the method, all call sites, all reads: deleted.
2. **No rootView replacement** — `PersistentTabHostView.update(rootView:)` deleted. The hosting view's root is set once at creation and never replaced.
3. **Tab-local invalidation, pane-local diff** — registering a view for pane X re-evaluates the tab-local `FlatPaneStripContent` body; SwiftUI's diff isolates the change to the affected pane segment.
4. **Zero cross-tab blast radius** — tabs that don't own the registered pane see no re-evaluation.
5. **Automatic invalidation** — no manual bridge needed. `register()` → slot mutation → `@Observable` fires → SwiftUI mounts the view.
6. **Two independent mechanisms** — store `@Observable` drives structure/layout, slot `@Observable` drives host availability. They never conflict.
7. **Pane-lifetime slot identity** — slots survive unregister/re-register cycles. Created proactively via `ensureSlot`, removed only on permanent pane deletion via `removeSlot`.
8. **No mutation during SwiftUI body evaluation** — slots are created proactively by PaneCoordinator in all four entry points (creation, hydration, undo, repair) before any SwiftUI body reads them. Lazy fallback exists as a safety net with a logged warning — if it fires in normal operation, an `ensureSlot` call was missed.
9. **removeSlot ordering** — `removeSlot(for:)` is called only after the pane's ForEach segment has been dropped (layout removal) AND `store.removePane()` has been called, in the same synchronous `@MainActor` method. Never called on plain unregister (repair/teardown-for-recreation).
