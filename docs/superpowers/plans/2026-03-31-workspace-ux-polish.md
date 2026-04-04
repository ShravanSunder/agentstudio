# Workspace UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the requested workspace UX fixes: two empty states, cache-backed recent worktree/CWD launcher actions, management-mode pane footer actions, drawer/footer layout fixes, sidebar alignment and tooltip polish, arrangement popover alignment, and release-version propagation into the macOS About panel.

**Architecture:** Keep structural state in `WorkspaceStore`, keep rebuildable activity metadata in `WorkspaceRepoCache`, and record “recent target opened” as an event-bus fact consumed by `WorkspaceCacheCoordinator` so cache ownership stays intact. Implement the new empty states and management footer as focused UI units instead of growing `PaneTabViewController` and `PaneLeafContainer` further, and centralize external-app launching plus bundle-version injection behind small helpers/scripts.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, `@Observable`, Agent Studio EventBus/WorkspaceCacheCoordinator, macOS help tags (`.help` / `toolTip`), GitHub Actions, `PlistBuddy`, `mise`

---

## Research Notes

### Current Issues And Why They Exist

1. **There is only one empty state today, so the app cannot distinguish “no folders yet” from “workspace exists but no pane is open.”**
   - The current welcome screen is hard-coded in `PaneTabEmptyStateViewFactory.make(...)`.
   - `PaneTabViewController.updateEmptyState()` toggles that one screen solely from `store.tabs.isEmpty`.
   - Result: the app shows the same welcome regardless of whether the workspace is brand new or already populated in the sidebar.

2. **There is no workspace-scoped recent target model for the second launcher screen yet.**
   - Existing “recents” in the repo are command-bar specific `UserDefaults` state, not worktree/CWD launch recency.
   - The workspace architecture docs define `workspace.cache.json` as the home for rebuildable, event-driven enrichment owned by `WorkspaceRepoCache`.
   - Result: the requested “latest 5 worktrees/CWDs” launcher cannot be built cleanly without adding cache-backed activity metadata.

3. **About shows stale version text because the release pipeline computes a version but never injects it into the bundled `Info.plist`.**
   - `AppDelegate` uses the standard macOS About panel via `NSApplication.orderFrontStandardAboutPanel`.
   - Both `.github/workflows/release.yml` and `.mise.toml` manually copy `Sources/AgentStudio/Resources/Info.plist` into the app bundle.
   - That plist is currently static and still contains `CFBundleShortVersionString = 0.0.1-alpha` and `CFBundleVersion = 0.0.1`.
   - Result: release artifacts can be named with a newer tag while About still reads old bundle metadata.

4. **Pane `cwd` and worktree root are not guaranteed to be the same in the current model.**
   - `PaneCoordinator` updates pane cwd from live terminal `cwdChanged` runtime events.
   - `WorkspaceStore.repoAndWorktree(containing:)` explicitly supports cwd values nested under a worktree root.
   - Floating panes may have a cwd with no worktree at all.
   - Result: Finder/Cursor actions must prefer live pane cwd and then fall back to worktree root, not assume one path model.

5. **Management-mode pane UI has no bottom identity/action strip yet.**
   - `PaneLeafContainer` already renders management-mode controls at the top and a drawer icon bar at the bottom.
   - There is no existing footer for pane identity or external-open actions.
   - Result: when rearranging panes, users do not get quick visual confirmation of “what this pane is” or one-click Finder/Cursor actions.

6. **Terminal content can visually disappear under bottom chrome because the pane body is not reserving space for that chrome.**
   - `PaneLeafContainer` layers bottom drawer UI as an overlay instead of carving out content space.
   - `PaneTabViewController` also pins the terminal container flush to the bottom of its content area.
   - Result: bottom rows of terminal content can be hidden behind the drawer/footer region, as seen in the reported screenshot.

7. **Sidebar child worktree rows are visually misaligned with the repo row grid.**
   - `RepoSidebarContentView` uses a different child-row inset and icon-column layout for `SidebarWorktreeRow` than the repo header row.
   - Result: worktree rows look slightly shifted relative to the parent repo icon/title column.

8. **Tooltip coverage is inconsistent.**
   - Some controls already use SwiftUI `.help(...)` or AppKit `toolTip`, but many management and toolbar affordances still lack hover help or use older copy.
   - Apple’s macOS guidance treats help tags/tooltips as the standard hover affordance for controls.
   - Result: icon-only controls are harder to discover than they need to be.

