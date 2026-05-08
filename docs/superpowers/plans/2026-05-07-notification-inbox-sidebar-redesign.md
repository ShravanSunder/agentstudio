# Notification Inbox Sidebar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the notification inbox read like an Agent Studio sidebar surface: useful source context on every row, correct command durations, repo/sidebar-matching chrome, honest grouping labels, and no implementation IDs leaking into UI.

**Architecture:** Keep notification domain state in `Features/InboxNotification/`, but promote reusable sidebar row/header chrome into `SharedComponents/`. Extend the denormalized notification source context at emit time with tab, pane, drawer, and runtime labels so old notifications remain readable after the source moves or closes. Grouping stays feature-owned, while visual shell, search, row hover, and section-header treatment follow the repo sidebar design system.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit-hosted sidebar, Swift Testing, `mise run build`, `mise run test`, `mise run lint`, Peekaboo visual smoke for native verification.

---

## Scope

This plan covers the global sidebar inbox and the shared row primitives needed by the pane inbox. It does not change the LUNA-361 notification policy, raw terminal-output capture, or unseen-activity promotion rules.

## Requirements

- Source context must always show something useful: repo/worktree/branch when available, plus tab/pane/drawer placement when available, with quiet workspace/app fallback when not.
- Repo and worktree display should match RepoExplorer semantics and visual rhythm.
- Command-finished duration must be correct; Ghostty emits nanoseconds, not seconds.
- `By tab` must not show UUID prefixes. If a tab has no useful name, use a stable human fallback such as `Tab 1`.
- `By pane` must distinguish parent panes from drawer child panes.
- Inbox sidebar background/chrome must match RepoExplorer.
- Sort/grouping buttons must have clear icon semantics and help labels.
- Global inbox and PaneInbox should share row rendering where their behavior contracts match.
- Red unread dot/count affordances must remain visible when the sidebar is collapsed or expanded.

## File Structure

### New Files

- `Sources/AgentStudio/SharedComponents/SidebarRowShell.swift`
  - Stateless shared row shell: compact sidebar padding, hover/focus/flash background, leading icon column, rounded row shape.
  - Imports only SwiftUI and Infrastructure.

- `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift`
  - Stateless shared collapsible section header: chevron, title, optional subtitle, trailing accessory/count.
  - Used by RepoExplorer and Inbox where interaction semantics match.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
  - Feature-owned presentation model derived from `InboxNotification.Source`.
  - Produces row source line, placement line, group labels, runtime fallback labels, and search text.

- `Tests/AgentStudioTests/SharedComponents/SidebarRowShellTests.swift`
  - Lightweight model/style tests for the shared row shell helpers.

- `Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift`
  - Tests for header title/accessory behavior where pure logic exists.

- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift`
  - Source line, placement line, fallbacks, and grouping labels.

### Modified Files

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
  - Extend `InboxNotification.Source.PaneSource` with denormalized tab/pane/drawer/runtime display fields.

- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
  - Populate source display fields from `WorkspacePaneAtom` and `WorkspaceTabLayoutAtom`.
  - Convert Ghostty command duration nanoseconds into display seconds.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
  - Use `InboxNotificationSourceDisplay` for filtering and group labels.
  - Stop exposing UUID prefixes as user-facing labels.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
  - Rebuild as compact sidebar-native row content using source display model.

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
  - Use shared section header and row shell.
  - Match RepoExplorer background/list chrome.
  - Replace ambiguous sort/grouping controls.

- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
  - Reuse the same `InboxRow` content and shared row shell where appropriate.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`
  - Adopt `SidebarSectionHeader` if the fit is direct; keep feature-specific wrapper for repo labels.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
  - Optionally wrap existing content in `SidebarRowShell` if no visual regression.

- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  - Add named sidebar row/source/timestamp tokens if existing tokens are insufficient.

- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
  - Add command duration display policy only if needed for maximum display cap. Do not put visual constants here.

- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
  - Pin grouping labels and filtering against source display strings.

- `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`
  - Pin source context emission and duration conversion.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
  - Pin header controls and activation behavior at model boundary.

- `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`
  - Pin shared row source display for pane-scoped rows.

---

## Task 1: Pin Source Context And Duration Bugs With Tests

**Files:**
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

- [ ] **Step 1: Add a failing routing test for command duration nanoseconds**

Add this test to `InboxNotificationRouterTests` near `commandFinishedGating`:

```swift
@Test("commandFinished duration from Ghostty nanoseconds renders as seconds")
func commandFinishedDurationUsesGhosttyNanoseconds() async {
    let fixture = await makeFixture()
    makeWindowKey(fixture.windowLifecycle)

    let paneId = PaneId()
    _ = addTerminalPane(paneId, to: fixture)
    fixture.attendedPane.setAttendedPaneId(nil)
    await Task.yield()

    _ = await fixture.bus.post(
        makePaneEnvelope(
            paneId: paneId,
            event: .terminal(.commandFinished(exitCode: 0, duration: 18_000_000_000))
        )
    )

    await waitForNotificationCount(
        1,
        in: fixture,
        description: "nanosecond command duration should meet threshold and notify"
    )

    #expect(fixture.inboxAtom.notifications[0].body == "exit 0 · 18s")
    await fixture.router.stop()
    fixture.tracker.stop()
    fixture.attendedPane.stop()
}
```

