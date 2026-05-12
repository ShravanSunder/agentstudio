# Notification Inbox Sidebar Style Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the global notification inbox and PaneInbox inherit Agent Studio's existing RepoExplorer sidebar visual language instead of inventing separate fonts, spacing, backgrounds, indentation, badge placement, and row chrome.

**Architecture:** Treat RepoExplorer as the source-of-truth sidebar surface. Extract reusable style tokens and atom-free shared components into `AppStyles.Shell.Sidebar` and `SharedComponents/`, prove RepoExplorer output stays equivalent, then rebuild inbox surfaces through the same primitives. Notification feature code owns notification content and commands only; shared components own visual geometry and interaction chrome.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit titlebar hosting, Swift Testing, `mise run format`, `mise run lint`, `mise run test`, PID-based Peekaboo visual verification.

---

## Product Acceptance Criteria

- Inbox root background, grouped section rhythm, row indentation, selected row fill, and hover behavior match RepoExplorer.
- Inbox row content is notification-specific but uses the same sidebar layout grammar as RepoExplorer.
- Global sidebar bell badge and PaneInbox drawer bell badge share placement behavior, not only badge drawing.
- Rows show useful source context: repo/worktree, tab, pane number/name, drawer child when known, runtime, and body.
- No row falls back to `unknown source`, UUID prefixes, or raw implementation IDs.
- PaneInbox does not show noisy group/row count numbers unless the user approves that product behavior later.
- Sort/group/filter/clear controls use distinct icons and command/help definitions.
- The new behavior is automatically testable: style contract tests, mounted button tests, production wiring tests, and visual smoke evidence.

## Non-Goals

- Do not implement the notification engine / derived activity work here. That belongs in the separate notification engine worktree.
- Do not add raw terminal output capture.
- Do not add the later Unread/All product toggle.
- Do not split existing Core inbox state smells unless explicitly approved during execution. This plan records them and keeps new work from expanding them.

## Current Evidence And Known Failures

- User screenshots show the inbox sidebar background, row rhythm, group indentation, and global bell badge do not visually match RepoExplorer.
- `docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md` contains the blocking checklist this plan implements.
- RepoExplorer currently uses `Color(nsColor: .windowBackgroundColor)` at `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`.
- RepoExplorer row typography and spacing live mostly in `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift` and `AppStyles.Shell.Sidebar`.
- Inbox rows currently define their own font sizes and padding in `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`.
- The global sidebar badge uses AppKit constraints to the outer `NSButton` frame in `Sources/AgentStudio/App/Windows/MainWindowController.swift`; PaneInbox uses SwiftUI overlay placement in `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`.

## File Structure

### Create

- `Sources/AgentStudio/SharedComponents/SidebarBadgeOverlay.swift`
  - Stateless SwiftUI helper that places `UnreadCountBadge` on a known icon-button hitbox.
  - Imports SwiftUI only.

- `Sources/AgentStudio/SharedComponents/SidebarMetadataLine.swift`
  - Stateless line primitive for icon-column-aligned sidebar metadata.
  - Used by notification rows first; can later be adopted by RepoExplorer if useful.

- `Tests/AgentStudioTests/SharedComponents/SidebarBadgeOverlayTests.swift`
  - Pins construction and placement contract surface.

- `Tests/AgentStudioTests/SharedComponents/SidebarMetadataLineTests.swift`
  - Pins construction and ensures it remains atom-free/value-driven.

- `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerPaneInboxClearTests.swift`
  - Uses production `MainSplitViewController.makePaneInboxPresentation()` wiring with a real `InboxNotificationAtom`.

### Modify

- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  - Add missing reusable sidebar tokens only.
  - Move notification badge placement tokens out of `Components.PaneInbox` if shared by titlebar and drawer.

- `Sources/AgentStudio/SharedComponents/SidebarRowShell.swift`
  - Use `AppStyles.Shell.Sidebar` tokens for padding, corner radius, hover, selected, and flashing fills.
  - Keep atom-free.

- `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift`
  - Add a content-builder overload so RepoExplorer can use it without losing repo title + owner styling.

- `Sources/AgentStudio/SharedComponents/UnreadCountBadge.swift`
  - Keep drawing-only.
  - Do not add placement logic here.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`
  - Adopt `SidebarSectionHeader` only after tests prove output stays equivalent.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
  - Use `SidebarRowShell` if it preserves existing hover/row output.
  - Do not change RepoExplorer appearance as part of this plan.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
  - Remove local font/padding decisions.
  - Render content through sidebar shared primitives and `AppStyles.Shell.Sidebar`.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
  - Match RepoExplorer section header hierarchy.
  - Remove count display from PaneInbox contexts.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
  - Add explicit placement parts for tab/pane/drawer/runtime instead of one long string.
  - Preserve branch/worktree source behavior.

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
  - Use shared root background/style tokens and clear button identifiers.
  - Replace ambiguous group/filter icon if still visually colliding with arrangement/layout.

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
  - Keep feature ownership of content, grouping, filtering, actions.
  - Do not add style constants here.

- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
  - Use same row primitive as global inbox.
  - Keep no Unread/All toggle and no noisy counts.
  - Add clear button identifier.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
  - Use shared badge overlay helper for PaneInbox drawer bell.

- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
  - Replace AppKit badge constraints with shared SwiftUI badge placement, preferably by hosting a SwiftUI badged titlebar button.

- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
  - Add tests for explicit tab/pane/drawer placement parts and truncation-safe priority.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
  - Add mounted clear button identifier/action coverage.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`
  - Add mounted or source-contract tests for clear button identifier and no noisy counts.

