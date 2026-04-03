# Onboarding Welcome Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sparse welcome screen with a three-state onboarding flow (welcome → scanning → launcher) that communicates AgentStudio's value and provides transition feedback.

**Architecture:** Add `scanningPath` to `WorkspaceStore`, add `.scanning(URL)` case to `WorkspaceEmptyStateKind`, rewrite the welcome body as a horizontal split layout with a sidebar illustration, add a scanning content view, auto-collapse sidebar on boot when no repos exist.

**Tech Stack:** SwiftUI views in NSHostingView, AppKit NSSplitViewController sidebar collapse, `@Observable` reactivity, SF Symbols, existing AppStyle constants and octicon assets.

**Spec:** `docs/superpowers/specs/2026-04-02-onboarding-welcome-flow-design.md`

---

### Task 1: Add scanning state to WorkspaceStore

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`

This adds the `scanningPath` property that drives the scanning UI state. No persistence — it's transient.

- [ ] **Step 1: Add scanningPath property to WorkspaceStore**

In `WorkspaceStore.swift`, add to the "Transient UI State" section (after line ~33):

```swift
// MARK: - Scanning State

private(set) var scanningPath: URL?

func beginScan(_ path: URL) { scanningPath = path }
func endScan() { scanningPath = nil }
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceStore.swift
git commit -m "feat: add scanningPath transient state to WorkspaceStore"
```

---

### Task 2: Add `.scanning` case to model and projector

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`

- [ ] **Step 1: Add `.scanning(URL)` case to WorkspaceEmptyStateKind**

In `WorkspaceLauncherProjector.swift`, update the enum:

```swift
enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case scanning(URL)
    case launcher
}
```

- [ ] **Step 2: Add scanningFolderPath convenience to WorkspaceEmptyStateModel**

```swift
struct WorkspaceEmptyStateModel: Equatable {
    let kind: WorkspaceEmptyStateKind
    let recentCards: [WorkspaceRecentCardModel]

    var scanningFolderPath: URL? {
        if case .scanning(let url) = kind { return url }
        return nil
    }

    var recentTargets: [RecentWorkspaceTarget] {
        recentCards.map(\.target)
    }

    var showsOpenAll: Bool {
        recentCards.count > 1
    }
}
```

- [ ] **Step 3: Update WorkspaceLauncherProjector.project to accept store directly**

The projector now reads `store.scanningPath` to determine if scanning is in progress:

```swift
@MainActor
enum WorkspaceLauncherProjector {
    static func project(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> WorkspaceEmptyStateModel {
        // Scanning takes priority when no repos exist yet
        if let scanningPath = store.scanningPath, store.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .scanning(scanningPath), recentCards: [])
        }

        if store.repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .noFolders, recentCards: [])
        }

        if store.tabs.isEmpty {
            let visibleCards = Array(
                projectRecentCards(
                    recentTargets: repoCache.recentTargets,
                    store: store,
                    repoCache: repoCache
                )
                .prefix(6)
            )
            return WorkspaceEmptyStateModel(
                kind: .launcher,
                recentCards: visibleCards
            )
        }

        return WorkspaceEmptyStateModel(kind: .launcher, recentCards: [])
    }
```

The rest of the file (private methods) stays unchanged.

- [ ] **Step 4: Fix any compiler errors from the new enum case**

The `switch` on `model.kind` in `WorkspaceEmptyStateView.swift` needs a `.scanning` case. Add a placeholder for now:

```swift
case .scanning:
    Text("Scanning…") // placeholder — replaced in Task 4
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift
git commit -m "feat: add scanning state to empty state model and projector"
```

---

### Task 3: Build the sidebar preview illustration

**Files:**
- Create: `Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift`

A static SwiftUI view showing a realistic sidebar preview with well-known repos. Uses `AppStyle` constants and the app's real octicon assets for visual consistency.

- [ ] **Step 1: Create WelcomeSidebarIllustration.swift**

Create the file at `Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift`:

```swift
import SwiftUI

/// Static, non-interactive illustration of the sidebar for the welcome screen.
/// Shows well-known open-source repos with realistic worktree structure and status chips
/// to communicate what AgentStudio's sidebar provides.
struct WelcomeSidebarIllustration: View {

    private let illustrationWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            repoGroup(
                title: "react",
                org: "facebook",
                accentColor: Color(red: 0.49, green: 0.54, blue: 0.97),
                worktrees: [
                    .main(title: "react", branch: "main"),
                    .worktree(
                        title: "react.concurrent-mode",
                        branch: "feature/concurrent-mode",
                        chips: .init(
                            added: 42, deleted: 8, isDirty: true,
                            ahead: 2, behind: 1, prCount: 1, notifications: 0
                        )
                    ),
                ],
                isExpanded: true
            )

            repoGroup(
                title: "uv",
                org: "astral-sh",
                accentColor: Color(red: 0.35, green: 0.79, blue: 0.56),
                worktrees: [
                    .main(title: "uv", branch: "main"),
                    .worktree(
                        title: "uv.fix-resolver",
                        branch: "fix/resolver-perf",
                        chips: .init(
                            added: 12, deleted: 3, isDirty: false,
                            ahead: 1, behind: 0, prCount: 1, notifications: 2
                        )
                    ),
                ],
                isExpanded: true
            )

            repoGroup(
                title: "ghostty",
                org: "ghostty-org",
                accentColor: Color(red: 0.6, green: 0.6, blue: 0.65),
                worktrees: [],
                isExpanded: false
            )
        }
        .padding(16)
        .frame(width: illustrationWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(AppStyle.fillMuted))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
                )
        )
    }

    // MARK: - Group

    private func repoGroup(
        title: String,
        org: String,
        accentColor: Color,
        worktrees: [IllustrationWorktree],
        isExpanded: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Group header
            HStack(spacing: AppStyle.spacingTight) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: AppStyle.textXs, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyle.textBase, alignment: .center)

                Text(title)
                    .font(.system(size: AppStyle.textBase, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(org)
                    .font(.system(size: AppStyle.sidebarGroupOrganizationFontSize))
                    .foregroundStyle(.tertiary)
            }

            // Worktrees (only when expanded)
            if isExpanded {
                ForEach(worktrees) { worktree in
                    illustrationWorktreeRow(worktree: worktree, accentColor: accentColor)
                        .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)
                }
            }
        }
    }

    // MARK: - Worktree Row

    private func illustrationWorktreeRow(
        worktree: IllustrationWorktree,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.sidebarRowContentSpacing) {
            // Checkout title row
            HStack(spacing: AppStyle.spacingTight) {
                worktreeIcon(isMain: worktree.isMain, color: accentColor)
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text(worktree.title)
                    .font(.system(size: AppStyle.textBase, weight: worktree.isMain ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            // Branch row
            HStack(spacing: AppStyle.spacingTight) {
                WorkspaceOcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text(worktree.branch)
                    .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            // Status chips — only for worktrees with interesting status
            if let chips = worktree.chips {
                WorkspaceStatusChipRow(
                    model: WorkspaceStatusChipsModel(
                        branchStatus: GitBranchStatus(
                            isDirty: chips.isDirty,
                            syncState: syncState(ahead: chips.ahead, behind: chips.behind),
                            prCount: chips.prCount,
                            linesAdded: chips.added,
                            linesDeleted: chips.deleted
                        ),
                        notificationCount: chips.notifications
                    ),
                    accentColor: accentColor
                )
                .padding(.leading, AppStyle.sidebarStatusRowLeadingIndent)
            }
        }
        .padding(.vertical, AppStyle.sidebarRowVerticalInset)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func worktreeIcon(isMain: Bool, color: Color) -> some View {
        if isMain {
            WorkspaceOcticonImage(name: "octicon-star-fill", size: AppStyle.textBase)
                .foregroundStyle(color)
        } else {
            WorkspaceOcticonImage(name: "octicon-git-worktree", size: AppStyle.textBase)
                .foregroundStyle(color)
                .rotationEffect(.degrees(180))
        }
    }

    private func syncState(ahead: Int, behind: Int) -> SyncState {
        if ahead > 0 && behind > 0 { return .diverged(ahead: ahead, behind: behind) }
        if ahead > 0 { return .ahead(ahead) }
        if behind > 0 { return .behind(behind) }
        return .synced
    }
}

// MARK: - Data Types

private struct IllustrationChips {
    let added: Int
    let deleted: Int
    let isDirty: Bool
    let ahead: Int
    let behind: Int
    let prCount: Int
    let notifications: Int
}

private struct IllustrationWorktree: Identifiable {
    let id: String
    let title: String
    let branch: String
    let isMain: Bool
    let chips: IllustrationChips?

    static func main(title: String, branch: String) -> IllustrationWorktree {
        IllustrationWorktree(id: "main-\(title)", title: title, branch: branch, isMain: true, chips: nil)
    }

    static func worktree(title: String, branch: String, chips: IllustrationChips) -> IllustrationWorktree {
        IllustrationWorktree(id: "wt-\(title)", title: title, branch: branch, isMain: false, chips: chips)
    }
}
```