- [ ] **Step 2: Add a failing routing test for tab/pane/drawer source fields**

Add this test to `InboxNotificationRouterDrawerChildTests.swift`:

```swift
@Test("drawer child notification stores parent and drawer source display context")
func drawerChildNotificationStoresSourceDisplayContext() async throws {
    let fixture = await makeFixture()
    makeWindowKey(fixture.windowLifecycle)

    let parentPaneId = PaneId()
    let parentPane = addTerminalPane(parentPaneId, to: fixture, title: "Claude")
    fixture.tabLayout.renameTab(try #require(fixture.tabLayout.tabs.first?.id), name: "Work")
    let drawerPane = try #require(
        fixture.paneAtom.addDrawerPane(
            to: parentPane.id,
            parentFallbackCWD: nil
        )
    )
    fixture.paneAtom.renamePane(drawerPane.id, title: "Gemini")
    fixture.attendedPane.setAttendedPaneId(parentPane.id)
    await Task.yield()

    _ = await fixture.bus.post(
        makePaneEnvelope(
            paneId: PaneId(drawerPane.id),
            event: .terminal(.commandFinished(exitCode: 0, duration: 20_000_000_000))
        )
    )

    await waitForNotificationCount(
        1,
        in: fixture,
        description: "drawer child command should notify while parent is attended"
    )

    let notification = fixture.inboxAtom.notifications[0]
    guard case .pane(let source) = notification.source else {
        Issue.record("Expected pane notification source")
        return
    }
    #expect(source.tabName == "Work")
    #expect(source.paneTitle == "Gemini")
    #expect(source.parentPaneId == parentPane.id)
    #expect(source.parentPaneTitle == "Claude")
    #expect(source.paneRole == .drawerChild)
    await fixture.router.stop()
    fixture.tracker.stop()
    fixture.attendedPane.stop()
}
```

If helper signatures differ, keep the assertions and adapt only the fixture construction.

- [ ] **Step 3: Add failing model tests for user-facing grouping labels**

Add these tests to `InboxNotificationListModelTests`:

```swift
@Test("byTab grouping uses tab names instead of UUID prefixes")
func byTabGroupingUsesTabNames() {
    let tabId = UUID()
    let notification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Claude Code",
        paneId: UUID(),
        tabId: tabId,
        tabName: "Work",
        paneTitle: "Claude"
    )

    let model = InboxNotificationListModel(
        notifications: [notification],
        grouping: .byTab,
        sort: .newestFirst,
        searchText: ""
    )

    #expect(model.sections.map(\.label) == ["Work"])
}

@Test("byPane grouping distinguishes drawer child panes")
func byPaneGroupingDistinguishesDrawerChildPanes() {
    let parentPaneId = UUID()
    let drawerPaneId = UUID()
    let notification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Gemini",
        paneId: drawerPaneId,
        repoName: "askluna",
        worktreeName: "askluna",
        branchName: "main",
        paneTitle: "Gemini",
        paneRole: .drawerChild,
        parentPaneId: parentPaneId,
        parentPaneTitle: "Claude"
    )

    let model = InboxNotificationListModel(
        notifications: [notification],
        grouping: .byPane,
        sort: .newestFirst,
        searchText: ""
    )

    #expect(model.sections.map(\.label) == ["Claude / Drawer: Gemini"])
}
```

Extend the local test helper in this file to accept:

```swift
tabName: String? = nil,
paneTitle: String? = nil,
paneRole: InboxNotification.Source.PaneRole = .main,
parentPaneId: UUID? = nil,
parentPaneTitle: String? = nil
```

- [ ] **Step 4: Run focused tests and verify failure**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationRouterTests|InboxNotificationRouterDrawerChildTests|InboxNotificationListModelTests"
```

Expected: FAIL because `PaneSource` lacks the new fields, command duration is treated as seconds, and group labels still use UUID prefixes / weak pane labels.

- [ ] **Step 5: Commit failing tests**

```bash
git add Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift
git commit -m $'test: pin notification inbox source display gaps\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 2: Extend Denormalized Notification Source Context

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

- [ ] **Step 1: Add source role and display fields**

In `InboxNotification.Source.PaneSource`, add:

```swift
enum PaneRole: String, Sendable, Codable, Equatable {
    case main
    case drawerChild
}

let tabName: String?
let paneTitle: String?
let paneRole: PaneRole
let parentPaneId: UUID?
let parentPaneTitle: String?
let drawerOrdinal: Int?
let runtimeLabel: String?
```

