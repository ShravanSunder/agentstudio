# Onboarding Welcome Flow

## Problem

The first-launch experience doesn't communicate what AgentStudio does or what scanning a folder means. The welcome screen is sparse — a faux-window card repeating the app name, redundant text blocks, and a small CTA buried at the bottom. There's no transition feedback when scanning starts, no indication of progress, and no explanation of the worktree-centric sidebar model that makes the app valuable.

## Design

Three-state onboarding flow with animated transitions between states. Each state maps to a `WorkspaceEmptyStateKind` enum case.

### State 1: Welcome (cold start)

**Conditions:** `store.repos.isEmpty` and not scanning.
**Sidebar:** Collapsed (`NSSplitViewItem.isCollapsed = true`).

**Content area layout — horizontal split, vertically centered:**

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   ┌─────────────────────┐                                    │
│   │                     │        [App Icon 56pt]             │
│   │  ▾ react   facebook │                                    │
│   │    ★ react          │     Welcome to AgentStudio         │
│   │      ⎇ main        │     A terminal workspace           │
│   │    ⟲ react.conc..  │     for your repos.                │
│   │      ⎇ feature/... │                                    │
│   │      +42 -8● ↑2 ↓1 │     Point at a parent folder —    │
│   │                     │     AgentStudio discovers every    │
│   │  ▾ uv    astral-sh  │     repo and worktree inside.     │
│   │    ★ uv             │                                    │
│   │      ⎇ main        │     [Choose a Folder to Scan…]     │
│   │    ⟲ uv.fix-res..  │              ⌘⌥⇧O                  │
│   │      ⎇ fix/resolv. │                                    │
│   │      +12-3  PR1 🔔2 │                                    │
│   │                     │                                    │
│   │  ▸ ghostty          │                                    │
│   └─────────────────────┘                                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

The horizontal layout uses the window width instead of stacking vertically. The illustration on the left foreshadows the sidebar; the text and CTA on the right are clean and breathable.

**App icon:** Existing `AppLogoTransparent.svg` via `AppLogoView` at 56pt. Smaller than before — the illustration is the visual anchor, not the icon.

**Title + subtitle:** Left-aligned on the right side. Title: "Welcome to AgentStudio". Subtitle: "A terminal workspace for your repos." — one line.

**Explanation:** One sentence of muted text: "Point at a parent folder — AgentStudio discovers every repo and worktree inside."

**Sidebar preview illustration:** A static SwiftUI view (`WelcomeSidebarIllustration`) positioned on the left side of the horizontal layout. Mimics the real sidebar structure using well-known open-source repos. Non-interactive, ~300pt wide. Uses the app's accent colors for checkout icons and status chips.

Content:

| Group | Org | Worktrees (checkout title → branch) | Notable status |
|-------|-----|--------------------------------------|----------------|
| react | facebook | ★ `react` → `main` (clean, synced); ⟲ `react.concurrent-mode` → `feature/concurrent-mode` (+42 -8 ●, ↑2 ↓1, PR 1) | Dirty indicator, ahead/behind, PR count |
| uv | astral-sh | ★ `uv` → `main` (clean, synced); ⟲ `uv.fix-resolver` → `fix/resolver-perf` (+12 -3, ↑1 ↓0, PR 1, 🔔 2) | Notification count |
| ghostty | ghostty-org | Collapsed (▸) | Shows collapsible groups |

Checkout titles use the `wt` (worktrunk) naming convention: main worktree is the repo folder name (`react`, `uv`), additional worktrees are `repo.branch-slug` (`react.concurrent-mode`, `uv.fix-resolver`). Branch names appear on a separate row below the checkout title, matching the real sidebar layout.

Each worktree row shows:
- Checkout type icon (★ main, ⟲ worktree) with accent color
- Checkout title (folder name)
- Branch icon + branch name (second row)
- Status chip row: diff (+/-), sync (↑↓), PR count, notification bell

The illustration is contained in a card with `RoundedRectangle` background (`fillMuted` opacity), border (`fillActive` opacity), max width ~400pt. Sized to show the structure without dominating the screen.

Below the illustration, a single line of muted text: "Point at a parent folder — AgentStudio discovers every repo and worktree inside."

**CTA button:** "Choose a Folder to Scan…" — `.borderedProminent`, `.controlSize(.large)`. Left-aligned with text. Triggers `CommandDispatcher.shared.dispatch(.addFolder)`.

