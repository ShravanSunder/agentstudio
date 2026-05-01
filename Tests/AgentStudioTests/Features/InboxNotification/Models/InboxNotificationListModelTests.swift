import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListModel")
struct InboxNotificationListModelTests {
    private struct SourceContext {
        var paneId: UUID?
        var tabId: UUID?
        var repoId: UUID?
        var repoName: String?
        var worktreeId: UUID?
        var worktreeName: String?
        var branchName: String?
    }

    private func makeInboxNotification(
        id: UUID = UUID(),
        timestamp: Date,
        title: String,
        body: String? = nil,
        paneId: UUID? = nil,
        tabId: UUID? = nil,
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
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
            source: makeSource(
                SourceContext(
                    paneId: paneId,
                    tabId: tabId,
                    repoId: repoId,
                    repoName: repoName,
                    worktreeId: worktreeId,
                    worktreeName: worktreeName,
                    branchName: branchName
                )
            ),
            isRead: isRead,
            isDismissedFromPaneInbox: false
        )
    }

    private func makeSource(_ context: SourceContext) -> InboxNotification.Source {
        guard
            context.paneId != nil || context.tabId != nil || context.repoId != nil
                || context.repoName != nil || context.worktreeId != nil
                || context.worktreeName != nil || context.branchName != nil
        else {
            return .global
        }
        return .pane(
            .init(
                paneId: context.paneId ?? UUID(),
                tabId: context.tabId,
                repoId: context.repoId,
                repoName: context.repoName,
                worktreeId: context.worktreeId,
                worktreeName: context.worktreeName,
                branchName: context.branchName
            )
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
        #expect(model.sections[0].id == "__ungrouped__")
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

    @Test("filters by typed worktree filter")
    func filtersByTypedWorktreeFilter() {
        let matchingWorktreeId = UUID()
        let otherWorktreeId = UUID()
        let matching = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Matching",
            worktreeId: matchingWorktreeId,
            worktreeName: "main"
        )
        let nonmatching = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Other",
            worktreeId: otherWorktreeId,
            worktreeName: "feature"
        )

        let model = InboxNotificationListModel(
            notifications: [matching, nonmatching],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "",
            filter: .worktree(id: matchingWorktreeId)
        )

        #expect(model.sections.flatMap(\.notifications).map(\.id) == [matching.id])
    }

    @Test("missing source names are not synthesized from ids")
    func missingSourceNamesAreNotSynthesizedFromIds() {
        let repoId = UUID()
        let worktreeId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "No names",
            repoId: repoId,
            worktreeId: worktreeId
        )

        #expect(notification.repoName == nil)
        #expect(notification.worktreeName == nil)

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.map(\.id) == ["repo:\(repoId.uuidString)"])
        #expect(model.sections.map(\.label) == ["Unknown Repo"])
    }

    @Test("collapsed grouped sections keep unread counts but hide rows")
    func collapsedGroupedSectionsKeepUnreadCountsButHideRows() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Hidden row",
            repoName: "agent-studio",
            isRead: false
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: "",
            collapsedGroups: [InboxNotificationGroupKey("agent-studio")]
        )

        #expect(model.sections.count == 1)
        #expect(model.sections[0].isCollapsed)
        #expect(model.sections[0].unreadCount == 1)
        #expect(model.sections[0].visibleNotifications.isEmpty)
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

    @Test("group boundary navigation skips collapsed groups")
    func groupBoundaryNavigationSkipsCollapsedGroups() {
        let firstPane = UUID()
        let collapsedPane = UUID()
        let thirdPane = UUID()
        let first = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "First",
            paneId: firstPane,
            worktreeName: "A"
        )
        let collapsed = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Collapsed",
            paneId: collapsedPane,
            worktreeName: "B"
        )
        let third = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 300),
            title: "Third",
            paneId: thirdPane,
            worktreeName: "C"
        )
        let model = InboxNotificationListModel(
            notifications: [first, collapsed, third],
            grouping: .byPane,
            sort: .oldestFirst,
            searchText: "",
            collapsedGroups: [InboxNotificationGroupKey(collapsedPane.uuidString)]
        )

        #expect(
            model.groupBoundaryTarget(
                from: first.id,
                direction: InboxNotificationListNavigationDirection.next
            ) == third.id
        )
        #expect(
            model.groupBoundaryTarget(
                from: third.id,
                direction: InboxNotificationListNavigationDirection.previous
            ) == first.id
        )
    }

    @Test("finds first and last endpoint targets")
    func findsEndpointTargets() {
        let first = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "First"
        )
        let last = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Last"
        )
        let model = InboxNotificationListModel(
            notifications: [last, first],
            grouping: .none,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.endpointTarget(.first) == first.id)
        #expect(model.endpointTarget(.last) == last.id)
    }
}
