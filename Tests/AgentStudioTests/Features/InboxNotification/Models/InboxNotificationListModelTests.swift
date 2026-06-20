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
        var tabDisplayLabel: String?
        var tabOrdinal: Int?
        var paneDisplayLabel: String?
        var paneOrdinal: Int?
        var paneRole: InboxNotification.PaneSource.PaneRole = .main
        var parentPaneId: UUID?
        var parentPaneDisplayLabel: String?
        var parentPaneOrdinal: Int?
        var drawerOrdinal: Int?
        var runtimeDisplayLabel: String?
    }

    private func makeInboxNotification(
        id: UUID = UUID(),
        timestamp: Date,
        kind: InboxNotificationKind = .agentRpc,
        title: String,
        body: String? = nil,
        paneId: UUID? = nil,
        tabId: UUID? = nil,
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil,
        tabDisplayLabel: String? = nil,
        tabOrdinal: Int? = nil,
        paneDisplayLabel: String? = nil,
        paneOrdinal: Int? = nil,
        paneRole: InboxNotification.PaneSource.PaneRole = .main,
        parentPaneId: UUID? = nil,
        parentPaneDisplayLabel: String? = nil,
        parentPaneOrdinal: Int? = nil,
        drawerOrdinal: Int? = nil,
        runtimeDisplayLabel: String? = nil,
        claimKey: InboxNotificationClaimKey? = nil,
        isRead: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp,
            kind: kind,
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
                    branchName: branchName,
                    tabDisplayLabel: tabDisplayLabel,
                    tabOrdinal: tabOrdinal,
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
            claimKey: claimKey,
            isRead: isRead,
            isDismissedFromPaneInbox: false
        )
    }

    private func makeSource(_ context: SourceContext) -> InboxNotification.Source {
        guard
            context.paneId != nil || context.tabId != nil || context.repoId != nil
                || context.repoName != nil || context.worktreeId != nil
                || context.worktreeName != nil || context.branchName != nil
                || context.tabDisplayLabel != nil || context.paneDisplayLabel != nil
                || context.runtimeDisplayLabel != nil
        else {
            return .global
        }
        return .pane(
            .init(
                paneId: context.paneId ?? UUID(),
                tabId: context.tabId,
                tabDisplayLabel: context.tabDisplayLabel,
                tabOrdinal: context.tabOrdinal,
                repoId: context.repoId,
                repoName: context.repoName,
                worktreeId: context.worktreeId,
                worktreeName: context.worktreeName,
                branchName: context.branchName,
                paneDisplayLabel: context.paneDisplayLabel,
                paneOrdinal: context.paneOrdinal,
                paneRole: context.paneRole,
                parentPaneId: context.parentPaneId,
                parentPaneDisplayLabel: context.parentPaneDisplayLabel,
                parentPaneOrdinal: context.parentPaneOrdinal,
                drawerOrdinal: context.drawerOrdinal,
                runtimeDisplayLabel: context.runtimeDisplayLabel
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

    @Test("unread-only filter keeps unread entries")
    func unreadOnlyFilterKeepsUnreadEntries() {
        let unread = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Unread",
            isRead: false
        )
        let read = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Read",
            isRead: true
        )

        let model = InboxNotificationListModel(
            notifications: [unread, read],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "",
            unreadOnly: true
        )

        #expect(model.sections.flatMap(\.notifications).map(\.id) == [unread.id])
    }

    @Test("section unread count excludes activity rows")
    func sectionUnreadCountExcludesActivityRows() {
        let paneId = UUID()
        let activity = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .unseenActivity,
            title: "Activity",
            claimKey: .init(
                paneId: paneId,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: UUID()
            )
        )
        let action = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            kind: .approvalRequested,
            title: "Approval",
            claimKey: .init(
                paneId: paneId,
                lane: .actionNeeded,
                semantic: .approvalRequested,
                sessionId: UUID()
            )
        )
        let readSafety = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 300),
            kind: .securityEvent,
            title: "Read safety",
            claimKey: .init(
                paneId: paneId,
                lane: .safety,
                semantic: .securityEvent,
                sessionId: nil
            ),
            isRead: true
        )

        let model = InboxNotificationListModel(
            notifications: [activity, action, readSafety],
            grouping: .none,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections[0].unreadCount == 1)
    }

    @Test("row state filter limits read rows when requested")
    func rowStateFilterLimitsReadRowsWhenRequested() {
        let unread = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .approvalRequested,
            title: "Unread",
            isRead: false
        )
        let read = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 101),
            kind: .approvalRequested,
            title: "Read",
            isRead: true
        )

        let unreadOnlyModel = InboxNotificationListModel(
            notifications: [unread, read],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "",
            contentMode: .rollUpAlerts,
            rowStateFilter: .unreadOnly
        )
        let allRowsModel = InboxNotificationListModel(
            notifications: [unread, read],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "",
            contentMode: .rollUpAlerts,
            rowStateFilter: .all
        )

        #expect(unreadOnlyModel.sections.flatMap(\.notifications).map(\.title) == ["Unread"])
        #expect(allRowsModel.sections.flatMap(\.notifications).map(\.title) == ["Unread", "Read"])
    }

    @Test("missing repo names use pane label instead of UUID prefix")
    func missingRepoNamesUsePaneLabelInsteadOfUUIDPrefix() {
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
        #expect(model.sections.map(\.label) == ["Pane"])
        #expect(
            model.sections.map(\.label).contains { label in
                label?.contains(repoId.uuidString.prefix(8)) == true
            } == false)
    }

    @Test("by tab grouping uses tab display label instead of UUID prefix")
    func byTabGroupingUsesTabDisplayLabel() {
        let tabId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            paneId: UUID(),
            tabId: tabId,
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Claude"
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byTab,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.map(\.id) == [tabId.uuidString])
        #expect(model.sections.map(\.label) == ["Work"])
    }

    @Test("by tab group headers use tab display label with tab number secondary text")
    func byTabGroupHeadersUseTabDisplayLabelWithTabNumber() {
        let tabId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            paneId: UUID(),
            tabId: tabId,
            tabDisplayLabel: "askluna",
            tabOrdinal: 1,
            paneDisplayLabel: "Ready (askluna)",
            paneOrdinal: 2
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byTab,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.first?.header?.title == "askluna")
        #expect(model.sections.first?.header?.secondaryTitle == "Tab 1")
    }

    @Test("by pane group headers use pane display label with pane number secondary text")
    func byPaneGroupHeadersUsePaneDisplayLabelWithPaneNumber() {
        let paneId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            paneId: paneId,
            tabDisplayLabel: "askluna",
            tabOrdinal: 1,
            paneDisplayLabel: "Ready (askluna)",
            paneOrdinal: 2
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byPane,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.first?.header?.title == "Ready (askluna)")
        #expect(model.sections.first?.header?.secondaryTitle == "Pane 2")
    }

    @Test("search uses source display text")
    func searchUsesSourceDisplayText() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Done",
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Gemini",
            runtimeDisplayLabel: "Terminal"
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "gemini"
        )

        #expect(model.sections.flatMap(\.notifications).map(\.id) == [notification.id])
    }

    @Test("collapsed grouped sections keep roll-up alert counts but hide rows")
    func collapsedGroupedSectionsKeepRollUpAlertCountsButHideRows() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .approvalRequested,
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

    @Test("groups by repo with roll-up alert counts")
    func groupsByRepoWithRollUpAlertCounts() {
        let betaUnread = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .approvalRequested,
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
            kind: .approvalRequested,
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

    @Test("repo pane tab and fallback groups all produce source group headers")
    func allGroupedSectionsProduceSourceGroupHeaders() {
        let repoId = UUID()
        let paneId = UUID()
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
            notifications: [repoNotification],
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
        #expect(byRepo.sections.contains { $0.header?.sourceKind == .otherSources })
        #expect(byPane.sections.first?.header?.sourceKind == .pane)
        #expect(byTab.sections.first?.header?.sourceKind == .tab)
    }

    @Test("repo groups default to neutral source presentation without repo resolver")
    func repoGroupsDefaultToNeutralSourcePresentation() {
        let repoId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Repo event",
            repoId: repoId,
            repoName: "agent-studio"
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.first?.header?.title == "agent-studio")
        #expect(model.sections.first?.header?.secondaryTitle == nil)
        #expect(model.sections.first?.header?.sourceKind == .repo(organizationName: nil))
        #expect(model.sections.first?.header?.accentColorHex == nil)
    }

    @Test("repo resolver supplies source group title owner and accent color")
    func repoResolverSuppliesSourceGroupTitleOwnerAndAccentColor() {
        let repoId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Repo event",
            repoId: repoId,
            repoName: "filesystem-name"
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: "",
            repoPresentation: { requestedRepoId in
                guard requestedRepoId == repoId else { return nil }
                return InboxNotificationRepoGroupPresentation(
                    title: "agent-studio",
                    organizationName: "ShravanSunder",
                    accentColorHex: "#EAC54F"
                )
            }
        )

        #expect(model.sections.first?.header?.title == "agent-studio")
        #expect(model.sections.first?.header?.secondaryTitle == "ShravanSunder")
        #expect(model.sections.first?.header?.sourceKind == .repo(organizationName: "ShravanSunder"))
        #expect(model.sections.first?.header?.accentColorHex == "#EAC54F")
    }

    @Test("repo resolver group id collapses repo buckets into one source group")
    func repoResolverGroupIdCollapsesRepoBucketsIntoOneSourceGroup() {
        let firstRepoId = UUID()
        let secondRepoId = UUID()
        let firstNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "First repo event",
            repoId: firstRepoId,
            repoName: "filesystem-a"
        )
        let secondNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Second repo event",
            repoId: secondRepoId,
            repoName: "filesystem-b"
        )

        let model = InboxNotificationListModel(
            notifications: [firstNotification, secondNotification],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: "",
            repoPresentation: { repoId in
                guard repoId == firstRepoId || repoId == secondRepoId else { return nil }
                return InboxNotificationRepoGroupPresentation(
                    groupId: "remote:ShravanSunder/agent-studio",
                    title: "agent-studio",
                    organizationName: "ShravanSunder",
                    accentColorHex: "#EAC54F"
                )
            }
        )

        #expect(model.sections.count == 1)
        #expect(model.sections.first?.id == "repoGroup:remote:ShravanSunder/agent-studio")
        #expect(model.sections.first?.header?.title == "agent-studio")
        #expect(model.sections.first?.header?.secondaryTitle == "ShravanSunder")
        #expect(model.sections.first?.header?.accentColorHex == "#EAC54F")
        #expect(model.sections.first?.notifications.map(\.id) == [firstNotification.id, secondNotification.id])
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

    @Test("by pane grouping rolls drawer children up to their parent pane")
    func byPaneGroupingRollsDrawerChildrenUpToParentPane() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let siblingPaneId = UUID()
        let parentNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Parent",
            paneId: parentPaneId,
            paneDisplayLabel: "Claude"
        )
        let drawerNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Drawer",
            paneId: drawerPaneId,
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: "Claude",
            drawerOrdinal: 1
        )
        let siblingNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 300),
            title: "Sibling",
            paneId: siblingPaneId,
            paneDisplayLabel: "Terminal"
        )

        let model = InboxNotificationListModel(
            notifications: [siblingNotification, drawerNotification, parentNotification],
            grouping: .byPane,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.map(\.id) == [parentPaneId.uuidString, siblingPaneId.uuidString])
        #expect(model.sections.map(\.label) == ["Claude", "Terminal"])
        #expect(model.sections[0].notifications.map(\.title) == ["Parent", "Drawer"])
    }

    @Test("group label uses newest source label independent of visible sort")
    func groupLabelUsesNewestSourceLabelIndependentOfVisibleSort() {
        let paneId = UUID()
        let older = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Older",
            paneId: paneId,
            paneDisplayLabel: "Old Label"
        )
        let newer = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Newer",
            paneId: paneId,
            paneDisplayLabel: "New Label"
        )

        let model = InboxNotificationListModel(
            notifications: [newer, older],
            grouping: .byPane,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.map(\.label) == ["New Label"])
        #expect(model.sections[0].notifications.map(\.title) == ["Older", "Newer"])
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
