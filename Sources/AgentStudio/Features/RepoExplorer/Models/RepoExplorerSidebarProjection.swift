import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

enum RepoExplorerEmptyState: Equatable, Sendable {
    case content
    case noRepositories
    case noPanes
    case noTabs
    case searchNoResults
}

enum RepoExplorerSidebarSectionKind: String, Equatable, Sendable {
    case pinnedRepositories
    case openRepositories
    case repositories
    case activeRepos
    case justNowRepos
    case lastHourRepos
    case todayRepos
    case lastSevenDaysRepos
    case olderRepos
    case noActivityRepos
    case pinnedPanes
    case panes

    static func activitySection(_ bucket: RepoExplorerActivityBucket) -> Self {
        switch bucket {
        case .active: .activeRepos
        case .justNow: .justNowRepos
        case .lastHour: .lastHourRepos
        case .today: .todayRepos
        case .lastSevenDays: .lastSevenDaysRepos
        case .older: .olderRepos
        case .noActivity: .noActivityRepos
        }
    }

    var sectionIcon: AppEntityIcon {
        switch self {
        case .pinnedRepositories, .openRepositories, .repositories: .repo
        case .pinnedPanes, .panes: .pane
        case .activeRepos, .justNowRepos, .lastHourRepos, .todayRepos, .lastSevenDaysRepos, .olderRepos,
            .noActivityRepos:
            .activity
        }
    }

    var title: String {
        switch self {
        case .pinnedRepositories: "Pinned repos"
        case .openRepositories: "Open repos"
        case .repositories: "Available repos"
        case .activeRepos: "Active"
        case .justNowRepos: "Just now"
        case .lastHourRepos: "Last hour"
        case .todayRepos: "Today"
        case .lastSevenDaysRepos: "Last 7 days"
        case .olderRepos: "Older"
        case .noActivityRepos: "No activity"
        case .pinnedPanes: "Pinned Panes"
        case .panes: "Other Panes"
        }
    }
}

enum RepoExplorerLoadingSectionState: Equatable, Sendable {
    case scanning
    case statusUnavailable
    case mixed
}

struct RepoExplorerSidebarSection: Identifiable, Equatable, Sendable {
    let kind: RepoExplorerSidebarSectionKind
    let resolvedGroups: [RepoPresentationGroup]
    let loadingRepos: [RepoPresentationItem]
    let unassociatedPaneDestinations: [RepoExplorerUnassociatedPaneDestination]

    init(
        kind: RepoExplorerSidebarSectionKind,
        resolvedGroups: [RepoPresentationGroup],
        loadingRepos: [RepoPresentationItem],
        unassociatedPaneDestinations: [RepoExplorerUnassociatedPaneDestination] = []
    ) {
        self.kind = kind
        self.resolvedGroups = resolvedGroups
        self.loadingRepos = loadingRepos
        self.unassociatedPaneDestinations = unassociatedPaneDestinations
    }

    var id: String { "section:\(kind.rawValue)" }
    var title: String { kind.title }

    func loadingState(enrichmentByRepoId: [UUID: RepoEnrichment]) -> RepoExplorerLoadingSectionState {
        var hasScanningRepos = false
        var hasStatusUnavailableRepos = false
        for repo in loadingRepos {
            switch enrichmentByRepoId[repo.id] {
            case .statusUnavailable:
                hasStatusUnavailableRepos = true
            case .awaitingOrigin, .none:
                hasScanningRepos = true
            case .resolvedLocal, .resolvedRemote:
                break
            }
        }
        if hasScanningRepos && hasStatusUnavailableRepos {
            return .mixed
        }
        return hasStatusUnavailableRepos ? .statusUnavailable : .scanning
    }
}

struct RepoExplorerSidebarContent: Equatable, Sendable {
    let sections: [RepoExplorerSidebarSection]
    let resolvedGroups: [RepoPresentationGroup]
    let worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]
    let paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]]
    let paneDestinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]]
    let paneDestinationsByRepoId: [UUID: [RepoExplorerPaneDestination]]
    let loadingRepos: [RepoPresentationItem]
    let emptyState: RepoExplorerEmptyState

    var showsNoResults: Bool {
        emptyState == .searchNoResults
    }

    init(
        sections: [RepoExplorerSidebarSection],
        resolvedGroups: [RepoPresentationGroup],
        worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:],
        paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:],
        paneDestinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]] = [:],
        paneDestinationsByRepoId: [UUID: [RepoExplorerPaneDestination]] = [:],
        loadingRepos: [RepoPresentationItem],
        showsNoResults: Bool
    ) {
        self.sections = sections
        self.resolvedGroups = resolvedGroups
        self.worktreeRowsByGroupId = worktreeRowsByGroupId
        self.paneRowsByGroupId = paneRowsByGroupId
        self.paneDestinationsByWorktreeId = paneDestinationsByWorktreeId
        self.paneDestinationsByRepoId = paneDestinationsByRepoId
        self.loadingRepos = loadingRepos
        emptyState = showsNoResults ? .searchNoResults : .content
    }

    init(
        sections: [RepoExplorerSidebarSection],
        resolvedGroups: [RepoPresentationGroup],
        worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:],
        paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:],
        paneDestinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]] = [:],
        paneDestinationsByRepoId: [UUID: [RepoExplorerPaneDestination]] = [:],
        loadingRepos: [RepoPresentationItem],
        emptyState: RepoExplorerEmptyState
    ) {
        self.sections = sections
        self.resolvedGroups = resolvedGroups
        self.worktreeRowsByGroupId = worktreeRowsByGroupId
        self.paneRowsByGroupId = paneRowsByGroupId
        self.paneDestinationsByWorktreeId = paneDestinationsByWorktreeId
        self.paneDestinationsByRepoId = paneDestinationsByRepoId
        self.loadingRepos = loadingRepos
        self.emptyState = emptyState
    }
}

