import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListModel")
struct InboxNotificationListModelTests {
    private struct SourceContext {
        var paneId: UUID?
        var tabId: UUID?
        var tabDisplayLabel: String?
        var repoId: UUID?
        var repoName: String?
        var worktreeId: UUID?
        var worktreeName: String?
        var branchName: String?
        var paneDisplayLabel: String?
        var paneOrdinal: Int?
        var paneRole: InboxNotification.PaneSource.PaneRole = .main
        var parentPaneId: UUID?
        var parentPaneDisplayLabel: String?
        var drawerOrdinal: Int?
        var runtimeDisplayLabel: String?
    }

    private func makeInboxNotification(
        id: UUID = UUID(),
        timestamp: Date,
        title: String,
        body: String? = nil,
        paneId: UUID? = nil,
        tabId: UUID? = nil,
        tabDisplayLabel: String? = nil,
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil,
        paneDisplayLabel: String? = nil,
        paneOrdinal: Int? = nil,
        paneRole: InboxNotification.PaneSource.PaneRole = .main,
        parentPaneId: UUID? = nil,
        parentPaneDisplayLabel: String? = nil,
        drawerOrdinal: Int? = nil,
        runtimeDisplayLabel: String? = nil,
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
                    tabDisplayLabel: tabDisplayLabel,
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
                    drawerOrdinal: drawerOrdinal,
                    runtimeDisplayLabel: runtimeDisplayLabel
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
                || context.tabDisplayLabel != nil || context.paneDisplayLabel != nil
                || context.paneOrdinal != nil
                || context.parentPaneDisplayLabel != nil || context.runtimeDisplayLabel != nil
        else {
            return .global
        }
        return .pane(
            .init(
                paneId: context.paneId ?? UUID(),
                tabId: context.tabId,
                tabDisplayLabel: context.tabDisplayLabel,
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
        #expect(model.sections.map(\.label) == ["Other sources"])
    }

    @Test("row presentation replaces empty titles with message text")
    func rowPresentationReplacesEmptyTitlesWithMessageText() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "   ",
            body: "Claude is waiting for your input",
            repoName: "agent-studio",
            worktreeName: "notification-system"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.primaryText == "Claude is waiting for your input")
        #expect(display.detailText == nil)
        #expect(display.sourceLine == "agent-studio · notification-system")
    }

