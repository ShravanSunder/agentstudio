# Notification Inbox Sidebar Contract Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Notification Inbox a first-class Agent Studio sidebar surface that visually matches RepoExplorer across every grouping mode: same source/group header grammar, icon slots, icon colors, indentation ladder, row chrome, metadata alignment, and visual verification standard.

**Architecture:** Treat RepoExplorer as the source-of-truth sidebar contract, not merely as a source of reusable padding constants. Extract a stateless source-group header primitive into `SharedComponents/`, make RepoExplorer and Inbox group headers flow through it, keep notification-specific display decisions inside `Features/InboxNotification/`, and use tests plus visual evidence to prove every grouping mode obeys the same geometry. No atoms or stores are added; this is presentation and display-model work over existing notification state.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit-hosted macOS sidebar, Swift Testing, `mise run format`, `mise run lint`, `mise run test`, PID/window-targeted Peekaboo or native `screencapture` visual verification when Peekaboo cannot capture the debug build.

---

## Corrected Product Goal

The Inbox must look like the Repo sidebar because it is the same product surface class.

The acceptance bar is not "the code imports SharedComponents." The acceptance bar is visual and structural:

- The user can put RepoExplorer and Inbox side by side and see one design system.
- Group headers line up across `By Repo`, `By Pane`, `By Tab`, and fallback groups like `Other sources`.
- No grouping mode falls back to a smaller plain section header unless RepoExplorer would do the same for that same row role.
- Icons use the same sidebar color semantics as repo/worktree rows when repo identity is available.
- Fallback groups reserve the same icon column with a neutral source icon.
- Notification metadata lines never create the "terminal icon sticking out" effect.
- Pane grouping groups by the main parent pane scope only, not by every child/drawer/tab detail.
- Pane-group count pills stay hidden unless product direction changes.
- Tests cover the row/header contracts automatically; visual capture proves the pixels are acceptable.

## TUI Design Target

This is the visual contract. Implementation details are allowed to change, but the rendered surface must preserve these columns, hierarchy, and row relationships.

### Repo Sidebar Reference Shape

```text
Repo sidebar reference
══════════════════════

┌─ Sidebar surface ──────────────────────────────────────────────────┐
│                                                                     │
│  [traffic lights]        [repos icon] [bell icon]                   │
│                                                                     │
│    ▸  [repo icon]  .github · askluna                                │
│                                                                     │
│    ▾  [repo icon]  agent-vm · ShravanSunder                         │
│                                                                     │
│         [★]  agent-vm                                               │
│              master                                                 │
│              [+0 -0] [↑0 ↓12] [pr 0]                                │
│                                                                     │
│         [worktree icon]  agent-vm.mcp-portal                        │
│                          mcp-portal                                 │
│                          [+3574 -3319] [↑- ↓-] [pr 0]               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Column contract:

  group row
    chevron  icon-slot  title            secondary      trailing
    ───────  ─────────  ───────────────  ───────────    ────────
       ▸      repo      agent-vm         ShravanSunder

  child row
             icon-slot  title
             ─────────  ─────────────────────────────
                ★       agent-vm
                        master
                        status chips
```

### Inbox Ungrouped Target

Ungrouped mode has no section headers. It still uses the same row shell, background, hover/selection fill, and text rhythm as the repo sidebar.

```text
Inbox: None
════════════

┌─ Inbox sidebar surface ─────────────────────────────────────────────┐
│                                                                     │
│  [Search inbox................................] [sort] [group] [x]  │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│     ●  New terminal activity                              3h        │
│        askluna · askluna                                            │
│        Tab askluna · Pane Ready                                     │
│        Output appeared while you were away                          │
│                                                                     │
│        Claude Code                                        5h        │
│        agent-studio · notification-inbox-redesign                   │
│        Claude is waiting for your input                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Rules:

  ▸ no group header row
  ▸ unread dot is an indicator, not the metadata icon column
  ▸ metadata text aligns under notification title text
  ▸ no terminal icon protrudes into the unread-dot column
```

### Inbox By Repo Target

`By Repo` must look like repo grouping, including `Other sources`. Fallback groups reserve the icon slot and use a neutral source icon instead of shifting text left.

```text
Inbox: By Repo
══════════════

┌─ Inbox sidebar surface ─────────────────────────────────────────────┐
│                                                                     │
│  [Search inbox................................] [sort] [group] [x]  │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│    ▾  [repo icon]    askluna                         [count?]       │
│                                                                     │
│         ●  New terminal activity                          3h        │
│            askluna · askluna                                       │
│            Tab askluna · Pane Ready                                │
│            Output appeared while you were away                      │
│                                                                     │
│    ▸  [source icon]  Other sources                  [count?]        │
│                                                                     │
│         ●  Workspace event                                2h        │
│            Workspace event                                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Rules:

  ▸ repo-backed header uses repo/sidebar icon and color semantics
  ▸ Other sources uses the same header height, text size, and icon slot
  ▸ child rows use AppStyles.Shell.Sidebar.groupChildRowLeadingInset
  ▸ optional count is allowed here because by-repo counts are useful
```

### Inbox By Pane Target

`By Pane` groups by the main parent pane scope only. Drawer-child notifications belong under their parent pane group. Pane group headers do not show count pills.

```text
Inbox: By Pane
══════════════

┌─ Inbox sidebar surface ─────────────────────────────────────────────┐
│                                                                     │
│  [Search inbox................................] [sort] [group] [x]  │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│    ▾  [pane icon]    Pane project-dev                               │
│                                                                     │
│         ●  New terminal activity                          3h        │
│            Terminal                                                │
│            Drawer Drawer                                           │
│            Output appeared while you were away                      │
│                                                                     │
│         ●  New terminal activity                          3h        │
│            Terminal                                                │
│            Tab Terminal · Pane project-dev                         │
│            Output appeared while you were away                      │
│                                                                     │
│    ▸  [pane icon]    Other panes                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Rules:

  ▸ header row uses same source group header as By Repo
  ▸ no numeric count pill in pane-group header
  ▸ drawer children do not create a separate top-level pane group
  ▸ parent pane label is the grouping label
```

### Inbox By Tab Target

`By Tab` uses the same group-header geometry with a tab icon. It must not fall back to a plain small gray section header.

```text
Inbox: By Tab
═════════════

┌─ Inbox sidebar surface ─────────────────────────────────────────────┐
│                                                                     │
│  [Search inbox................................] [sort] [group] [x]  │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│    ▾  [tab icon]     Tab askluna                     [count?]       │
│                                                                     │
│         ●  New terminal activity                          3h        │
│            askluna · askluna                                       │
│            Pane Ready                                              │
│            Output appeared while you were away                      │
│                                                                     │
│    ▸  [tab icon]     Untitled Tab                   [count?]        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Rules:

  ▸ tab header uses same source group header as By Repo and By Pane
  ▸ tab labels are human labels, never raw UUIDs
  ▸ optional count is allowed here unless product direction changes
```

### PaneInbox Target

PaneInbox is a smaller surface, but its rows still obey the same notification row grammar. It should not introduce a separate row/background language.