Update its initializer to:

```swift
init(
    paneId: UUID,
    tabId: UUID? = nil,
    tabName: String? = nil,
    repoId: UUID? = nil,
    repoName: String? = nil,
    worktreeId: UUID? = nil,
    worktreeName: String? = nil,
    branchName: String? = nil,
    paneTitle: String? = nil,
    paneRole: PaneRole = .main,
    parentPaneId: UUID? = nil,
    parentPaneTitle: String? = nil,
    drawerOrdinal: Int? = nil,
    runtimeLabel: String? = nil
) {
    self.paneId = paneId
    self.tabId = tabId
    self.tabName = tabName?.nilIfBlank
    self.repo = NamedSource(id: repoId, name: repoName)
    self.worktree = NamedSource(id: worktreeId, name: worktreeName)
    self.branchName = branchName?.nilIfBlank
    self.paneTitle = paneTitle?.nilIfBlank
    self.paneRole = paneRole
    self.parentPaneId = parentPaneId
    self.parentPaneTitle = parentPaneTitle?.nilIfBlank
    self.drawerOrdinal = drawerOrdinal
    self.runtimeLabel = runtimeLabel?.nilIfBlank
}
```

If `nilIfBlank` does not already exist, add this private extension at the bottom of the file:

```swift
private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

- [ ] **Step 2: Add computed accessors for display fields**

Add these computed properties to `InboxNotification`:

```swift
var tabName: String? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.tabName
}

var paneTitle: String? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.paneTitle
}

var paneRole: Source.PaneSource.PaneRole? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.paneRole
}

var parentPaneId: UUID? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.parentPaneId
}

var parentPaneTitle: String? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.parentPaneTitle
}

var drawerOrdinal: Int? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.drawerOrdinal
}

var runtimeLabel: String? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource.runtimeLabel
}
```

- [ ] **Step 3: Populate source context in the router**

Replace `ResolvedPaneContext` with:

```swift
private struct ResolvedPaneContext {
    let tabId: UUID?
    let tabName: String?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
    let paneTitle: String?
    let paneRole: InboxNotification.Source.PaneSource.PaneRole
    let parentPaneId: UUID?
    let parentPaneTitle: String?
    let drawerOrdinal: Int?
    let runtimeLabel: String?
}
```

Update `resolveContext(for:)` in `InboxNotificationRouter` to:

```swift
private func resolveContext(for paneId: UUID) -> ResolvedPaneContext? {
    guard let pane = paneAtom.pane(paneId) else { return nil }
    let tab = tabLayout.tabContaining(paneId: paneId)
    let parentPaneId = pane.parentPaneId
    let parentPane = parentPaneId.flatMap { paneAtom.pane($0) }
    let drawerOrdinal = parentPane?.drawer?.paneIds.firstIndex(of: paneId).map { $0 + 1 }
    let paneRole: InboxNotification.Source.PaneSource.PaneRole =
        parentPaneId == nil ? .main : .drawerChild

    return ResolvedPaneContext(
        tabId: tab?.id,
        tabName: tab?.name,
        repoId: pane.repoId,
        repoName: pane.metadata.repoName,
        worktreeId: pane.worktreeId,
        worktreeName: pane.metadata.worktreeName,
        branchName: pane.metadata.checkoutRef,
        paneTitle: pane.title,
        paneRole: paneRole,
        parentPaneId: parentPaneId,
        parentPaneTitle: parentPane?.title,
        drawerOrdinal: drawerOrdinal,
        runtimeLabel: runtimeLabel(for: pane)
    )
}

private func runtimeLabel(for pane: Pane) -> String? {
    switch pane.content {
    case .terminal:
        return "Terminal"
    case .webview:
        return "Web"
    case .bridge(let state):
        return state.panelKind.displayTitle
    }
}
```

If `BridgePaneState.PanelKind.displayTitle` does not exist, add a private switch inside `runtimeLabel(for:)` using the existing cases.

- [ ] **Step 4: Pass source fields into notification construction**

Update the `.init(...)` call for `InboxNotification.Source.PaneSource`:

```swift
source: .pane(
    .init(
        paneId: paneId,
        tabId: resolvedContext?.tabId,
        tabName: resolvedContext?.tabName,
        repoId: resolvedContext?.repoId,
        repoName: resolvedContext?.repoName,
        worktreeId: resolvedContext?.worktreeId,
        worktreeName: resolvedContext?.worktreeName,
        branchName: resolvedContext?.branchName,
        paneTitle: resolvedContext?.paneTitle,
        paneRole: resolvedContext?.paneRole ?? .main,
        parentPaneId: resolvedContext?.parentPaneId,
        parentPaneTitle: resolvedContext?.parentPaneTitle,
        drawerOrdinal: resolvedContext?.drawerOrdinal,
        runtimeLabel: resolvedContext?.runtimeLabel
    )
)
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationRouterDrawerChildTests|InboxNotificationListModelTests"
```

Expected: source-field tests now compile and pass, but duration test may still fail until Task 3.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift \
  Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift
git commit -m $'feat: denormalize inbox source display context\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 3: Fix Command Duration Units And Formatting

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`

