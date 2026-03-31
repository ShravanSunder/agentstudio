# Canonical Pane Ownership Validation Design

**Date:** 2026-03-31 (rev 3 — post Codex review)

## Background: Tabs Own More Panes Than They Show

A tab owns panes across **multiple arrangements**. Think of arrangements as saved
workspace layouts — "coding" shows panes A, B, C; "reviewing" shows panes A and D.
The panes B, C, D all exist and have running terminals, but only some are visible
at any given time.

```
Tab owns:          [A, B, C, D]          ← canonical ownership (tab.panes)
"coding" shows:    [A, B, C]             ← one arrangement
"reviewing" shows: [A, D]                ← another arrangement
active arrangement: "coding"

tab.panes     = [A, B, C, D]            ← all owned panes
tab.paneIds   = [A, B, C]               ← only the active arrangement
```

Pane D is alive (terminal running) but not in the active arrangement. It's hidden,
not deleted. If pane D's shell exits, the system needs to close it. But the action
validator only knows about panes in the active arrangement and rejects the close.

## The Current Workaround: `executeTrusted`

Two paths exist through `ActionExecutor`:

```
User action (keyboard, click, command bar):
    ActionExecutor.execute(action)
    → ActionValidator.validate(action, snapshot)    ← checks active arrangement
    → if valid: coordinator.execute(validated)
    → if invalid: log warning, drop action

System action (process termination):
    ActionExecutor.executeTrusted(action)
    → coordinator.execute(action)                   ← skips validation entirely
```

`executeTrusted` exists solely because the validator doesn't have canonical ownership
information. It's a bypass that:
- Lets system events close panes the validator would wrongly reject
- Provides zero validation for system-originated actions
- Creates a second code path that any caller could misuse

## Problem

Seven concrete bugs exist because the validator, resolver, and process-termination
paths only see the active arrangement, not canonical ownership:

### Bug 1: closePane→closeTab collapse kills entire tab (two sites)

**ActionValidator.swift:68**: When `tab.paneCount <= 1`, closePane is escalated to
closeTab. But `paneCount` is arrangement-scoped.

**ActionResolver.swift:60**: Same collapse — `tab.allPaneIds.count <= 1` also uses
arrangement scope (via `ResolvableTab.allPaneIds` which returns `tab.paneIds`).

Both sites: a tab with 1 visible pane and 3 hidden panes would close the entire
tab (killing all 4 panes) when a single hidden pane terminates.

```
Tab owns:    [A, B, C, D]
Arrangement: [A]              ← paneCount = 1
D terminates → closePane(D) → validator/resolver sees count=1 → escalates to closeTab
→ A, B, C also destroyed
```

### Bug 2: Process termination uses arrangement `isSplit` for close decision

`PaneTabViewController.swift:822`: For visible panes, the code uses `tab.isSplit`
(arrangement) to decide pane-close vs tab-close. If the arrangement shows 1 pane
but the tab canonically owns more, it dispatches closeTab instead of closePane.

### Bug 3: Undo anchor for hidden pane uses wrong pane set

`WorkspaceStore.swift:1698`: `snapshotForPaneClose` finds the reinsertion anchor
from `tab.paneIds` (arrangement). On undo, a hidden pane would reappear in the
active arrangement at the wrong position — or worse, `insertPane` at
`WorkspaceStore.swift:1757` would make a previously hidden pane visible.

### Bug 4: Close-worktree-terminal misses hidden panes (two sites)

`PaneTabViewController.swift:679,689`: `closeTerminal(for:)` searches `tab.paneIds`
for a pane matching the worktree. A pane hidden in the current arrangement is
invisible to this search. The close decision at line 687 also uses `tab.isSplit`.

### Bug 5: openTerminal searches arrangement only

`PaneCoordinator+ActionExecution.swift:24`: `openTerminal(for:)` checks if a tab
already has a pane for the worktree using `tab.paneIds`. A hidden pane is missed,
so the coordinator creates a duplicate instead of navigating to the existing one.

### Bug 6: closePlaceholderPane uses arrangement `isSplit`

