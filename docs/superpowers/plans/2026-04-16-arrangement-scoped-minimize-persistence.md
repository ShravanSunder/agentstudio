# Arrangement-Scoped Minimize Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make minimized top-level panes belong to each arrangement, so switching away and back restores the same minimized panes, restarting the app restores that arrangement-local minimized state from disk, extra arrangements default to `#1`, `#2`, `#3`, and the arrangement panel supports wider inline rename without an alert.

**Architecture:** `PaneArrangement` becomes the owner of top-level minimized pane state. `Tab` continues to own arrangement selection (`activeArrangementId`) and focus, but it no longer owns one shared top-level `minimizedPaneIds` set. A new arrangement-specific atom is not introduced: arrangement state already belongs to tab layout, so the clean fix is to keep that boundary in `WorkspaceTabLayoutAtom` and move only the data ownership. All top-level minimize/expand, layout rendering, arrangement switching, launch restore, and persistence paths must read the active arrangement’s minimized set instead of tab-global transient state. `PaneArrangement` gets backward-compatible decoding so older workspace files restore with `minimizedPaneIds = []` rather than failing to decode. The arrangement panel is widened to a single final target (`minWidth: 320, idealWidth: 380, maxWidth: 460`) and chips support inline rename, so rename happens in-place without an alert or extra popover.

**Tech Stack:** Swift 6.2, SwiftUI, `@MainActor` atoms, `WorkspaceStore` persistence, Swift Testing

---

## State Ownership

Canonical state for this feature must stay in atoms.

- `WorkspaceTabLayoutAtom` remains the single owner of top-level arrangement state:
  - `Tab.arrangements`
  - `Tab.activeArrangementId`
  - each `PaneArrangement.minimizedPaneIds`
- `WorkspaceStore` is the existing persistence wrapper/facade around those atoms; it is not the canonical owner of arrangement state.
- Views and adapters read atom state and dispatch actions back into the atom-backed command path.
- Default custom-arrangement naming policy such as `#1`, `#2`, `#3` is derived/helper logic, not atom-owned business logic.
- `ArrangementPanel` may keep short-lived UI-only edit state such as:
  - which chip is currently being edited
  - the in-progress rename draft text

That local view state is only for the active text field interaction. It must not become a second source of truth for arrangement names, minimized panes, or the active arrangement.

## Context

Today the model splits arrangement state and minimize state:

- `Tab.arrangements` and `Tab.activeArrangementId` are persisted.
- `Tab.minimizedPaneIds` is separate, transient, and cleared on arrangement switch.

That creates two bad behaviors:

1. In memory, “minimize in Default, switch away, switch back” loses minimized state because `WorkspaceTabLayoutAtom.switchArrangement(...)` clears `tabs[tabIndex].minimizedPaneIds`.
2. On restart, minimized state is lost because `Tab.CodingKeys` excludes `minimizedPaneIds`.

The desired model is stricter and simpler:

- a saved arrangement is the state you return to
- minimized top-level panes are part of that arrangement state
- switching arrangements loads that arrangement’s minimized set
- persistence writes and restores that arrangement-local minimized set
- extra arrangements default to predictable names (`#1`, `#2`, `#3`, ...)
- arrangement rename happens inline in the panel itself

Drawer minimize behavior stays separate in `Drawer.minimizedPaneIds`. This plan only changes top-level tab arrangements.

## File Structure

### Modified Files