struct RepoExplorerPlacementContext: Equatable, Sendable {
    let paneId: UUID
    let tabId: UUID
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool

    var displayText: String {
        let paneTitle = "Pane \(paneIndexInTab + 1)"
        return isActiveInTab ? "\(paneTitle) active" : paneTitle
    }
}

struct RepoExplorerProjectedWorktreeRow: Equatable, Sendable {
    let groupId: String
    let repo: RepoPresentationItem
    let worktree: Worktree
    let rowId: String
    let checkoutColorHex: String
    let placementContext: RepoExplorerPlacementContext?
    var activitySubgroup: RepoExplorerActivityBucket?
}

struct RepoExplorerPaneDestination: Equatable, Sendable, Identifiable {
    let paneId: UUID
    let repoId: UUID
    let worktreeId: UUID
    let worktreeLabel: String
    let tabId: UUID
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool
    let paneDisplayLabel: String

    init(
        paneId: UUID,
        repoId: UUID,
        worktreeId: UUID,
        worktreeLabel: String,
        tabId: UUID,
        tabIndex: Int,
        paneIndexInTab: Int,
        isActiveInTab: Bool,
        paneDisplayLabel: String = ""
    ) {
        self.paneId = paneId
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.worktreeLabel = worktreeLabel
        self.tabId = tabId
        self.tabIndex = tabIndex
        self.paneIndexInTab = paneIndexInTab
        self.isActiveInTab = isActiveInTab
        self.paneDisplayLabel = paneDisplayLabel
    }

    var id: UUID { paneId }

    var label: String {
        let activeSuffix = isActiveInTab ? " — Active" : ""
        return
            "\(worktreeLabel) — \(paneDisplayLabel) — Tab \(tabIndex + 1), Pane \(paneIndexInTab + 1)\(activeSuffix)"
    }

    func label(paneDisplayLabel: String) -> String {
        let activeSuffix = isActiveInTab ? " — Active" : ""
        return
            "\(worktreeLabel) — \(paneDisplayLabel) — Tab \(tabIndex + 1), Pane \(paneIndexInTab + 1)\(activeSuffix)"
    }
}

struct RepoExplorerUnassociatedPaneDestination: Equatable, Sendable, Identifiable {
    let paneId: UUID
    let tabId: UUID
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool

    var id: UUID { paneId }

    func label(paneDisplayLabel: String) -> String {
        let activeSuffix = isActiveInTab ? " — Active" : ""
        return "\(paneDisplayLabel) — Tab \(tabIndex + 1), Pane \(paneIndexInTab + 1)\(activeSuffix)"
    }
}

enum RepoExplorerSidebarProjection: Equatable, Sendable {
    case ready(RepoExplorerSidebarContent)
    case degraded(RepoExplorerTopologyFault)

    var sections: [RepoExplorerSidebarSection] {
        switch self {
        case .ready(let content): content.sections
        case .degraded: []
        }
    }

    var resolvedGroups: [RepoPresentationGroup] {
        switch self {
        case .ready(let content): content.resolvedGroups
        case .degraded: []
        }
    }

    var loadingRepos: [RepoPresentationItem] {
        switch self {
        case .ready(let content): content.loadingRepos
        case .degraded: []
        }
    }

    func scanningRepoCount(enrichmentByRepoId: [UUID: RepoEnrichment]) -> Int {
        loadingRepos.count { repo in
            switch enrichmentByRepoId[repo.id] {
            case .awaitingOrigin, .none:
                return true
            case .resolvedLocal, .resolvedRemote, .statusUnavailable:
                return false
            }
        }
    }

    var worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] {
        switch self {
        case .ready(let content): content.worktreeRowsByGroupId
        case .degraded: [:]
        }
    }

    var paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] {
        switch self {
        case .ready(let content): content.paneRowsByGroupId
        case .degraded: [:]
        }
    }

    var paneDestinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]] {
        switch self {
        case .ready(let content): content.paneDestinationsByWorktreeId
        case .degraded: [:]
        }
    }

    var paneDestinationsByRepoId: [UUID: [RepoExplorerPaneDestination]] {
        switch self {
        case .ready(let content): content.paneDestinationsByRepoId
        case .degraded: [:]
        }
    }

    var emptyState: RepoExplorerEmptyState {
        switch self {
        case .ready(let content): content.emptyState
        case .degraded: .content
        }
    }

    var showsNoResults: Bool {
        switch self {
        case .ready(let content): content.showsNoResults
        case .degraded: false
        }
    }

    init(
        sections: [RepoExplorerSidebarSection],
        resolvedGroups: [RepoPresentationGroup],
        worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:],
        loadingRepos: [RepoPresentationItem],
        showsNoResults: Bool
    ) {
        self = .ready(
            RepoExplorerSidebarContent(
                sections: sections,
                resolvedGroups: resolvedGroups,
                worktreeRowsByGroupId: worktreeRowsByGroupId,
                loadingRepos: loadingRepos,
                showsNoResults: showsNoResults
            )
        )
    }

    init(
        sections: [RepoExplorerSidebarSection],
        resolvedGroups: [RepoPresentationGroup],
        worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:],
        loadingRepos: [RepoPresentationItem],
        emptyState: RepoExplorerEmptyState
    ) {
        self = .ready(
            RepoExplorerSidebarContent(
                sections: sections,
                resolvedGroups: resolvedGroups,
                worktreeRowsByGroupId: worktreeRowsByGroupId,
                loadingRepos: loadingRepos,
                emptyState: emptyState
            )
        )
    }
}