```text
PaneInbox popover
═════════════════

┌─ Pane inbox ────────────────────────────────────────────────────────┐
│                                                                     │
│  Pane inbox                                  [filter] [clear] [x]   │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│     ●  New terminal activity                              3h        │
│        Terminal                                                     │
│        Drawer Drawer                                                │
│        Output appeared while you were away                          │
│                                                                     │
│        Claude Code                                        5h        │
│        agent-studio · notification-inbox-redesign                   │
│        Claude is waiting for your input                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Rules:

  ▸ same InboxRow content component as global Inbox
  ▸ no group count pills
  ▸ no separate background color language
  ▸ placement metadata aligns under title text
```

### Wrong Shape To Eliminate

This is the current failure pattern. Do not preserve it.

```text
Wrong mixed grammar
═══════════════════

    ▾  [repo icon]  askluna

       ●  New terminal activity
          Terminal
    [terminal icon sticks out]  Tab Terminal · Pane project-dev

  ▸ Other sources

       ●  Workspace event

Why this is wrong:

  ▸ repo groups and fallback groups do not share columns
  ▸ Other sources text starts in a different x-position
  ▸ plain group header uses different typography
  ▸ terminal metadata icon occupies the unread indicator column
```

## Current Failure Model

Current branch evidence shows the Inbox shares some primitives but still mixes two layout grammars:

- Repo-backed groups use `SidebarRepoGroupHeader`.
- `Other sources`, `By Pane`, and `By Tab` use `SidebarSectionHeader`.
- `SidebarSectionHeader` has different font size, padding, and no source icon slot.
- `InboxRow` uses an unread-dot leading column on the title line, but `SidebarMetadataLine` may draw a terminal icon in that same leading column on later lines.
- `InboxNotificationSidebarViewTests` currently pins the wrong contract:
  `InboxNotificationGroupHeader.chromePolicy(for: .plain) == .plainSectionHeader`.

That is why the UI can have shared components in code while still looking misaligned.

## Non-Goals

- Do not change the notification engine, promoter, router claim semantics, or derived terminal activity thresholds.
- Do not add an atom, store, coordinator, event type, or event-bus command path.
- Do not introduce a new sidebar design language.
- Do not make pixel-perfect screenshot assertions in Swift tests.
- Do not use wall-clock sleeps in tests.
- Do not modify `vendor/zmx` or Ghostty app files.

## File Structure

### Create

- `Sources/AgentStudio/SharedComponents/SidebarSourceGroupHeader.swift`
  - Stateless group-header primitive for sidebar source rows.
  - Inputs are values and closures only.
  - Imports SwiftUI.
  - Does not import `Core`, `Features`, or `App`.

- `Sources/AgentStudio/SharedComponents/SidebarSourceGroupIcon.swift`
  - Value type for icon identity and color style.
  - Supports SF Symbols and Octicons without exposing repo/inbox domain types.
  - Imports SwiftUI because `Color` is presentation-only here.

- `Tests/AgentStudioTests/SharedComponents/SidebarSourceGroupHeaderTests.swift`
  - Pins shared component policy, icon slot behavior, and atom-free import boundary.

- `docs/wip/debugging/2026-05-14-notification-inbox-sidebar-contract-visual.md`
  - Records visual verification commands, image paths, pass/fail observations, and any Peekaboo blocker.

### Modify

- `Sources/AgentStudio/SharedComponents/SidebarRepoGroupHeader.swift`
  - Rebuild as a wrapper over `SidebarSourceGroupHeader`.
  - Preserve current RepoExplorer appearance.

- `Sources/AgentStudio/SharedComponents/SidebarGroupRow.swift`
  - Either delete if no longer used, or convert to a compatibility wrapper over `SidebarSourceGroupHeader` content.
  - It must not remain the only place with hard-coded repo icon grammar.

- `Sources/AgentStudio/SharedComponents/SidebarMetadataLine.swift`
  - Keep its current reserved icon-column contract. Source/detail rows already align correctly because a blank spacer is reserved when no icon exists.
  - Do not add a new leading mode unless implementation discovers a separate reusable need.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
  - Replace plain/repo header style split with source-group presentation data.
  - Keep grouping semantics feature-owned.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
  - Add source-group presentation helpers for repo, pane, tab, and fallback groups.
  - Keep denormalized labels human-readable.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
  - Always render grouped Inbox sections with `SidebarSourceGroupHeader`.
  - Remove `plainSectionHeader` from grouped Inbox header chrome.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
  - Fix metadata leading alignment and remove the protruding terminal icon.
  - Keep notification-specific title/time/source/detail rendering here.

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
  - Keep row indentation as the shared group-child indent.
  - Ensure every grouping mode goes through the same header row contract.

- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
  - Apply the same row metadata alignment fix to PaneInbox.
  - Keep PaneInbox count pills hidden.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
  - Continue using `RepoPresentationColoring.checkoutColorHex`.
  - No visual change intended.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
  - No required behavior change; use only as the row grammar reference for icon columns and colored worktree icons.

- `Tests/AgentStudioTests/Architecture/SidebarSurfaceConvergenceTests.swift`
  - Upgrade convergence tests from "same shell" to "same group header family."

- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
  - Add all grouping-mode contract tests.

- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift`
  - Add source-group presentation tests.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
  - Flip the currently-wrong `.plainSectionHeader` expectation.
  - Add mounted tests for header accessibility and count behavior.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxRowTests.swift`
  - Add metadata alignment tests proving placement rows remove the terminal glyph while preserving the reserved text column.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`
  - Add row-alignment and no-count assertions for PaneInbox.

---

## Task 1: Red-Test The Complete Header Contract

**Files:**
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Modify: `Tests/AgentStudioTests/Architecture/SidebarSurfaceConvergenceTests.swift`

- [ ] **Step 1: Replace the wrong header chrome expectation with the corrected failing expectation**

In `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`, find the test named `repoGroupedInboxAndRepoExplorerUseSharedRepoHeaderChrome` and replace it with:

```swift
@Test("all grouped inbox section headers use source group header chrome")
@MainActor
func groupedInboxHeadersUseSourceGroupHeaderChrome() {
    #expect(
        InboxNotificationGroupHeader.chromePolicy(for: .repo(organizationName: "askluna"))
            == .sourceGroupHeader
    )
    #expect(InboxNotificationGroupHeader.chromePolicy(for: .plain) == .sourceGroupHeader)
    #expect(RepoExplorerView.groupHeaderChromePolicy == .sourceGroupHeader)
    #expect(SidebarSourceGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
    #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
    #expect(
        SidebarSourceGroupHeader<EmptyView>.leadingInset
            == AppStyles.Shell.Sidebar.listRowLeadingInset
    )
}
```

- [ ] **Step 2: Upgrade architecture convergence test**

In `Tests/AgentStudioTests/Architecture/SidebarSurfaceConvergenceTests.swift`, add:

```swift
@Test("repo and inbox grouped headers share source group header chrome")
@MainActor
func repoAndInboxGroupedHeadersShareSourceGroupHeaderChrome() {
    #expect(SidebarSourceGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
    #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
    #expect(RepoExplorerView.groupHeaderChromePolicy == .sourceGroupHeader)
    #expect(InboxNotificationGroupHeader.chromePolicy(for: .plain) == .sourceGroupHeader)
    #expect(
        InboxNotificationGroupHeader.chromePolicy(for: .repo(organizationName: "ShravanSunder"))
            == .sourceGroupHeader
    )
}
```

- [ ] **Step 3: Run the focused tests and verify they fail for the right reason**

Run:

```bash
mise run test -- --filter "SidebarSurfaceConvergenceTests|InboxNotificationSidebarViewTests.groupedInboxHeadersUseSourceGroupHeaderChrome"
```

Expected:

- FAIL because `SidebarHeaderChromePolicy.sourceGroupHeader` does not exist.
- FAIL because `SidebarSourceGroupHeader` does not exist.
- No unrelated test crash.

---

## Task 2: Add The Shared Source Group Header Primitive

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SidebarSourceGroupIcon.swift`
- Create: `Sources/AgentStudio/SharedComponents/SidebarSourceGroupHeader.swift`
- Modify: `Sources/AgentStudio/SharedComponents/SidebarSurfaceChrome.swift`
- Modify: `Sources/AgentStudio/SharedComponents/SidebarRepoGroupHeader.swift`
- Test: `Tests/AgentStudioTests/SharedComponents/SidebarSourceGroupHeaderTests.swift`