| File | Responsibility |
|---|---|
| `Sources/AgentStudio/Core/Models/PaneArrangement.swift` | Add persisted `minimizedPaneIds` for top-level arrangement state |
| `Sources/AgentStudio/Core/Models/Tab.swift` | Remove top-level `minimizedPaneIds` ownership and transient coding comments |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift` | Rewire minimize/expand/switch/prune/remove paths to mutate the active arrangement’s minimized set |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift` | Drive arrangement panel minimize indicators from the active arrangement and provide derived default naming |
| `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift` | Pass active arrangement minimized set into strip rendering |
| `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift` | Pass active arrangement minimized set into strip rendering |
| `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift` | Replace alert-based rename with inline editing and widen the panel |
| `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift` | Compute arrangement-switch view transitions using previous and next arrangement-local minimized sets |
| `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` | Restore/render visible panes using arrangement-local minimized state |
| `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift` | Filter top-level restore ordering with active arrangement minimized set |
| `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift` | Compute minimized badge count from the active arrangement |
| `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift` | Remove duplicated arrangement auto-name helper and use shared derived/helper naming rule |
| `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` | Remove duplicated arrangement auto-name helper and use shared derived/helper naming rule |
| `docs/architecture/component_architecture.md` | Update persisted model table for `PaneArrangement` and `Tab` |
| `docs/architecture/window_system_design.md` | Remove contradictory “transient” claim for top-level minimized panes |

### Test Files

| File | Responsibility |
|---|---|
| `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift` | Add red-green tests for arrangement-local minimize behavior and restart restore |
| `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift` | Verify persisted state keeps arrangement-local minimized IDs after pruning |
| `Tests/AgentStudioTests/Core/Models/TabArrangementTests.swift` | Move codable expectations from transient minimize to persisted arrangement minimize |
| `Tests/AgentStudioTests/App/ActionExecutorTests.swift` | Verify switching arrangements restores the arrangement’s own minimized state |
| `Tests/AgentStudioTests/Core/State/ArrangementDerivedTests.swift` | Verify the panel derives minimize indicators from the active arrangement |
| `Tests/AgentStudioTests/Core/Views/ArrangementPanelInlineRenameTests.swift` | Verify inline rename editing state and wider layout contract |

---

## Task 1: Lock The Desired Behavior With Failing Tests

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Models/TabArrangementTests.swift`
- Modify: `Tests/AgentStudioTests/App/ActionExecutorTests.swift`

- [ ] **Step 1: Write the failing arrangement-switch behavior test**

Add this test to `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`:

```swift
    @Test
    func test_switchArrangement_restoresArrangementLocalMinimizedPanes() {
        let paneIds = [
            store.createPane(source: .floating(launchDirectory: nil, title: "One")).id,
            store.createPane(source: .floating(launchDirectory: nil, title: "Two")).id,
            store.createPane(source: .floating(launchDirectory: nil, title: "Three")).id,
        ]
        let tab = makeTab(paneIds: paneIds, activePaneId: paneIds[0])
        store.appendTab(tab)

        let focusId = store.createArrangement(
            name: "Focus",
            paneIds: Set([paneIds[0], paneIds[2]]),
            inTab: tab.id
        )!

        store.minimizePane(paneIds[1], inTab: tab.id)
        store.switchArrangement(to: focusId, inTab: tab.id)
        store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)

        let restoredTab = store.tab(tab.id)!
        #expect(restoredTab.activeArrangementId == tab.defaultArrangement.id)
        #expect(restoredTab.activeArrangement.minimizedPaneIds == Set([paneIds[1]]))
    }
```

- [ ] **Step 2: Run the test to verify red**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "test_switchArrangement_restoresArrangementLocalMinimizedPanes"
```

Expected: fail because `PaneArrangement` has no `minimizedPaneIds` and/or switching arrangements still clears tab-level minimize state.

- [ ] **Step 3: Write the failing persistence test**

Add this test to `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`:

```swift
    @Test
    func test_arrangementLocalMinimizedPanes_persistAndRestore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "arr-minimized-persist-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store1 = WorkspaceStore(persistor: persistor)

        let paneOne = store1.createPane(source: .floating(launchDirectory: nil, title: "One"))
        let paneTwo = store1.createPane(source: .floating(launchDirectory: nil, title: "Two"))
        let tab = makeTab(paneIds: [paneOne.id, paneTwo.id], activePaneId: paneOne.id)
        store1.appendTab(tab)
        store1.minimizePane(paneTwo.id, inTab: tab.id)
        store1.flush()

        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        let restoredTab = store2.tabs.first!
        #expect(restoredTab.activeArrangement.minimizedPaneIds == Set([paneTwo.id]))

        try? FileManager.default.removeItem(at: tempDir)
    }
```

