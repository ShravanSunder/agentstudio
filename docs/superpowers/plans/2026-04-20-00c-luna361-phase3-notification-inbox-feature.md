# LUNA-361 Phase 3 — Notification Inbox Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the notification inbox feature end-to-end on top of the Phase 1 shell (UIStateAtom composition state + `SidebarSurfaceHost`) and the Phase 2 `KeyboardOwner` plumbing (CommandBar default-scope). At the end of Phase 3: agents and CLI tools can emit notifications that appear in the sidebar Inbox, per-drawer popover, sidebar bell badges, and an in-app log that's searchable / sortable / groupable with full keymap.

**Architecture:** Feature slice at `Features/NotificationInbox/` — self-contained. Two feature atoms (`NotificationInboxAtom` for the log, `NotificationInboxPrefsAtom` for user prefs), one feature store wrapping both, one leaf `NotificationRouter` subscribing to `EventBus<RuntimeEnvelope>`, a `PaneFocusTracker` diffing `WorkspacePaneAtom.activePaneId` transitions, plus SwiftUI views for the sidebar and drawer popover. Bridge feature grows an `inbox.post` RPC method; Core drawer views grow a `TrailingActions` bell slot; CommandBar registers `.inbox`-scoped actions. No composition state lives here — that's on `UIStateAtom` in Core (Phase 1). All paths per `docs/architecture/directory_structure.md` feature-slice self-containment rules.

**Tech Stack:** Swift 6.2 · SwiftUI · Swift Testing · existing `EventBus<RuntimeEnvelope>` · existing `RPCRouter` · `@Observable @MainActor` atoms · `AppPolicies.NotificationInbox.maxRetainedNotifications` (added)

**Depends on:** Phase 1 (composition state, RepoExplorer rename, `SidebarSurfaceHost`, `InboxPlaceholderView`). Phase 2 (`KeyboardOwner`, `KeyboardOwnerDerived`, `.inbox` CommandBar scope registered).

**Blocks:** Nothing — terminal phase.

---

## Spec references

- [`docs/superpowers/specs/2026-04-17-notification-inbox-design.md`](../specs/2026-04-17-notification-inbox-design.md) — entire spec drives this phase
- [`docs/superpowers/specs/2026-04-18-interaction-model-wip.md`](../specs/2026-04-18-interaction-model-wip.md) — sidebarHasFocus contract (§4.3), shortcut resolution
- [`docs/architecture/directory_structure.md`](../../architecture/directory_structure.md) — feature-slice self-containment
- [`docs/architecture/pane_runtime_architecture.md`](../../architecture/pane_runtime_architecture.md) — runtime envelope bus contracts
- [`docs/architecture/pane_runtime_eventbus_design.md`](../../architecture/pane_runtime_eventbus_design.md) — bus subscription pattern

---

## File Structure

```
Features/NotificationInbox/                              [NEW FULL SLICE]
├── Models/
│   ├── Notification.swift                               [NEW]
│   └── NotificationInboxTypes.swift                     [NEW]
├── Components/
│   ├── InboxRow.swift                                   [NEW]
│   ├── InboxGroupHeader.swift                           [NEW]
│   └── InboxEmptyState.swift                            [NEW]
├── Routing/
│   ├── NotificationRouter.swift                         [NEW]
│   └── PaneFocusTracker.swift                           [NEW]
├── State/
│   └── MainActor/
│       ├── Atoms/
│       │   ├── NotificationInboxAtom.swift              [NEW]
│       │   └── NotificationInboxPrefsAtom.swift         [NEW]
│       └── Persistence/
│           └── NotificationInboxStore.swift             [NEW]
└── Views/
    ├── InboxSidebarView.swift                           [NEW]
    ├── DrawerInboxPopover.swift                         [NEW]
    ├── DrawerInboxBellHost.swift                        [NEW]
    └── InboxPlaceholderView.swift                       [DELETE]

Core/Views/Drawer/
├── DrawerOverlay.swift                                  [MOD] + TrailingActions
│                                                               .onOpenInbox,
│                                                               .inboxUnreadCount
└── DrawerIconBar.swift                                  [MOD] render bell
                                                                trailing button

Features/Bridge/Transport/
└── RPCRouter.swift                                      [MOD] register inbox.post

Features/CommandBar/
└── CommandBarDataSource.swift                           [MOD] populate .inbox
                                                                scope actions

Features/RepoExplorer/
└── RepoExplorerWorktreeRow.swift                        [MOD] 🔔 N pill binds
                                                                to NotificationInbox-
                                                                Atom.unreadCount

App/Boot/
└── AppDelegate.swift                                    [MOD] instantiate atoms
                                                                + store + router
                                                                + tracker; inject
                                                                into views

App/Commands/
├── AppCommand.swift                                     [MOD] + .showDrawerInbox
└── AppShortcut.swift                                    [MOD] bind ⌘⇧I

App/Windows/
└── SidebarSurfaceHost.swift                             [MOD] swap Inbox-
                                                                PlaceholderView
                                                                for Inbox-
                                                                SidebarView

Tests — full §13 coverage in Tests/AgentStudioTests/Features/NotificationInbox/
(plus integration in Tests/AgentStudioTests/Integration/)
```

---

## Task order rationale

1. **Data types** (Notification, NotificationKind, Grouping, Sort enums) — no dependencies.
2. **`NotificationInboxAtom`** — the log + queries + mutations.
3. **`NotificationInboxPrefsAtom`** — grouping/sort/bellEnabled.
4. **`NotificationInboxStore`** — persists both atoms.
5. **`PaneFocusTracker`** — diffs focus transitions; emits a stream.
6. **`NotificationRouter`** — subscribes to EventBus, applies §7 routing, writes atom.
7. **Bridge RPC `inbox.post` handler.**
8. **`InboxRow` / `InboxGroupHeader` / `InboxEmptyState` components.**
9. **`InboxSidebarView`** — composes components, declares `InboxFocus`, publishes `sidebarHasFocus`, attaches the `⌥F`/`⌥G`/`⌥S`/arrows/Enter/Space keymap.
10. **`DrawerOverlay.TrailingActions` extension + `DrawerIconBar` bell rendering.**
11. **`DrawerInboxBellHost` + `DrawerInboxPopover`.**
12. **`RepoExplorerWorktreeRow` 🔔 N pill binding.**
13. **CommandBar `.inbox` scope actions populated.**
14. **⌘⇧I composite command + `AppDelegate` dispatch handler.**
15. **`SidebarSurfaceHost` swap + `AppDelegate` boot wiring + `InboxPlaceholderView` deletion.**
16. **Integration tests + Phase 3 verification.**

---

## Task 1: Data types (Notification, NotificationKind, Grouping, Sort)

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Models/Notification.swift`
- Create: `Sources/AgentStudio/Features/NotificationInbox/Models/NotificationInboxTypes.swift`
- Test: `Tests/AgentStudioTests/Features/NotificationInbox/Models/NotificationTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentStudioTests/Features/NotificationInbox/Models/NotificationTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@Suite("Notification model")
struct NotificationTests {

    @Test("Notification roundtrips through JSON")
    func jsonRoundtrip() throws {
        let id = UUID()
        let now = Date()
        let original = Notification(
            id: id,
            timestamp: now,
            kind: .agentDesktopNotification,
            title: "Codex done",
            body: "exit 0 · 4m 12s",
            paneId: UUID(),
            tabId: UUID(),
            repoId: UUID(),
            repoName: "agent-studio",
            worktreeId: UUID(),
            worktreeName: "drawer-improvements",
            branchName: "drawer-improvements",
            isRead: false,
            isDismissedFromDrawer: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Notification.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.kind == original.kind)
        #expect(decoded.repoName == original.repoName)
        #expect(decoded.isRead == original.isRead)
        #expect(decoded.isDismissedFromDrawer == original.isDismissedFromDrawer)
    }

    @Test("NotificationKind enumerates expected cases")
    func kindCases() {
        let _: NotificationKind = .agentDesktopNotification
        let _: NotificationKind = .bellRang
        let _: NotificationKind = .commandFinished
        let _: NotificationKind = .agentRpc
        let _: NotificationKind = .approvalRequested
        let _: NotificationKind = .securityEvent
    }

    @Test("NotificationInboxGrouping enumerates expected cases")
    func groupingCases() {
        let _: NotificationInboxGrouping = .none
        let _: NotificationInboxGrouping = .byRepo
        let _: NotificationInboxGrouping = .byPane
        let _: NotificationInboxGrouping = .byTab
    }

