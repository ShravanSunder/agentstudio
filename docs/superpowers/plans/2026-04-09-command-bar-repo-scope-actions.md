# Command Bar — Unified Worktree Actions & Everything Scope

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unified worktree rows with presence awareness, modifier-key actions (⌘↵ new tab, ⌥↵ current tab), drill-in for multi-pane worktrees — in both `#` (repos) scope and the default everything scope. Tab items become searchable by name and arrangement names. All panes remain visible (no suppression).

**Architecture:** Introduce a `WorktreePresence` model that pairs a worktree with its open panes/tabs. Both `repoScopeItems` and `everythingItems` use this model to build unified worktree rows. The `CommandBarTextField` gains modifier-key detection on Enter. The `CommandBarFooter` becomes dynamic based on selected item state. A new `CommandBarAction.worktreeAction` variant lets the view resolve the correct action at execution time. Tab items gain arrangement-name keywords for search. The old `worktreeItems` helper (everything scope) is replaced by the same unified builder used in repos scope.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (NSTextField key events), Swift Testing

---

## Visual Design

### Mental Model — What "opening" means

A worktree is a directory on disk. Opening it means creating a pane for it. The only question is where the pane goes:

```
  ⌘↵  New pane in NEW tab
       ┌──────────┐
       │ Tab (new) │
       │ ┌──────┐ │
       │ │ Pane │ │  ← new pane, new tab
       │ └──────┘ │
       └──────────┘

  ⌥↵  New pane in CURRENT tab
       ┌──────────────────────┐
       │ Tab (current)        │
       │ ┌──────┐  ┌──────┐  │
       │ │exist.│  │ Pane │  │  ← new pane, current tab
       │ │ pane │  │(new) │  │
       │ └──────┘  └──────┘  │
       └──────────────────────┘

  ↵   Navigate to existing pane
       (no new pane created)
```

### `#` Scope — Repos/Worktrees

**Worktree with 1 pane open:**
```
┌─────────────────────────────────────────────────────┐
│  #  my-repo                                         │
├─────────────────────────────────────────────────────┤
│                                                     │
│  MY-REPO (WORKTREES)                                │
│  ┌─────────────────────────────────────────────────┐│
│  │ ⑂  main                  ● Tab 1 · 1 pane      ││
│  │ ⑂  feat-x                ● Tab 3 · 1 pane      ││
│  │ ⑂  hotfix                                       ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
├─────────────────────────────────────────────────────┤
│  ↵ Go to   ⌘↵ New tab   ⌥↵ Open in tab   esc Close│
└─────────────────────────────────────────────────────┘
```

**Worktree with multiple panes (▸ = drill-in):**
```
┌─────────────────────────────────────────────────────┐
│  #  my-repo                                         │
├─────────────────────────────────────────────────────┤
│                                                     │
│  MY-REPO (WORKTREES)                                │
│  ┌─────────────────────────────────────────────────┐│
│  │ ⑂  main                  ● 3 panes · 2 tabs ▸  ││
│  │ ⑂  feat-x                ● Tab 3 · 1 pane      ││
│  │ ⑂  hotfix                                       ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
├─────────────────────────────────────────────────────┤
│  ↵ Choose pane   ⌘↵ New tab   ⌥↵ Open in tab      │
└─────────────────────────────────────────────────────┘
```

**Drill-in level (↵ on multi-pane worktree):**
```
┌─────────────────────────────────────────────────────┐
│  #  my-repo ❯ main                                  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  NAVIGATE TO                                        │
│  ┌─────────────────────────────────────────────────┐│
│  │ 🖥  Terminal — main       Tab 1 · Active         ││
│  │ 🖥  Terminal — main       Tab 1 · Drawer         ││
│  │ 🖥  Terminal — main       Tab 4                  ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
│  OPEN NEW                                           │
│  ┌─────────────────────────────────────────────────┐│
│  │ +  New pane in new tab              ⌘↵          ││
│  │ +  New pane in current tab          ⌥↵          ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
├─────────────────────────────────────────────────────┤
│  ↵ Select   ⌫ Back   esc Close                     │
└─────────────────────────────────────────────────────┘
```

**Not-open worktree, bare ↵ → choice level:**
```
┌─────────────────────────────────────────────────────┐
│  #  my-repo ❯ hotfix                                │
├─────────────────────────────────────────────────────┤
│                                                     │
│  OPEN                                               │
│  ┌─────────────────────────────────────────────────┐│
│  │ +  New pane in new tab              ⌘↵          ││
│  │ +  New pane in current tab          ⌥↵          ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
├─────────────────────────────────────────────────────┤
│  ↵ Select   ⌫ Back   esc Close                     │
└─────────────────────────────────────────────────────┘
```

**Not-open worktree, no tabs in app (only one option):**
```
│  │ ⑂  hotfix                                       ││  ← selected
├─────────────────────────────────────────────────────┤
│  ↵ Open in new tab   esc Close                     │
```

### Everything Scope — No Prefix

All groups coexist. No suppression. Each answers a different question.

```
┌─────────────────────────────────────────────────────┐
│  🔍  my-repo                                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  WORKTREES                                          │
│  │ ⑂  my-repo / main        ● Tab 1 · 1 pane      ││  ← unified, modifiers
│  │ ⑂  my-repo / feat-x      ● Tab 3 · 1 pane      ││
│  │ ⑂  my-repo / hotfix                             ││
│                                                     │
│  TABS                                               │
│  │ 📚 my-repo                Tab 1 · Active         ││  ← searchable by name
│                                                     │
│  PANES                                              │
│  │ 🖥  Terminal — main        Tab 1 · Active        ││  ← all panes, always
│  │ 🖥  Terminal — feat-x      Tab 3                 ││
│  │ 🖥  Floating terminal      Tab 2                 ││
│                                                     │
│  COMMANDS                                           │
│  │ ▸  Remove Repo                   →              ││
│                                                     │
├─────────────────────────────────────────────────────┤
│  ↵ Go to   ⌘↵ New tab   ⌥↵ Open in tab   esc Close│
│  (footer adapts per selected item type)             │
└─────────────────────────────────────────────────────┘
```

