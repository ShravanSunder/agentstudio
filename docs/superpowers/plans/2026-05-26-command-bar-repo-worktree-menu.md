# Command Bar Repo Worktree Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the `#` command-bar scope into a repo -> worktree -> action navigator, keep `$` as pane selection with richer search metadata, make pane cwd changes refresh pane repo/worktree identity, and add user/agent-settable notes for main panes.

**Architecture:** `#` becomes an object browser. Root rows are repo containers; repo rows drill into worktrees; worktree rows drill into an action screen. Container rows own skip-ahead `Cmd-Return` / `Opt-Return`; leaf rows execute on Return. Cwd synchronization lands before `$` search enrichment and stays in `PaneCoordinator`, because it already receives surface/runtime cwd facts and can resolve topology without making `WorkspacePaneAtom` depend on repository topology. Pane notes live on `PaneMetadata` as user-authored labels, separate from live repo/worktree/cwd facets.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI command-bar views, `WorkspaceStore`/atoms, `CommandDispatcher`, existing `CommandBarItem`/`CommandBarLevel` navigation stack.

---

## Current Grounding

- `CommandBarDataSource.repoScopeItems(store:)` currently mixes single-worktree rows at root and groups multi-worktree repos by `"repo (worktrees)"`.
- `CommandBarDataSource.buildWorktreeActionsLevel(...)` currently builds an `"Open"` group containing new-pane actions and a `"Navigate to"` group containing existing panes.
- `CommandBarAction.worktreeAction(presence:)` and `CommandBarWorktreeActionResolver` already encode Return drills in and modified Enter opens.
- `FooterHintBuilder` already knows worktree rows get `Cmd-Return` / `Opt-Return` hints.
- `$` pane search already matches pane repo/worktree/cwd keywords through `keywordsForPane(...)`, but tab rows only have `["tab", "switch"]`.
- `PaneCoordinator.onSurfaceCWDChanged(...)` and the runtime `.cwdChanged` branch update cwd only; they do not refresh `repoId` / `worktreeId`.
- `WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing:)` already resolves the deepest matching worktree for a cwd.
- `PaneMetadata.source` is fixed-at-creation provenance; `PaneMetadata.facets` is live metadata. The data model already has the right split, so do not add `startingRepoId`, `startingWorktreeId`, or a parallel "original identity" blob.
- `PaneMetadata` does not currently have a user-authored note field. `WorkspacePaneAtom` has `updatePaneTitle(...)` and `renamePane(...)`, but no note mutation. `PaneDisplayDerived.collapsedBarLabelParts(for:)` renders generated repo/worktree/branch/cwd labels for minimized panes, and `$` pane rows use `tab.activePaneIds`, which are main active-arrangement panes, not drawer children.

## Command Bar Mantra

```text
# owns locations and opening.

$ owns existing pane navigation.

> owns verbs.
```

## Data Model Contract

```text
Pane
  id
    stable pane identity across layout, surface, runtime, and zmx

  metadata.source
    fixed launch provenance
    .worktree(worktreeId, repoId, launchDirectory)
    .floating(launchDirectory, title)

  metadata.facets.cwd
    live terminal cwd, updated by Ghostty/runtime cwd facts

  metadata.facets.repoId / worktreeId / repoName / worktreeName
    live location identity, re-resolved from cwd when cwd is inside a
    known worktree

  metadata.note
    live user/agent-authored pane note
    visible on minimized/collapsed main-pane chrome
    searchable in $ pane selection
    not part of source provenance and not part of cwd-derived facets
```

## Live Identity Flow

```text
Ghostty pwd action OR TerminalRuntime cwdChanged
        │
        ▼
PaneCoordinator receives cwd fact
        │
        ▼
WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing: cwd)
        │
        ▼
WorkspacePaneAtom updates live facets
        │
        ├── cwd
        ├── repoId / repoName
        └── worktreeId / worktreeName
        │
        ▼
Command bar, tab labels, pane labels, presence, and $ search read the
updated live identity
```

## Design Decisions

- `#` root is repo-only. Single-worktree repos still drill in so row shape is consistent.
- Star means main worktree only, never repo.
- Repo-screen path commands target the repo's main/default worktree path.
- Worktree-screen path commands target that exact worktree path.
- `Copy Current Pane Path` is a `>` command, not a `#` row. It copies the active main pane's live cwd, falling back to launch directory when cwd is not known. Shortcut: `Cmd-Opt-Shift-O`.
- The first worktree action group is named `Open` and includes both path actions and pane-opening actions:
  - `Copy path`
  - `Reveal in Finder`
  - `New pane in new tab`
  - `New pane in current tab`
- `$` filters by repo name, worktree name, tab title, pane title, and cwd/path metadata, but it still only focuses/selects existing tabs and panes.
- Cwd identity refresh must land before `$` search enrichment because stale live facets would make search and presence lie after a shell `cd`.
- Live identity follows cwd. If a terminal changes directory into another known worktree, command-bar labels, `$` search, and `#` presence should treat the pane as belonging to the new worktree.
- If cwd changes outside any known worktree, clear live repo/worktree facets so stale presence/search metadata does not lie. The immutable launch source still records where the pane was born.
- Launch source remains provenance and fallback. Do not add another stored "starting identity" field unless a future feature has a concrete user-visible need for it.
- Floating panes follow the same live-identity rule. A `.floating` source pane that cds into a known worktree keeps `PaneMetadata.source == .floating(...)`, but its live facets may resolve to that repo/worktree for labels, search, and presence. It is not converted into a worktree-launched pane.
- Repo/worktree names in facets are live display cache. Topology lookup remains authoritative; names may be filled by cwd resolution and should not be the only source of truth.
- Pane notes are main-pane UI affordances. Store the note on pane metadata so persistence, command-bar search, and display all read one value, but expose editing and minimized-note display only for main panes. Drawer child panes inherit the parent work context and stay out of this note-editing surface.
- `Edit Pane Note` is a `>` command scoped to the active main pane. Shortcut: `Cmd-Opt-Shift-N`.
- Notes do not replace generated identity. A note should be the human label shown first when space is tight; repo/worktree/branch/cwd identity remains searchable and visible as supporting metadata.

## File Structure

- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`
  - Add explicit repo navigation action shape.
  - Keep footer semantics compile-time explicit.

- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
  - Replace current mixed repo scope with repo root rows.
  - Add repo level builder.
  - Add worktree level path actions in the existing `Open` group.
  - Reuse `LocalActionSpec.copyPath` and `LocalActionSpec.revealInFinder` for labels/icons.

- Create: `Sources/AgentStudio/Infrastructure/PathActions.swift`
  - Shared side-effect helper for Copy Path and Reveal in Finder.

- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
  - Route repo reveal action through shared `PathActions`.

- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
  - Route worktree reveal/copy actions through shared `PathActions`.

- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
  - Add tab keyword enrichment for `$` search.
  - Keep pane scope action ownership narrow.

- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
  - Add a narrow method to update cwd and resolved repo/worktree facets together.
  - Add a narrow method to update a pane note.

- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`
  - Add `private(set) var note: String?`.
  - Normalize whitespace-only notes to `nil`.
  - Preserve backwards-compatible decode with `decodeIfPresent`.

- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
  - Include note in `PaneDisplayParts`.
  - Include note in pane search keywords.
  - Show note first in collapsed/minimized main-pane label parts, followed by generated repo/worktree/branch identity.

- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
  - Route both surface cwd changes and runtime cwd facts through one helper that updates cwd plus resolved identity.

- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Add `editPaneNote`.
  - Add `copyCurrentPanePath`.

- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Add `editPaneNote` with `Cmd-Opt-Shift-N`.
  - Add `copyCurrentPanePath` with `Cmd-Opt-Shift-O`.

- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
  - Add a command-bar entry for editing the current main pane note.
  - Add a command-bar entry for copying the current main pane path.

- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
  - Classify `editPaneNote` and `copyCurrentPanePath` as controller-local non-pane commands so the exhaustive command switch stays compiling.

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Dispatch `editPaneNote` for the active main pane only.
  - Dispatch `copyCurrentPanePath` for the active main pane only.
  - Do not expose note editing for drawer children.
  - Do not copy drawer child pane paths from this command.

- Create: `Sources/AgentStudio/App/Panes/PaneNote/PaneNotePresentation.swift`
  - Owns the presentation seam for the pane-note editor.
  - Keeps `PaneTabViewController` testable without building a popover in controller tests.

- Modify: `AGENTS.md`
  - Add the command-bar mantra and live identity rule to the command/shortcut guidance so future agents do not conflate `#`, `$`, and `>`.

