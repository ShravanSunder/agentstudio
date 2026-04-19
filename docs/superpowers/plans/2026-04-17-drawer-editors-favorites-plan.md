# Drawer Editor Chooser Spec + Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:executing-plans` to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old drawer `VS/Cursor` control with one drawer-owned editor chooser button and dropup. Hard-cutover the old `FavoriteChoice` system first. The new chooser keeps menu content reusable, keeps runtime atom state editor-specific, and follows the existing workspace focus and command availability model.

**Architecture:** `DrawerEditorChooserFactory` owns the drawer-specific shell, placement, anchoring, and pane wiring. `EditorChooserMenuContent` is a dumb reusable renderer for numbered menu rows. These commands are UI side effects, not workspace mutations, so they use `WorkspaceFocus` + `visibleWhen` + `canExecute(_:)` and do **not** route through `PaneActionCommand` / `WorkspaceCommandValidator`.

**Execution Discipline:** This plan is strictly TDD. For every task:
- write or update the focused tests first
- run them red
- implement the minimum code to turn them green
- rerun the focused tests before moving on

**Slice Boundary:** This feature uses a host-shell plus feature-content split:
- `App/Panes/DrawerEditorChooser/` owns drawer-specific assembly, placement, anchoring, and pane wiring
- `Components/EditorChooser/` owns the reusable editor chooser menu content, row model, and menu styling
- `Core/State/.../UIStateAtom.swift` owns editor chooser runtime state
- `Infrastructure/` owns installed editor discovery and external editor launching

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSWorkspace`, main-actor atoms, persistence wrappers, `Testing`

---

## Spec

### Toolbar Contract

```
┌────────────────────────────────────────────────────────────────┐
│ [toggle] [add]                     [code icon + chevron] │ [F] │
└────────────────────────────────────────────────────────────────┘
```

- Replace the old `VS/Cursor` drawer control entirely.
- The editor chooser button is one static launcher:
  - code icon
  - popover chevron
  - no app name
  - no `Open in Editor` label
- Keep exactly one divider between the editor chooser and Finder.
- No divider after Finder.

### Dropup Contract

```
┌──────────────────────────────────────────────┐
│ [1] [app icon] Cursor             [bookmark] │
│ [2] [app icon] VS Code       [bookmark.fill] │
│ [3] [app icon] Windsurf            [bookmark]│
│ [4] [app icon] Antigravity         [bookmark]│
│ [5] [app icon] Xcode               [bookmark]│
└──────────────────────────────────────────────┘
```

- Row click opens that editor immediately.
- Bookmark click only toggles the bookmarked editor. It must never launch.
- Bookmark icons use:
  - `bookmark` for unbookmarked rows
  - `bookmark.fill` in accent color for the bookmarked row
- No `Current` badge.
- No last-selected editor state.
- Leading number badges use the same visual family as the drawer chrome:
  - subtle lighter fill than the popover background
  - no accent color by default
- Row hover background must be visible.
- Bookmark hit target must be at least `22x22`, preferably `24x24`.

### Editor State Model

The reusable view stays generic. The atom follows the editor feature definition.

```swift
struct EditorChooserState: Equatable, Codable {
    var openForPaneId: UUID?
    var bookmarkedEditorId: String?
}
```

Inside `UIStateAtom`, editor state is stored as a nested editor-specific value, not generic menu-choice fields.

Semantics:

- `bookmarkedEditorId`
  - the row with `bookmark.fill`
  - the editor launched by `⌘O`
- `openForPaneId`
  - which pane currently owns the open editor chooser
  - only one chooser can be open at a time

### Reuse Boundary

Reusable:

- `EditorChooserMenuContent`
- `EditorChoiceItem`
- `EditorChooserMenuModel`

Concrete:

- `DrawerEditorChooserFactory`

The factory takes the atom and concrete pane context, and derives:

- installed editor list
- row numbers
- open-state binding
- bookmark callbacks
- launch callbacks

The reusable view does **not** know about `UIStateAtom`.

### Launch Resolution

Row / button behavior:

- row click:
  - launch that editor
- bookmark click:
  - toggle `bookmarkedEditorId`
  - do not launch

Shortcut behavior:

- `⌘O`
  - launch bookmarked editor if one exists
  - otherwise use implicit default launch order:
    - Cursor if installed
    - otherwise VS Code if installed
    - otherwise do nothing
- `⌘⇧O`
  - reveal in Finder
- `⌘⌥O`
  - open the dropup

Default bookmark semantics:

- if no explicit bookmark exists, no row is visually bookmarked
- the implicit default launch order exists only for `⌘O`
- the dropup is opened only by:
  - toolbar button click
  - `⌘⌥O`

### Focus / Validator Rules

These commands are UI side-effect commands, not workspace mutations:

- `openPaneLocationInBookmarkedEditor`
- `openPaneLocationInFinder`
- `openPaneLocationInEditorMenu`

They must:

- use `visibleWhen: [.hasActivePane]`
- use `canExecute(_:)` to require `selectedPaneManagementContext()?.targetPath != nil`
- bypass `PaneActionCommand` and `WorkspaceCommandValidator`

This keeps them aligned with the current architecture:

- workspace focus controls visibility and discoverability
- command availability controls runtime executability
- validators remain for workspace-shape mutations only

### Pane Targeting

When a drawer pane is active, its path wins.

```
selected pane for location commands
  = visible active drawer pane if one exists
  = otherwise active main pane