`PaneCoordinator+TerminalPlaceholders.swift:71`: `closePlaceholderPane` decides
pane-close vs tab-close using `tab.isSplit`. If canonical has more panes than the
arrangement, it wrongly dispatches closeTab.

### Bug 7: Pane removal only sweeps active + default arrangements

`WorkspaceStore.swift:546-569`: `removePaneFromLayout` removes a pane from the
active arrangement and default arrangement, but not from other custom arrangements.
A hidden pane close can leave stale pane IDs in non-active custom arrangements.

## Design

### Principle: Surgical fixes at specific sites — no broad rename

The audit found that 14 of 18 `tab.paneIds` call sites correctly need arrangement
scope (UI rendering, geometry sync, arrangement saving, drop resolution). A rename
would be cosmetic churn. `ResolvableTab.allPaneIds` returning arrangement-only is
correct for navigation and resolution — those operations act on what the user sees.

The fix is:
1. Give `TabSnapshot` a second field so the validator can distinguish canonical from arranged
2. Fix the resolver's closePane collapse
3. Update the 7 buggy sites to use canonical where appropriate
4. Fix pane removal to sweep all arrangements
5. Delete `executeTrusted`

### 1. Expand `TabSnapshot` with canonical ownership

```swift
struct TabSnapshot: Equatable {
    let id: UUID
    let arrangedPaneIds: [UUID]     // active arrangement layout (was: paneIds)
    let canonicalPaneIds: [UUID]    // all owned panes (tab.panes)
    let activePaneId: UUID?         // may point to a hidden pane — that's OK,
                                    // arrangement navigation will exclude it

    // Arrangement-scoped (unchanged behavior for UI/navigation validation)
    var isSplit: Bool { arrangedPaneIds.count > 1 }
    var paneCount: Int { arrangedPaneIds.count }

    // Canonical-scoped (new — for lifecycle validation)
    var canonicalPaneCount: Int { canonicalPaneIds.count }

    func ownsPane(_ paneId: UUID) -> Bool {
        canonicalPaneIds.contains(paneId)
    }

    func arrangedContains(_ paneId: UUID) -> Bool {
        arrangedPaneIds.contains(paneId)
    }
}
```

The old `paneIds` field is renamed to `arrangedPaneIds` **only inside TabSnapshot**.
`Tab.paneIds` stays as-is on the model — no rename there.

### 2. Split `ActionStateSnapshot` into two lookup maps

The snapshot needs TWO pane→tab lookups because different validator cases need
different scopes:

```swift
struct ActionStateSnapshot {
    /// Finds the tab that OWNS a pane (canonical — any arrangement)
    /// Used by: closePane, removeDrawerPane, insertPane(source: .existingPane)
    private let canonicalPaneToTab: [UUID: UUID]

    /// Finds the tab where a pane is VISIBLE (arrangement — active layout only)
    /// Used by: insertPane(target), focusPane, resizePane, extractPane, mergeTab
    private let arrangedPaneToTab: [UUID: UUID]

    init(tabs: [TabSnapshot], ...) {
        var canonical: [UUID: UUID] = [:]
        var arranged: [UUID: UUID] = [:]
        for tab in tabs {
            for paneId in tab.canonicalPaneIds {
                canonical[paneId] = tab.id
            }
            for paneId in tab.arrangedPaneIds {
                arranged[paneId] = tab.id
            }
        }
        // Drawer panes → same tab as parent (canonical)
        for (drawerPaneId, parentPaneId) in drawerParentByPaneId {
            canonical[drawerPaneId] = canonical[parentPaneId]
        }
        self.canonicalPaneToTab = canonical
        self.arrangedPaneToTab = arranged
    }

    /// Does this tab OWN the pane? (any arrangement)
    func tabOwnsPane(_ tabId: UUID, paneId: UUID) -> Bool {
        canonicalPaneToTab[paneId] == tabId
    }

    /// Is this pane VISIBLE in its tab's active arrangement?
    func tabArrangesPane(_ tabId: UUID, paneId: UUID) -> Bool {
        arrangedPaneToTab[paneId] == tabId
    }

    /// Find the tab that owns a pane (canonical)
    func tabOwning(paneId: UUID) -> TabSnapshot? {
        guard let tabId = canonicalPaneToTab[paneId] else { return nil }
        return tab(tabId)
    }

    /// Find the tab where a pane is arranged (visible)
    func tabArranging(paneId: UUID) -> TabSnapshot? {
        guard let tabId = arrangedPaneToTab[paneId] else { return nil }
        return tab(tabId)
    }
}
```