- Modify: `docs/architecture/commands_and_shortcuts.md`
  - Document command-bar scope ownership, drill-in semantics, and footer shortcut semantics.

- Modify: `docs/architecture/workspace_data_architecture.md`
  - Document live cwd -> repo/worktree identity resolution as workspace data model behavior.

- Modify: `docs/architecture/component_architecture.md`
  - Clarify `PaneMetadata.source` is fixed provenance and `PaneMetadata.facets` owns live identity.

- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift`
  - Pin repo-only root, repo drill-in, worktree action grouping, and path action placement.

- Test: `Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift`
  - Pin repo/worktree container hint semantics for explicit repo navigation actions.

- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
  - Pin `$` filtering by repo/worktree/tab/pane metadata.

- Test: `Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift`
  - Pin runtime cwd changes re-associate pane identity.

- Test: `Tests/AgentStudioTests/App/PaneCoordinatorCWDIdentityTests.swift`
  - Pin surface cwd stream changes re-associate pane identity.

- Test: `Tests/AgentStudioTests/Core/RuntimeEventSystem/Contracts/PaneMetadataTests.swift`
  - Pin note normalization and decode compatibility.

- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneDisplayDerivedTests.swift`
  - Pin note appears first in collapsed/minimized main-pane label parts and participates in keywords.

- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
  - Pin `$` search matches pane notes.

- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerPaneNoteTests.swift`
  - Pin edit-note dispatch targets only active main panes.

---

### Task 1: Add Repo Root Rows For `#`

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift`

- [ ] **Step 1: Write the failing root-shape tests**

Add these tests to `CommandBarUnifiedWorktreeDataSourceTests`.

```swift
@Test
func test_reposScope_rootRowsAreReposNotWorktrees() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/root-agent-studio"))
    let main = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/root-agent-studio"),
        isMainWorktree: true
    )
    let feature = Worktree(
        repoId: repo.id,
        name: "pane-shortcuts",
        path: URL(filePath: "/tmp/root-agent-studio.pane-shortcuts")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])

    let items = CommandBarDataSource.items(
        scope: .repos,
        store: store,
        repoCache: RepoCacheAtom(),
        dispatcher: dispatcher
    )

    #expect(items.contains { $0.id == "repo-\(repo.id.uuidString)" })
    #expect(!items.contains { $0.id == "repo-wt-\(main.id.uuidString)" })
    #expect(!items.contains { $0.id == "repo-wt-\(feature.id.uuidString)" })

    let repoItem = items.first { $0.id == "repo-\(repo.id.uuidString)" }
    #expect(repoItem?.title == "root-agent-studio")
    #expect(repoItem?.subtitle == "2 worktrees")
    #expect(repoItem?.hasChildren == true)
    #expect(repoItem?.group == "Repos")
}

@Test
func test_reposScope_singleWorktreeRepoStillDrillsIn() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/single-root-repo"))

    let items = CommandBarDataSource.items(
        scope: .repos,
        store: store,
        repoCache: RepoCacheAtom(),
        dispatcher: dispatcher
    )

    let repoItem = items.first { $0.id == "repo-\(repo.id.uuidString)" }
    #expect(repoItem?.title == "single-root-repo")
    #expect(repoItem?.hasChildren == true)

    guard case .navigateRepo(let level) = repoItem?.action else {
        Issue.record("Expected repo root row to navigate")
        return
    }
    #expect(level.title == "single-root-repo")
    #expect(level.scopeLabel == "Repo")
}
```

- [ ] **Step 2: Run root-shape tests to verify they fail**

Run:

```bash
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_reposScope_rootRowsAreReposNotWorktrees"
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_reposScope_singleWorktreeRepoStillDrillsIn"
```

Expected: FAIL because `repoScopeItems` currently emits `repo-wt-*` worktree rows at root.

- [ ] **Step 3: Add explicit repo navigation action**

In `CommandBarAction`, add a typed repo navigation action. This keeps item kinding action-based instead of coupling behavior to string id prefixes.

```swift
case navigateRepo(CommandBarLevel)
```

In `CommandBarItemKind`, add `.repo`.

```swift
enum CommandBarItemKind {
    case repo
    case tab
    case pane
    case worktree
    case command
    case other
}
```

Update `kind`:

```swift
var kind: CommandBarItemKind {
    switch action {
    case .worktreeAction:
        return .worktree
    case .dispatch:
        return .command
    case .navigate:
        return command == nil ? .other : .command
    case .navigateRepo:
        return .repo
    case .custom:
        return .other
    case .dispatchTargeted(let command, _, let targetType):
        if command == .selectTab && targetType == .tab {
            return .tab
        }
        if command == .focusPane && (targetType == .pane || targetType == .floatingTerminal) {
            return .pane
        }
        return .command
    }
}
```

Update `CommandBarItem.worktreeOpenState` so `.navigateRepo` returns `nil` with `.navigate`, and update `CommandBarPanelController.executeItem(...)`:

```swift
case .navigate(let level), .navigateRepo(let level):
    state.pushLevel(level)
```

- [ ] **Step 4: Replace `repoScopeItems` root emission**

Replace `repoScopeItems(store:)` in `CommandBarDataSource+WorktreeRows.swift` with repo rows only.

```swift
static func repoScopeItems(store: WorkspaceStore) -> [CommandBarItem] {
    store.repositoryTopologyAtom.repos
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .map { repo in
            repoRootItem(repo: repo, store: store)
        }
}
```

Add the root item helper:

```swift
static func repoRootItem(repo: Repo, store: WorkspaceStore) -> CommandBarItem {
    let level = buildRepoLevel(repo: repo, store: store)
    return CommandBarItem(
        id: "repo-\(repo.id.uuidString)",
        title: repo.name,
        subtitle: repoRootSubtitle(repo: repo, store: store),
        icon: .system(.folder),
        group: "Repos",
        groupPriority: 0,
        keywords: repoRootKeywords(repo: repo),
        hasChildren: true,
        action: .navigateRepo(level)
    )
}

static func repoRootKeywords(repo: Repo) -> [String] {
    var keywords = ["repo", repo.name, repo.repoPath.lastPathComponent]
    keywords.append(contentsOf: repo.worktrees.map(\.name))
    keywords.append(contentsOf: repo.worktrees.map { $0.path.lastPathComponent })
    return keywords
}

