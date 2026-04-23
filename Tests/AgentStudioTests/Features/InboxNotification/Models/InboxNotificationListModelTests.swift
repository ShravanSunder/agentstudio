import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListModel")
struct InboxNotificationListModelTests {
    private func makeInboxNotification(
        id: UUID = UUID(),
        timestamp: Date,
        title: String,
        body: String? = nil,
        paneId: UUID? = nil,
        tabId: UUID? = nil,
        repoName: String? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil,
        isRead: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp,
            kind: .agentRpc,
            title: title,
            body: body,
            paneId: paneId,
            tabId: tabId,
            repoId: nil,
            repoName: repoName,
            worktreeId: nil,
            worktreeName: worktreeName,
            branchName: branchName,
            isRead: isRead,
            isDismissedFromDrawer: false
        )
    }

    @Test("builds ungrouped newest-first sections")
    func buildsUngroupedNewestFirstSections() {
        let older = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Older"
        )
        let newer = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Newer"
        )

        let model = InboxNotificationListModel(
            notifications: [older, newer],
            grouping: .none,
            sort: .newestFirst,
            searchText: ""
        )

        #expect(model.sections.count == 1)
        #expect(model.sections[0].id == "all")
        #expect(model.sections[0].label == nil)
        #expect(model.sections[0].notifications.map(\.title) == ["Newer", "Older"])
    }

    @Test("filters across title body and source context")
    func filtersAcrossTitleBodyAndSourceContext() {
        let matchingBody = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Build finished",
            body: "Contains needle"
        )
        let matchingRepo = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Other",
            repoName: "Needle Repo"
        )
        let nonmatching = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 300),
            title: "Other"
        )

        let model = InboxNotificationListModel(
            notifications: [matchingBody, matchingRepo, nonmatching],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "needle"
        )

        #expect(
            model.sections.flatMap(\.notifications).map(\.id) == [
                matchingBody.id,
                matchingRepo.id,
            ])
    }

    @Test("groups by repo with unread counts")
    func groupsByRepoWithUnreadCounts() {
        let betaUnread = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Beta unread",
            repoName: "beta",
            isRead: false
        )
        let alphaRead = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Alpha read",
            repoName: "alpha",
            isRead: true
        )
        let alphaUnread = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 300),
            title: "Alpha unread",
            repoName: "alpha",
            isRead: false
        )

        let model = InboxNotificationListModel(
            notifications: [betaUnread, alphaRead, alphaUnread],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.map(\.label) == ["alpha", "beta"])
        #expect(model.sections.map(\.unreadCount) == [1, 1])
        #expect(
            model.sections[0].notifications.map(\.title) == [
                "Alpha read",
                "Alpha unread",
            ])
    }

    @Test("finds group boundary target from focused row")
    func findsGroupBoundaryTargetFromFocusedRow() {
        let firstPane = UUID()
        let secondPane = UUID()
        let first = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "First",
            paneId: firstPane,
            worktreeName: "A"
        )
        let second = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Second",
            paneId: secondPane,
            worktreeName: "B"
        )
        let model = InboxNotificationListModel(
            notifications: [first, second],
            grouping: .byPane,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(
            model.groupBoundaryTarget(
                from: first.id,
                direction: InboxNotificationListNavigationDirection.next
            ) == second.id
        )
        #expect(
            model.groupBoundaryTarget(
                from: second.id,
                direction: InboxNotificationListNavigationDirection.previous
            ) == first.id
        )
        #expect(
            model.groupBoundaryTarget(
                from: second.id,
                direction: InboxNotificationListNavigationDirection.next
            ) == nil
        )
    }
}
