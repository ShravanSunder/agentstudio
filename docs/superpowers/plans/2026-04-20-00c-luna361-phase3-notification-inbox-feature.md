# LUNA-361 Phase 3 — Notification Inbox Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the notification inbox feature end-to-end on top of the Phase 1 shell (UIStateAtom composition state + `SidebarSurfaceHost`) and the Phase 2 `KeyboardOwner` plumbing (CommandBar default-scope). At the end of Phase 3: agents and CLI tools can emit notifications that appear in the sidebar Inbox, per-drawer popover, sidebar bell badges, and an in-app log that's searchable / sortable / groupable with full keymap.

**Architecture:** Feature slice at `Features/InboxNotification/` — self-contained. Two feature atoms (`InboxNotificationAtom` for the log, `InboxNotificationPrefsAtom` for user prefs), one feature store wrapping both, one leaf `InboxNotificationRouter` subscribing to `EventBus<RuntimeEnvelope>`, a `PaneFocusTracker` diffing `WorkspacePaneAtom.activePaneId` transitions, plus SwiftUI views for the sidebar and drawer popover. Bridge feature grows an `inbox.post` RPC method; Core drawer views grow a `TrailingActions` bell slot; CommandBar registers `.inbox`-scoped actions. No composition state lives here — that's on `UIStateAtom` in Core (Phase 1). All paths per `docs/architecture/directory_structure.md` feature-slice self-containment rules.

**Tech Stack:** Swift 6.2 · SwiftUI · Swift Testing · existing `EventBus<RuntimeEnvelope>` · existing `RPCRouter` · `@Observable @MainActor` atoms · `AppPolicies.InboxNotification.maxRetained` (added)

**Depends on:** Phase 1 (composition state, RepoExplorer rename, `SidebarSurfaceHost`, `InboxNotificationPlaceholderView`). Phase 2 (`KeyboardOwner`, `KeyboardOwnerDerived`, `.inbox` CommandBar scope registered).

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
Features/InboxNotification/                              [NEW FULL SLICE]
├── Models/
│   └── InboxNotification.swift                               [NEW]
├── Components/
│   ├── InboxRow.swift                                   [NEW]
│   ├── InboxNotificationGroupHeader.swift                           [NEW]
│   └── InboxNotificationEmptyState.swift                            [NEW]
├── Routing/
│   ├── InboxNotificationRouter.swift                         [NEW]
│   └── PaneFocusTracker.swift                           [NEW]
├── State/
│   └── MainActor/
│       ├── Atoms/
│       │   ├── InboxNotificationAtom.swift              [NEW]
│       │   └── InboxNotificationPrefsAtom.swift         [NEW]
│       └── Persistence/
│           └── InboxNotificationStore.swift             [NEW]
└── Views/
    ├── InboxNotificationSidebarView.swift                           [NEW]
    ├── InboxNotificationDrawerPopover.swift                         [NEW]
    ├── InboxNotificationDrawerBellHost.swift                        [NEW]
    └── InboxNotificationPlaceholderView.swift                       [DELETE]

Core/Models/
├── InboxNotificationTypes.swift                         [NEW] Grouping + Sort
│                                                              enums; Core-resident
│                                                              because Notification-
│                                                              InboxCommands
│                                                              references them
│                                                              (spec §8.5.2)
└── InboxNotificationCommands.swift                      [NEW] callback bundle +
                                                                read snapshots;
                                                                cross-feature seam
                                                                for Features/
                                                                CommandBar/

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
                                                                scope actions via
                                                                InboxNotification-
                                                                Commands seam (NO
                                                                atom imports)

Features/RepoExplorer/
├── RepoExplorerWorktreeRow.swift                        [MOD] 🔔 N pill takes
│                                                                Int unreadCount
│                                                                prop — NO atom
│                                                                import (spec §8.5.1)
└── RepoExplorerView.swift                               [MOD] accepts a
                                                                 (Worktree) -> Int
                                                                 closure to pass
                                                                 counts through

App/Boot/
└── AppDelegate.swift                                    [MOD] instantiate atoms
                                                                + store + router
                                                                + tracker; inject
                                                                into views

App/Commands/
├── AppCommand.swift                                     [MOD] + .showDrawerInboxNotifications
└── AppShortcut.swift                                    [MOD] bind ⌘⇧I

App/Windows/
└── SidebarSurfaceHost.swift                             [MOD] swap Inbox-
                                                                PlaceholderView
                                                                for Inbox-
                                                                SidebarView

Tests — full §13 coverage in Tests/AgentStudioTests/Features/InboxNotification/
(plus integration in Tests/AgentStudioTests/Integration/)
```

---

## Task order rationale

1. **Data types** (Notification, InboxNotificationKind, Grouping, Sort enums) — no dependencies.
2. **`InboxNotificationAtom`** — the log + queries + mutations.
3. **`InboxNotificationPrefsAtom`** — grouping/sort/bellEnabled.
4. **`InboxNotificationStore`** — persists both atoms.
5. **`PaneFocusTracker`** — diffs focus transitions; emits a stream.
6. **`InboxNotificationRouter`** — subscribes to EventBus, applies §7 routing, writes atom.
7. **Bridge RPC `inbox.post` handler.**
8. **`InboxRow` / `InboxNotificationGroupHeader` / `InboxNotificationEmptyState` components.**
9. **`InboxNotificationSidebarView`** — composes components, declares `InboxFocus`, publishes `sidebarHasFocus`, attaches the `⌥F`/`⌥G`/`⌥S`/arrows/Enter/Space keymap.
10. **`DrawerOverlay.TrailingActions` extension + `DrawerIconBar` bell rendering.**
11. **`InboxNotificationDrawerBellHost` + `InboxNotificationDrawerPopover`.**
12. **`RepoExplorerWorktreeRow` 🔔 N pill binding.**
13. **CommandBar `.inbox` scope actions populated.**
14. **⌘⇧I composite command + `AppDelegate` dispatch handler.**
15. **`SidebarSurfaceHost` swap + `AppDelegate` boot wiring + `InboxNotificationPlaceholderView` deletion.**
16. **Integration tests + Phase 3 verification.**

---

## Task 1: Data types (Notification, InboxNotificationKind, Grouping, Sort)

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`
- Create: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationTypes.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Models/NotificationTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentStudioTests/Features/InboxNotification/Models/NotificationTests.swift`:

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
        let original = InboxNotification(
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
        let decoded = try decoder.decode(InboxNotification.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.kind == original.kind)
        #expect(decoded.repoName == original.repoName)
        #expect(decoded.isRead == original.isRead)
        #expect(decoded.isDismissedFromDrawer == original.isDismissedFromDrawer)
    }

    @Test("InboxNotificationKind enumerates expected cases")
    func kindCases() {
        let _: InboxNotificationKind = .agentDesktopNotification
        let _: InboxNotificationKind = .bellRang
        let _: InboxNotificationKind = .commandFinished
        let _: InboxNotificationKind = .agentRpc
        let _: InboxNotificationKind = .approvalRequested
        let _: InboxNotificationKind = .securityEvent
    }

    @Test("InboxNotificationGrouping enumerates expected cases")
    func groupingCases() {
        let _: InboxNotificationGrouping = .none
        let _: InboxNotificationGrouping = .byRepo
        let _: InboxNotificationGrouping = .byPane
        let _: InboxNotificationGrouping = .byTab
    }

    @Test("InboxNotificationSort enumerates expected cases")
    func sortCases() {
        let _: InboxNotificationSort = .newestFirst
        let _: InboxNotificationSort = .oldestFirst
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test -- --filter NotificationTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `InboxNotification.swift`**

Create `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift`:

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
    let kind: InboxNotificationKind
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
enum InboxNotificationKind: String, Sendable, Codable, Equatable {
    case agentDesktopNotification      // Ghostty OSC 9/777
    case bellRang                      // Ghostty bell
    case commandFinished               // Ghostty command completion, gated
    case agentRpc                      // Bridge RPC inbox.post
    case approvalRequested             // ArtifactEvent.approvalRequested
    case securityEvent                 // Filtered SecurityEvent subset (§7)
}
```