    @Test("NotificationInboxSort enumerates expected cases")
    func sortCases() {
        let _: NotificationInboxSort = .newestFirst
        let _: NotificationInboxSort = .oldestFirst
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test -- --filter NotificationTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `Notification.swift`**

Create `Sources/AgentStudio/Features/NotificationInbox/Models/Notification.swift`:

```swift
import Foundation

/// A single notification entry in the inbox.
///
/// Source context (repo/worktree/tab/pane names and ids) is
/// denormalized at emit time so history renders coherently even
/// if the source pane is later closed. Click-through uses `paneId`
/// and degrades gracefully if the pane is gone (see spec §8.5).
struct Notification: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: NotificationKind
    let title: String
    let body: String?

    // Denormalized source context — frozen at emit time.
    let paneId: UUID?
    let tabId: UUID?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?

    // Dismissal state — see spec §4.2.
    var isRead: Bool
    var isDismissedFromDrawer: Bool
}

/// The kind of notification. Drives routing decisions and display.
/// See spec §7 for the event-to-kind routing contract.
enum NotificationKind: String, Sendable, Codable, Equatable {
    case agentDesktopNotification      // Ghostty OSC 9/777
    case bellRang                      // Ghostty bell
    case commandFinished               // Ghostty command completion, gated
    case agentRpc                      // Bridge RPC inbox.post
    case approvalRequested             // ArtifactEvent.approvalRequested
    case securityEvent                 // Filtered SecurityEvent subset (§7)
}
```

- [ ] **Step 4: Create `NotificationInboxTypes.swift`**

Create `Sources/AgentStudio/Features/NotificationInbox/Models/NotificationInboxTypes.swift`:

```swift
import Foundation

/// How the inbox list is grouped. User preference; persisted via
/// NotificationInboxStore.
enum NotificationInboxGrouping: String, Sendable, Codable, Equatable, CaseIterable {
    case none
    case byRepo
    case byPane
    case byTab
}

/// How the inbox list is sorted. User preference; persisted via
/// NotificationInboxStore.
enum NotificationInboxSort: String, Sendable, Codable, Equatable, CaseIterable {
    case newestFirst
    case oldestFirst
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mise run test -- --filter NotificationTests`
Expected: PASS (4 tests)

- [ ] **Step 6: Lint**

Run: `mise run lint`

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/NotificationInbox/Models/ \
        Tests/AgentStudioTests/Features/NotificationInbox/Models/
git commit -m "feat(notification-inbox): add Notification + support enums

Notification record with denormalized source context,
NotificationKind (the six routed event classifications),
NotificationInboxGrouping (.none/.byRepo/.byPane/.byTab), and
NotificationInboxSort (.newestFirst/.oldestFirst). All feature-
scoped under Features/NotificationInbox/Models/. LUNA-361 Phase 3."
```

---

## Task 2: `NotificationInboxAtom` — the log

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxAtom.swift`
- Test: `Tests/AgentStudioTests/Features/NotificationInbox/State/NotificationInboxAtomTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentStudioTests/Features/NotificationInbox/State/NotificationInboxAtomTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("NotificationInboxAtom")
struct NotificationInboxAtomTests {

    private func makeNotification(
        id: UUID = UUID(),
        paneId: UUID? = nil,
        worktreeId: UUID? = nil,
        tabId: UUID? = nil,
        isRead: Bool = false,
        isDismissedFromDrawer: Bool = false,
        timestamp: Date = Date()
    ) -> Notification {
        Notification(
            id: id,
            timestamp: timestamp,
            kind: .agentDesktopNotification,
            title: "Test",
            body: nil,
            paneId: paneId,
            tabId: tabId,
            repoId: nil,
            repoName: nil,
            worktreeId: worktreeId,
            worktreeName: nil,
            branchName: nil,
            isRead: isRead,
            isDismissedFromDrawer: isDismissedFromDrawer
        )
    }

    @Test("append adds to notifications")
    func appendAdds() {
        let atom = NotificationInboxAtom()
        #expect(atom.notifications.count == 0)
        atom.append(makeNotification())
        #expect(atom.notifications.count == 1)
    }

    @Test("markRead(id:) sets isRead true")
    func markReadById() {
        let atom = NotificationInboxAtom()
        let n = makeNotification()
        atom.append(n)
        #expect(atom.notifications[0].isRead == false)
        atom.markRead(id: n.id)
        #expect(atom.notifications[0].isRead == true)
    }

    @Test("markRead(paneId:) marks all notifications for that pane")
    func markReadByPane() {
        let paneA = UUID()
        let paneB = UUID()
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(paneId: paneA))
        atom.append(makeNotification(paneId: paneA))
        atom.append(makeNotification(paneId: paneB))

        atom.markRead(paneId: paneA)

        #expect(atom.notifications[0].isRead == true)
        #expect(atom.notifications[1].isRead == true)
        #expect(atom.notifications[2].isRead == false)
    }

    @Test("markAllRead sets isRead true on every entry")
    func markAllRead() {
        let atom = NotificationInboxAtom()
        for _ in 0..<5 { atom.append(makeNotification()) }
        atom.markAllRead()
        #expect(atom.notifications.allSatisfy { $0.isRead })
    }

    @Test("dismissFromDrawer(id:) sets flag true")
    func dismissFromDrawerById() {
        let atom = NotificationInboxAtom()
        let n = makeNotification()
        atom.append(n)
        atom.dismissFromDrawer(id: n.id)
        #expect(atom.notifications[0].isDismissedFromDrawer == true)
    }

    @Test("dismissFromDrawer(paneId:) sets flag true for every pane entry")
    func dismissFromDrawerByPane() {
        let paneA = UUID()
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(paneId: paneA))
        atom.append(makeNotification(paneId: paneA))
        atom.dismissFromDrawer(paneId: paneA)
        #expect(atom.notifications.allSatisfy { $0.isDismissedFromDrawer })
    }

    @Test("toggleReadState flips the value")
    func toggleReadState() {
        let atom = NotificationInboxAtom()
        let n = makeNotification()
        atom.append(n)
        atom.toggleReadState(id: n.id)
        #expect(atom.notifications[0].isRead == true)
        atom.toggleReadState(id: n.id)
        #expect(atom.notifications[0].isRead == false)
    }

    @Test("unreadCount(forPaneId:) counts matches")
    func unreadCountForPane() {
        let paneA = UUID()
        let paneB = UUID()
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(paneId: paneA, isRead: false))
        atom.append(makeNotification(paneId: paneA, isRead: true))
        atom.append(makeNotification(paneId: paneB, isRead: false))
        #expect(atom.unreadCount(forPaneId: paneA) == 1)
        #expect(atom.unreadCount(forPaneId: paneB) == 1)
    }

    @Test("unreadCount(forWorktreeId:) counts matches")
    func unreadCountForWorktree() {
        let wtA = UUID()
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(worktreeId: wtA, isRead: false))
        atom.append(makeNotification(worktreeId: wtA, isRead: true))
        atom.append(makeNotification(worktreeId: nil, isRead: false))
        #expect(atom.unreadCount(forWorktreeId: wtA) == 1)
    }

    @Test("unreadCount(forTabId:) counts matches")
    func unreadCountForTab() {
        let tabA = UUID()
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(tabId: tabA, isRead: false))
        atom.append(makeNotification(tabId: tabA, isRead: false))
        #expect(atom.unreadCount(forTabId: tabA) == 2)
    }

    @Test("unreadCount(forDrawerPaneIds:) sums across ids")
    func unreadCountForDrawer() {
        let p1 = UUID()
        let p2 = UUID()
        let p3 = UUID()
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(paneId: p1, isRead: false))
        atom.append(makeNotification(paneId: p2, isRead: false))
        atom.append(makeNotification(paneId: p3, isRead: false))
        #expect(atom.unreadCount(forDrawerPaneIds: [p1, p2]) == 2)
    }

    @Test("globalUnreadCount counts all unread")
    func globalUnread() {
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(isRead: false))
        atom.append(makeNotification(isRead: true))
        atom.append(makeNotification(isRead: false))
        #expect(atom.globalUnreadCount == 2)
    }

    @Test("retention cap: inserting beyond cap evicts oldest")
    func retentionCap() {
        let atom = NotificationInboxAtom()
        let cap = AppPolicies.NotificationInbox.maxRetainedNotifications
        let base = Date(timeIntervalSince1970: 1_000_000)
        // Fill to cap with distinct timestamps
        for i in 0..<cap {
            atom.append(makeNotification(
                timestamp: base.addingTimeInterval(TimeInterval(i))))
        }
        #expect(atom.notifications.count == cap)
        let oldestId = atom.notifications.first?.id
        // One more push
        atom.append(makeNotification(
            timestamp: base.addingTimeInterval(TimeInterval(cap + 1))))
        #expect(atom.notifications.count == cap)
        #expect(atom.notifications.contains(where: { $0.id == oldestId }) == false,
                "oldest entry should be evicted")
    }

    @Test("clearReadHistory removes read entries, keeps unread")
    func clearReadHistory() {
        let atom = NotificationInboxAtom()
        atom.append(makeNotification(isRead: true))
        atom.append(makeNotification(isRead: false))
        atom.append(makeNotification(isRead: true))
        atom.clearReadHistory()
        #expect(atom.notifications.count == 1)
        #expect(atom.notifications[0].isRead == false)
    }

    @Test("clearAll removes everything")
    func clearAll() {
        let atom = NotificationInboxAtom()
        for _ in 0..<3 { atom.append(makeNotification()) }
        atom.clearAll()
        #expect(atom.notifications.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test -- --filter NotificationInboxAtomTests`
Expected: FAIL — atom does not exist.

- [ ] **Step 3: Create `NotificationInboxAtom.swift`**

Create `Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxAtom.swift`:

```swift
import Foundation
import Observation

/// Canonical mutable state for the notification log.
///
/// `@Observable @MainActor`. Reads are `private(set)`; mutations
/// go through methods (valtio pattern). Never touches disk —
/// persistence lives in `NotificationInboxStore`.
///
/// Retention cap is `AppPolicies.NotificationInbox
/// .maxRetainedNotifications`. When append would exceed the cap,
/// the oldest entry by timestamp is evicted.
///
/// See spec §4.3.
@MainActor
@Observable
final class NotificationInboxAtom {

    // MARK: - State

    private(set) var notifications: [Notification] = []

    // MARK: - Derived reads

    func unreadCount(forPaneId paneId: UUID) -> Int {
        notifications.reduce(0) { acc, n in
            (n.paneId == paneId && !n.isRead) ? acc + 1 : acc
        }
    }

    func unreadCount(forWorktreeId worktreeId: UUID) -> Int {
        notifications.reduce(0) { acc, n in
            (n.worktreeId == worktreeId && !n.isRead) ? acc + 1 : acc
        }
    }

    func unreadCount(forTabId tabId: UUID) -> Int {
        notifications.reduce(0) { acc, n in
            (n.tabId == tabId && !n.isRead) ? acc + 1 : acc
        }
    }

    func unreadCount(forDrawerPaneIds paneIds: [UUID]) -> Int {
        let set = Set(paneIds)
        return notifications.reduce(0) { acc, n in
            if let pid = n.paneId, set.contains(pid), !n.isRead {
                return acc + 1
            }
            return acc
        }
    }

    var globalUnreadCount: Int {
        notifications.reduce(0) { acc, n in n.isRead ? acc : acc + 1 }
    }

    // MARK: - Mutations

    func append(_ notification: Notification) {
        notifications.append(notification)
        enforceRetentionCap()
    }

    func markRead(id: UUID) {
        update(id: id) { $0.isRead = true }
    }

    func markRead(paneId: UUID) {
        for index in notifications.indices
        where notifications[index].paneId == paneId {
            notifications[index].isRead = true
        }
    }

    func markAllRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
    }

    func dismissFromDrawer(id: UUID) {
        update(id: id) { $0.isDismissedFromDrawer = true }
    }

    func dismissFromDrawer(paneId: UUID) {
        for index in notifications.indices
        where notifications[index].paneId == paneId {
            notifications[index].isDismissedFromDrawer = true
        }
    }

    func toggleReadState(id: UUID) {
        update(id: id) { $0.isRead.toggle() }
    }

    func clearReadHistory() {
        notifications.removeAll { $0.isRead }
    }

    func clearAll() {
        notifications.removeAll()
    }

    // MARK: - Internal helpers

    private func update(id: UUID, mutate: (inout Notification) -> Void) {
        guard let idx = notifications.firstIndex(where: { $0.id == id })
        else { return }
        mutate(&notifications[idx])
    }

    private func enforceRetentionCap() {
        let cap = AppPolicies.NotificationInbox.maxRetainedNotifications
        guard notifications.count > cap else { return }
        // Evict oldest by timestamp. Typical insertion order is
        // newest-at-end (timestamps monotonically increasing), so
        // this is usually a simple drop-first. Sort defensively.
        notifications.sort { $0.timestamp < $1.timestamp }
        let overflow = notifications.count - cap
        notifications.removeFirst(overflow)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise run test -- --filter NotificationInboxAtomTests`
Expected: PASS (all tests)

- [ ] **Step 5: Lint**

Run: `mise run lint`

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxAtom.swift \
        Tests/AgentStudioTests/Features/NotificationInbox/State/NotificationInboxAtomTests.swift
git commit -m "feat(notification-inbox): add NotificationInboxAtom

@Observable @MainActor log. private(set) reads, method-gated
mutation. Derived unreadCount queries across paneId, worktree-
Id, tabId, and [paneIds] dimensions, plus globalUnreadCount.
Retention cap enforced via AppPolicies.NotificationInbox
.maxRetainedNotifications — oldest-by-timestamp evicted on
overflow. LUNA-361 Phase 3."
```

---

## Task 3: `NotificationInboxPrefsAtom`

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxPrefsAtom.swift`
- Test: `Tests/AgentStudioTests/Features/NotificationInbox/State/NotificationInboxPrefsAtomTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import AgentStudio

@MainActor
@Suite("NotificationInboxPrefsAtom")
struct NotificationInboxPrefsAtomTests {

    @Test("defaults")
    func defaults() {
        let atom = NotificationInboxPrefsAtom()
        #expect(atom.grouping == .none)
        #expect(atom.sort == .newestFirst)
        #expect(atom.bellEnabled == false)
    }

    @Test("setGrouping")
    func setGrouping() {
        let atom = NotificationInboxPrefsAtom()
        atom.setGrouping(.byRepo)
        #expect(atom.grouping == .byRepo)
    }

    @Test("setSort")
    func setSort() {
        let atom = NotificationInboxPrefsAtom()
        atom.setSort(.oldestFirst)
        #expect(atom.sort == .oldestFirst)
    }

    @Test("setBellEnabled")
    func setBellEnabled() {
        let atom = NotificationInboxPrefsAtom()
        atom.setBellEnabled(true)
        #expect(atom.bellEnabled == true)
        atom.setBellEnabled(false)
        #expect(atom.bellEnabled == false)
    }
}
```

- [ ] **Step 2: Implement**

Create `Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxPrefsAtom.swift`:

```swift
import Foundation
import Observation

/// User preferences for the notification inbox. Feature-scoped.
/// Persisted alongside `NotificationInboxAtom` in a single JSON
/// file via `NotificationInboxStore` (WorkspaceStore pattern —
/// one store wrapping multiple atoms that persist together).
@MainActor
@Observable
final class NotificationInboxPrefsAtom {
    private(set) var grouping: NotificationInboxGrouping = .none
    private(set) var sort: NotificationInboxSort = .newestFirst
    private(set) var bellEnabled: Bool = false

    func setGrouping(_ grouping: NotificationInboxGrouping) {
        self.grouping = grouping
    }

    func setSort(_ sort: NotificationInboxSort) {
        self.sort = sort
    }

    func setBellEnabled(_ enabled: Bool) {
        self.bellEnabled = enabled
    }
}
```

- [ ] **Step 3: Run tests, lint, commit**

```bash
mise run test -- --filter NotificationInboxPrefsAtomTests
mise run lint
git add ...
git commit -m "feat(notification-inbox): add NotificationInboxPrefsAtom

Feature-scoped user prefs: grouping, sort, bellEnabled.
Defaults: .none / .newestFirst / false. Persisted via
NotificationInboxStore alongside the log atom. LUNA-361 Phase 3."
```

---

## Task 4: `NotificationInboxStore` (persists both atoms)

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Persistence/NotificationInboxStore.swift`
- Test: `Tests/AgentStudioTests/Features/NotificationInbox/State/NotificationInboxStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("NotificationInboxStore")
struct NotificationInboxStoreTests {

    private func makeTempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notification-inbox.json")
    }

    @Test("roundtrip: save + load returns equal notifications")
    func roundtrip() async throws {
        let url = makeTempURL()
        let atom1 = NotificationInboxAtom()
        let prefs1 = NotificationInboxPrefsAtom()
        let clock = TestClock()
        let store1 = NotificationInboxStore(
            inboxAtom: atom1,
            prefsAtom: prefs1,
            fileURL: url,
            clock: clock
        )
        let note = Notification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Test",
            body: nil,
            paneId: UUID(),
            tabId: nil,
            repoId: nil,
            repoName: nil,
            worktreeId: nil,
            worktreeName: nil,
            branchName: nil,
            isRead: false,
            isDismissedFromDrawer: false
        )
        atom1.append(note)
        prefs1.setGrouping(.byRepo)
        prefs1.setSort(.oldestFirst)
        prefs1.setBellEnabled(true)
        try await store1.save()

        let atom2 = NotificationInboxAtom()
        let prefs2 = NotificationInboxPrefsAtom()
        let store2 = NotificationInboxStore(
            inboxAtom: atom2,
            prefsAtom: prefs2,
            fileURL: url,
            clock: clock
        )
        try store2.load()

        #expect(atom2.notifications.count == 1)
        #expect(atom2.notifications[0].id == note.id)
        #expect(prefs2.grouping == .byRepo)
        #expect(prefs2.sort == .oldestFirst)
        #expect(prefs2.bellEnabled == true)
    }

    @Test("load from missing file uses defaults")
    func loadMissingFileUsesDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID()).json")
        let atom = NotificationInboxAtom()
        let prefs = NotificationInboxPrefsAtom()
        let store = NotificationInboxStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )
        try store.load()  // must not throw
        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .none)
        #expect(prefs.bellEnabled == false)
    }
}
```

- [ ] **Step 2: Implement**

Create `Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Persistence/NotificationInboxStore.swift`:

```swift
import Foundation
import Observation

/// Persistence wrapper over the notification-inbox feature atoms.
/// One store, one JSON file, two atoms — matches WorkspaceStore's
/// "one store wrapping multiple atoms that persist together"
/// pattern.
///
/// Path: `~/.agentstudio/workspaces/<workspaceId>/notification-inbox.json`
/// (canonical workspace bundle — sibling of workspace.state.json,
/// workspace.cache.json, workspace.ui.json).
@MainActor
final class NotificationInboxStore {
    let inboxAtom: NotificationInboxAtom
    let prefsAtom: NotificationInboxPrefsAtom

    private let fileURL: URL
    private let clock: any Clock<Duration>
    private let debounceDuration: Duration
    private var debouncedSaveTask: Task<Void, Never>?

    init(
        inboxAtom: NotificationInboxAtom,
        prefsAtom: NotificationInboxPrefsAtom,
        fileURL: URL,
        clock: any Clock<Duration> = ContinuousClock(),
        debounceDuration: Duration = .milliseconds(500)
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.fileURL = fileURL
        self.clock = clock
        self.debounceDuration = debounceDuration
    }

    // MARK: - Codable payload

    private struct Payload: Codable {
        var schemaVersion: Int = 1
        var notifications: [Notification]
        var prefs: Prefs

        struct Prefs: Codable {
            var grouping: NotificationInboxGrouping
            var sort: NotificationInboxSort
            var bellEnabled: Bool
        }
    }

    // MARK: - Load

    func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return  // missing file → defaults (greenfield policy)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        // Replace the atom's notifications wholesale by re-appending.
        // (NotificationInboxAtom's retention cap enforces size.)
        inboxAtom.clearAll()
        for note in payload.notifications {
            inboxAtom.append(note)
        }
        prefsAtom.setGrouping(payload.prefs.grouping)
        prefsAtom.setSort(payload.prefs.sort)
        prefsAtom.setBellEnabled(payload.prefs.bellEnabled)
    }

    // MARK: - Save

    func save() async throws {
        let payload = Payload(
            schemaVersion: 1,
            notifications: inboxAtom.notifications,
            prefs: .init(
                grouping: prefsAtom.grouping,
                sort: prefsAtom.sort,
                bellEnabled: prefsAtom.bellEnabled
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    /// Debounced save — call on any atom mutation. Coalesces
    /// rapid-fire mutations into a single save after
    /// `debounceDuration`.
    func scheduleDebouncedSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.clock.sleep(for: self.debounceDuration)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            try? await self.save()
        }
    }
}
```

- [ ] **Step 3: Wire the atom observer to trigger scheduleDebouncedSave**

In `AppDelegate` boot wiring (Task 15), you'll subscribe to `inboxAtom` and `prefsAtom` mutations via `Observation.withObservationTracking` and call `store.scheduleDebouncedSave()` on change — matching how `UIStateStore` / `RepoCacheStore` observe their atoms. For Phase 3 scope, add a comment TODO inside the store noting this wiring happens in the boot path.

- [ ] **Step 4: Run tests, lint, commit**

```bash
mise run test -- --filter NotificationInboxStoreTests
mise run lint
git add Sources/AgentStudio/Features/NotificationInbox/State/MainActor/Persistence/ \
        Tests/AgentStudioTests/Features/NotificationInbox/State/NotificationInboxStoreTests.swift
git commit -m "feat(notification-inbox): add NotificationInboxStore

One store wrapping both feature atoms (log + prefs). JSON
persistence to workspace bundle path ~/.agentstudio/workspaces/
<id>/notification-inbox.json. Missing-file load is a no-op
(defaults). Debounced save helper — wired to atom mutations
by AppDelegate boot sequencing. LUNA-361 Phase 3."
```

---

## Task 5: `PaneFocusTracker`

Emits an `AsyncStream<PaneId>` of focus-gained transitions by diffing `WorkspacePaneAtom.activePaneId`. Consumed by `NotificationRouter` to auto-dismiss notifications when the user focuses their source pane.

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Routing/PaneFocusTracker.swift`
- Test: `Tests/AgentStudioTests/Features/NotificationInbox/Routing/PaneFocusTrackerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("PaneFocusTracker")
struct PaneFocusTrackerTests {

    @Test("emits paneId on transition A → B")
    func emitsOnTransition() async {
        let paneAtom = WorkspacePaneAtom()
        let tracker = PaneFocusTracker(paneAtom: paneAtom)

        var collected: [UUID] = []
        let task = Task {
            for await id in tracker.focusGainedStream {
                collected.append(id)
                if collected.count >= 2 { break }
            }
        }

        let paneA = UUID()
        let paneB = UUID()
        paneAtom.setActivePaneId(paneA)  // adjust to real setter
        try? await Task.sleep(for: .milliseconds(10))
        paneAtom.setActivePaneId(paneB)
        try? await Task.sleep(for: .milliseconds(10))

        _ = await task.value
        #expect(collected == [paneA, paneB])
        tracker.stop()
    }

    @Test("does not emit when activePaneId stays the same")
    func noEmitOnNoChange() async {
        let paneAtom = WorkspacePaneAtom()
        let tracker = PaneFocusTracker(paneAtom: paneAtom)

        let paneA = UUID()
        paneAtom.setActivePaneId(paneA)

        var count = 0
        let task = Task {
            for await _ in tracker.focusGainedStream {
                count += 1
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        // Same paneId again — should not emit a second time
        paneAtom.setActivePaneId(paneA)
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        tracker.stop()
        _ = await task.value
        #expect(count == 1, "only initial assignment should emit")
    }
}
```

Adjust `WorkspacePaneAtom` accessor names (`setActivePaneId`) to match the real atom API — grep the codebase.

- [ ] **Step 2: Implement**

Create `Sources/AgentStudio/Features/NotificationInbox/Routing/PaneFocusTracker.swift`:

```swift
import Foundation
import Observation

/// Observes `WorkspacePaneAtom.activePaneId` transitions and
/// emits the gained paneId via an `AsyncStream`.
///
/// `WorkspaceFocusDerived` is snapshot-only — it does not emit
/// transition events. This tracker closes that gap for
/// consumers (primarily `NotificationRouter`) that need to
/// react to "user focused pane X."
///
/// Lifecycle: `start()` is called at boot by the composition
/// root; `stop()` is called at shutdown. The stream continuation
/// is finished on stop.
@MainActor
final class PaneFocusTracker {
    private let paneAtom: WorkspacePaneAtom
    private let continuation: AsyncStream<UUID>.Continuation
    let focusGainedStream: AsyncStream<UUID>

    private var lastActivePaneId: UUID?
    private var observationTask: Task<Void, Never>?

    init(paneAtom: WorkspacePaneAtom) {
        self.paneAtom = paneAtom
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation
        start()
    }

    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            await self?.observeLoop()
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        continuation.finish()
    }

    private func observeLoop() async {
        while !Task.isCancelled {
            let current = withObservationTracking {
                paneAtom.activePaneId  // adjust if the property name differs
            } onChange: { }
            if current != lastActivePaneId, let id = current {
                continuation.yield(id)
            }
            lastActivePaneId = current
            // Yield until the next observation change fires via
            // the onChange handler — in practice the observation
            // library re-runs the body. If the codebase prefers
            // a different pattern (e.g., a callback installed on
            // the atom directly), mirror that.
            try? await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
```

If the existing codebase has a canonical pattern for observation-based streams over `@Observable` atoms, match it — the above is a reasonable default but a cleaner idiom (e.g., a `ValueStream` utility) may already exist. Grep `withObservationTracking` in the codebase before committing to this exact shape.

- [ ] **Step 3: Tests, lint, commit**

```bash
mise run test -- --filter PaneFocusTrackerTests
mise run lint
git add ...
git commit -m "feat(notification-inbox): add PaneFocusTracker

Observes WorkspacePaneAtom.activePaneId transitions and emits
the gained paneId via AsyncStream<UUID>. Closes the gap left
by WorkspaceFocusDerived being snapshot-only. Consumed by
NotificationRouter to auto-dismiss notifications when the user
focuses their source pane. LUNA-361 Phase 3."
```

---

## Task 6: `NotificationRouter`

The leaf bus subscriber. Implements the §7 routing contract: reads `EventBus<RuntimeEnvelope>` events, gates them per the contract, enriches with repo/worktree/branch context, and appends to `NotificationInboxAtom`.

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Routing/NotificationRouter.swift`
- Test: `Tests/AgentStudioTests/Features/NotificationInbox/Routing/NotificationRouterTests.swift`

- [ ] **Step 1: Read the EventBus and RuntimeEnvelope types**

```bash
grep -rn "class EventBus\|struct RuntimeEnvelope\|enum PaneRuntimeEvent" Sources/AgentStudio/Core/RuntimeEventSystem/
```

Confirm the types' public API before writing the router. Key things to identify:
- How to subscribe (`eventBus.subscribe()` or an `AsyncStream` accessor?)
- `RuntimeEnvelope.event` enum cases (`.terminal(.desktopNotificationRequested...)`, etc.)
- `RuntimeEnvelope.source` — how to extract paneId

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Features/NotificationInbox/Routing/NotificationRouterTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("NotificationRouter routing contract (spec §7)")
struct NotificationRouterTests {

    /// Lightweight fixture. The router under test needs an EventBus
    /// to subscribe to, a NotificationInboxAtom to write into, a
    /// prefsAtom for the bell toggle, a workspacePaneAtom for focus
    /// checks, and a paneContextResolver for repo/worktree/branch
    /// enrichment. Build minimal fixtures per the existing test
    /// helper conventions in the codebase.
    private func makeFixture() -> Fixture {
        // Construct atoms, bus, resolver; return a struct holding them
        // plus the router under test. Follow existing test-support
        // patterns (grep `struct.*Fixture` under Tests/).
        fatalError("implement with existing fixture utilities")
    }

    struct Fixture {
        let bus: EventBus<RuntimeEnvelope>
        let inboxAtom: NotificationInboxAtom
        let prefsAtom: NotificationInboxPrefsAtom
        let paneAtom: WorkspacePaneAtom
        let router: NotificationRouter
    }

    // §7 row-by-row tests. Each posts an envelope on the bus, then
    // checks inboxAtom.notifications for the expected kind / count.
    // Per the spec, tests rely on an injected clock rather than
    // wall-clock sleeps.

    @Test("desktopNotificationRequested → agentDesktopNotification")
    func desktopNotification() async throws {
        let f = makeFixture()
        let title = "Codex done"
        let body = "exit 0"
        let paneId = UUID()

        let envelope = /* build RuntimeEnvelope with source=.pane(paneId),
                          event=.terminal(.desktopNotificationRequested(
                              title: title, body: body)) */
            fatalError("build envelope")

        await f.bus.post(envelope)
        // drain
        try? await Task.sleep(for: .milliseconds(20))

        #expect(f.inboxAtom.notifications.count == 1)
        #expect(f.inboxAtom.notifications[0].kind == .agentDesktopNotification)
        #expect(f.inboxAtom.notifications[0].title == title)
        #expect(f.inboxAtom.notifications[0].body == body)
        #expect(f.inboxAtom.notifications[0].paneId == paneId)
    }

    @Test("bellRang with bellEnabled=false → no notification")
    func bellGatedOff() async throws {
        let f = makeFixture()
        #expect(f.prefsAtom.bellEnabled == false)
        let envelope = /* build .terminal(.bellRang) */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.isEmpty)
    }

    @Test("bellRang with bellEnabled=true → bellRang notification")
    func bellGatedOn() async throws {
        let f = makeFixture()
        f.prefsAtom.setBellEnabled(true)
        let envelope = /* .terminal(.bellRang) */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.count == 1)
        #expect(f.inboxAtom.notifications[0].kind == .bellRang)
    }

    @Test("commandFinished with focused pane → no notification")
    func commandFinishedFocused() async throws {
        let f = makeFixture()
        let paneId = UUID()
        f.paneAtom.setActivePaneId(paneId)  // adjust to real API
        let envelope = /* .terminal(.commandFinished(exitCode: 0, duration: 30))
                          on source=.pane(paneId) */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.isEmpty)
    }

    @Test("commandFinished unfocused, duration < 10s → no notification")
    func commandFinishedShort() async throws {
        let f = makeFixture()
        let envelope = /* commandFinished on unfocused pane, duration = 3 */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.isEmpty)
    }

    @Test("commandFinished unfocused, duration >= 10s → commandFinished notification")
    func commandFinishedLong() async throws {
        let f = makeFixture()
        let envelope = /* commandFinished on unfocused pane, duration = 15 */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.count == 1)
        #expect(f.inboxAtom.notifications[0].kind == .commandFinished)
    }

    @Test("approvalRequested always notifies")
    func approvalRequested() async throws {
        let f = makeFixture()
        let envelope = /* artifact event with approvalRequested */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.count == 1)
        #expect(f.inboxAtom.notifications[0].kind == .approvalRequested)
    }

    // Security event subset
    @Test("SecurityEvent.networkEgressBlocked → notification")
    func securityNetworkEgress() async throws {
        let f = makeFixture()
        let envelope = /* .security(.networkEgressBlocked(...)) */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.count == 1)
        #expect(f.inboxAtom.notifications[0].kind == .securityEvent)
    }