    @Test("repo source line preserves branch when worktree is missing")
    func repoSourceLinePreservesBranchWhenWorktreeIsMissing() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Plan updated",
            repoName: "agent-studio",
            branchName: "notification-inbox-redesign"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.sourceLine == "agent-studio · notification-inbox-redesign")
        #expect(display.searchText.contains("notification-inbox-redesign"))
    }

    @Test("source display includes branch pane and drawer placement")
    func sourceDisplayIncludesBranchPaneAndDrawerPlacement() {
        let parentPaneId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            body: "waiting",
            repoName: "agent-studio",
            worktreeName: "notification-system",
            branchName: "notification-inbox-redesign",
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: "Main",
            drawerOrdinal: 1,
            runtimeDisplayLabel: "Terminal"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.primaryText == "Claude Code")
        #expect(display.sourceLine == "agent-studio · notification-system / notification-inbox-redesign")
        #expect(display.placementLine == "Parent Main · Drawer 1: Gemini · Terminal")
        #expect(display.detailText == "waiting")
        #expect(display.searchText.contains("Gemini"))
    }

    @Test("pane inbox row context hides redundant parent placement")
    func paneInboxRowContextHidesRedundantParentPlacement() {
        let parentPaneId = UUID()
        let parentNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Parent",
            paneId: parentPaneId,
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Claude",
            runtimeDisplayLabel: "Terminal"
        )
        let drawerNotification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Drawer",
            paneId: UUID(),
            tabDisplayLabel: "Work",
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: "Claude",
            drawerOrdinal: 2,
            runtimeDisplayLabel: "Terminal"
        )

        let parentDisplay = InboxNotificationSourceDisplay(
            notification: parentNotification,
            rowContext: .paneInbox(parentPaneId: parentPaneId)
        )
        let drawerDisplay = InboxNotificationSourceDisplay(
            notification: drawerNotification,
            rowContext: .paneInbox(parentPaneId: parentPaneId)
        )

        #expect(parentDisplay.placementLine == "Work · Terminal")
        #expect(drawerDisplay.placementLine == "Work · Parent Claude · Drawer 2: Gemini · Terminal")
    }

    @Test("filter labels use denormalized names without uuid prefixes")
    func filterLabelsUseDenormalizedNamesWithoutUUIDPrefixes() {
        let repoId = UUID()
        let worktreeId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Filtered",
            repoId: repoId,
            repoName: "agent-studio",
            worktreeId: worktreeId,
            worktreeName: "notification-system"
        )

        #expect(
            InboxNotificationSourceDisplay.filterLabel(
                for: .repo(id: repoId),
                notifications: [notification]
            ) == "agent-studio"
        )
        #expect(
            InboxNotificationSourceDisplay.filterLabel(
                for: .worktree(id: worktreeId),
                notifications: [notification]
            ) == "notification-system"
        )
        #expect(
            InboxNotificationSourceDisplay.filterLabel(
                for: .repo(id: UUID()),
                notifications: [notification]
            ) == "Filtered repo"
        )
    }

    @Test("filter labels use newest matching denormalized name")
    func filterLabelsUseNewestMatchingDenormalizedName() {
        let repoId = UUID()
        let worktreeId = UUID()
        let stale = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Stale filter row",
            repoId: repoId,
            repoName: "old-repo",
            worktreeId: worktreeId,
            worktreeName: "old-worktree"
        )
        let current = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Current filter row",
            repoId: repoId,
            repoName: "current-repo",
            worktreeId: worktreeId,
            worktreeName: "current-worktree"
        )

        #expect(
            InboxNotificationSourceDisplay.filterLabel(
                for: .repo(id: repoId),
                notifications: [stale, current]
            ) == "current-repo"
        )
        #expect(
            InboxNotificationSourceDisplay.filterLabel(
                for: .worktree(id: worktreeId),
                notifications: [stale, current]
            ) == "current-worktree"
        )
    }

    @Test("source display suppresses legacy absurd command duration details")
    func sourceDisplaySuppressesLegacyAbsurdCommandDurationDetails() {
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .commandFinished,
            title: "Command finished",
            body: "exit 0 · 4842802399m 18s",
            source: .pane(.init(paneId: UUID(), runtimeDisplayLabel: "Terminal")),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.primaryText == "Command finished")
        #expect(display.detailText == "exit 0")
    }

    @Test("legacy pane source fallback uses terminal instead of generic notification text")
    func legacyPaneSourceFallbackUsesTerminalInsteadOfGenericNotificationText() {
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentDesktopNotification,
            title: "Claude Code",
            body: "waiting",
            source: .pane(.init(paneId: UUID())),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.sourceLine == "Terminal")
        #expect(display.searchText.contains("Pane notification") == false)
    }

    @Test("group labels use human source labels without uuid prefixes")
    func groupLabelsUseHumanSourceLabelsWithoutUUIDPrefixes() {
        let tabId = UUID()
        let paneId = UUID()
        let byTab = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Tab row",
            paneId: paneId,
            tabId: tabId,
            tabDisplayLabel: "Build"
        )
        let drawer = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Drawer row",
            paneId: UUID(),
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneDisplayLabel: "Main",
            drawerOrdinal: 1
        )

        let tabModel = InboxNotificationListModel(
            notifications: [byTab],
            grouping: .byTab,
            sort: .oldestFirst,
            searchText: ""
        )
        let paneModel = InboxNotificationListModel(
            notifications: [drawer],
            grouping: .byPane,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(tabModel.sections.map(\.label) == ["Build"])
        #expect(paneModel.sections.map(\.label) == ["Parent Main · Drawer 1: Gemini"])
    }

    @Test("repo grouping carries repo header presentation")
    func repoGroupingCarriesRepoHeaderPresentation() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Repo row",
            repoName: "agent-studio",
            worktreeName: "notification-system"
        )

        let model = InboxNotificationListModel(
            notifications: [notification],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.map(\.label) == ["agent-studio"])
        #expect(model.sections.first?.header?.style == .repo(organizationName: nil))
    }

    @Test("source display exposes tab pane drawer and runtime placement parts")
    func sourceDisplayExposesPlacementParts() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            body: "Waiting for input",
            paneId: drawerPaneId,
            tabDisplayLabel: "Tab 2",
            repoName: "agent-studio",
            worktreeName: "notification-system",
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: "Main",
            drawerOrdinal: 1,
            runtimeDisplayLabel: "Terminal"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.sourceLine == "agent-studio · notification-system")
        #expect(display.placementParts == ["Tab 2", "Parent Main · Drawer 1: Gemini", "Terminal"])
        #expect(display.placementLine == "Tab 2 · Parent Main · Drawer 1: Gemini · Terminal")
    }

    @Test("source display includes pane number fallback when pane label is blank")
    func sourceDisplayIncludesPaneNumberFallback() {
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            tabDisplayLabel: "Tab 2",
            paneDisplayLabel: nil,
            paneOrdinal: 3,
            paneRole: .main,
            runtimeDisplayLabel: "Terminal"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.placementParts == ["Tab 2", "Pane 3", "Terminal"])
    }

    @Test("source display uses a single locator for untitled drawer children")
    func sourceDisplayUsesSingleLocatorForUntitledDrawerChildren() {
        let parentPaneId = UUID()
        let notification = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Claude Code",
            tabDisplayLabel: "Tab 1",
            paneDisplayLabel: nil,
            paneOrdinal: 2,
            paneRole: .drawerChild,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: "Terminal",
            drawerOrdinal: 1,
            runtimeDisplayLabel: "Terminal"
        )

        let display = InboxNotificationSourceDisplay(notification: notification)

        #expect(display.placementParts == ["Tab 1", "Pane 2 · Drawer 1", "Terminal"])
        #expect(display.placementLine == "Tab 1 · Pane 2 · Drawer 1 · Terminal")
        #expect(display.placementLine?.contains("Pane 2: Terminal") == false)
        #expect(display.placementLine?.contains("Terminal · Terminal") == false)
    }

    @Test("pane inbox suppresses only redundant active parent pane self-placement")
    func paneInboxSuppressesOnlyRedundantActiveParentPaneSelfPlacement() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let parent = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Parent",
            paneId: parentPaneId,
            tabDisplayLabel: "Tab 2",
            paneDisplayLabel: "Main",
            paneOrdinal: 1,
            paneRole: .main,
            runtimeDisplayLabel: "Terminal"
        )
        let drawer = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Drawer",
            paneId: drawerPaneId,
            tabDisplayLabel: "Tab 2",
            paneDisplayLabel: "Gemini",
            paneRole: .drawerChild,
            parentPaneId: parentPaneId,
            parentPaneDisplayLabel: "Main",
            drawerOrdinal: 1,
            runtimeDisplayLabel: "Terminal"
        )

        let parentDisplay = InboxNotificationSourceDisplay(
            notification: parent,
            rowContext: .paneInbox(parentPaneId: parentPaneId)
        )
        let drawerDisplay = InboxNotificationSourceDisplay(
            notification: drawer,
            rowContext: .paneInbox(parentPaneId: parentPaneId)
        )

        #expect(parentDisplay.placementParts == ["Tab 2", "Terminal"])
        #expect(drawerDisplay.placementParts == ["Tab 2", "Parent Main · Drawer 1: Gemini", "Terminal"])
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

    @Test("repo-less byRepo section uses stable Other sources label")
    func repoLessByRepoSectionUsesStableOtherSourcesLabel() {
        let first = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "First repo-less row",
            worktreeName: "agent-vm",
            branchName: "notification-system"
        )
        let second = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Second repo-less row",
            worktreeName: "agent-studio",
            branchName: "notification-system-5"
        )

        let model = InboxNotificationListModel(
            notifications: [first, second],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.count == 1)
        #expect(model.sections[0].id == "__no_repo__")
        #expect(model.sections[0].label == "Other sources")
        #expect(model.sections[0].notifications.map(\.id) == [first.id, second.id])
    }

    @Test("repo id group label uses newest denormalized repo name independent of sort")
    func repoIdGroupLabelUsesNewestDenormalizedRepoNameIndependentOfSort() {
        let repoId = UUID()
        let stale = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Stale name row",
            repoId: repoId,
            repoName: "old-name"
        )
        let current = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Current name row",
            repoId: repoId,
            repoName: "current-name"
        )

        let model = InboxNotificationListModel(
            notifications: [current, stale],
            grouping: .byRepo,
            sort: .oldestFirst,
            searchText: ""
        )

        #expect(model.sections.count == 1)
        #expect(model.sections[0].id == "repo:\(repoId.uuidString)")
        #expect(model.sections[0].label == "current-name")
        #expect(model.sections[0].notifications.map(\.id) == [stale.id, current.id])
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
            paneDisplayLabel: "A"
        )
        let collapsed = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Collapsed",
            paneId: collapsedPane,
            paneDisplayLabel: "B"
        )
        let third = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 300),
            title: "Third",
            paneId: thirdPane,
            paneDisplayLabel: "C"
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