- [ ] **Step 1: Replace seconds formatter with nanoseconds formatter**

In `InboxNotificationRouter`, replace:

```swift
private func formattedDuration(_ seconds: UInt64) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    if minutes > 0 {
        return "\(minutes)m \(remainingSeconds)s"
    }
    return "\(remainingSeconds)s"
}
```

with:

```swift
private func formattedDuration(_ nanoseconds: UInt64) -> String {
    let seconds = nanoseconds / 1_000_000_000
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    if minutes > 0 {
        return "\(minutes)m \(remainingSeconds)s"
    }
    return "\(remainingSeconds)s"
}
```

- [ ] **Step 2: Fix threshold comparison to use nanoseconds**

Replace:

```swift
guard duration >= AppPolicies.InboxNotification.commandFinishedMinDurationSeconds else {
    return .ignore(reason: "below_duration_threshold")
}
```

with:

```swift
guard duration >= AppPolicies.InboxNotification.commandFinishedMinDurationNanoseconds else {
    return .ignore(reason: "below_duration_threshold")
}
```

In `AppPolicies.InboxNotification`, replace:

```swift
static let commandFinishedMinDurationSeconds: UInt64 = 10
```

with:

```swift
static let commandFinishedMinDurationSeconds: UInt64 = 10
static let commandFinishedMinDurationNanoseconds: UInt64 =
    commandFinishedMinDurationSeconds * 1_000_000_000
```

- [ ] **Step 3: Update existing tests to pass nanosecond durations**

In inbox router tests only, convert command-finished test inputs:

```swift
duration: 20
duration: 15
duration: 3
```

to:

```swift
duration: 20_000_000_000
duration: 15_000_000_000
duration: 3_000_000_000
```

Do not change Ghostty adapter tests that intentionally prove raw payload forwarding.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationRouterTests|InboxNotificationRouterDrawerChildTests|GhosttyActionRouterTests|GhosttyAdapterTests"
```

Expected: PASS. The new duration test must assert `exit 0 · 18s`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/AppPolicies.swift \
  Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift
git commit -m $'fix: format inbox command durations from nanoseconds\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 4: Add Inbox Source Display Model

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
- Create: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`

- [ ] **Step 1: Write source display tests**

Create `InboxNotificationSourceDisplayTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationSourceDisplay")
struct InboxNotificationSourceDisplayTests {
    @Test("repo source line includes branch when branch differs from worktree")
    func repoSourceLineIncludesDistinctBranch() {
        let notification = makeNotification(
            repoName: "askluna",
            worktreeName: "notification-system",
            branchName: "notification-system-5",
            tabName: "Work",
            paneTitle: "Claude"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.sourceLine == "askluna · notification-system / notification-system-5")
        #expect(display.placementLine == "Tab: Work · Pane: Claude")
        #expect(display.groupLabel(for: .byRepo) == "askluna")
        #expect(display.groupLabel(for: .byTab) == "Work")
        #expect(display.groupLabel(for: .byPane) == "Claude")
    }

    @Test("drawer child placement names parent and child")
    func drawerChildPlacementNamesParentAndChild() {
        let notification = makeNotification(
            repoName: "askluna",
            worktreeName: "askluna",
            branchName: "askluna",
            tabName: "Work",
            paneTitle: "Gemini",
            paneRole: .drawerChild,
            parentPaneTitle: "Claude",
            drawerOrdinal: 2
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.sourceLine == "askluna · askluna")
        #expect(display.placementLine == "Tab: Work · Pane: Claude · Drawer: Gemini")
        #expect(display.groupLabel(for: .byPane) == "Claude / Drawer: Gemini")
    }

    @Test("global source uses quiet workspace fallback")
    func globalSourceUsesQuietFallback() {
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Notification",
            body: "Body",
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.sourceLine == "Workspace event")
        #expect(display.placementLine == nil)
        #expect(display.groupLabel(for: .byRepo) == "Workspace")
    }

    private func makeNotification(
        repoName: String? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil,
        tabName: String? = nil,
        paneTitle: String? = nil,
        paneRole: InboxNotification.Source.PaneSource.PaneRole = .main,
        parentPaneTitle: String? = nil,
        drawerOrdinal: Int? = nil
    ) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Claude Code",
            body: "Claude is waiting for your input",
            source: .pane(
                .init(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabName: tabName,
                    repoName: repoName,
                    worktreeName: worktreeName,
                    branchName: branchName,
                    paneTitle: paneTitle,
                    paneRole: paneRole,
                    parentPaneTitle: parentPaneTitle,
                    drawerOrdinal: drawerOrdinal,
                    runtimeLabel: "Terminal"
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
```

