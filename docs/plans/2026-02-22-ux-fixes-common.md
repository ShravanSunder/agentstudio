# UX Fixes Common Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix pane editor interaction issues, redesign sidebar repo management with recursive discovery and worktree badges, add duplicate/open-in actions through the validated action pipeline, and enhance new pane/tab creation with repo/worktree picker options.

**Architecture:** All new user actions route through `PaneAction` → `ActionResolver` → `ActionValidator` → `PaneCoordinator` → `WorkspaceStore`. New `PaneAction` cases use `PaneId` (not raw `UUID`) for pane identity. All pane creation flows populate `PaneMetadata` with full dynamic view fields (`repoId`, `worktreeId`, `checkoutRef`, `parentFolder`, `agentType`, `tags`) to support dynamic views and window restoration. Deduplication queries `RuntimeRegistry` + `PaneMetadata.worktreeId`. Sidebar changes modify `SidebarContentView` (vertical slice in `App/`). New `CommandBarScope.repos` reuses existing `Features/CommandBar/`. Every change is unit-testable.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSSplitViewController), `@Observable` stores, `PaneId` (UUIDv7), `PaneMetadata`, `RuntimeRegistry`, `WorktrunkService` (git CLI wrapper)

## Review Follow-up Tasks

- [x] Resolve every open Gemini code review comment for this UX fixes stream.
- [x] Post a GitHub reply on each Gemini review thread with explicit status: `Addressed` or `Dismissed`.
- [x] For each `Dismissed` reply, include a brief technical reason and the file/line reference used for validation.

**Pane Identity Contract:**
- `PaneId` struct (UUIDv7 for new panes, UUID compat for legacy) — already exists in `Core/PaneRuntime/Contracts/PaneId.swift`
- `PaneMetadata` with rich identity — already exists in `Core/PaneRuntime/Contracts/PaneMetadata.swift`
- `RuntimeRegistry` keyed by `PaneId` — already exists in `Core/PaneRuntime/Registry/RuntimeRegistry.swift`
- New `PaneAction` cases MUST use `PaneId` for pane identity (existing cases still use `UUID` pending full migration)
- All pane creation flows MUST populate `PaneMetadata.source` with `.worktree(worktreeId:, repoId:)` and set live fields (`repoId`, `worktreeId`, `checkoutRef`, `parentFolder`) for dynamic view projection

---

## Phase 1: Pane Editor Quick Fixes

### Task 1: Resize Drag Handle to 60×100

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift:72-103`

**Context:** The drag handle (move icon) in pane editor mode is currently 20×32 points. User wants 60w×100h. Icon stays at `toolbarIconSize` (16pt). Corner radius scales proportionally (12→20).

**Step 1: Update drag handle frame**

In `TerminalPaneLeaf.swift`, find the drag handle ZStack (line 72-103). Change:
- `.frame(width: 20, height: 20 * 1.6)` → `.frame(width: 60, height: 100)` (line 83)
- `cornerRadius: 12` → `cornerRadius: 20` (line 76, 84)
- Same changes to the drag preview block (line 93-100): `.frame(width: 60, height: 100)` and `cornerRadius: 20`

**Step 2: Build and verify**

Run: `mise run build`
Expected: Compiles without errors.

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift
git commit -m "fix: resize pane editor drag handle to 60×100"
```

---

### Task 2: Block Pane Interaction in Editor Mode

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift:46`

**Context:** In editor mode, the underlying pane (webview, terminal) still receives mouse events — dragging, clicking, scrolling all pass through. The pane content should be non-interactable; only editor overlay buttons should respond.

**Step 1: Add hit-testing guard on PaneViewRepresentable**

In `TerminalPaneLeaf.swift` body (line 46), after `PaneViewRepresentable(paneView: paneView)`, add:
```swift
PaneViewRepresentable(paneView: paneView)
    .allowsHitTesting(!managementMode.isActive)
```

This blocks all mouse events from reaching the NSView when editor mode is active. The editor overlay controls (minimize, close, add, drag handle) are in ZStack layers above and are unaffected.

**Step 2: Build and verify**

Run: `mise run build`
Expected: Compiles. In editor mode, clicking/dragging pane content does nothing. Editor buttons still work.

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift
git commit -m "fix: block pane interaction in editor mode"
```

---

