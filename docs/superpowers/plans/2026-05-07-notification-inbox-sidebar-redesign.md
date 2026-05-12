# Notification Inbox Sidebar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the notification inbox read like an Agent Studio sidebar surface: every row shows useful source context, command durations are correct, global inbox and PaneInbox share row semantics, and the UI no longer leaks implementation IDs or mismatched chrome.

**Architecture:** Keep notification domain state inside `Features/InboxNotification/`, denormalize human source labels at emit time, and route presentation through feature-owned display models. Promote only stateless, atom-free visual primitives into `SharedComponents/`; feature wrappers own hover, focus, selection, commands, filtering, and activation.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit-hosted sidebar, Swift Testing, `mise run build`, `mise run test`, `mise run lint`, Peekaboo PID-based visual verification.

---

## Current Completion Status

Status as of 2026-05-12 on branch `notification-inbox-redesign`:

- Code implementation and automated verification were previously green, but that did not mean product visual acceptance was complete.
- Product visual acceptance is still tracked separately. See `docs/wip/communications/2026-05-11-notification-inbox-visual-feedback-ledger.md`.
- The follow-up plan `docs/superpowers/plans/2026-05-11-notification-inbox-sidebar-style-convergence.md` owns the missing visual/style/test pieces.
- Treat this redesign as incomplete until the visual ledger is either checked off with screenshot evidence or explicitly split into named follow-up work with user approval.

---

## Review Corrections Locked In

This plan has been revised after Codex xhigh and Claude Opus 4.7 review. These are constraints, not suggestions:

- Use current code symbols:
  - `InboxNotification.PaneSource`, not `InboxNotification.Source.PaneSource`.
  - `PaneContent.bridgePanel`, not `.bridge`.
  - `BridgePanelKind` currently has `.diffViewer` only; no `displayTitle` exists.
  - `AttendedPaneAtom` is derived-only. Do not add `setAttendedPaneId`.
  - `PaneFocusTracker.stop()` is async and must be awaited in tests.
  - The router test helper `addTerminalPane(_:to:repoId:worktreeId:)` returns a tab `UUID` and has no `title:` parameter.
- Preserve green commits. Write failing tests and implementation in the same task, then commit only after the focused tests pass.
- Commit steps are included because this branch workflow has been explicitly using commits as checkpoints. If execution happens without git-write permission, skip commit steps and keep the file changes staged/uncommitted for review.
- Build directories:
  - Main agent shell may use `.build-agent-$PPID`.
  - Subagents must use `.build-agent-$$`.
  - Every command below uses `BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"` so a subagent does not lock the parent build directory.
- Shared components are stateless. They take values and closures. They do not own `@State`, subscribe to atoms, import `Core/`, import `Features/`, or know about inbox/repo domain types.
- Persistence is part of the design. Adding source display fields must not quarantine existing inbox files.

## Scope

This plan covers the global sidebar inbox, PaneInbox row reuse, source display, duration correctness, grouping labels, active filter labels, shared sidebar chrome primitives, and visual smoke evidence.

This plan does not implement raw terminal-output capture, full unseen-activity promotion, or the later Unread/All product toggle. It does include the narrow PaneInbox observed-source clear policy needed so unread badges do not stay lit after the user has actually observed the source terminal pane.

### Investigation Note: PaneInbox Badge Sticking While Observed

Manual smoke found a bug outside pure badge geometry: the PaneInbox badge can remain visible while the source terminal pane is focused and scrolled to the bottom.

Current code explains the behavior:

- `InboxNotificationAtom.visiblePaneInboxUnreadCount(forPaneIds:)` counts notifications that are unread and not `isDismissedFromPaneInbox`.
- `InboxNotificationRouter` listens to `PaneFocusTracker.focusGainedStream`, but the focus path only records `inbox.focusGainedObservedPane`; it does not mark anything read or dismiss anything from PaneInbox.
- `TerminalActivityAtom` records output-burst growth from `ScrollbarState.total` and now retains whether a pane is pinned to bottom.
- `ScrollbarState.isPinnedToBottom` already exists, and terminal UI also computes an effective pinned-to-bottom state for the scroll-to-bottom affordance, but that observation state is not available to the inbox policy.
- `desktopNotificationRequested` and `bellRang` currently notify even for the attended pane. `commandFinished` and `secureInputChanged` already suppress attended-pane notifications.

So the bug is not random UI state. It is a missing observation policy: PaneInbox unread state has no way to know that the user is currently looking at the source pane at the live bottom of its output.

This plan therefore includes a narrow observed-pane clear policy for PaneInbox badges. It does not implement full unseen-activity promotion. It only defines when pane-scoped unread affordances should clear once a notification has already been created.

### Locked Heuristics

- Auto-clearable kinds: `agentDesktopNotification`, `bellRang`, `commandFinished`, `agentRpc`, and future `unseenActivity`.
- User-action-required kinds: `approvalRequested`, `securityEvent`, `persistenceRecovery`, `terminalProgressError`, `terminalRendererUnhealthy`, `terminalSecureInputRequested`.
- Observed means the source pane is attended and pinned to bottom.
- If an auto-clearable event arrives while already observed, append a read + PaneInbox-dismissed history row; do not light any unread affordance.
- Parent PaneInbox scope does not change observation ownership. Drawer-child rows clear only when the drawer child source pane is observed.
- PaneInbox and global inbox use the same read flag. Auto-clearing a row marks it read globally and dismisses it from PaneInbox, so the global badge and PaneInbox badge cannot disagree.

The original inbox spec treated broad SharedComponents extraction as out of scope. That is superseded by the later project rule in `AGENTS.md`: when two app surfaces need the same visual control and interaction semantics, extract a stateless primitive into `SharedComponents/`.

## Requirements

- Rows must always show useful source context.
  - Preferred: repo + worktree + branch.
  - Also show placement: tab, main pane, drawer child when known.
  - Fallbacks must be human labels, never `unknown source` or UUID prefixes.
- Command-finished duration must interpret Ghostty duration as nanoseconds.
- `By tab` grouping must use a stable human label:
  - tab name when non-empty
  - otherwise `Tab N` from current tab order at emit time
  - otherwise `Untitled Tab`
- `By pane` grouping must distinguish main panes from drawer child panes.
- Active filter chips must not show `Repo <uuid>` or `Worktree <uuid>`.
- Inbox sidebar background and row rhythm must match RepoExplorer.
- Sort/group controls must use clear icons and tooltips.
- Global inbox and PaneInbox must use the same row rendering component, with a row context that hides redundant placement in PaneInbox.
- Sidebar unread affordance must remain visible in collapsed and expanded states.
- The global inbox toolbar badge must match the PaneInbox badge treatment: red numeric capsule anchored to the bell's top-trailing corner. Do not use a loose fixed-position red dot.
- Both inbox surfaces must expose a visible clear-notifications control:
  - global sidebar inbox clears global notification history through a command-backed action
  - PaneInbox clears the active pane scope through a command-backed action
  - controls must use command definitions for icon/help/tooltip labels, not local string drift
- PaneInbox unread badges must represent unobserved source-pane activity, not historical rows the user is already looking at.
- A terminal pane is observed for PaneInbox clearing only when it is the attended pane and its latest terminal scrollbar state is pinned to bottom. Focus alone is insufficient because the user may be reading scrollback; bottom alone is insufficient because the pane may be unattended.
- Observed-pane clearing applies only to auto-clearable pane activity. Explicit action/security/approval rows stay until the user activates or marks them read.

## File Structure

### New Files

- `Sources/AgentStudio/SharedComponents/SidebarRowShell.swift`
  - Stateless shared row shell for sidebar-like list rows.
  - Inputs: selected/flashing/hover state and content.
  - Imports SwiftUI + Infrastructure only.

- `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift`
  - Stateless shared collapsible section header with optional trailing content.
  - Used by inbox group headers and RepoExplorer group headers where semantics match.

- `Sources/AgentStudio/SharedComponents/UnreadCountBadge.swift`
  - Stateless SwiftUI unread-count badge.
  - Shared by PaneInbox drawer button and the global inbox sidebar toolbar button.
  - Takes display text as a value. Does not know about atoms, pane inbox, or notification policy.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
  - Feature-owned source display model.
  - Produces source line, placement line, grouping labels, active filter labels, search text, and row-specific presentation.

- `Sources/AgentStudio/Features/InboxNotification/Models/PaneInboxAutoClearPolicy.swift`
  - Feature-owned policy for deciding which pane notifications may auto-clear when observed.
  - Keeps product semantics out of `InboxNotificationAtom`.

- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
  - Pins source/placement/group/filter labels and fallbacks through the display model and list model.

- `Tests/AgentStudioTests/Features/InboxNotification/Models/PaneInboxAutoClearPolicyTests.swift`
  - Pins auto-clearable vs user-action-required notification kinds.

- `Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift`
  - Minimal compile/initialization coverage for the generic header helpers.

- `Tests/AgentStudioTests/SharedComponents/UnreadCountBadgeTests.swift`
  - Minimal compile coverage for the shared unread badge primitive.

### Modified Files

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
  - Extend `InboxNotification.PaneSource` with denormalized tab/pane/drawer/runtime fields.
  - Add custom decode defaults for old stored notifications.

- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
  - Bump payload schema to 2.
  - Accept schema 1 and 2 on load.
  - Save schema 2 on next flush.

- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
  - Populate denormalized source fields.
  - Compare and format command duration as nanoseconds.
  - Clear auto-clearable PaneInbox rows when focus and bottom observation prove the user has seen the source pane.

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Add command identities for clearing global inbox notifications and active PaneInbox notifications.

- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
  - Add command specs for clear controls so visible buttons, command bar rows, and tooltips share labels/icons/help.

- `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationCommands.swift`
  - Route global clear commands through the existing inbox command seam.

- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Execute the active-pane clear command against the same PaneInbox target resolver used by the PaneInbox toggle command.

- `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
  - Add a command-backed clear closure for active PaneInbox scope.

- `Sources/AgentStudio/Features/Terminal/State/MainActor/Atoms/TerminalActivityAtom.swift`
  - Retain latest `ScrollbarState` or a derived pinned-to-bottom flag per pane.
  - Do not turn raw scrollbar callbacks into notifications here.

- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
  - Use `InboxNotificationSourceDisplay` for search and group labels.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
  - Render compact source-first row content.
  - Accept a row context so global inbox and PaneInbox can share rendering without duplicating redundant placement.

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
  - Wrap `SidebarSectionHeader`.

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
  - Use shared row shell.
  - Match RepoExplorer chrome.
  - Replace UUID active-filter labels.
  - Clarify sort/group controls.

- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
  - Use shared row shell and shared `InboxRow`.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
  - Replace inline PaneInbox badge drawing with `UnreadCountBadge`.

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`
  - Adopt `SidebarSectionHeader` if exact current semantics are preserved.

- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
  - Replace fixed-position red unread dot with a count badge hosted on the inbox toolbar button.
  - Badge geometry must visually match PaneInbox's drawer icon badge.

- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  - Add style tokens only when existing sidebar tokens are insufficient.

- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
  - Add duration nanosecond policy.

- Tests:
  - `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`
  - `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift`
  - `Tests/AgentStudioTests/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStoreTests.swift`
  - `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
  - `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`
  - `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
  - `Tests/AgentStudioTests/Features/InboxNotification/Models/PaneInboxAutoClearPolicyTests.swift`
  - `Tests/AgentStudioTests/Features/Terminal/State/TerminalActivityAtomTests.swift`
  - `Tests/AgentStudioTests/App/AppCommandTests.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
  - `Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxCommandsTests.swift`

---

## Task 1: Source Context Schema And Routing

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStoreTests.swift`

- [x] **Step 1: Add routing tests using the current fixture API**

Add this test to `InboxNotificationRouterTests`:

```swift
@Test("pane notification stores denormalized tab pane and runtime source context")
func paneNotificationStoresSourceDisplayContext() async {
    let fixture = await makeFixture()
    let paneId = PaneId()
    let tabId = addTerminalPane(paneId, to: fixture)
    fixture.tabLayout.renameTab(tabId, name: "Work")
    fixture.paneAtom.renamePane(paneId.uuid, title: "Claude")

    _ = await fixture.bus.post(
        makePaneEnvelope(
            paneId: paneId,
            event: .terminal(.desktopNotificationRequested(title: "Claude Code", body: "waiting"))
        )
    )

    await waitForNotificationCount(
        1,
        in: fixture,
        description: "desktop notification should capture source context"
    )

    let notification = fixture.inboxAtom.notifications[0]
    guard case .pane(let source) = notification.source else {
        Issue.record("Expected pane source")
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
        return
    }

    #expect(source.tabId == tabId)
    #expect(source.tabDisplayLabel == "Work")
    #expect(source.paneDisplayLabel == "Claude")
    #expect(source.paneRole == .main)
    #expect(source.parentPaneId == nil)
    #expect(source.runtimeDisplayLabel == "Terminal")
    await fixture.router.stop()
    await fixture.tracker.stop()
    fixture.attendedPane.stop()
}
```

Add this test to `InboxNotificationRouterDrawerChildTests`:

```swift
@Test("drawer child notification stores parent and drawer source context")
func drawerChildNotificationStoresParentAndDrawerSourceContext() async throws {
    let fixture = await makeFixture()
    let parentPaneId = PaneId()
    let tabId = addTerminalPane(parentPaneId, to: fixture)
    fixture.tabLayout.renameTab(tabId, name: "Work")
    fixture.paneAtom.renamePane(parentPaneId.uuid, title: "Claude")
    let drawerPane = try #require(
        fixture.paneAtom.addDrawerPane(to: parentPaneId.uuid, parentFallbackCWD: nil)
    )
    fixture.paneAtom.renamePane(drawerPane.id, title: "Gemini")

    _ = await fixture.bus.post(
        makePaneEnvelope(
            paneId: PaneId(uuid: drawerPane.id),
            event: .terminal(.desktopNotificationRequested(title: "Gemini", body: "waiting"))
        )
    )

    await waitForNotificationCount(
        1,
        in: fixture,
        description: "drawer child desktop notification should capture source context"
    )

    let notification = fixture.inboxAtom.notifications[0]
    guard case .pane(let source) = notification.source else {
        Issue.record("Expected pane source")
        await fixture.router.stop()
        await fixture.tracker.stop()
        fixture.attendedPane.stop()
        return
    }

    #expect(source.tabId == tabId)
    #expect(source.tabDisplayLabel == "Work")
    #expect(source.paneDisplayLabel == "Gemini")
    #expect(source.paneRole == .drawerChild)
    #expect(source.parentPaneId == parentPaneId.uuid)
    #expect(source.parentPaneDisplayLabel == "Claude")
    #expect(source.drawerOrdinal == 1)
    #expect(source.runtimeDisplayLabel == "Terminal")
    await fixture.router.stop()
    await fixture.tracker.stop()
    fixture.attendedPane.stop()
}
```

Add this test to `InboxNotificationRouterTests` to pin the tab fallback:

```swift
@Test("source context uses tab ordinal fallback when tab name is empty")
func sourceContextUsesTabOrdinalFallbackWhenTabNameIsEmpty() async {
    let fixture = await makeFixture()
    let paneId = PaneId()
    let tabId = addTerminalPane(paneId, to: fixture)
    fixture.tabLayout.renameTab(tabId, name: " ")

    _ = await fixture.bus.post(
        makePaneEnvelope(
            paneId: paneId,
            event: .terminal(.desktopNotificationRequested(title: "Done", body: nil))
        )
    )

    await waitForNotificationCount(
        1,
        in: fixture,
        description: "notification should use a human tab fallback"
    )

    let source = try? #require(fixture.inboxAtom.notifications[0].paneContext)
    #expect(source?.tabDisplayLabel == "Tab 1")
    await fixture.router.stop()
    await fixture.tracker.stop()
    fixture.attendedPane.stop()
}
```

- [x] **Step 2: Extend `InboxNotification.PaneSource`**

In `InboxNotification.swift`, add the pane role enum and fields directly under `PaneSource`:

```swift
struct PaneSource: Sendable, Codable, Equatable {
    enum PaneRole: String, Sendable, Codable, Equatable {
        case main
        case drawerChild
    }

    let paneId: UUID
    let tabId: UUID?
    let tabDisplayLabel: String?
    let repo: NamedSource?
    let worktree: NamedSource?
    let branchName: String?
    let paneDisplayLabel: String?
    let paneRole: PaneRole
    let parentPaneId: UUID?
    let parentPaneDisplayLabel: String?
    let drawerOrdinal: Int?
    let runtimeDisplayLabel: String?
}
```

Update the initializer:

```swift
init(
    paneId: UUID,
    tabId: UUID? = nil,
    tabDisplayLabel: String? = nil,
    repoId: UUID? = nil,
    repoName: String? = nil,
    worktreeId: UUID? = nil,
    worktreeName: String? = nil,
    branchName: String? = nil,
    paneDisplayLabel: String? = nil,
    paneRole: PaneRole = .main,
    parentPaneId: UUID? = nil,
    parentPaneDisplayLabel: String? = nil,
    drawerOrdinal: Int? = nil,
    runtimeDisplayLabel: String? = nil
) {
    self.paneId = paneId
    self.tabId = tabId
    self.tabDisplayLabel = tabDisplayLabel.nilIfBlank
    self.repo = NamedSource(id: repoId, name: repoName)
    self.worktree = NamedSource(id: worktreeId, name: worktreeName)
    self.branchName = branchName.nilIfBlank
    self.paneDisplayLabel = paneDisplayLabel.nilIfBlank
    self.paneRole = paneRole
    self.parentPaneId = parentPaneId
    self.parentPaneDisplayLabel = parentPaneDisplayLabel.nilIfBlank
    self.drawerOrdinal = drawerOrdinal
    self.runtimeDisplayLabel = runtimeDisplayLabel.nilIfBlank
}
```

Add custom decode defaults so old notification entries decode:

```swift
private enum CodingKeys: String, CodingKey {
    case paneId
    case tabId
    case tabDisplayLabel
    case repo
    case worktree
    case branchName
    case paneDisplayLabel
    case paneRole
    case parentPaneId
    case parentPaneDisplayLabel
    case drawerOrdinal
    case runtimeDisplayLabel
}

init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.paneId = try container.decode(UUID.self, forKey: .paneId)
    self.tabId = try container.decodeIfPresent(UUID.self, forKey: .tabId)
    self.tabDisplayLabel = try container.decodeIfPresent(String.self, forKey: .tabDisplayLabel)?.nilIfBlank
    self.repo = try container.decodeIfPresent(NamedSource.self, forKey: .repo)
    self.worktree = try container.decodeIfPresent(NamedSource.self, forKey: .worktree)
    self.branchName = try container.decodeIfPresent(String.self, forKey: .branchName)?.nilIfBlank
    self.paneDisplayLabel = try container.decodeIfPresent(String.self, forKey: .paneDisplayLabel)?.nilIfBlank
    self.paneRole = try container.decodeIfPresent(PaneRole.self, forKey: .paneRole) ?? .main
    self.parentPaneId = try container.decodeIfPresent(UUID.self, forKey: .parentPaneId)
    self.parentPaneDisplayLabel =
        try container.decodeIfPresent(String.self, forKey: .parentPaneDisplayLabel)?.nilIfBlank
    self.drawerOrdinal = try container.decodeIfPresent(Int.self, forKey: .drawerOrdinal)
    self.runtimeDisplayLabel =
        try container.decodeIfPresent(String.self, forKey: .runtimeDisplayLabel)?.nilIfBlank
}
```