**Shortcut hint:** "⌘⌥⇧O" in muted small text below the button.

**Layout implementation:** `HStack` with `alignment: .center`, illustration on leading side (fixed ~300pt width), text/CTA on trailing side (flexible). Outer container centers the `HStack` within the content area. Max total width ~820pt.

### Transition: Welcome → Scanning

- Content area cross-fades (SwiftUI `.transition(.opacity)`, duration 0.25s)
- Sidebar expands via `NSSplitViewItem.isCollapsed = false` (native AppKit animation, triggered from `AppDelegate.handleAddFolderRequested` which already calls `expandSidebar()`)

### State 2: Scanning

**Conditions:** Scanning in progress (between `refreshWatchedFolders` call and return).
**Sidebar:** Expanded, showing "Scanning…" section header (existing `SidebarLoadingSectionHeaderRow`) with repos appearing as discovered.

**Content area layout (vertically centered):**

```
           ◌  (spinning)

        Scanning ~/dev

   Found 3 repositories so far…
   Repos appear in the sidebar
   as they're discovered.

   ─────────────────────────────

   ⌘T  Open a terminal tab
       anytime — no need to wait.
```

**Spinner:** SF Symbol with `.symbolEffect(.rotate)` — native macOS 14+ animation. Candidate symbol: `arrow.trianglehead.2.counterclockwise` or `progress.indicator` if available, otherwise a simple `ProgressView()` circular style.

**Folder path:** "Scanning ~/dev" — display the user-selected folder path, abbreviated with `~` for home directory. Passed via `WorkspaceEmptyStateKind.scanning(URL)`.

**Live repo count:** "Found N repositories so far…" — reads `store.repos.count` reactively. When count is 0, shows "Looking for repositories…" instead.

**Hint text:** Below a subtle divider (`Color.white.opacity(fillSubtle)`, 1pt), show "⌘T" in accent color + "Open a terminal tab anytime — no need to wait." in secondary text. This communicates that the user isn't blocked.

### Transition: Scanning → Launcher

- Content area cross-fades when `refreshWatchedFolders` returns
- If zero repos found: existing "No Git Repositories Found" alert fires (already implemented in `AppDelegate`), state returns to `.noFolders`
- If repos found: state transitions to `.launcher`
- Sidebar already expanded, no change

### State 3: Launcher

**Conditions:** `!store.repos.isEmpty` and `store.tabs.isEmpty`.
**Sidebar:** Expanded with fully enriched repos.

**Content area layout (vertically centered):**

```
        Workspace Ready
   Open a recent worktree, or
   pick one from the sidebar.

   Recent              Open All ▸
   ┌──────────┐ ┌──────────┐
   │ repo-a   │ │ repo-b   │
   │ ⎇ branch │ │ ⎇ branch │
   └──────────┘ └──────────┘
```

**No "Add Folder" button.** The toolbar already has the Add Folder button (⌘⌥⇧O). Duplicating it here adds clutter. Users who need to scan more folders use the toolbar.

**Recent cards:** Existing `WorkspaceRecentCardView` grid, unchanged. Shows up to 6 recent worktrees/CWDs with icons, branch names, and status chips.

**Empty recents:** If no recent targets exist, show existing `WorkspaceRecentPlaceholderCard` with dashed border.

## Model Changes

### WorkspaceEmptyStateKind

```swift
enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case scanning(URL)  // new — carries scanned folder path
    case launcher
}
```

### WorkspaceEmptyStateModel

Add `scanningFolderPath` derived property:

```swift
var scanningFolderPath: URL? {
    if case .scanning(let url) = kind { return url }
    return nil
}
```

### WorkspaceLauncherProjector

New projection logic:

```swift
static func project(
    store: WorkspaceStore,
    repoCache: WorkspaceRepoCache,
    scanningFolderPath: URL?  // new parameter
) -> WorkspaceEmptyStateModel {
    if let path = scanningFolderPath {
        return WorkspaceEmptyStateModel(kind: .scanning(path), recentCards: [])
    }
    if store.repos.isEmpty {
        return WorkspaceEmptyStateModel(kind: .noFolders, recentCards: [])
    }
    // ... existing launcher logic
}
```

### Scanning state lifecycle