- [ ] **Step 2: Verify the octicon image type name**

The sidebar uses `OcticonImage` (in `RepoSidebarContentView.swift`) while the welcome view uses `WorkspaceOcticonImage`. Check which name is correct and use it consistently. Grep for both:

Run: Search for `OcticonImage` and `WorkspaceOcticonImage` in the codebase to determine the correct type name. Update the illustration code to match.

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

There may be compilation issues if:
- `GitBranchStatus` init is not a plain memberwise init — check and adapt
- `SyncState` enum cases differ — check exact names
- Octicon image view name differs — fix to match

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift
git commit -m "feat: add sidebar preview illustration for welcome screen"
```

---

### Task 4: Rewrite the welcome and scanning content views

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`

Replace the vertical `folderIntakeBody` with a horizontal layout (illustration left, text+CTA right). Add the scanning body. Remove the "Add Folder" button from the launcher body.

- [ ] **Step 1: Rewrite folderIntakeBody as horizontal layout**

Replace the existing `folderIntakeBody` in `WorkspaceEmptyStateView.swift`:

```swift
private var folderIntakeBody: some View {
    HStack(alignment: .center, spacing: 56) {
        WelcomeSidebarIllustration()

        VStack(alignment: .leading, spacing: 20) {
            AppLogoView(size: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to AgentStudio")
                    .font(.system(size: 26, weight: .semibold))

                Text("A terminal workspace for your repos.")
                    .font(.system(size: AppStyle.textLg))
                    .foregroundStyle(.secondary)
            }

            Text("Point at a parent folder — AgentStudio discovers every repo and worktree inside.")
                .font(.system(size: AppStyle.textBase))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 320)

            VStack(alignment: .leading, spacing: 8) {
                Button("Choose a Folder to Scan…") {
                    onAddFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("⌘⌥⇧O")
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 2)
            }
        }
    }
    .frame(maxWidth: .infinity)
}
```

- [ ] **Step 2: Add scanningBody**

Add a new computed property after `folderIntakeBody`:

```swift
private var scanningBody: some View {
    VStack(spacing: 20) {
        ProgressView()
            .controlSize(.regular)
            .scaleEffect(1.2)

        VStack(spacing: 8) {
            Text("Scanning \(scanningFolderDisplayName)")
                .font(.system(size: 20, weight: .semibold))

            if repoCount > 0 {
                Text("Found \(repoCount) \(repoCount == 1 ? "repository" : "repositories") so far…")
                    .font(.system(size: AppStyle.textBase))
                    .foregroundStyle(.secondary)
            } else {
                Text("Looking for repositories…")
                    .font(.system(size: AppStyle.textBase))
                    .foregroundStyle(.secondary)
            }

            Text("Repos appear in the sidebar as they're discovered.")
                .font(.system(size: AppStyle.textSm))
                .foregroundStyle(.tertiary)
        }

        // Divider
        Rectangle()
            .fill(Color.white.opacity(AppStyle.fillSubtle))
            .frame(width: 200, height: 1)
            .padding(.vertical, 4)

        // ⌘T hint
        HStack(alignment: .top, spacing: 10) {
            Text("⌘T")
                .font(.system(size: AppStyle.textBase, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)

            Text("Open a terminal tab anytime — no need to wait.")
                .font(.system(size: AppStyle.textBase))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 320)
    }
    .frame(maxWidth: .infinity)
}

private var scanningFolderDisplayName: String {
    guard let path = model.scanningFolderPath else { return "" }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let fullPath = path.path
    if fullPath.hasPrefix(home) {
        return "~" + fullPath.dropFirst(home.count)
    }
    return fullPath
}
```