9. **The arrangement popover currently uses the default centered arrow placement.**
   - `CustomTabBar` opens the arrangement UI with `.popover(isPresented: $showPanel, arrowEdge: .bottom)`.
   - Result: the popover arrow is centered on the control, which does not match the requested left-biased visual alignment.

### Why The Proposed Ownership Is Correct

- **Recent launcher metadata belongs in `WorkspaceRepoCache`, not `WorkspaceStore` or `WorkspaceUIStore`.**
  - It is workspace-scoped and useful to UI, but it is still derived activity metadata rather than structural truth or pure presentation preference.
  - The architecture docs define cache as rebuildable, event-driven, and coordinator-owned, which matches “recent target opened” facts.

- **The second launcher state should be native UI, not a bundled screenshot.**
  - Native UI keeps text editable, scales correctly, supports future hover states/tooltips, and avoids freezing a temporary screenshot aesthetic into the product.

- **Cursor opening should mirror VS Code behavior by using the CLI with `--reuse-window`.**
  - This is the least surprising implementation for “open in app, reuse existing context” and keeps the logic isolated in one helper.

---

## Locked Decisions

These decisions came from user clarification during planning. Treat them as requirements, not suggestions.

- **Zero-folder state:** native intake screen focused on `Add Folder...` / scanning for repos. Do not keep the current generic welcome as-is.
- **Second welcome state:** shown only when folders/worktrees exist in the workspace but no pane/tab is open yet.
- **Second welcome actions:** recent 5 worktrees/CWDs, open selected recent in a tab, open all recent in tabs, add folder to scan for repos.
- **Second welcome exclusions:** no Finder action on this launcher screen.
- **Management-mode footer:** this is a management-mode-only affordance, not a normal-mode pane footer and not a generic arrangement-mode feature.
- **Management-mode footer actions:** include `Open in Finder` and `Open in Cursor`.
- **Cursor assumption for this slice:** assume the `cursor` command is available locally. Availability detection and disabled-state UX can be follow-up work.
- **Target resolution for Finder/Cursor:** use live pane `cwd` when present, otherwise fall back to worktree root.
- **Sidebar alignment bug:** child worktree rows should align visually with the repo icon/title grid, not sit on a shifted secondary column.

## Reference Basis

### Local Code References

- Empty-state implementation:
  - `Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift`
  - `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Management-mode and pane chrome:
  - `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
  - `Sources/AgentStudio/App/ManagementModeMonitor.swift`
  - `Sources/AgentStudio/Infrastructure/AppStyle.swift`
- Sidebar row layout:
  - `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Cache ownership and persistence:
  - `Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift`
  - `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
  - `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Runtime cwd semantics:
  - `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`
  - `Sources/AgentStudio/App/PaneCoordinator.swift`
  - `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Arrangement popover:
  - `Sources/AgentStudio/Core/Views/CustomTabBar.swift`
- About/version packaging:
  - `Sources/AgentStudio/App/AppDelegate.swift`
  - `Sources/AgentStudio/Resources/Info.plist`
  - `.github/workflows/release.yml`
  - `.mise.toml`

### External References

- Apple SwiftUI help tags / tooltips:
  - https://developer.apple.com/documentation/swiftui/view/help(_:)
- Apple SwiftUI popover attachment anchor:
  - https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)
- Apple AppKit `NSPopover` positioning fallback:
  - https://developer.apple.com/documentation/appkit/nspopover/show(relativeto:of:preferrededge:)
- Apple bundle version keys:
  - https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
  - https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion
- GitHub Actions ref/tag variables:
  - https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
  - https://docs.github.com/en/actions/reference/workflows-and-actions/variables