Keep synthesized encoding. Add this extension at file bottom if missing:

```swift
private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

Add computed accessors to `InboxNotification`:

```swift
var paneContext: PaneSource? {
    guard case .pane(let paneSource) = source else { return nil }
    return paneSource
}

var tabDisplayLabel: String? { paneContext?.tabDisplayLabel }
var paneDisplayLabel: String? { paneContext?.paneDisplayLabel }
var paneRole: PaneSource.PaneRole? { paneContext?.paneRole }
var parentPaneId: UUID? { paneContext?.parentPaneId }
var parentPaneDisplayLabel: String? { paneContext?.parentPaneDisplayLabel }
var drawerOrdinal: Int? { paneContext?.drawerOrdinal }
var runtimeDisplayLabel: String? { paneContext?.runtimeDisplayLabel }
```

- [x] **Step 3: Add payload schema migration tests**

Add tests to `InboxNotificationStoreTests`:

```swift
@Test("schema v1 inbox payload loads and defaults new pane source fields")
func schemaV1PayloadLoadsAndDefaultsNewPaneSourceFields() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentstudio-inbox-v1-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("inbox.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let paneId = UUID()
    let payload = """
    {
      "schemaVersion": 1,
      "notifications": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "timestamp": "2026-05-07T00:00:00Z",
          "kind": "agentRpc",
          "title": "Claude Code",
          "body": "waiting",
          "source": {
            "pane": {
              "_0": {
                "paneId": "\(paneId.uuidString)",
                "tabId": null,
                "repo": null,
                "worktree": null,
                "branchName": null
              }
            }
          },
          "isRead": false,
          "isDismissedFromPaneInbox": false
        }
      ],
      "prefs": { "grouping": "none", "sort": "newestFirst", "bellEnabled": true }
    }
    """
    try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    let inboxAtom = InboxNotificationAtom()
    let prefsAtom = InboxNotificationPrefsAtom()
    let store = InboxNotificationStore(
        inboxAtom: inboxAtom,
        prefsAtom: prefsAtom,
        fileURL: fileURL,
        debounceDuration: .milliseconds(1)
    )

    try store.load()

    let notification = try #require(inboxAtom.notifications.first)
    let source = try #require(notification.paneContext)
    #expect(source.paneRole == .main)
    #expect(source.tabDisplayLabel == nil)
    #expect(source.paneDisplayLabel == nil)
    #expect(source.runtimeDisplayLabel == nil)
    #expect(prefsAtom.bellEnabled == true)
}
```

If existing store tests already have fixture helpers, use them instead of duplicating temporary directory setup. The assertions must stay.

- [x] **Step 4: Update `InboxNotificationStore.Payload` schema handling**

In `InboxNotificationStore.swift`:

```swift
private struct Payload: Codable {
    static let currentSchemaVersion = 2
    private static let supportedSchemaVersions: Set<Int> = [1, 2]
```

Change the initializer default so test-only construction also writes the current schema:

```swift
init(
    schemaVersion: Int = Self.currentSchemaVersion,
    notifications: [InboxNotification],
    prefs: Prefs
)
```

Replace the schema guard with:

```swift
guard Self.supportedSchemaVersions.contains(decodedSchemaVersion) else {
    throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "Inbox notification schemaVersion \(decodedSchemaVersion) is unsupported"
    )
}
self.schemaVersion = decodedSchemaVersion
```

Do not carry two runtime data models. Decoding v1 into the current `InboxNotification` model with defaults is the migration. `flush()` must still write `Payload.currentSchemaVersion`.

- [x] **Step 5: Populate source context in router**

Replace the router's resolved context type with:

```swift
private struct ResolvedPaneContext {
    let tabId: UUID?
    let tabDisplayLabel: String?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
    let paneDisplayLabel: String?
    let paneRole: InboxNotification.PaneSource.PaneRole
    let parentPaneId: UUID?
    let parentPaneDisplayLabel: String?
    let drawerOrdinal: Int?
    let runtimeDisplayLabel: String?
}
```

Use current APIs in `resolveContext(for:)`:

```swift
private func resolveContext(for paneId: UUID) -> ResolvedPaneContext? {
    guard let pane = paneAtom.pane(paneId) else { return nil }
    let tab = tabLayout.tabContaining(paneId: paneId)
    let tabDisplayLabel = tabDisplayLabel(for: tab)
    let parentPaneId = pane.parentPaneId
    let parentPane = parentPaneId.flatMap { paneAtom.pane($0) }
    let drawerOrdinal = parentPane?.drawer?.paneIds.firstIndex(of: paneId).map { $0 + 1 }

    return ResolvedPaneContext(
        tabId: tab?.id,
        tabDisplayLabel: tabDisplayLabel,
        repoId: pane.repoId,
        repoName: pane.metadata.repoName,
        worktreeId: pane.worktreeId,
        worktreeName: pane.metadata.worktreeName,
        branchName: pane.metadata.checkoutRef,
        paneDisplayLabel: pane.title,
        paneRole: parentPaneId == nil ? .main : .drawerChild,
        parentPaneId: parentPaneId,
        parentPaneDisplayLabel: parentPane?.title,
        drawerOrdinal: drawerOrdinal,
        runtimeDisplayLabel: runtimeDisplayLabel(for: pane.content)
    )
}

private func tabDisplayLabel(for tab: Tab?) -> String? {
    guard let tab else { return nil }
    let trimmedName = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty { return trimmedName }
    if let index = tabLayout.tabs.firstIndex(where: { $0.id == tab.id }) {
        return "Tab \(index + 1)"
    }
    return "Untitled Tab"
}

private func runtimeDisplayLabel(for content: PaneContent) -> String? {
    switch content {
    case .terminal:
        return "Terminal"
    case .webview:
        return "Web"
    case .bridgePanel(let state):
        return bridgePanelDisplayLabel(for: state.panelKind)
    case .codeViewer:
        return "Code"
    case .unsupported:
        return nil
    }
}

private func bridgePanelDisplayLabel(for kind: BridgePanelKind) -> String {
    switch kind {
    case .diffViewer:
        return "Diff"
    }
}
```

Pass fields into `InboxNotification.PaneSource`:

```swift
source: .pane(
    .init(
        paneId: paneId,
        tabId: resolvedContext?.tabId,
        tabDisplayLabel: resolvedContext?.tabDisplayLabel,
        repoId: resolvedContext?.repoId,
        repoName: resolvedContext?.repoName,
        worktreeId: resolvedContext?.worktreeId,
        worktreeName: resolvedContext?.worktreeName,
        branchName: resolvedContext?.branchName,
        paneDisplayLabel: resolvedContext?.paneDisplayLabel,
        paneRole: resolvedContext?.paneRole ?? .main,
        parentPaneId: resolvedContext?.parentPaneId,
        parentPaneDisplayLabel: resolvedContext?.parentPaneDisplayLabel,
        drawerOrdinal: resolvedContext?.drawerOrdinal,
        runtimeDisplayLabel: resolvedContext?.runtimeDisplayLabel
    )
)
```

- [x] **Step 6: Run focused tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "InboxNotificationRouterTests|InboxNotificationRouterDrawerChildTests|InboxNotificationStoreTests"
```

Expected: PASS.

- [x] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift \
  Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift \
  Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStoreTests.swift
git commit -m $'feat: denormalize inbox source context\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 2: Command Duration Nanoseconds

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift`

- [x] **Step 1: Add duration test**

Add this test to `InboxNotificationRouterTests`:

```swift
@Test("commandFinished duration from Ghostty nanoseconds renders as seconds")
func commandFinishedDurationUsesGhosttyNanoseconds() async {
    let fixture = await makeFixture()

    let paneId = PaneId()
    _ = addTerminalPane(paneId, to: fixture)

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
    await fixture.tracker.stop()
    fixture.attendedPane.stop()
}
```

- [x] **Step 2: Add nanosecond policy**

In `AppPolicies.InboxNotification`:

```swift
static let commandFinishedMinDurationSeconds: UInt64 = 10
static let commandFinishedMinDurationNanoseconds: UInt64 =
    commandFinishedMinDurationSeconds * 1_000_000_000
```

- [x] **Step 3: Compare and format nanoseconds**

In `InboxNotificationRouter`, compare the raw Ghostty duration against the nanosecond policy:

```swift
guard duration >= AppPolicies.InboxNotification.commandFinishedMinDurationNanoseconds else {
    return .ignore(reason: "below_duration_threshold")
}
```

Replace the formatter with:

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

- [x] **Step 4: Update inbox router tests only**

In inbox notification router tests, convert command-finished durations:

```swift
duration: 20_000_000_000
duration: 15_000_000_000
duration: 3_000_000_000
```

Do not change Ghostty adapter/action router tests that prove raw payload forwarding.

- [x] **Step 5: Run focused tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "InboxNotificationRouterTests|InboxNotificationRouterDrawerChildTests|GhosttyActionRouterTests|GhosttyAdapterTests"
```

Expected: PASS. The new test must assert `exit 0 · 18s`.