- [ ] **Step 1: Write shared component tests**

Create `Tests/AgentStudioTests/SharedComponents/SidebarSourceGroupHeaderTests.swift`:

```swift
import Testing

@testable import AgentStudio

@Suite("SidebarSourceGroupHeader")
struct SidebarSourceGroupHeaderTests {
    @Test("source group header uses shared chrome policy and leading inset")
    @MainActor
    func sourceGroupHeaderUsesSharedChromePolicyAndLeadingInset() {
        #expect(SidebarSourceGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(
            SidebarSourceGroupHeader<EmptyView>.leadingInset
                == AppStyles.Shell.Sidebar.listRowLeadingInset
        )
    }

    @Test("default repo header wraps source group header chrome")
    @MainActor
    func defaultRepoHeaderWrapsSourceGroupHeaderChrome() {
        #expect(SidebarRepoGroupHeader<EmptyView>.chromePolicy == .sourceGroupHeader)
        #expect(
            SidebarRepoGroupHeader<EmptyView>.leadingInset
                == SidebarSourceGroupHeader<EmptyView>.leadingInset
        )
    }

    @Test("source group icons describe fixed sidebar icon slots")
    func sourceGroupIconsDescribeFixedSidebarIconSlots() {
        #expect(SidebarSourceGroupIcon.repo.symbolName == "octicon-repo")
        #expect(SidebarSourceGroupIcon.otherSources.symbolName == "tray")
        #expect(SidebarSourceGroupIcon.pane.symbolName == "rectangle.inset.filled")
        #expect(SidebarSourceGroupIcon.tab.symbolName == "macwindow")
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
mise run test -- --filter "SidebarSourceGroupHeaderTests"
```

Expected:

- FAIL because `SidebarSourceGroupHeader` and `SidebarSourceGroupIcon` do not exist.

- [ ] **Step 3: Add `SidebarSourceGroupIcon`**

Create `Sources/AgentStudio/SharedComponents/SidebarSourceGroupIcon.swift`:

```swift
import AppKit
import SwiftUI

enum SidebarSourceGroupIcon: Equatable {
    enum SymbolKind: Equatable {
        case system
        case octicon
    }

    case repo
    case coloredRepo(colorHex: String)
    case checkout(colorHex: String, isMain: Bool)
    case pane
    case tab
    case workspace
    case otherSources

    var symbolName: String {
        switch self {
        case .repo, .coloredRepo:
            return "octicon-repo"
        case .checkout(_, let isMain):
            return isMain ? "octicon-star-fill" : "octicon-git-worktree"
        case .pane:
            return "rectangle.inset.filled"
        case .tab:
            return "macwindow"
        case .workspace:
            return "building.2"
        case .otherSources:
            return "tray"
        }
    }

    var symbolKind: SymbolKind {
        switch self {
        case .repo, .coloredRepo, .checkout:
            return .octicon
        case .pane, .tab, .workspace, .otherSources:
            return .system
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .coloredRepo(let colorHex), .checkout(let colorHex, _):
            return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
        case .repo, .pane, .tab, .workspace, .otherSources:
            return .secondary
        }
    }

    var rotationDegrees: Double {
        switch self {
        case .checkout(_, let isMain):
            return isMain ? 0 : 180
        case .repo, .coloredRepo, .pane, .tab, .workspace, .otherSources:
            return 0
        }
    }
}
```

- [ ] **Step 4: Add the source group header chrome policy**

In `Sources/AgentStudio/SharedComponents/SidebarSurfaceChrome.swift`, update:

```swift
enum SidebarHeaderChromePolicy: Equatable {
    case plainSectionHeader
    case repoGroupHeader
    case sourceGroupHeader
}
```

- [ ] **Step 5: Add `SidebarSourceGroupHeader`**

Create `Sources/AgentStudio/SharedComponents/SidebarSourceGroupHeader.swift`:

```swift
import SwiftUI

struct SidebarSourceGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let icon: SidebarSourceGroupIcon
    let title: String
    let secondaryTitle: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    static var chromePolicy: SidebarHeaderChromePolicy {
        .sourceGroupHeader
    }

    static var leadingInset: CGFloat {
        AppStyles.Shell.Sidebar.listRowLeadingInset
    }

    var body: some View {
        Button(action: onToggle) {
            SidebarSectionHeaderRow(isCollapsed: isCollapsed) {
                HStack(spacing: AppStyles.General.Spacing.standard) {
                    headerIcon
                        .frame(
                            width: AppStyles.Shell.Sidebar.groupIconSize,
                            alignment: .leading
                        )

                    HStack(spacing: AppStyles.Shell.Sidebar.groupTitleSpacing) {
                        Text(title)
                            .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(2)

                        if let secondaryTitle, !secondaryTitle.isEmpty {
                            Text("·")
                                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text(secondaryTitle)
                                .font(
                                    .system(
                                        size: AppStyles.Shell.Sidebar.groupOrganizationFontSize,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(
                                    maxWidth: AppStyles.Shell.Sidebar.groupOrganizationMaxWidth,
                                    alignment: .leading
                                )
                                .layoutPriority(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
                .contentShape(Rectangle())
            } trailingContent: {
                trailingContent()
            }
            .padding(.leading, Self.leadingInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch icon.symbolKind {
        case .system:
            Image(systemName: icon.symbolName)
                .font(.system(size: AppStyles.Shell.Sidebar.groupIconSize, weight: .medium))
                .foregroundStyle(icon.foregroundStyle)
        case .octicon:
            OcticonImage(name: icon.symbolName, size: AppStyles.Shell.Sidebar.groupIconSize)
                .foregroundStyle(icon.foregroundStyle)
                .rotationEffect(.degrees(icon.rotationDegrees))
        }
    }
}

extension SidebarSourceGroupHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        icon: SidebarSourceGroupIcon,
        title: String,
        secondaryTitle: String?,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.icon = icon
        self.title = title
        self.secondaryTitle = secondaryTitle
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}
```

- [ ] **Step 6: Rebuild `SidebarRepoGroupHeader` as a wrapper**

Replace `Sources/AgentStudio/SharedComponents/SidebarRepoGroupHeader.swift` with:

```swift
import SwiftUI

struct SidebarRepoGroupHeader<TrailingContent: View>: View {
    let isCollapsed: Bool
    let repoTitle: String
    let organizationName: String?
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    static var chromePolicy: SidebarHeaderChromePolicy {
        SidebarSourceGroupHeader<TrailingContent>.chromePolicy
    }

    static var leadingInset: CGFloat {
        SidebarSourceGroupHeader<TrailingContent>.leadingInset
    }

    var body: some View {
        SidebarSourceGroupHeader(
            isCollapsed: isCollapsed,
            icon: .repo,
            title: repoTitle,
            secondaryTitle: organizationName,
            onToggle: onToggle
        ) {
            trailingContent()
        }
    }
}

extension SidebarRepoGroupHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        repoTitle: String,
        organizationName: String?,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.repoTitle = repoTitle
        self.organizationName = organizationName
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}
```

- [ ] **Step 7: Run shared component and architecture tests**

Run:

```bash
mise run test -- --filter "SidebarSourceGroupHeaderTests|SidebarSurfaceConvergenceTests"
```

Expected:

- PASS for `SidebarSourceGroupHeaderTests`.
- `SidebarSurfaceConvergenceTests` may still fail until Inbox header code is migrated in Task 4.

---

## Task 3: Model All Inbox Group Headers As Source Groups

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift`

- [ ] **Step 1: Add failing grouping model tests**

Add to `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`:

```swift
@Test("repo pane tab and fallback groups all produce source group headers")
func allGroupedSectionsProduceSourceGroupHeaders() {
    let repoId = UUID()
    let paneId = UUID()
    let parentPaneId = UUID()
    let tabId = UUID()
    let repoNotification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Repo event",
        paneId: paneId,
        tabId: tabId,
        repoId: repoId,
        repoName: "agent-studio",
        worktreeName: "notification-inbox-redesign",
        tabDisplayLabel: "Tab 2",
        paneDisplayLabel: "Pane 1"
    )
    let drawerNotification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 110),
        title: "Drawer event",
        paneId: UUID(),
        tabId: tabId,
        repoId: repoId,
        repoName: "agent-studio",
        worktreeName: "notification-inbox-redesign",
        tabDisplayLabel: "Tab 2",
        paneDisplayLabel: "Drawer",
        paneRole: .drawerChild,
        parentPaneId: parentPaneId,
        parentPaneDisplayLabel: "Pane 1"
    )
    let globalNotification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 120),
        title: "Workspace event"
    )

    let byRepo = InboxNotificationListModel(
        notifications: [repoNotification, globalNotification],
        grouping: .byRepo,
        sort: .newestFirst,
        searchText: ""
    )
    let byPane = InboxNotificationListModel(
        notifications: [repoNotification, drawerNotification],
        grouping: .byPane,
        sort: .newestFirst,
        searchText: ""
    )
    let byTab = InboxNotificationListModel(
        notifications: [repoNotification],
        grouping: .byTab,
        sort: .newestFirst,
        searchText: ""
    )

    #expect(byRepo.sections.allSatisfy { $0.header?.style == .sourceGroup })
    #expect(byPane.sections.allSatisfy { $0.header?.style == .sourceGroup })
    #expect(byTab.sections.allSatisfy { $0.header?.style == .sourceGroup })
    #expect(byRepo.sections.contains { $0.header?.title == "Other sources" })
}
```

Add to the existing by-pane grouping test or add a new one:

```swift
@Test("by-pane grouping uses parent pane scope for drawer children")
func byPaneGroupingUsesParentPaneScopeForDrawerChildren() {
    let parentPaneId = UUID()
    let parent = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Parent",
        paneId: parentPaneId,
        paneDisplayLabel: "Pane project-dev"
    )
    let drawer = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 101),
        title: "Drawer",
        paneId: UUID(),
        paneDisplayLabel: "Drawer",
        paneRole: .drawerChild,
        parentPaneId: parentPaneId,
        parentPaneDisplayLabel: "Pane project-dev"
    )

    let model = InboxNotificationListModel(
        notifications: [parent, drawer],
        grouping: .byPane,
        sort: .newestFirst,
        searchText: ""
    )

    #expect(model.sections.count == 1)
    #expect(model.sections[0].header?.title == "Pane project-dev")
}
```

- [ ] **Step 2: Run model tests and verify they fail**

Run:

```bash
mise run test -- --filter "InboxNotificationListModelTests.allGroupedSectionsProduceSourceGroupHeaders|InboxNotificationListModelTests.byPaneGroupingUsesParentPaneScopeForDrawerChildren"
```

Expected:

- FAIL because `InboxNotificationListSectionHeader.Style.sourceGroup` and `header.title` do not exist or because `.plain` is still used.

- [ ] **Step 3: Replace the header model with source-group fields**

In `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`, replace `InboxNotificationListSectionHeader` with:

```swift
struct InboxNotificationListSectionHeader: Equatable {
    enum SourceKind: Equatable {
        case repo(organizationName: String?)
        case pane
        case tab
        case workspace
        case otherSources
    }

    enum Style: Equatable {
        case sourceGroup
    }

    let title: String
    let secondaryTitle: String?
    let sourceKind: SourceKind

    var label: String? {
        title
    }

    var style: Style {
        .sourceGroup
    }
}
```

Update `InboxNotificationListSection.label` to keep compiling:

```swift
var label: String? {
    header?.label
}
```

- [ ] **Step 4: Update section builders**

In the `.byRepo` builder, use:

```swift
header: { groupKey, items in
    switch groupKey {
    case .repoName(let name):
        return InboxNotificationListSectionHeader(
            title: name,
            secondaryTitle: nil,
            sourceKind: .repo(organizationName: nil)
        )
    case .noRepo:
        return InboxNotificationListSectionHeader(
            title: "Other sources",
            secondaryTitle: nil,
            sourceKind: .otherSources
        )
    default:
        return InboxNotificationListSectionHeader(
            title: bestGroupLabel(
                for: items,
                grouping: .byRepo,
                placeholder: "Other sources"
            ),
            secondaryTitle: nil,
            sourceKind: .repo(organizationName: nil)
        )
    }
}
```

In the `.byPane` builder, use:

```swift
header: { _, items in
    InboxNotificationListSectionHeader(
        title: bestGroupLabel(for: items, grouping: .byPane, placeholder: "Other panes"),
        secondaryTitle: nil,
        sourceKind: .pane
    )
}
```

In the `.byTab` builder, use:

```swift
header: { _, items in
    InboxNotificationListSectionHeader(
        title: bestGroupLabel(for: items, grouping: .byTab, placeholder: "Untitled Tab"),
        secondaryTitle: nil,
        sourceKind: .tab
    )
}
```

- [ ] **Step 5: Run model tests**

Run:

```bash
mise run test -- --filter "InboxNotificationListModelTests|InboxNotificationSourceDisplayTests"
```

Expected:

- PASS for model/source display tests.
- Compile failures in view tests are expected until Task 4 updates view code.

---

## Task 4: Render Every Inbox Group Through The Shared Header

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

- [ ] **Step 1: Add failing source-kind-to-icon tests**

Add to `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`:

```swift
@Test("inbox group header maps every source kind to a fixed icon slot")
@MainActor
func inboxGroupHeaderMapsEverySourceKindToFixedIconSlot() {
    #expect(
        InboxNotificationGroupHeader.icon(for: .repo(organizationName: nil))
            == .repo
    )
    #expect(InboxNotificationGroupHeader.icon(for: .pane) == .pane)
    #expect(InboxNotificationGroupHeader.icon(for: .tab) == .tab)
    #expect(InboxNotificationGroupHeader.icon(for: .workspace) == .workspace)
    #expect(InboxNotificationGroupHeader.icon(for: .otherSources) == .otherSources)
}
```

- [ ] **Step 2: Run the view test and verify it fails**

Run:

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests.inboxGroupHeaderMapsEverySourceKindToFixedIconSlot|InboxNotificationSidebarViewTests.groupedInboxHeadersUseSourceGroupHeaderChrome"
```