    @Test("SecurityEvent.sandboxStarted → no notification (lifecycle, not alert)")
    func securitySandboxStarted() async throws {
        let f = makeFixture()
        let envelope = /* .security(.sandboxStarted(...)) */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.isEmpty)
    }

    // Default-deny rows
    @Test("FilesystemEvent events do NOT notify")
    func filesystemEventsIgnored() async throws {
        let f = makeFixture()
        let envelope = /* filesChanged event */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.isEmpty)
    }

    @Test("progressReportUpdated → no notification")
    func progressIgnored() async throws {
        let f = makeFixture()
        let envelope = /* .terminal(.progressReportUpdated(...)) */
            fatalError("build envelope")
        await f.bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(f.inboxAtom.notifications.isEmpty)
    }

    // Auto-dismiss via PaneFocusTracker
    @Test("focus-gained clears unread for that pane")
    func focusGainedClearsUnread() async throws {
        let f = makeFixture()
        let paneId = UUID()
        // Pre-seed a notification for paneId
        f.inboxAtom.append(/* notification with paneId */
            fatalError("build notification"))
        #expect(f.inboxAtom.unreadCount(forPaneId: paneId) == 1)

        // Simulate focus gained
        f.paneAtom.setActivePaneId(paneId)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(f.inboxAtom.unreadCount(forPaneId: paneId) == 0,
                "router should mark read on focus-gained")
        // Drawer dismissal too
        #expect(
            f.inboxAtom.notifications.first?.isDismissedFromDrawer == true
        )
    }
}
```

Fill in the `fatalError("build envelope")` placeholders with the real `RuntimeEnvelope(...)` constructions once the envelope API is confirmed. Every row of the §7 routing table must have at least one test.

- [ ] **Step 3: Implement `NotificationRouter`**

Create `Sources/AgentStudio/Features/NotificationInbox/Routing/NotificationRouter.swift`:

```swift
import Foundation