- [x] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/AppPolicies.swift \
  Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterDrawerChildTests.swift
git commit -m $'fix: treat inbox command durations as nanoseconds\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 3: Inbox Source Display Model

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

- [x] **Step 1: Add display tests**

Add `InboxNotificationSourceDisplay` coverage to `InboxNotificationListModelTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListModel")
struct InboxNotificationListModelTests {
    @Test("repo source line includes worktree and distinct branch")
    func repoSourceLineIncludesDistinctBranch() {
        let notification = makeNotification(
            repoName: "askluna",
            worktreeName: "notification-system",
            branchName: "notification-system-5",
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Claude"
        )

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.sourceLine == "askluna · notification-system / notification-system-5")
        #expect(display.placementLine == "Tab Work · Pane Claude")
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
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneDisplayLabel: "Claude",
            drawerOrdinal: 2
        )

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.sourceLine == "askluna · askluna")
        #expect(display.placementLine == "Tab Work · Pane Claude · Drawer Gemini")
        #expect(display.groupLabel(for: .byPane) == "Claude / Drawer Gemini")
    }

    @Test("pane inbox hides redundant parent placement")
    func paneInboxHidesRedundantParentPlacement() {
        let parentPaneId = UUID()
        let notification = makeNotification(
            parentPaneId: parentPaneId,
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneDisplayLabel: "Claude"
        )

        let display = InboxNotificationSourceDisplay(
            notification: notification,
            rowContext: .paneInbox(parentPaneId: parentPaneId)
        )

        #expect(display.placementLine == "Drawer Gemini")
    }

    @Test("source display never emits unknown source")
    func sourceDisplayNeverEmitsUnknownSource() {
        let notification = makeNotification()

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.sourceLine != "unknown source")
        #expect(display.searchText.contains("unknown source") == false)
        #expect(display.sourceLine == "Terminal")
    }

    @Test("filter labels never expose UUID prefixes")
    func filterLabelsNeverExposeUUIDPrefixes() {
        let repoId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let worktreeId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let notification = makeNotification(
            repoId: repoId,
            repoName: "askluna",
            worktreeId: worktreeId,
            worktreeName: "notification-system"
        )

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.filterLabel(for: .repo(id: repoId)) == "askluna")
        #expect(display.filterLabel(for: .worktree(id: worktreeId)) == "notification-system")
    }

    private func makeNotification(
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil,
        parentPaneId: UUID? = nil,
        tabDisplayLabel: String? = nil,
        paneDisplayLabel: String? = nil,
        paneRole: InboxNotification.PaneSource.PaneRole = .main,
        parentPaneDisplayLabel: String? = nil,
        drawerOrdinal: Int? = nil,
        runtimeDisplayLabel: String? = "Terminal"
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
                    tabDisplayLabel: tabDisplayLabel,
                    repoId: repoId,
                    repoName: repoName,
                    worktreeId: worktreeId,
                    worktreeName: worktreeName,
                    branchName: branchName,
                    paneDisplayLabel: paneDisplayLabel,
                    paneRole: paneRole,
                    parentPaneId: parentPaneId,
                    parentPaneDisplayLabel: parentPaneDisplayLabel,
                    drawerOrdinal: drawerOrdinal,
                    runtimeDisplayLabel: runtimeDisplayLabel
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
```

- [x] **Step 2: Implement `InboxNotificationSourceDisplay`**

Create `InboxNotificationSourceDisplay.swift`:

```swift
import Foundation

struct InboxNotificationSourceDisplay: Sendable, Equatable {
    enum RowContext: Sendable, Equatable {
        case globalInbox
        case paneInbox(parentPaneId: UUID)
    }

    let sourceLine: String
    let placementLine: String?
    let searchText: String

    private let repoGroupLabel: String
    private let paneGroupLabel: String
    private let tabGroupLabel: String
    private let filterLabels: [InboxFilter: String]

    init(
        notification: InboxNotification,
        rowContext: RowContext = .globalInbox
    ) {
        switch notification.source {
        case .global:
            self.sourceLine = "Workspace event"
            self.placementLine = nil
            self.searchText = [notification.title, notification.body, "Workspace event"]
                .compactMap(\.self)
                .joined(separator: " ")
            self.repoGroupLabel = "Workspace"
            self.paneGroupLabel = "Workspace"
            self.tabGroupLabel = "Workspace"
            self.filterLabels = [:]

        case .pane(let source):
            let sourceLine = Self.sourceLine(for: source)
            let placementLine = Self.placementLine(for: source, rowContext: rowContext)
            self.sourceLine = sourceLine
            self.placementLine = placementLine
            self.searchText = [
                notification.title,
                notification.body,
                sourceLine,
                placementLine,
                source.runtimeDisplayLabel,
            ].compactMap(\.self).joined(separator: " ")
            self.repoGroupLabel = nonBlank(source.repo?.name) ?? "Workspace"
            self.paneGroupLabel = Self.paneGroupLabel(for: source)
            self.tabGroupLabel = nonBlank(source.tabDisplayLabel) ?? "Untitled Tab"
            self.filterLabels = Self.filterLabels(for: source)
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

    func filterLabel(for filter: InboxFilter) -> String? {
        filterLabels[filter]
    }

    private static func sourceLine(for source: InboxNotification.PaneSource) -> String {
        if let repoName = nonBlank(source.repo?.name) {
            if let worktreeName = nonBlank(source.worktree?.name) {
                if let branchName = nonBlank(source.branchName), branchName != worktreeName {
                    return "\(repoName) · \(worktreeName) / \(branchName)"
                }
                return "\(repoName) · \(worktreeName)"
            }
            return repoName
        }

        if let worktreeName = nonBlank(source.worktree?.name) {
            if let branchName = nonBlank(source.branchName), branchName != worktreeName {
                return "\(worktreeName) / \(branchName)"
            }
            return worktreeName
        }

        if let branchName = nonBlank(source.branchName) {
            return branchName
        }

        if let runtimeDisplayLabel = nonBlank(source.runtimeDisplayLabel) {
            return runtimeDisplayLabel
        }

        return "Workspace event"
    }

    private static func placementLine(
        for source: InboxNotification.PaneSource,
        rowContext: RowContext
    ) -> String? {
        var parts: [String] = []
        switch rowContext {
        case .globalInbox:
            if let tabDisplayLabel = nonBlank(source.tabDisplayLabel) {
                parts.append("Tab \(tabDisplayLabel)")
            }
            appendPanePlacement(for: source, to: &parts)

        case .paneInbox(let parentPaneId):
            if source.paneRole == .drawerChild,
                source.parentPaneId == parentPaneId,
                let paneDisplayLabel = nonBlank(source.paneDisplayLabel)
            {
                parts.append("Drawer \(paneDisplayLabel)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func appendPanePlacement(
        for source: InboxNotification.PaneSource,
        to parts: inout [String]
    ) {
        switch source.paneRole {
        case .main:
            if let paneDisplayLabel = nonBlank(source.paneDisplayLabel) {
                parts.append("Pane \(paneDisplayLabel)")
            }
        case .drawerChild:
            if let parentPaneDisplayLabel = nonBlank(source.parentPaneDisplayLabel) {
                parts.append("Pane \(parentPaneDisplayLabel)")
            }
            if let paneDisplayLabel = nonBlank(source.paneDisplayLabel) {
                parts.append("Drawer \(paneDisplayLabel)")
            } else if let drawerOrdinal = source.drawerOrdinal {
                parts.append("Drawer \(drawerOrdinal)")
            } else {
                parts.append("Drawer")
            }
        }
    }

    private static func paneGroupLabel(for source: InboxNotification.PaneSource) -> String {
        switch source.paneRole {
        case .main:
            return nonBlank(source.paneDisplayLabel)
                ?? nonBlank(source.runtimeDisplayLabel)
                ?? "Pane"
        case .drawerChild:
            let parentTitle = nonBlank(source.parentPaneDisplayLabel) ?? "Pane"
            if let paneTitle = nonBlank(source.paneDisplayLabel) {
                return "\(parentTitle) / Drawer \(paneTitle)"
            }
            if let drawerOrdinal = source.drawerOrdinal {
                return "\(parentTitle) / Drawer \(drawerOrdinal)"
            }
            return "\(parentTitle) / Drawer"
        }
    }

    private static func filterLabels(for source: InboxNotification.PaneSource) -> [InboxFilter: String] {
        var labels: [InboxFilter: String] = [:]
        if let repoId = source.repo?.id {
            labels[.repo(id: repoId)] = nonBlank(source.repo?.name) ?? "Filtered repo"
        }
        if let worktreeId = source.worktree?.id {
            labels[.worktree(id: worktreeId)] = nonBlank(source.worktree?.name) ?? "Filtered worktree"
        }
        return labels
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
```

If `InboxFilter` uses different case names, adapt the two filter-label cases to the existing enum and keep the "no UUID label" test.

- [x] **Step 3: Wire list model search and grouping**

In `InboxNotificationListModel`, use the display model:

```swift
private static func matchesSearch(
    notification: InboxNotification,
    searchText: String
) -> Bool {
    let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmedQuery.isEmpty else { return true }
    return InboxNotificationSourceDisplay(notification: notification)
        .searchText
        .lowercased()
        .contains(trimmedQuery)
}
```

Use the same display model for section labels:

```swift
let display = InboxNotificationSourceDisplay(notification: notification)
let label = display.groupLabel(for: grouping)
```

- [x] **Step 4: Add list model UUID regression tests**

Add or update tests in `InboxNotificationListModelTests`:

```swift
@Test("byTab grouping uses tab display label instead of UUID prefix")
func byTabGroupingUsesTabDisplayLabel() {
    let notification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Claude Code",
        paneId: UUID(),
        tabId: UUID(),
        tabDisplayLabel: "Work",
        paneDisplayLabel: "Claude"
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
    let notification = makeInboxNotification(
        timestamp: Date(timeIntervalSince1970: 100),
        title: "Gemini",
        paneId: UUID(),
        repoName: "askluna",
        worktreeName: "askluna",
        branchName: "main",
        paneDisplayLabel: "Gemini",
        paneRole: .drawerChild,
        parentPaneId: parentPaneId,
        parentPaneDisplayLabel: "Claude"
    )

    let model = InboxNotificationListModel(
        notifications: [notification],
        grouping: .byPane,
        sort: .newestFirst,
        searchText: ""
    )

    #expect(model.sections.map(\.label) == ["Claude / Drawer Gemini"])
}
```

Extend the local helper to accept the new display fields. Use `InboxNotification.PaneSource.PaneRole`.

- [x] **Step 5: Run focused tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "InboxNotificationListModelTests"
```

Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationSourceDisplay.swift \
  Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift
git commit -m $'feat: add inbox source display model\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 4: Shared Sidebar Primitives

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SidebarRowShell.swift`
- Create: `Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift`
- Create: `Sources/AgentStudio/SharedComponents/UnreadCountBadge.swift`
- Create: `Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift`
- Create: `Tests/AgentStudioTests/SharedComponents/UnreadCountBadgeTests.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`

- [x] **Step 1: Add style tokens only for shared sidebar chrome**

In `AppStyles.Shell.Sidebar`, add tokens if existing names are missing:

```swift
static let rowHorizontalInset: CGFloat = 8
static let rowCornerRadius: CGFloat = AppStyles.General.CornerRadius.bar
static let rowContentSpacing: CGFloat = 3
static let notificationRowUnreadDotSize: CGFloat = 6
static let notificationRowTitleSize: CGFloat = AppStyles.General.Typography.textBase
static let notificationRowSourceSize: CGFloat = AppStyles.General.Typography.textSm
static let notificationRowDetailSize: CGFloat = AppStyles.General.Typography.textSm
static let notificationRowTimestampSize: CGFloat = AppStyles.General.Typography.textSm
```

Add badge tokens under a shared component namespace, not under PaneInbox:

```swift
enum NotificationBadge {
    static let fontSize: CGFloat = AppStyles.Components.PaneInbox.unreadBadgeFontSize
    static let horizontalPadding: CGFloat = AppStyles.Components.PaneInbox.unreadBadgeHorizontalPadding
    static let verticalPadding: CGFloat = AppStyles.Components.PaneInbox.unreadBadgeVerticalPadding
    static let offset: CGFloat = AppStyles.Components.PaneInbox.unreadBadgeOffset
}
```

Do not add behavioral limits here.

- [x] **Step 2: Create stateless `SidebarRowShell`**

Create `SidebarRowShell.swift`:

```swift
import SwiftUI

struct SidebarRowShell<Content: View>: View {
    let isSelected: Bool
    let isFlashing: Bool
    let isHovering: Bool
    let content: Content

    init(
        isSelected: Bool = false,
        isFlashing: Bool = false,
        isHovering: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isFlashing = isFlashing
        self.isHovering = isHovering
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, AppStyles.Shell.Sidebar.rowVerticalInset)
            .padding(.horizontal, AppStyles.Shell.Sidebar.rowHorizontalInset)
            .background(rowBackground)
            .contentShape(Rectangle())
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

Feature row wrappers own `@State private var isHovering` and pass the value in.

- [x] **Step 3: Create `SidebarSectionHeader` with explicit EmptyView overload**

Create `SidebarSectionHeader.swift`:

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
        @ViewBuilder trailingContent: () -> TrailingContent
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

extension SidebarSectionHeader where TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            isExpanded: isExpanded,
            onToggle: onToggle
        ) {
            EmptyView()
        }
    }
}
```

- [x] **Step 4: Create `UnreadCountBadge`**

Create `UnreadCountBadge.swift`:

```swift
import SwiftUI

struct UnreadCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(
                size: AppStyles.Components.NotificationBadge.fontSize,
                weight: .semibold
            ))
            .padding(.horizontal, AppStyles.Components.NotificationBadge.horizontalPadding)
            .padding(.vertical, AppStyles.Components.NotificationBadge.verticalPadding)
            .background(Capsule().fill(.red))
            .foregroundStyle(.white)
            .fixedSize()
    }
}
```

This component is intentionally visual-only. PaneInbox and global inbox decide the text.

- [x] **Step 5: Replace inbox group header**

Update `InboxNotificationGroupHeader` to wrap the shared header:

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

- [x] **Step 6: Replace RepoExplorer group header only if output stays equivalent**

In `RepoExplorerGroupHeader.swift`, wrap the existing resolved group header content with `SidebarSectionHeader`. Preserve:

- chevron direction
- title text
- organization subtitle if present
- tap target
- expanded/collapsed callback

If the current header has RepoExplorer-specific layout that cannot be represented by `SidebarSectionHeader` without adding feature-specific parameters, stop and leave RepoExplorer unchanged; the inbox header is still covered by the shared primitive and this becomes a follow-up.

- [x] **Step 7: Add compile-oriented shared tests**

Create `SidebarSectionHeaderTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarSectionHeader")
struct SidebarSectionHeaderTests {
    @Test("empty trailing initializer builds")
    func emptyTrailingInitializerBuilds() {
        let header = SidebarSectionHeader(
            title: "askluna",
            isExpanded: true,
            onToggle: {}
        )

        #expect(String(describing: type(of: header)).contains("SidebarSectionHeader"))
    }
}
```

Create `UnreadCountBadgeTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("UnreadCountBadge")
struct UnreadCountBadgeTests {
    @Test("badge builds with count text")
    func badgeBuildsWithCountText() {
        let badge = UnreadCountBadge(text: "1")

        #expect(String(describing: type(of: badge)).contains("UnreadCountBadge"))
    }
}
```

- [x] **Step 8: Run build and shared tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "SidebarSectionHeaderTests|UnreadCountBadgeTests"
SWIFT_BUILD_DIR="$BUILD_PATH" mise run build
```

Expected: PASS.

- [x] **Step 9: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SidebarRowShell.swift \
  Sources/AgentStudio/SharedComponents/SidebarSectionHeader.swift \
  Sources/AgentStudio/SharedComponents/UnreadCountBadge.swift \
  Sources/AgentStudio/Infrastructure/AppStyles.swift \
  Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift \
  Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift \
  Tests/AgentStudioTests/SharedComponents/SidebarSectionHeaderTests.swift \
  Tests/AgentStudioTests/SharedComponents/UnreadCountBadgeTests.swift
git commit -m $'feat: add shared sidebar chrome primitives\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 5: Redesign Inbox Rows And Sidebar Chrome

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- Modify: `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Modify: `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`
- Modify: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxCommandsTests.swift`

- [x] **Step 1: Update `InboxRow` API**

Change `InboxRow` to accept a row context:

```swift
struct InboxRow: View {
    let notification: InboxNotification
    let now: Date
    let rowContext: InboxNotificationSourceDisplay.RowContext

    private var display: InboxNotificationSourceDisplay {
        InboxNotificationSourceDisplay(notification: notification, rowContext: rowContext)
    }
}
```

Render the row in this order:

1. Title + relative age.
2. Source line: repo/worktree/branch or runtime fallback.
3. Placement line when it adds information.
4. Body snippet when present.

Use current `relativeTime`. Do not render `unknown source`.

- [x] **Step 2: Replace source rendering in `InboxRow`**

Inside `body`, use:

```swift
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

    if let body = notification.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(body)
            .font(.system(size: AppStyles.Shell.Sidebar.notificationRowDetailSize))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}
```

Keep or update the existing icon helpers; do not add new feature-specific colors to `SharedComponents`.

- [x] **Step 3: Wrap sidebar rows with hover owned by feature wrapper**

In `InboxSidebarNotificationRow`, keep hover state feature-local:

```swift
@State private var isHovering = false
```

Wrap:

```swift
SidebarRowShell(
    isFlashing: isFlashing,
    isHovering: isHovering
) {
    InboxRow(
        notification: notification,
        now: now,
        rowContext: .globalInbox
    )
}
.onHover { isHovering = $0 }
```

Keep the existing activation, focus, and keyboard modifiers on the shell.

- [x] **Step 4: Wrap PaneInbox rows with selected state**

In `PaneInboxNotificationPopover`, replace custom `RoundedRectangle` row backgrounds with:

```swift
SidebarRowShell(
    isSelected: selectedNotificationId == notification.id
) {
    InboxRow(
        notification: notification,
        now: Date(),
        rowContext: .paneInbox(parentPaneId: parentPaneId)
    )
}
```

Do not call it DrawerInbox. The user-facing concept is PaneInbox.

- [x] **Step 5: Use shared badge for PaneInbox drawer bell**

In `DrawerIconBar`, replace the inline badge text/capsule overlay with:

```swift
UnreadCountBadge(text: inboxUnreadBadge.text)
    .offset(
        x: AppStyles.Components.NotificationBadge.offset,
        y: -AppStyles.Components.NotificationBadge.offset
    )