The existing `tabContainsPane` and `tabContaining(paneId:)` are REMOVED — they
were ambiguous. Callers must explicitly choose `tabOwnsPane`/`tabOwning` (canonical)
or `tabArrangesPane`/`tabArranging` (arrangement).

This prevents the bug where `insertPane`, `mergeTab`, `reactivatePane` would
accept hidden panes as targets. Those validators use `tabArrangesPane` — the
target must be visible.

### 3. Update validator — per-action ownership scope

Each validation case uses the right scope. **Source/lifecycle panes** use canonical
(any owned pane). **Target/interaction panes** use arrangement (must be visible).

| Action | Pane role | Scope | Snapshot method | Reason |
|--------|-----------|-------|-----------------|--------|
| `closePane` | source | canonical | `tabOwnsPane` | Any owned pane can be closed |
| `closeTab` | — | tab exists | — | Tab-level, no pane check |
| `breakUpTab` | — | arrangement | `tab.isSplit` | Can only break up what user sees |
| `extractPaneToTab` | source | arrangement | `tabArrangesPane` | Can only extract visible panes |
| `focusPane` | target | arrangement | `tabArrangesPane` | Can only focus visible panes |
| `resizePane` | target | arrangement | `tab.isSplit` | Can only resize visible layout |
| `equalizePanes` | — | arrangement | `tab.isSplit` | Can only equalize visible layout |
| `duplicatePane` | source | arrangement | `tabArrangesPane` | Can only duplicate visible panes |
| `toggleSplitZoom` | target | arrangement | `tabArrangesPane` | Can only zoom visible panes |
| `minimizePane` | target | arrangement | `tabArrangesPane` | Can only minimize visible panes |
| `expandPane` | target | arrangement | `tabArrangesPane` | Can only expand visible panes |
| `insertPane` target | target | arrangement | `tabArrangesPane` | Can only split next to visible |
| `insertPane` source (.existingPane) | source | canonical | `tabOwnsPane` | Moving works on any owned pane |
| `mergeTab` target | target | arrangement | `tabArrangesPane` | Target pane must be visible |
| `reactivatePane` | target | arrangement | `tabArrangesPane` | Can only reactivate visible |
| `removeDrawerPane` | source | canonical | `tabOwnsPane` | Drawers can close regardless |

### 4. Fix closePane→closeTab collapse (BOTH sites)

**ActionValidator** must use canonical count:

```swift
case .closePane(let tabId, let paneId):
    guard let tab = state.tab(tabId) else {
        return .failure(.tabNotFound(tabId: tabId))
    }
    guard tab.ownsPane(paneId) else {
        return .failure(.paneNotFound(paneId: paneId, tabId: tabId))
    }
    // Use CANONICAL count — arrangement may hide siblings
    if tab.canonicalPaneCount <= 1 {
        return .success(ValidatedAction(.closeTab(tabId: tabId)))
    }
    return .success(ValidatedAction(action))
```