/// Leaf subscriber on EventBus<RuntimeEnvelope>. Applies the
/// §7 routing contract: maps incoming runtime events to
/// Notification records (or discards them), enriches with
/// denormalized source context, and appends to
/// NotificationInboxAtom.
///
/// Also subscribes to PaneFocusTracker.focusGainedStream and
/// clears read + dismissed-from-drawer flags on focused panes.
///
/// See spec §7 (routing contract), §4.2 (dismissal rule), §8.3
/// (subscription pattern).
@MainActor
final class NotificationRouter {

    private let bus: EventBus<RuntimeEnvelope>
    private let inboxAtom: NotificationInboxAtom
    private let prefsAtom: NotificationInboxPrefsAtom
    private let paneAtom: WorkspacePaneAtom
    private let contextResolver: PaneContextResolver
    private let focusTracker: PaneFocusTracker

    private var busTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope>,
        inboxAtom: NotificationInboxAtom,
        prefsAtom: NotificationInboxPrefsAtom,
        paneAtom: WorkspacePaneAtom,
        contextResolver: PaneContextResolver,
        focusTracker: PaneFocusTracker
    ) {
        self.bus = bus
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.paneAtom = paneAtom
        self.contextResolver = contextResolver
        self.focusTracker = focusTracker
        start()
    }

    func start() {
        // Subscribe to the bus. Adjust to match existing bus API.
        busTask = Task { [weak self] in
            guard let self else { return }
            for await envelope in self.bus.events {
                self.handle(envelope)
            }
        }
        focusTask = Task { [weak self] in
            guard let self else { return }
            for await paneId in self.focusTracker.focusGainedStream {
                self.inboxAtom.markRead(paneId: paneId)
                self.inboxAtom.dismissFromDrawer(paneId: paneId)
            }
        }
    }

    func stop() {
        busTask?.cancel()
        focusTask?.cancel()
    }

    // MARK: - Routing contract (§7)

    private func handle(_ envelope: RuntimeEnvelope) {
        guard let kind = classify(envelope) else { return }
        guard let sourcePaneId = paneId(from: envelope) else {
            // For some kinds (e.g. security), paneId may legitimately
            // be nil. Build a notification with nil paneId.
            append(kind: kind, title: title(for: envelope),
                   body: body(for: envelope), paneId: nil)
            return
        }
        append(
            kind: kind,
            title: title(for: envelope),
            body: body(for: envelope),
            paneId: sourcePaneId
        )
    }

    /// Returns the NotificationKind if the envelope should produce
    /// a notification, nil otherwise. Implements spec §7 row-by-row.
    private func classify(_ envelope: RuntimeEnvelope) -> NotificationKind? {
        switch envelope.event {
        case .terminal(.desktopNotificationRequested):
            return .agentDesktopNotification

        case .terminal(.bellRang):
            return prefsAtom.bellEnabled ? .bellRang : nil

        case .terminal(.commandFinished(_, let duration)):
            // Only if pane is NOT focused AND duration >= 10s
            guard let pid = paneId(from: envelope),
                  paneAtom.activePaneId != pid,
                  duration >= 10
            else { return nil }
            return .commandFinished

        // Bridge inbox.post comes through as a PaneRuntimeEvent case
        // added in Task 7. Adjust the case name as Task 7 specifies.
        case .plugin(_, let event) where event is BridgeInboxPostEvent:
            return .agentRpc

        case .artifact(.approvalRequested):
            return .approvalRequested

        case .security(.networkEgressBlocked),
             .security(.filesystemAccessDenied),
             .security(.secretAccessed),
             .security(.processSpawnBlocked):
            return .securityEvent

        case .security(.sandboxHealthChanged(let healthy)) where !healthy:
            return .securityEvent

        // Default deny for everything else:
        default:
            return nil
        }
    }

    private func paneId(from envelope: RuntimeEnvelope) -> UUID? {
        if case .pane(let pid) = envelope.source { return pid }
        return nil
    }

    private func title(for envelope: RuntimeEnvelope) -> String {
        // Extract per-kind titles. For desktopNotificationRequested,
        // the title is in the event payload. For others, synthesize
        // a sensible default per the kind.
        // Adjust to the actual event case shapes.
        switch envelope.event {
        case .terminal(.desktopNotificationRequested(let t, _)):
            return t
        case .terminal(.bellRang):
            return "Bell"
        case .terminal(.commandFinished(let code, _)):
            return code == 0 ? "Command finished"
                             : "Command failed (exit \(code))"
        case .artifact(.approvalRequested):
            return "Approval requested"
        case .security:
            return "Security event"
        default:
            return "Notification"
        }
    }

    private func body(for envelope: RuntimeEnvelope) -> String? {
        switch envelope.event {
        case .terminal(.desktopNotificationRequested(_, let b)):
            return b.isEmpty ? nil : b
        case .terminal(.commandFinished(let code, let duration)):
            return "exit \(code) · \(formatDuration(duration))"
        default:
            return nil
        }
    }

    private func formatDuration(_ seconds: UInt64) -> String {
        let minutes = seconds / 60
        let s = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(s)s"
        } else {
            return "\(s)s"
        }
    }

    private func append(
        kind: NotificationKind,
        title: String,
        body: String?,
        paneId: UUID?
    ) {
        let context = paneId.flatMap {
            contextResolver.resolve(paneId: $0)
        }
        let note = Notification(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            title: title,
            body: body,
            paneId: paneId,
            tabId: context?.tabId,
            repoId: context?.repoId,
            repoName: context?.repoName,
            worktreeId: context?.worktreeId,
            worktreeName: context?.worktreeName,
            branchName: context?.branchName,
            isRead: false,
            isDismissedFromDrawer: false
        )
        inboxAtom.append(note)
    }
}

