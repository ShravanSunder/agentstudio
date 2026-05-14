# Welcome Launcher Command Bar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the tabless launcher feel like Welcome 1 by migrating fully to a shared `AppStyles.Welcome` visual namespace, embedding a real command-bar-style preview under `⌘P`, and making `⌘T` / `⌘P` clickable smart-start rows while preserving Welcome 1 itself.

**Architecture:** The fix should keep Welcome 1 visually unchanged and move all launcher-specific style values into a new `AppStyles.Welcome` namespace, leaving `WorkspaceEmptyStateLayout` responsible only for derived geometry. `⌘T` remains a special smart-start shortcut routed to `showCommandBarRepos`, while the real blank-tab command stays `.newTab`; the launcher preview under `⌘P` must reuse actual command-bar view components with mock data instead of a generic explanatory box. All touched code should migrate directly to `AppStyles`; no compatibility alias layer should survive.

**Tech Stack:** SwiftUI, AppKit, Swift Observation, existing command-bar view components in `Sources/AgentStudio/Features/CommandBar/Views`, Swift Testing, mise, swift-format, swiftlint

---

## Context And Why The Current Branch State Is Wrong

The merged branch now contains:

- live style namespace: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- current broken launcher implementation: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`

### Current bad composition

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ centered title block                                                        │
│                                                                              │
│ Start Fast                Recent                                             │
│ [boxed cmd-t slab]       [small lonely recent card]                         │
│ [boxed cmd-p slab]                                                     dead  │
│ [generic fake command-bar box]                                        space │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Approved target composition

```text
┌──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                        Your workspace                                                │
│                      Start something new, or jump back into recent work                              │
│                                                                                                      │
│  Start Fast                                                                                         │
│                                                                                                      │
│  ⌘T  New tab or worktree                                  Recent                                     │
│      Always opens the # picker.                          ┌──────────────────────┐ ┌──────────────┐ │
│      New Empty Tab is always first.                      │ recent               │ │ recent       │ │
│                                                          └──────────────────────┘ └──────────────┘ │
│  ⌘P  Command palette                                                                              │
│      Search the app using scoped prefixes.                                                        │
│                                                          ┌──────────────────────┐ ┌──────────────┐ │
│      ╭────────────────────────────────────────────╮      │ recent               │ │ recent       │ │
│      │ ▸ Search or jump to…                      │      └──────────────────────┘ └──────────────┘ │
│      ├────────────────────────────────────────────┤                                                  │
│      │ >  Commands           Run actions         │                                                  │
│      │ $  Panes              Jump to tabs/panes  │                                                  │
│      │ #  Repos/Worktrees    Open repo/worktree  │                                                  │
│      ├────────────────────────────────────────────┤                                                  │
│      │ Enter Select   ↑↓ Move   Esc Dismiss      │                                                  │
│      ╰────────────────────────────────────────────╯                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Non-negotiable design rules

- Welcome 1 must not visually change.
- The launcher must reuse the same visual language as Welcome 1.
- `Start Fast` is plain section text, not a card.
- `⌘T` row is clickable, but should not look like a heavy slab.
- `⌘P` row is clickable.
- Only the embedded command-bar preview is boxed.
- `Recent` must align with the left edge of the `⌘P` description / preview column, not the far-left section root.
- No separator line between `⌘T` and `⌘P`; spacing only.
- The `⌘P` preview must use actual command-bar chrome, not a fake matrix box.

## File Structure

### Modify
- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  Reason: add `AppStyles.Welcome` as the shared style namespace.
- `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
  Reason: replace the current ugly launcher layout with the approved Welcome 1 Echo layout.
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
  Reason: keep `New Empty Tab` pinned first in `#` scope.
- `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  Reason: `⌘T` stays `AppShortcut.newTab` but routes to `showCommandBarRepos`.
- `Sources/AgentStudio/App/Commands/AppCommand.swift`
  Reason: keep `.newTab` as the real blank-tab action; expose `showCommandBarRepos` as the `⌘T` surface.
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  Reason: keep `.newTab` fallback rooted at first watched folder, else home.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
  Reason: keep menu / app routing consistent with `⌘T` smart-start where intended.

### Reuse from command bar
- `Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift`
- `Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift`
- `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultRow.swift`
- `Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift`

### Test files
- `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`
- `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift`
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarGlobalKeyRouterTests.swift`

## Shared Welcome Namespace

Add this namespace in `AppStyles.swift` and make the launcher consume it.