- Cursor CLI `--reuse-window`:
  - https://docs.cursor.com/tools/cli

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `Sources/AgentStudio/Core/Models/RecentWorkspaceTarget.swift` | Create | Cache model for recent worktree/CWD launcher entries |
| `Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift` | Modify | Own recent target state and recency mutation methods |
| `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift` | Modify | Persist recent target cache entries in `workspace.cache.json` |
| `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/WorkspaceActivityEvent.swift` | Create | New system fact type for “recent target opened” |
| `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift` | Modify | Add workspace-activity event namespace |
| `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift` | Modify | Consume recent-target facts and update cache |
| `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift` | Modify | Emit recent-target facts after successful open/new-tab actions |
| `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift` | Create | Derive which empty state to show and which recent entries/actions are available |
| `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift` | Create | Native SwiftUI empty-state / launcher content |
| `Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift` | Modify | Host SwiftUI empty-state view instead of hard-coded AppKit-only welcome |
| `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` | Modify | Drive two empty states and launcher actions |
| `Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift` | Create | Pure projector for management-footer labels and open-target resolution |
| `Sources/AgentStudio/Core/Views/Splits/ManagementPaneFooter.swift` | Create | Management-mode footer with pane identity text plus Finder/Cursor actions |
| `Sources/AgentStudio/Infrastructure/ExternalWorkspaceOpener.swift` | Create | Finder + Cursor (`--reuse-window`) launching helper |
| `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift` | Modify | Reserve bottom chrome space, show management footer, wire footer actions |
| `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift` | Modify | Fix worktree alignment grid and child indentation |
| `Sources/AgentStudio/Core/Views/CustomTabBar.swift` | Modify | Left-biased arrangement popover attachment anchor |
| `Sources/AgentStudio/App/MainWindowController.swift` | Modify | Improve AppKit toolbar/tool button help tag text |
| `scripts/inject-bundle-version.sh` | Create | Single bundle-version injection script for local and CI packaging |
| `.github/workflows/release.yml` | Modify | Inject tag-driven marketing/build version into bundled `Info.plist` |
| `.mise.toml` | Modify | Reuse bundle-version injection script for local release bundle creation |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift` | Modify | Recent-target ordering/cap tests |
| `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift` | Modify | Recent-target cache persistence round-trip tests |
| `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift` | Modify | Coordinator recent-target fact consumption tests |
| `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift` | Create | Empty-state/launcher derivation tests |
| `Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift` | Create | `cwd` → worktree fallback resolution tests |
| `Tests/AgentStudioTests/Infrastructure/ExternalWorkspaceOpenerTests.swift` | Create | Cursor command argument construction tests |

## Task 1: Add Recent Target Cache Model And Persistence

**Files:**
- Create: `Sources/AgentStudio/Core/Models/RecentWorkspaceTarget.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`

- [ ] **Step 1: Write failing cache-store tests**

```swift
@Test
func recordRecentTarget_movesExistingEntryToFront_andCapsAtFive() {
    let cache = WorkspaceRepoCache()
    let targets = (0..<6).map { index in
        RecentWorkspaceTarget(
            id: "target-\(index)",
            path: URL(fileURLWithPath: "/tmp/project-\(index)"),
            displayTitle: "project-\(index)",
            kind: .cwdOnly,
            lastOpenedAt: Date(timeIntervalSince1970: Double(index))
        )
    }

    for target in targets {
        cache.recordRecentTarget(target)
    }
    cache.recordRecentTarget(targets[2])

    #expect(cache.recentTargets.count == 5)
    #expect(cache.recentTargets.first?.id == targets[2].id)
}
```

- [ ] **Step 2: Run the focused cache-store tests and confirm failure**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-cache swift test --filter WorkspaceRepoCacheTests --filter WorkspacePersistorTests`

Expected: compile failure for missing `RecentWorkspaceTarget` / `recordRecentTarget` / `recentTargets`.

- [ ] **Step 3: Add the cache model and store API**

```swift
struct RecentWorkspaceTarget: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case worktree
        case cwdOnly
    }

    let id: String
    let path: URL
    let displayTitle: String
    let subtitle: String
    let repoId: UUID?
    let worktreeId: UUID?
    let kind: Kind
    let lastOpenedAt: Date
}

@Observable
@MainActor
final class WorkspaceRepoCache {
    private(set) var recentTargets: [RecentWorkspaceTarget] = []

    func recordRecentTarget(_ target: RecentWorkspaceTarget) {
        recentTargets.removeAll { $0.id == target.id }
        recentTargets.insert(target, at: 0)
        if recentTargets.count > 5 {
            recentTargets = Array(recentTargets.prefix(5))
        }
    }
}
```

- [ ] **Step 4: Persist recent targets in `workspace.cache.json`**

```swift
struct PersistableCacheState: Codable {
    var schemaVersion: Int
    var workspaceId: UUID
    var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
    var pullRequestCountByWorktreeId: [UUID: Int]
    var notificationCountByWorktreeId: [UUID: Int]
    var recentTargets: [RecentWorkspaceTarget]
    var sourceRevision: UInt64
    var lastRebuiltAt: Date?
}
```

- [ ] **Step 5: Add persistence round-trip tests**