```

Keep the same `.overlay(alignment: .topTrailing)` anchor. This preserves the visual behavior from PaneInbox while moving the drawing into the shared component.

- [x] **Step 6: Replace global sidebar inbox dot with matching count badge**

In `MainWindowController`, replace the fixed-position `inboxToolbarBellDot` with a hosted SwiftUI badge:

```swift
private var inboxToolbarBadgeHostingView: NSHostingView<UnreadCountBadge>?
```

Replace `installInboxUnreadDot(on:)` with:

```swift
private func installInboxUnreadBadge(on button: NSButton) {
    let badge = NSHostingView(rootView: UnreadCountBadge(text: "1"))
    badge.identifier = NSUserInterfaceItemIdentifier("inboxToolbarUnreadBadge")
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.isHidden = true
    badge.setContentHuggingPriority(.required, for: .horizontal)
    badge.setContentHuggingPriority(.required, for: .vertical)
    button.addSubview(badge)
    NSLayoutConstraint.activate([
        badge.topAnchor.constraint(
            equalTo: button.topAnchor,
            constant: -AppStyles.Components.NotificationBadge.offset
        ),
        badge.trailingAnchor.constraint(
            equalTo: button.trailingAnchor,
            constant: AppStyles.Components.NotificationBadge.offset
        ),
    ])
    inboxToolbarBadgeHostingView = badge
    updateInboxUnreadBadge()
    observeInboxUnreadCount()
}
```

Replace `updateInboxUnreadDot()` with:

```swift
private func updateInboxUnreadBadge() {
    let unreadCount = inboxAtom?.globalUnreadCount ?? 0
    guard unreadCount > 0 else {
        inboxToolbarBadgeHostingView?.isHidden = true
        return
    }
    inboxToolbarBadgeHostingView?.rootView = UnreadCountBadge(
        text: "\(unreadCount)"
    )
    inboxToolbarBadgeHostingView?.isHidden = false
}
```

Update call sites from `installInboxUnreadDot(on:)` / `updateInboxUnreadDot()` to the badge names. The global sidebar bell should now look like Image #2: a red count badge pinned to the bell's top-trailing corner, not a small dot floating over the icon.

The global toolbar badge is intentionally uncapped. It mirrors the real global unread count. PaneInbox uses its own capped badge text (`25+`) because that surface is a compact per-pane affordance with a visible retention limit.

- [x] **Step 7: Match RepoExplorer sidebar chrome**

In the inbox root container, match RepoExplorer's sidebar base:

```swift
.frame(minWidth: 200)
.background(Color(nsColor: .windowBackgroundColor))
```

If RepoExplorer uses an AppStyles token for background by execution time, use the token instead of literal `windowBackgroundColor`.

- [x] **Step 8: Replace active filter UUID labels**

In `InboxSidebarHeader.activeFilterLabel`, remove UUID-prefix fallbacks:

```swift
private var activeFilterLabel: String? {
    guard let filter else { return nil }
    return notifications
        .lazy
        .compactMap { InboxNotificationSourceDisplay(notification: $0).filterLabel(for: filter) }
        .first ?? fallbackFilterLabel(for: filter)
}

private func fallbackFilterLabel(for filter: InboxFilter) -> String {
    switch filter {
    case .repo:
        return "Filtered repo"
    case .worktree:
        return "Filtered worktree"
    }
}
```

If the header does not currently receive notifications, pass the current filtered/unfiltered notification array into it. Do not store labels in Core atoms.

- [x] **Step 9: Clarify sort and grouping buttons**

Use clear icons and help:

```swift
Image(systemName: sort == .newestFirst ? "arrow.down" : "arrow.up")
    .help(sort == .newestFirst ? "Newest notifications first" : "Oldest notifications first")
```

For grouping:

```swift
Image(systemName: "line.3.horizontal.decrease.circle")
    .help("Group notifications")
```

- [x] **Step 10: Add view/model regression tests**

Add tests that assert:

- `PaneInboxNotificationPopover` uses full keyboard item count and row context does not show the parent pane redundantly for parent-scoped rows.
- The active filter label for a repo/worktree filter never contains the first eight UUID characters.
- Sidebar group labels with `byTab` never contain a UUID prefix.
- The global sidebar toolbar badge text is uncapped and tracks the real global unread count.
- The global sidebar toolbar no longer creates a view identified as `inboxToolbarBellDot`.

Example assertion for filter labels:

```swift
#expect(label.contains(repoId.uuidString.prefix(8)) == false)
#expect(label == "askluna")
```

In `MainWindowControllerInboxToolbarButtonTests`, replace the red-dot test with:

```swift
@Test("bell unread badge tracks global unread count")
func bellUnreadBadgeTracksUnreadCount() async {
    let inboxAtom = InboxNotificationAtom()
    await withMainWindowControllerHarness(inboxAtom: inboxAtom) { harness in
        let badge = findDescendant(
            in: harness.window,
            identifier: "inboxToolbarUnreadBadge"
        )
        let oldDot = findDescendant(
            in: harness.window,
            identifier: "inboxToolbarBellDot"
        )

        #expect(badge != nil)
        #expect(oldDot == nil)
        #expect(badge?.isHidden == true)

        inboxAtom.append(makeUnreadNotification())

        await eventually("inbox bell badge should become visible") {
            badge?.isHidden == false
        }
    }
}

@Test("bell unread badge text uses uncapped global unread count")
func bellUnreadBadgeTextUsesUncappedGlobalUnreadCount() async throws {
    let inboxAtom = InboxNotificationAtom()
    try await withMainWindowControllerHarness(inboxAtom: inboxAtom) { harness in
        let badge = try #require(
            findDescendant(
                in: harness.window,
                identifier: "inboxToolbarUnreadBadge"
            ) as? NSHostingView<UnreadCountBadge>
        )

        for _ in 0..<26 {
            inboxAtom.append(makeUnreadNotification())
        }

        await eventually("inbox bell badge should show uncapped count") {
            badge.rootView.text == "26"
        }
    }
}
```

- [x] **Step 11: Run focused tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "PaneInboxNotificationPopoverTests|InboxNotificationSidebarViewTests|InboxNotificationListModelTests|MainWindowControllerInboxToolbarButtonTests"
```

Expected: PASS.

- [x] **Step 12: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift \
  Sources/AgentStudio/App/Windows/MainWindowController.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift \
  Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift
git commit -m $'feat: redesign inbox rows around source context\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 6: Clear Notification Commands And Buttons

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationCommands.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
- Modify: `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxCommandsTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [x] **Step 1: Add command identities**

In `AppCommand.swift`, add the commands near the existing inbox commands:

```swift
case clearInboxNotifications
case clearPaneInboxNotifications
```

In `AppCommand+Catalog.swift`, add definitions:

```swift
case .clearInboxNotifications:
    return CommandSpec(
        command: self,
        label: "Clear Inbox Notifications",
        icon: .system(.trash),
        helpText: "Clear all notification history from the sidebar inbox",
        commandBarGroupName: "Inbox",
        commandBarGroupPriority: CommandBarGroupPriority.miscellaneous
    )
case .clearPaneInboxNotifications:
    return CommandSpec(
        command: self,
        label: "Clear Pane Inbox Notifications",
        icon: .system(.trash),
        helpText: "Clear notifications for the active pane and its drawer children",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane
    )