### Dynamic Footer per Item Type

```
  Worktree (1 pane)    → ↵ Go to   ⌘↵ New tab   ⌥↵ Open in tab   esc Close
  Worktree (N panes)   → ↵ Choose pane   ⌘↵ New tab   ⌥↵ Open in tab   esc
  Worktree (not open)  → ↵ Choose   ⌘↵ New tab   ⌥↵ Open in tab   esc Close
  Worktree (no tabs)   → ↵ New tab   esc Close
  Tab selected         → ↵ Go to   ↑↓ Navigate   esc Close
  Pane selected        → ↵ Go to   ↑↓ Navigate   esc Close
  Command selected     → ↵ Open    → Drill in    esc Close
  Nested level         → ↵ Select  ⌫ Back   esc Close
```

---

## Design Decisions

**No dedup / no suppression:** All panes show in the Panes group regardless of worktree binding. All tabs show in the Tabs group. Worktree rows exist alongside them — each group answers a different question:
- **Worktrees** — "I want to work on this codebase" (presence + open actions)
- **Tabs** — "I want that tab layout" (navigate by name/arrangement)
- **Panes** — "I want that specific terminal" (navigate by title/cwd/branch)
- **Commands** — "I want to do something"

**Command mapping:**
- `⌘↵` "New tab" dispatches `.openNewTerminalInTab` (always creates a new tab) — NOT `.openWorktree` (which navigates to existing)
- `⌥↵` "Open in tab" dispatches `.openWorktreeInPane` (adds pane to current tab)
- `↵` "Go to" dispatches `.focusPane` (navigates to existing pane)

**Out of scope — window identity:** The app supports multiple windows, but this plan models presence as pane + tab location only. "Navigate across windows" is a follow-up.

**Dynamic footer:** Footer hints change based on selected item type:
- Worktree selected → full modifier set per state matrix
- Tab/Pane/Command selected → standard `↵ Go to / Open` hints

**Modifier state matrix:**

| Selected worktree state | App has tabs? | ↵ (bare Enter) | ⌘↵ | ⌥↵ |
|-------------------------|---------------|-----------------|-----|-----|
| 1 pane open | yes | Go to pane | New tab | Open in tab |
| 1 pane open | n/a* | Go to pane | New tab | — |
| N panes open | yes | Drill in (choose) | New tab | Open in tab |
| N panes open | n/a* | Drill in (choose) | New tab | — |
| Not open | yes | Choose (drill in) | New tab | Open in tab |
| Not open | no | New tab (only option) | — | — |

*If panes exist, at least one tab exists.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/AgentStudio/Features/CommandBar/WorktreePresence.swift` | Model: worktree + its open panes + tab locations |
| Modify | `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift` | Add `CommandBarAction.worktreeAction`; add `WorktreeOpenState` to item; add `FooterHint` model |
| Modify | `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` | Rewrite `repoScopeItems` and `everythingItems` with unified worktree rows; enhance tab keywords |
| Modify | `Sources/AgentStudio/Features/CommandBar/Views/CommandBarTextField.swift` | Detect ⌘↵ and ⌥↵ modifier keys on Enter |
| Modify | `Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift` | Plumb `onModifierEnter` callback |
| Modify | `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift` | Handle modifier-aware execution; compute dynamic footer hints |
| Modify | `Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift` | Accept `[FooterHint]` instead of booleans; render dynamically |
| Modify | `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultRow.swift` | Show presence indicator (●) for open worktrees |
| Create | `Tests/AgentStudioTests/Features/CommandBar/WorktreePresenceTests.swift` | Tests for presence computation |
| Create | `Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift` | Tests for dynamic footer hint generation per item state |
| Modify | `Tests/AgentStudioTests/Helpers/CommandBarFactories.swift` | Add `worktreeOpenState` param to `makeCommandBarItem` factory |
| Modify | `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift` | Tests for unified worktree rows in both scopes; tab keyword tests |

---

## Task 1: WorktreePresence Model

**Files:**
- Create: `Sources/AgentStudio/Features/CommandBar/WorktreePresence.swift`
- Create: `Tests/AgentStudioTests/Features/CommandBar/WorktreePresenceTests.swift`

This model computes which panes are open for a given worktree and where they live. Pure data, no side effects.

- [ ] **Step 1: Write failing tests for WorktreePresence.build**

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorktreePresenceTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    private func makeStore() -> WorkspaceStore {
        let store = WorkspaceStore()
        atom(\.workspaceFocusContext).startObserving(store: store)
        return store
    }

    @Test
    func test_build_worktreeWithNoPanes_returnsEmptyPresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-test"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-test"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let presence = WorktreePresence.build(
            worktree: worktree,
            repo: repo,
            store: store
        )

        #expect(presence.worktreeId == worktree.id)
        #expect(presence.repoId == repo.id)
        #expect(presence.openPanes.isEmpty)
        #expect(presence.openState == .notOpen)
    }

    @Test
    func test_build_worktreeWithOnePane_returnsSinglePanePresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-single"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/presence-single/feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminal"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let presence = WorktreePresence.build(
            worktree: worktree,
            repo: repo,
            store: store
        )

        #expect(presence.openPanes.count == 1)
        #expect(presence.openPanes[0].paneId == pane.id)
        #expect(presence.openPanes[0].tabId == tab.id)
        #expect(presence.openPanes[0].tabIndex == 0)
        #expect(presence.openState == .singlePane)
    }

    @Test
    func test_build_worktreeWithMultiplePanes_returnsMultiPanePresence() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-multi"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-multi"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let paneA = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "A"
        )
        let tabA = Tab(paneId: paneA.id)
        store.appendTab(tabA)

        let paneB = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "B"
        )
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabB)

        let presence = WorktreePresence.build(
            worktree: worktree,
            repo: repo,
            store: store
        )

        #expect(presence.openPanes.count == 2)
        #expect(presence.openState == .multiplePanes)
        let tabIds = Set(presence.openPanes.map(\.tabId))
        #expect(tabIds.contains(tabA.id))
        #expect(tabIds.contains(tabB.id))
    }

    @Test
    func test_build_computesDistinctTabCount() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/presence-tabs"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/presence-tabs"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let paneA = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "A"
        )
        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let paneB = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "B"
        )
        store.insertPane(paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after)

        let presence = WorktreePresence.build(
            worktree: worktree,
            repo: repo,
            store: store
        )

        #expect(presence.openPanes.count == 2)
        #expect(presence.distinctTabCount == 1)
        #expect(presence.openState == .multiplePanes)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorktreePresenceTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `WorktreePresence` doesn't exist yet.

- [ ] **Step 3: Implement WorktreePresence**

Create `Sources/AgentStudio/Features/CommandBar/WorktreePresence.swift`:

```swift
import Foundation