/// Supplies denormalized source context for a pane at emit time.
/// Lookup from WorkspacePaneAtom + RepoCacheAtom.
@MainActor
struct PaneContextResolver {
    let paneAtom: WorkspacePaneAtom
    let repoCacheAtom: RepoCacheAtom   // or whatever the real accessor is

    struct Resolved {
        let tabId: UUID?
        let repoId: UUID?
        let repoName: String?
        let worktreeId: UUID?
        let worktreeName: String?
        let branchName: String?
    }

    func resolve(paneId: UUID) -> Resolved? {
        guard let pane = paneAtom.pane(paneId) else { return nil }
        // Pull repo/worktree/branch info from RepoCacheAtom keyed
        // by pane.repoId / pane.worktreeId. Wire to the real API.
        return Resolved(
            tabId: /* pane.tabId or parent tab lookup */ nil,
            repoId: pane.repoId,
            repoName: /* repoCacheAtom.repoName(for: pane.repoId) */ nil,
            worktreeId: pane.worktreeId,
            worktreeName: /* repoCacheAtom.worktreeName(for: pane.worktreeId) */ nil,
            branchName: /* repoCacheAtom.branch(for: pane.worktreeId) */ nil
        )
    }
}
```

Fill in the context resolver with the real `RepoCacheAtom` accessor names by grepping the existing code.

- [ ] **Step 4: Run tests, lint, commit**

```bash
mise run test -- --filter NotificationRouterTests
mise run lint
git add Sources/AgentStudio/Features/NotificationInbox/Routing/ \
        Tests/AgentStudioTests/Features/NotificationInbox/Routing/
git commit -m "feat(notification-inbox): add NotificationRouter

Leaf subscriber on EventBus<RuntimeEnvelope>. Implements spec
§7 routing contract row-by-row. Enriches with repo/worktree/
branch denormalized context at emit time. Also subscribes to
PaneFocusTracker.focusGainedStream to auto-dismiss on focus
(markRead + dismissFromDrawer). LUNA-361 Phase 3."
```

---

## Task 7: Bridge `inbox.post` RPC handler

**Files:**
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
  - Add a new handler for method name `inbox.post`.
  - Payload shape per spec §7:
    ```json
    { "jsonrpc": "2.0",
      "method": "inbox.post",
      "params": { "title": "...", "body": "..." } }
    ```
  - Emit a new `PaneRuntimeEvent` case (or reuse `.plugin(kind: .bridgePanel, event: BridgeInboxPostEvent)` if the codebase prefers the plugin wrapper). The router classifies this as `.agentRpc`.
  - Infer paneId from the bridge pane context at RPC receive time; ignore any `paneId` in the caller-supplied params (security: agents cannot spoof).
- Test fixture: `Tests/BridgeContractFixtures/valid/rpc-command-inbox-post.json`
- Test: `Tests/AgentStudioTests/Features/Bridge/Transport/InboxPostHandlerTests.swift`

- [ ] **Step 1: Add the fixture file**

Create `Tests/BridgeContractFixtures/valid/rpc-command-inbox-post.json`:

```json
{
  "jsonrpc": "2.0",
  "method": "inbox.post",
  "params": {
    "title": "Claude Code finished",
    "body": "3 files changed, 142 lines"
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Features/Bridge/Transport/InboxPostHandlerTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("Bridge inbox.post RPC handler")
struct InboxPostHandlerTests {

    @Test("valid inbox.post emits PaneRuntimeEvent with inferred paneId")
    func validPost() async throws {
        // Arrange: RPCRouter instance bound to a specific bridge
        // pane (paneId P), bus emitter captured for assertion.
        let expectedPaneId = UUID()
        var emitted: [RuntimeEnvelope] = []
        let router = makeRPCRouter(
            paneId: expectedPaneId,
            onEmit: { emitted.append($0) }
        )
        let payload = try fixtureData("rpc-command-inbox-post.json")

        // Act
        try await router.handle(message: payload)

        // Assert
        #expect(emitted.count == 1)
        let env = emitted[0]
        if case .pane(let pid) = env.source {
            #expect(pid == expectedPaneId)
        } else {
            Issue.record("expected .pane source, got \(env.source)")
        }
        // Assert the event is the inbox.post event type, title/body
        // match. Adjust case match to whatever shape the
        // implementation picks.
    }

    @Test("inbox.post with caller-supplied paneId is ignored (security)")
    func spoofIgnored() async throws {
        let routerPaneId = UUID()
        let spoofedPaneId = UUID()
        var emitted: [RuntimeEnvelope] = []
        let router = makeRPCRouter(
            paneId: routerPaneId,
            onEmit: { emitted.append($0) }
        )

        let spoofed: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "inbox.post",
            "params": [
                "title": "Fake",
                "body": "Fake",
                "paneId": spoofedPaneId.uuidString
            ]
        ]
        let data = try JSONSerialization.data(
            withJSONObject: spoofed, options: [])
        try await router.handle(message: data)

        #expect(emitted.count == 1)
        if case .pane(let pid) = emitted[0].source {
            #expect(pid == routerPaneId,
                    "must use router's paneId, not caller-supplied")
        }
    }

    // Helpers — implement against real APIs:
    private func makeRPCRouter(
        paneId: UUID,
        onEmit: @escaping (RuntimeEnvelope) -> Void
    ) -> RPCRouter { fatalError() }
    private func fixtureData(_ name: String) throws -> Data { fatalError() }
}
```

- [ ] **Step 3: Implement the handler**

Modify `RPCRouter.swift`:

1. Register `inbox.post` in whatever method registry the router uses.
2. Handler body:

```swift
// Inside RPCRouter (or a new file under Methods/):
func handleInboxPost(params: [String: Any]) throws {
    guard let title = params["title"] as? String else {
        throw RPCError.invalidParams("missing 'title'")
    }
    let body = params["body"] as? String
    // IMPORTANT: we deliberately do NOT read params["paneId"] —
    // the RPC connection is bound to a specific bridge pane, and
    // that's the authoritative source. Caller-supplied paneId is
    // ignored to prevent spoofing.
    let envelope = RuntimeEnvelope(
        source: .pane(self.bridgePaneId),
        event: /* InboxPost event — see note in Task 6 about whether
                  this is a new PaneRuntimeEvent case or a plugin
                  wrapper */,
        // ... other envelope fields
    )
    emit(envelope)  // whatever the bus injection method is
}
```

3. Decide on the `RuntimeEnvelope.event` shape for bridge inbox posts. Two reasonable options:
    - Add a new `PaneRuntimeEvent` case, e.g., `.bridgeInboxPost(title: String, body: String?)`. Requires updating `NotificationRouter.classify(_:)` to match.
    - Wrap in the existing `.plugin(kind:event:)` mechanism — if the codebase already uses plugin events for bridge-specific things, follow that.

    Grep `case plugin` and existing bridge event injections to decide. Use whichever matches the codebase's convention.

- [ ] **Step 4: Run tests, lint, commit**

```bash
mise run test -- --filter InboxPostHandlerTests
mise run lint
git add Sources/AgentStudio/Features/Bridge/Transport/ \
        Tests/BridgeContractFixtures/valid/rpc-command-inbox-post.json \
        Tests/AgentStudioTests/Features/Bridge/Transport/InboxPostHandlerTests.swift
git commit -m "feat(bridge): add inbox.post RPC handler

Registers the inbox.post JSON-RPC method on RPCRouter. Emits
a PaneRuntimeEvent with paneId inferred from the bridge
connection's bound pane. Caller-supplied 'paneId' param is
ignored (agents cannot spoof notifications from other panes).
Consumed by NotificationRouter as .agentRpc kind. LUNA-361
Phase 3."
```

---

## Task 8: Inbox components (`InboxRow`, `InboxGroupHeader`, `InboxEmptyState`)

Small SwiftUI views. Stateless — take a `Notification` (or group descriptor) and render.

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Components/InboxRow.swift`
- Create: `Sources/AgentStudio/Features/NotificationInbox/Components/InboxGroupHeader.swift`
- Create: `Sources/AgentStudio/Features/NotificationInbox/Components/InboxEmptyState.swift`

Reference the panel layout in spec §6.

- [ ] **Step 1: `InboxRow`**

```swift
import SwiftUI

/// Single row in the inbox. Two or three lines:
///   Line 1: unread dot + title + relative time
///   Line 2: <repo> · <worktree> (or worktree / branch if different)
///   Line 3: body (dim, single line, only if non-empty)
/// See spec §6 row anatomy.
struct InboxRow: View {
    let notification: Notification
    let now: Date     // inject for deterministic "2m ago" formatting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if !notification.isRead {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }
                Text(notification.title)
                    .font(.system(size: 13, weight: notification.isRead
                                  ? .regular : .semibold))
                    .lineLimit(1)
                Spacer()
                Text(relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let contextLine {
                Text(contextLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let body = notification.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private var relativeTime: String {
        let delta = now.timeIntervalSince(notification.timestamp)
        // Simple: "now", "5m", "2h", "3d" — match existing relative
        // time helper if one exists in the codebase, else implement
        // inline.
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }
        return "\(Int(delta / 86_400))d"
    }

    private var contextLine: String? {
        guard let repo = notification.repoName else { return nil }
        if let worktree = notification.worktreeName {
            if let branch = notification.branchName,
               branch != worktree {
                return "\(repo) · \(worktree) / \(branch)"
            }
            return "\(repo) · \(worktree)"
        }
        return repo
    }
}
```