### Task 3: Unify Editor Button Styling

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift:111-181`

**Context:** Minimize, close, and add (+) buttons have inconsistent sizes and colors. All three should use:
- **Icon size:** `AppStyle.paneControlIconSize` (18pt)
- **Frame:** `AppStyle.paneControlButtonSize` (34pt)
- **Background:** `Color.black.opacity(AppStyle.foregroundDim)` — solid black at 0.5
- **Icon color:** `.white.opacity(AppStyle.foregroundMuted)` — white at 0.6
- **Add button keeps quarter-moon shape** (UnevenRoundedRectangle) but matches color/size

**Step 1: Update minimize and close buttons (lines 111-143)**

Change icon font from `AppStyle.toolbarIconSize` → `AppStyle.paneControlIconSize` for both minimize and close:
```swift
Image(systemName: "minus.circle.fill")
    .font(.system(size: AppStyle.paneControlIconSize))
    .foregroundStyle(.white.opacity(AppStyle.foregroundMuted))
    .background(Circle().fill(Color.black.opacity(AppStyle.foregroundDim)))
```
Same for `xmark.circle.fill`.

**Step 2: Update add (+) button (lines 145-181)**

Change icon font from `AppStyle.fontSmall` → `AppStyle.paneControlIconSize`, and frame to match:
```swift
Image(systemName: "plus")
    .font(.system(size: AppStyle.paneControlIconSize, weight: .bold))
    .foregroundStyle(.white.opacity(AppStyle.foregroundMuted))
    .frame(width: AppStyle.paneControlButtonSize, height: AppStyle.paneControlButtonSize + 12)
    .background(
        UnevenRoundedRectangle(
            topLeadingRadius: AppStyle.panelCornerRadius + 4,
            bottomLeadingRadius: AppStyle.panelCornerRadius + 4,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
        .fill(Color.black.opacity(AppStyle.foregroundDim))
    )
```

The quarter-moon shape is preserved but uses the same black fill opacity and icon styling.

**Step 3: Build and verify**

Run: `mise run build`
Expected: All three buttons render with consistent black backgrounds and white icons at the same size.

**Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift
git commit -m "fix: unify pane editor button styling (size, color, opacity)"
```

---

## Phase 2: Sidebar Infrastructure

### Task 4: Fix Sidebar Collapse Behavior

**Files:**
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift:55`

**Context:** Currently `collapseBehavior = .preferResizingSplitViewWithFixedSiblings` causes the window to shrink when the sidebar collapses. User wants the content area to expand and fill the space — sidebar just disappears, window stays same size.

**Step 1: Change collapse behavior**

In `MainSplitViewController.viewDidLoad()` (line 55), change:
```swift
sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
```
to:
```swift
sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
```

This tells AppKit: when the sidebar collapses/expands, resize the sibling (content area) while keeping the overall split view frame fixed.

**Step 2: Build and verify**

Run: `mise run build`
Expected: Toggling sidebar causes content area to expand/contract. Window frame stays constant.

**Step 3: Commit**

```bash
git add Sources/AgentStudio/App/MainSplitViewController.swift
git commit -m "fix: sidebar collapse expands content area instead of shrinking window"
```

---

### Task 5: Add `isMainWorktree` to Worktree Model

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Worktree.swift`
- Modify: `Sources/AgentStudio/Infrastructure/WorktrunkService.swift`
- Test: `Tests/AgentStudioTests/` (new test file for WorktrunkService parsing)

**Context:** The first entry from `git worktree list` is always the main checkout. We need a flag to distinguish it so the sidebar can show a ★ badge.

**Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Infrastructure/WorktrunkService_test.swift`:
```swift
import Testing
@testable import AgentStudio

@Suite("WorktrunkService parsing")
struct WorktrunkServiceParsingTests {
    @Test("parseGitWorktreeList marks first entry as main worktree")
    func firstEntryIsMain() {
        let output = """
            worktree /path/to/repo
            HEAD abc1234
            branch refs/heads/main

            worktree /path/to/repo-feature
            HEAD def5678
            branch refs/heads/feature-branch

            """
        let service = WorktrunkService.shared
        let worktrees = service.parseGitWorktreeList(output)

        #expect(worktrees.count == 2)
        #expect(worktrees[0].isMainWorktree == true)
        #expect(worktrees[0].branch == "main")
        #expect(worktrees[1].isMainWorktree == false)
        #expect(worktrees[1].branch == "feature-branch")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `mise run test`
Expected: FAIL — `isMainWorktree` does not exist on `Worktree`.

**Step 3: Add `isMainWorktree` field to Worktree**

In `Core/Models/Worktree.swift`, add:
```swift
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: URL
    var branch: String
    var agent: AgentType?
    var status: WorktreeStatus
    var stableKey: String
    var isMainWorktree: Bool  // ← NEW

    init(name: String, path: URL, branch: String, agent: AgentType? = nil,
         status: WorktreeStatus = .idle, isMainWorktree: Bool = false) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.branch = branch
        self.agent = agent
        self.status = status
        self.stableKey = StableKey.from(path)
        self.isMainWorktree = isMainWorktree
    }
}
```

Add `CodingKeys` with a default for backwards compatibility:
```swift
init(from decoder: Decoder) throws {
    // ... existing fields ...
    self.isMainWorktree = try container.decodeIfPresent(Bool.self, forKey: .isMainWorktree) ?? false
}
```

**Step 4: Update WorktrunkService to set `isMainWorktree`**

In `parseGitWorktreeList`, track index. First entry gets `isMainWorktree: true`:
```swift
// In the append logic, pass isMainWorktree: worktrees.isEmpty
worktrees.append(
    Worktree(
        name: name,
        path: pathURL,
        branch: branch,
        isMainWorktree: worktrees.isEmpty  // first = main
    ))
```

Same for `discoverWithWorktrunk` — mark first filtered entry as main.

**Step 5: Run test to verify it passes**

Run: `mise run test`
Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Worktree.swift \
       Sources/AgentStudio/Infrastructure/WorktrunkService.swift \
       Tests/AgentStudioTests/Infrastructure/WorktrunkService_test.swift
git commit -m "feat: add isMainWorktree flag to Worktree model"
```

---

### Task 6: Recursive Repo Discovery (Scan Folder for Git Repos)

**Files:**
- Create: `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift` (SidebarContentView.addRepo)
- Test: `Tests/AgentStudioTests/Infrastructure/RepoScanner_test.swift`

**Context:** Currently "Add Repo" opens a folder picker for a single git repo. New behavior: user selects a parent folder, scanner finds all git repos up to 3 levels deep, adds them all.

**Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Infrastructure/RepoScanner_test.swift`:
```swift
import Testing
import Foundation
@testable import AgentStudio

@Suite("RepoScanner")
struct RepoScannerTests {
    @Test("discovers git repos up to 3 levels deep")
    func discoversReposAtDepth() throws {
        // Arrange: create temp directory structure
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-test-\(UUID().uuidString)")
        let fm = FileManager.default

        // Level 1: repo-a/.git
        try fm.createDirectory(at: tmp.appending(path: "repo-a/.git"), withIntermediateDirectories: true)
        // Level 2: group/repo-b/.git
        try fm.createDirectory(at: tmp.appending(path: "group/repo-b/.git"), withIntermediateDirectories: true)
        // Level 3: org/team/repo-c/.git
        try fm.createDirectory(at: tmp.appending(path: "org/team/repo-c/.git"), withIntermediateDirectories: true)
        // Level 4 (too deep): org/team/sub/repo-d/.git
        try fm.createDirectory(at: tmp.appending(path: "org/team/sub/repo-d/.git"), withIntermediateDirectories: true)
        // Not a repo: no-git/
        try fm.createDirectory(at: tmp.appending(path: "no-git"), withIntermediateDirectories: true)

        // Act
        let scanner = RepoScanner()
        let repos = scanner.scanForGitRepos(in: tmp, maxDepth: 3)

        // Assert
        #expect(repos.count == 3)
        let names = Set(repos.map(\.lastPathComponent))
        #expect(names.contains("repo-a"))
        #expect(names.contains("repo-b"))
        #expect(names.contains("repo-c"))
        #expect(!names.contains("repo-d"))

        // Cleanup
        try? fm.removeItem(at: tmp)
    }

    @Test("does not descend into .git directories")
    func skipsGitInternals() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "scanner-skip-\(UUID().uuidString)")
        let fm = FileManager.default

        // repo/.git/modules/sub (should not be detected as separate repo)
        try fm.createDirectory(
            at: tmp.appending(path: "repo/.git/modules/sub/.git"),
            withIntermediateDirectories: true)

        let scanner = RepoScanner()
        let repos = scanner.scanForGitRepos(in: tmp, maxDepth: 3)

        #expect(repos.count == 1)
        #expect(repos[0].lastPathComponent == "repo")

        try? fm.removeItem(at: tmp)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `mise run test`
Expected: FAIL — `RepoScanner` does not exist.

**Step 3: Implement RepoScanner**

Create `Sources/AgentStudio/Infrastructure/RepoScanner.swift`:
```swift
import Foundation

/// Scans a directory tree for git repositories up to a configurable depth.
struct RepoScanner {
    /// Scans `rootURL` for directories containing a `.git` subdirectory.
    /// Stops descending into a directory once a `.git` is found (no nested repos).
    /// Skips `.git` internals, hidden directories, and symlinks.
    func scanForGitRepos(in rootURL: URL, maxDepth: Int = 3) -> [URL] {
        var repos: [URL] = []
        scanDirectory(rootURL, currentDepth: 0, maxDepth: maxDepth, results: &repos)
        return repos.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func scanDirectory(_ url: URL, currentDepth: Int, maxDepth: Int, results: inout [URL]) {
        guard currentDepth <= maxDepth else { return }

        let fm = FileManager.default
        let gitDir = url.appending(path: ".git")

        // If this directory has .git, it's a repo — don't descend further
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) {
            results.append(url)
            return
        }

        // Otherwise, scan subdirectories
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { continue }

            scanDirectory(item, currentDepth: currentDepth + 1, maxDepth: maxDepth, results: &results)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `mise run test`
Expected: PASS.

**Step 5: Update sidebar addRepo to use scanner**

In `MainSplitViewController.swift`, update `SidebarContentView.addRepo()`:
```swift
private func addRepo() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Select a folder containing git repositories"
    panel.prompt = "Add Repos"

    if panel.runModal() == .OK, let url = panel.url {
        let scanner = RepoScanner()
        let repoPaths = scanner.scanForGitRepos(in: url, maxDepth: 3)

        if repoPaths.isEmpty {
            // Fallback: treat the selected folder itself as a repo
            let repo = store.addRepo(at: url)
            let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
            store.updateRepoWorktrees(repo.id, worktrees: worktrees)
        } else {
            for repoPath in repoPaths {
                // Skip if repo already exists (by path)
                guard !store.repos.contains(where: { $0.repoPath == repoPath }) else { continue }
                let repo = store.addRepo(at: repoPath)
                let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
                store.updateRepoWorktrees(repo.id, worktrees: worktrees)
            }
        }
    }
}
```

**Step 6: Build and verify**

Run: `mise run build`
Expected: Compiles.

**Step 7: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/RepoScanner.swift \
       Sources/AgentStudio/App/MainSplitViewController.swift \
       Tests/AgentStudioTests/Infrastructure/RepoScanner_test.swift
git commit -m "feat: recursive repo discovery scans folder for git repos (max 3 levels)"
```

---

## Phase 3: Sidebar UX Overhaul

### Task 7: Sidebar Tree Redesign (Main Badge, Repo Row Actions)

**Files:**
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift` (SidebarContentView, RepoRowView, WorktreeRowView)

**Context:** Redesign sidebar to match reference app patterns (adapted to our style):
- Repo row: expand chevron, repo name, worktree count badge, `...` menu, `+` button
- Main worktree: ★ badge before name
- Other worktrees: branch icon (current `arrow.triangle.branch`)
- Indentation: keep our current level (half the reference app)
- Worktree rows show status badges (OPEN/MERGED/etc.) and +/- diff stats (future)

**Step 1: Update RepoRowView with action buttons**

```swift
struct RepoRowView: View {
    let repo: Repo
    let onAddWorktree: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            Text(repo.name)
                .font(.system(size: AppStyle.fontPrimary, weight: .medium))
                .lineLimit(1)

            Spacer()

            if isHovered {
                // Quick actions (visible on hover)
                HStack(spacing: 2) {
                    Menu {
                        Button("Refresh Worktrees") { /* notification */ }
                        Divider()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil,
                                inFileViewerRootedAtPath: repo.repoPath.path)
                        }
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(repo.repoPath.path, forType: .string)
                        }
                        Divider()
                        Button("Remove Repo", role: .destructive) { /* notification */ }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: AppStyle.fontSmall))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Button(action: onAddWorktree) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyle.fontSmall))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("New worktree")
                }
                .transition(.opacity)
            } else {
                // Worktree count badge
                Text("\(repo.worktrees.count)")
                    .font(.system(size: AppStyle.fontSmall, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
```

**Step 2: Update WorktreeRowView with main badge**

```swift
struct WorktreeRowView: View {
    let worktree: Worktree
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onOpenInPane: () -> Void  // NEW
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            // Main worktree gets star, others get branch icon
            if worktree.isMainWorktree {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(worktree.name)
                .font(.system(size: AppStyle.fontBody))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            if worktree.status != .idle {
                StatusBadgeView(status: worktree.status)
            }

            if let agent = worktree.agent {
                AgentBadgeView(agent: agent)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .contextMenu {
            Button {
                onOpenNew()
            } label: {
                Label("Open in New Tab", systemImage: "plus.rectangle")
            }

            Button {
                onOpenInPane()
            } label: {
                Label("Open in Pane (Split)", systemImage: "rectangle.split.2x1")
            }

            Divider()

            Button {
                onOpen()
            } label: {
                Label("Go to Terminal", systemImage: "terminal")
            }

            Button {
                openInCursor()
            } label: {
                Label("Open in Cursor", systemImage: "cursorarrow.rays")
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                copyPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
            }
        }
    }

    // ... existing helper methods ...
}
```

**Step 3: Build and verify**

Run: `mise run build`
Expected: Compiles. Sidebar shows ★ on main worktrees, hover shows repo actions.

**Step 4: Commit**

```bash
git add Sources/AgentStudio/App/MainSplitViewController.swift
git commit -m "feat: sidebar redesign with main worktree badge and repo action buttons"
```

---

### Task 8: Double-Click Deduplication + Open-in-Pane Action

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneAction.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Registry/RuntimeRegistry.swift` (add worktree query)
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift` (sidebar handlers)
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistry_test.swift`

**Context:** Double-clicking a worktree should open a new tab UNLESS that worktree already has an open pane — then switch to its tab. Query `RuntimeRegistry` + `PaneMetadata.worktreeId` for deduplication (not session models). Context menu provides both "Open in Tab" and "Open in Pane (Split)".

**Step 1: Write the failing test for RuntimeRegistry worktree lookup**

```swift
import Testing
@testable import AgentStudio

@Suite("RuntimeRegistry worktree lookup")
struct RuntimeRegistryWorktreeLookupTests {
    @Test("findPaneWithWorktree returns paneId when worktree is registered")
    func findsExistingWorktree() async {
        // Arrange
        let registry = RuntimeRegistry()
        let paneId = PaneId()
        let worktreeId = UUID()
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            source: .worktree(worktreeId: worktreeId, repoId: UUID()),
            title: "test"
        )
        let mockRuntime = MockPaneRuntime(paneId: paneId, metadata: metadata)
        registry.register(mockRuntime)

        // Act
        let found = registry.findPaneWithWorktree(worktreeId: worktreeId)

        // Assert
        #expect(found == paneId)
    }

    @Test("findPaneWithWorktree returns nil for unknown worktree")
    func returnsNilForUnknown() {
        let registry = RuntimeRegistry()
        #expect(registry.findPaneWithWorktree(worktreeId: UUID()) == nil)
    }
}
```

**Step 2: Run test — expect fail**

Run: `mise run test`
Expected: FAIL — `findPaneWithWorktree` doesn't exist.

**Step 3: Add `findPaneWithWorktree` to RuntimeRegistry**

```swift
/// Find a pane whose metadata source has the given worktreeId.
/// Returns the first matching PaneId, or nil.
func findPaneWithWorktree(worktreeId: UUID) -> PaneId? {
    for (paneId, runtime) in runtimes {
        if runtime.metadata.source.worktreeId == worktreeId {
            return paneId
        }
    }
    return nil
}
```

**Step 4: Run test — expect pass**

Run: `mise run test`
Expected: PASS.

**Step 5: Wire deduplication into PaneCoordinator**

`PaneCoordinator` uses `RuntimeRegistry.findPaneWithWorktree` to check if the worktree is already open. If found, resolve to `.selectTab` for the tab containing that pane. If not found, proceed with new tab/pane creation.

The coordinator queries `WorkspaceStore` to find which tab contains the pane (by paneId → tab layout lookup).

**Step 6: Update sidebar double-click handler**

In `SidebarContentView`, the `onOpen` closure for `WorktreeRowView` becomes:
```swift
onOpen: {
    // Post notification — PaneCoordinator handles deduplication
    NotificationCenter.default.post(
        name: .openWorktreeRequested,
        object: nil,
        userInfo: ["worktree": worktree, "repo": repo, "deduplicateTab": true]
    )
}
```

**Step 7: Add `openInPane` notification and handler**

Add to notification names:
```swift
static let openWorktreeInPaneRequested = Notification.Name("openWorktreeInPaneRequested")
```

Handle in `MainSplitViewController`:
```swift
notificationTasks.append(
    Task { [weak self] in
        for await notification in NotificationCenter.default.notifications(named: .openWorktreeInPaneRequested) {
            guard let self, !Task.isCancelled else { break }
            self.handleOpenWorktreeInPane(notification)
        }
    })

private func handleOpenWorktreeInPane(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
        let worktree = userInfo["worktree"] as? Worktree,
        let repo = userInfo["repo"] as? Repo
    else { return }
    paneTabViewController?.openTerminalInPane(for: worktree, in: repo)
}
```

**Step 8: Ensure pane creation populates full PaneMetadata**

When creating any pane from sidebar (either new tab or split), build `PaneMetadata` with all dynamic view fields:
```swift
let metadata = PaneMetadata(
    paneId: PaneId(),
    contentType: .terminal,
    source: .worktree(worktreeId: worktree.id, repoId: repo.id),
    title: worktree.name,
    cwd: worktree.path,
    repoId: repo.id,
    worktreeId: worktree.id,
    parentFolder: worktree.path.deletingLastPathComponent().lastPathComponent,
    checkoutRef: worktree.branch
)
```

This ensures dynamic views can group by repo, worktree, branch, and folder.

**Step 9: Build and verify**

Run: `mise run build`
Expected: Compiles.

**Step 10: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Registry/RuntimeRegistry.swift \
       Sources/AgentStudio/App/PaneCoordinator.swift \
       Sources/AgentStudio/App/MainSplitViewController.swift \
       Tests/AgentStudioTests/
git commit -m "feat: double-click deduplication via RuntimeRegistry + open-in-pane"
```

---

## Phase 4: Duplicate & New Tab/Pane Enhancements

### Task 9: Add Duplicate PaneActions (using PaneId)

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneAction.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionValidator_test.swift`

**Context:** New actions for duplicating tabs and panes. These are the first `PaneAction` cases to use `PaneId` (not raw `UUID`) for pane identity. "Duplicate tab" creates a new tab with the same split layout, spawning new sessions with fully-populated `PaneMetadata`. "Duplicate pane" splits the focused pane and creates a new session with the same source and metadata.

**Step 1: Add PaneAction cases with `PaneId`**

```swift
// In PaneAction enum:
/// Duplicate an entire tab's layout with new sessions for each pane.
/// Each new pane gets a fresh PaneId and PaneMetadata cloned from the source.
case duplicateTab(tabId: UUID)
/// Duplicate a pane by splitting and creating a new session with the same source.
/// Uses PaneId (not UUID) for pane identity — first case to use the new contract.
case duplicatePane(tabId: UUID, paneId: PaneId, direction: SplitNewDirection)
```

Note: `tabId` stays `UUID` (tabs are not panes). `paneId` uses `PaneId` struct.

**Step 2: Write failing tests**

```swift
@Test("duplicateTab validates with existing tab")
func duplicateTabValid() {
    let snapshot = makeSnapshotWithTab(tabId: testTabId)
    let result = ActionValidator.validate(.duplicateTab(tabId: testTabId), state: snapshot)
    #expect(result.isSuccess)
}

@Test("duplicatePane validates with existing pane in tab")
func duplicatePaneValid() {
    let testPaneId = PaneId(uuid: UUID())
    let snapshot = makeSnapshotWithPane(tabId: testTabId, paneId: testPaneId.uuid)
    let result = ActionValidator.validate(
        .duplicatePane(tabId: testTabId, paneId: testPaneId, direction: .right),
        state: snapshot
    )
    #expect(result.isSuccess)
}

@Test("duplicatePane fails when tab not found")
func duplicatePaneInvalidTab() {
    let snapshot = ActionStateSnapshot(tabs: [], activeTabId: nil, isManagementModeActive: false)
    let result = ActionValidator.validate(
        .duplicatePane(tabId: UUID(), paneId: PaneId(), direction: .right),
        state: snapshot
    )
    #expect(result.isFailure)
}
```

**Step 3: Run tests — expect fail**

Run: `mise run test`
Expected: FAIL — cases don't exist.

**Step 4: Implement ActionValidator handling**

Add switch cases in `ActionValidator.validate`. Note: `ActionStateSnapshot` currently uses `UUID` for pane lookups, so bridge via `.uuid`:
```swift
case .duplicateTab(let tabId):
    guard state.tab(tabId) != nil else {
        return .failure(.tabNotFound(tabId: tabId))
    }
    return .success(ValidatedAction(action))

case .duplicatePane(let tabId, let paneId, _):
    guard let tab = state.tab(tabId) else {
        return .failure(.tabNotFound(tabId: tabId))
    }
    guard tab.paneIds.contains(paneId.uuid) else {
        return .failure(.paneNotFound(paneId: paneId.uuid, tabId: tabId))
    }
    return .success(ValidatedAction(action))
```

**Step 5: Implement PaneCoordinator execution**

`executeDuplicateTab(tabId:)`:
1. Get source tab's layout
2. For each leaf pane: query `RuntimeRegistry` for its `PaneMetadata`
3. Create new `PaneId()` for each leaf (UUIDv7)
4. Build new `PaneMetadata` for each — clone source metadata but with new `paneId`, `createdAt: Date()`
5. Build a new layout tree with same split structure but new pane IDs
6. Create new tab, insert after source tab
7. Register new runtimes in `RuntimeRegistry`

`executeDuplicatePane(tabId:, paneId:, direction:)`:
1. Query `RuntimeRegistry.runtime(for: paneId)` to get source metadata
2. Create new `PaneId()` and clone metadata with new identity
3. Reuse existing `insertPane` logic with `.newTerminal` source
4. Register new runtime

**Key: Full PaneMetadata on duplicate:**
```swift
let sourceMetadata = registry.runtime(for: sourcePaneId)!.metadata
let newPaneId = PaneId()
let newMetadata = PaneMetadata(
    paneId: newPaneId,
    contentType: sourceMetadata.contentType,
    source: sourceMetadata.source,
    createdAt: Date(),
    title: sourceMetadata.title,
    cwd: sourceMetadata.cwd,
    repoId: sourceMetadata.repoId,
    worktreeId: sourceMetadata.worktreeId,
    parentFolder: sourceMetadata.parentFolder,
    checkoutRef: sourceMetadata.checkoutRef,
    agentType: sourceMetadata.agentType,
    tags: sourceMetadata.tags
)
```

**Step 6: Run tests — expect pass**

Run: `mise run test`
Expected: PASS.

**Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Actions/PaneAction.swift \
       Sources/AgentStudio/Core/Actions/ActionResolver.swift \
       Sources/AgentStudio/Core/Actions/ActionValidator.swift \
       Sources/AgentStudio/App/PaneCoordinator.swift \
       Tests/AgentStudioTests/
git commit -m "feat: add duplicateTab and duplicatePane actions (PaneId, full PaneMetadata)"
```

---

### Task 10: Duplicate Button in Tab Bar

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/CustomTabBar.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`

**Context:** Add a duplicate button next to the arrangement button in the tab bar. Click = duplicate tab. Right-click/long-press menu = option to duplicate focused pane.

**Step 1: Create DuplicateTabButton**

In `CustomTabBar.swift`, add a new private view (after `TabBarArrangementButton`):

```swift
private struct TabBarDuplicateButton: View {
    let adapter: TabBarAdapter
    let onDuplicateTab: () -> Void
    let onDuplicatePane: () -> Void
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Duplicate Tab") { onDuplicateTab() }
            Button("Duplicate Focused Pane") { onDuplicatePane() }
        } label: {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyle.toolbarButtonSize, height: AppStyle.toolbarButtonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
                )
                .contentShape(Circle())
        } primaryAction: {
            onDuplicateTab()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Duplicate Tab")
    }
}
```

**Step 2: Wire into CustomTabBar**

Add callback props to `CustomTabBar`:
```swift
var onDuplicateTab: (() -> Void)?
var onDuplicatePane: (() -> Void)?
```

Insert the button between arrangement and scroll area in the `HStack`:
```swift
// After TabBarArrangementButton:
if let onDuplicateTab, let onDuplicatePane {
    TabBarDuplicateButton(
        adapter: adapter,
        onDuplicateTab: onDuplicateTab,
        onDuplicatePane: onDuplicatePane
    )
}
```

**Step 3: Wire in PaneTabViewController**

Pass the callbacks from `PaneTabViewController` where it creates the `CustomTabBar`:
```swift
onDuplicateTab: { [weak self] in
    guard let self, let tabId = self.store.activeTabId else { return }
    self.executor.execute(.duplicateTab(tabId: tabId))
},
onDuplicatePane: { [weak self] in
    guard let self,
          let tabId = self.store.activeTabId,
          let paneId = self.store.activeTab?.activeSessionId
    else { return }
    self.executor.execute(.duplicatePane(tabId: tabId, paneId: paneId, direction: .right))
}
```

**Step 4: Build and verify**

Run: `mise run build`
Expected: Compiles. Duplicate button appears next to arrangement button.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/CustomTabBar.swift \
       Sources/AgentStudio/App/Panes/PaneTabViewController.swift
git commit -m "feat: add duplicate button to tab bar (click=tab, menu=pane)"
```

---

### Task 11: New Tab/Pane Button Options with CommandBar Scope

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/CustomTabBar.swift` (NewTabButton context menu)
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift` (new scope)
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` (repo/worktree items)
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift` (+ button context menu)
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSource_test.swift`

**Context:** The + button (new tab) and the quarter-moon + button (new pane) should offer options: Empty Terminal, Open Repo (list repos → worktrees), Open via ⌘P (scoped to repos). CommandBar gets a new `.repos` scope that shows repos → worktrees.

**Step 1: Add `.repos` scope to CommandBar**

In `CommandBarState.swift`, the scope enum (likely `CommandBarScope`):
```swift
case repos  // Shows repos and worktrees for opening
```

**Step 2: Write failing test for repo scope data source**

```swift
@Test("repos scope builds items from store repos")
func reposScopeItems() {
    let store = makeTestStoreWithRepos()
    let dataSource = CommandBarDataSource(store: store, dispatcher: mockDispatcher)
    let items = dataSource.items(for: .repos, query: "")

    #expect(!items.isEmpty)
    // Should have repo groups with worktree items
    #expect(items.contains { $0.title == "main" })
}
```

**Step 3: Run test — expect fail**

**Step 4: Implement CommandBarDataSource for `.repos` scope**

Build items from `store.repos`:
- Each repo is a group header
- Each worktree is a selectable item with action `.custom { openWorktree(worktree, in: repo) }`
- Main worktree shows ★ prefix

**Step 5: Update NewTabButton with context menu**

```swift
private struct NewTabButton: View {
    let onAdd: () -> Void
    let onOpenRepoInTab: (() -> Void)?  // Opens CommandBar scoped to repos
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Empty Terminal") { onAdd() }
            Divider()
            Button("Open Repo/Worktree...") {
                onOpenRepoInTab?()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyle.toolbarButtonSize, height: AppStyle.toolbarButtonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
                )
                .contentShape(Circle())
        } primaryAction: {
            onAdd()  // Default click = empty terminal (existing behavior)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("New Tab")
    }
}
```

**Step 6: Same pattern for the quarter-moon + button in TerminalPaneLeaf**

Convert the editor mode + button to a Menu with primaryAction:
- Default click: insert new terminal (existing behavior)
- Menu options: "Empty Terminal", "Open Repo/Worktree..." (opens CommandBar scoped)

**Step 7: Wire `onOpenRepoInTab` to show CommandBar with `.repos` scope**

Through the callback chain: `CustomTabBar` → `PaneTabViewController` → `CommandBarPanelController.show(scope: .repos)`

**Step 8: Run tests — expect pass**

Run: `mise run test`
Expected: PASS.

**Step 9: Build and verify**

Run: `mise run build`
Expected: Compiles. + button shows menu on right-click, default click creates empty terminal.

**Step 10: Commit**

```bash
git add Sources/AgentStudio/Core/Views/CustomTabBar.swift \
       Sources/AgentStudio/Core/Views/Splits/TerminalPaneLeaf.swift \
       Sources/AgentStudio/Features/CommandBar/CommandBarState.swift \
       Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift \
       Tests/AgentStudioTests/
git commit -m "feat: new tab/pane button options with CommandBar repos scope"
```

---

## Summary

| Phase | Tasks | What Changes |
|-------|-------|--------------|
| **1. Pane Editor Fixes** | 1-3 | Drag handle 60×100, block pane interaction, unify button styling |
| **2. Sidebar Infra** | 4-6 | Collapse behavior, `isMainWorktree` flag, recursive repo scanner |
| **3. Sidebar UX** | 7-8 | Tree redesign with badges/actions, double-click dedup, open-in-pane |
| **4. Tab Bar** | 9-11 | Duplicate actions, duplicate button, + button options + CommandBar scope |

**Key architectural constraints:**
- All user actions flow through `PaneAction` → `ActionResolver` → `ActionValidator` → `PaneCoordinator` → `WorkspaceStore`
- **New `PaneAction` cases use `PaneId`** (struct, UUIDv7) for pane identity — first cases to use the pane runtime contract
- **All pane creation populates full `PaneMetadata`** — `repoId`, `worktreeId`, `checkoutRef`, `parentFolder`, `agentType`, `tags` — for dynamic views and window restoration
- **Deduplication queries `RuntimeRegistry`** via `PaneMetadata.worktreeId` — not session models
- New `RepoScanner` lives in `Infrastructure/` (no feature imports)
- `isMainWorktree` is a model-level field, backwards-compatible via `decodeIfPresent`
- CommandBar `.repos` scope reuses existing `Features/CommandBar/` scoping mechanism
- Pane runtime contract types (`PaneId`, `PaneMetadata`, `RuntimeRegistry`) already exist in `Core/PaneRuntime/` — this plan extends them with queries, does not restructure

**Directory placement:**
| New File | Location | Why |
|----------|----------|-----|
| `RepoScanner.swift` | `Infrastructure/` | Domain-agnostic FS utility, no feature imports |
| `RuntimeRegistry` query | `Core/PaneRuntime/Registry/` | Extends existing registry with worktree lookup |
| Sidebar views | `App/MainSplitViewController.swift` | Vertical slice — crosses features, stays in App/ |
| CommandBar scope | `Features/CommandBar/` | Feature-scoped, extends existing scoping |
| Duplicate actions | `Core/Actions/` | Shared action type, not feature-specific |