```swift
@Test
func test_saveAndLoad_cacheState_roundTripsRecentTargets() throws {
    let workspaceId = UUID()
    let target = RecentWorkspaceTarget(
        id: "cwd:/tmp/demo",
        path: URL(fileURLWithPath: "/tmp/demo"),
        displayTitle: "demo",
        subtitle: "/tmp/demo",
        repoId: nil,
        worktreeId: nil,
        kind: .cwdOnly,
        lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_123)
    )
    let cacheState = WorkspacePersistor.PersistableCacheState(
        workspaceId: workspaceId,
        recentTargets: [target]
    )

    try persistor.saveCache(cacheState)
    let loaded = persistor.loadCache(for: workspaceId).value

    #expect(loaded?.recentTargets == [target])
}
```

- [ ] **Step 6: Re-run the focused tests and confirm pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-cache swift test --filter WorkspaceRepoCacheTests --filter WorkspacePersistorTests`

Expected: PASS for recent-target store + persistence coverage.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Models/RecentWorkspaceTarget.swift \
  Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift \
  Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift
git commit -m "feat: persist recent workspace targets in cache"
```

## Task 2: Record Recent Target Opens Through The Event Bus

**Files:**
- Create: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/WorkspaceActivityEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift`
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

- [ ] **Step 1: Write a failing coordinator test for recent-target facts**

```swift
@Test
func recentTargetOpened_recordsRecentTargetInCache() {
    let store = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: store,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )
    let worktreeId = UUID()
    let repoId = UUID()
    let target = RecentWorkspaceTarget(
        id: "worktree:\(worktreeId.uuidString)",
        path: URL(fileURLWithPath: "/tmp/agent-studio"),
        displayTitle: "agent-studio",
        subtitle: "main",
        repoId: repoId,
        worktreeId: worktreeId,
        kind: .worktree,
        lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_456)
    )

    coordinator.consume(
        .system(
            .test(event: .workspaceActivity(.recentTargetOpened(target)))
        )
    )

    #expect(repoCache.recentTargets.first == target)
}
```

- [ ] **Step 2: Run the coordinator tests and confirm failure**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-activity swift test --filter WorkspaceCacheCoordinatorTests`

Expected: compile failure for missing `WorkspaceActivityEvent` / `.workspaceActivity`.

- [ ] **Step 3: Add the new system fact type**

```swift
enum WorkspaceActivityEvent: Sendable {
    case recentTargetOpened(RecentWorkspaceTarget)
}

enum SystemScopedEvent: Sendable {
    case topology(TopologyEvent)
    case appLifecycle(AppLifecycleEvent)
    case focusChanged(FocusChangeEvent)
    case configChanged(ConfigChangeEvent)
    case workspaceActivity(WorkspaceActivityEvent)
}
```

- [ ] **Step 4: Teach the cache coordinator to consume the fact**

```swift
func consume(_ envelope: RuntimeEnvelope) {
    switch envelope {
    case .system(let systemEnvelope):
        handleTopology(systemEnvelope)
        handleWorkspaceActivity(systemEnvelope)
    case .worktree(let worktreeEnvelope):
        handleEnrichment(worktreeEnvelope)
    case .pane:
        return
    }
}

private func handleWorkspaceActivity(_ envelope: SystemEnvelope) {
    guard case .workspaceActivity(let activityEvent) = envelope.event else { return }
    switch activityEvent {
    case .recentTargetOpened(let target):
        repoCache.recordRecentTarget(target)
    }
}
```

- [ ] **Step 5: Emit recent-target facts from successful open/new-tab actions**

```swift
private func postRecentTargetOpened(
    path: URL,
    displayTitle: String,
    subtitle: String,
    repoId: UUID?,
    worktreeId: UUID?
) {
    let target = RecentWorkspaceTarget(
        id: worktreeId.map { "worktree:\($0.uuidString)" } ?? "cwd:\(path.standardizedFileURL.path)",
        path: path,
        displayTitle: displayTitle,
        subtitle: subtitle,
        repoId: repoId,
        worktreeId: worktreeId,
        kind: worktreeId == nil ? .cwdOnly : .worktree,
        lastOpenedAt: Date()
    )

    Task {
        await PaneRuntimeEventBus.shared.post(
            .system(
                SystemEnvelope(
                    source: .builtin(.coordinator),
                    seq: 0,
                    timestamp: ContinuousClock().now,
                    event: .workspaceActivity(.recentTargetOpened(target))
                )
            )
        )
    }
}
```

