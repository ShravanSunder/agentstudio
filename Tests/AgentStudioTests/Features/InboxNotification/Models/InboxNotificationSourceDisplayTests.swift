import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationSourceDisplay")
struct InboxNotificationSourceDisplayTests {
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

    @Test("legacy pane display falls back to pane-scoped labels")
    func legacyPaneDisplayFallsBackToPaneScopedLabels() {
        let notification = makeNotification(runtimeDisplayLabel: nil)

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.sourceLine == "Pane event")
        #expect(display.groupLabel(for: .byRepo) == "Pane")
        #expect(display.groupLabel(for: .byTab) == "Pane")
        #expect(display.groupLabel(for: .byPane) == "Pane")
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