```

This same resolution must be used for:

- toolbar button actions
- `⌘O`
- `⌘⇧O`
- `⌘⌥O`
- popover ownership (`openForPaneId`)

### Installed Editor Discovery

- Installed editor discovery must refresh on each menu build and on each open action.
- Do not rely on a process-lifetime static snapshot for the chooser contents.
- Keep discovery on `@MainActor` because it uses `NSWorkspace`.

---

## File Structure

### New files

- `Sources/AgentStudio/App/Panes/DrawerEditorChooser/DrawerEditorChooserFactory.swift`
  - Concrete drawer-editor wiring from atom + pane context into the drawer-owned shell.
- `Sources/AgentStudio/Components/EditorChooser/EditorChoiceItem.swift`
  - Reusable editor row model with `id`, `title`, `appIcon`, and `shortcutNumber`.
- `Sources/AgentStudio/Components/EditorChooser/EditorChooserMenuContent.swift`
  - Reusable numbered editor menu content. `EditorChooserMenuModel` lives in this file alongside the reusable view.
- `Tests/AgentStudioTests/Components/EditorChooser/EditorChooserMenuContentTests.swift`
  - Model-level row-order, number, and bookmark rendering tests.

### Deleted files

- `Sources/AgentStudio/Core/Views/Controls/FavoriteChoicePopover.swift`
- `Sources/AgentStudio/Core/Models/FavoriteChoiceItem.swift`
- `Tests/AgentStudioTests/Core/Views/FavoriteChoicePopoverModelTests.swift`

### Modified files

- `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
  - Remove generic choice-menu editor fields and replace them with nested editor-specific state.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
  - Hydrate and flush the nested editor state.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor.swift`
  - Remove old favorite-choice persistence and add editor-state persistence with backward-compatible decode.
- `Sources/AgentStudio/Infrastructure/ExternalApps/ExternalEditorTarget.swift`
  - Keep the existing editor catalog work, ensure discovery refreshes on each menu build and open action, and provide implicit default resolution.
- `Sources/AgentStudio/Infrastructure/ExternalApps/ExternalWorkspaceOpener.swift`
  - Remove old preferred/favorite helpers and keep only the concrete launch helpers needed by the new chooser.
- `Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift`
  - Replace old trailing props with the concrete editor chooser factory output.
- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
  - Host the new chooser button before Finder and suppress tooltips when the chooser is open.
- `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
  - Use the factory with the correct pane-target resolution and fresh editor discovery.
- `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Align pane-location command definitions with the final shortcut map.
- `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Final shortcuts for editor chooser, Finder, and bookmarked/default editor.
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Final direct command behavior and `canExecute` gating.
- `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
  - New shortcut map coverage.
- `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
  - Bookmarked/default editor path, implicit default launch order, and drawer-pane targeting coverage.