- [ ] **Step 3: Add repoCount property**

The scanning view needs a live repo count. Add a property to `WorkspaceEmptyStateView`:

```swift
struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let repoCount: Int  // new — live count from store.repos.count
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void
```

- [ ] **Step 4: Update the switch to include scanning case**

Replace the placeholder `case .scanning` in the body:

```swift
Group {
    switch model.kind {
    case .noFolders:
        folderIntakeBody
            .id("noFolders")
            .transition(.opacity)
    case .scanning:
        scanningBody
            .id("scanning")
            .transition(.opacity)
    case .launcher:
        launcherBody
            .id("launcher")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
```

- [ ] **Step 5: Remove the WorkspaceHomeHeader from folderIntakeBody**

The welcome screen now has its own inline title/subtitle (left-aligned on the right side of the HStack), so it no longer uses `WorkspaceHomeHeader`. The launcher still uses it. No change to `WorkspaceHomeHeader` itself.

- [ ] **Step 6: Remove the "Add Folder" button from launcherBody**

In `launcherBody`, delete the trailing button block:

```swift
// DELETE this from launcherBody:
Button("Add Folder to Scan...") {
    onAddFolder()
}
.buttonStyle(.bordered)
.controlSize(.large)
.help("Add folder to scan for repos")
```

The toolbar already has the Add Folder button.

- [ ] **Step 7: Build to verify compilation**

This will fail because `PaneTabEmptyStateViewFactory` and `PaneTabViewController` need the new `repoCount` parameter. Fix in next task.

---

### Task 5: Wire up the factory and view controller

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`

- [ ] **Step 1: Update PaneTabEmptyStateViewFactory to pass repoCount**

```swift
@MainActor
enum PaneTabEmptyStateViewFactory {
    static func make(
        model: WorkspaceEmptyStateModel,
        repoCount: Int,
        onAddFolder: @escaping () -> Void,
        onOpenRecent: @escaping (RecentWorkspaceTarget) -> Void,
        onOpenAllRecent: @escaping () -> Void
    ) -> NSHostingView<WorkspaceEmptyStateView> {
        NSHostingView(
            rootView: WorkspaceEmptyStateView(
                model: model,
                repoCount: repoCount,
                onAddFolder: onAddFolder,
                onOpenRecent: onOpenRecent,
                onOpenAllRecent: onOpenAllRecent
            )
        )
    }
}
```

- [ ] **Step 2: Update PaneTabViewController — createEmptyStateView**

In `PaneTabViewController.swift`, update `createEmptyStateView()`:

```swift
private func createEmptyStateView() -> NSHostingView<WorkspaceEmptyStateView> {
    PaneTabEmptyStateViewFactory.make(
        model: emptyStateModel,
        repoCount: store.repos.count,
        onAddFolder: { [weak self] in self?.addFolderAction() },
        onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
        onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
    )
}
```

- [ ] **Step 3: Update PaneTabViewController — rebuildEmptyStateView**

Update `rebuildEmptyStateView()` to pass repoCount and use the new rootView:

```swift
private func rebuildEmptyStateView() {
    let currentModel = emptyStateModel
    guard currentModel != lastEmptyStateModel else { return }
    emptyStateView?.rootView = WorkspaceEmptyStateView(
        model: currentModel,
        repoCount: store.repos.count,
        onAddFolder: { [weak self] in self?.addFolderAction() },
        onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
        onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
    )
    lastEmptyStateModel = currentModel
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift
git commit -m "feat: rewrite welcome as horizontal layout, add scanning content view"
```

---

### Task 6: Wire scanning lifecycle in AppDelegate

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`

- [ ] **Step 1: Set scanningPath before refreshWatchedFolders**

In `handleAddFolderRequested`, wrap the refresh call with begin/end scan:

```swift
private func handleAddFolderRequested(startingAt initialURL: URL? = nil) async {
    let rootURL: URL
    if let initialURL {
        rootURL = initialURL.standardizedFileURL
    } else {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to scan for Git repositories."
        panel.prompt = "Scan Folder"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }
        rootURL = selectedURL.standardizedFileURL
    }

    // 1. Persist the watched path (direct store mutation)
    store.addWatchedPath(rootURL)

    // 2. Signal scanning state for UI
    store.beginScan(rootURL)

    // The watched-folder command returns the authoritative scan summary.
    let refreshSummary = await watchedFolderCommands.refreshWatchedFolders(
        store.watchedPaths.map(\.path)
    )

    // 3. Clear scanning state
    store.endScan()

    let repoPaths = refreshSummary.repoPaths(in: rootURL)

    guard !repoPaths.isEmpty else {
        let alert = NSAlert()
        alert.messageText = "No Git Repositories Found"
        alert.informativeText =
            "No folders with a Git repository were found under \(rootURL.lastPathComponent). The folder will still be watched for future repos."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/App/AppDelegate.swift
git commit -m "feat: wire scanning lifecycle begin/end in addFolder flow"
```

---

### Task 7: Auto-collapse sidebar on boot when no repos

**Files:**
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`

- [ ] **Step 1: Override sidebar restore to force-collapse when empty**

In `MainSplitViewController.viewDidLoad()`, replace the sidebar collapsed restore block:

```swift
// Restore sidebar collapsed state — force collapse if no repos
if store.repos.isEmpty {
    sidebarItem.isCollapsed = true
} else if UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey) {
    sidebarItem.isCollapsed = true
}
```

This ensures first-launch (no repos) always shows sidebar collapsed, even if a previous session left it expanded.

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/App/MainSplitViewController.swift
git commit -m "feat: auto-collapse sidebar on boot when no repos exist"
```