- [ ] **Step 4: Run the persistence test to verify red**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "test_arrangementLocalMinimizedPanes_persistAndRestore"
```

Expected: fail because minimized state is not encoded/decoded with arrangements.

- [ ] **Step 5: Write the failing transformer pruning test**

Add this test to `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`:

```swift
    @Test
    func makePersistableState_preservesArrangementLocalMinimizedIdsForPersistedPanes() {
        let metadataAtom = WorkspaceMetadataAtom()
        let topologyAtom = WorkspaceRepositoryTopologyAtom()
        let paneAtom = WorkspacePaneAtom()
        let tabLayoutAtom = WorkspaceTabLayoutAtom()

        metadataAtom.hydrate(
            workspaceId: UUID(),
            workspaceName: "Workspace",
            createdAt: Date(timeIntervalSince1970: 1000),
            sidebarWidth: 250,
            windowFrame: nil
        )

        let persistentPane = makePane(title: "Persistent")
        let temporaryPane = makePane(title: "Temporary", lifetime: .temporary)
        paneAtom.addPane(persistentPane)
        paneAtom.addPane(temporaryPane)

        var tab = makeTab(
            paneIds: [persistentPane.id, temporaryPane.id],
            activePaneId: persistentPane.id
        )
        tab.arrangements[tab.activeArrangementIndex].minimizedPaneIds = [persistentPane.id, temporaryPane.id]
        tabLayoutAtom.appendTab(tab)
        tabLayoutAtom.setActiveTab(tab.id)

        let state = WorkspacePersistenceTransformer.makePersistableState(
            metadataAtom: metadataAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 2000)
        )

        #expect(state.tabs[0].activeArrangement.minimizedPaneIds == Set([persistentPane.id]))
    }
```

- [ ] **Step 6: Run the transformer test to verify red**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "makePersistableState_preservesArrangementLocalMinimizedIdsForPersistedPanes"
```

Expected: fail because arrangement minimize state does not exist yet.

---

## Task 2: Move Top-Level Minimize State Onto PaneArrangement

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/PaneArrangement.swift`
- Modify: `Sources/AgentStudio/Core/Models/Tab.swift`

- [ ] **Step 1: Add persisted arrangement-local minimized state**

Update `Sources/AgentStudio/Core/Models/PaneArrangement.swift`:

```swift
struct PaneArrangement: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var isDefault: Bool
    var layout: Layout
    var visiblePaneIds: Set<UUID>
    var minimizedPaneIds: Set<UUID>

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isDefault: Bool = true,
        layout: Layout,
        visiblePaneIds: Set<UUID>? = nil,
        minimizedPaneIds: Set<UUID> = []
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.layout = layout
        self.visiblePaneIds = visiblePaneIds ?? Set(layout.paneIds)
        self.minimizedPaneIds = minimizedPaneIds
    }
}
```

- [ ] **Step 2: Add backward-compatible decoding for older workspaces**

Do not rely on synthesized decoding for `PaneArrangement`. Add a custom `init(from:)` so existing persisted files that lack `minimizedPaneIds` still decode successfully:

```swift
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault
        case layout
        case visiblePaneIds
        case minimizedPaneIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        layout = try container.decode(Layout.self, forKey: .layout)
        visiblePaneIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .visiblePaneIds)
            ?? Set(layout.paneIds)
        minimizedPaneIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .minimizedPaneIds) ?? []
    }