- `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift`
  - Persistence and backward-compat coverage.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceUIStoreTests.swift`
  - `bookmarkedEditorId` and `openForPaneId` atom behavior.
- `Tests/AgentStudioTests/Infrastructure/ExternalApps/ExternalWorkspaceOpenerTests.swift`
  - app/CLI fallback ordering and stale target handling.
- `docs/architecture/directory_structure.md`
  - Add the host-shell vs feature-content placement rule and this chooser as a concrete example.
- `docs/architecture/README.md`
  - Add `Components/EditorChooser/` to the architecture map.
- `docs/architecture/appkit_swiftui_architecture.md`
  - Document that drawer toolbar assembly stays App-owned even when it embeds feature-owned content.

---

## Tasks

### Task 0: Hard-Cutover Remove The FavoriteChoice Abstraction

**Files:**
- Delete: `Sources/AgentStudio/Core/Views/Controls/FavoriteChoicePopover.swift`
- Delete: `Sources/AgentStudio/Core/Models/FavoriteChoiceItem.swift`
- Delete: `Tests/AgentStudioTests/Core/Views/FavoriteChoicePopoverModelTests.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Infrastructure/ExternalApps/ExternalWorkspaceOpener.swift`

- [ ] **Step 1: Delete the old UI/model/test files**

Delete:
- `FavoriteChoicePopover`
- `FavoriteChoiceItem`
- `FavoriteChoicePopoverModelTests`

- [ ] **Step 2: Remove old generic atom state and API**

Delete from `UIStateAtom`:
- `favoriteChoiceByMenuId`
- `recentChoiceByMenuId`
- `activeChoicePopoverRequest`
- `ChoicePopoverRequest`
- `favoriteChoice(...)`
- `recentChoice(...)`
- `setFavoriteChoice(...)`
- `setRecentChoice(...)`
- `requestChoicePopover(...)`

- [ ] **Step 3: Remove old generic persistence**

Delete old persistence fields and decode branches tied to:
- `favoriteChoiceByMenuId`
- `recentChoiceByMenuId`
- old generic popover state

Old persisted JSON containing those fields is silently ignored on decode. No migration shim and no backward-compat runtime path.

- [ ] **Step 4: Remove old command, shortcut, and opener surfaces**

Delete old command and shortcut cases:
- `openPaneLocationInPreferredEditor`
- `openPaneLocationInFavoriteEditor`

Delete old opener helpers:
- `openInPreferredEditor`
- `openInFavoriteEditor`

- [ ] **Step 5: Remove old wiring from drawer and controller code**

Delete all references to:
- `FavoriteChoicePopover`
- `FavoriteChoiceItem`
- `drawer.external-editor`
- old recent/favorite choice helpers

- [ ] **Step 6: Run a grep sweep to prove hard cutover**

Run:
`rg -n "FavoriteChoice|favoriteChoiceByMenuId|recentChoiceByMenuId|activeChoicePopoverRequest|ChoicePopoverRequest|drawer.external-editor|openPaneLocationInPreferredEditor|openPaneLocationInFavoriteEditor|openInPreferredEditor|openInFavoriteEditor" Sources/AgentStudio Tests/AgentStudioTests`

Expected:
- no results

### Task 1: Introduce Editor-Specific Atom State And Persistence

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceUIStoreTests.swift`

- [ ] **Step 1: Write the failing atom and persistence tests**

```swift
@Test
func editorState_bookmarkedEditor_roundTripsThroughPersistence() throws {
    let workspaceId = UUID()
    let atom = UIStateAtom()
    let store = UIStateStore(atom: atom, persistor: persistor)

    atom.setBookmarkedEditor("vscode")

    try store.flush(for: workspaceId)

    let restoredAtom = UIStateAtom()
    UIStateStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

    #expect(restoredAtom.editorChooserState.bookmarkedEditorId == "vscode")
}

@Test
func editorState_clear_resetsOpenAndBookmarked() {
    let atom = UIStateAtom()

    atom.setBookmarkedEditor("xcode")
    atom.setOpenEditorPane(UUID())

    atom.clear()

    #expect(atom.editorChooserState.bookmarkedEditorId == nil)
    #expect(atom.editorChooserState.openForPaneId == nil)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:
`swift test --filter "UIStateStoreTests|WorkspaceUIStoreTests" --build-path ".build-agent-$PPID"`

Expected:
- FAIL because `editorChooserState` does not exist yet

- [ ] **Step 3: Implement nested editor state**

```swift
struct EditorChooserState: Equatable, Codable {
    var openForPaneId: UUID?
    var bookmarkedEditorId: String?
}
```

Add editor-specific mutators on `UIStateAtom`:
- `setBookmarkedEditor(_:)`
- `setOpenEditorPane(_:)`

- [ ] **Step 4: Make persistence backward-compatible**

Add a new `editorChooserState` field to `PersistableUIState` with explicit decode fallback:

```swift
self.editorChooserState =
    try container.decodeIfPresent(EditorChooserState.self, forKey: .editorChooserState) ?? .init()