---

### Task 8: Visual verification and polish

**Files:** None new — this is verification and adjustments.

- [ ] **Step 1: Build and launch**

```bash
mise run build
pkill -9 -f "AgentStudio" 2>/dev/null; sleep 1
.build/debug/AgentStudio &
```

- [ ] **Step 2: Verify welcome screen (State 1)**

Use Peekaboo to capture the welcome screen:

```bash
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Check:
- Sidebar is collapsed (no sidebar visible)
- Horizontal layout: illustration left, text+CTA right
- Illustration shows 3 repo groups with realistic data
- Status chips only on worktrees with interesting status
- App icon at 56pt, left-aligned with text
- "Choose a Folder to Scan…" button is prominent
- ⌘⌥⇧O hint visible

- [ ] **Step 3: Verify scanning transition (State 2)**

Click "Choose a Folder to Scan…", select a folder with repos.

Check:
- Welcome content fades out
- Sidebar slides in from left
- Scanning content appears: spinner, folder path, live repo count
- ⌘T hint visible below divider
- Repos appear in sidebar as discovered

- [ ] **Step 4: Verify launcher (State 3)**

After scan completes:

Check:
- Content transitions to "Workspace Ready"
- Recent cards visible (if any recent targets exist)
- No "Add Folder" button in content area
- Sidebar shows all discovered repos

- [ ] **Step 5: Verify edge case — cancel folder picker**

Click "Choose a Folder to Scan…", then cancel the dialog.

Check:
- Stays on welcome screen
- No state change

- [ ] **Step 6: Verify edge case — scan folder with no repos**

Select an empty folder.

Check:
- "No Git Repositories Found" alert appears
- Returns to welcome screen after dismissing

- [ ] **Step 7: Adjust spacing/sizing if needed**

Based on visual verification, tune:
- `HStack` spacing in `folderIntakeBody` (currently 56pt)
- Illustration width (currently 300pt)
- Max content width (currently 820pt in `contentWidth`)
- Icon size, text sizes, padding

- [ ] **Step 8: Run full lint and test**

```bash
mise run lint
mise run test
```

Expected: Zero errors, all tests pass.

- [ ] **Step 9: Final commit**

```bash
git add -A
git commit -m "polish: visual adjustments after verification"
```