- [ ] **Step 4: Create `InboxNotificationTypes.swift` in Core/Models**

Per spec §8.5.2, `InboxNotificationGrouping` and `InboxNotificationSort` live in **Core** (not the feature slice) because `InboxNotificationCommands` (Task 13) references them and that struct is Core-resident. The enums are pure codable tags with no feature-specific logic.

Create `Sources/AgentStudio/Core/Models/InboxNotificationTypes.swift`:

```swift
import Foundation

/// How the notification inbox list is grouped. User preference;
/// persisted via InboxNotificationStore.
///
/// Lives in Core because `InboxNotificationCommands` (also in
/// Core) references it — so `Features/CommandBar/` can consume
/// inbox prefs without importing `Features/InboxNotification/`.
/// See spec §8.5.2.
enum InboxNotificationGrouping: String, Sendable, Codable, Equatable, CaseIterable {
    case none
    case byRepo
    case byPane
    case byTab
}

/// How the notification inbox list is sorted. User preference;
/// persisted via InboxNotificationStore.
///
/// Same Core placement rationale as InboxNotificationGrouping.
enum InboxNotificationSort: String, Sendable, Codable, Equatable, CaseIterable {
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
git add Sources/AgentStudio/Features/InboxNotification/Models/InboxNotification.swift \
        Sources/AgentStudio/Core/Models/InboxNotificationTypes.swift \
        Tests/AgentStudioTests/Features/InboxNotification/Models/
git commit -m "feat(notification-inbox): add Notification + support enums

Notification record with denormalized source context,
InboxNotificationKind (the six routed event classifications),
InboxNotificationGrouping (.none/.byRepo/.byPane/.byTab), and
InboxNotificationSort (.newestFirst/.oldestFirst). All feature-
scoped under Features/InboxNotification/Models/. LUNA-361 Phase 3."
```

---

## Task 2: `InboxNotificationAtom` — the log

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationAtomTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationAtomTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("InboxNotificationAtom")
struct InboxNotificationAtomTests {

    private func makeInboxNotification(
        id: UUID = UUID(),
        paneId: UUID? = nil,
        worktreeId: UUID? = nil,
        tabId: UUID? = nil,
        isRead: Bool = false,
        isDismissedFromDrawer: Bool = false,
        timestamp: Date = Date()
    ) -> Notification {
        InboxNotification(
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
        let atom = InboxNotificationAtom()
        #expect(atom.notifications.count == 0)
        atom.append(makeInboxNotification())
        #expect(atom.notifications.count == 1)
    }

    @Test("markRead(id:) sets isRead true")
    func markReadById() {
        let atom = InboxNotificationAtom()
        let n = makeInboxNotification()
        atom.append(n)
        #expect(atom.notifications[0].isRead == false)
        atom.markRead(id: n.id)
        #expect(atom.notifications[0].isRead == true)
    }

    @Test("markRead(paneId:) marks all notifications for that pane")
    func markReadByPane() {
        let paneA = UUID()
        let paneB = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: paneA))
        atom.append(makeInboxNotification(paneId: paneA))
        atom.append(makeInboxNotification(paneId: paneB))

        atom.markRead(paneId: paneA)