static func repoRootSubtitle(repo: Repo, store: WorkspaceStore) -> String? {
    let openPanes = repo.worktrees.flatMap { worktree in
        buildWorktreePresence(worktree: worktree, repo: repo, store: store).openPanes
    }
    let openPaneCount = openPanes.count
    let worktreeCount = repo.worktrees.count

    var parts: [String] = []
    if worktreeCount == 1 {
        if let first = openPanes.first, openPaneCount == 1 {
            parts.append("● Tab \(first.tabIndex + 1) · 1 pane")
        } else if openPaneCount > 1 {
            parts.append("● \(openPaneCount) panes")
        }
    } else {
        parts.append("\(worktreeCount) worktrees")
        if openPaneCount > 0 {
            parts.append("● \(openPaneCount) open")
        }
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
```

- [ ] **Step 5: Run the root-shape tests**

Run:

```bash
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_reposScope_rootRowsAreReposNotWorktrees"
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_reposScope_singleWorktreeRepoStillDrillsIn"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift \
  Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift
git commit -m "feat: make repo command scope root repo-first"
```

---

### Task 2: Add Repo And Worktree Action Levels With One `Open` Group

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift`

- [ ] **Step 1: Write failing action-level tests**

Add these tests.

```swift
@Test
func test_repoLevelShowsOpenCommandsBeforeWorktrees() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/repo-level-actions"))
    let main = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/repo-level-actions"),
        isMainWorktree: true
    )
    let feature = Worktree(
        repoId: repo.id,
        name: "feature",
        path: URL(filePath: "/tmp/repo-level-actions-feature")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])
    let storedRepo = store.repos[0]

    let level = CommandBarDataSource.buildRepoLevel(repo: storedRepo, store: store)

    #expect(level.title == "repo-level-actions")
    #expect(level.scopeLabel == "Repo")
    #expect(level.items.map(\.title).prefix(2) == ["Copy path", "Reveal in Finder"])
    #expect(level.items[0].group == "Open")
    #expect(level.items[1].group == "Open")
    #expect(level.items.contains { $0.title == "main" && $0.group == "Worktrees" })
    #expect(level.items.contains { $0.title == "feature" && $0.group == "Worktrees" })
}

@Test
func test_worktreeLevelUsesSingleOpenGroupForPathAndPaneActions() {
    let presence = makeWorktreePresence(paneCount: 1)
    let worktree = Worktree(
        repoId: presence.repoId,
        name: presence.worktreeName,
        path: URL(filePath: "/tmp/repo/main"),
        isMainWorktree: presence.isMainWorktree
    )

    let level = CommandBarDataSource.buildWorktreeActionsLevel(
        worktree: worktree,
        presence: presence,
        canOpenInCurrentTab: true
    )

    let openTitles = level.items.filter { $0.group == "Open" }.map(\.title)
    #expect(openTitles == [
        "Copy path",
        "Reveal in Finder",
        "New pane in new tab",
        "New pane in current tab",
    ])
    #expect(level.items.contains { $0.group == "Navigate to" && $0.title == "Terminal — main" })
}
```

- [ ] **Step 2: Run action-level tests to verify they fail**

Run:

```bash
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_repoLevelShowsOpenCommandsBeforeWorktrees"
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_worktreeLevelUsesSingleOpenGroupForPathAndPaneActions"
```

Expected: FAIL because `buildRepoLevel` does not exist and worktree actions do not include path commands.

- [ ] **Step 3: Add shared path action helper**

Create `Sources/AgentStudio/Infrastructure/PathActions.swift`.

```swift
import AppKit
import Foundation

enum PathActions {
    @MainActor
    static func copyPath(_ path: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path.path, forType: .string)
    }

    @MainActor
    @discardableResult
    static func revealInFinder(_ path: URL) -> Bool {
        ExternalWorkspaceOpener.openInFinder(path)
    }
}
```

Update `RepoExplorerView`:

```swift
Button(LocalActionSpec.revealInFinder.actionSpec.label) {
    PathActions.revealInFinder(primaryRepo.repoPath)
}
```

Update `RepoExplorerWorktreeRow`:

```swift
Button {
    PathActions.revealInFinder(worktree.path)
} label: {
    menuLabel(actionSpec: LocalActionSpec.revealInFinder.actionSpec)
}

Button {
    PathActions.copyPath(worktree.path)
} label: {
    menuLabel(actionSpec: LocalActionSpec.copyPath.actionSpec)
}
```

- [ ] **Step 4: Add command-bar path action item helpers**

Add these helpers in `CommandBarDataSource+WorktreeRows.swift`. They reuse `LocalActionSpec` so command bar and sidebar share labels/icons.

```swift
static func copyPathItem(id: String, path: URL, group: String, groupPriority: Int) -> CommandBarItem {
    let spec = LocalActionSpec.copyPath.actionSpec
    CommandBarItem(
        id: "\(id)-copy-path",
        title: spec.label,
        icon: spec.icon,
        group: group,
        groupPriority: groupPriority,
        keywords: ["copy", "path", path.path],
        action: .custom {
            Task { @MainActor in
                PathActions.copyPath(path)
            }
        }
    )
}

static func revealInFinderItem(id: String, path: URL, group: String, groupPriority: Int) -> CommandBarItem {
    let spec = LocalActionSpec.revealInFinder.actionSpec
    CommandBarItem(
        id: "\(id)-reveal-finder",
        title: spec.label,
        icon: spec.icon,
        group: group,
        groupPriority: groupPriority,
        keywords: ["reveal", "finder", "open", "path", path.path],
        action: .custom {
            Task { @MainActor in
                PathActions.revealInFinder(path)
            }
        }
    )
}
```

- [ ] **Step 5: Add `buildRepoLevel`**

Add this function in `CommandBarDataSource+WorktreeRows.swift`.

```swift
static func buildRepoLevel(repo: Repo, store: WorkspaceStore) -> CommandBarLevel {
    let defaultWorktree = repo.worktrees.first(where: \.isMainWorktree) ?? repo.worktrees.first
    var items: [CommandBarItem] = []

    if let defaultWorktree {
        items.append(copyPathItem(id: "repo-\(repo.id.uuidString)", path: defaultWorktree.path, group: "Open", groupPriority: 0))
        items.append(revealInFinderItem(id: "repo-\(repo.id.uuidString)", path: defaultWorktree.path, group: "Open", groupPriority: 0))
    }

    items.append(
        contentsOf: repo.worktrees
            .sorted { lhs, rhs in
                if lhs.isMainWorktree != rhs.isMainWorktree {
                    return lhs.isMainWorktree
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { worktree in
                let presence = buildWorktreePresence(worktree: worktree, repo: repo, store: store)
                let level = buildWorktreeActionsLevel(
                    worktree: worktree,
                    presence: presence,
                    canOpenInCurrentTab: store.activeTabId != nil
                )
                return CommandBarItem(
                    id: "repo-wt-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: worktreePresenceSubtitle(presence: presence, worktree: worktree),
                    icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
                    group: "Worktrees",
                    groupPriority: 1,
                    keywords: ["repo", "worktree", "terminal", repo.name, worktree.name, worktree.path.path],
                    hasChildren: true,
                    action: .navigate(level),
                    command: .openWorktree
                )
            }
    )

    return CommandBarLevel(
        id: "level-repo-\(repo.id.uuidString)",
        title: repo.name,
        parentLabel: "Repos",
        scopeLabel: "Repo",
        items: items
    )
}
```

- [ ] **Step 6: Put path actions into the existing worktree `Open` group**

Change `buildWorktreeActionsLevel` to accept the selected worktree, then initialize `items` with Copy/Revealer first and append new-pane rows.

```swift
static func buildWorktreeActionsLevel(
    worktree: Worktree,
    presence: WorktreePresence,
    canOpenInCurrentTab: Bool
) -> CommandBarLevel {
    let worktreeId = presence.worktreeId
    // existing body continues below
}
```

```swift
var items: [CommandBarItem] = [
    copyPathItem(id: "wt-\(worktreeId.uuidString)", path: worktree.path, group: "Open", groupPriority: 0),
    revealInFinderItem(id: "wt-\(worktreeId.uuidString)", path: worktree.path, group: "Open", groupPriority: 0),
    CommandBarItem(
        id: "wt-new-tab-\(worktreeId.uuidString)",
        title: "New pane in new tab",
        icon: .system(.plusRectangle),
        shortcutTrigger: newTabShortcut,
        group: "Open",
        groupPriority: 0,
        action: .dispatchTargeted(.openNewTerminalInTab, target: worktreeId, targetType: .worktree),
        command: .openNewTerminalInTab
    ),
]
```

Do not add `worktreePath` to `WorktreePresence`. `buildWorktreeActionsLevel(...)` receives the selected `Worktree` in this task, and keeping path off presence avoids updating unrelated test factories.

- [ ] **Step 7: Run action-level tests**

Run:

```bash
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_repoLevelShowsOpenCommandsBeforeWorktrees"
mise run test -- --filter "CommandBarUnifiedWorktreeDataSourceTests/test_worktreeLevelUsesSingleOpenGroupForPathAndPaneActions"
mise run test -- --filter "WorktreePresenceTests"
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift \
  Sources/AgentStudio/Infrastructure/PathActions.swift \
  Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift \
  Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift \
  Tests/AgentStudioTests/Helpers/CommandBarFactories.swift
git commit -m "feat: add repo and worktree command bar action levels"
```

---

### Task 3: Refresh Pane Repo/Worktree Identity When Cwd Changes

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorCWDIdentityTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift`

- [ ] **Step 1: Write failing atom/store live identity tests**

Add these tests to `WorkspaceStoreTests`. They pin the data model before touching `PaneCoordinator`.

```swift
@Test
func updatePaneLiveLocation_resolvesKnownWorktreeAndPreservesLaunchSource() {
    let store = WorkspaceStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/live-identity-repo"))
    let main = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/live-identity-repo"),
        isMainWorktree: true
    )
    let feature = Worktree(
        repoId: repo.id,
        name: "feature",
        path: URL(filePath: "/tmp/live-identity-repo-feature")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])

    let pane = store.createPane(
        source: .worktree(worktreeId: main.id, repoId: repo.id, launchDirectory: main.path),
        title: "Terminal"
    )

    let cwd = feature.path.appending(path: "Sources")
    store.paneAtom.updatePaneCWDAndResolvedContext(
        pane.id,
        cwd: cwd,
        resolvedContext: store.repositoryTopologyAtom.repoAndWorktree(containing: cwd)
    )

    let updated = store.pane(pane.id)
    #expect(updated?.metadata.cwd == cwd)
    #expect(updated?.repoId == repo.id)
    #expect(updated?.worktreeId == feature.id)
    #expect(updated?.metadata.repoName == repo.name)
    #expect(updated?.metadata.worktreeName == "feature")

    guard case .worktree(let launchWorktreeId, let launchRepoId, let launchDirectory) = updated?.metadata.source else {
        Issue.record("Expected launch source to remain worktree provenance")
        return
    }
    #expect(launchWorktreeId == main.id)
    #expect(launchRepoId == repo.id)
    #expect(launchDirectory == main.path)
}