The scanning state is a `scanningPath: URL?` property on `WorkspaceStore` (not a separate store — one property doesn't justify a new injectable). Set before calling `refreshWatchedFolders`, cleared when it returns.

```swift
// On WorkspaceStore
private(set) var scanningPath: URL?

func beginScan(_ path: URL) { scanningPath = path }
func endScan() { scanningPath = nil }
```

`PaneTabViewController` already observes `WorkspaceStore`, so no new injection needed.

### Sidebar auto-collapse

In `AppDelegate` or `MainSplitViewController`, after initial load:
- If `store.repos.isEmpty` and `scanningPath == nil` → collapse sidebar
- Scanning start → expand sidebar (already happens via `expandSidebar()` in `handleAddFolderRequested`)

This is a one-time boot behavior, not a reactive binding. Once the user manually toggles the sidebar, their preference persists.

## New Views

### WelcomeSidebarIllustration

A private SwiftUI view in `WorkspaceEmptyStateView.swift` (or a separate file if it exceeds ~100 lines).

Renders a static, non-interactive mockup of the sidebar showing:
- 3 repo groups (react/facebook, uv/astral-sh, ghostty/ghostty-org)
- 2 expanded with worktrees, 1 collapsed
- Each worktree shows: checkout icon, title, branch row, status chips
- Uses real `AppStyle` constants for sizing and spacing
- Uses real octicon/SF Symbol assets for icons
- Contained in a rounded rect card with `fillMuted` background and `fillActive` border
- Max width ~400pt, height determined by content

The illustration uses simplified inline views (not the actual `SidebarWorktreeRow`) to avoid coupling to interactive behavior (hover, context menus, tap gestures). It mirrors the visual structure only.

### ScanningContentView

The content shown during State 2. Either a private view in `WorkspaceEmptyStateView.swift` or extracted if large.

- Spinner: `ProgressView().controlSize(.regular)` or SF Symbol with `.symbolEffect(.rotate)`
- Folder path display with `~` abbreviation
- Live repo count from `store.repos.count`
- Divider + ⌘T keyboard hint

## Transitions

All transitions happen within the SwiftUI `WorkspaceEmptyStateView` via the existing `.animation(.easeInOut(duration: 0.25), value: model.kind)` modifier.

Each state branch gets an explicit `.id()` for SwiftUI structural identity:
- `.id("noFolders")` with `.transition(.opacity)`
- `.id("scanning")` with `.transition(.opacity)`
- `.id("launcher")` with `.transition(.opacity.combined(with: .move(edge: .bottom)))`

The sidebar expand/collapse is handled by AppKit outside the SwiftUI view hierarchy — no cross-boundary animation choreography needed.

## What's NOT Changing

- Toolbar "Add Folder" button — unchanged, always visible
- Sidebar `SidebarLoadingSectionHeaderRow` scanning indicator — unchanged, still shows during scan
- `WorkspaceRecentCardView` — unchanged
- `WorkspaceRecentPlaceholderCard` — unchanged
- `PaneTabEmptyStateViewFactory` — signature gains `repoCount` parameter
- Command dispatch flow — `CommandDispatcher.shared.dispatch(.addFolder)` routing unchanged
- Folder picker (`NSOpenPanel`) — unchanged
- `refreshWatchedFolders` scanning pipeline — unchanged
- `RepoScanner` filesystem traversal — unchanged

## File Impact

| File | Change |
|------|--------|
| `WorkspaceEmptyStateView.swift` | Replace `folderIntakeBody` with horizontal layout (illustration + CTA), add `scanningBody`, add `WelcomeSidebarIllustration`, remove `WorkspaceHomeIntroCard` (already done), remove `launcherBody` "Add Folder" button |
| `WorkspaceLauncherProjector.swift` | Add `.scanning` projection using `store.scanningPath` |
| `WorkspaceStore.swift` | Add `scanningPath: URL?` property with `beginScan`/`endScan` methods |
| `PaneTabViewController.swift` | Pass `store.scanningPath` to projector (already observes store) |
| `AppDelegate.swift` | Set/clear `store.scanningPath` around `refreshWatchedFolders` call, auto-collapse sidebar on boot if no repos |

### Edge cases

- **Folder picker cancelled:** No state change, stay on welcome.
- **Repeat scan from launcher:** Stay on launcher; sidebar's "Scanning…" indicator is sufficient. Only show scanning content when no repos exist yet.
- **Sidebar auto-collapse on boot:** Force-collapse if `repos.isEmpty`, regardless of persisted `sidebarCollapsed` preference. Once user manually toggles, their preference persists.
- **Zero repos after scan:** Existing "No Git Repositories Found" alert fires, state returns to `.noFolders`.