**ActionResolver** also collapses using `allPaneIds.count`. Since `allPaneIds`
stays arrangement-scoped (correct for resolver's navigation role), and the
resolver's collapse is a pre-validation convenience, the resolver collapse is
acceptable — the validator will independently verify using canonical count.

**Intentional asymmetry (UX decision):** The resolver and validator use different
scopes for the same action. This is a deliberate product choice:

- Resolver operates on user intent — when the user closes the arrangement's only
  visible pane, escalating to closeTab is the right UX. The user sees one pane,
  they close it, the tab goes away.
- Validator operates on state invariants — when a hidden pane terminates and
  closePane arrives, canonical count prevents escalation because siblings exist.

**Product consequence:** User pressing Cmd+W on a single-visible-pane arrangement
closes the entire tab, including hidden panes in other arrangements. This is
intentional — each arrangement is a view into the tab, not a protection boundary.
Closing the last visible pane means "I'm done with this tab." If the user wants
to keep hidden panes alive, they should switch to an arrangement that shows them
first, or use per-pane close (which is only available in multi-pane arrangements).

If this UX decision changes in the future (e.g., "close pane should only close
the pane, never the tab, even if it's the last visible one"), then the resolver
collapse must also move to canonical count. Document this dependency.

### 5. Fix process termination path

`PaneTabViewController.handleTerminalProcessTerminated` uses one path for all
panes. No `executeTrusted`, no hidden-vs-visible branching:

```swift
func handleTerminalProcessTerminated(paneId: UUID) {
    guard let pane = store.pane(paneId) else { return }

    // Drawer child: direct removal
    if let parentPaneId = pane.parentPaneId,
        store.tabContaining(paneId: parentPaneId) != nil
    {
        dispatchAction(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
        return
    }

    // Layout pane: close through validated path
    // Use canonical count (tab.panes) not arrangement (tab.isSplit)
    if let tab = store.tabContaining(paneId: paneId) {
        if tab.panes.count > 1 {
            dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
        } else {
            dispatchAction(.closeTab(tabId: tab.id))
        }
        return
    }
}
```

Note: `tab.panes.count > 1` is a pre-filter to decide closePane vs closeTab
before validation. Safe because the validator independently verifies.

**Behavior change for visible panes too:** The current visible-pane path (line 822)
uses `tab.isSplit` (arrangement). In a multi-arrangement tab where the arrangement
shows 1 pane, a visible pane termination currently closes the entire tab. After
this fix, it dispatches closePane because canonical count > 1. This is correct —
hidden siblings should not be killed by a visible pane's process termination.

### 6. Hidden pane closes are not undoable

Process-termination closes of hidden panes should NOT create undo entries. The pane
was invisible to the user — offering undo for an invisible close is confusing, and
the reinsertion anchor logic (`snapshotForPaneClose`) uses arrangement scope which
would place the pane incorrectly on undo.

In `PaneCoordinator.executeClosePane`, skip the undo snapshot when the pane is not
in the active arrangement:

```swift
private func executeClosePane(tabId: UUID, paneId: UUID) {
    guard let tab = store.tab(tabId) else { return }

    // Only snapshot for undo if pane is in the active arrangement.
    // Hidden pane closes (process termination) are not user-undoable.
    if tab.paneIds.contains(paneId) {
        if let snapshot = store.snapshotForPaneClose(paneId: paneId, inTab: tabId) {
            appendUndoEntry(.pane(snapshot))
        }
    }

    // ... rest of close logic unchanged
}
```

### 7. Fix close-worktree-terminal to search canonical

`PaneTabViewController.closeTerminal(for:)` at lines 679 and 689: search
`tab.panes` instead of `tab.paneIds`. Also fix the close decision at line 687
to use `tab.panes.count > 1` instead of `tab.isSplit`.

### 8. Fix openTerminal — hidden panes are not navigable

`PaneCoordinator+ActionExecution.swift:24`: `openTerminal(for:)` checks if a pane
already exists for the worktree. Currently uses `tab.paneIds` (arrangement).

**UX decision:** Hidden panes are NOT navigable. When the user asks to open a
terminal for a worktree, they expect to see it. If the matching pane exists but
is hidden in another arrangement, create a new visible one — don't silently
activate a tab where the pane is invisible.

The search stays arrangement-scoped (`tab.paneIds`). No change needed here.
Duplicates across arrangements are acceptable — each arrangement is a different
workspace context. The real duplicate protection is within the same arrangement,
which the current code already handles.

**Removed from the fix list** — current behavior is correct for this case.

### 9. Fix closePlaceholderPane — both search and close decision

`PaneCoordinator+TerminalPlaceholders.swift:70-77`: Two fixes needed:

1. **Search**: Change `store.tabs.first(where: { $0.paneIds.contains(paneId) })`
   to `store.tabs.first(where: { $0.panes.contains(paneId) })` — find placeholder
   pane even if hidden in current arrangement.

2. **Decision**: Change `tab.isSplit` to `tab.panes.count > 1` — use canonical
   count so a hidden placeholder doesn't kill the whole tab.

### 10. Fix pane removal to sweep ALL arrangements

`WorkspaceStore.removePaneFromLayout` at lines 546-569 currently removes panes from
only the active and default arrangements. Add a sweep of all custom arrangements:

```swift
// After removing from active + default, sweep ALL custom arrangements.
// Must update BOTH layout and visiblePaneIds to maintain the invariant:
//   arrangement.layout.paneIds == arrangement.visiblePaneIds
for i in tabs[tabIndex].arrangements.indices {
    // Update layout
    if let updated = tabs[tabIndex].arrangements[i].layout.removing(paneId: paneId) {
        tabs[tabIndex].arrangements[i].layout = updated
    } else {
        tabs[tabIndex].arrangements[i].layout = Layout()
    }
    // Update visiblePaneIds to stay in sync with layout
    tabs[tabIndex].arrangements[i].visiblePaneIds.remove(paneId)
}
```

Both `layout` and `visiblePaneIds` are updated together. Leaving `visiblePaneIds`
stale is an invariant violation that the repair logic would catch and fix, but
the spec must not introduce fresh drift as normal behavior.

If a custom arrangement becomes completely empty after the sweep, it gets
`Layout()` and an empty `visiblePaneIds`. The UI should handle empty
arrangements gracefully (show empty state or auto-remove the arrangement).

### 11. Delete `executeTrusted`

Remove `ActionExecutor.executeTrusted(_:)` entirely. Its only caller
(`PaneTabViewController.handleTerminalProcessTerminated` lines 816, 818) is
replaced by `dispatchAction` in section 5. Add an architecture test asserting
`executeTrusted` does not exist.

## What doesn't change

- `Tab.paneIds` — stays as active arrangement accessor (no rename on the model)
- `Tab.panes` — canonical ownership list, unchanged
- `Tab.isSplit` — stays arrangement-scoped (correct for UI rendering)
- `Layout.paneIds` — spatial ordering within arrangement, unchanged
- `ResolvableTab.allPaneIds` — stays arrangement-scoped (correct for resolution)
- `PaneArrangement` model — unchanged
- `PaneCoordinator.execute()` — unchanged, receives validated actions
- All UI rendering paths — unchanged, correctly use arrangement
- `ActionResolver` closePane collapse — stays arrangement-scoped (validator is authoritative)

## Risk

Medium. The changes touch 7 specific locations plus the snapshot/validator layer.
The `TabSnapshot` expansion is additive (new field, rename existing). The validator
changes are per-case decisions grounded in the audit. The `executeTrusted` deletion
removes code.

Main risks:
- closePane→closeTab escalation change: canonical count means a tab with hidden
  panes won't escalate to closeTab when arrangement shows 1 pane. This is correct
  but changes behavior from what exists today.
- Pane removal sweep of all arrangements: must handle the case where a custom
  arrangement's layout becomes empty after removal.
- undo skip for hidden panes: if a user manually closes a hidden pane through a
  future UI (e.g. arrangement manager), they'd expect undo. The current rule is
  "hidden = no undo" which is correct for process termination but may need
  revisiting when user-initiated hidden close exists.

## Test plan

- Existing validator tests: update `TabSnapshot` construction to include
  `canonicalPaneIds` (same as `arrangedPaneIds` for current tests — behavior
  unchanged for single-arrangement tabs)
- New test: validator approves `closePane` for canonical-but-hidden pane
- New test: validator rejects `focusPane` for canonical-but-hidden pane
- New test: closePane does NOT escalate to closeTab when canonical count > 1
  but arrangement count = 1
- New test: closePane DOES escalate to closeTab when canonical count = 1
- New test: hidden pane close does not create undo entry
- New test: visible pane close still creates undo entry
- New test: `removePaneFromLayout` removes from all arrangements
- New test: `openTerminal` finds existing hidden pane instead of creating duplicate
- Architecture test: assert `executeTrusted` does not exist in ActionExecutor
- Architecture test: assert `TabSnapshot` has both `arrangedPaneIds` and
  `canonicalPaneIds`
