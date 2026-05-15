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

    @Test("repo grouping row hides repeated repo context and keeps tab and pane placement")
    func repoGroupingRowHidesRepeatedRepoContext() {
        let notification = makeNotification(
            repoName: "askluna",
            worktreeName: "feature/luna-287",
            tabDisplayLabel: "askluna",
            tabOrdinal: 1,
            paneDisplayLabel: "Ready (askluna)",
            paneOrdinal: 2
        )

        let display = InboxNotificationSourceDisplay(
            notification: notification,
            rowContext: .globalInbox,
            grouping: .byRepo
        )

        #expect(display.sourceLine == "Tab 1 · askluna")
        #expect(display.placementLine == "Pane 2 · Ready (askluna)")
    }

    @Test("tab grouping row keeps repo context and shows pane number with name")
    func tabGroupingRowKeepsRepoContextAndShowsPaneNumber() {
        let notification = makeNotification(
            repoName: "askluna",
            worktreeName: "feature/luna-287",
            tabDisplayLabel: "askluna",
            tabOrdinal: 1,
            paneDisplayLabel: "Ready (askluna)",
            paneOrdinal: 2
        )

        let display = InboxNotificationSourceDisplay(
            notification: notification,
            rowContext: .globalInbox,
            grouping: .byTab
        )

        #expect(display.sourceLine == "askluna · feature/luna-287")
        #expect(display.placementLine == "Pane 2 · Ready (askluna)")
    }

    @Test("pane grouping row keeps repo context and shows tab number with name")
    func paneGroupingRowKeepsRepoContextAndShowsTabNumber() {
        let notification = makeNotification(
            repoName: "askluna",
            worktreeName: "feature/luna-287",
            tabDisplayLabel: "askluna",
            tabOrdinal: 1,
            paneDisplayLabel: "Ready (askluna)",
            paneOrdinal: 2
        )

        let display = InboxNotificationSourceDisplay(
            notification: notification,
            rowContext: .globalInbox,
            grouping: .byPane
        )

        #expect(display.sourceLine == "askluna · feature/luna-287")
        #expect(display.placementLine == "Tab 1 · askluna")
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
        #expect(display.groupLabel(for: .byPane) == "Claude")
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

    @Test("blank notification title promotes body as primary display text")
    func blankNotificationTitlePromotesBodyAsPrimaryDisplayText() {
        let notification = makeNotification(
            title: "   ",
            body: "Agent output changed while you were away"
        )

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.primaryText == "Agent output changed while you were away")
        #expect(display.detailText == nil)
        #expect(display.searchText.contains("Agent output changed while you were away"))
    }

    @Test("source display hides generic unseen activity body details")
    func sourceDisplayHidesGenericUnseenActivityBodyDetails() {
        let notification = makeNotification(
            title: "New terminal activity",
            body: "Output appeared while you were away"
        )

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.primaryText == "New terminal activity")
        #expect(display.detailText == nil)
    }

    @Test("source display keeps specific body details")
    func sourceDisplayKeepsSpecificBodyDetails() {
        let notification = makeNotification(
            title: "Claude Code finished",
            body: "3 files changed"
        )

        let display = InboxNotificationSourceDisplay(notification: notification, rowContext: .globalInbox)

        #expect(display.detailText == "3 files changed")
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
        title: String = "Claude Code",
        body: String? = "Claude is waiting for your input",
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil,
        parentPaneId: UUID? = nil,
        tabDisplayLabel: String? = nil,
        tabOrdinal: Int? = nil,
        paneDisplayLabel: String? = nil,
        paneOrdinal: Int? = nil,
        paneRole: InboxNotification.PaneSource.PaneRole = .main,
        parentPaneDisplayLabel: String? = nil,
        parentPaneOrdinal: Int? = nil,
        drawerOrdinal: Int? = nil,
        runtimeDisplayLabel: String? = "Terminal"
    ) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: title,
            body: body,
            source: .pane(
                .init(
                    paneId: UUID(),
                    tabId: UUID(),
                    tabDisplayLabel: tabDisplayLabel,
                    tabOrdinal: tabOrdinal,
                    repoId: repoId,
                    repoName: repoName,
                    worktreeId: worktreeId,
                    worktreeName: worktreeName,
                    branchName: branchName,
                    paneDisplayLabel: paneDisplayLabel,
                    paneOrdinal: paneOrdinal,
                    paneRole: paneRole,
                    parentPaneId: parentPaneId,
                    parentPaneDisplayLabel: parentPaneDisplayLabel,
                    parentPaneOrdinal: parentPaneOrdinal,
                    drawerOrdinal: drawerOrdinal,
                    runtimeDisplayLabel: runtimeDisplayLabel
                )
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