- [ ] **Step 6: Re-run the coordinator tests and one command-path test**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-activity swift test --filter WorkspaceCacheCoordinatorTests --filter PaneTabViewControllerCommandTests`

Expected: PASS, with recent-target facts stored without violating cache ownership.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/WorkspaceActivityEvent.swift \
  Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift \
  Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift \
  Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift
git commit -m "feat: record recent workspace opens through cache coordinator"
```

## Task 3: Replace The Single Empty State With Two Native Launcher States

**Files:**
- Create: `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- Create: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift`

- [ ] **Step 1: Write failing projector tests for the two empty states**

```swift
@Test
func project_noRepos_returnsFolderIntakeState() {
    let result = WorkspaceLauncherProjector.project(
        repos: [],
        tabs: [],
        recentTargets: []
    )

    #expect(result.kind == .noFolders)
}

@Test
func project_reposButNoTabs_returnsReadyLauncherState() {
    let repo = Repo(name: "agent-studio", repoPath: URL(fileURLWithPath: "/tmp/agent-studio"))
    let target = RecentWorkspaceTarget(
        id: "cwd:/tmp/agent-studio",
        path: URL(fileURLWithPath: "/tmp/agent-studio"),
        displayTitle: "agent-studio",
        subtitle: "/tmp/agent-studio",
        repoId: nil,
        worktreeId: nil,
        kind: .cwdOnly,
        lastOpenedAt: Date()
    )

    let result = WorkspaceLauncherProjector.project(
        repos: [repo],
        tabs: [],
        recentTargets: [target]
    )

    #expect(result.kind == .launcher)
    #expect(result.recentTargets.count == 1)
}
```

- [ ] **Step 2: Run the new projector tests and confirm failure**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-launcher swift test --filter WorkspaceLauncherProjectorTests`

Expected: compile failure for missing projector/state types.

- [ ] **Step 3: Create the projector and state model**

```swift
enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case launcher
}

struct WorkspaceEmptyStateModel: Equatable {
    let kind: WorkspaceEmptyStateKind
    let recentTargets: [RecentWorkspaceTarget]
    let showsOpenAll: Bool
}

enum WorkspaceLauncherProjector {
    static func project(
        repos: [Repo],
        tabs: [Tab],
        recentTargets: [RecentWorkspaceTarget]
    ) -> WorkspaceEmptyStateModel {
        if repos.isEmpty {
            return .init(kind: .noFolders, recentTargets: [], showsOpenAll: false)
        }
        if tabs.isEmpty {
            let recent = Array(recentTargets.prefix(5))
            return .init(kind: .launcher, recentTargets: recent, showsOpenAll: recent.count > 1)
        }
        return .init(kind: .launcher, recentTargets: [], showsOpenAll: false)
    }
}
```

- [ ] **Step 4: Implement a native SwiftUI empty-state view**

```swift
struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    var body: some View {
        switch model.kind {
        case .noFolders:
            NoFoldersEmptyState(onAddFolder: onAddFolder)
        case .launcher:
            WorkspaceLauncherState(
                recentTargets: model.recentTargets,
                onAddFolder: onAddFolder,
                onOpenRecent: onOpenRecent,
                onOpenAllRecent: onOpenAllRecent
            )
        }
    }
}
```

- [ ] **Step 5: Replace the AppKit-only factory body with `NSHostingView`**

```swift
static func make(
    model: WorkspaceEmptyStateModel,
    onAddFolder: @escaping () -> Void,
    onOpenRecent: @escaping (RecentWorkspaceTarget) -> Void,
    onOpenAllRecent: @escaping () -> Void
) -> NSView {
    let root = WorkspaceEmptyStateView(
        model: model,
        onAddFolder: onAddFolder,
        onOpenRecent: onOpenRecent,
        onOpenAllRecent: onOpenAllRecent
    )
    return NSHostingView(rootView: root)
}
```

- [ ] **Step 6: Update `PaneTabViewController` to drive launcher actions**

```swift
private func createEmptyStateView() -> NSView {
    let model = WorkspaceLauncherProjector.project(
        repos: store.repos,
        tabs: store.tabs,
        recentTargets: repoCache.recentTargets
    )
    return PaneTabEmptyStateViewFactory.make(
        model: model,
        onAddFolder: { [weak self] in self?.addFolderAction() },
        onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
        onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
    )
}
```

- [ ] **Step 7: Re-run projector and command-path tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-launcher swift test --filter WorkspaceLauncherProjectorTests --filter PaneTabViewControllerCommandTests`