// MARK: - WorktreeOpenState

/// Whether a worktree has panes open and how many.
enum WorktreeOpenState {
    case notOpen
    case singlePane
    case multiplePanes
}

// MARK: - WorktreePaneLocation

/// A pane that is open for a specific worktree, with its tab location.
struct WorktreePaneLocation {
    let paneId: UUID
    let tabId: UUID
    let tabIndex: Int
    let isActiveInTab: Bool
}

// MARK: - WorktreePresence

/// Pairs a worktree with its currently open panes and their tab locations.
/// Used by the command bar to show unified worktree rows with presence indicators.
struct WorktreePresence {
    let worktreeId: UUID
    let repoId: UUID
    let worktreeName: String
    let repoName: String
    let isMainWorktree: Bool
    let openPanes: [WorktreePaneLocation]

    var openState: WorktreeOpenState {
        switch openPanes.count {
        case 0: return .notOpen
        case 1: return .singlePane
        default: return .multiplePanes
        }
    }

    var distinctTabCount: Int {
        Set(openPanes.map(\.tabId)).count
    }

    @MainActor
    static func build(
        worktree: Worktree,
        repo: Repo,
        store: WorkspaceStore
    ) -> WorktreePresence {
        let panes = store.panes(for: worktree.id)
        var locations: [WorktreePaneLocation] = []

        for pane in panes {
            guard let tab = store.tabContaining(paneId: pane.id),
                let tabIndex = store.tabs.firstIndex(where: { $0.id == tab.id })
            else { continue }

            let isActive = tab.activePaneId == pane.id
            locations.append(
                WorktreePaneLocation(
                    paneId: pane.id,
                    tabId: tab.id,
                    tabIndex: tabIndex,
                    isActiveInTab: isActive
                )
            )
        }

        return WorktreePresence(
            worktreeId: worktree.id,
            repoId: repo.id,
            worktreeName: worktree.name,
            repoName: repo.name,
            isMainWorktree: worktree.isMainWorktree,
            openPanes: locations
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorktreePresenceTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/WorktreePresence.swift Tests/AgentStudioTests/Features/CommandBar/WorktreePresenceTests.swift
git commit -m "feat(command-bar): add WorktreePresence model for worktree open-state tracking"
```

---

## Task 2: Modifier Key Detection in TextField

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarTextField.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`

The NSTextField intercepts Enter but doesn't pass modifier flags. We need ⌘↵ and ⌥↵.

- [ ] **Step 1: Add `EnterModifier` enum and update `onEnter` callback in `CommandBarTextField`**

Add to `CommandBarTextField.swift`, above the struct:

```swift
// MARK: - EnterModifier

/// Modifier key held when pressing Enter in the command bar.
enum EnterModifier {
    case none
    case command  // ⌘↵
    case option   // ⌥↵
}
```

Then change the `CommandBarTextField` struct:

Replace `let onEnter: () -> Void` with `let onEnter: (EnterModifier) -> Void`.

In the `Coordinator.control(_:textView:doCommandBy:)` method, replace the `insertNewline` case:

```swift
case #selector(NSResponder.insertNewline(_:)):
    let flags = NSApp.currentEvent?.modifierFlags ?? []
    let modifier: EnterModifier
    if flags.contains(.command) {
        modifier = .command
    } else if flags.contains(.option) {
        modifier = .option
    } else {
        modifier = .none
    }
    parent.onEnter(modifier)
    return true
```

- [ ] **Step 2: Update `CommandBarSearchField` to plumb the modifier**

In `CommandBarSearchField.swift`, change `let onEnter: () -> Void` to `let onEnter: (EnterModifier) -> Void`.

The `CommandBarTextField` init call already passes `onEnter: onEnter` — no change needed there since the type change flows through.

- [ ] **Step 3: Update `CommandBarView` to handle modifier enter**

In `CommandBarView.swift`, change the `CommandBarSearchField` init:

```swift
CommandBarSearchField(
    state: state,
    onArrowUp: { state.moveSelectionUp(totalItems: totalItems) },
    onArrowDown: { state.moveSelectionDown(totalItems: totalItems) },
    onEnter: { modifier in executeSelected(modifier: modifier) },
    onBackspaceOnEmpty: { handleBackspace() }
)
```

Change `executeSelected()` to `executeSelected(modifier: EnterModifier = .none)` and pass the modifier through to `executeItem`:

```swift
private func executeSelected(modifier: EnterModifier = .none) {
    guard let item = selectedItem else { return }
    executeItem(item, modifier: modifier)
}
```

Update `executeItem` to accept the modifier (for now, ignore it — Task 4 will use it):

```swift
private func executeItem(_ item: CommandBarItem, modifier: EnterModifier = .none) {
    if dimmedItemIds.contains(item.id) { return }

    switch item.action {
    case .dispatch(let command):
        state.recordRecent(itemId: item.id)
        onDismiss()
        dispatcher.dispatch(command)

    case .dispatchTargeted(let command, let target, let targetType):
        state.recordRecent(itemId: item.id)
        onDismiss()
        dispatcher.dispatch(command, target: target, targetType: targetType)

    case .navigate(let level):
        state.pushLevel(level)

    case .custom(let closure):
        state.recordRecent(itemId: item.id)
        onDismiss()
        closure()
    }
}
```

Also update the `onSelect` callback for `CommandBarResultsList`:

```swift
onSelect: { item in executeItem(item) }
```

This keeps mouse-click behavior as `.none` modifier — correct default.

- [ ] **Step 4: Build to verify compilation**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — no compile errors.

- [ ] **Step 5: Run full command bar test suite**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBar" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all existing tests still green.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/Views/CommandBarTextField.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift
git commit -m "feat(command-bar): detect ⌘↵ and ⌥↵ modifier keys on Enter"
```

---

## Task 3: Dynamic Footer Hints

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift` — add `FooterHint` model and `WorktreeOpenState` on item
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift` — render from `[FooterHint]`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift` — compute hints from selected item

- [ ] **Step 1: Add `FooterHint` model and `worktreeOpenState` to `CommandBarItem.swift`**

Add at the bottom of `CommandBarItem.swift`:

```swift
// MARK: - FooterHint

/// A single hint shown in the command bar footer (e.g., "⌘↵ New tab").
struct FooterHint: Identifiable {
    let id: String
    let key: String
    let label: String
}

// MARK: - FooterHintBuilder

/// Builds dynamic footer hints based on selected item state.
enum FooterHintBuilder {
    static func hints(
        for item: CommandBarItem?,
        isNested: Bool,
        hasTabsOpen: Bool
    ) -> [FooterHint] {
        guard !isNested else {
            return [
                FooterHint(id: "enter", key: "↵", label: "Select"),
                FooterHint(id: "navigate", key: "↑↓", label: "Navigate"),
                FooterHint(id: "back", key: "⌫", label: "Back"),
                FooterHint(id: "dismiss", key: "esc", label: "Close"),
            ]
        }

        guard let item else {
            return [
                FooterHint(id: "navigate", key: "↑↓", label: "Navigate"),
                FooterHint(id: "dismiss", key: "esc", label: "Close"),
            ]
        }

        guard let openState = item.worktreeOpenState else {
            // Non-worktree item — standard hints
            var hints = [FooterHint(id: "enter", key: "↵", label: "Open")]
            if item.hasChildren {
                hints.append(FooterHint(id: "drillin", key: "→", label: "Drill in"))
            }
            hints.append(FooterHint(id: "navigate", key: "↑↓", label: "Navigate"))
            hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close"))
            return hints
        }

        // Worktree item — dynamic hints based on open state
        switch openState {
        case .notOpen where !hasTabsOpen:
            return [
                FooterHint(id: "enter", key: "↵", label: "New tab"),
                FooterHint(id: "navigate", key: "↑↓", label: "Navigate"),
                FooterHint(id: "dismiss", key: "esc", label: "Close"),
            ]
        case .notOpen:
            return [
                FooterHint(id: "enter", key: "↵", label: "Choose"),
                FooterHint(id: "cmd-enter", key: "⌘↵", label: "New tab"),
                FooterHint(id: "opt-enter", key: "⌥↵", label: "Open in tab"),
                FooterHint(id: "navigate", key: "↑↓", label: "Navigate"),
                FooterHint(id: "dismiss", key: "esc", label: "Close"),
            ]
        case .singlePane:
            var hints = [
                FooterHint(id: "enter", key: "↵", label: "Go to"),
                FooterHint(id: "cmd-enter", key: "⌘↵", label: "New tab"),
            ]
            if hasTabsOpen {
                hints.append(FooterHint(id: "opt-enter", key: "⌥↵", label: "Open in tab"))
            }
            hints.append(FooterHint(id: "navigate", key: "↑↓", label: "Navigate"))
            hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close"))
            return hints
        case .multiplePanes:
            var hints = [
                FooterHint(id: "enter", key: "↵", label: "Choose pane"),
                FooterHint(id: "cmd-enter", key: "⌘↵", label: "New tab"),
            ]
            if hasTabsOpen {
                hints.append(FooterHint(id: "opt-enter", key: "⌥↵", label: "Open in tab"))
            }
            hints.append(FooterHint(id: "navigate", key: "↑↓", label: "Navigate"))
            hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close"))
            return hints
        }
    }
}
```

Also add `worktreeOpenState` property to `CommandBarItem`. Add it after the existing `command` property:

```swift
let worktreeOpenState: WorktreeOpenState?
```

Add `worktreeOpenState: WorktreeOpenState? = nil` as a parameter to the `init` with a default of `nil`.

- [ ] **Step 2: Rewrite `CommandBarFooter` to accept `[FooterHint]`**

Replace `CommandBarFooter.swift` entirely:

```swift
import SwiftUI

// MARK: - CommandBarFooter

/// Dynamic keyboard hints footer, adapts to selected item state.
struct CommandBarFooter: View {
    let hints: [FooterHint]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(hints) { hint in
                footerHint(hint.key, hint.label)
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: AppStyle.textXs, weight: .medium, design: .monospaced))
            Text(label)
                .font(.system(size: AppStyle.textXs))
        }
        .foregroundStyle(.primary.opacity(0.3))
    }
}
```

- [ ] **Step 3: Update `CommandBarView` to compute and pass hints**

In `CommandBarView.swift`, replace the footer section:

```swift
CommandBarFooter(
    hints: footerHints
)
```

Add computed property:

```swift
private var footerHints: [FooterHint] {
    FooterHintBuilder.hints(
        for: selectedItem,
        isNested: state.isNested,
        hasTabsOpen: !store.tabs.isEmpty
    )
}
```

- [ ] **Step 4: Write focused tests for `FooterHintBuilder`**

Create `Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FooterHintBuilderTests {

    // MARK: - Nested Level

    @Test
    func test_nested_showsSelectBackClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: true, hasTabsOpen: true)
        let keys = hints.map(\.key)
        #expect(keys.contains("↵"))
        #expect(keys.contains("⌫"))
        #expect(keys.contains("esc"))
    }

    // MARK: - Non-Worktree Items

    @Test
    func test_nonWorktreeItem_showsStandardHints() {
        let item = makeCommandBarItem(id: "tab-1", title: "Tab")
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let keys = hints.map(\.key)
        #expect(keys.contains("↵"))
        #expect(keys.contains("esc"))
        #expect(!keys.contains("⌘↵"))
    }

    @Test
    func test_nonWorktreeItemWithChildren_showsDrillIn() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd", hasChildren: true)
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let keys = hints.map(\.key)
        #expect(keys.contains("→"))
    }

    // MARK: - Worktree: Not Open

    @Test
    func test_worktreeNotOpen_noTabs_showsBareEnterNewTab() {
        let item = makeCommandBarItem(
            id: "wt-1", title: "main",
            worktreeOpenState: .notOpen
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: false)
        let labels = hints.map(\.label)
        #expect(labels.contains("New tab"))
        #expect(!labels.contains("Open in tab"))
        #expect(!labels.contains("Choose"))
    }

    @Test
    func test_worktreeNotOpen_tabsExist_showsChooseAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1", title: "main",
            worktreeOpenState: .notOpen
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let keys = hints.map(\.key)
        #expect(keys.contains("↵"))
        #expect(keys.contains("⌘↵"))
        #expect(keys.contains("⌥↵"))
    }

    // MARK: - Worktree: Single Pane

    @Test
    func test_worktreeSinglePane_showsGoToAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1", title: "main",
            worktreeOpenState: .singlePane
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)
        #expect(labels.contains("Go to"))
        #expect(labels.contains("New tab"))
        #expect(labels.contains("Open in tab"))
    }

    // MARK: - Worktree: Multiple Panes

    @Test
    func test_worktreeMultiplePanes_showsChoosePaneAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1", title: "main",
            worktreeOpenState: .multiplePanes
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)
        #expect(labels.contains("Choose pane"))
        #expect(labels.contains("New tab"))
        #expect(labels.contains("Open in tab"))
    }

    @Test
    func test_worktreeMultiplePanes_noTabs_hidesOpenInTab() {
        let item = makeCommandBarItem(
            id: "wt-1", title: "main",
            worktreeOpenState: .multiplePanes
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: false)
        let labels = hints.map(\.label)
        #expect(!labels.contains("Open in tab"))
    }
}
```

Update the `makeCommandBarItem` factory in `Tests/AgentStudioTests/Helpers/CommandBarFactories.swift` to accept `worktreeOpenState`:

```swift
func makeCommandBarItem(
    id: String = "test-item",
    title: String = "Test Item",
    subtitle: String? = nil,
    icon: String? = "terminal",
    iconColor: Color? = nil,
    shortcutKeys: [ShortcutKey]? = nil,
    group: String = "Commands",
    groupPriority: Int = 3,
    keywords: [String] = [],
    hasChildren: Bool = false,
    action: CommandBarAction = .dispatch(.closeTab),
    worktreeOpenState: WorktreeOpenState? = nil
) -> CommandBarItem {
    CommandBarItem(
        id: id,
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        shortcutKeys: shortcutKeys,
        group: group,
        groupPriority: groupPriority,
        keywords: keywords,
        hasChildren: hasChildren,
        action: action,
        worktreeOpenState: worktreeOpenState
    )
}
```

- [ ] **Step 5: Run footer hint tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FooterHintBuilderTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all 8 tests green.

- [ ] **Step 6: Run full command bar tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBar" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all existing tests green.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift Tests/AgentStudioTests/Helpers/CommandBarFactories.swift
git commit -m "feat(command-bar): dynamic footer hints based on selected item state"
```

---

## Task 4: Unified Worktree Rows in Repo Scope

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` — rewrite `repoScopeItems`; add shared worktree item builders
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift` — add `CommandBarAction.worktreeAction` variant
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift` — handle the new action variant with modifier resolution
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift` — new tests for unified rows

- [ ] **Step 1: Add `worktreeAction` variant to `CommandBarAction`**

In `CommandBarItem.swift`, add a new case to `CommandBarAction`:

```swift
enum CommandBarAction {
    case dispatch(AppCommand)
    case dispatchTargeted(AppCommand, target: UUID, targetType: SearchItemType)
    case navigate(CommandBarLevel)
    case custom(@Sendable () -> Void)
    /// Worktree-aware action: resolves differently based on modifier key and open state.
    case worktreeAction(worktreeId: UUID, presence: WorktreePresence)
}
```

- [ ] **Step 2: Write failing tests for new repo scope items**

Add to `CommandBarDataSourceTests.swift`:

```swift
// MARK: - Repos Scope — Unified Worktree Rows

@Test
func test_reposScope_worktreeWithNoPanes_hasNotOpenState() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/repo-no-panes"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/repo-no-panes"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

    let items = CommandBarDataSource.items(
        scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    let item = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }
    #expect(item != nil)
    #expect(item?.worktreeOpenState == .notOpen)
    #expect(item?.hasChildren == false)
}

@Test
func test_reposScope_worktreeWithOnePane_hasSinglePaneState() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/repo-one-pane"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "feature",
        path: URL(filePath: "/tmp/repo-one-pane/feature")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Terminal"
    )
    store.appendTab(Tab(paneId: pane.id))