```swift
extension AppStyles {
    enum Welcome {
        static let pageHorizontalPadding: CGFloat = 56
        static let pageVerticalPadding: CGFloat = 48
        static let contentColumnsGap: CGFloat = 72

        static let titleFontSize: CGFloat = 30
        static let bodyFontSize: CGFloat = 16

        static let sectionLabelFontSize: CGFloat = 15
        static let sectionLabelOpacity: CGFloat = 0.62

        static let shortcutTitleFontSize: CGFloat = 24
        static let shortcutBodyFontSize: CGFloat = 16
        static let shortcutKeyFontSize: CGFloat = 18
        static let shortcutKeyColumnWidth: CGFloat = 44

        static let teachingColumnWidth: CGFloat = 520
        static let recentsColumnWidth: CGFloat = 520
        static let blockGap: CGFloat = 28
        static let previewTopGap: CGFloat = 14

        static let recentCardWidth: CGFloat = 250
        static let recentCardGap: CGFloat = 20
        static let recentsColumnCount = 2

        static let previewWidth: CGFloat = 500
        static let previewCornerRadius: CGFloat = 16
        static let previewSearchRowHeight: CGFloat = 44
        static let previewResultRowHeight: CGFloat = 36
        static let previewFooterHeight: CGFloat = 28
    }
}
```

### Rule

- `AppStyles.Welcome` owns visual tokens.
- `WorkspaceEmptyStateLayout` owns derived width math only.
- `AppStyles.swift` must be removed by the end of the work.
- All touched code must migrate to `AppStyles`; no compatibility shim, no aliases, no dual-source truth.

## Task 1: Normalize The Style Foundation To `AppStyles.Welcome`

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

- [ ] **Step 1: Write the failing token tests**

```swift
@Test("launcher uses shared welcome namespace for critical tokens")
func launcherUsesSharedWelcomeNamespaceForCriticalTokens() {
    #expect(AppStyles.Welcome.titleFontSize == 30)
    #expect(AppStyles.Welcome.bodyFontSize == 16)
    #expect(AppStyles.Welcome.recentsColumnCount == 2)
    #expect(AppStyles.Welcome.previewWidth == 500)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL because `AppStyles.Welcome` does not exist yet
```

- [ ] **Step 3: Add `AppStyles.Welcome` and migrate references**

Add the namespace in `AppStyles.swift` and migrate all welcome / launcher callers to it directly.

```swift
extension AppStyles {
    enum Welcome {
        ...
    }
}
```

Do not add aliases back into `AppStyles.swift`.

- [ ] **Step 4: Re-run the focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS
```

## Task 2: Rebuild The Launcher To Match Welcome 1 Hierarchy

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift`

- [ ] **Step 1: Write failing layout tests**

```swift
@Test("launcher recent rail aligns with the command bar preview column")
func launcherRecentRailAlignsWithPreviewColumn() {
    #expect(AppStyles.Welcome.contentColumnsGap == 72)
    #expect(AppStyles.Welcome.teachingColumnWidth > AppStyles.Welcome.recentCardWidth)
}

@Test("launcher recent grid stays fixed at two columns")
func launcherRecentGridStaysFixedAtTwoColumns() {
    #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 800) == 2)
    #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1800) == 2)
}

@Test("folder intake state remains Welcome 1")
func folderIntakeStateRemainsWelcomeOne() {
    let result = WorkspaceLauncherProjector.project(store: WorkspaceStore())
    #expect(result.kind == .noFolders)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL because current launcher geometry still reflects the bad implementation
```

- [ ] **Step 2b: Add explicit non-regression coverage for non-launcher states**

In `WorkspaceLauncherProjectorTests.swift`, keep or add tests for:

```swift
@Test("project_noRepos_returnsFolderIntakeState")
@Test("project_scanningWithoutRepos_returnsScanningState")
@Test("project_emptyFolderScanWithoutRepos_returnsEmptyScanState")
```

These must stay green before and after the launcher rewrite because all three modes share `WorkspaceEmptyStateView.swift`.

- [ ] **Step 3: Replace the current launcher stack with the approved structure**

Implement this structure in `WorkspaceEmptyStateView.swift`:

```swift
private func launcherBody(availableWidth: CGFloat) -> some View {
    VStack(spacing: 40) {
        WorkspaceHomeHeader(
            title: "Your workspace",
            subtitle: "Start something new, or jump back into recent work"
        )

        VStack(alignment: .leading, spacing: 22) {
            Text("Start Fast")
                .font(.system(size: AppStyles.Welcome.sectionLabelFontSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.sectionLabelOpacity))

            HStack(alignment: .top, spacing: AppStyles.Welcome.contentColumnsGap) {
                launcherTeachingColumn
                    .frame(width: AppStyles.Welcome.teachingColumnWidth, alignment: .leading)

                launcherRecentRail(visibleRecentCards: visibleRecentCards)
                    .frame(width: AppStyles.Welcome.recentsColumnWidth, alignment: .leading)
            }
        }
    }
}
```

### Required hierarchy