Expected: PASS for empty-state derivation and launcher command routing.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift \
  Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
  Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift
git commit -m "feat: add dual workspace empty states and recent launcher"
```

## Task 4: Add Management-Mode Pane Footer And Reserve Bottom Chrome Space

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift`
- Create: `Sources/AgentStudio/Core/Views/Splits/ManagementPaneFooter.swift`
- Create: `Sources/AgentStudio/Infrastructure/ExternalWorkspaceOpener.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Test: `Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift`
- Test: `Tests/AgentStudioTests/Infrastructure/ExternalWorkspaceOpenerTests.swift`

- [ ] **Step 1: Write failing pure tests for target resolution and Cursor arguments**

```swift
@Test
func targetPath_prefersLiveCwd_thenFallsBackToWorktreeRoot() {
    let context = PaneManagementContext(
        title: "agent-studio",
        subtitle: "main",
        targetPath: URL(fileURLWithPath: "/tmp/agent-studio/subdir")
    )

    #expect(context.targetPath?.path == "/tmp/agent-studio/subdir")
}

@Test
func cursorArguments_useReuseWindowFlag() {
    let request = ExternalWorkspaceOpener.cursorCommand(
        path: URL(fileURLWithPath: "/tmp/agent-studio")
    )

    #expect(request.launchPath == "/usr/bin/env")
    #expect(request.arguments == ["cursor", "--reuse-window", "/tmp/agent-studio"])
}
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-footer swift test --filter PaneManagementContextTests --filter ExternalWorkspaceOpenerTests`

Expected: compile failure for missing footer-context / external opener types.

- [ ] **Step 3: Add the pure context projector**

```swift
struct PaneManagementContext: Equatable {
    let title: String
    let subtitle: String
    let targetPath: URL?

    static func project(
        paneId: UUID,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> Self {
        let paneTitle = PaneDisplayProjector.displayLabel(for: paneId, store: store, repoCache: repoCache)
        let pane = store.pane(paneId)
        let resolvedTarget = pane?.metadata.cwd
            ?? pane?.worktreeId.flatMap { store.worktree($0)?.path }

        return Self(
            title: paneTitle,
            subtitle: resolvedTarget?.path ?? "No filesystem target",
            targetPath: resolvedTarget
        )
    }
}
```

- [ ] **Step 4: Add the external opener helper**

```swift
enum ExternalWorkspaceOpener {
    struct CommandRequest: Equatable {
        let launchPath: String
        let arguments: [String]
    }

    static func cursorCommand(path: URL) -> CommandRequest {
        CommandRequest(
            launchPath: "/usr/bin/env",
            arguments: ["cursor", "--reuse-window", path.path]
        )
    }