- [ ] **Step 2: Run source display tests and verify failure**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationSourceDisplayTests"
```

Expected: FAIL because `InboxNotificationSourceDisplay` does not exist.

- [ ] **Step 3: Implement `InboxNotificationSourceDisplay`**

Create `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`:

```swift
import Foundation

struct InboxNotificationSourceDisplay: Sendable, Equatable {
    let sourceLine: String
    let placementLine: String?
    let searchText: String

    private let repoGroupLabel: String
    private let paneGroupLabel: String
    private let tabGroupLabel: String

    init(notification: InboxNotification) {
        switch notification.source {
        case .global:
            self.sourceLine = "Workspace event"
            self.placementLine = nil
            self.searchText = [
                notification.title,
                notification.body,
                "Workspace event",
            ].compactMap(\.self).joined(separator: " ")
            self.repoGroupLabel = "Workspace"
            self.paneGroupLabel = "Workspace"
            self.tabGroupLabel = "Workspace"

        case .pane(let paneSource):
            let sourceLine = Self.sourceLine(for: paneSource)
            let placementLine = Self.placementLine(for: paneSource)
            self.sourceLine = sourceLine
            self.placementLine = placementLine
            self.searchText = [
                notification.title,
                notification.body,
                sourceLine,
                placementLine,
                paneSource.runtimeLabel,
            ].compactMap(\.self).joined(separator: " ")
            self.repoGroupLabel = paneSource.repo?.name ?? "Workspace"
            self.paneGroupLabel = Self.paneGroupLabel(for: paneSource)
            self.tabGroupLabel = Self.nonBlank(paneSource.tabName) ?? "Current Tab"
        }
    }

    func groupLabel(for grouping: InboxNotificationGrouping) -> String? {
        switch grouping {
        case .none:
            return nil
        case .byRepo:
            return repoGroupLabel
        case .byPane:
            return paneGroupLabel
        case .byTab:
            return tabGroupLabel
        }
    }

    private static func sourceLine(for source: InboxNotification.Source.PaneSource) -> String {
        if let repoName = source.repo?.name {
            if let worktreeName = source.worktree?.name {
                if let branchName = nonBlank(source.branchName), branchName != worktreeName {
                    return "\(repoName) · \(worktreeName) / \(branchName)"
                }
                return "\(repoName) · \(worktreeName)"
            }
            return repoName
        }

        if let worktreeName = source.worktree?.name {
            if let branchName = nonBlank(source.branchName), branchName != worktreeName {
                return "\(worktreeName) / \(branchName)"
            }
            return worktreeName
        }

        if let branchName = nonBlank(source.branchName) {
            return branchName
        }

        if let runtimeLabel = nonBlank(source.runtimeLabel) {
            return runtimeLabel
        }

        return "Workspace event"
    }