```

Do not assign shortcuts in this task. These are command-backed button and command-bar actions first; shortcut allocation can happen after the UX settles.

- [x] **Step 2: Add command catalog tests**

In `AppCommandTests`, extend the inbox command coverage:

```swift
@Test("notification clear commands have command specs")
func notificationClearCommandsHaveCommandSpecs() {
    let globalClear = CommandDispatcher.shared.definition(for: .clearInboxNotifications)
    let paneClear = CommandDispatcher.shared.definition(for: .clearPaneInboxNotifications)

    #expect(globalClear.label == "Clear Inbox Notifications")
    #expect(globalClear.shortcut == nil)
    #expect(globalClear.icon == .system(.trash))
    #expect(paneClear.label == "Clear Pane Inbox Notifications")
    #expect(paneClear.appliesTo == [.pane])
    #expect(paneClear.visibleWhen == [.hasActivePane])
}
```

- [x] **Step 3: Route global clear through the existing inbox command seam**

In `InboxNotificationCommands.Actions`, keep the existing `clearAll` callback. In `CommandBarDataSource+Inbox.swift`, use the command spec for the clear-all row instead of local strings:

```swift
let clearInboxSpec = AppCommand.clearInboxNotifications.definition
items.append(
    CommandBarItem(
        id: "inbox.clearAll",
        title: clearInboxSpec.label,
        icon: clearInboxSpec.icon,
        group: Group.inboxCommands,
        groupPriority: Priority.commands,
        keywords: ["inbox", "notification", "clear", "delete"],
        action: .dispatch(.clearInboxNotifications),
        command: .clearInboxNotifications
    )
)
```

Keep `inbox.clearReadHistory` as a command-bar scoped utility. The command-bar row and visible sidebar button both dispatch `clearInboxNotifications`; `AppDelegate` handles that command through `InboxNotificationCommands.actions.clearAll` so the UI surfaces do not bypass the command seam.

- [x] **Step 4: Add PaneInbox clear execution seam**

In `PaneInboxPresentation`, add:

```swift
let clearNotifications: @MainActor (_ parentPaneId: UUID, _ paneIds: [UUID]) -> Void
```

In `MainSplitViewController.makePaneInboxPresentation()`, wire it to the atom:

```swift
clearNotifications: { parentPaneId, paneIds in
    _ = parentPaneId
    for paneId in paneIds {
        inbox.markRead(paneId: paneId)
        inbox.dismissFromPaneInbox(paneId: paneId)
    }
}
```

The explicit parent id remains in the signature so future tracing/policy can distinguish "clear active parent scope" from arbitrary pane-id mutation.

- [x] **Step 5: Execute PaneInbox clear from `PaneTabViewController`**

Extend `handlePaneInboxCommand(_:)`:

```swift
switch command {
case .showPaneInboxNotifications:
    paneInboxPresentation.toggle(parentPaneId: target.parentPaneId, paneIds: target.paneIds)
    return true
case .clearPaneInboxNotifications:
    paneInboxPresentation.clearNotifications(target.parentPaneId, target.paneIds)
    return true
default:
    return false
}
```

Use `activePaneInboxTarget()` for active-pane commands and the shared `paneInboxTarget(anchorPaneId:)` helper for targeted commands dispatched by the PaneInbox popover. Both paths must resolve the same parent + drawer-child scope.

- [x] **Step 6: Add visible clear button to global inbox sidebar**

In `InboxSidebarHeader`, add a clear button near sort/group controls:

```swift
let clearDefinition = AppCommand.clearInboxNotifications.definition
Button(action: actions.onClearAll) {
    CommandIconView(icon: clearDefinition.icon)
}
.buttonStyle(.plain)
.help(clearDefinition.controlToolTip)
```

If `CommandIconView` is not available in this slice, use the existing local command-icon rendering helper already used by sidebar buttons. Do not hard-code `"Clear"` or `"trash"` outside the command definition.

Add `onClearAll: @MainActor @Sendable () -> Void` to `InboxSidebarActions`, and wire it in `InboxNotificationSidebarView` to dispatch `AppCommand.clearInboxNotifications`. AppDelegate handles that command through `InboxNotificationCommands.actions.clearAll` so the visible button, command bar, and shell route share the same command seam.

- [x] **Step 7: Add visible clear button to PaneInbox popover**

In `PaneInboxNotificationPopover.headerControls`, add a clear button before the close separator. This plan explicitly does not ship the later Unread/All toggle, so no filter control should appear in PaneInbox:

```swift
let clearDefinition = AppCommand.clearPaneInboxNotifications.definition
Button {
    dispatcher.dispatch(.clearPaneInboxNotifications, target: parentPaneId, targetType: .pane)
} label: {
    CommandIconView(icon: clearDefinition.icon)
}
.buttonStyle(.plain)
.help(clearDefinition.controlToolTip)
```

The button clears the current PaneInbox scope: mark matching rows read globally and dismiss them from PaneInbox. It must not delete unrelated global inbox history.

- [x] **Step 8: Add clear behavior tests**

In `PaneTabViewControllerCommandTests`, add:

```swift
@Test("clearPaneInboxNotifications clears active parent pane scope")
func clearPaneInboxNotificationsClearsActiveParentPaneScope() async throws {
    let harness = await makePaneTabHarness()
    let parentPaneId = try #require(harness.activePaneId)
    let drawerPane = try #require(harness.store.paneAtom.addDrawerPane(to: parentPaneId, parentFallbackCWD: nil))
    let otherPaneId = UUID()
    harness.inboxAtom.append(makeUnreadPaneNotification(paneId: parentPaneId))
    harness.inboxAtom.append(makeUnreadPaneNotification(paneId: drawerPane.id))
    harness.inboxAtom.append(makeUnreadPaneNotification(paneId: otherPaneId))

    harness.controller.execute(.clearPaneInboxNotifications)

    #expect(harness.inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [parentPaneId, drawerPane.id]) == 0)
    #expect(harness.inboxAtom.unreadCount(forPaneId: otherPaneId) == 1)
}
```

Adapt helper names to the existing harness. The assertions are the contract: active parent + drawer children clear; unrelated panes remain.

In `InboxNotificationSidebarViewTests`, add a test that the clear button invokes `clearAll` and empties `InboxNotificationAtom`.

In `PaneInboxNotificationPopoverTests`, add a test that the clear button action clears only the provided `paneIds`.

- [x] **Step 9: Run focused tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "AppCommandTests|CommandBarInboxCommandsTests|PaneTabViewControllerCommandTests|InboxNotificationSidebarViewTests|PaneInboxNotificationPopoverTests"
```

Expected: PASS.

- [x] **Step 10: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppCommand.swift \
  Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift \
  Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift \
  Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationCommands.swift \
  Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift \
  Sources/AgentStudio/App/Windows/MainSplitViewController.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift \
  Tests/AgentStudioTests/App/AppCommandTests.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxCommandsTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift
git commit -m $'feat: add command-backed inbox clear controls\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 7: PaneInbox Observed-Pane Clear Policy

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Models/PaneInboxAutoClearPolicy.swift`
- Create: `Tests/AgentStudioTests/Features/InboxNotification/Models/PaneInboxAutoClearPolicyTests.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/State/MainActor/Atoms/TerminalActivityAtom.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/State/TerminalActivityAtomTests.swift`

- [x] **Step 1: Pin terminal bottom state in `TerminalActivityAtom`**

Extend `TerminalActivitySnapshot` with the last terminal scrollbar observation:

```swift
var scrollbarState: ScrollbarState?

var isPinnedToBottom: Bool {
    scrollbarState?.isPinnedToBottom == true
}
```

When consuming `.terminal(.scrollbarChanged(let state))`, store `state` before updating output-burst state.

Do not use the view-local `TerminalSurfaceScrollView.isEffectivelyPinnedToBottom` in the first pass. The inbox policy needs a model-level signal. If the sticky-bottom buffer later proves necessary for product feel, promote that as a typed runtime/UI fact in a separate pass instead of reaching into the view layer.

- [x] **Step 2: Add an auto-clear policy type**

Create `PaneInboxAutoClearPolicy`:

```swift
enum PaneInboxAutoClearDecision: Sendable, Equatable {
    case clear
    case keep(reason: String)
}

struct PaneInboxAutoClearPolicy: Sendable {
    func decision(
        notification: InboxNotification,
        isSourcePaneAttended: Bool,
        isSourcePanePinnedToBottom: Bool
    ) -> PaneInboxAutoClearDecision {
        guard isSourcePaneAttended else { return .keep(reason: "source_pane_unattended") }
        guard isSourcePanePinnedToBottom else { return .keep(reason: "source_pane_not_at_bottom") }
        guard isAutoClearable(notification.kind) else { return .keep(reason: "requires_user_action") }
        return .clear
    }

    private func isAutoClearable(_ kind: InboxNotificationKind) -> Bool {
        switch kind {
        case .agentDesktopNotification, .bellRang, .commandFinished, .agentRpc:
            return true
        case .terminalSecureInputRequested,
             .terminalProgressError,
             .terminalRendererUnhealthy,
             .persistenceRecovery,
             .approvalRequested,
             .securityEvent:
            return false
        }
    }
}
```

If `InboxNotificationKind.unseenActivity` exists by implementation time, it must be auto-clearable. Derived unseen activity is the primary reason this policy exists.

- [x] **Step 3: Clear auto-clearable PaneInbox rows when a pane becomes observed**

In `InboxNotificationRouter`, inject a narrow `isPanePinnedToBottom` closure so the inbox feature does not depend directly on the terminal feature atom. The router also keeps same-stream scrollbar state so a `scrollbarChanged(isPinnedToBottom: true)` event immediately followed by a passive notification is handled in order.

```swift
let isObserved =
    paneId == attendedPane.attendedPaneId
    && (sameStreamPinnedState[paneId] ?? isPanePinnedToBottom(paneId))
```

On focus gained and on scrollbar changes for the attended pane:

1. Find notifications whose `notification.paneId == paneId`.
2. Apply `PaneInboxAutoClearPolicy`.
3. For `.clear`, call `markRead(id:)` and `dismissFromPaneInbox(id:)`.
4. Emit `inbox.observedPaneCleared` with:
   - `agentstudio.pane.id`
   - `agentstudio.inbox.cleared_count`
   - `agentstudio.inbox.keep_count`
   - `agentstudio.inbox.reason` when nothing clears

This must happen in the inbox router or a feature-owned helper, not in `InboxNotificationAtom`. The atom stores and mutates; it does not decide product policy.

Because `markRead(id:)` updates the canonical read flag, observed-pane clearing also clears the global unread badge. Do not add a separate PaneInbox-only read state.

The `.terminal(.scrollbarChanged)` classifier must keep ignoring scrollbar callbacks for notification creation, but it must not return before running the observed-pane clear check. The intended flow is:

```swift
case .terminal(.scrollbarChanged):
    clearObservedPaneInboxRowsIfNeeded(paneId: envelope.paneId.uuid)
    return .ignore(reason: "activity_only_scrollbar")