```

- [ ] **Step 3: Remove tab-global top-level minimized ownership**

Update `Sources/AgentStudio/Core/Models/Tab.swift` so `Tab` no longer stores `minimizedPaneIds`:

```swift
struct Tab: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var allPaneIds: [UUID]
    var arrangements: [PaneArrangement]
    var activeArrangementId: UUID
    var activePaneId: UUID?
    var zoomedPaneId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case allPaneIds = "panes"
        case arrangements
        case activeArrangementId
        case activePaneId
    }
}
```

- [ ] **Step 4: Add arrangement-scoped convenience accessors**

Add these derived accessors to `Tab`:

```swift
    var activeMinimizedPaneIds: Set<UUID> {
        activeArrangement.minimizedPaneIds
    }
```

If mutation helpers need writable access, add them in `WorkspaceTabLayoutAtom` rather than on `Tab` to keep mutation ownership with the atom.

- [ ] **Step 5: Run the model-focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabArrangementTests"
```

Expected: pass after updating codable expectations for arrangement-scoped minimize state.

---

## Task 3: Rewire WorkspaceTabLayoutAtom To Mutate The Active Arrangement

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`

- [ ] **Step 1: Make minimize/expand hit the active arrangement**

Replace tab-global mutations with active-arrangement mutations in `WorkspaceTabLayoutAtom.minimizePane(...)` and `expandPane(...)`:

```swift
        tabs[tabIndex].arrangements[arrIndex].minimizedPaneIds.insert(paneId)
```

and

```swift
        guard tabs[tabIndex].arrangements[arrIndex].minimizedPaneIds.contains(paneId) else { return }
        tabs[tabIndex].arrangements[arrIndex].minimizedPaneIds.remove(paneId)
```

Use `tabs[tabIndex].activeArrangementIndex` for the arrangement being edited.

- [ ] **Step 2: Stop clearing minimize state on arrangement switch**

Update `switchArrangement(to:inTab:)` in `WorkspaceTabLayoutAtom` to remove this behavior:

```swift
        tabs[tabIndex].minimizedPaneIds = []
```

After switching, choose an active pane that exists in the target layout and is not minimized in the target arrangement:

```swift
        let visibleUnminimizedPaneIds = tabs[tabIndex].activeArrangement.layout.paneIds.filter {
            !tabs[tabIndex].activeArrangement.minimizedPaneIds.contains($0)
        }