    private static func placementLine(for source: InboxNotification.Source.PaneSource) -> String? {
        var parts: [String] = []
        if let tabName = nonBlank(source.tabName) {
            parts.append("Tab: \(tabName)")
        }

        switch source.paneRole {
        case .main:
            if let paneTitle = nonBlank(source.paneTitle) {
                parts.append("Pane: \(paneTitle)")
            }
        case .drawerChild:
            if let parentPaneTitle = nonBlank(source.parentPaneTitle) {
                parts.append("Pane: \(parentPaneTitle)")
            }
            if let paneTitle = nonBlank(source.paneTitle) {
                parts.append("Drawer: \(paneTitle)")
            } else if let drawerOrdinal = source.drawerOrdinal {
                parts.append("Drawer: \(drawerOrdinal)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func paneGroupLabel(for source: InboxNotification.Source.PaneSource) -> String {
        switch source.paneRole {
        case .main:
            return nonBlank(source.paneTitle) ?? nonBlank(source.runtimeLabel) ?? "Pane"
        case .drawerChild:
            let parentTitle = nonBlank(source.parentPaneTitle) ?? "Pane"
            if let paneTitle = nonBlank(source.paneTitle) {
                return "\(parentTitle) / Drawer: \(paneTitle)"
            }
            if let drawerOrdinal = source.drawerOrdinal {
                return "\(parentTitle) / Drawer \(drawerOrdinal)"
            }
            return "\(parentTitle) / Drawer"
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
```

- [ ] **Step 4: Wire list model to display model**

In `InboxNotificationListModel.filterNotifications(searchText:)`, replace direct field checks with:

```swift
return notifications.filter { notification in
    InboxNotificationSourceDisplay(notification: notification)
        .searchText
        .lowercased()
        .contains(trimmedQuery)
}
```

In `buildSections`, update labels:

```swift
label: { InboxNotificationSourceDisplay(notification: $0).groupLabel(for: .byRepo) ?? "Workspace" }
```

and equivalent for `.byPane` / `.byTab`.

- [ ] **Step 5: Run model tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationSourceDisplayTests|InboxNotificationListModelTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift \
  Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift
git commit -m $'feat: add inbox source display model\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 5: Extract Shared Sidebar Row And Section Header Primitives

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SidebarRowShell.swift`
- Create: `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`

- [ ] **Step 1: Add sidebar row style tokens**

In `AppStyles.Shell.Sidebar`, add:

```swift
static let notificationRowTitleSize: CGFloat = AppStyles.General.Typography.textBase
static let notificationRowSourceSize: CGFloat = AppStyles.General.Typography.textSm
static let notificationRowDetailSize: CGFloat = AppStyles.General.Typography.textSm
static let notificationRowTimestampSize: CGFloat = AppStyles.General.Typography.textSm
static let notificationRowUnreadDotSize: CGFloat = 6
static let rowHorizontalInset: CGFloat = 8
static let rowCornerRadius: CGFloat = AppStyles.General.CornerRadius.bar
```

- [ ] **Step 2: Create `SidebarRowShell`**

Create:

```swift
import SwiftUI

struct SidebarRowShell<Content: View>: View {
    let isSelected: Bool
    let isFlashing: Bool
    let content: Content

    @State private var isHovering = false

    init(
        isSelected: Bool = false,
        isFlashing: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isFlashing = isFlashing
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, AppStyles.Shell.Sidebar.rowVerticalInset)
            .padding(.horizontal, AppStyles.Shell.Sidebar.rowHorizontalInset)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.rowCornerRadius)
            .fill(rowFill)
    }

    private var rowFill: Color {
        if isFlashing {
            return Color.accentColor.opacity(AppStyles.General.Fill.selected)
        }
        if isSelected {
            return Color.accentColor.opacity(AppStyles.General.Fill.active)
        }
        if isHovering {
            return Color.accentColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
        }
        return Color.clear
    }
}
```

- [ ] **Step 3: Create `SidebarSectionHeader`**

Create:

```swift
import SwiftUI

struct SidebarSectionHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.trailingContent = trailingContent()
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppStyles.General.Spacing.standard) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyles.Shell.Sidebar.groupIconSize)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: AppStyles.Shell.Sidebar.groupOrganizationFontSize))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AppStyles.General.Spacing.standard)
                trailingContent
            }
            .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
            .padding(.horizontal, AppStyles.Shell.Sidebar.rowHorizontalInset)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 4: Replace inbox group header**

Update `InboxNotificationGroupHeader` to call `SidebarSectionHeader`:

```swift
struct InboxNotificationGroupHeader: View {
    let label: String
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        SidebarSectionHeader(
            title: label,
            isExpanded: !isCollapsed,
            onToggle: onToggle
        ) {
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: AppStyles.Shell.Sidebar.chipFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppStyles.Shell.Sidebar.countBadgeHorizontalPadding)
                    .padding(.vertical, AppStyles.Shell.Sidebar.countBadgeVerticalPadding)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(AppStyles.Shell.Sidebar.countBadgeBackgroundOpacity))
                    )
            }
        }
    }
}
```

- [ ] **Step 5: Run build**

Run:

```bash
mise run build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SidebarRowShell.swift \
  Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift \
  Sources/AgentStudio/Infrastructure/AppStyles.swift \
  Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift
git commit -m $'feat: add shared sidebar row primitives\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 6: Redesign Inbox Row Content Around Source Context

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [ ] **Step 1: Replace `InboxRow` with source-first content**

Replace `InboxRow` body with:

```swift
struct InboxRow: View {
    let notification: InboxNotification
    let now: Date

    private var display: InboxNotificationSourceDisplay {
        InboxNotificationSourceDisplay(notification: notification)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.General.Spacing.standard) {
                unreadDot
                notificationIcon

                Text(notification.title)
                    .font(.system(
                        size: AppStyles.Shell.Sidebar.notificationRowTitleSize,
                        weight: notification.isRead ? .regular : .semibold
                    ))
                    .foregroundStyle(notification.isRead ? .secondary : .primary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: AppStyles.General.Spacing.standard)

                Text(relativeTime)
                    .font(.system(size: AppStyles.Shell.Sidebar.notificationRowTimestampSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(display.sourceLine)
                .font(.system(size: AppStyles.Shell.Sidebar.notificationRowSourceSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let placementLine = display.placementLine {
                Text(placementLine)
                    .font(.system(size: AppStyles.Shell.Sidebar.notificationRowDetailSize))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let body = notification.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: AppStyles.Shell.Sidebar.notificationRowDetailSize))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var unreadDot: some View {
        if notification.isRead {
            Color.clear
                .frame(
                    width: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize,
                    height: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize
                )
        } else {
            Circle()
                .fill(.red)
                .frame(
                    width: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize,
                    height: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize
                )
        }
    }

    private var notificationIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: AppStyles.Shell.Sidebar.worktreeIconSize, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)
    }

    private var iconName: String {
        switch notification.kind {
        case .agentDesktopNotification, .agentRpc:
            return "terminal"
        case .bellRang:
            return "bell"
        case .commandFinished:
            return "checkmark.circle"
        case .terminalSecureInputRequested:
            return "keyboard"
        case .terminalProgressError, .terminalRendererUnhealthy:
            return "exclamationmark.triangle"
        case .persistenceRecovery:
            return "externaldrive.badge.exclamationmark"
        case .approvalRequested:
            return "checkmark.seal"
        case .securityEvent:
            return "lock.shield"
        }
    }

    private var iconColor: Color {
        switch notification.kind {
        case .commandFinished:
            return AppStyles.Shell.Sidebar.chipSuccessColor
        case .terminalProgressError, .terminalRendererUnhealthy, .securityEvent:
            return AppStyles.Shell.Sidebar.chipDangerColor
        case .terminalSecureInputRequested, .approvalRequested:
            return AppStyles.Shell.Sidebar.chipWarningColor
        default:
            return .secondary
        }
    }
}
```

Keep the existing `relativeTime` property.

- [ ] **Step 2: Wrap sidebar rows in `SidebarRowShell`**

In `InboxSidebarNotificationRow.body`, replace:

```swift
InboxRow(notification: notification, now: now)
```

with:

```swift
SidebarRowShell(isFlashing: isFlashing) {
    InboxRow(notification: notification, now: now)
}
```

Keep the existing focus, tap, and key handling modifiers on the shell.

- [ ] **Step 3: Wrap pane inbox rows in the same shell**

In `PaneInboxNotificationPopover`, replace row background logic with:

```swift
SidebarRowShell(
    isSelected: selectedNotificationId == notification.id
) {
    InboxRow(notification: notification, now: Date())
}
```

Remove the custom `RoundedRectangle(...).fill(...)` row background block.

- [ ] **Step 4: Run view tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneInboxNotificationPopoverTests|InboxNotificationSidebarViewTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift
git commit -m $'feat: redesign inbox rows around source context\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 7: Match Sidebar Background And Header Controls

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

- [ ] **Step 1: Match RepoExplorer background**

In `InboxSidebarRootContainer.baseChrome`, add the same background and minimum width as RepoExplorer:

```swift
.frame(minWidth: 200)
.background(Color(nsColor: .windowBackgroundColor))
```

The final body should look like:

```swift
private var baseChrome: some View {
    VStack(spacing: 0) {
        ...
    }
    .frame(minWidth: 200)
    .background(Color(nsColor: .windowBackgroundColor))
}
```

- [ ] **Step 2: Give header controls clear icons and help**

In `InboxSidebarHeader`, replace:

```swift
Image(systemName: sort == .newestFirst ? "arrow.down.to.line" : "arrow.up.to.line")
```

with:

```swift
Image(systemName: sort == .newestFirst ? "arrow.down" : "arrow.up")
```

Add help:

```swift
.help(sort == .newestFirst ? "Newest notifications first" : "Oldest notifications first")
```

For the grouping button, keep `line.3.horizontal.decrease.circle` or replace with:

```swift
Image(systemName: "rectangle.3.group")
```

and add:

```swift
.help("Group notifications")
```

- [ ] **Step 3: Add Unread / All plan hook but do not implement behavior**

Add no UI toggle in this task. Add a private placeholder-free note in the plan follow-up by updating this file's tests only if needed. The Unread / All toggle is a product decision and should be a separate task after the source-display reset lands.

- [ ] **Step 4: Run build**

Run:

```bash
mise run build
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift
git commit -m $'fix: align inbox sidebar chrome with repo sidebar\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 8: Protect Against UUID Labels And Unknown Source Regressions

**Files:**
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

- [ ] **Step 1: Add regression test for no UUID prefixes in labels**

Add:

```swift
@Test("group labels do not expose UUID prefixes")
func groupLabelsDoNotExposeUUIDPrefixes() {
    let tabId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let paneId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let notification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Claude Code",
        paneId: paneId,
        tabId: tabId,
        paneTitle: "Claude"
    )

