# Extract Sidebar Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract private sidebar row/chip components from the monolithic `RepoSidebarContentView.swift` into composable, reusable views, then use them in the welcome screen illustration to guarantee pixel-identical rendering with the real sidebar.

**Architecture:** Move `SidebarWorktreeRow`, `SidebarResolvedGroupHeaderRow`, `SidebarGroupRow`, chip views, and supporting types out of `RepoSidebarContentView.swift` into focused files in `Features/Sidebar/`. Drop `private`. Update imports. Rewrite `WelcomeSidebarIllustration` to use the real components with mock `Worktree` data and no-op callbacks. Delete the duplicate `WorkspaceStatusChips.swift` chip views that were broken (loaded from nonexistent `SidebarIcons.xcassets`).

**Tech Stack:** SwiftUI, AppKit (NSColor extension), existing AppStyle constants, OcticonImage

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Features/Sidebar/SidebarChips.swift` | **Create** | `SidebarChip`, `SidebarDiffChip`, `SidebarStatusSyncChip` — chip views + `SidebarChip.Style` enum |
| `Features/Sidebar/SidebarWorktreeRow.swift` | **Create** | `SidebarWorktreeRow`, `SidebarCheckoutIconKind` enum |
| `Features/Sidebar/SidebarGroupHeader.swift` | **Create** | `SidebarGroupRow`, `SidebarResolvedGroupHeaderRow` |
| `Features/Sidebar/RepoSidebarContentView.swift` | **Modify** | Remove extracted components, import from new files |
| `Infrastructure/Extensions/NSColor+Hex.swift` | **Create** | `NSColor(hex:)` and `hexString` extension (currently fileprivate in sidebar) |
| `App/Panes/WelcomeSidebarIllustration.swift` | **Rewrite** | Use real `SidebarResolvedGroupHeaderRow` + `SidebarWorktreeRow` with mock data |
| `Core/Views/WorkspaceStatusChips.swift` | **Modify** | Delete dead `WorkspaceDiffChip`, `WorkspaceStatusSyncChip`, `WorkspaceStatusChip` views that duplicate sidebar chips. Keep `WorkspaceStatusChipsModel` and `WorkspaceStatusChipRow` but rewrite internals to delegate to the extracted sidebar chips |

---

### Task 1: Extract NSColor+Hex extension

**Files:**
- Create: `Sources/AgentStudio/Infrastructure/Extensions/NSColor+Hex.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`

The `NSColor(hex:)` init and `hexString` computed property are currently `fileprivate` at the bottom of `RepoSidebarContentView.swift` (lines 1461-1478). Move them to a standalone extension file so they're usable app-wide.

- [ ] **Step 1: Create NSColor+Hex.swift**

Create `Sources/AgentStudio/Infrastructure/Extensions/NSColor+Hex.swift`:

```swift
import AppKit

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat(value & 0xff) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        let red = Int((rgb.redComponent * 255.0).rounded())
        let green = Int((rgb.greenComponent * 255.0).rounded())
        let blue = Int((rgb.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
```

- [ ] **Step 2: Remove the fileprivate extension from RepoSidebarContentView.swift**

Delete lines 1461-1478 (the `extension NSColor { ... }` block with `fileprivate` inits) from `RepoSidebarContentView.swift`. Also remove the `// swiftlint:enable file_length` comment if it follows immediately.

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10` (timeout 60000ms)
Expected: `Build complete!` — the sidebar code already uses `NSColor(hex:)` and removing `fileprivate` + adding the new file should resolve identically.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/Extensions/NSColor+Hex.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git commit -m "refactor: extract NSColor+Hex extension to Infrastructure"
```

---

### Task 2: Extract sidebar chip views

**Files:**
- Create: `Sources/AgentStudio/Features/Sidebar/SidebarChips.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`

Move `SidebarChip` (with its `Style` enum), `SidebarDiffChip`, and `SidebarStatusSyncChip` from `RepoSidebarContentView.swift` into their own file. Drop `private`.

- [ ] **Step 1: Create SidebarChips.swift**

Create `Sources/AgentStudio/Features/Sidebar/SidebarChips.swift` with the three chip structs copied verbatim from `RepoSidebarContentView.swift` lines 783-932, but with `private` removed from all three struct declarations. Keep all internal computed properties and methods as-is.

The file should contain:
- `struct SidebarChip: View` (with nested `enum Style`)
- `struct SidebarStatusSyncChip: View`
- `struct SidebarDiffChip: View`

Add `import SwiftUI` at the top.

- [ ] **Step 2: Remove the chip structs from RepoSidebarContentView.swift**

Delete the following from `RepoSidebarContentView.swift`:
- `private struct SidebarChip: View { ... }` (lines 783-837)
- `private struct SidebarStatusSyncChip: View { ... }` (lines 839-878)
- `private struct SidebarDiffChip: View { ... }` (lines 880-932)

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10` (timeout 60000ms)
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/SidebarChips.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git commit -m "refactor: extract sidebar chip views to SidebarChips.swift"
```

---

### Task 3: Extract SidebarWorktreeRow and SidebarCheckoutIconKind

**Files:**
- Create: `Sources/AgentStudio/Features/Sidebar/SidebarWorktreeRow.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`

Move `SidebarCheckoutIconKind` enum and `SidebarWorktreeRow` struct out. Drop `private`. The row references `SidebarChip`, `SidebarDiffChip`, `SidebarStatusSyncChip` (extracted in Task 2), `OcticonImage`, `AppStyle`, `GitBranchStatus`, `Worktree`, and `ExternalWorkspaceOpener`.

- [ ] **Step 1: Create SidebarWorktreeRow.swift**

Create `Sources/AgentStudio/Features/Sidebar/SidebarWorktreeRow.swift` containing:
- `enum SidebarCheckoutIconKind` (copied from line 777-781, drop `private`)
- `struct SidebarWorktreeRow: View` (copied from lines 531-728, drop `private`)

Add `import SwiftUI` at the top.

All private computed properties (`syncCounts`, `hasSyncSignal`, `lineDiffCounts`, `checkoutTypeIcon`) and the `openInCursor()` method stay as `private` within the struct — only the struct itself becomes non-private.

- [ ] **Step 2: Remove from RepoSidebarContentView.swift**

Delete `private enum SidebarCheckoutIconKind` (lines 777-781) and `private struct SidebarWorktreeRow: View` (lines 531-728) from `RepoSidebarContentView.swift`.

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10` (timeout 60000ms)
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/SidebarWorktreeRow.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git commit -m "refactor: extract SidebarWorktreeRow to own file"
```

---

### Task 4: Extract SidebarGroupHeader views

**Files:**
- Create: `Sources/AgentStudio/Features/Sidebar/SidebarGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`

Move `SidebarGroupRow` and `SidebarResolvedGroupHeaderRow`.

- [ ] **Step 1: Create SidebarGroupHeader.swift**

Create `Sources/AgentStudio/Features/Sidebar/SidebarGroupHeader.swift` containing:
- `struct SidebarGroupRow: View` (from lines 473-508, drop `private`)
- `struct SidebarResolvedGroupHeaderRow: View` (from lines 510-529, drop `private`)

Add `import SwiftUI` at the top.

- [ ] **Step 2: Remove from RepoSidebarContentView.swift**

Delete `private struct SidebarGroupRow` (lines 473-508) and `private struct SidebarResolvedGroupHeaderRow` (lines 510-529).

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10` (timeout 60000ms)
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/SidebarGroupHeader.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git commit -m "refactor: extract SidebarGroupHeader views to own file"
```

---

### Task 5: Rewrite WelcomeSidebarIllustration using real sidebar components

**Files:**
- Rewrite: `Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift`

Replace the custom illustration views with the real `SidebarResolvedGroupHeaderRow` and `SidebarWorktreeRow` components, feeding them mock `Worktree` instances and `GitBranchStatus` data. This guarantees pixel-identical rendering with the real sidebar.

- [ ] **Step 1: Rewrite WelcomeSidebarIllustration.swift**

The new implementation:
- Creates mock `Worktree` instances (with fake UUIDs, paths like `/tmp/mock/ghostty`, etc.)
- Creates mock `GitBranchStatus` for worktrees with interesting status
- Renders `SidebarResolvedGroupHeaderRow` for each group header
- Renders `SidebarWorktreeRow` for each worktree with no-op callbacks and `.allowsHitTesting(false)`
- Uses `SidebarRepoGrouping.automaticPaletteHexes` for accent colors (via the now-available `NSColor(hex:)`)
- Wraps everything in the same card container (rounded rect, fillMuted background, fillActive border)

Mock data (same repos as before):
- **ghostty / ghostty-org** (expanded): main + `ghostty.gpu-renderer` (dirty, ↑3, PR 1) + `ghostty.fix-keybinds` (clean, PR 1)
- **uv / astral-sh** (expanded): main + `uv.fix-resolver` (+12 -3, ↑1, PR 1, 🔔 2)

The key difference from the old approach: no custom row views — the real `SidebarWorktreeRow` handles all icon rendering, chip layout, and styling.

For `SidebarWorktreeRow`'s callback parameters (`onOpen`, `onOpenNew`, `onOpenInPane`, `onSetIconColor`), pass empty closures `{}` and apply `.allowsHitTesting(false)` to the entire illustration.

For `SidebarResolvedGroupHeaderRow`, pass `isExpanded: true` for both groups.

Use `SidebarRepoGrouping.automaticPaletteHexes[0]` (`#F5C451` yellow) for ghostty and `automaticPaletteHexes[3]` (`#4ADE80` green) for uv — the real sidebar palette colors.

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10` (timeout 60000ms)
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift
git commit -m "feat: rewrite illustration using real sidebar components with mock data"
```

---

### Task 6: Clean up WorkspaceStatusChips.swift

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/WorkspaceStatusChips.swift`

`WorkspaceStatusChips.swift` has duplicate chip implementations (`WorkspaceDiffChip`, `WorkspaceStatusSyncChip`, `WorkspaceStatusChip`) that were broken (used the deleted `WorkspaceOcticonImage`). Rewrite `WorkspaceStatusChipRow` to delegate to the now-extracted sidebar chip components.

- [ ] **Step 1: Rewrite WorkspaceStatusChipRow to use sidebar chips**

Keep `WorkspaceStatusChipsModel` (it's a useful data model). Rewrite `WorkspaceStatusChipRow` body to use `SidebarDiffChip`, `SidebarStatusSyncChip`, and `SidebarChip` directly — the same chip views the real sidebar uses. Delete all the `Workspace*` chip view structs that duplicate the sidebar chips.

The resulting file should contain only:
- `WorkspaceStatusChipsModel` struct
- `WorkspaceStatusChipRow` view (which uses `SidebarDiffChip`, `SidebarStatusSyncChip`, `SidebarChip`)

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10` (timeout 60000ms)
Expected: `Build complete!`

Note: `WorkspaceStatusChipRow` is used by `WorkspaceRecentCardView` in `WorkspaceEmptyStateView.swift`. Verify it still compiles correctly.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/WorkspaceStatusChips.swift
git commit -m "refactor: rewrite WorkspaceStatusChipRow to use extracted sidebar chips"
```

---

### Task 7: Visual verification

**Files:** None — verification only.

- [ ] **Step 1: Full build**

Run: `AGENT_RUN_ID="verify" mise run build 2>&1 | tail -10` (timeout 120000ms)
Expected: `Build complete!`

- [ ] **Step 2: Launch and verify welcome screen**

```bash
pkill -9 -f "AgentStudio" 2>/dev/null; sleep 1
.build-agent-verify/debug/AgentStudio &
```

Verify with Peekaboo:
- Welcome illustration uses the SAME icons as the real sidebar (identical rendering)
- Chip styling matches sidebar chips exactly
- Group headers look identical to sidebar group headers
- Accent colors match the real sidebar palette

- [ ] **Step 3: Verify real sidebar is unaffected**

Click "Choose a Folder to Scan…", select a folder with repos. After scanning:
- Sidebar renders correctly with all components
- Worktree rows, chips, group headers all look the same as before
- No visual regression

- [ ] **Step 4: Run lint and tests**

```bash
mise run lint
mise run test
```

Expected: Zero errors, all tests pass.

- [ ] **Step 5: Commit any polish**

```bash
git add -A
git commit -m "polish: visual verification adjustments"
```