        #expect(atom.notifications[0].isRead == true)
        #expect(atom.notifications[1].isRead == true)
        #expect(atom.notifications[2].isRead == false)
    }

    @Test("markAllRead sets isRead true on every entry")
    func markAllRead() {
        let atom = InboxNotificationAtom()
        for _ in 0..<5 { atom.append(makeInboxNotification()) }
        atom.markAllRead()
        #expect(atom.notifications.allSatisfy { $0.isRead })
    }

    @Test("dismissFromDrawer(id:) sets flag true")
    func dismissFromDrawerById() {
        let atom = InboxNotificationAtom()
        let n = makeInboxNotification()
        atom.append(n)
        atom.dismissFromDrawer(id: n.id)
        #expect(atom.notifications[0].isDismissedFromDrawer == true)
    }

    @Test("dismissFromDrawer(paneId:) sets flag true for every pane entry")
    func dismissFromDrawerByPane() {
        let paneA = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: paneA))
        atom.append(makeInboxNotification(paneId: paneA))
        atom.dismissFromDrawer(paneId: paneA)
        #expect(atom.notifications.allSatisfy { $0.isDismissedFromDrawer })
    }

    @Test("toggleReadState flips the value")
    func toggleReadState() {
        let atom = InboxNotificationAtom()
        let n = makeInboxNotification()
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
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: paneA, isRead: false))
        atom.append(makeInboxNotification(paneId: paneA, isRead: true))
        atom.append(makeInboxNotification(paneId: paneB, isRead: false))
        #expect(atom.unreadCount(forPaneId: paneA) == 1)
        #expect(atom.unreadCount(forPaneId: paneB) == 1)
    }

    @Test("unreadCount(forWorktreeId:) counts matches")
    func unreadCountForWorktree() {
        let wtA = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(worktreeId: wtA, isRead: false))
        atom.append(makeInboxNotification(worktreeId: wtA, isRead: true))
        atom.append(makeInboxNotification(worktreeId: nil, isRead: false))
        #expect(atom.unreadCount(forWorktreeId: wtA) == 1)
    }

    @Test("unreadCount(forTabId:) counts matches")
    func unreadCountForTab() {
        let tabA = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(tabId: tabA, isRead: false))
        atom.append(makeInboxNotification(tabId: tabA, isRead: false))
        #expect(atom.unreadCount(forTabId: tabA) == 2)
    }

    @Test("unreadCount(forDrawerPaneIds:) sums across ids")
    func unreadCountForDrawer() {
        let p1 = UUID()
        let p2 = UUID()
        let p3 = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: p1, isRead: false))
        atom.append(makeInboxNotification(paneId: p2, isRead: false))
        atom.append(makeInboxNotification(paneId: p3, isRead: false))
        #expect(atom.unreadCount(forDrawerPaneIds: [p1, p2]) == 2)
    }

    @Test("globalUnreadCount counts all unread")
    func globalUnread() {
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(isRead: false))
        atom.append(makeInboxNotification(isRead: true))
        atom.append(makeInboxNotification(isRead: false))
        #expect(atom.globalUnreadCount == 2)
    }

    @Test("retention cap: inserting beyond cap evicts oldest")
    func retentionCap() {
        let atom = InboxNotificationAtom()
        let cap = AppPolicies.InboxNotification.maxRetained
        let base = Date(timeIntervalSince1970: 1_000_000)
        // Fill to cap with distinct timestamps
        for i in 0..<cap {
            atom.append(makeInboxNotification(
                timestamp: base.addingTimeInterval(TimeInterval(i))))
        }
        #expect(atom.notifications.count == cap)
        let oldestId = atom.notifications.first?.id
        // One more push
        atom.append(makeInboxNotification(
            timestamp: base.addingTimeInterval(TimeInterval(cap + 1))))
        #expect(atom.notifications.count == cap)
        #expect(atom.notifications.contains(where: { $0.id == oldestId }) == false,
                "oldest entry should be evicted")
    }

    @Test("clearReadHistory removes read entries, keeps unread")
    func clearReadHistory() {
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(isRead: true))
        atom.append(makeInboxNotification(isRead: false))
        atom.append(makeInboxNotification(isRead: true))
        atom.clearReadHistory()
        #expect(atom.notifications.count == 1)
        #expect(atom.notifications[0].isRead == false)
    }

    @Test("clearAll removes everything")
    func clearAll() {
        let atom = InboxNotificationAtom()
        for _ in 0..<3 { atom.append(makeInboxNotification()) }
        atom.clearAll()
        #expect(atom.notifications.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test -- --filter InboxNotificationAtomTests`
Expected: FAIL — atom does not exist.

- [ ] **Step 3: Create `InboxNotificationAtom.swift`**

Create `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`:

```swift
import Foundation
import Observation

/// Canonical mutable state for the notification log.
///
/// `@Observable @MainActor`. Reads are `private(set)`; mutations
/// go through methods (valtio pattern). Never touches disk —
/// persistence lives in `InboxNotificationStore`.
///
/// Retention cap is `AppPolicies.InboxNotification
/// .maxRetained`. When append would exceed the cap,
/// the oldest entry by timestamp is evicted.
///
/// See spec §4.3.
@MainActor
@Observable
final class InboxNotificationAtom {

    // MARK: - State

    private(set) var notifications: [InboxNotification] = []

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

    func append(_ notification: InboxNotification) {
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
        let cap = AppPolicies.InboxNotification.maxRetained
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

Run: `mise run test -- --filter InboxNotificationAtomTests`
Expected: PASS (all tests)

- [ ] **Step 5: Lint**

Run: `mise run lint`

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift \
        Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationAtomTests.swift
git commit -m "feat(notification-inbox): add InboxNotificationAtom

@Observable @MainActor log. private(set) reads, method-gated
mutation. Derived unreadCount queries across paneId, worktree-
Id, tabId, and [paneIds] dimensions, plus globalUnreadCount.
Retention cap enforced via AppPolicies.InboxNotification
.maxRetained — oldest-by-timestamp evicted on
overflow. LUNA-361 Phase 3."
```

---

## Task 3: `InboxNotificationPrefsAtom`

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationPrefsAtom.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationPrefsAtomTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import AgentStudio

@MainActor
@Suite("InboxNotificationPrefsAtom")
struct InboxNotificationPrefsAtomTests {

    @Test("defaults")
    func defaults() {
        let atom = InboxNotificationPrefsAtom()
        #expect(atom.grouping == .none)
        #expect(atom.sort == .newestFirst)
        #expect(atom.bellEnabled == false)
    }

    @Test("setGrouping")
    func setGrouping() {
        let atom = InboxNotificationPrefsAtom()
        atom.setGrouping(.byRepo)
        #expect(atom.grouping == .byRepo)
    }

    @Test("setSort")
    func setSort() {
        let atom = InboxNotificationPrefsAtom()
        atom.setSort(.oldestFirst)
        #expect(atom.sort == .oldestFirst)
    }

    @Test("setBellEnabled")
    func setBellEnabled() {
        let atom = InboxNotificationPrefsAtom()
        atom.setBellEnabled(true)
        #expect(atom.bellEnabled == true)
        atom.setBellEnabled(false)
        #expect(atom.bellEnabled == false)
    }
}
```

- [ ] **Step 2: Implement**

Create `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationPrefsAtom.swift`:

```swift
import Foundation
import Observation

/// User preferences for the notification inbox. Feature-scoped.
/// Persisted alongside `InboxNotificationAtom` in a single JSON
/// file via `InboxNotificationStore` (WorkspaceStore pattern —
/// one store wrapping multiple atoms that persist together).
@MainActor
@Observable
final class InboxNotificationPrefsAtom {
    private(set) var grouping: InboxNotificationGrouping = .none
    private(set) var sort: InboxNotificationSort = .newestFirst
    private(set) var bellEnabled: Bool = false

    func setGrouping(_ grouping: InboxNotificationGrouping) {
        self.grouping = grouping
    }

    func setSort(_ sort: InboxNotificationSort) {
        self.sort = sort
    }

    func setBellEnabled(_ enabled: Bool) {
        self.bellEnabled = enabled
    }
}
```

- [ ] **Step 3: Run tests, lint, commit**

```bash
mise run test -- --filter InboxNotificationPrefsAtomTests
mise run lint
git add ...
git commit -m "feat(notification-inbox): add InboxNotificationPrefsAtom

Feature-scoped user prefs: grouping, sort, bellEnabled.
Defaults: .none / .newestFirst / false. Persisted via
InboxNotificationStore alongside the log atom. LUNA-361 Phase 3."
```

---

## Task 4: `InboxNotificationStore` (persists both atoms)

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("InboxNotificationStore")
struct InboxNotificationStoreTests {

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
        let atom1 = InboxNotificationAtom()
        let prefs1 = InboxNotificationPrefsAtom()
        let clock = TestClock()
        let store1 = InboxNotificationStore(
            inboxAtom: atom1,
            prefsAtom: prefs1,
            fileURL: url,
            clock: clock
        )
        let note = InboxNotification(
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

        let atom2 = InboxNotificationAtom()
        let prefs2 = InboxNotificationPrefsAtom()
        let store2 = InboxNotificationStore(
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
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
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

Create `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`:

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
final class InboxNotificationStore {
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom

    private let fileURL: URL
    private let clock: any Clock<Duration>
    private let debounceDuration: Duration
    private var debouncedSaveTask: Task<Void, Never>?

    init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
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
        var notifications: [InboxNotification]
        var prefs: Prefs

        struct Prefs: Codable {
            var grouping: InboxNotificationGrouping
            var sort: InboxNotificationSort
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
        // (InboxNotificationAtom's retention cap enforces size.)
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
mise run test -- --filter InboxNotificationStoreTests
mise run lint
git add Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/ \
        Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationStoreTests.swift
git commit -m "feat(notification-inbox): add InboxNotificationStore

One store wrapping both feature atoms (log + prefs). JSON
persistence to workspace bundle path ~/.agentstudio/workspaces/
<id>/notification-inbox.json. Missing-file load is a no-op
(defaults). Debounced save helper — wired to atom mutations
by AppDelegate boot sequencing. LUNA-361 Phase 3."
```

---

## Task 5: `PaneFocusTracker`

Emits an `AsyncStream<PaneId>` of focus-gained transitions by diffing `WorkspacePaneAtom.activePaneId`. Consumed by `InboxNotificationRouter` to auto-dismiss notifications when the user focuses their source pane.

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Routing/PaneFocusTracker.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Routing/PaneFocusTrackerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("PaneFocusTracker")
struct PaneFocusTrackerTests {

    /// Drain up to `expected` events from the stream with a
    /// bounded number of runloop cycles. No wall-clock sleep.
    /// If fewer events arrive than expected within the bound,
    /// returns what was collected.
    private func collect(
        from tracker: PaneFocusTracker,
        expected: Int,
        maxIterations: Int = 50
    ) async -> [UUID] {
        var collected: [UUID] = []
        // AsyncStream delivers on whichever actor is iterating; we
        // drain synchronously within the test by yielding the
        // runloop a bounded number of times.
        let task = Task { @MainActor in
            for await id in tracker.focusGainedStream {
                collected.append(id)
                if collected.count >= expected { break }
            }
        }
        for _ in 0..<maxIterations where collected.count < expected {
            await Task.yield()
        }
        task.cancel()
        return collected
    }

    @Test("emits paneId on transition A → B")
    func emitsOnTransition() async {
        let paneAtom = WorkspacePaneAtom()
        let tracker = PaneFocusTracker(paneAtom: paneAtom)
        let paneA = UUID()
        let paneB = UUID()

        paneAtom.setActivePaneId(paneA)   // adjust to real setter
        // Let the onChange + re-register hop finish.
        await Task.yield()
        paneAtom.setActivePaneId(paneB)
        await Task.yield()

        let collected = await collect(from: tracker, expected: 2)
        #expect(collected == [paneA, paneB])
        tracker.stop()
    }

    @Test("does not emit when activePaneId stays the same")
    func noEmitOnNoChange() async {
        let paneAtom = WorkspacePaneAtom()
        let tracker = PaneFocusTracker(paneAtom: paneAtom)
        let paneA = UUID()

        paneAtom.setActivePaneId(paneA)
        await Task.yield()
        // Same paneId again — must not emit
        paneAtom.setActivePaneId(paneA)
        await Task.yield()

        let collected = await collect(
            from: tracker, expected: 2, maxIterations: 10)
        #expect(collected == [paneA],
                "only the initial transition should emit; same-value writes must not")
        tracker.stop()
    }
}
```

Adjust `WorkspacePaneAtom` accessor names (`setActivePaneId`) to match the real atom API — grep the codebase.

**Why `Task.yield()` instead of `Task.sleep(...)`:** per `AGENTS.md` "No Wall-Clock Tests," tests must wait for events, not for arbitrary time. The tracker's `onChange` closure schedules a `Task { @MainActor ... }`; yielding the runloop a bounded number of times gives that task a chance to run without tying the test to a specific wall-clock budget. If the test still flakes, the answer is NOT to add sleep — it's to expose a deterministic seam (e.g., an injected re-register callback) for tests to drive.

- [ ] **Step 2: Implement**

Create `Sources/AgentStudio/Features/InboxNotification/Routing/PaneFocusTracker.swift`:

```swift
import Foundation
import Observation

/// Observes `WorkspacePaneAtom.activePaneId` transitions and
/// emits the gained paneId via an `AsyncStream`.
///
/// `WorkspaceFocusDerived` is snapshot-only — it does not emit
/// transition events. This tracker closes that gap for
/// consumers (primarily `InboxNotificationRouter`) that need to
/// react to "user focused pane X."
///
/// Event-driven via `withObservationTracking` + `onChange`
/// re-registration. No polling, no sleeps. Matches the existing
/// pattern at:
///   - `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
///     line ~85 ("withObservationTracking fires once per
///     registration, so we re-register")
///   - `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
///     line ~116
///   - `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
///     line ~345
///
/// Grep `withObservationTracking` in the codebase before
/// implementing to confirm the idiom is unchanged since this
/// plan was written.
@MainActor
final class PaneFocusTracker {
    private let paneAtom: WorkspacePaneAtom
    private let continuation: AsyncStream<UUID>.Continuation
    let focusGainedStream: AsyncStream<UUID>

    private var lastActivePaneId: UUID?
    private var isStopped: Bool = false

    init(paneAtom: WorkspacePaneAtom) {
        self.paneAtom = paneAtom
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        self.focusGainedStream = stream
        self.continuation = continuation
        // Seed lastActivePaneId with the current value so the first
        // real transition registers correctly.
        self.lastActivePaneId = paneAtom.activePaneId
        observe()
    }

    /// Register a one-shot observation. When `activePaneId`
    /// changes, `onChange` fires on the main actor; we handle
    /// the transition and re-register to catch the next change.
    /// No polling.
    private func observe() {
        guard !isStopped else { return }
        withObservationTracking {
            // Read-to-register. Swift observation tracks whichever
            // properties we access inside the closure.
            _ = paneAtom.activePaneId
        } onChange: { [weak self] in
            // onChange is delivered off-main by Swift observation;
            // hop back to main to touch @MainActor state and
            // re-register safely.
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.handleTransition()
                self.observe()   // re-register for the next change
            }
        }
    }

    private func handleTransition() {
        let current = paneAtom.activePaneId
        defer { lastActivePaneId = current }
        guard current != lastActivePaneId,
              let gainedId = current
        else { return }
        continuation.yield(gainedId)
    }

    func stop() {
        isStopped = true
        continuation.finish()
    }
}
```

**Pattern notes:**

- `withObservationTracking`'s `onChange` closure fires exactly once per registration, then the tracking is torn down. To keep observing we re-register from inside `onChange`. This is the codebase convention (`TabBarAdapter.swift:85` has an explicit comment calling it out).
- `onChange` is not guaranteed to run on the main actor — the `Task { @MainActor ... }` hop is necessary before touching any `@MainActor` state.
- Avoid busy-loops (`while !Task.isCancelled { sleep }`) entirely — they waste main-actor CPU and can reorder or drop transitions under load.
- If you discover the codebase has a wrapper utility (`ValueStream`, a generic `observe(_:)` helper, etc.) that encapsulates this pattern, use it. Grep first.

**Tests** can rely on synchronous propagation: after `paneAtom.setActivePaneId(x)`, the `onChange` closure schedules a `Task { @MainActor }` which resolves on the next runloop cycle. Use a bounded-wait primitive (`await fulfillment(of:)`, `TestClock.advance`, or a small `await Task.yield()` loop bounded by iteration count) rather than `Task.sleep(for:)` for deterministic tests. Per `AGENTS.md` "No Wall-Clock Tests."

- [ ] **Step 3: Tests, lint, commit**

```bash
mise run test -- --filter PaneFocusTrackerTests
mise run lint
git add ...
git commit -m "feat(notification-inbox): add PaneFocusTracker

Observes WorkspacePaneAtom.activePaneId transitions and emits
the gained paneId via AsyncStream<UUID>. Closes the gap left
by WorkspaceFocusDerived being snapshot-only. Consumed by
InboxNotificationRouter to auto-dismiss notifications when the user
focuses their source pane. LUNA-361 Phase 3."
```

---

## Task 6: `InboxNotificationRouter`

The leaf bus subscriber. Implements the §7 routing contract: reads `EventBus<RuntimeEnvelope>` events, gates them per the contract, enriches with repo/worktree/branch context, and appends to `InboxNotificationAtom`.

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`

- [ ] **Step 1: Read the EventBus and RuntimeEnvelope types**

```bash
grep -rn "class EventBus\|struct RuntimeEnvelope\|enum PaneRuntimeEvent" Sources/AgentStudio/Core/RuntimeEventSystem/
```

Confirm the types' public API before writing the router. Key things to identify:
- How to subscribe (`eventBus.subscribe()` or an `AsyncStream` accessor?)
- `RuntimeEnvelope.event` enum cases (`.terminal(.desktopNotificationRequested...)`, etc.)
- `RuntimeEnvelope.source` — how to extract paneId

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("InboxNotificationRouter routing contract (spec §7)")
struct InboxNotificationRouterTests {

    /// Lightweight fixture. The router under test needs an EventBus
    /// to subscribe to, a InboxNotificationAtom to write into, a
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
        let inboxAtom: InboxNotificationAtom
        let prefsAtom: InboxNotificationPrefsAtom
        let paneAtom: WorkspacePaneAtom
        let router: InboxNotificationRouter
    }

    // §7 row-by-row tests. Each posts an envelope on the bus, then
    // checks inboxAtom.notifications for the expected kind / count.
    // Per the spec, tests rely on an injected clock rather than
    // wall-clock sleeps.

    @Test("desktopNotificationRequested → agentDesktopNotification")
    func desktopInboxNotification() async throws {
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

- [ ] **Step 3: Implement `InboxNotificationRouter`**

Create `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`:

```swift
import Foundation

/// Leaf subscriber on EventBus<RuntimeEnvelope>. Applies the
/// §7 routing contract: maps incoming runtime events to
/// InboxNotification records (or discards them), enriches with
/// denormalized source context, and appends to
/// InboxNotificationAtom.
///
/// Also subscribes to PaneFocusTracker.focusGainedStream and
/// clears read + dismissed-from-drawer flags on focused panes.
///
/// See spec §7 (routing contract), §4.2 (dismissal rule), §8.3
/// (subscription pattern).
@MainActor
final class InboxNotificationRouter {

    private let bus: EventBus<RuntimeEnvelope>
    private let inboxAtom: InboxNotificationAtom
    private let prefsAtom: InboxNotificationPrefsAtom
    private let paneAtom: WorkspacePaneAtom
    private let contextResolver: PaneContextResolver
    private let focusTracker: PaneFocusTracker

    private var busTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?

    init(
        bus: EventBus<RuntimeEnvelope>,
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
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

    /// Returns the InboxNotificationKind if the envelope should produce
    /// a notification, nil otherwise. Implements spec §7 row-by-row.
    private func classify(_ envelope: RuntimeEnvelope) -> InboxNotificationKind? {
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
        kind: InboxNotificationKind,
        title: String,
        body: String?,
        paneId: UUID?
    ) {
        let context = paneId.flatMap {
            contextResolver.resolve(paneId: $0)
        }
        let note = InboxNotification(
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
mise run test -- --filter InboxNotificationRouterTests
mise run lint
git add Sources/AgentStudio/Features/InboxNotification/Routing/ \
        Tests/AgentStudioTests/Features/InboxNotification/Routing/
git commit -m "feat(notification-inbox): add InboxNotificationRouter

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
    - Add a new `PaneRuntimeEvent` case, e.g., `.bridgeInboxPost(title: String, body: String?)`. Requires updating `InboxNotificationRouter.classify(_:)` to match.
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
Consumed by InboxNotificationRouter as .agentRpc kind. LUNA-361
Phase 3."
```

---

## Task 8: Inbox components (`InboxRow`, `InboxNotificationGroupHeader`, `InboxNotificationEmptyState`)

Small SwiftUI views. Stateless — take a `InboxNotification` (or group descriptor) and render.

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
- Create: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- Create: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationEmptyState.swift`

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
    let notification: InboxNotification
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

- [ ] **Step 2: `InboxNotificationGroupHeader`**

```swift
import SwiftUI

struct InboxNotificationGroupHeader: View {
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

- [ ] **Step 3: `InboxNotificationEmptyState`**

```swift
import SwiftUI

struct InboxNotificationEmptyState: View {
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
git add Sources/AgentStudio/Features/InboxNotification/Components/
git commit -m "feat(notification-inbox): add InboxRow/GroupHeader/EmptyState components

Small stateless SwiftUI views following spec §6 row anatomy.
Reusable within the feature — feature-internal Components/
subdirectory per feature-slice self-containment rules.
LUNA-361 Phase 3."
```

---

## Task 9: `InboxNotificationSidebarView`

The main inbox screen. Composes components, declares `InboxFocus` (per spec §4.3 / §8.4), publishes `sidebarHasFocus`, attaches all keymap shortcuts, applies grouping + sort + search, handles click-through.

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`

- [ ] **Step 1: Implement the view**

Create `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`:

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

struct InboxNotificationSidebarView: View {

    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
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
            let next: InboxNotificationSort =
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
                let next: InboxNotificationSort =
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
                InboxNotificationEmptyState()
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
                        InboxNotificationGroupHeader(
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
            ForEach(InboxNotificationGrouping.allCases, id: \.self) { g in
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

    private var filtered: [InboxNotification] {
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

    private func sorted(_ list: [InboxNotification]) -> [InboxNotification] {
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
        let notifications: [InboxNotification]
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

    private func label(for g: InboxNotificationGrouping) -> String {
        switch g {
        case .none:   return "None"
        case .byRepo: return "By repo"
        case .byPane: return "By pane"
        case .byTab:  return "By tab"
        }
    }

    // MARK: - Actions

    private func activate(_ n: InboxNotification) {
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
@Test("InboxNotificationSidebarView instantiates")
func instantiates() {
    let inbox = InboxNotificationAtom()
    let prefs = InboxNotificationPrefsAtom()
    let uiState = UIStateAtom()
    let dispatcher = CommandDispatcher.makeForTest()  // or real
    let view = InboxNotificationSidebarView(
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
git add Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift \
        Tests/AgentStudioTests/Features/InboxNotification/Views/
git commit -m "feat(notification-inbox): add InboxNotificationSidebarView

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
11 InboxNotificationDrawerBellHost) injects the values. LUNA-361 Phase 3."
```

---

## Task 11: `InboxNotificationDrawerBellHost` + `InboxNotificationDrawerPopover`

**Files:**
- Create: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationDrawerBellHost.swift`
- Create: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationDrawerPopover.swift`

Per spec §3.2, the drawer popover is scoped to panes in the currently focused drawer. `InboxNotificationDrawerBellHost` is the Features-level wrapper that reads `InboxNotificationAtom.unreadCount(forDrawerPaneIds:)`, injects into `TrailingActions`, and attaches the popover presentation.

- [ ] **Step 1: Implement `InboxNotificationDrawerBellHost`**

```swift
import SwiftUI

/// Features-level wrapper around DrawerOverlay that supplies
/// the bell slot's unread count and open-popover action. Lives
/// in the feature slice because it reads InboxNotificationAtom.
/// Called by whatever instantiates DrawerOverlay (App or
/// per-pane view layer).
@MainActor
struct InboxNotificationDrawerBellHost<Content: View>: View {
    let drawerPaneIds: [UUID]  // the panes this drawer hosts
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let dispatcher: CommandDispatcher
    /// The DrawerOverlay (or equivalent) you want to host.
    let content: (DrawerOverlay.TrailingActions) -> Content

    @State private var popoverOpen: Bool = false

    var body: some View {
        content(trailingActions())
            .popover(isPresented: $popoverOpen, arrowEdge: .top) {
                InboxNotificationDrawerPopover(
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

- [ ] **Step 2: Implement `InboxNotificationDrawerPopover`**

```swift
import SwiftUI

struct InboxNotificationDrawerPopover: View {
    let drawerPaneIds: [UUID]
    let inboxAtom: InboxNotificationAtom
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

    private var relevant: [InboxNotification] {
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
                InboxNotificationEmptyState()
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
git add Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationDrawerBellHost.swift \
        Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationDrawerPopover.swift
git commit -m "feat(notification-inbox): add InboxNotificationDrawerBellHost + InboxNotificationDrawerPopover

Host wraps DrawerOverlay and injects inboxUnreadCount +
onOpenInbox into its TrailingActions (bell slot from Task 10).
Popover filters notifications to paneId in drawerPaneIds and
not isDismissedFromDrawer; clicking a row marks read +
dismisses from drawer and dispatches focusPane. LUNA-361
Phase 3."
```

---

## Task 12: `RepoExplorerWorktreeRow` 🔔 N pill — primitive `unreadCount` prop

**Files:**
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift` (passes the count through)
- Modify: `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift` (reads the atom, produces the counts)

**Boundary rule** per `docs/architecture/directory_structure.md` and spec §8.5.1: `Features/RepoExplorer/` MUST NOT import `Features/InboxNotification/`. The row receives a plain `Int` via prop; the App composition layer (`SidebarSurfaceHost`) is where the atom is read and counts are computed.

- [ ] **Step 1: Find the existing pill-render code**

```bash
grep -n "🔔\|bell\|notificationCount" Sources/AgentStudio/Features/RepoExplorer/
```

Today the pill likely shows a placeholder `0`. Replace with the injected count prop.

- [ ] **Step 2: Add `unreadCount: Int` prop — no atom reference**

```swift
struct RepoExplorerWorktreeRow: View {
    let worktree: Worktree
    let unreadCount: Int            // NEW — primitive prop, no atom import
    // ... existing fields ...

    var body: some View {
        // ... existing row content ...
        HStack {
            // ... other pills ...
            bellPill
        }
    }

    private var bellPill: some View {
        HStack(spacing: 2) {
            Image(systemName: "bell")
                .font(.system(size: 10))
            Text("\(unreadCount)")
                .font(.system(size: 10))
        }
        .foregroundStyle(unreadCount > 0 ? .red : .secondary)
    }
}
```

Verify: `grep -rn "InboxNotification" Sources/AgentStudio/Features/RepoExplorer/` returns **zero** results. The feature has no knowledge that an inbox exists.

- [ ] **Step 3: `RepoExplorerView` passes counts per worktree**

`RepoExplorerView` is already a feature-internal view. It receives a closure from its caller (`SidebarSurfaceHost`) that maps each worktree to its unread count. No atom reference either:

```swift
struct RepoExplorerView: View {
    // ... existing props ...
    let unreadCount: (Worktree) -> Int     // NEW — plain closure

    var body: some View {
        // ... existing layout ...
        ForEach(worktrees) { wt in
            RepoExplorerWorktreeRow(
                worktree: wt,
                unreadCount: unreadCount(wt),
                // ... existing props ...
            )
        }
    }
}
```

- [ ] **Step 4: `SidebarSurfaceHost` (App) resolves the count**

`SidebarSurfaceHost` in `App/Windows/` can import both `Features/RepoExplorer/` and `Features/InboxNotification/` — that's the composition layer's job.

```swift
// In SidebarSurfaceHost:
case .repos:
    RepoExplorerView(
        // ... existing props ...
        unreadCount: { [weak inboxAtom] wt in
            inboxAtom?.unreadCount(forWorktreeId: wt.id) ?? 0
        }
    )
```

Propagate `inboxAtom: InboxNotificationAtom` into `SidebarSurfaceHost`'s init (added in Task 15 boot wiring). `SidebarSurfaceHost` is App-level, so this import is legitimate.

- [ ] **Step 5: Verify boundary + run tests**

```bash
# Must return zero hits:
grep -rn "InboxNotificationAtom\|InboxNotificationPrefs" Sources/AgentStudio/Features/RepoExplorer/

mise run test -- --filter RepoExplorer
mise run lint
```

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/RepoExplorer/ \
        Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift
git commit -m "feat(repo-explorer): worktree bell pill binds to primitive unreadCount prop

RepoExplorerWorktreeRow takes Int unreadCount, not the atom,
so Features/RepoExplorer/ does not import Features/Notification-
Inbox/. The atom read lives in App/Windows/SidebarSurfaceHost,
which resolves counts per worktree and passes them via a closure
through RepoExplorerView. Preserves the Features/X -> Features/Y
import boundary. LUNA-361 Phase 3."
```

---

## Task 13: Populate `.inbox` CommandBar scope actions via `InboxNotificationCommands`

**Files:**
- Create: `Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift`
- Create: `Sources/AgentStudio/Core/Models/InboxNotificationTypes.swift` (move `InboxNotificationGrouping` + `InboxNotificationSort` from the feature slice)
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationPrefsAtom.swift` (import the enums from their new Core home)

**Boundary rule** per spec §8.5.2: `Features/CommandBar/` MUST NOT import `Features/InboxNotification/`. CommandBar consumes a `InboxNotificationCommands` struct — a callback bundle + read snapshots — that lives in `Core/Models/`. App composition constructs it with closures that capture the real atoms.

**Note on enum promotion:** Task 1 originally placed `InboxNotificationGrouping` and `InboxNotificationSort` inside `Features/InboxNotification/Models/`. Because `InboxNotificationCommands` (Core) references them, they must be promoted to `Core/Models/InboxNotificationTypes.swift`. The enums carry no feature-specific logic — pure codable tags — so this promotion is acceptable and was noted in spec §8.5.2. If this task executes after Task 1 has already landed files, `git mv` them.

- [ ] **Step 1: Move the enums to Core**

```bash
git mv Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationTypes.swift \
       Sources/AgentStudio/Core/Models/InboxNotificationTypes.swift
```

Update any consumer imports — grep and confirm the types still resolve (same module, just a different directory, so imports usually don't change).

- [ ] **Step 2: Create `InboxNotificationCommands` in Core**

Create `Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift`:

```swift
import Foundation

/// Callback bundle + read snapshots that let Core and other
/// features invoke notification-inbox actions without importing
/// `Features/InboxNotification/`.
///
/// Constructed by the App composition root (`App/Boot/
/// AppDelegate.swift`), which captures the feature atoms inside
/// the closures. Consumers hold the struct by value and invoke
/// closures without knowing about atoms.
///
/// See docs/superpowers/specs/2026-04-17-notification-inbox-design.md §8.5.2.
@MainActor
struct InboxNotificationCommands: Sendable {
    // Mutations
    var markAllAsRead: () -> Void
    var clearReadHistory: () -> Void
    var clearAll: () -> Void
    var setGrouping: (InboxNotificationGrouping) -> Void
    var toggleSort: () -> Void
    var toggleBellEnabled: () -> Void
    var returnToWorktreeSidebar: () -> Void

    // Read snapshots (for CommandBar label text like
    // "Enable bell" vs "Disable bell")
    var bellEnabled: () -> Bool
    var currentGrouping: () -> InboxNotificationGrouping
    var currentSort: () -> InboxNotificationSort
}
```

- [ ] **Step 3: Consume `InboxNotificationCommands` in `CommandBarDataSource`**

Modify `CommandBarDataSource.swift`. Replace the atom imports (there should be none now after the boundary fix) with a `InboxNotificationCommands` dependency:

```swift
final class CommandBarDataSource {
    // ... existing properties ...
    private let notificationInboxCommands: InboxNotificationCommands?

    init(
        // ... existing dependencies ...
        notificationInboxCommands: InboxNotificationCommands?
    ) {
        // ... existing assignments ...
        self.notificationInboxCommands = notificationInboxCommands
    }
}
```

`notificationInboxCommands` is optional so the CommandBar data source has a clear "inbox disabled" state (no inbox actions shown). App composition always provides it when the feature is alive.

Replace the `.inbox` scope case to use the callback bundle:

```swift
case .inbox:
    guard let cmds = notificationInboxCommands else { return [] }
    var rows: [CommandBarItem] = []

    rows.append(CommandBarItem(
        id: "inbox.markAllAsRead",
        label: "Mark all as read",
        icon: .system(name: "checkmark.circle"),
        action: { _ in cmds.markAllAsRead() }
    ))

    rows.append(CommandBarItem(
        id: "inbox.clearReadHistory",
        label: "Clear read history",
        icon: .system(name: "trash"),
        action: { _ in cmds.clearReadHistory() }
    ))

    rows.append(CommandBarItem(
        id: "inbox.clearAll",
        label: "Clear all notifications…",
        icon: .system(name: "trash.fill"),
        action: { ctx in
            ctx.confirm(
                message: "Clear all notifications?",
                onConfirm: { cmds.clearAll() }
            )
        }
    ))

    for grouping in InboxNotificationGrouping.allCases {
        rows.append(CommandBarItem(
            id: "inbox.grouping.\(grouping.rawValue)",
            label: "Change grouping: \(labelFor(grouping))",
            icon: .system(name: "line.3.horizontal"),
            action: { _ in cmds.setGrouping(grouping) }
        ))
    }

    rows.append(CommandBarItem(
        id: "inbox.toggleSort",
        label: "Toggle sort order",
        icon: .system(name: "arrow.up.arrow.down"),
        action: { _ in cmds.toggleSort() }
    ))

    let bellLabel = cmds.bellEnabled()
        ? "Disable bell notifications"
        : "Enable bell notifications"
    rows.append(CommandBarItem(
        id: "inbox.toggleBell",
        label: bellLabel,
        icon: .system(name: "bell"),
        action: { _ in cmds.toggleBellEnabled() }
    ))

    rows.append(CommandBarItem(
        id: "inbox.returnToWorktrees",
        label: "Return to worktree sidebar (⌘S)",
        icon: .system(name: "sidebar.left"),
        action: { _ in cmds.returnToWorktreeSidebar() }
    ))

    return rows
```

The `CommandBarDataSource` file contains **zero** imports or references to `InboxNotificationAtom` / `InboxNotificationPrefsAtom`. The only notification types it knows are the Core-resident `InboxNotificationGrouping` / `InboxNotificationSort` enums and the `InboxNotificationCommands` struct.

- [ ] **Step 4: Verify the boundary**

```bash
# All must return zero hits in Features/CommandBar/:
grep -rn "InboxNotificationAtom\|InboxNotificationPrefs" Sources/AgentStudio/Features/CommandBar/
grep -rn "import.*InboxNotification\|Features/InboxNotification" Sources/AgentStudio/Features/CommandBar/
```

- [ ] **Step 5: Tests**

Write a `CommandBarDataSourceInboxScopeTests.swift` that drives the data source with a fake `InboxNotificationCommands` (the test constructs one with capture-counters instead of real atoms):

```swift
@MainActor
@Suite("CommandBar .inbox scope actions")
struct CommandBarDataSourceInboxScopeTests {

    @Test("emits seven inbox-scoped action rows plus four grouping rows")
    func emitsExpectedRows() {
        let sink = InboxCommandsSink()
        let cmds = sink.makeCommands()
        let ds = CommandBarDataSource(
            // ... existing fixture ...,
            notificationInboxCommands: cmds
        )
        let rows = ds.items(for: .inbox, context: /* ... */)
        let ids = Set(rows.map(\.id))
        #expect(ids.contains("inbox.markAllAsRead"))
        #expect(ids.contains("inbox.clearReadHistory"))
        #expect(ids.contains("inbox.clearAll"))
        #expect(ids.contains("inbox.grouping.none"))
        #expect(ids.contains("inbox.grouping.byRepo"))
        #expect(ids.contains("inbox.grouping.byPane"))
        #expect(ids.contains("inbox.grouping.byTab"))
        #expect(ids.contains("inbox.toggleSort"))
        #expect(ids.contains("inbox.toggleBell"))
        #expect(ids.contains("inbox.returnToWorktrees"))
    }

    @Test("toggleBell label reflects current bell state")
    func bellLabel() {
        let sink = InboxCommandsSink()
        sink.bellEnabled = false
        let cmds = sink.makeCommands()
        let ds = CommandBarDataSource(
            // ... fixture ...,
            notificationInboxCommands: cmds
        )
        let rows = ds.items(for: .inbox, context: /* ... */)
        let bell = rows.first { $0.id == "inbox.toggleBell" }
        #expect(bell?.label == "Enable bell notifications")

        sink.bellEnabled = true
        let rows2 = ds.items(for: .inbox, context: /* ... */)
        let bell2 = rows2.first { $0.id == "inbox.toggleBell" }
        #expect(bell2?.label == "Disable bell notifications")
    }

    @Test("returns empty rows when notificationInboxCommands is nil")
    func disabled() {
        let ds = CommandBarDataSource(
            // ... fixture ...,
            notificationInboxCommands: nil
        )
        let rows = ds.items(for: .inbox, context: /* ... */)
        #expect(rows.isEmpty)
    }
}

/// Test-local stand-in — captures invocations without needing
/// the real feature atoms.
@MainActor
final class InboxCommandsSink {
    var bellEnabled: Bool = false
    var markAllAsReadCount = 0
    var setGroupingCalls: [InboxNotificationGrouping] = []
    // ... etc ...

    func makeCommands() -> InboxNotificationCommands {
        InboxNotificationCommands(
            markAllAsRead:       { self.markAllAsReadCount += 1 },
            clearReadHistory:    { },
            clearAll:            { },
            setGrouping:         { self.setGroupingCalls.append($0) },
            toggleSort:          { },
            toggleBellEnabled:   { self.bellEnabled.toggle() },
            returnToWorktreeSidebar: { },
            bellEnabled:     { self.bellEnabled },
            currentGrouping: { .none },
            currentSort:     { .newestFirst }
        )
    }
}
```

This test suite explicitly exercises the boundary: if someone accidentally reintroduces an atom import later, the test still passes (sink is self-contained), but `grep` guards catch it.

- [ ] **Step 6: Lint, commit**

```bash
mise run lint
git add Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift \
        Sources/AgentStudio/Core/Models/InboxNotificationTypes.swift \
        Sources/AgentStudio/Features/CommandBar/ \
        Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationPrefsAtom.swift \
        Tests/AgentStudioTests/Features/CommandBar/
git commit -m "feat(command-bar): populate .inbox scope via InboxNotificationCommands seam

Introduces InboxNotificationCommands in Core/Models — a
callback bundle + read snapshots that let CommandBar consume
inbox actions without importing the feature. Promotes
InboxNotificationGrouping and InboxNotificationSort to
Core/Models/InboxNotificationTypes.swift so the commands
struct can reference them without crossing feature boundaries.

Implements the seven inbox-scoped action rows from spec §5.2
through the commands struct. Features/CommandBar/ has ZERO
imports of Features/InboxNotification/ after this change.
LUNA-361 Phase 3."
```

---

## Task 14: ⌘⇧I composite command — drawer inbox popover

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift` — add `.showDrawerInboxNotifications`
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
ShortcutTrigger(key: "i", modifiers: [.command, .shift]): .showDrawerInboxNotifications,
```

- [ ] **Step 3: Implement the handler**

Per spec §3.2, `⌘⇧I` opens the drawer inbox popover **for the drawer of the currently focused pane**. If focus is not on a pane inside a drawer, the command is a no-op.

```swift
// In AppDelegate.perform(_ command:) dispatch switch:
case .showDrawerInboxNotifications:
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
    // depends on how InboxNotificationDrawerBellHost exposes its popover —
    // likely via a binding controlled by the view layer, so this
    // handler may route through a shared `drawerInboxPopover-
    // Presenter` object. Follow the existing pattern for other
    // keyboard-triggered popovers.
    drawerInboxPresenter.open(forDrawerPaneIds: drawer.paneIds)
}
```

If no clean mechanism exists to pop a SwiftUI popover from AppDelegate, store a small `@Published` / `@Observable` request ID on a singleton presenter atom (`InboxNotificationDrawerPresenterAtom`) that the `InboxNotificationDrawerBellHost` observes and translates into `popoverOpen = true`. Keep this minimal.

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
opens InboxNotificationDrawerPopover scoped to that drawer's paneIds. No-op
when focus is not on a pane inside a drawer. LUNA-361 Phase 3."
```

---

## Task 15: Swap placeholder, boot wiring, delete `InboxNotificationPlaceholderView`

**Files:**
- Modify: `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Delete: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationPlaceholderView.swift`

- [ ] **Step 1: Replace `InboxNotificationPlaceholderView` with `InboxNotificationSidebarView` in `SidebarSurfaceHost`**

```swift
// BEFORE (Phase 1)
case .inbox:
    InboxNotificationPlaceholderView()

// AFTER (Phase 3)
case .inbox:
    InboxNotificationSidebarView(
        inboxAtom: inboxAtom,
        prefsAtom: prefsAtom,
        uiState: uiState,
        dispatcher: dispatcher
    )
```

Propagate the new dependencies (`inboxAtom`, `prefsAtom`, `dispatcher`) through `SidebarSurfaceHost`'s init. Update its construction in `MainSplitViewController` accordingly.

- [ ] **Step 2: Delete the placeholder**

```bash
git rm Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationPlaceholderView.swift
```

- [ ] **Step 3: Wire the boot sequence in `AppDelegate.swift`**

Post-Phase-2 state: `AppDelegate` already awaits `UIStateStore.load()` and constructs `MainWindowController`. Extend:

```swift
// During applicationDidFinishLaunching, after store loads:

// 1. Instantiate feature atoms
let notificationInboxAtom = InboxNotificationAtom()
let notificationInboxPrefsAtom = InboxNotificationPrefsAtom()
let notificationInboxStore = InboxNotificationStore(
    inboxAtom: notificationInboxAtom,
    prefsAtom: notificationInboxPrefsAtom,
    fileURL: workspaceBundleURL.appendingPathComponent(
        "notification-inbox.json")
)
do {
    try notificationInboxStore.load()
} catch {
    // Greenfield: file missing or corrupt → defaults, no crash
    Logger.boot.error("InboxNotificationStore load failed: \(error)")
}

// 2. Wire PaneFocusTracker
let paneFocusTracker = PaneFocusTracker(paneAtom: store.paneAtom)

// 3. Wire PaneContextResolver
let paneContextResolver = PaneContextResolver(
    paneAtom: store.paneAtom,
    repoCacheAtom: store.repoCacheAtom
)

// 4. Wire InboxNotificationRouter
let notificationRouter = InboxNotificationRouter(
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

// 6. Construct the InboxNotificationCommands callback bundle
//    (spec §8.5.2 cross-feature seam). This is how Features/
//    CommandBar/ consumes inbox actions without importing the
//    feature atom.
let notificationInboxCommands = InboxNotificationCommands(
    markAllAsRead:       { [weak notificationInboxAtom] in
        notificationInboxAtom?.markAllRead()
    },
    clearReadHistory:    { [weak notificationInboxAtom] in
        notificationInboxAtom?.clearReadHistory()
    },
    clearAll:            { [weak notificationInboxAtom] in
        notificationInboxAtom?.clearAll()
    },
    setGrouping:         { [weak notificationInboxPrefsAtom] grouping in
        notificationInboxPrefsAtom?.setGrouping(grouping)
    },
    toggleSort:          { [weak notificationInboxPrefsAtom] in
        guard let p = notificationInboxPrefsAtom else { return }
        let next: InboxNotificationSort =
            p.sort == .newestFirst ? .oldestFirst : .newestFirst
        p.setSort(next)
    },
    toggleBellEnabled:   { [weak notificationInboxPrefsAtom] in
        guard let p = notificationInboxPrefsAtom else { return }
        p.setBellEnabled(!p.bellEnabled)
    },
    returnToWorktreeSidebar: { [weak commandDispatcher] in
        commandDispatcher?.dispatch(.showWorktreeSidebar)
    },
    bellEnabled:     { [weak notificationInboxPrefsAtom] in
        notificationInboxPrefsAtom?.bellEnabled ?? false
    },
    currentGrouping: { [weak notificationInboxPrefsAtom] in
        notificationInboxPrefsAtom?.grouping ?? .none
    },
    currentSort:     { [weak notificationInboxPrefsAtom] in
        notificationInboxPrefsAtom?.sort ?? .newestFirst
    }
)

// 7. Inject the commands into CommandBarDataSource. The data
//    source is already instantiated earlier in the boot path;
//    extend its constructor to accept an optional
//    InboxNotificationCommands and pass it here.
//    (If CommandBarDataSource construction currently happens
//     before the feature atoms are ready, restructure the boot
//     order so it happens after. The cyclic dependency is
//     only apparent — commands are closures that capture
//     lazily.)

// 8. Propagate through view layer:
//    - SidebarSurfaceHost receives notificationInboxAtom (to
//      read unreadCount(forWorktreeId:) and pass counts into
//      RepoExplorerView) and the prefs atom (to drive
//      InboxNotificationSidebarView).
//    - InboxNotificationDrawerBellHost receives both atoms + dispatcher
//      (it lives INSIDE Features/InboxNotification/ so atom
//      imports are fine there).
//    - RepoExplorerWorktreeRow does NOT receive atoms — only
//      a plain Int unreadCount (per Task 12).
```

Retain references to the router, tracker, and commands so they aren't deallocated. Call `router.stop()` / `tracker.stop()` during application termination if the app has an explicit shutdown sequence.

- [ ] **Step 4: Build, test, lint, commit**

```bash
mise run build
mise run test
mise run lint
git add ...
git commit -m "feat(app): wire InboxNotification boot + swap placeholder for real view

AppDelegate instantiates InboxNotificationAtom,
InboxNotificationPrefsAtom, InboxNotificationStore,
PaneContextResolver, PaneFocusTracker, and InboxNotificationRouter;
loads the store; propagates atoms through MainWindowController
and SidebarSurfaceHost. Debounced save wired via observation
of both atoms. InboxNotificationPlaceholderView deleted — SidebarSurfaceHost
now renders InboxNotificationSidebarView in the .inbox case. LUNA-361
Phase 3."
```

---

## Task 16: Integration tests + Phase 3 verification

**Files:**
- Create: `Tests/AgentStudioTests/Integration/InboxNotificationIntegrationTests.swift`

Per spec §13, end-to-end tests proving emit → display.

- [ ] **Step 1: Emission to display integration**

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("Notification Inbox integration (emit → display)")
struct InboxNotificationIntegrationTests {

    @Test("desktopNotificationRequested on bus → atom has notification with context")
    func emitToAtom() async throws {
        // Wire the full chain: bus + router + atom + context resolver
        let paneAtom = WorkspacePaneAtom()
        let repoCache = RepoCacheAtom()
        let inbox = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let bus = EventBus<RuntimeEnvelope>()
        let paneFocus = PaneFocusTracker(paneAtom: paneAtom)
        let router = InboxNotificationRouter(
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

    @Test("Bridge inbox.post RPC → ends up in InboxNotificationAtom")
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
    - [ ] `grep -rn "InboxNotificationPlaceholderView" Sources/` → zero hits (file deleted + consumers updated).
    - [ ] `grep -rn "TODO.*Phase 3\|FIXME.*Phase 3" Sources/` → zero hits.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/Integration/
git commit -m "test: add notification inbox integration tests

End-to-end from EventBus emission through InboxNotificationRouter
into InboxNotificationAtom, plus click-through routing, focus-
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