- [ ] **Step 2: `InboxGroupHeader`**

```swift
import SwiftUI

struct InboxGroupHeader: View {
    let label: String
    let unreadCount: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }
}
```

- [ ] **Step 3: `InboxEmptyState`**

```swift
import SwiftUI

struct InboxEmptyState: View {
    var body: some View {
        VStack {
            Text("No notifications yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Build + lint + commit**

```bash
mise run build
mise run lint
git add Sources/AgentStudio/Features/NotificationInbox/Components/
git commit -m "feat(notification-inbox): add InboxRow/GroupHeader/EmptyState components

Small stateless SwiftUI views following spec §6 row anatomy.
Reusable within the feature — feature-internal Components/
subdirectory per feature-slice self-containment rules.
LUNA-361 Phase 3."
```

---

## Task 9: `InboxSidebarView`

The main inbox screen. Composes components, declares `InboxFocus` (per spec §4.3 / §8.4), publishes `sidebarHasFocus`, attaches all keymap shortcuts, applies grouping + sort + search, handles click-through.

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Views/InboxSidebarView.swift`

- [ ] **Step 1: Implement the view**

Create `Sources/AgentStudio/Features/NotificationInbox/Views/InboxSidebarView.swift`:

```swift
import SwiftUI

/// Focus targets within the Inbox sidebar surface.
/// See spec §4.3 sidebarHasFocus contract.
enum InboxFocus: Hashable {
    case search
    case list
    case row(UUID)
    case groupingMenu
}

struct InboxSidebarView: View {

    let inboxAtom: NotificationInboxAtom
    let prefsAtom: NotificationInboxPrefsAtom
    let uiState: UIStateAtom

    // Command dispatcher for click-through focusing of source pane
    let dispatcher: CommandDispatcher

    @FocusState private var focusedField: InboxFocus?
    @State private var searchText: String = ""
    @State private var groupingMenuOpen: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .onChange(of: focusedField) { _, new in
            uiState.setSidebarHasFocus(new != nil)
        }
        // ⌥F: focus the search field
        .onKeyPress(.init("f"), modifiers: [.option]) {
            focusedField = .search
            return .handled
        }
        // ⌥G: toggle grouping menu
        .onKeyPress(.init("g"), modifiers: [.option]) {
            groupingMenuOpen.toggle()
            return .handled
        }
        // ⌥S: toggle sort
        .onKeyPress(.init("s"), modifiers: [.option]) {
            let next: NotificationInboxSort =
                prefsAtom.sort == .newestFirst ? .oldestFirst : .newestFirst
            prefsAtom.setSort(next)
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .search)
                .onSubmit {
                    focusedField = .list  // move to list on Enter
                }
            Button(action: { /* toggle sort */
                let next: NotificationInboxSort =
                    prefsAtom.sort == .newestFirst
                    ? .oldestFirst : .newestFirst
                prefsAtom.setSort(next)
            }) {
                Image(systemName: prefsAtom.sort == .newestFirst
                      ? "arrow.down.to.line"
                      : "arrow.up.to.line")
            }
            .buttonStyle(.borderless)
            Button(action: { groupingMenuOpen.toggle() }) {
                Image(systemName: "line.3.horizontal")
            }
            .buttonStyle(.borderless)
            .focused($focusedField, equals: .groupingMenu)
            .popover(isPresented: $groupingMenuOpen) {
                groupingMenu
            }
        }
        .padding(8)
    }

    private var list: some View {
        Group {
            if filtered.isEmpty {
                InboxEmptyState()
            } else {
                scrollableBody
            }
        }
    }

    private var scrollableBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedRows, id: \.key) { group in
                    if !group.label.isEmpty {
                        InboxGroupHeader(
                            label: group.label,
                            unreadCount: group.unreadCount
                        )
                    }
                    ForEach(group.notifications) { note in
                        InboxRow(notification: note, now: Date())
                            .focused($focusedField, equals: .row(note.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activate(note)
                            }
                            .onKeyPress(.return) {
                                if focusedField == .row(note.id) {
                                    activate(note)
                                    return .handled
                                }
                                return .ignored
                            }
                            .onKeyPress(.space) {
                                if focusedField == .row(note.id) {
                                    inboxAtom.toggleReadState(id: note.id)
                                    return .handled
                                }
                                return .ignored
                            }
                    }
                }
            }
        }
        .focused($focusedField, equals: .list)
    }

    private var groupingMenu: some View {
        VStack(alignment: .leading) {
            ForEach(NotificationInboxGrouping.allCases, id: \.self) { g in
                Button(action: {
                    prefsAtom.setGrouping(g)
                    groupingMenuOpen = false
                }) {
                    HStack {
                        Image(systemName: prefsAtom.grouping == g
                              ? "checkmark" : "")
                        Text(label(for: g))
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
    }

    // MARK: - Filtering / grouping / sort

    private var filtered: [Notification] {
        let q = searchText.lowercased()
        if q.isEmpty { return sorted(inboxAtom.notifications) }
        return sorted(inboxAtom.notifications.filter {
            $0.title.lowercased().contains(q)
            || ($0.body ?? "").lowercased().contains(q)
            || ($0.repoName ?? "").lowercased().contains(q)
            || ($0.worktreeName ?? "").lowercased().contains(q)
            || ($0.branchName ?? "").lowercased().contains(q)
        })
    }

    private func sorted(_ list: [Notification]) -> [Notification] {
        switch prefsAtom.sort {
        case .newestFirst:
            return list.sorted { $0.timestamp > $1.timestamp }
        case .oldestFirst:
            return list.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private struct Group {
        let key: String
        let label: String
        let notifications: [Notification]
        var unreadCount: Int {
            notifications.reduce(0) { $1.isRead ? $0 : $0 + 1 }
        }
    }

    private var groupedRows: [Group] {
        let items = filtered
        switch prefsAtom.grouping {
        case .none:
            return [Group(key: "all", label: "", notifications: items)]
        case .byRepo:
            let buckets = Dictionary(grouping: items) {
                $0.repoName ?? "(no repo)"
            }
            return buckets.keys.sorted().map { key in
                Group(key: key, label: key,
                      notifications: buckets[key] ?? [])
            }
        case .byPane:
            let buckets = Dictionary(grouping: items) {
                $0.paneId?.uuidString ?? "(no pane)"
            }
            return buckets.keys.sorted().map { key in
                let list = buckets[key] ?? []
                let label = list.first?.worktreeName ?? key
                return Group(key: key, label: label, notifications: list)
            }
        case .byTab:
            let buckets = Dictionary(grouping: items) {
                $0.tabId?.uuidString ?? "(no tab)"
            }
            return buckets.keys.sorted().map { key in
                Group(key: key, label: "Tab \(key.prefix(8))",
                      notifications: buckets[key] ?? [])
            }
        }
    }

    private func label(for g: NotificationInboxGrouping) -> String {
        switch g {
        case .none:   return "None"
        case .byRepo: return "By repo"
        case .byPane: return "By pane"
        case .byTab:  return "By tab"
        }
    }

    // MARK: - Actions

    private func activate(_ n: Notification) {
        inboxAtom.markRead(id: n.id)
        inboxAtom.dismissFromDrawer(id: n.id)
        if let paneId = n.paneId {
            dispatcher.dispatch(.focusPane(paneId))
        }
    }
}
```

Adjust `.onKeyPress(...)` API usage to whatever Swift 6.2 / iOS 17+ convention the codebase uses. If `.onKeyPress` isn't appropriate (older target), use `NSViewRepresentable` key-event bridge or `.keyboardShortcut` with hidden buttons per existing patterns. Check what `CommandBar` does for custom key handling.

Adjust `CommandDispatcher.dispatch(.focusPane(...))` to match the real API — the spec says `PaneActionCommand.focusPane(paneId)`.

- [ ] **Step 2: Tests (view-level smoke)**

Write a smoke test ensuring the view instantiates and renders for a small fixture set. Full UI tests (keymap behavior, click-through) are more productive as integration tests in Task 16. For now:

```swift
@Test("InboxSidebarView instantiates")
func instantiates() {
    let inbox = NotificationInboxAtom()
    let prefs = NotificationInboxPrefsAtom()
    let uiState = UIStateAtom()
    let dispatcher = CommandDispatcher.makeForTest()  // or real
    let view = InboxSidebarView(
        inboxAtom: inbox,
        prefsAtom: prefs,
        uiState: uiState,
        dispatcher: dispatcher
    )
    #expect(view.body is (any View))  // trivial — exercise the init
}
```

- [ ] **Step 3: Build, lint, commit**

```bash
mise run build
mise run lint
git add Sources/AgentStudio/Features/NotificationInbox/Views/InboxSidebarView.swift \
        Tests/AgentStudioTests/Features/NotificationInbox/Views/
git commit -m "feat(notification-inbox): add InboxSidebarView

Main inbox sidebar screen. Declares InboxFocus enum and
publishes sidebarHasFocus via @FocusState onChange per spec
§4.3 contract. Keymap: ⌥F (search), ⌥G (grouping menu),
⌥S (sort toggle), arrows/Enter/Space (row navigation),
click-through via dispatcher → PaneActionCommand.focusPane.
Search filters across title/body/repo/worktree/branch.
Grouping: none/by repo/by pane/by tab. LUNA-361 Phase 3."
```

---

## Task 10: Drawer `TrailingActions` extension + bell rendering

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`

- [ ] **Step 1: Read `DrawerOverlay.swift` and `DrawerIconBar.swift`**

Locate the `TrailingActions` struct (in `DrawerOverlay.swift`) and the trailing-actions rendering block in `DrawerIconBar.swift` (approximately lines 116–147 per Phase 1 research).

- [ ] **Step 2: Extend `TrailingActions`**

Add two fields to the `TrailingActions` struct:

```swift
public struct TrailingActions {
    // ... existing fields ...
    /// Callback invoked when the user taps the inbox bell. Nil
    /// means no bell rendered.
    public var onOpenInbox: (() -> Void)? = nil

    /// Unread count shown as a badge on the bell icon. Zero or
    /// nil means no badge.
    public var inboxUnreadCount: Int = 0
}
```

- [ ] **Step 3: Render the bell in `DrawerIconBar`**

In the trailing-actions `if let trailingActions { ... }` conditional (the HStack near line 116-147), add — after existing icons, after a visible `Divider()` — a new button for the bell:

```swift
if let onOpenInbox = trailingActions.onOpenInbox {
    Divider()
        .frame(height: 14)
        .padding(.horizontal, 4)
    trailingActionButton(
        icon: .system(name: "bell.fill"),
        helpText: "Open notification inbox",
        isHovered: /* @State hover binding — mirror existing pattern */,
        action: onOpenInbox
    )
    .overlay(alignment: .topTrailing) {
        if trailingActions.inboxUnreadCount > 0 {
            Text("\(trailingActions.inboxUnreadCount)")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(.red))
                .foregroundStyle(.white)
                .offset(x: 4, y: -4)
        }
    }
}
```

Match the existing `trailingActionButton(...)` helper signature exactly (grep inside `DrawerIconBar.swift`).

- [ ] **Step 4: Build, lint, commit**

```bash
mise run build
mise run lint
git add Sources/AgentStudio/Core/Views/Drawer/
git commit -m "feat(drawer): add bell slot to TrailingActions + render in DrawerIconBar