    let items = CommandBarDataSource.items(
        scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    let item = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }
    #expect(item?.worktreeOpenState == .singlePane)
    #expect(item?.subtitle?.contains("Tab 1") == true)
    #expect(item?.hasChildren == false)
}

@Test
func test_reposScope_worktreeWithMultiplePanes_hasMultiplePanesStateAndDrillIn() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/repo-multi-pane"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/repo-multi-pane"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

    let paneA = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "A"
    )
    store.appendTab(Tab(paneId: paneA.id))
    let paneB = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "B"
    )
    store.appendTab(Tab(paneId: paneB.id))

    let items = CommandBarDataSource.items(
        scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    let item = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }
    #expect(item?.worktreeOpenState == .multiplePanes)
    #expect(item?.subtitle?.contains("2 panes") == true)
    #expect(item?.hasChildren == true)
}

@Test
func test_reposScope_worktreeWithOnePaneSubtitleShowsTabLocation() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/repo-subtitle"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/repo-subtitle"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "T"
    )
    store.appendTab(Tab(paneId: pane.id))

    let items = CommandBarDataSource.items(
        scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
    let item = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }

    #expect(item?.subtitle == "● Tab 1 · 1 pane")
}

@Test
func test_reposScope_worktreeNotOpen_subtitleIsNilOrMainWorktree() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/repo-not-open"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/repo-not-open"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

    let items = CommandBarDataSource.items(
        scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
    let item = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }

    #expect(item?.subtitle == "main worktree")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `worktreeOpenState` not set by current data source.