Expected:

- FAIL because `InboxNotificationGroupHeader.icon(for:)` does not exist.

- [ ] **Step 3: Replace `InboxNotificationGroupHeader` rendering**

Replace `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift` with:

```swift
import SwiftUI

struct InboxNotificationGroupHeader: View {
    let header: InboxNotificationListSectionHeader
    let unreadCount: Int
    let isCollapsed: Bool
    var showsUnreadCount = true
    let onToggle: () -> Void

    static func chromePolicy(for _: InboxNotificationListSectionHeader.Style) -> SidebarHeaderChromePolicy {
        SidebarSourceGroupHeader<EmptyView>.chromePolicy
    }

    static func icon(for sourceKind: InboxNotificationListSectionHeader.SourceKind) -> SidebarSourceGroupIcon {
        switch sourceKind {
        case .repo:
            return .repo
        case .pane:
            return .pane
        case .tab:
            return .tab
        case .workspace:
            return .workspace
        case .otherSources:
            return .otherSources
        }
    }

    var body: some View {
        SidebarSourceGroupHeader(
            isCollapsed: isCollapsed,
            icon: Self.icon(for: header.sourceKind),
            title: header.title,
            secondaryTitle: header.secondaryTitle,
            onToggle: onToggle
        ) {
            unreadBadge()
        }
        .accessibilityIdentifier("inboxSourceGroupHeader")
    }

    @ViewBuilder
    private func unreadBadge() -> some View {
        if unreadCount > 0, showsUnreadCount {
            UnreadCountBadge(text: "\(unreadCount)")
                .accessibilityIdentifier("inboxGroupUnreadBadge")
        }
    }
}
```

- [ ] **Step 4: Run header and sidebar tests**