DrawerOverlay.TrailingActions grows two optional fields:
onOpenInbox callback and inboxUnreadCount badge number. When
onOpenInbox is non-nil, DrawerIconBar renders a bell icon
button as the rightmost trailing slot (after a divider),
with an optional red-capsule unread-count badge overlay.
Feature-agnostic — the Features-level wrapper (Phase 3 Task
11 DrawerInboxBellHost) injects the values. LUNA-361 Phase 3."
```

---

## Task 11: `DrawerInboxBellHost` + `DrawerInboxPopover`

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Views/DrawerInboxBellHost.swift`
- Create: `Sources/AgentStudio/Features/NotificationInbox/Views/DrawerInboxPopover.swift`

Per spec §3.2, the drawer popover is scoped to panes in the currently focused drawer. `DrawerInboxBellHost` is the Features-level wrapper that reads `NotificationInboxAtom.unreadCount(forDrawerPaneIds:)`, injects into `TrailingActions`, and attaches the popover presentation.

- [ ] **Step 1: Implement `DrawerInboxBellHost`**

```swift
import SwiftUI

/// Features-level wrapper around DrawerOverlay that supplies
/// the bell slot's unread count and open-popover action. Lives
/// in the feature slice because it reads NotificationInboxAtom.
/// Called by whatever instantiates DrawerOverlay (App or
/// per-pane view layer).
@MainActor
struct DrawerInboxBellHost<Content: View>: View {
    let drawerPaneIds: [UUID]  // the panes this drawer hosts
    let inboxAtom: NotificationInboxAtom
    let prefsAtom: NotificationInboxPrefsAtom
    let dispatcher: CommandDispatcher
    /// The DrawerOverlay (or equivalent) you want to host.
    let content: (DrawerOverlay.TrailingActions) -> Content

    @State private var popoverOpen: Bool = false

    var body: some View {
        content(trailingActions())
            .popover(isPresented: $popoverOpen, arrowEdge: .top) {
                DrawerInboxPopover(
                    drawerPaneIds: drawerPaneIds,
                    inboxAtom: inboxAtom,
                    dispatcher: dispatcher,
                    onClose: { popoverOpen = false }
                )
            }
    }

    private func trailingActions() -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            // ... pass-through existing fields if any ...
            onOpenInbox: { popoverOpen = true },
            inboxUnreadCount: inboxAtom.unreadCount(
                forDrawerPaneIds: drawerPaneIds)
        )
    }
}
```

Adjust `DrawerOverlay.TrailingActions` init to match existing signature — you may need to accept pass-through fields (finder/editor callbacks) from an outer caller and add the bell here.

- [ ] **Step 2: Implement `DrawerInboxPopover`**

```swift
import SwiftUI

struct DrawerInboxPopover: View {
    let drawerPaneIds: [UUID]
    let inboxAtom: NotificationInboxAtom
    let dispatcher: CommandDispatcher
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(width: 320, height: 400)
    }

    private var header: some View {
        HStack {
            Text("Drawer inbox")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var relevant: [Notification] {
        let set = Set(drawerPaneIds)
        return inboxAtom.notifications
            .filter { n in
                guard let pid = n.paneId else { return false }
                return set.contains(pid) && !n.isDismissedFromDrawer
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var list: some View {
        Group {
            if relevant.isEmpty {
                InboxEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(relevant) { note in
                            InboxRow(notification: note, now: Date())
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    inboxAtom.markRead(id: note.id)
                                    inboxAtom.dismissFromDrawer(id: note.id)
                                    if let paneId = note.paneId {
                                        dispatcher.dispatch(.focusPane(paneId))
                                    }
                                    onClose()
                                }
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build, lint, commit**

```bash
mise run build
mise run lint
git add Sources/AgentStudio/Features/NotificationInbox/Views/DrawerInboxBellHost.swift \
        Sources/AgentStudio/Features/NotificationInbox/Views/DrawerInboxPopover.swift
git commit -m "feat(notification-inbox): add DrawerInboxBellHost + DrawerInboxPopover

Host wraps DrawerOverlay and injects inboxUnreadCount +
onOpenInbox into its TrailingActions (bell slot from Task 10).
Popover filters notifications to paneId in drawerPaneIds and
not isDismissedFromDrawer; clicking a row marks read +
dismisses from drawer and dispatches focusPane. LUNA-361
Phase 3."
```

---

## Task 12: `RepoExplorerWorktreeRow` 🔔 N pill binds to `NotificationInboxAtom`

**Files:**
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`

- [ ] **Step 1: Find the existing pill-render code**

Grep:
```bash
grep -n "🔔\|bell\|notificationCount" Sources/AgentStudio/Features/RepoExplorer/
```

Today the pill likely shows a placeholder `0`. Replace the data source with `inboxAtom.unreadCount(forWorktreeId: ...)`.

- [ ] **Step 2: Inject `inboxAtom` dependency**

Propagate `inboxAtom` through the view chain from wherever `RepoExplorerView` is instantiated (the view receives it from `SidebarSurfaceHost`, which receives it from the composition root in Task 15). Add as a stored property on `RepoExplorerWorktreeRow`:

```swift
struct RepoExplorerWorktreeRow: View {
    let worktree: Worktree
    let inboxAtom: NotificationInboxAtom   // NEW
    // ... existing fields ...

    var body: some View {
        // ... existing row content ...
        HStack {
            // ... other pills ...
            bellPill  // bound to the atom
        }
    }

    private var bellPill: some View {
        let count = inboxAtom.unreadCount(forWorktreeId: worktree.id)
        return HStack(spacing: 2) {
            Image(systemName: "bell")
                .font(.system(size: 10))
            Text("\(count)")
                .font(.system(size: 10))
        }
        .foregroundStyle(count > 0 ? .red : .secondary)
    }
}
```

- [ ] **Step 3: Run tests (existing RepoExplorer tests) to ensure nothing breaks; lint; commit**

```bash
mise run test -- --filter RepoExplorer
mise run lint
git add Sources/AgentStudio/Features/RepoExplorer/
git commit -m "feat(repo-explorer): bind worktree bell pill to NotificationInboxAtom

RepoExplorerWorktreeRow now reads unread count from
NotificationInboxAtom.unreadCount(forWorktreeId:). Replaces
the placeholder 0. LUNA-361 Phase 3."
```

---

## Task 13: Populate `.inbox` CommandBar scope actions

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`

- [ ] **Step 1: Define inbox-scoped action rows**

Per spec §5.2, the `.inbox` scope should offer:

- Mark all as read
- Clear read history
- Clear all notifications (with confirmation)
- Change grouping → None / By repo / By pane / By tab
- Toggle sort order
- Enable bell notifications / Disable bell notifications
- Return to worktree sidebar (⌘S)

- [ ] **Step 2: Wire each action**

In `CommandBarDataSource.swift` where `.inbox` currently returns `[]` (from Phase 2), populate:

```swift
case .inbox:
    var rows: [CommandBarItem] = []

    rows.append(CommandBarItem(
        id: "inbox.markAllAsRead",
        label: "Mark all as read",
        icon: .system(name: "checkmark.circle"),
        action: { _ in inboxAtom.markAllRead() }
    ))

    rows.append(CommandBarItem(
        id: "inbox.clearReadHistory",
        label: "Clear read history",
        icon: .system(name: "trash"),
        action: { _ in inboxAtom.clearReadHistory() }
    ))

    rows.append(CommandBarItem(
        id: "inbox.clearAll",
        label: "Clear all notifications…",
        icon: .system(name: "trash.fill"),
        action: { ctx in
            // Show an NSAlert confirmation before clearing
            ctx.confirm(
                message: "Clear all notifications?",
                onConfirm: { inboxAtom.clearAll() }
            )
        }
    ))

    // Grouping switcher — four rows
    for g in NotificationInboxGrouping.allCases {
        rows.append(CommandBarItem(
            id: "inbox.grouping.\(g.rawValue)",
            label: "Change grouping: \(labelFor(g))",
            icon: .system(name: "line.3.horizontal"),
            action: { _ in prefsAtom.setGrouping(g) }
        ))
    }

    // Sort toggle
    rows.append(CommandBarItem(
        id: "inbox.toggleSort",
        label: "Toggle sort order",
        icon: .system(name: "arrow.up.arrow.down"),
        action: { _ in
            let next: NotificationInboxSort =
                prefsAtom.sort == .newestFirst
                ? .oldestFirst : .newestFirst
            prefsAtom.setSort(next)
        }
    ))

    // Bell toggle — label reflects current state
    let bellLabel = prefsAtom.bellEnabled
        ? "Disable bell notifications"
        : "Enable bell notifications"
    rows.append(CommandBarItem(
        id: "inbox.toggleBell",
        label: bellLabel,
        icon: .system(name: "bell"),
        action: { _ in
            prefsAtom.setBellEnabled(!prefsAtom.bellEnabled)
        }
    ))

    // Return to worktree sidebar
    rows.append(CommandBarItem(
        id: "inbox.returnToWorktrees",
        label: "Return to worktree sidebar (⌘S)",
        icon: .system(name: "sidebar.left"),
        action: { ctx in ctx.dispatcher.dispatch(.showWorktreeSidebar) }
    ))

    return rows
```

Match `CommandBarItem` init signature and `action` closure shape exactly — grep an existing item construction to mirror. If actions take a `context` type, follow that convention.

Propagate `inboxAtom` and `prefsAtom` dependencies into `CommandBarDataSource` (update its init / factory).

- [ ] **Step 3: Tests, lint, commit**

Extend `CommandBarDataSourceTests.swift` (create if absent) with an inbox-scope smoke test: instantiate the data source with atoms, request items for `.inbox`, assert the expected item ids are present.

```bash
mise run test -- --filter CommandBar
mise run lint
git add Sources/AgentStudio/Features/CommandBar/
git commit -m "feat(command-bar): populate .inbox scope with action rows

Implements the seven inbox-scoped CommandBar actions from
spec §5.2: Mark all as read, Clear read history, Clear all
(with confirmation), Change grouping (four rows), Toggle
sort, Enable/Disable bell (reflects state), Return to
worktree sidebar. Reads NotificationInboxAtom and Notification-
InboxPrefsAtom through injected dependencies. LUNA-361 Phase 3."
```

---

## Task 14: ⌘⇧I composite command — drawer inbox popover

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift` — add `.showDrawerInbox`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift` — bind ⌘⇧I
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift` — dispatch handler

- [ ] **Step 1: Add the case**

```swift
// AppCommand.swift
case showDrawerInbox
```

- [ ] **Step 2: Bind the shortcut**

```swift
// AppShortcut.swift
ShortcutTrigger(key: "i", modifiers: [.command, .shift]): .showDrawerInbox,
```

- [ ] **Step 3: Implement the handler**

Per spec §3.2, `⌘⇧I` opens the drawer inbox popover **for the drawer of the currently focused pane**. If focus is not on a pane inside a drawer, the command is a no-op.

```swift
// In AppDelegate.perform(_ command:) dispatch switch:
case .showDrawerInbox:
    openDrawerInboxForFocusedPane()
```