    static func openInFinder(_ path: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
    }
}
```

Implementation note:
- This slice assumes `cursor` is present in PATH.
- Do not add availability-detection UX or fallback-window logic yet.
- If later testing shows the local installation only supports `-r`, accept `["cursor", "-r", path.path]` as an equivalent implementation.

- [ ] **Step 5: Implement the management footer view**

```swift
struct ManagementPaneFooter: View {
    let context: PaneManagementContext
    let onOpenFinder: () -> Void
    let onOpenCursor: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title).font(.system(size: AppStyle.textXs, weight: .semibold))
                Text(context.subtitle).font(.system(size: AppStyle.textXs)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenFinder) { Image(systemName: "folder") }.help("Open pane location in Finder")
            Button(action: onOpenCursor) { Image(systemName: "cursorarrow.click.2") }.help("Open pane location in Cursor")
        }
        .padding(.horizontal, AppStyle.spacingStandard)
        .frame(height: DrawerLayout.iconBarFrameHeight)
        .background(Color.black.opacity(AppStyle.managementControlFill))
    }
}
```

- [ ] **Step 6: Reserve bottom pane space instead of letting content hide behind drawer/footer chrome**

```swift
VStack(spacing: 0) {
    PaneViewRepresentable(paneHost: paneHost)
        .id(paneHost.hostIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    if managementMode.isActive {
        ManagementPaneFooter(
            context: PaneManagementContext.project(
                paneId: paneHost.id,
                store: store,
                repoCache: repoCache
            ),
            onOpenFinder: { openPaneInFinder() },
            onOpenCursor: { openPaneInCursor() }
        )
    } else if !isDrawerChild {
        DrawerOverlay(
            paneId: paneHost.id,
            drawer: drawer,
            isIconBarVisible: true,
            action: actionDispatcher.dispatch
        )
        .frame(height: DrawerLayout.iconBarFrameHeight)
    }
}
```

- [ ] **Step 7: Re-run the pure tests and one pane command suite**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-footer swift test --filter PaneManagementContextTests --filter ExternalWorkspaceOpenerTests --filter PaneTabViewControllerCommandTests`

Expected: PASS for target resolution, Cursor arguments, and no command regressions.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift \
  Sources/AgentStudio/Core/Views/Splits/ManagementPaneFooter.swift \
  Sources/AgentStudio/Infrastructure/ExternalWorkspaceOpener.swift \
  Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift \
  Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift \
  Tests/AgentStudioTests/Infrastructure/ExternalWorkspaceOpenerTests.swift
git commit -m "feat: add management pane footer and external open actions"
```

## Task 5: Fix Sidebar Alignment, Tooltip Coverage, And Arrangement Popover Alignment

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/Core/Views/CustomTabBar.swift`
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

- [ ] **Step 1: Write a failing sidebar row-layout test for the worktree leading grid**

```swift
@Test
func sidebarWorktreeRow_usesSharedLeadingIconColumnWidth() {
    #expect(AppStyle.sidebarGroupChildRowLeadingInset >= AppStyle.sidebarListRowLeadingInset)
    #expect(AppStyle.sidebarRowLeadingIconColumnWidth > 0)
}
```

- [ ] **Step 2: Run the sidebar-focused tests and confirm current polish gaps**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-sidebar swift test --filter RepoSidebarContentViewTests`

Expected: either missing assertion helpers or failing expectations after the row-grid change is introduced.

- [ ] **Step 3: Align worktree rows to the same visual icon grid as repo headers**

```swift
private struct SidebarWorktreeRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sidebarRowContentSpacing) {
            HStack(spacing: AppStyle.spacingTight) {
                checkoutTypeIcon
                    .frame(width: AppStyle.sidebarGroupIconSize, alignment: .leading)
                Text(checkoutTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: AppStyle.spacingTight) {
                OcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
                    .frame(width: AppStyle.sidebarGroupIconSize, alignment: .leading)
                Text(branchName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
```

- [ ] **Step 4: Left-bias the arrangements popover arrow**

```swift
.popover(
    isPresented: $showPanel,
    attachmentAnchor: .point(.bottomLeading),
    arrowEdge: .bottom
) {
    ArrangementPanel(
        tabId: tab.id,
        panes: tab.panes,
        arrangements: tab.arrangements,
        onPaneAction: onPaneAction,
        onSaveArrangement: { onSaveArrangement(tab.id) }
    )
}
```

Implementation note:
- Start with SwiftUI `attachmentAnchor`.
- If visual verification shows the arrow is still centered or otherwise uncontrollable, hard-cut to an AppKit-backed `NSPopover` anchored to a left-biased positioning rect instead of layering more SwiftUI workarounds.

- [ ] **Step 5: Audit and add missing help tags with product copy**

```swift
item.toolTip = "Add folder to scan for repos (\u{2318}\u{2325}\u{21E7}O)"

Button(action: onOpenCursor) {
    Image(systemName: "cursorarrow.click.2")
}
.help("Open pane location in Cursor")
```

- [ ] **Step 6: Re-run the focused tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-sidebar swift test --filter RepoSidebarContentViewTests --filter TabBarAdapterTests`

Expected: PASS for sidebar and tab-bar non-regression coverage.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
  Sources/AgentStudio/Core/Views/CustomTabBar.swift \
  Sources/AgentStudio/App/MainWindowController.swift \
  Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "fix: polish sidebar alignment tooltips and popover anchor"
```

## Task 6: Inject Release Versions Into The Bundled Info.plist

**Files:**
- Create: `scripts/inject-bundle-version.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `.mise.toml`
- Modify: `Sources/AgentStudio/Resources/Info.plist`

- [ ] **Step 1: Write the bundle-version injection script**

```bash
#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$1"
MARKETING_VERSION="$2"
BUILD_VERSION="$3"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "$PLIST_PATH"
```

- [ ] **Step 2: Update the release workflow to derive versions from tag + run number**

```yaml
- name: Determine version
  id: version
  run: |
    if [[ "$GITHUB_REF" == refs/tags/* ]]; then
      echo "marketing_version=${GITHUB_REF#refs/tags/v}" >> "$GITHUB_OUTPUT"
    else
      echo "marketing_version=0.0.0-dev" >> "$GITHUB_OUTPUT"
    fi
    echo "build_version=${GITHUB_RUN_NUMBER}" >> "$GITHUB_OUTPUT"

- name: Create App Bundle
  run: |
    cp Sources/AgentStudio/Resources/Info.plist "$APP_DIR/"
    scripts/inject-bundle-version.sh \
      "$APP_DIR/Info.plist" \
      "${{ steps.version.outputs.marketing_version }}" \
      "${{ steps.version.outputs.build_version }}"
```

- [ ] **Step 3: Reuse the same script in the local `mise` bundle task**

```toml
MARKETING_VERSION="${APP_MARKETING_VERSION:-0.0.1-dev}"
BUILD_VERSION="${APP_BUILD_VERSION:-$(git rev-list --count HEAD)}"
cp Sources/AgentStudio/Resources/Info.plist "$APP_DIR/"
scripts/inject-bundle-version.sh "$APP_DIR/Info.plist" "$MARKETING_VERSION" "$BUILD_VERSION"
```

- [ ] **Step 4: Keep the checked-in plist as a sane development baseline**

```xml
<key>CFBundleVersion</key>
<string>1</string>
<key>CFBundleShortVersionString</key>
<string>0.0.1-dev</string>
```

- [ ] **Step 5: Run packaging smoke checks**

Run: `APP_MARKETING_VERSION=0.2.0 APP_BUILD_VERSION=123 mise run create-app-bundle`

Expected: bundle builds successfully.

Run: `plutil -p AgentStudio.app/Contents/Info.plist | rg 'CFBundleShortVersionString|CFBundleVersion|0.2.0|123'`

Expected: output shows `CFBundleShortVersionString => "0.2.0"` and `CFBundleVersion => "123"`.

- [ ] **Step 6: Commit**

```bash
git add scripts/inject-bundle-version.sh \
  .github/workflows/release.yml \
  .mise.toml \
  Sources/AgentStudio/Resources/Info.plist
git commit -m "fix: inject bundle version during app packaging"
```

## Final Verification

- [ ] **Step 1: Run format**

Run: `mise run format`

Expected: exit code `0`.

- [ ] **Step 2: Run lint**

Run: `mise run lint`

Expected: exit code `0`.

- [ ] **Step 3: Run full tests**

Run: `mise run test`

Expected: all Swift `Testing` suites pass with exit code `0`.

- [ ] **Step 4: Build the app**

Run: `mise run build`

Expected: exit code `0` and `.build/debug/AgentStudio` refreshed.

- [ ] **Step 5: Visually verify the UX fixes**

Run:

```bash
pkill -9 -f "AgentStudio" || true
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Expected visual checks:
- zero-folder screen shows native Add Folder intake state
- populated-but-tabless workspace shows launcher state with recent items
- management mode shows pane footer with label + Finder/Cursor actions
- terminal content no longer hides behind bottom drawer/footer chrome
- worktree rows align cleanly under repo header icon grid
- tooltips appear on hover for newly added controls
- arrangement popover arrow is visibly left-biased instead of centered
- About panel shows the injected build version after packaging smoke check

- [ ] **Step 6: Commit the verification-only follow-up if needed**

```bash
git add -A
git commit -m "chore: finalize workspace ux polish" || true
```

## Self-Review

- Spec coverage:
  - Empty-state split: covered in Task 3.
  - Recent 5 worktrees/CWDs and “open all in tabs”: covered in Tasks 2 and 3.
  - Management-mode footer labels plus Finder/Cursor actions: covered in Task 4.
  - Drawer/content overlap bug: covered in Task 4.
  - Sidebar child alignment bug: covered in Task 5.
  - Missing tooltips/help tags: covered in Task 5.
  - Left-aligned arrangement popover arrow: covered in Task 5.
  - About/version mismatch and GitHub Release propagation: covered in Task 6.
- Placeholder scan:
  - No `TODO`, `TBD`, “implement later”, or “write tests for the above” placeholders remain.
- Type consistency:
  - `RecentWorkspaceTarget`, `WorkspaceActivityEvent`, `WorkspaceEmptyStateModel`, and `PaneManagementContext` use the same names across task definitions.

Plan complete and saved to `docs/superpowers/plans/2026-03-31-workspace-ux-polish.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