@Test
func updatePaneLiveLocation_clearsLiveRepoAndWorktreeWhenCwdLeavesKnownWorktrees() {
    let store = WorkspaceStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/live-clear-repo"))
    let main = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/live-clear-repo"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main])
    let pane = store.createPane(
        source: .worktree(worktreeId: main.id, repoId: repo.id, launchDirectory: main.path),
        title: "Terminal"
    )

    let externalCwd = URL(filePath: "/tmp/outside-known-worktrees")
    store.paneAtom.updatePaneCWDAndResolvedContext(
        pane.id,
        cwd: externalCwd,
        resolvedContext: store.repositoryTopologyAtom.repoAndWorktree(containing: externalCwd)
    )

    let updated = store.pane(pane.id)
    #expect(updated?.metadata.cwd == externalCwd)
    #expect(updated?.repoId == nil)
    #expect(updated?.worktreeId == nil)
    #expect(updated?.metadata.repoName == nil)
    #expect(updated?.metadata.worktreeName == nil)

    guard case .worktree(let launchWorktreeId, let launchRepoId, let launchDirectory) = updated?.metadata.source else {
        Issue.record("Expected launch source to remain worktree provenance")
        return
    }
    #expect(launchWorktreeId == main.id)
    #expect(launchRepoId == repo.id)
    #expect(launchDirectory == main.path)
}

@Test
func updatePaneLiveLocation_preservesFloatingSourceWhileLiveFacetsFollowKnownCwd() {
    let store = WorkspaceStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/live-floating-repo"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "floating-target",
        path: URL(filePath: "/tmp/live-floating-repo/floating-target")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .floating(launchDirectory: URL(filePath: "/tmp/scratch"), title: "scratch"),
        title: "Scratch Terminal"
    )

    let changed = store.paneAtom.updatePaneCWDAndResolvedContext(
        pane.id,
        cwd: worktree.path,
        resolvedContext: store.repositoryTopologyAtom.repoAndWorktree(containing: worktree.path)
    )

    let updated = store.pane(pane.id)
    #expect(changed == true)
    #expect(updated?.repoId == repo.id)
    #expect(updated?.worktreeId == worktree.id)
    guard case .floating(let launchDirectory, let title) = updated?.metadata.source else {
        Issue.record("Expected launch source to remain floating provenance")
        return
    }
    #expect(launchDirectory == URL(filePath: "/tmp/scratch"))
    #expect(title == "scratch")
}

@Test
func updatePaneLiveLocation_isIdempotentWhenCwdAndResolvedContextAreUnchanged() {
    let store = WorkspaceStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/live-idempotent-repo"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/live-idempotent-repo"),
        isMainWorktree: true
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Terminal"
    )
    let resolvedContext = store.repositoryTopologyAtom.repoAndWorktree(containing: worktree.path)

    let first = store.paneAtom.updatePaneCWDAndResolvedContext(
        pane.id,
        cwd: worktree.path,
        resolvedContext: resolvedContext
    )
    let second = store.paneAtom.updatePaneCWDAndResolvedContext(
        pane.id,
        cwd: worktree.path,
        resolvedContext: resolvedContext
    )

    #expect(first == true)
    #expect(second == false)
}
```

- [ ] **Step 2: Run atom/store tests to verify they fail**

Run:

```bash
mise run test -- --filter "WorkspaceStoreTests/updatePaneLiveLocation_"
```

Expected: FAIL because `updatePaneCWDAndResolvedContext` does not exist yet.

- [ ] **Step 3: Add atomic pane live location update method**

In `WorkspacePaneAtom.swift`, add:

```swift
func updatePaneCWDAndResolvedContext(
    _ paneId: UUID,
    cwd: URL?,
    resolvedContext: (repo: Repo, worktree: Worktree)?
) -> Bool {
    guard panes[paneId] != nil else {
        workspacePaneLogger.warning("updatePaneCWDAndResolvedContext: pane \(paneId) not found")
        return false
    }

    var facets = panes[paneId]!.metadata.facets
    facets.cwd = cwd

    if let resolvedContext {
        facets.repoId = resolvedContext.repo.id
        facets.repoName = resolvedContext.repo.name
        facets.worktreeId = resolvedContext.worktree.id
        facets.worktreeName = resolvedContext.worktree.name
    } else {
        facets.repoId = nil
        facets.repoName = nil
        facets.worktreeId = nil
        facets.worktreeName = nil
    }

    guard facets != panes[paneId]!.metadata.facets else {
        return false
    }

    panes[paneId]!.metadata.updateFacets(facets)
    return true
}
```

Do not put topology lookup in `WorkspacePaneAtom`; keep the atom a state owner, not a resolver. Do not add `startingRepoId`, `startingWorktreeId`, or any other original-identity field. `PaneMetadata.source` is already the fixed launch provenance.

- [ ] **Step 4: Run atom/store tests**

Run:

```bash
mise run test -- --filter "WorkspaceStoreTests/updatePaneLiveLocation_"
```

Expected: PASS.

- [ ] **Step 5: Write failing runtime cwd identity test**

Add a test near the existing runtime dispatch coverage in `PaneCoordinatorRuntimeDispatchTests`. Use the existing `makeTestPaneCoordinator(...)`, `makeTestPaneRuntimeEventBus()`, and `runtimeEnvelope(paneId:event:seq:)` helpers in that file. Do not call `PaneCoordinator.handleRuntimeEnvelope(...)` directly; it is private. Post the runtime fact through the bus, because that is the production ingress.

```swift
@Test
func runtimeCwdChangedUpdatesPaneWorktreeIdentity() async {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-runtime-cwd-identity-\(UUID().uuidString)")
    let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
    store.restore()
    let paneEventBus = makeTestPaneRuntimeEventBus()
    let coordinator = makeTestPaneCoordinator(
        store: store,
        viewRegistry: ViewRegistry(),
        runtime: SessionRuntime(store: store),
        surfaceManager: MockPaneCoordinatorSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        paneEventBus: paneEventBus
    )
    _ = coordinator

    let repo = store.addRepo(at: URL(filePath: "/tmp/cwd-identity-repo"))
    let main = Worktree(
        repoId: repo.id,
        name: "main",
        path: URL(filePath: "/tmp/cwd-identity-repo"),
        isMainWorktree: true
    )
    let feature = Worktree(
        repoId: repo.id,
        name: "feature",
        path: URL(filePath: "/tmp/cwd-identity-repo-feature")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])

    let pane = store.createPane(
        source: .worktree(worktreeId: main.id, repoId: repo.id, launchDirectory: main.path),
        title: "Terminal"
    )
    store.appendTab(Tab(paneId: pane.id))

    let source = PaneId(uuid: pane.id)
    await waitForRuntimeBusSubscriber(paneEventBus)
    _ = await paneEventBus.post(
        runtimeEnvelope(
            paneId: source,
            event: .terminal(.cwdChanged(feature.path.appending(path: "Sources").path))
        )
    )

    await eventually("runtime cwd should refresh pane identity") {
        store.pane(pane.id)?.worktreeId == feature.id
    }

    let updated = store.pane(pane.id)
    #expect(updated?.metadata.cwd == feature.path.appending(path: "Sources"))
    #expect(updated?.repoId == repo.id)
    #expect(updated?.worktreeId == feature.id)
    #expect(updated?.metadata.worktreeName == "feature")

    guard case .worktree(let launchWorktreeId, _, let launchDirectory) = updated?.metadata.source else {
        Issue.record("Expected launch source to remain unchanged")
        return
    }
    #expect(launchWorktreeId == main.id)
    #expect(launchDirectory == main.path)

    try? FileManager.default.removeItem(at: tempDir)
}