```text
Start Fast

⌘T row
⌘P row
embedded command bar preview

Recent
2-column recent rail
```

- [ ] **Step 4: Make `⌘T` and `⌘P` clickable text-first rows**

Do **not** keep them as full heavy cards. Use a button wrapper with subtle hover feedback:

```swift
Button(action: action) {
    VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 12) { ... }
        VStack(alignment: .leading, spacing: 4) { ... }
            .padding(.leading, AppStyles.Welcome.shortcutKeyColumnWidth + 12)
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.onHover { isHovered = $0 }
```

The rows must read like Welcome 1 text blocks with click affordance, not like separate boxed tiles.

- [ ] **Step 5: Re-run the launcher tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS
```

- [ ] **Step 6: Re-run the projector non-regression tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceLauncherProjectorTests
```

Expected:

```text
PASS
```

## Task 3: Replace The Fake Matrix With A Real Command-Bar Embed

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Reuse from:
  - `Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift`
  - `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultRow.swift`
  - `Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

- [ ] **Step 1: Write a failing preview contract test**

```swift
@Test("command palette preview uses command bar dimensions")
func commandPalettePreviewUsesCommandBarDimensions() {
    #expect(AppStyles.Welcome.previewWidth == 500)
    #expect(AppStyles.Welcome.previewSearchRowHeight == 44)
    #expect(AppStyles.Welcome.previewResultRowHeight == 36)
    #expect(AppStyles.Welcome.previewFooterHeight == 28)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL because the current embed is still generic / underspecified
```

- [ ] **Step 3: Build a real command-bar-style preview with mock data**

Use actual command-bar components and mock data:

```swift
private struct CommandBarEmbeddedPreview: View {
    private let items: [CommandBarItem] = [
        CommandBarItem(
            id: "preview-commands",
            title: "Commands",
            subtitle: "Run actions and commands",
            shortcutKeys: [ShortcutKey(symbol: ">")],
            group: "Preview",
            groupPriority: 0,
            action: .custom({})
        ),
        CommandBarItem(
            id: "preview-panes",
            title: "Panes",
            subtitle: "Jump to open tabs and panes",
            shortcutKeys: [ShortcutKey(symbol: "$")],
            group: "Preview",
            groupPriority: 0,
            action: .custom({})
        ),
        CommandBarItem(
            id: "preview-repos",
            title: "Repos/Worktrees",
            subtitle: "Open a repo or worktree",
            shortcutKeys: [ShortcutKey(symbol: "#")],
            group: "Preview",
            groupPriority: 0,
            action: .custom({})
        ),
    ]
}
```

Render with:

```swift
VStack(spacing: 0) {
    CommandBarStatusStrip(mode: .normal, context: .empty)
    Divider().opacity(0.15)
    mockSearchRow
    Divider().opacity(0.3)
    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        CommandBarResultRow(item: item, isSelected: index == 0)
    }
    Divider().opacity(0.3)
    CommandBarFooter(hints: previewFooterHints)
}
```

### Critical rule
- This must look like the command bar using the same components.
- It must not be a generic rounded card with plain text rows.

- [ ] **Step 4: Align the preview and recent rail**

Use this grid:

```text
⌘T title/body left edge = x
⌘P title/body left edge = x
preview left edge       = x
Recent left edge        = x + previewWidth + contentColumnsGap
recent grid left edge   = Recent left edge
```

- [ ] **Step 5: Re-run the launcher tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS
```

## Task 4: Keep `.newTab` Real, Make Only `⌘T` Special

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Test:
  - `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
  - `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
  - `Tests/AgentStudioTests/Features/CommandBar/CommandBarGlobalKeyRouterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func test_reposScope_emptyStore_stillShowsNewEmptyTab() {
    let store = makeStore()
    let items = CommandBarDataSource.items(
        scope: .repos,
        store: store,
        repoCache: RepoCacheAtom(),
        dispatcher: dispatcher
    )
    #expect(items.count == 1)
    #expect(items.first?.title == "New Empty Tab")
    #expect(items.first?.command == .newTab)
}

@Test
func executeNewTab_usesFirstWatchedFolderAsFallback() {
    ...
    #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd?.standardizedFileURL
        == watchedFolder.standardizedFileURL)
}

@Test
func commandSpecDerivesKeyBindingFromShortcut() {
    let startContextDefinition = CommandDispatcher.shared.definition(for: .showCommandBarRepos)
    #expect(startContextDefinition.keyBinding?.key == "t")
    #expect(startContextDefinition.keyBinding?.modifiers == [.command])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter CommandBarDataSourceTests

SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter PaneTabViewControllerCommandTests

SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter ShortcutCatalogTests
```

Expected:

```text
FAIL because the smart-start routing / row injection are not yet complete
```