```

On restore and hydrate:
- always reset `editorChooserState.openForPaneId = nil`
- never restore an open chooser across launches or workspace reloads

- [ ] **Step 5: Run the focused tests to verify they pass**

Run:
`swift test --filter "UIStateStoreTests|WorkspaceUIStoreTests" --build-path ".build-agent-$PPID"`

Expected:
- PASS

### Task 2: Build The Reusable Popover And Concrete Drawer Factory

**Files:**
- Create: `Sources/AgentStudio/Components/EditorChooser/EditorChoiceItem.swift`
- Create: `Sources/AgentStudio/Components/EditorChooser/EditorChooserMenuContent.swift`
- Create: `Sources/AgentStudio/App/Panes/DrawerEditorChooser/DrawerEditorChooserFactory.swift`
- Test: `Tests/AgentStudioTests/Components/EditorChooser/EditorChooserMenuContentTests.swift`

- [ ] **Step 1: Write the failing reusable model tests**

```swift
@Test
func displayItems_preserveOrderAndNumbers() {
    let items = [
        EditorChoiceItem(id: "cursor", title: "Cursor", appIcon: nil, shortcutNumber: 1),
        EditorChoiceItem(id: "vscode", title: "VS Code", appIcon: nil, shortcutNumber: 2),
    ]

    let rows = EditorChooserMenuModel.displayItems(
        items: items,
        bookmarkedEditorId: "vscode"
    )

    #expect(rows.map(\.shortcutNumber) == [1, 2])
    #expect(rows.last?.isBookmarked == true)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:
`swift test --filter "EditorChooserMenuContentTests" --build-path ".build-agent-$PPID"`

Expected:
- FAIL because the reusable model does not exist yet

- [ ] **Step 3: Implement the reusable model and popover**

Implement:
- `EditorChoiceItem`
- `EditorChooserMenuModel`
- `EditorChooserMenuContent`

The reusable view receives only:
- items
- `bookmarkedEditorId`
- `isPresented` binding
- `onSelect`
- `onToggleBookmark`

It must not know about `UIStateAtom`.

- [ ] **Step 4: Implement the concrete factory**

`DrawerEditorChooserFactory` owns:
- installed editor discovery
- stable ordering
- number assignment
- open-state binding to `editorChooserState.openForPaneId`
- bookmark binding to `editorChooserState.bookmarkedEditorId`
- launch callback wiring

It takes:
- the atom
- pane id
- launch closure

It does **not** require callers to prebuild `EditorChoiceItem` arrays.

- [ ] **Step 5: Run the focused tests to verify they pass**

Run:
`swift test --filter "EditorChooserMenuContentTests" --build-path ".build-agent-$PPID"`

Expected:
- PASS

### Task 3: Integrate The Drawer Toolbar And Final Shortcuts

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`

- [ ] **Step 1: Write the failing shortcut and behavior tests, and add compile-only command stubs if needed**

```swift
@Test
func shortcutDecoder_decodesFinalEditorShortcuts() {
    #expect(
        ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command]),
            in: .global
        ) == .openPaneLocationInBookmarkedEditor
    )
    #expect(
        ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command, .shift]),
            in: .global
        ) == .openPaneLocationInFinder
    )
    #expect(
        ShortcutDecoder.shortcut(
            for: .init(key: .character(.o), modifiers: [.command, .option]),
            in: .global
        ) == .openPaneLocationInEditorMenu
    )
}
```

```swift
@Test("bookmarked editor shortcut without bookmark uses implicit default order")
func executeOpenBookmarkedEditor_withoutBookmark_usesImplicitDefaultOrder() {
    let harness = makeHarness()
    let (repo, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
    let pane = harness.store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Pane",
        provider: .zmx
    )
    let tab = Tab(paneId: pane.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    let didExecute = harness.controller.execute(.openPaneLocationInBookmarkedEditor)

    #expect(didExecute)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:
`swift test --filter "ShortcutCatalogTests|PaneTabViewControllerCommandTests|DrawerCommandIntegrationTests" --build-path ".build-agent-$PPID"`

Expected:
- FAIL on stale shortcut map or old command behavior

- [ ] **Step 3: Wire the new toolbar and command behavior**

Implement:
- drawer toolbar order: `[editor chooser] │ [Finder]`
- no old VS/Cursor button
- no divider after Finder
- `⌘O` launches bookmark if present, else uses Cursor → VS Code → nothing
- `⌘⇧O` reveals in Finder
- `⌘⌥O` opens chooser

- [ ] **Step 4: Keep focus and validator semantics correct**

Keep:
- `visibleWhen: [.hasActivePane]`
- `canExecute(_:)` gating on `targetPath`
- direct controller handling

Do not:
- route these commands through `PaneActionCommand`
- route these commands through `WorkspaceCommandValidator`

- [ ] **Step 5: Run the focused tests to verify they pass**

Run:
`swift test --filter "ShortcutCatalogTests|PaneTabViewControllerCommandTests|DrawerCommandIntegrationTests" --build-path ".build-agent-$PPID"`

Expected:
- PASS

### Task 4: Update Architecture Docs For The New Slice Boundary

**Files:**
- Modify: `docs/architecture/directory_structure.md`
- Modify: `docs/architecture/README.md`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`

- [ ] **Step 1: Document the host-shell vs feature-content split**

Add to `directory_structure.md`:
- `App/` owns host-specific shell assembly
- `Features/` owns capability-specific reusable content
- `Core/` owns shared state and contracts
- `Infrastructure/` owns OS / process integration

Add this chooser as the concrete example:
- `App/Panes/DrawerEditorChooser/` owns drawer button, placement, anchoring, divider, and pane wiring
- `Components/EditorChooser/` owns numbered rows, bookmark UI, and chooser model

- [ ] **Step 2: Update the architecture index**

Add `Components/EditorChooser/` to `docs/architecture/README.md` so the new slice is visible in the architecture map.

- [ ] **Step 3: Update AppKit/SwiftUI architecture guidance**

Add a short note to `appkit_swiftui_architecture.md` that host surfaces such as drawer toolbars remain App-owned assembly points even when they embed feature-owned content.

- [ ] **Step 4: Review doc wording for consistency**

Make sure the same terms are used throughout:
- `DrawerEditorChooserFactory`
- `EditorChooserMenuContent`
- `EditorChooserMenuModel`
- `EditorChooserState`

### Task 5: Finish The Important Regression Coverage

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceUIStoreTests.swift`
- Modify: `Tests/AgentStudioTests/Infrastructure/ExternalApps/ExternalWorkspaceOpenerTests.swift`
- Modify: `Tests/AgentStudioTests/Components/EditorChooser/EditorChooserMenuContentTests.swift`

- [ ] **Step 1: Add the missing regression tests**

Add explicit coverage for:
- bookmark toggle on the same editor clears the bookmark
- app request failing falls back to command request when available
- implicit default launch order for `⌘O`: bookmark → Cursor → VS Code → nothing
- chooser opens for the drawer pane, not the parent pane
- `clear()` resets `openForPaneId`

- [ ] **Step 2: Run the focused regression tests to verify they pass**

Run:
`swift test --filter "WorkspaceUIStoreTests|ExternalWorkspaceOpenerTests|EditorChooserMenuContentTests|PaneTabViewControllerCommandTests" --build-path ".build-agent-$PPID"`

Expected:
- PASS

### Task 6: Full Verification

**Files:**
- Verify existing tree only

- [ ] **Step 1: Run the full test suite**

Run:
`mise run test`

Expected:
- PASS, exit code `0`

- [ ] **Step 2: Run lint**

Run:
`mise run lint`

Expected:
- PASS, exit code `0`

- [ ] **Step 3: Visually verify the drawer toolbar and dropup**

Verify:
- static editor chooser button placement
- single divider before Finder
- no divider after Finder
- row hover treatment
- bookmark hit target and non-launch behavior
- numbered badge styling in the drawer color family

Use Peekaboo if allowed for this branch's verification workflow; otherwise perform explicit user-run visual verification before calling the task done.

---

## Self-Review

- **Hard cutover:** The old `FavoriteChoice` abstraction is deleted before the new chooser lands. No shims, no parallel paths, no compatibility layer.
- **Spec coverage:** Covers final toolbar shape, final shortcut map, editor-specific atom state, reusable-vs-concrete split, bookmark behavior, and focus/validator rules.
- **Focus and validation:** Uses `WorkspaceFocus` and `visibleWhen` for discoverability, `canExecute(_:)` for runtime availability, and bypasses workspace mutation validation by design.
- **Placeholder scan:** No TODO/TBD/“if desired” branches remain.
- **Type consistency:** The same terms are used throughout: `editorChooserState`, `bookmarkedEditorId`, `openForPaneId`, `EditorChooserState`, `DrawerEditorChooserFactory`, `EditorChooserMenuContent`, `EditorChooserMenuModel`.