- [ ] **Step 4: Rewrite `repoScopeItems` and add shared worktree builders in `CommandBarDataSource.swift`**

Replace the `repoScopeItems` method and add the shared builder methods. These builders will be reused by the everything scope in Task 6.

```swift
// MARK: - Repos Scope (grouped by repo)

private static func repoScopeItems(store: WorkspaceStore) -> [CommandBarItem] {
    var items: [CommandBarItem] = []
    let singleWorktreeRepos = store.repos
        .filter { $0.worktrees.count <= 1 }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    let multiWorktreeRepos = store.repos
        .filter { $0.worktrees.count > 1 }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    for repo in singleWorktreeRepos {
        for worktree in repo.worktrees {
            let presence = WorktreePresence.build(worktree: worktree, repo: repo, store: store)
            items.append(unifiedWorktreeItem(
                worktree: worktree,
                repo: repo,
                presence: presence,
                group: "Repos",
                groupPriority: 0
            ))
        }
    }

    for (repoIndex, repo) in multiWorktreeRepos.enumerated() {
        let groupName = "\(repo.name) (worktrees)"
        for worktree in repo.worktrees {
            let presence = WorktreePresence.build(worktree: worktree, repo: repo, store: store)
            items.append(unifiedWorktreeItem(
                worktree: worktree,
                repo: repo,
                presence: presence,
                group: groupName,
                groupPriority: repoIndex + 1
            ))
        }
    }

    return items
}

// MARK: - Shared Unified Worktree Builders

/// Build a unified worktree row with presence awareness.
/// Used by both repos scope and everything scope.
static func unifiedWorktreeItem(
    worktree: Worktree,
    repo: Repo,
    presence: WorktreePresence,
    group: String,
    groupPriority: Int
) -> CommandBarItem {
    let subtitle = worktreePresenceSubtitle(presence: presence, worktree: worktree)
    let hasChildren = presence.openState == .multiplePanes

    let action: CommandBarAction
    if hasChildren {
        let level = buildWorktreePaneDrillInLevel(presence: presence, worktree: worktree, repo: repo)
        action = .navigate(level)
    } else {
        action = .worktreeAction(worktreeId: worktree.id, presence: presence)
    }

    return CommandBarItem(
        id: "repo-wt-\(worktree.id.uuidString)",
        title: worktree.name,
        subtitle: subtitle,
        icon: worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch",
        group: group,
        groupPriority: groupPriority,
        keywords: ["repo", "worktree", "terminal", repo.name, worktree.name],
        hasChildren: hasChildren,
        action: action,
        command: .openWorktree,
        worktreeOpenState: presence.openState
    )
}

static func worktreePresenceSubtitle(
    presence: WorktreePresence,
    worktree: Worktree
) -> String? {
    switch presence.openState {
    case .notOpen:
        return worktree.isMainWorktree ? "main worktree" : nil
    case .singlePane:
        let loc = presence.openPanes[0]
        return "● Tab \(loc.tabIndex + 1) · 1 pane"
    case .multiplePanes:
        let paneCount = presence.openPanes.count
        let tabCount = presence.distinctTabCount
        if tabCount == 1 {
            return "● \(paneCount) panes · Tab \(presence.openPanes[0].tabIndex + 1)"
        }
        return "● \(paneCount) panes · \(tabCount) tabs"
    }
}

static func buildWorktreePaneDrillInLevel(
    presence: WorktreePresence,
    worktree: Worktree,
    repo: Repo
) -> CommandBarLevel {
    var items: [CommandBarItem] = []

    for loc in presence.openPanes {
        let targetType: SearchItemType = .pane
        items.append(
            CommandBarItem(
                id: "wt-pane-\(loc.paneId.uuidString)",
                title: "Terminal — \(worktree.name)",
                subtitle: loc.isActiveInTab ? "Tab \(loc.tabIndex + 1) · Active" : "Tab \(loc.tabIndex + 1)",
                icon: "terminal",
                group: "Navigate to",
                groupPriority: 0,
                action: .dispatchTargeted(.focusPane, target: loc.paneId, targetType: targetType)
            ))
    }

    let worktreeId = worktree.id
    items.append(
        CommandBarItem(
            id: "wt-new-tab-\(worktree.id.uuidString)",
            title: "New pane in new tab",
            icon: "plus.rectangle",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
            group: "Open new",
            groupPriority: 1,
            action: .dispatchTargeted(.openNewTerminalInTab, target: worktreeId, targetType: .worktree),
            command: .openNewTerminalInTab
        ))
    items.append(
        CommandBarItem(
            id: "wt-add-pane-\(worktree.id.uuidString)",
            title: "New pane in current tab",
            icon: "rectangle.split.2x1",
            shortcutKeys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
            group: "Open new",
            groupPriority: 1,
            action: .dispatchTargeted(.openWorktreeInPane, target: worktreeId, targetType: .worktree),
            command: .openWorktreeInPane
        ))

    return CommandBarLevel(
        id: "level-wt-\(worktree.id.uuidString)",
        title: worktree.name,
        parentLabel: repo.name,
        items: items
    )
}

static func buildWorktreeOpenChoiceLevel(
    worktree: Worktree,
    repo: Repo,
    hasTabsOpen: Bool
) -> CommandBarLevel {
    let worktreeId = worktree.id
    var items: [CommandBarItem] = []

    items.append(
        CommandBarItem(
            id: "wt-choice-new-tab-\(worktree.id.uuidString)",
            title: "New pane in new tab",
            icon: "plus.rectangle",
            shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
            group: "Open",
            groupPriority: 0,
            action: .dispatchTargeted(.openNewTerminalInTab, target: worktreeId, targetType: .worktree),
            command: .openNewTerminalInTab
        ))

    if hasTabsOpen {
        items.append(
            CommandBarItem(
                id: "wt-choice-add-pane-\(worktree.id.uuidString)",
                title: "New pane in current tab",
                icon: "rectangle.split.2x1",
                shortcutKeys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                group: "Open",
                groupPriority: 0,
                action: .dispatchTargeted(.openWorktreeInPane, target: worktreeId, targetType: .worktree),
                command: .openWorktreeInPane
            ))
    }

    return CommandBarLevel(
        id: "level-wt-choice-\(worktree.id.uuidString)",
        title: worktree.name,
        parentLabel: repo.name,
        items: items
    )
}
```