```

This side effect is required for the common stuck-badge path: the pane is already focused while scrolled up, then the user scrolls back to bottom.

- [x] **Step 4: Preserve user-action-required events even when observed**

Current `classifySecureInput(_:paneId:)` suppresses secure-input requests when the source pane is attended. Remove that attended-pane suppression for secure input.

Secure input is user-action-required under the locked heuristics. If it fires while the source pane is attended and pinned to bottom, it should still append an unread row and light both unread affordances. The observed-pane auto-clear policy must return `.keep(reason: "requires_user_action")`.

- [x] **Step 5: Do not clear drawer-child rows from parent focus alone**

PaneInbox scope includes the parent pane plus drawer children for visibility. Observation still belongs to the source pane.

Rules:

- Parent pane attended + parent pane pinned to bottom clears parent-source auto-clearable rows.
- Parent pane attended does not clear drawer-child rows unless that drawer child pane itself becomes the attended/source pane and is pinned to bottom.
- Drawer child notification activation still focuses the drawer child and then clears the row through the existing activation path.

- [x] **Step 6: Add tests for the exact bug**

Add focused tests:

- `focusedPaneAtBottomClearsAutoClearablePaneInboxBadge`
  - Create an unread `.agentDesktopNotification` or `.commandFinished` row for a pane.
  - Emit/record scrollbar state with `bottom == total`.
  - Mark that pane attended.
  - Assert `visiblePaneInboxUnreadCount(forPaneIds: [paneId]) == 0`.
  - Assert notification is read and dismissed from PaneInbox.

- `focusedPaneScrolledUpKeepsPaneInboxBadge`
  - Same setup with `bottom < total`.
  - Assert count remains 1.

- `attendedPaneScrollingBackToBottomClearsAutoClearablePaneInboxBadge`
  - Create an unread auto-clearable row for an attended pane.
  - First emit scrollbar state with `bottom < total`; assert count remains 1.
  - Then emit scrollbar state with `bottom == total`; assert count becomes 0.
  - This pins the side-effect-only `.scrollbarChanged` reevaluation path.

- `unattendedPaneAtBottomKeepsPaneInboxBadge`
  - Same setup with bottom true but attended pane different or nil.
  - Assert count remains 1.

- `observedPaneDoesNotAutoClearActionOrSecurityRows`
  - Use `.approvalRequested` or `.securityEvent`.
  - Assert count remains 1 even when focused and at bottom.

- `observedSecureInputStillCreatesUnreadNotification`
  - Source pane is attended and pinned to bottom before `.terminal(.secureInputChanged(true))`.
  - Assert one `.terminalSecureInputRequested` row exists.
  - Assert row is unread and not dismissed from PaneInbox.
  - Assert `globalUnreadCount == 1`.
  - Assert `visiblePaneInboxUnreadCount(forPaneIds: [paneId]) == 1`.

- `parentFocusDoesNotClearDrawerChildPaneInboxBadge`
  - Parent and drawer child both in the PaneInbox scope.
  - Notification source is drawer child.
  - Parent is attended and at bottom.
  - Assert parent PaneInbox still shows the child row.

- [x] **Step 7: Add regression tests for event-time observed events**

If a terminal event arrives while its source pane is already attended and pinned to bottom:

- Auto-clearable pane events must not light the PaneInbox badge or global unread badge.
- Append the history row as `isRead = true` and `isDismissedFromPaneInbox = true`.
- Do not suppress the history row; the row is still useful evidence that the event happened.
- User-action-required events should still light the badge.

Add tests:

- `observedAutoClearableEventAppendsReadDismissedHistoryRow`
  - Source pane is attended and pinned to bottom before the event arrives.
  - Event is `.desktopNotificationRequested`, `.bellRang`, or `.commandFinished`.
  - Assert one row exists.
  - Assert `isRead == true`.
  - Assert `isDismissedFromPaneInbox == true`.
  - Assert `globalUnreadCount == 0`.
  - Assert `visiblePaneInboxUnreadCount(forPaneIds: [paneId]) == 0`.

- `observedUserActionRequiredEventStillLightsUnreadBadges`
  - Source pane is attended and pinned to bottom before the event arrives.
  - Event is approval/security/progress-error style, or secure input.
  - Assert row exists unread and visible in PaneInbox.

- [x] **Step 8: Run focused tests**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
swift test --build-path "$BUILD_PATH" --filter "PaneInboxAutoClearPolicyTests|InboxNotificationRouterTests|TerminalActivityAtomTests"
```

Expected: PASS.

- [x] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Models/PaneInboxAutoClearPolicy.swift \
  Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift \
  Sources/AgentStudio/Features/Terminal/State/MainActor/Atoms/TerminalActivityAtom.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Models/PaneInboxAutoClearPolicyTests.swift \
  Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift \
  Tests/AgentStudioTests/Features/Terminal/State/TerminalActivityAtomTests.swift
git commit -m $'fix: clear pane inbox badge for observed terminal activity\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 8: Visual Smoke Data And Screenshots

**Files:**
- Create: `docs/wip/debugging/2026-05-07-notification-inbox-sidebar-redesign-smoke.md`

- [x] **Step 1: Build**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
SWIFT_BUILD_DIR="$BUILD_PATH" mise run build
```

Expected: PASS.

- [x] **Step 2: Launch debug build by PID**

```bash
BUILD_PATH="${SWIFT_BUILD_DIR:-.build-agent-$$}"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
echo "$APP_PID"
```

Do not use `.build/debug/AgentStudio` unless the build command really produced that directory in this same shell.

- [x] **Step 3: Seed or collect representative notifications**

Create or manually trigger at least:

- command finished from a main pane
- agent waiting/input notification from a main pane
- notification from a drawer child
- notification with repo/worktree/branch
- notification with missing repo/worktree but known runtime
- long body text that must truncate

If no deterministic seed helper exists, use the manual smoke workflow and record that in the note.

- [x] **Step 4: Capture with Peekaboo**

```bash
peekaboo see --app "PID:$APP_PID" --json > /tmp/agentstudio-inbox-redesign-sidebar.json
```

Open PaneInbox for a parent pane that has drawer-child notifications, then capture:

```bash
peekaboo see --app "PID:$APP_PID" --json > /tmp/agentstudio-inbox-redesign-pane-inbox.json
```

- [x] **Step 5: Write smoke note**

Create `docs/wip/debugging/2026-05-07-notification-inbox-sidebar-redesign-smoke.md`:

```markdown
# 2026-05-07 Notification Inbox Sidebar Redesign Smoke

## Result

- RepoExplorer background and Inbox background match:
- Inbox row source line shows repo/worktree/branch:
- Inbox row placement line shows tab/pane/drawer context:
- PaneInbox hides redundant parent placement and shows drawer context:
- No row displays `unknown source`:
- Command duration appears human-scale:
- Sort icon no longer looks like download:
- Group labels avoid UUID prefixes:
- Active filter chip avoids UUID prefixes:
- Collapsed/expanded unread affordance remains visible:
- Global sidebar inbox bell badge matches PaneInbox badge placement:
- No loose red dot appears over the sidebar inbox bell:
- PaneInbox badge clears after focusing the source pane at terminal bottom:
- PaneInbox badge remains when the source pane is focused but scrolled up:
- Drawer-child rows are not cleared by parent-pane focus alone:

## Evidence

- Sidebar capture: `/tmp/agentstudio-inbox-redesign-sidebar.json`
- PaneInbox capture: `/tmp/agentstudio-inbox-redesign-pane-inbox.json`
```

Fill every result line with `yes`, `no`, or `not exercised`.

- [x] **Step 6: Commit smoke note**

```bash
git add docs/wip/debugging/2026-05-07-notification-inbox-sidebar-redesign-smoke.md
git commit -m $'docs: add notification inbox redesign smoke note\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Task 9: Full Verification

**Files:**
- No source changes unless verification fails.

- [x] **Step 1: Format**

```bash
mise run format
```

Expected: exit 0.

- [x] **Step 2: Build**

```bash
mise run build
```

Expected: exit 0.

- [x] **Step 3: Full tests**

```bash
mise run test
```

Expected: all Swift Testing tests pass.

- [x] **Step 4: Lint**

```bash
mise run lint
```

Expected: exit 0, zero swiftlint/swift-format/boundary errors.

- [x] **Step 5: Commit verification fixes only if needed**

```bash
git status --short
```

If formatting or verification changed files:

```bash
git add Sources Tests docs
git commit -m $'chore: finalize notification inbox sidebar redesign\n\nCo-authored-by: Codex <noreply@openai.com>'
```

---

## Out Of Scope / Follow-Up

- Unread / All toggle for global inbox and PaneInbox.
- Full unseen-activity promotion from derived terminal activity facts; this plan only pins how PaneInbox clears existing auto-clearable rows once their source pane is observed.
- Raw terminal-output parsing, file links, diagnostics, and structured agent updates.
- Replacing the inbox grouping model with a fully nested outline if simple sections still feel too flat after this redesign.
- Accessibility-specific keyboard and VoiceOver pass.
- RepoExplorer worktree row extraction into `SidebarRowShell` if it requires behavior changes beyond visual shell reuse.

## Self-Review

### Spec Coverage

- Source context denormalization: Task 1.
- Old inbox persistence compatibility: Task 1.
- Command duration correctness: Task 2.
- Row source, placement, group, filter labels: Task 3.
- Shared components and AppStyles/AppPolicies discipline: Task 4.
- Global inbox and PaneInbox row reuse: Task 5.
- RepoExplorer chrome parity: Tasks 4 and 5.
- Command-backed clear controls for sidebar inbox and PaneInbox: Task 6.
- PaneInbox observed-source clear policy: Task 7.
- PaneInbox/global inbox unread badge visual parity: Tasks 4, 5, and 8.
- Visual verification: Task 8.

### Placeholder Scan

This plan avoids `TBD`, "write tests for the above", and vague edge-case placeholders. Deferred work is named in Out Of Scope with concrete follow-up boundaries.

### Type Consistency

New source context fields are consistently named:

- `tabDisplayLabel`
- `paneDisplayLabel`
- `paneRole`
- `parentPaneId`
- `parentPaneDisplayLabel`
- `drawerOrdinal`
- `runtimeDisplayLabel`

The display type is `InboxNotificationSourceDisplay`. The nested role type is `InboxNotification.PaneSource.PaneRole`. Grouping remains `InboxNotificationGrouping`.

### Review Fixes Applied

- No nonexistent `setAttendedPaneId` usage.
- No nonexistent `.bridge` pane case or `displayTitle` API.
- No failing-test commits.
- No subagent build-dir collision via `.build-agent-$PPID`.
- No `@State` inside `SharedComponents`.
- No `Current Tab` fallback in the display model.
- No UUID-prefix active filter labels.