- `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`
  - Replace badge existence-only coverage with placement sanity checks.

- `Tests/AgentStudioTests/App/AppCommandTests.swift`
  - Add missing clear command `shortcut == nil` and command-bar priority assertions.

- `docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md`
  - Update checklist as tasks complete.

- `docs/wip/debugging/2026-05-11-notification-inbox-sidebar-style-smoke.md`
  - Create visual smoke evidence with RepoExplorer/Inbox/PaneInbox screenshots or record a concrete Peekaboo blocker.

---

## Task 1: Lock The Existing RepoExplorer Sidebar Contract

**Files:**
- Modify: `Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift`
- Modify: `Tests/AgentStudioTests/SharedComponents/SidebarRowShellTests.swift`
- Modify: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerWorktreeRowTests.swift` if this file exists; otherwise create it.

- [x] **Step 1: Write failing tests for shared sidebar token usage**

Add to `Tests/AgentStudioTests/SharedComponents/SidebarRowShellTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarRowShell")
struct SidebarRowShellTests {
    @Test("row shell builds with selected hover and flashing states")
    func rowShellBuildsWithAllVisualStates() {
        let normal = SidebarRowShell(isSelected: false, isFlashing: false, isHovered: false) {
            Text("Normal")
        }
        let selected = SidebarRowShell(isSelected: true, isFlashing: false, isHovered: false) {
            Text("Selected")
        }
        let flashing = SidebarRowShell(isSelected: false, isFlashing: true, isHovered: false) {
            Text("Flashing")
        }

        #expect(String(describing: type(of: normal)).contains("SidebarRowShell"))
        #expect(String(describing: type(of: selected)).contains("SidebarRowShell"))
        #expect(String(describing: type(of: flashing)).contains("SidebarRowShell"))
    }

    @Test("row shell background color follows sidebar token semantics")
    func rowShellBackgroundColorFollowsSidebarTokenSemantics() {
        #expect(
            SidebarRowShell<EmptyView>.backgroundColor(
                isSelected: false,
                isFlashing: false,
                isHovered: false
            ) == .clear
        )
        #expect(
            SidebarRowShell<EmptyView>.backgroundColor(
                isSelected: true,
                isFlashing: false,
                isHovered: false
            ) == Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowSelectedOpacity)
        )
        #expect(
            SidebarRowShell<EmptyView>.backgroundColor(
                isSelected: false,
                isFlashing: false,
                isHovered: true
            ) == Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
        )
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
mise run test -- --filter "SidebarRowShellTests"
```

Expected:

- FAIL because `AppStyles.Shell.Sidebar.rowSelectedOpacity` does not exist or `SidebarRowShell.backgroundColor` still uses a non-sidebar token.

- [x] **Step 3: Add sidebar selected token and update row shell**

In `Sources/AgentStudio/Infrastructure/AppStyles.swift`, inside `AppStyles.Shell.Sidebar`, add:

```swift
static let rowSelectedOpacity: CGFloat = AppStyles.General.Fill.selected
```

In `Sources/AgentStudio/SharedComponents/SidebarRowShell.swift`, update:

```swift
static func backgroundColor(
    isSelected: Bool,
    isFlashing: Bool,
    isHovered: Bool
) -> Color {
    if isFlashing || isSelected {
        return Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowSelectedOpacity)
    }
    if isHovered {
        return Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
    }
    return .clear
}
```

- [x] **Step 4: Run focused tests**

Run:

```bash
mise run test -- --filter "SidebarRowShellTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/AppStyles.swift \
  Sources/AgentStudio/SharedComponents/SidebarRowShell.swift \
  Tests/AgentStudioTests/SharedComponents/SidebarRowShellTests.swift
git commit -m $'test: lock shared sidebar row shell tokens\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 2: Share Badge Placement, Not Just Badge Drawing

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SidebarBadgeOverlay.swift`
- Create: `Tests/AgentStudioTests/SharedComponents/SidebarBadgeOverlayTests.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- Modify: `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- Modify: `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`

- [x] **Step 1: Write failing tests for shared badge overlay construction**

Create `Tests/AgentStudioTests/SharedComponents/SidebarBadgeOverlayTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarBadgeOverlay")
struct SidebarBadgeOverlayTests {
    @Test("badge overlay modifier builds with and without badge text")
    func badgeOverlayModifierBuildsWithOptionalBadgeText() {
        let badged = Image(systemName: "bell.fill")
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .sidebarBadgeOverlay(text: "3")
        let unbadged = Image(systemName: "bell")
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .sidebarBadgeOverlay(text: nil)

        #expect(String(describing: type(of: badged)).contains("ModifiedContent"))
        #expect(String(describing: type(of: unbadged)).contains("ModifiedContent"))
    }