    let tabModel = InboxNotificationListModel(
        notifications: [notification],
        grouping: .byTab,
        sort: .newestFirst,
        searchText: ""
    )
    let paneModel = InboxNotificationListModel(
        notifications: [notification],
        grouping: .byPane,
        sort: .newestFirst,
        searchText: ""
    )

    #expect(tabModel.sections[0].label?.contains("AAAAAAAA") == false)
    #expect(paneModel.sections[0].label?.contains("11111111") == false)
}
```

- [ ] **Step 2: Add regression test for no `unknown source` display**

Add to `InboxNotificationSourceDisplayTests`:

```swift
@Test("source display never emits unknown source")
func sourceDisplayNeverEmitsUnknownSource() {
    let notification = InboxNotification(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 100),
        kind: .agentRpc,
        title: "Notification",
        body: nil,
        source: .pane(.init(paneId: UUID())),
        isRead: false,
        isDismissedFromPaneInbox: false
    )

    let display = InboxNotificationSourceDisplay(notification: notification)

    #expect(display.sourceLine != "unknown source")
    #expect(display.searchText.contains("unknown source") == false)
}
```

- [ ] **Step 3: Run tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationSourceDisplayTests|InboxNotificationListModelTests"
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationSourceDisplayTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift
git commit -m $'test: guard inbox source labels against implementation leaks\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 9: Visual Smoke With Peekaboo

**Files:**
- Create: `docs/wip/debugging/2026-05-07-notification-inbox-sidebar-redesign-smoke.md`

- [ ] **Step 1: Build the app**

Run:

```bash
mise run build
```

Expected: PASS.

- [ ] **Step 2: Launch with trace disabled for visual smoke**

Run:

```bash
"$SWIFT_BUILD_DIR/debug/AgentStudio" &
APP_PID=$!
echo "$APP_PID"
```

If `SWIFT_BUILD_DIR` is empty, use:

```bash
".build/debug/AgentStudio" &
APP_PID=$!
echo "$APP_PID"
```

- [ ] **Step 3: Capture RepoExplorer and Inbox screenshots**

Run:

```bash
peekaboo see --app "PID:$APP_PID" --json > /tmp/agentstudio-inbox-redesign-initial.json
```

Manually switch to RepoExplorer and Inbox, then capture:

```bash
peekaboo see --app "PID:$APP_PID" --json > /tmp/agentstudio-inbox-redesign-after-switch.json
```

- [ ] **Step 4: Create smoke note**

Create `docs/wip/debugging/2026-05-07-notification-inbox-sidebar-redesign-smoke.md`:

```markdown
# 2026-05-07 Notification Inbox Sidebar Redesign Smoke