```

If the old `activePaneId` is missing or minimized in the target arrangement, fall back to the first unminimized pane.

- [ ] **Step 3: Prune arrangement-local minimized IDs in every mutation path**

Every place that currently removes or intersects `tabs[tabIndex].minimizedPaneIds` must instead operate per arrangement:

- `removePaneFromLayout`
- `removePaneReferences`
- `pruneInvalidPanes`
- `validateTabInvariants`

Pattern:

```swift
for arrangementIndex in tabs[tabIndex].arrangements.indices {
    tabs[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.formIntersection(validPaneIds)
    tabs[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.formIntersection(
        Set(tabs[tabIndex].arrangements[arrangementIndex].layout.paneIds)
    )
}
```

- [ ] **Step 4: Preserve minimized state when creating arrangements**

When `createArrangement(name:paneIds:inTab:)` builds a new arrangement, initialize `minimizedPaneIds` from the panes currently minimized in the active arrangement that are also part of the new arrangement:

```swift
let inheritedMinimizedPaneIds = tabs[tabIndex].activeArrangement.minimizedPaneIds.intersection(paneIds)
```

Pass that into the new `PaneArrangement`.

- [ ] **Step 5: Run the arrangement store tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreArrangementTests"
```

Expected: pass, including the new switch-away-and-back test.

---

## Task 4: Move Default Arrangement Naming To Derived/Helper Logic

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/Core/State/ArrangementDerivedTests.swift`

- [ ] **Step 1: Add a derived/helper naming API**

Add a read-only helper in `ArrangementDerived` for the default naming policy:

```swift
    func nextCustomArrangementName(for tabId: UUID) -> String? {
        let tabLayout = atom(\.workspaceTabLayout)
        guard let tab = tabLayout.tab(tabId) else { return nil }
        let existingNames = Set(tab.arrangements.map(\.name))
        var index = 1
        while existingNames.contains("#\(index)") {
            index += 1
        }
        return "#\(index)"
    }
```

This stays a projection concern. It reads atom state but does not become atom-owned business logic.

- [ ] **Step 2: Replace duplicated UI naming helpers**

Remove the local `nextArrangementName(existing:)` helpers from:

- `FlatTabStripContainer`
- `PaneTabViewController`

Replace them with reads through `ArrangementDerived` or an equivalent pure helper so every caller uses the same `#1`, `#2`, `#3` rule.

- [ ] **Step 3: Add and run the naming tests**

Add tests in `Tests/AgentStudioTests/Core/State/ArrangementDerivedTests.swift`:

```swift
    @Test
    func test_nextCustomArrangementName_startsAtHashOne() {
        let (tab, _) = createTabWithPanes(2)
        let derived = ArrangementDerived()
        #expect(derived.nextCustomArrangementName(for: tab.id) == "#1")
    }

    @Test
    func test_nextCustomArrangementName_skipsUsedIndexes() {
        let (tab, paneIds) = createTabWithPanes(3)
        _ = store.createArrangement(name: "#1", paneIds: Set([paneIds[0]]), inTab: tab.id)
        _ = store.createArrangement(name: "#2", paneIds: Set([paneIds[1]]), inTab: tab.id)

        let derived = ArrangementDerived()
        #expect(derived.nextCustomArrangementName(for: tab.id) == "#3")
    }
```

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "nextCustomArrangementName"
```

Expected: pass.

---

## Task 5: Rewire View, Coordinator, And Restore Consumers

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- Modify: `Tests/AgentStudioTests/App/ActionExecutorTests.swift`

- [ ] **Step 1: Update all top-level readers to use the active arrangement**

Replace top-level `tab.minimizedPaneIds` reads with `tab.activeArrangement.minimizedPaneIds` or `tab.activeMinimizedPaneIds` in:

- `ArrangementDerived`
- `SingleTabContent`
- `ActiveTabContent`
- `TabBarAdapter`
- `TerminalRestoreScheduler`
- `PaneCoordinator+ViewLifecycle`

Treat this as a hard cutover. Remove `Tab.minimizedPaneIds`, let the compiler surface every remaining read site, and fix each compile error in the same changeset. Use this inventory as the starting list, not the stopping condition:

- `ArrangementDerived`
- `SingleTabContent`
- `ActiveTabContent`
- `TabBarAdapter`
- `TerminalRestoreScheduler`
- `PaneCoordinator+ViewLifecycle`
- `PaneCoordinator+ActionExecution`

- [ ] **Step 2: Fix arrangement switch transition computation**

In `PaneCoordinator+ActionExecution.swift`, capture both previous and new arrangement-local minimized sets:

```swift
let previousVisiblePaneIds = tab.activeArrangement.visiblePaneIds
let previouslyMinimizedPaneIds = tab.activeArrangement.minimizedPaneIds
store.tabLayoutAtom.switchArrangement(to: arrangementId, inTab: tabId)
guard let updatedTab = store.tabLayoutAtom.tab(tabId) else { break }
let newVisiblePaneIds = updatedTab.activeArrangement.visiblePaneIds
let newlyMinimizedPaneIds = updatedTab.activeArrangement.minimizedPaneIds
```

Update transition computation so panes minimized in the target arrangement stay detached instead of being reattached just because they are visible members of that arrangement.

- [ ] **Step 3: Add the failing then passing coordinator regression test**

Add a test to `Tests/AgentStudioTests/App/ActionExecutorTests.swift` that:

- minimizes a pane in Default
- creates/switches to another arrangement
- switches back
- asserts the pane is still minimized in Default

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "switchArrangement"
```

Expected: pass with no regressions in existing arrangement switch tests.

---

## Task 6: Replace Alert Rename With Inline Rename And Widen The Panel

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/ArrangementPanelInlineRenameTests.swift`

- [ ] **Step 1: Write the failing inline rename interaction test**

Create `Tests/AgentStudioTests/Core/Views/ArrangementPanelInlineRenameTests.swift` with a focused state-level test around:

- entering inline rename mode for a non-default arrangement
- editing text in-place
- submitting rename without using `.alert`

The implementation can use a small extracted view-state helper if the SwiftUI surface is awkward to test directly.

- [ ] **Step 2: Replace alert-based rename with inline chip editing**

In `ArrangementPanel.swift`:

- remove `renamingArrangementId` + `.alert(...)`
- keep local rename draft state inline with the chip row
- double-clicking an arrangement name enters edit mode
- `TextField` appears in place of the chip label
- `Return` commits rename
- `Escape` or loss of focus cancels rename
- default arrangement should not enter rename mode

- [ ] **Step 3: Widen the arrangement panel**

Update:

```swift
.frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
```

This gives the pane list and inline rename field enough space without creating a giant panel.

- [ ] **Step 4: Run the arrangement panel tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ArrangementPanelInlineRenameTests|ArrangementDerivedTests"
```

Expected: pass.

---

## Task 7: Persist And Restore Arrangement-Scoped Minimized State

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`

- [ ] **Step 1: Let codable persistence carry arrangement-local minimize state**

No new top-level persistence schema fields are needed. Once `PaneArrangement` is `Codable` with `minimizedPaneIds`, the existing persisted `tabs` payload will include it automatically.

The required transformer change is pruning: when removing invalid pane IDs, also prune each arrangement’s minimized set against remaining layout pane IDs.

- [ ] **Step 2: Verify restart restore now round-trips arrangement-local minimized state**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "persistAndRestore"
```

Expected: pass for both existing arrangement persistence tests and the new minimized persistence test.

---

## Task 8: Update Docs To Match The Fixed Model

**Files:**
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/window_system_design.md`

- [ ] **Step 1: Update model docs**

In `component_architecture.md`:

- remove `Tab.minimizedPaneIds`
- add `PaneArrangement.minimizedPaneIds` as persisted arrangement state

In `window_system_design.md`:

- replace the contradictory “minimized state persists” / “transient, not persisted” pair
- document that top-level minimized panes are arrangement-scoped and restored with the arrangement

- [ ] **Step 2: Verify docs and code agree**

Run:

```bash
rg -n "Tab.minimizedPaneIds|transient, not persisted|PaneArrangement.minimizedPaneIds" docs/architecture Sources/AgentStudio
```

Expected: no stale docs claiming top-level minimize is tab-global transient state.

---

## Final Verification

- [ ] **Step 1: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreArrangementTests|WorkspacePersistenceTransformerTests|ActionExecutorTests|TabArrangementTests"
```

Expected: all focused tests pass.

- [ ] **Step 2: Run full project verification**

Run sequentially, not in parallel:

```bash
mise run test
mise run lint
```

Expected:

- `mise run test` exits `0`
- `mise run lint` exits `0`

- [ ] **Step 3: Manual behavior check**

Verify this exact user flow in the app:

1. Open a split tab with at least three panes.
2. Minimize one pane in Default.
3. Save or switch to another arrangement.
4. Switch back to Default.
5. Quit and relaunch the app.
6. Confirm the same pane is still minimized in Default.

---

## Self-Review

- Spec coverage: covers the in-memory model bug, the arrangement switch bug, the persistence gap, the launch/restore readers, and the docs drift.
- Placeholder scan: no `TODO`/`TBD` placeholders remain.
- Type consistency: the plan uses one model throughout: `PaneArrangement.minimizedPaneIds` owns top-level minimize state.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-16-arrangement-scoped-minimize-persistence.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