**Note:** Do NOT delete the old `worktreeItems` method yet — `everythingItems` still calls it. Task 6 will replace it.

- [ ] **Step 5: Handle `worktreeAction` in `CommandBarView.executeItem`**

In `CommandBarView.swift`, add the `.worktreeAction` case to `executeItem` and add the `resolveWorktreeAction` method:

```swift
case .worktreeAction(let worktreeId, let presence):
    resolveWorktreeAction(
        worktreeId: worktreeId,
        presence: presence,
        modifier: modifier,
        itemId: item.id
    )
```

```swift
private func resolveWorktreeAction(
    worktreeId: UUID,
    presence: WorktreePresence,
    modifier: EnterModifier,
    itemId: String
) {
    switch modifier {
    case .command:
        state.recordRecent(itemId: itemId)
        onDismiss()
        dispatcher.dispatch(.openNewTerminalInTab, target: worktreeId, targetType: .worktree)

    case .option:
        state.recordRecent(itemId: itemId)
        onDismiss()
        dispatcher.dispatch(.openWorktreeInPane, target: worktreeId, targetType: .worktree)

    case .none:
        switch presence.openState {
        case .notOpen where store.tabs.isEmpty:
            state.recordRecent(itemId: itemId)
            onDismiss()
            dispatcher.dispatch(.openNewTerminalInTab, target: worktreeId, targetType: .worktree)

        case .notOpen:
            guard let worktree = store.worktree(worktreeId),
                let repo = store.repo(containing: worktreeId)
            else { return }
            let level = CommandBarDataSource.buildWorktreeOpenChoiceLevel(
                worktree: worktree,
                repo: repo,
                hasTabsOpen: !store.tabs.isEmpty
            )
            state.pushLevel(level)

        case .singlePane:
            let loc = presence.openPanes[0]
            state.recordRecent(itemId: itemId)
            onDismiss()
            dispatcher.dispatch(.focusPane, target: loc.paneId, targetType: .pane)

        case .multiplePanes:
            break
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — both old and new tests green.

- [ ] **Step 7: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift
git commit -m "feat(command-bar): unified worktree rows with presence, drill-in, and modifier actions in # scope"
```