    @Test("badge offset comes from sidebar badge placement token")
    func badgeOffsetComesFromSidebarToken() {
        #expect(AppStyles.Shell.Sidebar.badgeOffset > 0)
        #expect(AppStyles.Shell.Sidebar.badgeHitboxSize == AppStyles.General.Button.compact)
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
mise run test -- --filter "SidebarBadgeOverlayTests"
```

Expected:

- FAIL because `sidebarBadgeOverlay`, `badgeOffset`, and `badgeHitboxSize` do not exist.

- [x] **Step 3: Add shared badge placement tokens**

In `Sources/AgentStudio/Infrastructure/AppStyles.swift`, inside `AppStyles.Shell.Sidebar`, add:

```swift
static let badgeOffset: CGFloat = 4
static let badgeHitboxSize: CGFloat = AppStyles.General.Button.compact
```

Keep `Components.NotificationBadge` as drawing tokens if desired, but do not make placement depend on `Components.PaneInbox`.

- [x] **Step 4: Create only the shared badge placement overlay**

Create `Sources/AgentStudio/SharedComponents/SidebarBadgeOverlay.swift`:

```swift
import SwiftUI

struct SidebarBadgeOverlay: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        content
            .frame(
                width: AppStyles.Shell.Sidebar.badgeHitboxSize,
                height: AppStyles.Shell.Sidebar.badgeHitboxSize
            )
            .overlay(alignment: .topTrailing) {
                if let text {
                    UnreadCountBadge(text: text)
                        .offset(
                            x: AppStyles.Shell.Sidebar.badgeOffset,
                            y: -AppStyles.Shell.Sidebar.badgeOffset
                        )
                }
            }
    }
}

extension View {
    func sidebarBadgeOverlay(text: String?) -> some View {
        modifier(SidebarBadgeOverlay(text: text))
    }
}
```

This helper owns placement only. It must not own button action, hover state, popover state, tooltip state, foreground style, or accessibility label. Those stay with the existing host buttons.

- [x] **Step 5: Use shared placement in `DrawerIconBar` without replacing drawer button chrome**

Keep the current `trailingActionButton`/popover structure in `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`. Apply the shared overlay to the existing bell icon content or to the existing icon-sized label view, for example:

```swift
Image(systemName: trailingActions.inboxUnreadBadge == nil ? "bell" : "bell.fill")
    .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
    .sidebarBadgeOverlay(text: trailingActions.inboxUnreadBadge?.text)
```

Do not replace the existing drawer action with a new button type. Preserve:

```swift
trailingActionButton(...)
.popover(
    isPresented: trailingActions.inboxPopoverPresented,
    arrowEdge: .bottom
) {
    if let inboxPopoverContent = trailingActions.inboxPopoverContent {
        inboxPopoverContent
    }
}
```

The important contract is:

- host button chrome remains local to the host surface
- badge overlay geometry is shared
- badge text formatting remains caller-owned

- [x] **Step 6: Replace AppKit frame-anchored badge in `MainWindowController`**

Preferred implementation: keep the titlebar action owner intact, but render the bell glyph through an `NSHostingView` that applies `.sidebarBadgeOverlay(text:)` to the icon-sized content. This gives titlebar and drawer the same badge placement without forcing them to share button chrome.

If keeping `NSButton` is required, add a centered icon layout guide and constrain the badge to that guide, not the outer button. Do not leave this code:

```swift
badge.topAnchor.constraint(equalTo: button.topAnchor, constant: -AppStyles.Components.NotificationBadge.offset)
badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: AppStyles.Components.NotificationBadge.offset)
```

- [x] **Step 7: Add a placement sanity test**

In `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`, add:

```swift
@Test("inbox toolbar badge sits in the bell button top trailing corner")
func inboxToolbarBadgeSitsInBellTopTrailingCorner() async throws {
    let inboxAtom = InboxNotificationAtom()
    await withMainWindowControllerHarness(inboxAtom: inboxAtom) { harness in
        let bellButton = try #require(
            findDescendant(in: harness.window, identifier: "inboxToolbarBell")
        )
        let badge = try #require(
            findDescendant(in: harness.window, identifier: "inboxToolbarUnreadBadge")
        )

        inboxAtom.append(makeUnreadToolbarNotification())

        await eventually("badge should become visible") {
            badge.isHidden == false
        }

        let badgeFrame = badge.convert(badge.bounds, to: bellButton)
        #expect(badgeFrame.midX > bellButton.bounds.midX)
        #expect(badgeFrame.midY > bellButton.bounds.midY)
        #expect(badgeFrame.minX >= bellButton.bounds.midX - 2)
        #expect(badgeFrame.maxY <= bellButton.bounds.maxY + AppStyles.Shell.Sidebar.badgeOffset + 8)
    }
}

private func makeUnreadToolbarNotification() -> InboxNotification {
    InboxNotification(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 1),
        kind: .agentDesktopNotification,
        title: "Toolbar",
        body: nil,
        source: .global,
        isRead: false,
        isDismissedFromPaneInbox: false
    )
}
```

If the hosted SwiftUI titlebar button changes the view hierarchy, adapt the finder to the new accessibility identifier but keep the geometry assertions.

- [x] **Step 8: Run focused tests**

```bash
mise run test -- --filter "SidebarBadgeOverlayTests|MainWindowControllerInboxToolbarButtonTests"
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SidebarBadgeOverlay.swift \
  Sources/AgentStudio/Infrastructure/AppStyles.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift \
  Sources/AgentStudio/App/Windows/MainWindowController.swift \
  Tests/AgentStudioTests/SharedComponents/SidebarBadgeOverlayTests.swift \
  Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift
git commit -m $'fix: share inbox badge placement across sidebar surfaces\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 3: Make RepoExplorer Group Header The Shared Baseline

**Files:**
- Modify: `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- Modify: `Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift`

- [x] **Step 1: Write failing tests for content-builder section headers**

Update `Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarSectionHeader")
struct SidebarSectionHeaderTests {
    @Test("section header builds with text label")
    func sectionHeaderBuildsWithTextLabel() {
        let header = SidebarSectionHeader(
            label: "agent-studio",
            isCollapsed: false,
            onToggle: {}
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }

    @Test("section header builds with custom label and trailing content")
    func sectionHeaderBuildsWithCustomLabelAndTrailingContent() {
        let header = SidebarSectionHeader(
            isCollapsed: false,
            onToggle: {},
            label: {
                HStack {
                    Text("agent-studio")
                    Text("ShravanSunder")
                }
            },
            trailingContent: {
                Text("7")
            }
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
mise run test -- --filter "SidebarSectionHeaderTests"
```

Expected:

- FAIL because `SidebarSectionHeader` does not support a custom label builder.

- [x] **Step 3: Add content-builder overload**

Replace `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift` with:

```swift
import SwiftUI

struct SidebarSectionHeader<LabelContent: View, TrailingContent: View>: View {
    let isCollapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder let label: () -> LabelContent
    @ViewBuilder let trailingContent: () -> TrailingContent

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyles.General.Typography.textBase, alignment: .center)

                label()

                Spacer(minLength: AppStyles.General.Spacing.standard)

                trailingContent()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SidebarSectionHeader where LabelContent == Text, TrailingContent == EmptyView {
    init(
        label: String,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.label = {
            Text(label)
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        self.trailingContent = { EmptyView() }
    }
}

extension SidebarSectionHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.label = label
        self.trailingContent = { EmptyView() }
    }
}
```

- [x] **Step 4: Use it in RepoExplorer without visual change**

In `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`, replace `RepoExplorerResolvedGroupHeaderRow.body` with:

```swift
var body: some View {
    SidebarSectionHeader(
        isCollapsed: !isExpanded,
        onToggle: {},
        label: {
            SidebarGroupRow(
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
    )
    .allowsHitTesting(false)
}
```

Keep the outer `Button` in `RepoExplorerView` as the action owner. If `.allowsHitTesting(false)` interferes with the outer button, instead add a `showsButtonChrome: Bool` parameter to `SidebarSectionHeader` and keep this row non-button. Do not create two action owners.

- [x] **Step 5: Use it in inbox group header**

In `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`, use:

```swift
SidebarSectionHeader(
    isCollapsed: isCollapsed,
    onToggle: onToggle,
    label: {
        Text(label)
            .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    },
    trailingContent: {
        if unreadCount > 0, showsUnreadCount {
            UnreadCountBadge(text: "\(unreadCount)")
        }
    }
)
```

Add `showsUnreadCount: Bool = true` to `InboxNotificationGroupHeader`. PaneInbox callers must pass `false`.

- [x] **Step 6: Run focused tests**

```bash
mise run test -- --filter "SidebarSectionHeaderTests|InboxNotificationSidebarViewTests|PaneInboxNotificationPopoverTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift \
  Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift \
  Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift \
  Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift
git commit -m $'refactor: share sidebar section header chrome\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 4: Rebuild Inbox Rows On Sidebar Row Grammar

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SidebarMetadataLine.swift`
- Create: `Tests/AgentStudioTests/SharedComponents/SidebarMetadataLineTests.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

- [x] **Step 1: Write failing tests for placement parts**

Add to `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`:

```swift
@Test("source display exposes tab pane drawer and runtime placement parts")
func sourceDisplayExposesPlacementParts() {
    let parentPaneId = UUID()
    let drawerPaneId = UUID()
    let notification = makeNotification(
        title: "Claude Code",
        body: "Waiting for input",
        tabDisplayLabel: "Tab 2",
        paneDisplayLabel: "Gemini",
        paneRole: .drawerChild,
        parentPaneId: parentPaneId,
        parentPaneDisplayLabel: "Main",
        drawerOrdinal: 1,
        runtimeDisplayLabel: "Terminal",
        paneId: drawerPaneId
    )

    let display = InboxNotificationSourceDisplay(notification: notification)

    #expect(display.sourceLine == "agent-studio · notification-system")
    #expect(display.placementParts == ["Tab 2", "Parent Main · Drawer 1", "Terminal"])
    #expect(display.placementLine == "Tab 2 · Parent Main · Drawer 1 · Terminal")
}

@Test("source display includes pane number fallback when pane label is blank")
func sourceDisplayIncludesPaneNumberFallback() {
    let notification = makeNotification(
        tabDisplayLabel: "Tab 2",
        paneDisplayLabel: nil,
        paneOrdinal: 3,
        paneRole: .main,
        runtimeDisplayLabel: "Terminal"
    )

    let display = InboxNotificationSourceDisplay(notification: notification)

    #expect(display.placementParts == ["Tab 2", "Main pane 3", "Terminal"])
}
```

If `InboxNotification.PaneSource` does not yet have `paneOrdinal`, add the field in this task with decode default `nil`.

- [x] **Step 2: Run the tests to verify they fail**

```bash
mise run test -- --filter "InboxNotificationListModelTests/sourceDisplay"
```

Expected:

- FAIL because `placementParts` and possibly `paneOrdinal` do not exist.

- [x] **Step 3: Add placement parts to display model**

In `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`, add:

```swift
let placementParts: [String]
```

Update initializer:

```swift
let placementParts = Self.placementParts(for: notification, rowContext: rowContext)
let placementLine = placementParts.isEmpty ? nil : placementParts.joined(separator: " · ")

self.placementParts = placementParts
self.placementLine = placementLine
```

Add:

```swift
private static func placementParts(
    for notification: InboxNotification,
    rowContext: RowContext
) -> [String] {
    guard let paneContext = notification.paneContext else {
        return orderedUnique([notification.runtimeDisplayLabel].compactMap { normalizedOptionalString($0) })
    }

    var parts: [String] = []
    if let tabDisplayLabel = normalizedOptionalString(paneContext.tabDisplayLabel) {
        parts.append(tabDisplayLabel)
    }

    switch paneContext.paneRole {
    case .main:
        if rowContext != .paneInbox(parentPaneId: paneContext.paneId) {
            parts.append(mainPaneLabel(for: paneContext))
        }
    case .drawerChild:
        parts.append(drawerPlacementLabel(for: paneContext))
    }

    if let runtimeDisplayLabel = normalizedOptionalString(paneContext.runtimeDisplayLabel) {
        parts.append(runtimeDisplayLabel)
    }

    return orderedUnique(parts)
}

private static func mainPaneLabel(for paneContext: InboxNotification.PaneSource) -> String {
    if let paneDisplayLabel = normalizedOptionalString(paneContext.paneDisplayLabel) {
        return "Main pane \(paneDisplayLabel)"
    }
    if let paneOrdinal = paneContext.paneOrdinal {
        return "Main pane \(paneOrdinal)"
    }
    return "Main pane"
}

private static func drawerPlacementLabel(for paneContext: InboxNotification.PaneSource) -> String {
    let drawerLabel: String
    if let drawerOrdinal = paneContext.drawerOrdinal {
        drawerLabel = "Drawer \(drawerOrdinal)"
    } else if let paneDisplayLabel = normalizedOptionalString(paneContext.paneDisplayLabel) {
        drawerLabel = "Drawer \(paneDisplayLabel)"
    } else {
        drawerLabel = "Drawer"
    }

    if let parentPaneDisplayLabel = normalizedOptionalString(paneContext.parentPaneDisplayLabel) {
        return "Parent \(parentPaneDisplayLabel) · \(drawerLabel)"
    }

    return drawerLabel
}
```

Acceptance tests must distinguish:

- main-pane rows: placement includes `Main pane ...`
- drawer-child rows: placement includes `Parent ... · Drawer ...` when parent context is known
- PaneInbox parent rows: redundant parent self-placement is suppressed only for the active parent pane, not for drawer children

- [x] **Step 4: Create metadata line primitive**

Create `Sources/AgentStudio/SharedComponents/SidebarMetadataLine.swift`:

```swift
import SwiftUI

struct SidebarMetadataLine: View {
    let iconSystemName: String?
    let text: String
    let prominence: SidebarMetadataProminence

    init(
        iconSystemName: String? = nil,
        text: String,
        prominence: SidebarMetadataProminence = .secondary
    ) {
        self.iconSystemName = iconSystemName
        self.text = text
        self.prominence = prominence
    }

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: AppStyles.Shell.Sidebar.branchIconSize, weight: .medium))
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)
            } else {
                Color.clear
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth)
            }

            Text(text)
                .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(prominence.foregroundStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SidebarMetadataProminence {
    case primary
    case secondary
    case tertiary

    var foregroundStyle: Color {
        switch self {
        case .primary:
            Color.primary
        case .secondary:
            Color.secondary
        case .tertiary:
            Color.secondary.opacity(AppStyles.General.Fill.muted)
        }
    }
}
```

Create `Tests/AgentStudioTests/SharedComponents/SidebarMetadataLineTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarMetadataLine")
struct SidebarMetadataLineTests {
    @Test("metadata line builds with and without icon")
    func metadataLineBuildsWithAndWithoutIcon() {
        let withIcon = SidebarMetadataLine(iconSystemName: "terminal", text: "Tab 2 · Pane 1")
        let withoutIcon = SidebarMetadataLine(text: "agent-studio")

        #expect(String(describing: type(of: withIcon)).contains("SidebarMetadataLine"))
        #expect(String(describing: type(of: withoutIcon)).contains("SidebarMetadataLine"))
    }
}
```

- [x] **Step 5: Rebuild `InboxRow` with sidebar tokens**

In `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`, replace local font/padding choices with:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            unreadDot
                .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

            Text(display.primaryText)
                .font(.system(size: AppStyles.General.Typography.textBase, weight: notification.isRead ? .regular : .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(relativeTime)
                .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                .foregroundStyle(.secondary)
        }

        SidebarMetadataLine(
            iconSystemName: nil,
            text: display.sourceLine,
            prominence: .secondary
        )

        if let placementLine = display.placementLine {
            SidebarMetadataLine(
                iconSystemName: "terminal",
                text: placementLine,
                prominence: .secondary
            )
        }

        if let detailText = display.detailText {
            SidebarMetadataLine(
                iconSystemName: nil,
                text: detailText,
                prominence: .tertiary
            )
        }
    }
}

@ViewBuilder
private var unreadDot: some View {
    if notification.isRead {
        Color.clear.frame(width: 6, height: 6)
    } else {
        Circle()
            .fill(.red)
            .frame(width: 6, height: 6)
    }
}
```

Remove row-local `.padding(.horizontal, 8)` and `.padding(.vertical, 4)`. Row padding belongs to `SidebarRowShell`.

- [x] **Step 6: Run focused tests**

```bash
mise run test -- --filter "SidebarMetadataLineTests|InboxNotificationListModelTests|PaneInboxNotificationPopoverTests|InboxNotificationSidebarViewTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SidebarMetadataLine.swift \
  Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift \
  Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift \
  Tests/AgentStudioTests/SharedComponents/SidebarMetadataLineTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift
git commit -m $'refactor: render inbox rows with shared sidebar grammar\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 5: Fix Inbox Surface Background, Indentation, And Control Icons

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [x] **Step 1: Write source-level contract tests for shared background and identifiers**

Add to `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`:

```swift
@Test("inbox sidebar uses repo explorer background and clear button identifier")
func inboxSidebarUsesRepoExplorerBackgroundAndClearButtonIdentifier() throws {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let source = try String(
        contentsOf: projectRoot.appending(
            path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains(".background(Color(nsColor: .windowBackgroundColor))"))
    #expect(source.contains(".accessibilityIdentifier(\"inboxSidebarClearButton\")"))
    #expect(source.contains("AppCommand.clearInboxNotifications.definition"))
}
```

Add to `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`:

```swift
@Test("pane inbox clear button has stable accessibility identifier")
func paneInboxClearButtonHasStableIdentifier() throws {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let source = try String(
        contentsOf: projectRoot.appending(
            path: "Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains(".accessibilityIdentifier(\"paneInboxClearButton\")"))
    #expect(source.contains("AppCommand.clearPaneInboxNotifications.definition"))
}
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests/inboxSidebarUsesRepoExplorerBackground|PaneInboxNotificationPopoverTests/paneInboxClearButton"
```

Expected:

- FAIL because identifiers are missing.

- [x] **Step 3: Add clear button identifiers**

In `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`, after the clear button help:

```swift
.accessibilityIdentifier("inboxSidebarClearButton")
```

In `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`, after the clear button help:

```swift
.accessibilityIdentifier("paneInboxClearButton")
```

- [x] **Step 4: Replace ambiguous sort/group/filter icons as one control set**

In `InboxSidebarComponents.swift`, use this final header-control symbol set unless the running app proves one still visually collides with existing sidebar/arrangement controls:

```swift
let sortIconName = "arrow.up.arrow.down.circle"
let groupIconName = "square.stack.3d.up"
let filterIconName = "line.3.horizontal.decrease.circle"
let clearIconName = AppCommand.clearInboxNotifications.definition.icon
```

Use distinct help text for each control:

```swift
.help("Sort notifications")
.help("Group notifications")
.help("Filter notifications")
.help(AppCommand.clearInboxNotifications.definition.controlToolTip)
```

Do not keep either of these ambiguous forms:

```swift
Image(systemName: sort == .newestFirst ? "arrow.down" : "arrow.up")
Image(systemName: "rectangle.3.group")
```

Add a source-contract test that fails if the inbox header uses the bare arrow symbols for sort or `rectangle.3.group` for grouping/filtering. The visual smoke must capture all four controls in the same sidebar header.

- [x] **Step 5: Ensure grouped rows are nested under headers**

In `InboxSidebarComponents.swift`, ensure row rendering under a group applies a leading inset:

```swift
.padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)
```

If `groupChildRowLeadingInset` does not exist, add it to `AppStyles.Shell.Sidebar` by reusing the exact inset path RepoExplorer child rows use, including the list-row leading inset. Do not recompute the hierarchy with a near-match formula.

Do not apply this inset when grouping is `.none`.

- [x] **Step 6: Run focused tests**

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests|PaneInboxNotificationPopoverTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift
git commit -m $'fix: align inbox sidebar controls and hierarchy\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 6: Fill Command And Production Wiring Test Gaps

**Files:**
- Modify: `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- Modify: `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerTestSupport.swift`
- Modify: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Create: `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerPaneInboxClearTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [x] **Step 1: Add missing command spec assertions**

In `Tests/AgentStudioTests/App/AppCommandTests.swift`, extend the clear command expectations:

```swift
let showInbox = AppCommand.showInboxNotifications.definition
let showPaneInbox = AppCommand.showPaneInboxNotifications.definition

#expect(clearInbox.shortcut == nil)
#expect(clearInbox.commandBarGroupName == showInbox.commandBarGroupName)
#expect(clearInbox.commandBarGroupPriority == showInbox.commandBarGroupPriority)
#expect(clearPaneInbox.shortcut == nil)
#expect(clearPaneInbox.commandBarGroupName == showPaneInbox.commandBarGroupName)
#expect(clearPaneInbox.commandBarGroupPriority == showPaneInbox.commandBarGroupPriority)
```

Do not reference `CommandBarGroupPriority` by name in tests if it is private to the catalog file. Compare against sibling command definitions instead.

- [x] **Step 2: Expose production pane inbox presentation to tests without adding a DEBUG hook**

In `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`, change:

```swift
private func makePaneInboxPresentation() -> PaneInboxPresentation
```

to internal default access:

```swift
func makePaneInboxPresentation() -> PaneInboxPresentation
```

This is not a behavior change and not a `#if DEBUG` test hook; it lets `@testable import AgentStudio` verify the exact production closure returned by the composition root.

In `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerTestSupport.swift`, add an optional `inboxAtom` parameter to `makeMainSplitViewControllerHarness` and `withMainSplitViewControllerHarness`, defaulting to `InboxNotificationAtom()`, and pass that exact atom into `MainSplitViewController`.

- [x] **Step 3: Add production MainSplit clear wiring test**

Create `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerPaneInboxClearTests.swift`:

```swift
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct MainSplitViewControllerPaneInboxClearTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("production pane inbox clear wiring marks parent and drawer rows read")
    func productionPaneInboxClearWiringMarksScopedRowsRead() async throws {
        let inboxAtom = InboxNotificationAtom()
        try await withMainSplitViewControllerHarness(withRepos: true, inboxAtom: inboxAtom) { harness in
            let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
            let parentTab = Tab(paneId: parentPane.id)
            harness.store.appendTab(parentTab)
            harness.store.setActiveTab(parentTab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
            let unrelatedPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Other"))

            inboxAtom.append(makePaneInboxNotification(paneId: parentPane.id))
            inboxAtom.append(makePaneInboxNotification(paneId: drawerPane.id))
            inboxAtom.append(makePaneInboxNotification(paneId: unrelatedPane.id))

            let presentation = harness.controller.makePaneInboxPresentation()
            presentation.clearNotifications(parentPane.id, [parentPane.id, drawerPane.id])

            #expect(inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [parentPane.id, drawerPane.id]) == 0)
            #expect(inboxAtom.unreadCount(forPaneId: unrelatedPane.id) == 1)
            #expect(inboxAtom.globalUnreadCount == 1)
        }
    }

    private func makePaneInboxNotification(paneId: UUID) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .agentDesktopNotification,
            title: "Pane inbox",
            body: nil,
            source: .pane(.init(paneId: paneId, runtimeDisplayLabel: "Terminal")),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
```

Do not use a recorder closure for this test. This test exists specifically to verify the production `MainSplitViewController` composition closure mutates the real `InboxNotificationAtom`.

- [x] **Step 4: Add mounted button tests**

In `InboxNotificationSidebarViewTests`, add a mounted button test using `inboxSidebarClearButton`. In `PaneInboxNotificationPopoverTests`, add a mounted/source-contract test using `paneInboxClearButton`.

Test names:

```swift
@Test("mounted inbox sidebar clear button dispatches clear command")
func mountedInboxSidebarClearButtonDispatchesClearCommand() async throws

@Test("mounted pane inbox clear button dispatches targeted clear command")
func mountedPaneInboxClearButtonDispatchesTargetedClearCommand() async throws
```

Use the existing `MockAppCommandRouter`, `MockCommandHandler`, and `findDescendant` helpers where available.

- [x] **Step 5: Run focused tests**

```bash
mise run test -- --filter "AppCommandTests|MainSplitViewControllerPaneInboxClearTests|InboxNotificationSidebarViewTests|PaneInboxNotificationPopoverTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Tests/AgentStudioTests/App/AppCommandTests.swift \
  Sources/AgentStudio/App/Windows/MainSplitViewController.swift \
  Tests/AgentStudioTests/App/Windows/MainSplitViewControllerTestSupport.swift \
  Tests/AgentStudioTests/App/Windows/MainSplitViewControllerPaneInboxClearTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift
git commit -m $'test: cover inbox clear controls through mounted surfaces\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 7: Update The Feedback Ledger And Visual Smoke Runbook

**Files:**
- Modify: `docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md`
- Create: `docs/wip/debugging/2026-05-11-notification-inbox-sidebar-style-smoke.md`
- Modify: `docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md`

- [x] **Step 1: Update checklist state**

In `docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md`, only mark an item `[x]` when source/tests or screenshot evidence exists. Leave visual items unchecked until screenshot review passes.

- [x] **Step 2: Create visual smoke runbook**

Create `docs/wip/debugging/2026-05-11-notification-inbox-sidebar-style-smoke.md`:

```markdown
# Notification Inbox Sidebar Style Smoke

Date: 2026-05-11
Branch: notification-inbox-redesign

## Commands

Run from the worktree root:

    source scripts/swift-build-slot.sh debug
    mise run build
    APP_BINARY="$(pwd)/$SWIFT_BUILD_DIR/debug/AgentStudio"
    "$APP_BINARY" &
    APP_PID=$!
    peekaboo see --app "PID:$APP_PID" --json > /tmp/agentstudio-style-see.json

## Required Captures

Capture each state separately. Do not satisfy this gate with one ambiguous screenshot.

1. RepoExplorer baseline:
   - State: repo sidebar open, at least one expanded repo, multiple worktree rows visible.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-01-repoexplorer.png`

2. Global inbox grouped:
   - State: global inbox sidebar open, grouped by repo or pane, unread rows visible.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-02-global-inbox-grouped.png`

3. Global sidebar badge:
   - State: sidebar/titlebar bell visible with unread count.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-03-global-badge.png`

4. PaneInbox drawer badge:
   - State: drawer icon bar visible with pane inbox unread badge.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-04-pane-badge.png`

5. PaneInbox popover:
   - State: PaneInbox popover open with at least one parent-row notification and one drawer-child notification.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-05-pane-popover.png`

Use PID targeting for every capture:

    peekaboo image --app "PID:$APP_PID" --path <output-path>

## Acceptance

- RepoExplorer and inbox backgrounds match.
- Group indentation and row rhythm match.
- Sidebar bell badge placement matches PaneInbox badge placement.
- Sort, group, filter, and clear icons are all distinct and legible.
- Rows show repo/worktree, tab, pane/drawer, runtime, and message.
- No row shows `unknown source`, UUID prefixes, or raw ids.
```

- [x] **Step 3: Update original plan status**

In `docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md`, change the current completion status so it does not claim product completion while visual acceptance is failing:

```markdown
- Code implementation and automated verification were previously green.
- Product visual acceptance is not complete. See `docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md`.
- The follow-up plan `docs/superpowers/plans/2026-05-11-notification-inbox-sidebar-style-convergence.md` owns the missing visual/style/test pieces.
```

- [ ] **Step 4: Commit**

```bash
git add docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md \
  docs/wip/debugging/2026-05-11-notification-inbox-sidebar-style-smoke.md \
  docs/superpowers/plans/2026-05-07-notification-inbox-sidebar-redesign.md
git commit -m $'docs: track inbox sidebar visual acceptance blockers\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 8: Full Verification

**Files:**
- No source changes unless verification fails.

- [x] **Step 1: Format**

Run:

```bash
mise run format
```

Expected: exits 0.

- [x] **Step 2: Lint**

Run:

```bash
mise run lint
```

Expected:

- swift-format OK
- swiftlint 0 violations
- Core boundary import check passed

- [x] **Step 3: Full tests**

Run:

```bash
mise run test
```

Expected: exits 0.

- [x] **Step 4: E2E tests**

Run:

```bash
mise run test-e2e
```

Expected: exits 0.

- [x] **Step 5: Zmx E2E tests**

Run:

```bash
mise run test-zmx-e2e
```

Expected: exits 0.

- [x] **Step 6: Build**

Run:

```bash
mise run build
```

Expected: exits 0.

- [x] **Step 7: Visual smoke**

Run the commands in `docs/wip/debugging/2026-05-11-notification-inbox-sidebar-style-smoke.md`.

Expected:

- Captures exist, or the runbook records the exact Peekaboo/tool blocker.
- If screenshots exist and still fail the visual checklist, do not mark this plan complete.

Actual result on 2026-05-12:

- `mise run build` passed.
- PID-based launch with isolated `AGENTSTUDIO_DATA_DIR` started PID `21377`.
- `peekaboo see --pid 21377 --path docs/wip/visual/2026-05-12-notification-inbox-redesign-current-smoke.png --json` failed with `WINDOW_NOT_FOUND`.
- Product visual acceptance remains unpassed; the runbook records the blocker.

- [ ] **Step 8: Final status**

Run:

```bash
git status --short --branch
```

Expected:

- Only intentional committed changes remain.
- No accidental changes in sibling worktrees.

---

## Self-Review

### Spec Coverage

- RepoExplorer visual parity: Tasks 1, 3, 4, 5, 7.
- Shared styles/components: Tasks 1, 2, 3, 4.
- Badge placement: Task 2.
- Source tab/pane/drawer numbers: Task 4.
- PaneInbox no noisy counts: Task 3 and Task 5.
- Controls/icons/testability: Task 5 and Task 6.
- Production wiring tests: Task 6.
- Visual evidence: Task 7 and Task 8.
- Atom boundary discipline: covered by file structure and non-goals; no new Core inbox atom/properties are introduced.

### Placeholder Scan

This plan intentionally leaves four product decisions as explicit decision points:

- Whether grouping/sorting remain final product controls or temporary discovery/debug affordances.
- Whether existing Core inbox state smells are in scope for this PR.
- Final row hierarchy after implementation screenshots: whether notification rows settle on two lines or three lines for source, placement, and body.
- Branch placement after visual review: primary source line, placement line, or shown only when it disambiguates the worktree.

Those are not implementation placeholders; they require user/product approval before broadening scope.

### Type Consistency

- `SidebarBadgeOverlay` is introduced in Task 2 and reused without replacing host button chrome.
- `SidebarMetadataLine` is introduced in Task 4 and reused in the same task.
- `placementParts` is introduced in Task 4 before tests depend on it.
- Existing commands remain `clearInboxNotifications` and `clearPaneInboxNotifications`.