private func waitForRuntimeBusSubscriber(_ paneEventBus: EventBus<RuntimeEnvelope>) async {
    for _ in 0..<200 {
        if await paneEventBus.subscriberCount >= 1 {
            return
        }
        await Task.yield()
    }
    #expect(await paneEventBus.subscriberCount >= 1, "coordinator did not subscribe to runtime bus")
}
```

- [ ] **Step 6: Run runtime identity test to verify failure**

Run:

```bash
mise run test -- --filter "PaneCoordinatorRuntimeDispatchTests/runtimeCwdChangedUpdatesPaneWorktreeIdentity"
```

Expected: FAIL because cwd changes do not update pane worktree identity.

- [ ] **Step 7: Add coordinator helper**

In `PaneCoordinator.swift`, add:

```swift
private func updatePaneCWDAndResolvedContext(paneId: UUID, cwd: URL?) {
    let resolvedContext = store.repositoryTopologyAtom.repoAndWorktree(containing: cwd)
    let didChange = store.paneAtom.updatePaneCWDAndResolvedContext(
        paneId,
        cwd: cwd,
        resolvedContext: resolvedContext
    )
    guard didChange else { return }
    if let cwd {
        paneFilesystemProjectionStore.updatePaneCwd(paneId: paneId, newCwd: cwd)
    }
}
```

Update `onSurfaceCWDChanged(...)`:

```swift
private func onSurfaceCWDChanged(_ event: SurfaceManager.SurfaceCWDChangeEvent) {
    guard let paneId = event.paneId else { return }
    updatePaneCWDAndResolvedContext(paneId: paneId, cwd: event.cwd)
}
```

Update the runtime `.cwdChanged` branch:

```swift
case .cwdChanged(let cwdPath):
    updatePaneCWDAndResolvedContext(
        paneId: sourcePaneUUID,
        cwd: URL(fileURLWithPath: cwdPath)
    )
```

- [ ] **Step 8: Run runtime identity test**

Run:

```bash
mise run test -- --filter "PaneCoordinatorRuntimeDispatchTests/runtimeCwdChangedUpdatesPaneWorktreeIdentity"
```

Expected: PASS.

- [ ] **Step 9: Add surface cwd stream identity test**

Create `Tests/AgentStudioTests/App/PaneCoordinatorCWDIdentityTests.swift` for surface-stream cwd coverage. Give the fake surface manager a retained continuation so the test can yield a real `SurfaceManager.SurfaceCWDChangeEvent`.

```swift
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorCWDIdentityTests {
    @Test
    func surfaceCwdChangedUpdatesPaneWorktreeIdentity() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-surface-cwd-identity-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let surfaceManager = CWDIdentitySurfaceManager()
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        _ = coordinator

        let repo = store.addRepo(at: URL(filePath: "/tmp/surface-cwd-identity-repo"))
        let main = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/surface-cwd-identity-repo"),
            isMainWorktree: true
        )
        let feature = Worktree(
            repoId: repo.id,
            name: "surface-feature",
            path: URL(filePath: "/tmp/surface-cwd-identity-repo-feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])
        let pane = store.createPane(
            source: .worktree(worktreeId: main.id, repoId: repo.id, launchDirectory: main.path),
            title: "Terminal"
        )
        store.appendTab(Tab(paneId: pane.id))

        surfaceManager.sendCWDChange(
            surfaceId: UUID(),
            paneId: pane.id,
            cwd: feature.path.appending(path: "Sources")
        )

        await eventually("surface cwd should refresh pane identity") {
            store.pane(pane.id)?.worktreeId == feature.id
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.cwd == feature.path.appending(path: "Sources"))
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == feature.id)
        #expect(updated?.metadata.worktreeName == "surface-feature")

        try? FileManager.default.removeItem(at: tempDir)
    }
}

@MainActor
private final class CWDIdentitySurfaceManager: PaneCoordinatorSurfaceManaging {
    private let continuation: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>.Continuation
    let surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        let stream = AsyncStream.makeStream(of: SurfaceManager.SurfaceCWDChangeEvent.self)
        self.surfaceCWDChanges = stream.stream
        self.continuation = stream.continuation
    }

    func sendCWDChange(surfaceId: UUID, paneId: UUID?, cwd: URL?) {
        continuation.yield(
            SurfaceManager.SurfaceCWDChangeEvent(surfaceId: surfaceId, paneId: paneId, cwd: cwd)
        )
    }

    func syncFocus(activeSurfaceId: UUID?) {}
    func createSurface(config: Ghostty.SurfaceConfiguration, metadata: SurfaceMetadata) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? { nil }
    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}
    func undoClose() -> ManagedSurface? { nil }
    func requeueUndo(_ surfaceId: UUID) {}
    func destroy(_ surfaceId: UUID) {}
}
```

Expected assertion body:

```swift
let updated = store.pane(pane.id)
#expect(updated?.metadata.cwd == feature.path)
#expect(updated?.repoId == repo.id)
#expect(updated?.worktreeId == feature.id)
#expect(updated?.metadata.worktreeName == "feature")
```

- [ ] **Step 10: Run focused coordinator cwd tests**

Run:

```bash
mise run test -- --filter "cwd"
```

Expected: PASS for all cwd-related tests.

- [ ] **Step 11: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "fix: refresh pane worktree identity on cwd changes"
```

---

### Task 4: Make `$` Search Match Repo, Worktree, Tab, Pane, And Cwd Context

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

- [ ] **Step 1: Write failing `$` search metadata tests**

Add tests to `CommandBarDataSourceTests`.

```swift
@Test
func test_panesScope_tabKeywordsIncludeRepoAndWorktreeContextFromPanes() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/search-agent-studio"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "pane-shortcuts",
        path: URL(filePath: "/tmp/search-agent-studio.pane-shortcuts")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Shell",
        facets: PaneContextFacets(
            repoId: repo.id,
            repoName: repo.name,
            worktreeId: worktree.id,
            worktreeName: worktree.name,
            cwd: worktree.path
        )
    )
    let tab = Tab(paneId: pane.id, name: "Review Tab")
    store.appendTab(tab)

    let items = CommandBarDataSource.items(
        scope: .panes,
        store: store,
        repoCache: RepoCacheAtom(),
        dispatcher: dispatcher
    )
    let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

    #expect(tabItem?.keywords.contains("search-agent-studio") == true)
    #expect(tabItem?.keywords.contains("pane-shortcuts") == true)
    #expect(tabItem?.keywords.contains("Review Tab") == true)
}

@Test
func test_panesScopeSearchFiltersPaneByRepoNameAndTabName() {
    let store = makeStore()
    let repo = store.addRepo(at: URL(filePath: "/tmp/filter-repo-name"))
    let worktree = Worktree(
        repoId: repo.id,
        name: "filter-worktree",
        path: URL(filePath: "/tmp/filter-repo-name/filter-worktree")
    )
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    let pane = store.createPane(
        source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
        title: "Pane Shell",
        facets: PaneContextFacets(
            repoId: repo.id,
            repoName: repo.name,
            worktreeId: worktree.id,
            worktreeName: worktree.name,
            cwd: worktree.path
        )
    )
    store.appendTab(Tab(paneId: pane.id, name: "Operations"))

    let items = CommandBarDataSource.items(
        scope: .panes,
        store: store,
        repoCache: RepoCacheAtom(),
        dispatcher: dispatcher
    )

    #expect(CommandBarSearch.filter(items: items, query: "filter-repo-name").contains { $0.id == "pane-\(pane.id.uuidString)" })
    #expect(CommandBarSearch.filter(items: items, query: "Operations").contains { $0.id == "pane-\(pane.id.uuidString)" })
}
```

- [ ] **Step 2: Run `$` metadata tests to verify failure**

Run:

```bash
mise run test -- --filter "CommandBarDataSourceTests/test_panesScope_tabKeywordsIncludeRepoAndWorktreeContextFromPanes"
mise run test -- --filter "CommandBarDataSourceTests/test_panesScopeSearchFiltersPaneByRepoNameAndTabName"
```

Expected: FAIL because tab keywords do not include pane repo/worktree metadata, and pane keywords do not include tab names.

- [ ] **Step 3: Add tab keyword helper**

In `CommandBarDataSource.swift`, add stable keyword dedupe plus tab keywords. Do not round-trip through an unordered `Set`; search scoring can depend on keyword order, and Set iteration order is nondeterministic.

```swift
private static func stableUniqueKeywords(_ keywords: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []

    for keyword in keywords {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let key = trimmed.localizedLowercase
        if seen.insert(key).inserted {
            result.append(trimmed)
        }
    }

    return result
}

private static func keywordsForTab(
    _ tab: Tab,
    store: WorkspaceStore,
    repoCache: RepoCacheAtom
) -> [String] {
    var keywords = ["tab", "switch", tab.name]
    keywords.append(contentsOf: tab.arrangements.filter { !$0.isDefault }.map(\.name))

    for paneId in tab.activePaneIds {
        guard let pane = store.paneAtom.pane(paneId) else { continue }
        keywords.append(contentsOf: keywordsForPane(pane, store: store, repoCache: repoCache))
        keywords.append(pane.title)
    }

    return stableUniqueKeywords(keywords)
}
```