---

## Task 5: Presence Indicator in Result Row

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultRow.swift`

- [ ] **Step 1: Add presence dot to the result row**

In `CommandBarResultRow.swift`, inside the `HStack`, after the icon section and before `highlightedTitle`, add:

```swift
// Presence indicator (● for open worktrees)
if let openState = item.worktreeOpenState, openState != .notOpen {
    Circle()
        .fill(Color.green.opacity(0.7))
        .frame(width: 6, height: 6)
}
```

- [ ] **Step 2: Build to verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultRow.swift
git commit -m "feat(command-bar): green presence indicator dot for open worktrees"
```

---

## Task 6: Everything Scope — Unified Worktree Rows & Enhanced Tab Search

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` — replace `worktreeItems` with unified builder; enhance `tabItems` keywords
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift` — new tests

This task replaces the old flat `worktreeItems` in the everything scope with the same unified worktree rows from Task 4, and enhances tab items with arrangement-name keywords.

- [ ] **Step 1: Write failing tests for everything scope changes**

Add to `CommandBarDataSourceTests.swift`:

```swift
// MARK: - Everything Scope — Unified Worktree Rows

@Test
func test_everythingScope_worktreeItemsHavePresenceState() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/everything-wt"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/everything-wt"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Terminal"
    )
    store.appendTab(Tab(paneId: pane.id))

    let items = CommandBarDataSource.items(
        scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    let wtItem = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }
    #expect(wtItem != nil)
    #expect(wtItem?.worktreeOpenState == .singlePane)
    #expect(wtItem?.group == "Worktrees")
}

@Test
func test_everythingScope_paneItemsStillPresent() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/everything-panes"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/everything-panes"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Terminal"
    )
    store.appendTab(Tab(paneId: pane.id))

    let items = CommandBarDataSource.items(
        scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    // Pane items still present — no suppression
    let paneItems = items.filter { $0.id.hasPrefix("pane-") }
    #expect(paneItems.count == 1)
    #expect(paneItems[0].id == "pane-\(pane.id.uuidString)")
}

@Test
func test_everythingScope_tabItemsStillPresent() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/everything-tabs"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/everything-tabs"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Terminal"
    )
    store.appendTab(Tab(paneId: pane.id))

    let items = CommandBarDataSource.items(
        scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    // Tab items still present — no suppression
    let tabItems = items.filter { $0.id.hasPrefix("tab-") }
    #expect(tabItems.count == 1)
}

@Test
func test_everythingScope_worktreeItemUsesRepoWorktreeId() {
    // Verify the worktree items in everything scope use "repo-wt-" prefix (unified)
    // not the old "wt-" prefix
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/everything-wt-id"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "feature",
        path: URL(filePath: "/tmp/everything-wt-id/feature")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

    let items = CommandBarDataSource.items(
        scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

    let oldStyleItems = items.filter { $0.id.hasPrefix("wt-") && !$0.id.hasPrefix("wt-pane-") && !$0.id.hasPrefix("wt-new-") && !$0.id.hasPrefix("wt-add-") && !$0.id.hasPrefix("wt-choice-") }
    let newStyleItems = items.filter { $0.id == "repo-wt-\(worktree.id.uuidString)" }
    #expect(oldStyleItems.isEmpty, "Old-style wt- items should no longer exist in everything scope")
    #expect(newStyleItems.count == 1)
}

// MARK: - Tab Keywords with Arrangement Names

@Test
func test_everythingScope_tabKeywordsIncludeArrangementNames() {
    let store = makeStore()
    let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
    var tab = Tab(paneId: pane.id)
    let namedArrangement = PaneArrangement(
        name: "Review",
        isDefault: false,
        layout: tab.layout,
        visiblePaneIds: Set(tab.activePaneIds)
    )
    tab.arrangements.append(namedArrangement)
    store.appendTab(tab)
    store.setActiveTab(tab.id)

    let items = CommandBarDataSource.items(
        scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
    let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

    #expect(tabItem?.keywords.contains("Review") == true)
}

@Test
func test_everythingScope_tabKeywordsIncludeTabName() {
    let store = makeStore()
    let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
    let tab = Tab(paneId: pane.id, name: "My Workspace")
    store.appendTab(tab)

    let items = CommandBarDataSource.items(
        scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
    let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

    #expect(tabItem?.keywords.contains("My Workspace") == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — everything scope still uses old `worktreeItems` without presence; tab keywords don't include arrangements.

- [ ] **Step 3: Replace `worktreeItems` with unified worktree builder in `everythingItems`**

In `CommandBarDataSource.swift`, update `everythingItems` to use the shared `unifiedWorktreeItem` builder instead of the old `worktreeItems`:

```swift
private static func everythingItems(
    store: WorkspaceStore,
    repoCache: RepoCacheAtom,
    dispatcher: CommandDispatcher,
    focus: WorkspaceFocus
) -> [CommandBarItem] {
    var items: [CommandBarItem] = []
    items.append(contentsOf: tabItems(store: store, repoCache: repoCache))
    items.append(contentsOf: paneItems(store: store, repoCache: repoCache))
    items.append(
        contentsOf: allCommandItems(
            dispatcher: dispatcher,
            store: store,
            repoCache: repoCache,
            focus: focus,
            groupName: Group.commands,
            priority: Priority.commands))
    items.append(contentsOf: everythingWorktreeItems(store: store))
    return items
}
```

Add the new `everythingWorktreeItems` method:

```swift
/// Unified worktree rows for the everything scope.
/// Uses the same builder as repos scope but with the "Worktrees" group.
private static func everythingWorktreeItems(store: WorkspaceStore) -> [CommandBarItem] {
    store.repos.flatMap { repo in
        repo.worktrees.map { worktree in
            let presence = WorktreePresence.build(worktree: worktree, repo: repo, store: store)
            return unifiedWorktreeItem(
                worktree: worktree,
                repo: repo,
                presence: presence,
                group: Group.worktrees,
                groupPriority: Priority.worktrees
            )
        }
    }
}
```

Delete the old `worktreeItems` method entirely.

- [ ] **Step 4: Enhance `tabItems` with arrangement-name and tab-name keywords**

In the `tabItems` method, update the keywords array:

```swift
private static func tabItems(
    store: WorkspaceStore,
    repoCache: RepoCacheAtom
) -> [CommandBarItem] {
    store.tabs.enumerated().map { index, tab in
        let title = tabDisplayTitle(tab: tab, store: store, repoCache: repoCache)
        let isActive = tab.id == store.activeTabId
        let paneCount = tab.activePaneIds.count
        let subtitle: String = {
            var parts: [String] = []
            if isActive {
                parts.append("Active")
            }
            parts.append("Tab \(index + 1)")
            if paneCount > 1 {
                parts.append("\(paneCount) panes")
            }
            return parts.joined(separator: " · ")
        }()

        // Build keywords including tab name and arrangement names
        var keywords: [String] = ["tab", "switch"]
        if tab.name != "Tab" {
            keywords.append(tab.name)
        }
        let arrangementNames = tab.arrangements
            .filter { !$0.isDefault }
            .map(\.name)
        keywords.append(contentsOf: arrangementNames)

        let tabId = tab.id
        return CommandBarItem(
            id: "tab-\(tab.id.uuidString)",
            title: title,
            subtitle: subtitle,
            icon: "rectangle.stack",
            group: Group.tabs,
            groupPriority: Priority.tabs,
            keywords: keywords,
            action: .dispatchTargeted(.selectTab, target: tabId, targetType: .tab),
            command: .selectTab
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all tests green.

- [ ] **Step 6: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift
git commit -m "feat(command-bar): unified worktree rows in everything scope; tab keywords include arrangement names"
```

---

## Task 7: Lint and Final Verification

**Files:** All modified files.

- [ ] **Step 1: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — zero errors.

- [ ] **Step 2: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all tests green, show pass/fail counts.

- [ ] **Step 3: Fix any lint or test failures**

If any failures, fix them and re-run.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(command-bar): lint and test fixes for unified worktree actions"
```