Run:

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests|SidebarSurfaceConvergenceTests|SidebarSourceGroupHeaderTests"
```

Expected:

- PASS for header chrome and icon mapping tests.
- Existing tests for hiding by-pane unread count still pass.

---

## Task 5: Fix The Protruding Terminal Icon Without Breaking Metadata Alignment

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxRowTests.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [ ] **Step 1: Add failing row contract tests**

Add to `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxRowTests.swift`:

```swift
@Test("placement metadata keeps reserved title column without terminal leading icon")
func placementMetadataKeepsReservedTitleColumnWithoutTerminalLeadingIcon() {
    #expect(InboxRow.placementMetadataIconSystemName == nil)
    #expect(InboxRow.usesReservedMetadataIconColumn)
}
```

Add to `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`:

```swift
@Test("pane inbox row uses same metadata leading alignment as global inbox")
func paneInboxRowUsesSameMetadataLeadingAlignmentAsGlobalInbox() {
    #expect(PaneInboxNotificationPopover.rowChromePolicy == .sidebarRowShell)
    #expect(InboxRow.usesReservedMetadataIconColumn)
}
```

- [ ] **Step 2: Run row tests and verify they fail**

Run:

```bash
mise run test -- --filter "InboxRowTests.placementMetadataKeepsReservedTitleColumnWithoutTerminalLeadingIcon|PaneInboxNotificationPopoverTests.paneInboxRowUsesSameMetadataLeadingAlignmentAsGlobalInbox"
```

Expected:

- FAIL because `InboxRow.placementMetadataIconSystemName` and `InboxRow.usesReservedMetadataIconColumn` do not exist.

- [ ] **Step 3: Update `InboxRow` placement metadata policy**

In `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`, add:

```swift
static let placementMetadataIconSystemName: String? = nil
static let usesReservedMetadataIconColumn = true
```

Keep `metadataLine` using `SidebarMetadataLine`'s default reserved icon-column behavior:

```swift
static func metadataLine(
    iconSystemName: String? = nil,
    text: String,
    prominence: SidebarMetadataProminence = .secondary
) -> SidebarMetadataLine {
    SidebarMetadataLine(
        iconSystemName: iconSystemName,
        text: text,
        prominence: prominence
    )
}
```

Update placement rendering:

```swift
if let placementLine = display.placementLine {
    Self.metadataLine(
        iconSystemName: Self.placementMetadataIconSystemName,
        text: placementLine,
        prominence: .secondary
    )
}
```

- [ ] **Step 4: Run row tests**

Run:

```bash
mise run test -- --filter "InboxRowTests|PaneInboxNotificationPopoverTests"
```

Expected:

- PASS.
- Placement metadata no longer draws a terminal icon in the unread-dot column.
- Source, placement, and detail metadata keep the reserved leading spacer so text still aligns under the notification title.

---

## Task 6: Add Source Color Parity Without Expanding State

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

- [ ] **Step 1: Add failing color contract test**

Add to `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`:

```swift
@Test("repo source group can carry checkout accent color")
@MainActor
func repoSourceGroupCanCarryCheckoutAccentColor() {
    let icon = InboxNotificationGroupHeader.icon(
        for: .repo(organizationName: "askluna"),
        accentColorHex: "#EAC54F"
    )

    if case .coloredRepo(let colorHex) = icon {
        #expect(colorHex == "#EAC54F")
    } else {
        Issue.record("Expected colored repo source icon for repo group with accent color")
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests.repoSourceGroupCanCarryCheckoutAccentColor"
```

Expected:

- FAIL because `InboxNotificationGroupHeader.icon(for:accentColorHex:)` does not exist.

- [ ] **Step 3: Add repo presentation data to section header**

In `InboxNotificationListSectionHeader`, add:

```swift
let accentColorHex: String?
```

Update every initializer site from Task 3:

```swift
        accentColorHex: nil
```

Do not add new atom state. This field is view/model presentation data derived from existing notification source identity and existing sidebar color information.

Add a small value type so the model can resolve the same repo group title, organization label, and color that RepoExplorer uses:

```swift
struct InboxNotificationRepoGroupPresentation: Equatable {
    let title: String
    let organizationName: String?
    let accentColorHex: String?
}
```

Update `InboxNotificationListModel.init` with a defaulted resolver so existing tests and callers continue to compile until they opt into repo presentation:

```swift
init(
    notifications: [InboxNotification],
    grouping: InboxNotificationGrouping,
    sort: InboxNotificationSort,
    searchText: String,
    filter: InboxFilter? = nil,
    collapsedGroups: Set<InboxNotificationGroupKey> = [],
    repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation? = { _ in nil }
) {
    let sortedNotifications = Self.sortNotifications(notifications, sort: sort)
    let sourceFilteredNotifications = Self.filterNotifications(
        sortedNotifications,
        filter: filter
    )
    let sourceItems = sourceFilteredNotifications.map(InboxNotificationListItem.init)
    let textFilteredItems = Self.filterItems(
        sourceItems,
        searchText: searchText
    )
    self.sections = Self.buildSections(
        items: textFilteredItems,
        grouping: grouping,
        collapsedGroups: collapsedGroups,
        repoPresentation: repoPresentation
    )
}
```

Update `buildSections` and `buildGroupedSections` signatures to carry the resolver:

```swift
private static func buildSections(
    items: [InboxNotificationListItem],
    grouping: InboxNotificationGrouping,
    collapsedGroups: Set<InboxNotificationGroupKey>,
    repoPresentation: (UUID?) -> InboxNotificationRepoGroupPresentation?
) -> [InboxNotificationListSection]
```

When creating repo headers, resolve once from the first repo-backed notification in the bucket:

```swift
let resolvedRepoPresentation = repoPresentation(items.first?.notification.repoId)

return InboxNotificationListSectionHeader.sourceGroup(
    title: resolvedRepoPresentation?.title ?? bestGroupLabel(
        for: items,
        grouping: .byRepo,
        placeholder: "Other sources"
    ),
    secondaryTitle: resolvedRepoPresentation?.organizationName,
    sourceKind: .repo(organizationName: resolvedRepoPresentation?.organizationName),
    accentColorHex: resolvedRepoPresentation?.accentColorHex
)
```

This keeps the default behavior testable: callers that do not provide a resolver get neutral repo icons, and the Inbox must still align correctly.

- [ ] **Step 4: Add accent-aware icon mapping**

In `InboxNotificationGroupHeader`, add:

```swift
static func icon(
    for sourceKind: InboxNotificationListSectionHeader.SourceKind,
    accentColorHex: String?
) -> SidebarSourceGroupIcon {
    switch sourceKind {
    case .repo:
        if let accentColorHex {
            return .coloredRepo(colorHex: accentColorHex)
        }
        return .repo
    case .pane:
        return .pane
    case .tab:
        return .tab
    case .workspace:
        return .workspace
    case .otherSources:
        return .otherSources
    }
}
```

Update the existing `icon(for:)` helper:

```swift
static func icon(for sourceKind: InboxNotificationListSectionHeader.SourceKind) -> SidebarSourceGroupIcon {
    icon(for: sourceKind, accentColorHex: nil)
}
```

Update `body`:

```swift
SidebarSourceGroupHeader(
    isCollapsed: isCollapsed,
    icon: Self.icon(for: header.sourceKind, accentColorHex: header.accentColorHex),
    title: header.title,
    secondaryTitle: header.secondaryTitle,
    onToggle: onToggle
) {
    unreadBadge()
}
.accessibilityIdentifier("inboxSourceGroupHeader")
```

- [ ] **Step 5: Pass existing repo cache state into the inbox surface**

In `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`, update `SidebarRootViewDependencies`:

```swift
struct SidebarRootViewDependencies {
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let uiState: UIStateAtom
    let sidebarCache: SidebarCacheAtom
    let inboxFilterDraft: InboxFilterDraftAtom
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let onRefocusActivePane: () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void
}
```

Update the default builder:

```swift
SidebarSurfaceHost(
    store: dependencies.store,
    repoCache: dependencies.repoCache,
    uiState: dependencies.uiState,
    sidebarCache: dependencies.sidebarCache,
    inboxFilterDraft: dependencies.inboxFilterDraft,
    inboxAtom: dependencies.inboxAtom,
    prefsAtom: dependencies.prefsAtom,
    onRefocusActivePane: dependencies.onRefocusActivePane,
    onDismissInbox: dependencies.onDismissInbox
)
```

Update the dependency construction in `viewDidLoad`:

```swift
SidebarRootViewDependencies(
    store: store,
    repoCache: repoCache,
    uiState: uiState,
    sidebarCache: atom(\.sidebarCache),
    inboxFilterDraft: atom(\.inboxFilterDraft),
    inboxAtom: inboxAtom,
    prefsAtom: inboxPrefsAtom,
    onRefocusActivePane: { [weak paneTabVC] in
        paneTabVC?.refocusActivePane()
    },
    onDismissInbox: { [weak self] in
        self?.collapseSidebar()
        self?.refocusActivePane()
    }
)
```

In `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`, add:

```swift
let repoCache: RepoCacheAtom
```

and pass it into `InboxNotificationSidebarView`:

```swift
InboxNotificationSidebarView(
    inboxAtom: inboxAtom,
    prefsAtom: prefsAtom,
    uiState: uiState,
    sidebarCache: sidebarCache,
    inboxFilterDraft: inboxFilterDraft,
    workspacePaneAtom: store.paneAtom,
    workspaceRepositoryTopologyAtom: store.repositoryTopologyAtom,
    repoCache: repoCache,
    dispatcher: .shared,
    onRefocusActivePane: onDismissInbox
)
```

- [ ] **Step 6: Derive repo presentation from existing repo/sidebar atoms**

In `InboxNotificationSidebarView`, add a helper that derives repo group title, owner label, and checkout color from existing sidebar/repo state. Keep it feature-local and value-returning:

```swift
static func repoPresentationByRepoId(
    repos: [Repo],
    repoEnrichmentByRepoId: [UUID: RepoEnrichment],
    checkoutColors: [SidebarCheckoutColorKey: String]
) -> [UUID: InboxNotificationRepoGroupPresentation] {
    let sidebarRepos = repos.map(RepoPresentationItem.init(repo:))
    let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
        repos: sidebarRepos,
        repoEnrichmentByRepoId: repoEnrichmentByRepoId
    )
    let resolvedGroups = RepoPresentationGrouping.buildGroups(
        repos: sidebarRepos,
        metadataByRepoId: repoMetadataById
    )
    let checkoutColorOverrides = Dictionary(
        uniqueKeysWithValues: checkoutColors.map { key, value in
            (key.rawValue, value)
        }
    )

    var presentationsByRepoId: [UUID: InboxNotificationRepoGroupPresentation] = [:]
    for group in resolvedGroups {
        for repo in group.repos {
            presentationsByRepoId[repo.id] = InboxNotificationRepoGroupPresentation(
                title: group.repoTitle,
                organizationName: group.organizationName,
                accentColorHex: RepoPresentationColoring.checkoutColorHex(
                    for: repo,
                    in: group,
                    checkoutColorOverrides: checkoutColorOverrides
                )
            )
        }
    }
    return presentationsByRepoId
}
```

Update `InboxNotificationSidebarView` stored properties and initializer:

```swift
let workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
let repoCache: RepoCacheAtom
```

Add a `repoPresentationFingerprint` to `InboxNotificationListModelKey`, and refresh the cached model when the derived presentation fingerprint changes. This prevents stale colors or owner labels when repo identity or sidebar color overrides update.

When refreshing `cachedListModel`, pass the presentation resolver:

```swift
let resolvedRepoPresentationByRepoId = repoPresentationByRepoId
cachedListModel = InboxNotificationListModel(
    notifications: inboxAtom.notifications,
    grouping: prefsAtom.grouping,
    sort: prefsAtom.sort,
    searchText: searchText,
    filter: activeFilter,
    collapsedGroups: sidebarCache.collapsedInboxGroups,
    repoPresentation: { repoId in
        guard let repoId else { return nil }
        return resolvedRepoPresentationByRepoId[repoId]
    }
)
```

Add the same argument at initial model construction in `init`.

- [ ] **Step 7: Run color and sidebar tests**

Run:

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests.repoSourceGroupCanCarryCheckoutAccentColor|InboxNotificationSidebarViewTests|SidebarSurfaceConvergenceTests"
```

Expected:

- PASS if existing data access is available.
- If Step 5 reveals dependency drift, stop and reconverge before adding dependencies to the view.

- [ ] **Step 8: Update all direct initializer call sites**

Any direct `InboxNotificationSidebarView(...)` call must pass the new dependencies or use a test-only convenience helper. Update at least:

```text
Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift
Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift
```

For tests, use local atoms:

```swift
let workspaceRepositoryTopologyAtom = WorkspaceRepositoryTopologyAtom()
let repoCache = RepoCacheAtom()

InboxNotificationSidebarView(
    inboxAtom: InboxNotificationAtom(),
    prefsAtom: InboxNotificationPrefsAtom(),
    uiState: UIStateAtom(),
    sidebarCache: SidebarCacheAtom(),
    inboxFilterDraft: InboxFilterDraftAtom(),
    workspacePaneAtom: WorkspacePaneAtom(),
    workspaceRepositoryTopologyAtom: workspaceRepositoryTopologyAtom,
    repoCache: repoCache,
    dispatcher: CommandDispatcher.shared,
    onRefocusActivePane: {}
)
```

Run:

```bash
rg -n "InboxNotificationSidebarView\\(" Sources/AgentStudio Tests/AgentStudioTests
mise run test -- --filter "InboxNotificationSidebarViewTests"
```

Expected:

- Every direct initializer call is updated.
- `InboxNotificationSidebarViewTests` passes.

---

## Task 7: Prove Every Grouping Mode In Mounted Views

**Files:**
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [ ] **Step 1: Add mounted By Repo header test**

Add to `InboxNotificationSidebarViewTests.swift`:

```swift
@Test("mounted by-repo inbox renders source group headers for repo and fallback groups")
func mountedByRepoInboxRendersSourceGroupHeadersForRepoAndFallbackGroups() throws {
    let notification = makeSourceNotification(repoName: "askluna")
    let fallback = InboxNotification(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 200),
        kind: .agentRpc,
        title: "Workspace event",
        body: nil,
        source: .global,
        isRead: false,
        isDismissedFromPaneInbox: false
    )
    let sections = InboxNotificationListModel(
        notifications: [notification, fallback],
        grouping: .byRepo,
        sort: .newestFirst,
        searchText: "",
        filter: nil,
        collapsedGroups: []
    ).sections

    let hostingView = NSHostingView(
        rootView: InboxSidebarRootHarness(
            activeFilter: nil,
            activeFilterLabel: nil,
            grouping: .byRepo,
            sections: sections
        )
        .frame(width: 360, height: 420)
    )
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    hostingView.layoutSubtreeIfNeeded()

    #expect(accessibleElementCount(in: hostingView, identifier: "inboxSourceGroupHeader") == 2)
}
```

- [ ] **Step 2: Add mounted By Pane and By Tab header tests**

Add:

```swift
@Test("mounted by-pane and by-tab inbox render source group headers")
func mountedByPaneAndByTabInboxRenderSourceGroupHeaders() {
    let paneNotification = makeSourceNotification(
        paneDisplayLabel: "Pane project-dev",
        tabDisplayLabel: "Tab 2"
    )
    let byPane = InboxNotificationListModel(
        notifications: [paneNotification],
        grouping: .byPane,
        sort: .newestFirst,
        searchText: "",
        filter: nil,
        collapsedGroups: []
    ).sections
    let byTab = InboxNotificationListModel(
        notifications: [paneNotification],
        grouping: .byTab,
        sort: .newestFirst,
        searchText: "",
        filter: nil,
        collapsedGroups: []
    ).sections

    let byPaneHostingView = NSHostingView(
        rootView: InboxSidebarRootHarness(
            activeFilter: nil,
            activeFilterLabel: nil,
            grouping: .byPane,
            sections: byPane
        )
        .frame(width: 360, height: 420)
    )
    let byPaneWindow = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    byPaneWindow.contentView = byPaneHostingView
    byPaneWindow.makeKeyAndOrderFront(nil)
    defer { byPaneWindow.orderOut(nil) }
    byPaneHostingView.layoutSubtreeIfNeeded()

    let byTabHostingView = NSHostingView(
        rootView: InboxSidebarRootHarness(
            activeFilter: nil,
            activeFilterLabel: nil,
            grouping: .byTab,
            sections: byTab
        )
        .frame(width: 360, height: 420)
    )
    let byTabWindow = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 360, height: 420),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    byTabWindow.contentView = byTabHostingView
    byTabWindow.makeKeyAndOrderFront(nil)
    defer { byTabWindow.orderOut(nil) }
    byTabHostingView.layoutSubtreeIfNeeded()

    #expect(byPane.allSatisfy { $0.header?.style == .sourceGroup })
    #expect(byTab.allSatisfy { $0.header?.style == .sourceGroup })
    #expect(byPane.first?.header?.sourceKind == .pane)
    #expect(byTab.first?.header?.sourceKind == .tab)
    #expect(accessibleElementCount(in: byPaneHostingView, identifier: "inboxSourceGroupHeader") == 1)
    #expect(accessibleElementCount(in: byTabHostingView, identifier: "inboxSourceGroupHeader") == 1)
}
```

- [ ] **Step 3: Run mounted grouping tests**

Run:

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests.mountedByRepoInboxRendersSourceGroupHeadersForRepoAndFallbackGroups|InboxNotificationSidebarViewTests.mountedByPaneAndByTabInboxRenderSourceGroupHeaders|PaneInboxNotificationPopoverTests"
```

Expected:

- PASS.
- No mounted test uses wall-clock sleeps.

---

## Task 8: Visual Verification With Repo Sidebar Comparison

**Files:**
- Create: `docs/wip/debugging/2026-05-14-notification-inbox-sidebar-contract-visual.md`
- Read only during capture: `tmp/visual-verification/`

- [ ] **Step 1: Build the app**

Run:

```bash
mise run build
```

Expected:

- Exit 0.
- Output includes `[swift-build-slot] using .build-agent-N`.

- [ ] **Step 2: Launch the debug app without killing any user app**

Run:

```bash
BUILD_PATH=$(ls -dt .build-agent-*/debug/AgentStudio 2>/dev/null | head -1 | xargs dirname | xargs dirname)
"$BUILD_PATH/debug/AgentStudio" &
PID=$!
echo "$PID"
```

Expected:

- Prints a PID.
- Do not use `pkill`.

- [ ] **Step 3: Capture Repo sidebar**

Preferred:

```bash
peekaboo see --app "PID:$PID" \
  --path tmp/visual-verification/2026-05-14-repo-sidebar.png \
  --json > tmp/visual-verification/2026-05-14-repo-sidebar.json
```

Fallback if Peekaboo cannot capture the debug app:

```bash
screencapture -x tmp/visual-verification/2026-05-14-repo-sidebar-fallback.png
```

Expected:

- Captured image shows Repo sidebar.
- Fallback capture is allowed only if the debug app is the visible frontmost window and the visual doc records that condition.
- If both capture routes fail, record the exact error in the visual doc and do not claim visual acceptance.

- [ ] **Step 4: Switch to Inbox and capture every grouping mode**

Use accessibility click or manual click against the launched debug app PID. Capture:

```text
tmp/visual-verification/2026-05-14-inbox-none.png
tmp/visual-verification/2026-05-14-inbox-by-repo.png
tmp/visual-verification/2026-05-14-inbox-by-pane.png
tmp/visual-verification/2026-05-14-inbox-by-tab.png
tmp/visual-verification/2026-05-14-pane-inbox.png
```

Use the same PID-targeted Peekaboo command shape for each image. If native fallback is required, bring the launched debug app window to the front first and record that the fallback is screen-based rather than PID/window-based.

Expected visual checks:

- Group chevrons line up with RepoExplorer group chevrons.
- Group icons line up with RepoExplorer group icons.
- Group titles line up with RepoExplorer group titles.
- Child notification rows have the same child indent as RepoExplorer worktree rows.
- `Other sources` has a neutral icon and does not jump left.
- `By Pane` and `By Tab` use the same header size and icon slot as `By Repo`.
- The terminal placement text no longer has a terminal icon protruding into the unread-dot column.
- PaneInbox does not show group count pills.
- Background material and row hover/selection color read as the same sidebar family.

- [ ] **Step 5: Write the visual evidence doc**

Create `docs/wip/debugging/2026-05-14-notification-inbox-sidebar-contract-visual.md`:

```markdown
# 2026-05-14 Notification Inbox Sidebar Contract Visual Verification

## Environment

- Branch: notification-inbox-redesign
- App PID: <PID printed by launch command>
- Build path: <.build-agent-N/debug/AgentStudio>
- Capture tool: Peekaboo or native screencapture fallback

## Captures

- Repo sidebar: `tmp/visual-verification/2026-05-14-repo-sidebar.png`
- Inbox none: `tmp/visual-verification/2026-05-14-inbox-none.png`
- Inbox by repo: `tmp/visual-verification/2026-05-14-inbox-by-repo.png`
- Inbox by pane: `tmp/visual-verification/2026-05-14-inbox-by-pane.png`
- Inbox by tab: `tmp/visual-verification/2026-05-14-inbox-by-tab.png`
- PaneInbox: `tmp/visual-verification/2026-05-14-pane-inbox.png`

## Visual Acceptance Checklist

- [ ] Repo and Inbox backgrounds match.
- [ ] Header control row does not visually collide with list rows.
- [ ] Group chevrons align.
- [ ] Group icons align.
- [ ] Group titles align.
- [ ] Child rows align.
- [ ] `Other sources` reserves the source icon column.
- [ ] `By Pane` groups by parent pane scope.
- [ ] `By Pane` does not show noisy count pills.
- [ ] `By Tab` uses the same source group header grammar.
- [ ] Terminal placement text no longer shows a protruding terminal icon.
- [ ] Hover/selection fills match RepoExplorer row chrome.

## Notes

Record any remaining visual drift here with screenshot coordinates and the owning file.
```

Replace angle-bracket placeholders before committing the doc.

---

## Task 9: Full Verification, Xhigh Review, Commit, Push, PR Update

**Files:**
- All modified source/test/doc files.

- [ ] **Step 1: Format**

Run:

```bash
mise run format
```

Expected:

- Exit 0.
- Swift sources formatted.

- [ ] **Step 2: Focused regression**

Run:

```bash
mise run test -- --filter "SidebarSourceGroupHeaderTests|SidebarSurfaceConvergenceTests|InboxNotificationListModelTests|InboxNotificationSourceDisplayTests|InboxNotificationSidebarViewTests|InboxRowTests|PaneInboxNotificationPopoverTests"
```

Expected:

- Exit 0.
- All focused suites pass.

- [ ] **Step 3: Lint**

Run:

```bash
mise run lint
```

Expected:

- Exit 0.
- swift-format lint OK.
- swiftlint 0 serious violations.
- Core boundary import check passed.

- [ ] **Step 4: Full default test suite**

Run:

```bash
mise run test
```

Expected:

- Exit 0.
- Record pass counts from output.
- Default-skipped E2E lanes may remain skipped if the project default skips them.

- [ ] **Step 5: Dirty-work and vendor check**

Run:

```bash
git status --short --branch
git diff --name-only | rg '(^vendor/|zmx|ghostty)' || true
```

Expected:

- Only intended source/test/doc files are modified.
- No `vendor/zmx`, `vendor/ghostty`, or Ghostty app files are modified.

- [ ] **Step 6: Xhigh review**

Spawn a reviewer subagent with this prompt:

```text
Review the uncommitted diff in /Users/shravansunder/Documents/dev/project-dev/agent-studio.notification-inbox-redesign.

Scope:
- Notification Inbox sidebar contract convergence with RepoExplorer.
- SharedComponents boundaries.
- All grouping modes: none, by repo, by pane, by tab.
- Terminal metadata icon alignment.
- PaneInbox count/row behavior.
- Tests and visual verification doc.

Check:
- no atom/store/event-bus sprawl
- no Core -> Features import violations
- shared components are stateless and atom-free
- repo sidebar visual contract is preserved
- tests cover the automatic regression surface
- no zmx/Ghostty app files touched

Return P0-P3 findings with file:line evidence.
```

Expected:

- No P0/P1 findings.
- Address any valid P2/P3 finding before commit.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/AgentStudio Tests/AgentStudioTests docs/superpowers/plans/2026-05-14-notification-inbox-sidebar-contract-convergence.md docs/wip/debugging/2026-05-14-notification-inbox-sidebar-contract-visual.md
git commit -m "Align notification inbox with sidebar contract

Co-authored-by: Codex <noreply@openai.com>"
```

Expected:

- Commit succeeds.
- Commit message contains the Codex trailer exactly once.

- [ ] **Step 8: Push and update PR**

Run:

```bash
git push
gh pr view --web=false --json number,url,headRefName,statusCheckRollup
```

Expected:

- Push succeeds.
- PR is updated.
- PR description or comment includes:
  - focused test counts
  - full `mise run test` counts
  - lint result
  - xhigh review result
  - visual evidence paths
  - explicit note that zmx/Ghostty app files were not touched

---

## Self-Review

### Spec Coverage

- Shared components exist but were too shallow: covered by Tasks 1, 2, and 4.
- Other grouping modes must match: covered by Tasks 3, 4, and 7.
- Misaligned groups: covered by one source header chrome and fixed icon slots in Tasks 2 and 4.
- Terminal icon sticking out: covered by Task 5.
- Repo icon colors/source colors: covered by Task 6.
- PaneInbox no noisy counts: covered by Tasks 4, 7, and 8.
- TUI design target and wrong-shape elimination: covered by `TUI Design Target`.
- Visual evidence: covered by Task 8.
- Tests and pyramid: unit/model tests in Tasks 1, 3, 5, 6; mounted view tests in Task 7; visual smoke in Task 8; full suite in Task 9.
- Architecture boundaries: SharedComponents stay stateless and atom-free; no new atoms/stores/events.
- TDD sequencing: every behavior task starts with a failing test, runs that focused test to confirm red, implements the minimum code, then reruns the focused test before broader verification.
- Defaults: default Inbox preferences remain covered by `InboxNotificationPrefsAtomTests`; default neutral group icon/color behavior is covered by the defaulted `repoPresentation` resolver and source-group icon tests.

### Placeholder Scan

The plan contains no `TBD`, `TODO`, or "implement later" steps. The only angle-bracket values appear inside the visual evidence document template and Task 8 explicitly requires replacing them before committing.

### Type Consistency

The plan consistently uses:

- `SidebarSourceGroupHeader`
- `SidebarSourceGroupIcon`
- `SidebarHeaderChromePolicy.sourceGroupHeader`
- `InboxNotificationListSectionHeader.SourceKind`
- `InboxRow.usesReservedMetadataIconColumn`
- `InboxRow.metadataLeadingMode`

Execution must keep those names or update every plan reference in the same pass.