- [ ] **Step 3: Inject `New Empty Tab` into the `#` picker**

In `CommandBarDataSource+WorktreeRows.swift` prepend:

```swift
var items: [CommandBarItem] = [
    CommandBarItem(
        id: "repo-new-empty-tab",
        title: "New Empty Tab",
        subtitle: "Blank terminal in watched folder or home",
        icon: "plus.square",
        group: "Repos",
        groupPriority: 0,
        keywords: ["new", "empty", "tab", "blank", "terminal"],
        action: .dispatch(.newTab),
        command: .newTab
    )
]
```

- [ ] **Step 4: Keep `.newTab` as the real blank-tab action**

In `PaneTabViewController.swift`:

```swift
private func addNewTab() {
    let launchDirectory =
        store.repositoryTopologyAtom.watchedPaths.first?.path
        ?? FileManager.default.homeDirectoryForCurrentUser

    dispatchAction(.openFloatingTerminal(launchDirectory: launchDirectory, title: nil))
}
```

- [ ] **Step 5: Make only the `⌘T` shortcut special**

In `AppShortcut.swift`:

```swift
var command: AppCommand {
    switch self {
    case .newTab:
        return .showCommandBarRepos
    default:
        ...
    }
}
```

In `AppCommand.swift`:

```swift
case .newTab:
    return CommandSpec(
        command: self,
        label: "New Empty Tab",
        icon: "plus.square",
        helpText: "Create a new empty tab",
        commandBarGroupName: "Window",
        commandBarGroupPriority: CommandBarGroupPriority.window
    )

case .showCommandBarRepos:
    return CommandSpec(
        command: self,
        shortcut: .newTab,
        label: "New Tab or Worktree",
        icon: "folder",
        helpText: "Open the repo and worktree picker",
        commandBarGroupName: "Commands",
        commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
        isHiddenInCommandBar: true
    )
```

In `AppDelegate.swift`, keep the File menu `New Tab` row on the real `.newTab` command. Only keyboard `⌘T` and the launcher `⌘T` row get smart-start behavior.

The approved rule is:

```text
keyboard ⌘T         -> showCommandBarRepos
launcher ⌘T row     -> showCommandBarRepos
File menu New Tab   -> newTab
synthetic picker row -> newTab
```

- [ ] **Step 6: Re-run the focused suites**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter CommandBarDataSourceTests

SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter PaneTabViewControllerCommandTests

SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
swift test --build-path "$SWIFT_BUILD_DIR" --filter ShortcutCatalogTests
```

Expected:

```text
PASS
```

## Task 5: Full Verification

**Files:**
- Verify all touched files above

- [ ] **Step 1: Run full build**

Run:

```bash
mise run build
```

Expected:

```text
Build complete! ... exit 0
```

- [ ] **Step 2: Run full test suite**

Run:

```bash
mise run test
```

Expected:

```text
All included suites pass; E2E / Zmx suites may be skipped by project config
```

- [ ] **Step 3: Run lint**

Run:

```bash
mise run lint
```

Expected:

```text
swift-format: OK
swiftlint: OK
architecture boundary checks passed
```

- [ ] **Step 4: Visual verification**

Run:

```bash
pkill -9 -f ".build-agent-codex-welcome/arm64-apple-macosx/debug/AgentStudio" >/dev/null 2>&1 || true
./.build-agent-codex-welcome/arm64-apple-macosx/debug/AgentStudio >/tmp/agentstudio-visual.log 2>&1 &
peekaboo app switch --to "AgentStudio"
peekaboo see --mode frontmost --json --path /tmp/agentstudio-frontmost.png
```

Manual acceptance:

```text
✓ Welcome 1 still looks identical
✓ launcher no longer reads as stacked utility boxes
✓ ⌘T row is clickable and text-first
✓ ⌘P row is clickable and text-first
✓ embedded preview looks like the real command bar
✓ Recent aligns with preview column
✓ recent rail balances the page in 2 columns
```

## Self-Review

- The plan now targets `AppStyles`, not an obsolete-only style path.
- The plan requires full migration off `AppStyles.swift`; no compatibility layer remains in the target end state.
- The plan separates:
  - `AppShortcut.newTab` = shortcut identity
  - `.showCommandBarRepos` = smart-start route
  - `.newTab` = real blank-tab action
- The plan resolves the menu contradiction explicitly:
  - keyboard / launcher row are special
  - File menu stays the real blank-tab command
- The plan keeps Welcome 1 unchanged and only changes launcher geometry and composition.
- The plan adds explicit non-regression checks for `noFolders`, `scanning`, and `scanEmpty`.
- The plan explicitly rejects the current ugly direction:
  - multiple heavy shortcut cards
  - fake generic matrix
  - misaligned `Recent` header
  - tiny underweighted right rail