```swift
@MainActor
private func openDrawerInboxForFocusedPane() {
    // Resolve the focused pane
    guard let activePaneId = store.paneAtom.activePaneId else { return }
    // Look up the pane's parent (if any). Per spec §10.2 drawer model:
    // child panes have parentPaneId pointing at their layout pane's
    // drawer host.
    guard let pane = store.paneAtom.pane(activePaneId),
          let parentPaneId = pane.parentPaneId,
          let parent = store.paneAtom.pane(parentPaneId),
          let drawer = parent.drawer
    else {
        return  // no-op
    }

    // Activate the drawer popover. The presentation mechanism
    // depends on how DrawerInboxBellHost exposes its popover —
    // likely via a binding controlled by the view layer, so this
    // handler may route through a shared `drawerInboxPopover-
    // Presenter` object. Follow the existing pattern for other
    // keyboard-triggered popovers.
    drawerInboxPresenter.open(forDrawerPaneIds: drawer.paneIds)
}
```

If no clean mechanism exists to pop a SwiftUI popover from AppDelegate, store a small `@Published` / `@Observable` request ID on a singleton presenter atom (`DrawerInboxPresenterAtom`) that the `DrawerInboxBellHost` observes and translates into `popoverOpen = true`. Keep this minimal.

- [ ] **Step 4: Tests, lint, commit**

Manual verification is acceptable here given the AppKit/popover integration:

1. Focus a pane inside a drawer
2. Press ⌘⇧I → popover opens showing that drawer's notifications
3. Focus a pane NOT inside a drawer (i.e., a layout pane)
4. Press ⌘⇧I → no-op (nothing happens)

Add a unit test for the no-op guard:

```swift
@Test("showDrawerInbox no-op when focused pane has no drawer parent")
func noOpWithoutDrawerParent() {
    // Setup: activePaneId points at a pane with parentPaneId == nil
    // Assert: drawerInboxPresenter.open(...) was NOT called
}
```

```bash
mise run test
mise run lint
git add ...
git commit -m "feat(app): wire CMD+SHIFT+I drawer inbox popover command

Resolves the focused pane's drawer parent per spec §10.2 and
opens DrawerInboxPopover scoped to that drawer's paneIds. No-op
when focus is not on a pane inside a drawer. LUNA-361 Phase 3."
```

---

## Task 15: Swap placeholder, boot wiring, delete `InboxPlaceholderView`

**Files:**
- Modify: `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Delete: `Sources/AgentStudio/Features/NotificationInbox/Views/InboxPlaceholderView.swift`

- [ ] **Step 1: Replace `InboxPlaceholderView` with `InboxSidebarView` in `SidebarSurfaceHost`**

```swift
// BEFORE (Phase 1)
case .inbox:
    InboxPlaceholderView()

// AFTER (Phase 3)
case .inbox:
    InboxSidebarView(
        inboxAtom: inboxAtom,
        prefsAtom: prefsAtom,
        uiState: uiState,
        dispatcher: dispatcher
    )
```

Propagate the new dependencies (`inboxAtom`, `prefsAtom`, `dispatcher`) through `SidebarSurfaceHost`'s init. Update its construction in `MainSplitViewController` accordingly.

- [ ] **Step 2: Delete the placeholder**

```bash
git rm Sources/AgentStudio/Features/NotificationInbox/Views/InboxPlaceholderView.swift
```

- [ ] **Step 3: Wire the boot sequence in `AppDelegate.swift`**

Post-Phase-2 state: `AppDelegate` already awaits `UIStateStore.load()` and constructs `MainWindowController`. Extend:

```swift
// During applicationDidFinishLaunching, after store loads:

// 1. Instantiate feature atoms
let notificationInboxAtom = NotificationInboxAtom()
let notificationInboxPrefsAtom = NotificationInboxPrefsAtom()
let notificationInboxStore = NotificationInboxStore(
    inboxAtom: notificationInboxAtom,
    prefsAtom: notificationInboxPrefsAtom,
    fileURL: workspaceBundleURL.appendingPathComponent(
        "notification-inbox.json")
)
do {
    try notificationInboxStore.load()
} catch {
    // Greenfield: file missing or corrupt → defaults, no crash
    Logger.boot.error("NotificationInboxStore load failed: \(error)")
}

// 2. Wire PaneFocusTracker
let paneFocusTracker = PaneFocusTracker(paneAtom: store.paneAtom)

// 3. Wire PaneContextResolver
let paneContextResolver = PaneContextResolver(
    paneAtom: store.paneAtom,
    repoCacheAtom: store.repoCacheAtom
)

// 4. Wire NotificationRouter
let notificationRouter = NotificationRouter(
    bus: paneRuntimeEventBus,
    inboxAtom: notificationInboxAtom,
    prefsAtom: notificationInboxPrefsAtom,
    paneAtom: store.paneAtom,
    contextResolver: paneContextResolver,
    focusTracker: paneFocusTracker
)

// 5. Wire debounced save on atom mutations
//    — observe notificationInboxAtom and notificationInboxPrefsAtom
//      via Observation.withObservationTracking; call
//      notificationInboxStore.scheduleDebouncedSave() on change.
//    Mirror how UIStateStore / RepoCacheStore do this in their
//    boot paths.

// 6. Propagate atoms through MainWindowController / SidebarSurfaceHost /
//    DrawerInboxBellHost / RepoExplorerWorktreeRow.
```

Retain references to the router and tracker so they aren't deallocated. Call `router.stop()` / `tracker.stop()` during application termination if the app has an explicit shutdown sequence.

- [ ] **Step 4: Build, test, lint, commit**

```bash
mise run build
mise run test
mise run lint
git add ...
git commit -m "feat(app): wire NotificationInbox boot + swap placeholder for real view

AppDelegate instantiates NotificationInboxAtom,
NotificationInboxPrefsAtom, NotificationInboxStore,
PaneContextResolver, PaneFocusTracker, and NotificationRouter;
loads the store; propagates atoms through MainWindowController
and SidebarSurfaceHost. Debounced save wired via observation
of both atoms. InboxPlaceholderView deleted — SidebarSurfaceHost
now renders InboxSidebarView in the .inbox case. LUNA-361
Phase 3."
```

---

## Task 16: Integration tests + Phase 3 verification

**Files:**
- Create: `Tests/AgentStudioTests/Integration/NotificationInboxIntegrationTests.swift`

Per spec §13, end-to-end tests proving emit → display.

- [ ] **Step 1: Emission to display integration**

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("Notification Inbox integration (emit → display)")
struct NotificationInboxIntegrationTests {

    @Test("desktopNotificationRequested on bus → atom has notification with context")
    func emitToAtom() async throws {
        // Wire the full chain: bus + router + atom + context resolver
        let paneAtom = WorkspacePaneAtom()
        let repoCache = RepoCacheAtom()
        let inbox = NotificationInboxAtom()
        let prefs = NotificationInboxPrefsAtom()
        let bus = EventBus<RuntimeEnvelope>()
        let paneFocus = PaneFocusTracker(paneAtom: paneAtom)
        let router = NotificationRouter(
            bus: bus,
            inboxAtom: inbox,
            prefsAtom: prefs,
            paneAtom: paneAtom,
            contextResolver: PaneContextResolver(
                paneAtom: paneAtom, repoCacheAtom: repoCache),
            focusTracker: paneFocus
        )

        // Seed a pane with known context
        let paneId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        // ... wire paneAtom.register(...) and repoCache.setRepoName(...) ...

        // Post envelope
        let envelope = /* .terminal(.desktopNotificationRequested(
            title: "Codex done", body: "exit 0"))
            with source=.pane(paneId) */ fatalError()
        await bus.post(envelope)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(inbox.notifications.count == 1)
        let n = inbox.notifications[0]
        #expect(n.kind == .agentDesktopNotification)
        #expect(n.paneId == paneId)
        #expect(n.repoId == repoId)
        #expect(n.worktreeId == worktreeId)
        router.stop()
        paneFocus.stop()
    }

    @Test("click-through: activate notification → markRead + dispatch focusPane")
    func clickThrough() { /* ... */ }

    @Test("focus-gained on pane → auto-dismiss all notifications for that pane")
    func focusGainedAutoDismiss() { /* ... */ }

    @Test("Bridge inbox.post RPC → ends up in NotificationInboxAtom")
    func bridgeRPCEndToEnd() { /* ... */ }
}
```

Fill in envelope constructors and fixture helpers against the real APIs.

- [ ] **Step 2: Phase 3 verification matrix**

- [ ] `mise run test` — every test in the whole project passes.
- [ ] `mise run lint` — clean.
- [ ] Manual verification (launch app):
    - [ ] Emit an OSC 9/777 notification from a terminal (e.g., `printf '\033]777;notify;Test;Body\a'`) → notification appears in inbox sidebar, in worktree bell pill, and in drawer bell (if pane is in a drawer).
    - [ ] Click the notification in the inbox → focuses source pane, marks read, clears from drawer.
    - [ ] Press ⌘I → focus inbox → press ⌥F → search field focused → type "test" → filtered results.
    - [ ] ⌥G → grouping menu opens → select "By repo" → list regroups.
    - [ ] ⌥S → sort toggle flips.
    - [ ] Arrow down → focus moves into list → Enter → focuses source pane.
    - [ ] Space on a row → toggles read/unread.
    - [ ] Open CommandBar (⌘P) with inbox focused → scope defaults to .inbox → pick "Mark all as read" → all marked read.
    - [ ] Disable bell via CommandBar action → fire a Ghostty bell → no notification.
    - [ ] Enable bell → fire Ghostty bell → bellRang notification appears.
    - [ ] Focus a pane inside a drawer → ⌘⇧I → drawer inbox popover opens.
    - [ ] Quit and relaunch → notifications and prefs persist.
    - [ ] Restore corruption test: manually delete `notification-inbox.json` → relaunch → app works, inbox empty.
- [ ] Grep for dead references:
    - [ ] `grep -rn "InboxPlaceholderView" Sources/` → zero hits (file deleted + consumers updated).
    - [ ] `grep -rn "TODO.*Phase 3\|FIXME.*Phase 3" Sources/` → zero hits.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/Integration/
git commit -m "test: add notification inbox integration tests

End-to-end from EventBus emission through NotificationRouter
into NotificationInboxAtom, plus click-through routing, focus-
gained auto-dismissal, and Bridge inbox.post RPC roundtrip.
Completes LUNA-361 Phase 3 test coverage."
```

---

## Final Phase 3 commit (release cut)

After all 16 tasks land and the verification matrix is green:

```bash
git tag luna361-phase3-complete
```

(Tag is optional — use if the team tags phase-complete milestones.)

---

## Scope boundaries (what is explicitly NOT in Phase 3)

- ✗ **macOS UNUserNotificationCenter** — separate follow-up ticket.
- ✗ **Cross-workspace aggregation** — deferred.
- ✗ **SharedComponents/ rollout** — separate design-system ticket.
- ✗ **Repos-navigation keymap** (arrows, enter, etc. in repos sidebar) — future ticket; Phase 3 only adds repos-surface focus publishing, not a keymap.
- ✗ **Unified keyboard dispatcher** — deferred architectural debt.
- ✗ **Email / Slack / remote fan-out** — non-goal.
- ✗ **Rich notification content (images, actions beyond click-through)** — non-goal.
- ✗ **User-configurable routing UI beyond bell on/off** — non-goal.
- ✗ **Fuzzy search in inbox** — non-goal.
- ✗ **Collapsible group sections** — non-goal (groups are always expanded per design decision).
- ✗ **Toasts / banners / transient surfaces** — non-goal.

If anything above starts to creep in during Phase 3 execution, stop and flag. The boundary is deliberate.