## Result

- RepoExplorer background and Inbox background match:
- Inbox row source line shows repo/worktree/branch:
- Inbox row placement line shows tab/pane/drawer context:
- No row displays `unknown source`:
- Command duration appears human-scale:
- Sort icon no longer looks like download:
- Group labels avoid UUID prefixes:
- PaneInbox row content matches global inbox row content:

## Evidence

- Initial capture: `/tmp/agentstudio-inbox-redesign-initial.json`
- After switch capture: `/tmp/agentstudio-inbox-redesign-after-switch.json`
```

Fill each result line with `yes`, `no`, or `not exercised`.

- [ ] **Step 5: Commit smoke note**

```bash
git add docs/wip/debugging/2026-05-07-notification-inbox-sidebar-redesign-smoke.md
git commit -m $'docs: add notification inbox redesign smoke note\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 10: Full Verification

**Files:**
- No source changes unless verification fails.

- [ ] **Step 1: Format**

Run:

```bash
mise run format
```

Expected: exit 0.

- [ ] **Step 2: Build**

Run:

```bash
mise run build
```

Expected: exit 0.

- [ ] **Step 3: Full tests**

Run:

```bash
mise run test
```

Expected: all Swift Testing tests pass.

- [ ] **Step 4: Lint**

Run:

```bash
mise run lint
```

Expected: exit 0, zero swiftlint/swift-format/boundary errors.

- [ ] **Step 5: Commit formatting or verification fixes**

Only if files changed:

```bash
git add Sources Tests docs
git commit -m $'chore: finalize notification inbox sidebar redesign\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Out Of Scope / Follow-Up

- Unread / All toggle for global inbox and PaneInbox.
- Product decision on whether unseen activity becomes an inbox notification, a badge, or a separate indicator.
- Raw terminal-output parsing, file links, diagnostics, and structured agent updates.
- Replacing the inbox grouping model with a fully nested outline if the simple section model still feels too flat after this redesign.
- Accessibility-specific keyboard and VoiceOver pass.

## Self-Review

### Spec Coverage

- Original inbox spec row anatomy is covered by Tasks 4 and 6.
- Source context denormalization is covered by Task 2.
- Repo/sidebar visual parity is covered by Tasks 5, 6, and 7.
- Command-finished duration correctness is covered by Task 3.
- Grouping label honesty is covered by Tasks 4 and 8.
- PaneInbox naming and shared row content are covered by Task 6.
- Visual verification is covered by Task 9.

### Placeholder Scan

This plan avoids `TBD`, "write tests for the above", and "handle edge cases" placeholders. The only deferred items are explicitly listed in Out Of Scope with concrete follow-up names.

### Type Consistency

New source context fields are consistently named:

- `tabName`
- `paneTitle`
- `paneRole`
- `parentPaneId`
- `parentPaneTitle`
- `drawerOrdinal`
- `runtimeLabel`

The display type is consistently named `InboxNotificationSourceDisplay`, and grouping remains `InboxNotificationGrouping`.