- [ ] **Step 4: Use tab keywords and include tab title in pane keywords**

In `tabItems(...)` and `paneAndTabItems(...)`, replace hand-built tab keyword arrays with:

```swift
keywords: keywordsForTab(tab, store: store, repoCache: repoCache),
```

In the `paneAndTabItems(...)` pane item builder, after `let tabTitle = ...`, pass tab title into pane keywords by adding a local helper call:

```swift
var paneKeywords = keywordsForPane(pane, store: store, repoCache: repoCache)
paneKeywords.append(tabTitle)
```

Then use:

```swift
keywords: stableUniqueKeywords(paneKeywords),
```

- [ ] **Step 5: Run `$` metadata tests**

Run:

```bash
mise run test -- --filter "CommandBarDataSourceTests/test_panesScope_tabKeywordsIncludeRepoAndWorktreeContextFromPanes"
mise run test -- --filter "CommandBarDataSourceTests/test_panesScopeSearchFiltersPaneByRepoNameAndTabName"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift
git commit -m "feat: enrich pane selector search metadata"
```

---

### Task 5: Add Main Pane Notes

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Create: `Sources/AgentStudio/App/Panes/PaneNote/PaneNotePresentation.swift`
- Test: `Tests/AgentStudioTests/Core/RuntimeEventSystem/Contracts/PaneMetadataTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneDisplayDerivedTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerPaneNoteTests.swift`

- [ ] **Step 1: Write failing `PaneMetadata` note tests**

Create `Tests/AgentStudioTests/Core/RuntimeEventSystem/Contracts/PaneMetadataTests.swift`.

```swift
import Foundation
import Testing
@testable import AgentStudio

@Suite
struct PaneMetadataTests {
    @Test("pane note trims whitespace and stores nil for blank notes")
    func paneNoteNormalizesBlankValues() {
        var metadata = PaneMetadata(
            source: .floating(launchDirectory: nil, title: "scratch"),
            title: "Terminal"
        )

        metadata.updateNote("  Debug checkout  ")
        #expect(metadata.note == "Debug checkout")

        metadata.updateNote("   ")
        #expect(metadata.note == nil)
    }

    @Test("pane metadata decodes persisted values without a note")
    func paneMetadataDecodesWithoutNote() throws {
        let json = """
        {
          "paneId": "00000000-0000-0000-0000-000000000001",
          "contentType": "terminal",
          "source": { "floating": { "launchDirectory": null, "title": "scratch" } },
          "executionBackend": "local",
          "createdAt": "2026-05-26T00:00:00Z",
          "title": "Terminal",
          "facets": {}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let metadata = try decoder.decode(PaneMetadata.self, from: Data(json.utf8))

        #expect(metadata.note == nil)
    }
}
```

- [ ] **Step 2: Run note metadata tests to verify they fail**

Run:

```bash
mise run test -- --filter "PaneMetadataTests"
```

Expected: FAIL because `PaneMetadata.note` and `updateNote(_:)` do not exist.

- [ ] **Step 3: Add `PaneMetadata.note`**

In `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`, add `note` as a live field, include it in initialization, canonicalization, coding, and mutation:

```swift
// Live fields
private(set) var title: String
private(set) var facets: PaneContextFacets
private(set) var checkoutRef: String?
private(set) var note: String?
```

```swift
init(
    paneId: PaneId = PaneId(),
    contentType: PaneContentType = .terminal,
    source: PaneMetadataSource,
    executionBackend: ExecutionBackend = .local,
    createdAt: Date = Date(),
    title: String = "Terminal",
    facets: PaneContextFacets = .empty,
    checkoutRef: String? = nil,
    note: String? = nil
) {
    self.paneId = paneId
    self.contentType = contentType
    self.source = source
    self.executionBackend = executionBackend
    self.createdAt = createdAt
    self.title = title
    let sourceFacets = PaneContextFacets(
        repoId: source.repoId,
        worktreeId: source.worktreeId,
        cwd: source.launchDirectory
    )
    self.facets = facets.fillingNilFields(from: sourceFacets)
    self.checkoutRef = checkoutRef
    self.note = Self.normalizedNote(note)
}
```

```swift
mutating func updateNote(_ newNote: String?) {
    note = Self.normalizedNote(newNote)
}

private static func normalizedNote(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
```

In `canonicalizedIdentity(...)`, pass `note: note`.

Add `.note` to `CodingKeys` and decode it with:

```swift
self.note = Self.normalizedNote(try container.decodeIfPresent(String.self, forKey: .note))
```

- [ ] **Step 4: Run metadata tests**

Run:

```bash
mise run test -- --filter "PaneMetadataTests"
```

Expected: PASS.

- [ ] **Step 5: Write failing atom mutation test**

In the existing workspace pane atom/store test file, add:

```swift
@Test("workspace pane atom updates pane note")
@MainActor
func workspacePaneAtomUpdatesPaneNote() {
    let atom = WorkspacePaneAtom()
    let pane = Pane(
        id: UUID(),
        content: .terminal,
        metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "scratch"))
    )
    #expect(atom.insertRestoredPane(pane))

    atom.updatePaneNote(pane.id, note: "  Restart backend after deploy  ")

    #expect(atom.pane(pane.id)?.metadata.note == "Restart backend after deploy")
}
```

- [ ] **Step 6: Add `WorkspacePaneAtom.updatePaneNote`**

In `WorkspacePaneAtom`, add a title-style mutation:

```swift
func updatePaneNote(_ paneId: UUID, note: String?) {
    guard panes[paneId] != nil else {
        workspacePaneLogger.warning("updatePaneNote: pane \(paneId) not found")
        return
    }
    panes[paneId]!.metadata.updateNote(note)
}
```

- [ ] **Step 7: Write failing display/search tests**

Add these cases to `PaneDisplayDerivedTests` or create the file if it does not exist:

```swift
@Test("pane note appears first in collapsed label parts")
@MainActor
func paneNoteAppearsFirstInCollapsedLabelParts() {
    withTestAtomRegistry { atoms in
        let paneId = UUID()
        var metadata = PaneMetadata(
            source: .floating(launchDirectory: URL(fileURLWithPath: "/tmp/project-dev/agent-studio"), title: nil),
            title: "Terminal"
        )
        metadata.updateNote("release smoke")
        #expect(atoms.workspacePane.insertRestoredPane(Pane(id: paneId, content: .terminal, metadata: metadata)))

        let parts = PaneDisplayDerived().collapsedBarLabelParts(for: paneId)

        #expect(parts.first?.text == "release smoke")
        #expect(parts.first?.icon == .system("note.text"))
        #expect(parts.first?.weight == .semibold)
    }
}

@Test("pane note participates in pane keywords")
@MainActor
func paneNoteParticipatesInPaneKeywords() {
    var metadata = PaneMetadata(source: .floating(launchDirectory: nil, title: nil), title: "Terminal")
    metadata.updateNote("gondolin auth logs")
    let pane = Pane(id: UUID(), content: .terminal, metadata: metadata)

    let keywords = PaneDisplayDerived().paneKeywords(for: pane)

    #expect(keywords.contains("gondolin auth logs"))
}
```

- [ ] **Step 8: Add note to display parts and collapsed labels**

Update `PaneDisplayParts`:

```swift
struct PaneDisplayParts: Equatable {
    let primaryLabel: String
    let note: String?
    let repoName: String?
    let branchName: String?
    let worktreeFolderName: String?
    let cwdFolderName: String?
}
```

Populate `note: pane.metadata.note` in every `PaneDisplayParts(...)` initializer. Update `paneKeywords(for:)` to include `parts.note` before generated identity:

```swift
return [parts.note, parts.primaryLabel, parts.repoName, parts.branchName, parts.worktreeFolderName, parts.cwdFolderName]
    .compactMap { $0 }
    .filter { !$0.isEmpty }
```

In `collapsedBarLabelParts(for:)`, prepend note when present:

```swift
let notePart = parts.note.map {
    CollapsedBarLabelPart(icon: .system("note.text"), text: $0, weight: .semibold)
}
```

Return `[notePart] + generatedParts` when the note exists; otherwise return the existing generated parts.

- [ ] **Step 9: Write failing `$` command-bar note search test**

In `CommandBarDataSourceTests`, add a test that creates a main pane with `metadata.note = "zmx lease repro"` and asserts `$` scope can find it:

```swift
@Test("$ pane scope searches pane notes")
@MainActor
func paneScopeSearchesPaneNotes() {
    withTestAtomRegistry { atoms in
        let paneId = UUID()
        var metadata = PaneMetadata(source: .floating(launchDirectory: nil, title: nil), title: "Terminal")
        metadata.updateNote("zmx lease repro")
        let pane = Pane(id: paneId, content: .terminal, metadata: metadata)
        #expect(atoms.workspacePane.insertRestoredPane(pane))
        atoms.workspaceTabShell.replaceTabs([Tab(paneId: paneId)], activeTabId: nil)

        let items = CommandBarDataSource.items(
            for: .panes,
            store: WorkspaceStore.fromAtomsForTesting(atoms)
        )

        #expect(items.contains { item in
            item.id == "pane-\(paneId.uuidString)" && item.keywords.contains("zmx lease repro")
        })
    }
}
```

- [ ] **Step 10: Add note to command-bar pane keywords**

In `CommandBarDataSource.keywordsForPane(...)`, append `parts.note` before generated identity fields:

```swift
if let note = parts.note {
    keywords.append(note)
}
```

- [ ] **Step 11: Write failing active-main-pane edit command tests**

Create `Tests/AgentStudioTests/App/PaneTabViewControllerPaneNoteTests.swift` with controller-level coverage using the existing pane controller harness. First extend `PaneTabViewControllerCommandLaunchRecorder` in `PaneTabViewControllerCommandTestSupport.swift`:

```swift
var editPaneNoteRequests: [UUID] = []
var copiedPanePaths: [String] = []
```

Thread a `PaneNotePresentation` through `makeHarness(...)`:

```swift
paneNotePresentation: PaneNotePresentation(
    present: { paneId in
        launchRecorder.editPaneNoteRequests.append(paneId)
    },
    editorContent: { _, _ in AnyView(EmptyView()) }
)
```

Then add the tests:

```swift
import Testing
@testable import AgentStudio

@Suite
@MainActor
struct PaneTabViewControllerPaneNoteTests {
    @Test("edit pane note command is available for active main pane")
    func editPaneNoteCommandIsAvailableForActiveMainPane() {
        let harness = makeHarness()
        let activePaneId = harness.store.tabLayoutAtom.activeTab?.activePaneId

        harness.controller.handleAppCommand(.editPaneNote)

        #expect(harness.launchRecorder.editPaneNoteRequests == activePaneId.map { [$0] } ?? [])
    }

    @Test("copy current pane path copies active main pane cwd")
    func copyCurrentPanePathCopiesActiveMainPaneCwd() throws {
        let harness = makeHarness()
        let activePaneId = try #require(harness.store.tabLayoutAtom.activeTab?.activePaneId)
        let cwd = URL(filePath: "/tmp/copy-current-pane-path/live")
        harness.store.paneAtom.updatePaneCWD(activePaneId, cwd: cwd)

        harness.controller.handleAppCommand(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPanePaths == [cwd.path])
    }

    @Test("copy current pane path falls back to launch directory")
    func copyCurrentPanePathFallsBackToLaunchDirectory() throws {
        let harness = makeHarnessWithSingleFloatingPane(
            launchDirectory: URL(filePath: "/tmp/copy-current-pane-path/launch")
        )

        harness.controller.handleAppCommand(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPanePaths == ["/tmp/copy-current-pane-path/launch"])
    }

    @Test("edit pane note command does not target drawer child panes")
    func editPaneNoteCommandDoesNotTargetDrawerChildPanes() throws {
        let harness = makeHarness()
        let parentPaneId = try #require(harness.store.tabLayoutAtom.activeTab?.activePaneId)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPaneId))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPaneId)

        harness.controller.handleAppCommand(.editPaneNote)

        #expect(harness.launchRecorder.editPaneNoteRequests.isEmpty)
    }

    @Test("copy current pane path does not target drawer child panes")
    func copyCurrentPanePathDoesNotTargetDrawerChildPanes() throws {
        let harness = makeHarness()
        let parentPaneId = try #require(harness.store.tabLayoutAtom.activeTab?.activePaneId)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPaneId))
        harness.store.paneAtom.updatePaneCWD(drawerPane.id, cwd: URL(filePath: "/tmp/drawer-path"))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPaneId)

        harness.controller.handleAppCommand(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPanePaths.isEmpty)
    }
}
```

If the existing harness does not already expose a pasteboard seam, add a narrow `copyPath` closure to the controller test support and production initializer. Production wiring calls `PathActions.copyPath(_:)`; tests record the copied string. Do not write tests against the real pasteboard.

- [ ] **Step 12: Add command identities, shortcuts, command-bar catalog entries, and action resolver classification**

In `AppCommand`, add:

```swift
case editPaneNote
case copyCurrentPanePath
```

In `AppCommand+Catalog`, add:

```swift
case .editPaneNote:
    return CommandSpec(
        command: .editPaneNote,
        shortcut: .editPaneNote,
        label: "Edit Pane Note",
        description: "Set a note for the current pane",
        group: .pane,
        icon: .system(.pencil)
    )
case .copyCurrentPanePath:
    return CommandSpec(
        command: .copyCurrentPanePath,
        shortcut: .copyCurrentPanePath,
        label: "Copy Current Pane Path",
        description: "Copy the current pane's cwd or launch directory",
        group: .pane,
        icon: LocalActionSpec.copyPath.actionSpec.icon
    )
```

In `AppShortcut`, add:

```swift
case editPaneNote
case copyCurrentPanePath
```

Classify both shortcuts as global and terminal-app-owned so Agent Studio swallows them before Ghostty can see the chords:

```swift
case .editPaneNote:
    return .init(
        trigger: .init(key: .character(.n), modifiers: [.command, .option, .shift]),
        contexts: [.global, .terminalAppOwned]
    )
case .copyCurrentPanePath:
    return .init(
        trigger: .init(key: .character(.o), modifiers: [.command, .option, .shift]),
        contexts: [.global, .terminalAppOwned]
    )
```

Map them back to commands:

```swift
case .editPaneNote:
    return .editPaneNote
case .copyCurrentPanePath:
    return .copyCurrentPanePath
```

Update all exhaustive shortcut policy switches. These are normal pane commands, not command-bar activation shortcuts. They should be blocked by transient surfaces by default unless a surface explicitly allows them.

In `ActionResolver.isNonPaneCommand(_:)`, put both commands in the `true` branch with the existing controller-local pane commands (`openPaneLocationInFinder`, `openPaneLocationInEditorMenu`). They are handled by `PaneTabViewController`, not converted into `PaneActionCommand`.

- [ ] **Step 13: Add note editor presentation seam**

Create `Sources/AgentStudio/App/Panes/PaneNote/PaneNotePresentation.swift`:

```swift
import SwiftUI

@MainActor
struct PaneNotePresentation {
    let present: (UUID) -> Void
    let editorContent: (_ paneId: UUID, _ submit: @escaping (String?) -> Void) -> AnyView

    static let disabled = PaneNotePresentation(
        present: { _ in },
        editorContent: { _, _ in AnyView(EmptyView()) }
    )
}
```

Add this stored property and initializer parameter to `PaneTabViewController`:

```swift
private let paneNotePresentation: PaneNotePresentation
```

```swift
paneNotePresentation: PaneNotePresentation = .disabled,
```

Assign it in the initializer.

- [ ] **Step 14: Implement main-pane-only note editor routing**

In `PaneTabViewController`, route `.editPaneNote` to the active main pane:

```swift
case .editPaneNote:
    guard let activeTab = workspaceTab.currentTab,
        let activePaneId = activeTab.activePaneId,
        activeTab.activePaneIds.contains(activePaneId)
    else {
        return
    }
    paneNotePresentation.present(activePaneId)
```

Also route `.copyCurrentPanePath` to the active main pane:

```swift
case .copyCurrentPanePath:
    guard let activePaneId = activeMainPaneId(),
        let pane = store.paneAtom.pane(activePaneId),
        let path = pane.metadata.cwd ?? pane.metadata.launchDirectory
    else {
        return
    }
    pathActions.copyPath(path)
```

Use the same `PathActions.copyPath(_:)` production helper used by the `#` command-bar rows, injected behind a tiny closure/seam for tests. Do not target active drawer child panes.

The presentation object can be a small AppKit/SwiftUI popover matching the existing rename transient pattern. It writes through:

```swift
store.paneAtom.updatePaneNote(paneId, note: submittedNote)
```

Register the editor as a transient keyboard surface so Escape dismisses it and app/global shortcuts are blocked unless the active-surface policy explicitly allows them.

- [ ] **Step 15: Run focused note tests**

Run:

```bash
mise run test -- --filter "PaneMetadataTests|PaneDisplayDerivedTests|CommandBarDataSourceTests|PaneTabViewControllerPaneNoteTests"
```

Expected: PASS.

- [ ] **Step 16: Commit**

```bash
git add Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift \
  Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift \
  Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift \
  Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift \
  Sources/AgentStudio/App/Commands/AppCommand.swift \
  Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift \
  Sources/AgentStudio/App/Commands/AppShortcut.swift \
  Sources/AgentStudio/Core/Actions/ActionResolver.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/App/Panes/PaneNote/PaneNotePresentation.swift \
  Tests/AgentStudioTests/Core/RuntimeEventSystem/Contracts/PaneMetadataTests.swift \
  Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneDisplayDerivedTests.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerPaneNoteTests.swift
git commit -m "feat: add searchable notes for main panes"
```

---

### Task 6: Document Scope Ownership, Pane Notes, And Live Identity

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/architecture/commands_and_shortcuts.md`
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/component_architecture.md`

No doc-grep architecture test for this task. The project architecture tests should pin code structure and forbidden dependencies, not exact prose. Verification is review of the updated authored docs plus full test/lint/build in Task 7.

- [ ] **Step 1: Update `AGENTS.md` command guidance**

In `AGENTS.md`, under the command specs and execution owners guidance, add this text:

```markdown
### Command Bar Scope Mantra

Use this model before changing command bar scopes, shortcut routing, or command-bar row behavior:

- `#` owns locations and opening.
- `$` owns existing pane navigation.
- `>` owns verbs.

`#` may show repo/worktree path actions and opening actions because it is the location navigator. `$` may search by repo, worktree, tab, pane, and cwd metadata, but it only selects existing panes/tabs. `>` owns app commands and should not become a project/location browser.

Pane live identity follows cwd. `PaneMetadata.source` is fixed launch provenance; `PaneMetadata.facets` is live context. Do not add `startingRepoId`, `startingWorktreeId`, or a parallel original-identity blob unless a concrete user-visible feature needs it.

Pane notes are user-authored labels. Store them in `PaneMetadata.note`, show them on minimized/collapsed main-pane chrome, and include them in `$` pane search. Notes do not replace repo/worktree/cwd identity; they sit above generated identity as the human label for what the pane is doing. `Edit Pane Note` uses `Cmd-Opt-Shift-N`.

`Copy Current Pane Path` uses `Cmd-Opt-Shift-O`. It belongs to `>` because it acts on the active existing pane, not on a selected repo/worktree row in `#`.
```

- [ ] **Step 2: Update `commands_and_shortcuts.md` command-bar section**

Add this section after the command bar execution-owner paragraph and before the navigation shortcut map.

````markdown
## Command Bar Scope Ownership

The command bar has three primary typed scopes:

```text
# owns locations and opening.

$ owns existing pane navigation.

> owns verbs.
```

`#` is an object/location navigator. Its root shows repos; repo rows drill into worktrees; worktree rows expose location actions and opening actions. Path actions such as Copy path and Reveal in Finder belong with opening actions under the same `Open` group because they act on the selected location.

`$` is a selector for already-open UI. It can filter by repo name, worktree name, cwd, tab title, and pane title because those are search metadata for existing panes/tabs. It must not grow repo/worktree management actions.

`>` is the command catalog. It owns verbs that dispatch through `AppCommand`/`CommandSpec` and the shared command pipeline.

Chevron rows are containers: Return drills in. Leaf rows execute: Return runs the row. `Cmd-Return` and `Opt-Return` are reserved for skip-ahead actions on container rows when meaningful, such as opening a selected worktree in a new tab or current tab without visiting the worktree action screen.

Pane notes are searchable in `$` because `$` owns existing pane navigation. They do not make `$` a command surface; editing a note remains a `>` command. `Edit Pane Note` uses `Cmd-Opt-Shift-N`.

`Copy Current Pane Path` is also a `>` command. It copies the active main pane's live cwd, falling back to launch directory when cwd is not known. It uses `Cmd-Opt-Shift-O`. This is separate from `#` Copy path rows, which act on selected repo/worktree locations.
````

- [ ] **Step 3: Update `workspace_data_architecture.md` identity semantics**

Add this subsection inside `Identity Semantics`, after the pane references paragraph.

````markdown
### Live Pane Location Identity

Pane live identity follows cwd. `PaneMetadata.source` records fixed launch provenance, while `PaneMetadata.facets` records live context for labels, grouping, command-bar search, and worktree presence.

When a terminal reports a cwd inside a known canonical worktree, `PaneCoordinator` resolves the cwd with `WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing:)` and updates the pane's live facets:

```text
cwdChanged
  ──► WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing: cwd)
  ──► WorkspacePaneAtom updates PaneMetadata.facets
        cwd
        repoId / repoName
        worktreeId / worktreeName
```

When cwd is outside all known worktrees, clear live repo/worktree facets so stale command-bar presence and `$` search metadata do not lie. `PaneMetadata.source` remains fixed launch provenance for restore and fallback; do not add separate `startingRepoId` or `startingWorktreeId` fields.

`PaneMetadata.note` stores user-authored pane notes. It is not cwd-derived and should not be cleared when cwd changes outside a known worktree.
````

- [ ] **Step 4: Update `component_architecture.md` PaneMetadata section**

In the `PaneMetadata` section, add this paragraph in the existing PaneMetadata discussion. If the section has shifted, anchor it near the existing `source` / `facets` description rather than inventing a new top-level section.

```markdown
`PaneMetadata.source` is fixed launch provenance. It says where the pane was born and remains stable for restore and fallback. `PaneMetadata.facets` is live context. `facets.cwd`, `facets.repoId`, `facets.worktreeId`, `facets.repoName`, and `facets.worktreeName` may change as the terminal cwd changes. Live command-bar behavior, pane labels, grouping, and worktree presence read facets, not a parallel starting-identity blob. Do not add `startingRepoId` or `startingWorktreeId`; the source/facets split already represents provenance vs current identity.

`PaneMetadata.note` is user-authored. It labels what the pane is for, appears on minimized/collapsed main-pane chrome, and participates in `$` search. It is intentionally separate from `source` and `facets`: source answers "where was this pane born?", facets answer "where is it now?", and note answers "what is this pane doing for the user?"
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md \
  docs/architecture/commands_and_shortcuts.md \
  docs/architecture/workspace_data_architecture.md \
  docs/architecture/component_architecture.md
git commit -m "docs: document command bar scope and live identity model"
```

---

### Task 7: Final Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run command-bar focused tests**

Run:

```bash
mise run test -- --filter "CommandBar"
```

Expected: PASS.

- [ ] **Step 2: Run cwd/runtime focused tests**

Run:

```bash
mise run test -- --filter "cwd|PaneCoordinatorRuntimeDispatch"
```

Expected: PASS.

- [ ] **Step 3: Run format**

Run:

```bash
mise run format
```

Expected: exit 0.

- [ ] **Step 4: Run lint**

Run:

```bash
mise run lint
```

Expected: exit 0, zero SwiftLint violations, boundary check passed.

- [ ] **Step 5: Run full tests**

Run:

```bash
mise run test
```

Expected: exit 0.

- [ ] **Step 6: Run launchable build**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-1" mise run build
```

Expected: exit 0 and `.build-agent-1/debug/AgentStudio` exists.

- [ ] **Step 7: Commit verification cleanup if formatting changed files**

```bash
git status --short
git add -u
git commit -m "chore: format command bar menu changes"
```

Only commit if `mise run format` changed tracked files.

---

## Self-Review

**Spec coverage:** Covered repo-only root, single-worktree drill-in, `Open` group unification for path and pane-opening actions, `$` search by repo/worktree/tab/pane metadata, Option A live identity following cwd, clearing stale live identity outside known worktrees, no new starting-identity blob, and documentation of the `#`/`$`/`>` mantra.

**Placeholder scan:** No placeholder wording remains. Stale harness references, doc-grep tests, and id-string discriminator instructions were removed or replaced with concrete code paths.

**Type consistency:** `WorktreePresence` stays path-free; `buildWorktreeActionsLevel(...)` receives the selected `Worktree` when it needs a path. `WorkspacePaneAtom.updatePaneCWDAndResolvedContext` takes already-resolved topology and keeps topology lookup in `PaneCoordinator`. `PaneMetadata.source` remains fixed launch provenance; `PaneMetadata.facets` remains the live identity surface.

**Known execution note:** The plan intentionally does not implement destructive repo actions such as remove repo in command bar. That remains outside scope.
