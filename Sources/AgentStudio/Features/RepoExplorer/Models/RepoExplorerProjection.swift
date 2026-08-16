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
    case favorites
    case panes
    case repositories
    case tabs

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .panes: "Panes"
        case .repositories: "Repositories"
        case .tabs: "Tabs"
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

struct RepoExplorerProjectedPaneRow: Equatable, Sendable {
    let groupId: String
    let repoId: UUID
    let destination: RepoExplorerPaneDestination
    let rowId: String
    let primaryText: String
    let secondaryText: String
    let recencyText: String
    let isActive: Bool

    init(
        groupId: String,
        repoId: UUID,
        destination: RepoExplorerPaneDestination,
        rowId: String,
        primaryText: String = "",
        secondaryText: String = "",
        recencyText: String = "Now",
        isActive: Bool = false
    ) {
        self.groupId = groupId
        self.repoId = repoId
        self.destination = destination
        self.rowId = rowId
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.recencyText = recencyText
        self.isActive = isActive
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

enum RepoExplorerProjection {
    static func project(
        _ snapshot: RepoExplorerSnapshot,
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts] = [:],
        tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts] = [:]
    ) -> RepoExplorerSidebarProjection {
        projectCancellable(
            snapshot,
            paneRowFactsByPaneId: paneRowFactsByPaneId,
            tabGroupFactsByTabId: tabGroupFactsByTabId,
            cancellationCheck: {}
        )
    }

    static func projectCancellable(
        _ snapshot: RepoExplorerSnapshot,
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts] = [:],
        tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts] = [:],
        cancellationCheck: () throws -> Void
    ) rethrows -> RepoExplorerSidebarProjection {
        try cancellationCheck()
        var topologyFaultDetector = RepoExplorerTopologyFaultDetector()
        for repo in snapshot.repos {
            topologyFaultDetector.observe(repo)
        }
        if let topologyFault = topologyFaultDetector.fault {
            return .degraded(topologyFault)
        }
        let resolvedRepos = resolvedRepos(snapshot.repos, enrichmentByRepoId: snapshot.repoEnrichmentSnapshotByRepoId)
        let filteredResolvedRepos = RepoExplorerFilter.filter(repos: resolvedRepos, query: snapshot.query)
        let filteredLoadingRepos = filterLoadingRepos(
            unresolvedRepos(snapshot.repos, enrichmentByRepoId: snapshot.repoEnrichmentSnapshotByRepoId),
            query: snapshot.query,
            sortOrder: snapshot.sortOrder
        )
        let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
            repos: filteredResolvedRepos,
            repoEnrichmentByRepoId: snapshot.repoEnrichmentSnapshotByRepoId
        )
        let checkoutColorHexByRepoId = checkoutColorHexByRepoId(
            repos: filteredResolvedRepos,
            metadataByRepoId: repoMetadataById
        )
        let paneDestinationsByWorktreeId = try paneDestinationsByWorktreeId(
            repos: snapshot.repos,
            locationsByWorktreeId: snapshot.paneLocationsByWorktreeId,
            paneRowFactsByPaneId: paneRowFactsByPaneId,
            cancellationCheck: cancellationCheck
        )
        let paneDestinationsByRepoId = paneDestinationsByRepoId(
            repos: snapshot.repos,
            destinationsByWorktreeId: paneDestinationsByWorktreeId
        )
        let resolvedGroups: [RepoPresentationGroup]
        let projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]
        let projectedPaneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]]
        switch snapshot.groupingMode {
        case .repo:
            resolvedGroups = repoIdentityGroups(
                repos: filteredResolvedRepos,
                metadataByRepoId: repoMetadataById,
                sortOrder: snapshot.sortOrder
            )
            projectedRowsByGroupId = worktreeRowsByGroupId(
                from: resolvedGroups,
                checkoutColorHexByRepoId: checkoutColorHexByRepoId
            )
            projectedPaneRowsByGroupId = [:]
        case .pane:
            let paneProjection = paneRepoGroups(
                repos: filteredResolvedRepos,
                metadataByRepoId: repoMetadataById,
                sortOrder: snapshot.sortOrder,
                destinationsByWorktreeId: paneDestinationsByWorktreeId,
                paneRowFactsByPaneId: paneRowFactsByPaneId
            )
            resolvedGroups = paneProjection.groups
            projectedRowsByGroupId = [:]
            projectedPaneRowsByGroupId = paneProjection.paneRowsByGroupId
        case .tab:
            let tabProjection = tabPaneGroups(
                repos: filteredResolvedRepos,
                destinationsByWorktreeId: paneDestinationsByWorktreeId,
                paneRowFactsByPaneId: paneRowFactsByPaneId,
                tabGroupFactsByTabId: tabGroupFactsByTabId
            )
            resolvedGroups = tabProjection.groups
            projectedRowsByGroupId = [:]
            projectedPaneRowsByGroupId = tabProjection.paneRowsByGroupId
        }

        let sections = sidebarSections(
            groupingMode: snapshot.groupingMode,
            resolvedGroups: resolvedGroups,
            loadingRepos: filteredLoadingRepos
        )
        let orderedResolvedGroups = sections.isEmpty ? resolvedGroups : sections.flatMap(\.resolvedGroups)
        let orderedLoadingRepos = sections.isEmpty ? filteredLoadingRepos : sections.flatMap(\.loadingRepos)

        return .ready(
            RepoExplorerSidebarContent(
                sections: sections,
                resolvedGroups: orderedResolvedGroups,
                worktreeRowsByGroupId: projectedRowsByGroupId,
                paneRowsByGroupId: projectedPaneRowsByGroupId,
                paneDestinationsByWorktreeId: paneDestinationsByWorktreeId,
                paneDestinationsByRepoId: paneDestinationsByRepoId,
                loadingRepos: orderedLoadingRepos,
                emptyState: emptyState(
                    snapshot: snapshot,
                    resolvedGroups: orderedResolvedGroups,
                    loadingRepos: orderedLoadingRepos
                )
            )
        )
    }

    private static func sidebarSections(
        groupingMode: RepoExplorerGroupingMode,
        resolvedGroups: [RepoPresentationGroup],
        loadingRepos: [RepoPresentationItem]
    ) -> [RepoExplorerSidebarSection] {
        if groupingMode == .tab {
            return [
                RepoExplorerSidebarSection(
                    kind: .tabs,
                    resolvedGroups: resolvedGroups,
                    loadingRepos: loadingRepos
                )
            ]
        }
        let favoriteGroups = resolvedGroups.filter { group in
            !group.repos.isEmpty && group.repos.allSatisfy(\.isFavorite)
        }
        let favoriteLoadingRepos = loadingRepos.filter(\.isFavorite)
        let regularGroups = resolvedGroups.filter { group in
            group.repos.contains { !$0.isFavorite }
        }
        let regularLoadingRepos = loadingRepos.filter { !$0.isFavorite }
        let normalSectionKind: RepoExplorerSidebarSectionKind =
            switch groupingMode {
            case .repo: .repositories
            case .pane: .panes
            case .tab: .tabs
            }

        var sections: [RepoExplorerSidebarSection] = []
        if !favoriteGroups.isEmpty || !favoriteLoadingRepos.isEmpty {
            sections.append(
                RepoExplorerSidebarSection(
                    kind: .favorites,
                    resolvedGroups: favoriteGroups,
                    loadingRepos: favoriteLoadingRepos
                )
            )
        }
        sections.append(
            RepoExplorerSidebarSection(
                kind: normalSectionKind,
                resolvedGroups: regularGroups,
                loadingRepos: regularLoadingRepos
            )
        )
        return sections
    }

    private static func emptyState(
        snapshot: RepoExplorerSnapshot,
        resolvedGroups: [RepoPresentationGroup],
        loadingRepos: [RepoPresentationItem]
    ) -> RepoExplorerEmptyState {
        guard resolvedGroups.isEmpty && loadingRepos.isEmpty else { return .content }
        if !snapshot.query.isEmpty {
            return .searchNoResults
        }
        switch snapshot.groupingMode {
        case .repo:
            return .noRepositories
        case .pane:
            return .noPanes
        case .tab:
            return .noTabs
        }
    }

    private static func checkoutColorHexByRepoId(
        repos: [RepoPresentationItem],
        metadataByRepoId: [UUID: RepoIdentityMetadata]
    ) -> [UUID: String] {
        let sourceGroups = RepoPresentationGrouping.buildGroups(
            repos: repos,
            metadataByRepoId: metadataByRepoId
        )
        return Dictionary(
            uniqueKeysWithValues: sourceGroups.flatMap { group in
                group.repos.map { repo in
                    (
                        repo.id,
                        RepoPresentationColoring.checkoutColorHex(
                            for: repo,
                            in: group
                        )
                    )
                }
            })
    }

    static func resolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return true
            case .awaitingOrigin, .statusUnavailable, .none:
                return false
            }
        }
    }

    static func loadingRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return false
            case .awaitingOrigin, .none:
                return true
            case .statusUnavailable:
                return false
            }
        }
    }

    private static func unresolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        loadingRepos(repos, enrichmentByRepoId: enrichmentByRepoId)
            + statusUnavailableRepos(repos, enrichmentByRepoId: enrichmentByRepoId)
    }

    static func statusUnavailableRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            if case .statusUnavailable = enrichmentByRepoId[repo.id] { return true }
            return false
        }
    }

    private static func filterLoadingRepos(
        _ repos: [RepoPresentationItem],
        query: String,
        sortOrder: RepoExplorerSortOrder
    ) -> [RepoPresentationItem] {
        let filteredRepos: [RepoPresentationItem]
        if query.isEmpty {
            filteredRepos = repos
        } else {
            filteredRepos = repos.filter { repo in
                repo.name.localizedCaseInsensitiveContains(query)
            }
        }

        return sortedRepos(filteredRepos, sortOrder: sortOrder)
    }

    private static func repoIdentityGroups(
        repos: [RepoPresentationItem],
        metadataByRepoId: [UUID: RepoIdentityMetadata],
        sortOrder: RepoExplorerSortOrder
    ) -> [RepoPresentationGroup] {
        repos.compactMap { repo -> RepoPresentationGroup? in
            guard !repo.worktrees.isEmpty else { return nil }
            let metadata = metadataByRepoId[repo.id]
            var projectedRepo = repo
            projectedRepo.worktrees = sortedWorktrees(repo.worktrees, sortOrder: sortOrder)
            return RepoPresentationGroup(
                id: "repo:\(repo.id.uuidString)",
                repoTitle: metadata?.repoName ?? repo.name,
                organizationName: metadata?.organizationName,
                repos: [projectedRepo]
            )
        }
        .sorted { lhs, rhs in
            repoGroupPrecedes(lhs, rhs, sortOrder: sortOrder)
        }
    }

    static func repoGroupPrecedes(
        _ lhs: RepoPresentationGroup,
        _ rhs: RepoPresentationGroup,
        sortOrder: RepoExplorerSortOrder
    ) -> Bool {
        let leftTitle = lhs.organizationName.map { "\(lhs.repoTitle)\($0)" } ?? lhs.repoTitle
        let rightTitle = rhs.organizationName.map { "\(rhs.repoTitle)\($0)" } ?? rhs.repoTitle
        return compare(leftTitle, rightTitle, sortOrder: sortOrder)
    }

    private static func paneRepoGroups(
        repos: [RepoPresentationItem],
        metadataByRepoId: [UUID: RepoIdentityMetadata],
        sortOrder: RepoExplorerSortOrder,
        destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]],
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts]
    ) -> (groups: [RepoPresentationGroup], paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]]) {
        let repoGroups = repoIdentityGroups(
            repos: repos,
            metadataByRepoId: metadataByRepoId,
            sortOrder: sortOrder
        )
        var paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:]
        let groups = repoGroups.compactMap { repoGroup -> RepoPresentationGroup? in
            guard let repo = repoGroup.repos.first else { return nil }
            let destinations = repo.worktrees
                .flatMap { destinationsByWorktreeId[$0.id, default: []] }
                .sorted { lhs, rhs in
                    paneRowPrecedes(
                        lhs,
                        rhs,
                        paneRowFactsByPaneId: paneRowFactsByPaneId,
                        usesRecency: true
                    )
                }
            guard !destinations.isEmpty else { return nil }

            let groupId = "pane-repo:\(repo.id.uuidString)"
            paneRowsByGroupId[groupId] = destinations.map { destination in
                RepoExplorerProjectedPaneRow(
                    groupId: groupId,
                    repoId: repo.id,
                    destination: destination,
                    rowId: "pane-row:\(groupId):\(destination.paneId.uuidString)",
                    primaryText: panePrimaryText(
                        destination,
                        terminalTitle: paneRowFactsByPaneId[destination.paneId]?.terminalTitle
                    ),
                    secondaryText: paneRowFactsByPaneId[destination.paneId]?.latestMessageText
                        ?? "No activity yet",
                    recencyText: paneRowFactsByPaneId[destination.paneId]?.recencyText ?? "Now",
                    isActive: paneRowFactsByPaneId[destination.paneId]?.isActive ?? false
                )
            }
            return RepoPresentationGroup(
                id: groupId,
                repoTitle: repoGroup.repoTitle,
                organizationName: repoGroup.organizationName,
                repos: repoGroup.repos
            )
        }
        return (groups, paneRowsByGroupId)
    }

    private static func paneDestinationsByWorktreeId(
        repos: [RepoPresentationItem],
        locationsByWorktreeId: [UUID: [WorkspacePaneLocation]],
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts],
        cancellationCheck: () throws -> Void
    ) rethrows -> [UUID: [RepoExplorerPaneDestination]] {
        var destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]] = [:]
        var processedWorktreeCount = 0
        for repo in repos {
            for worktree in repo.worktrees {
                if processedWorktreeCount.isMultiple(of: 256) {
                    try cancellationCheck()
                }
                processedWorktreeCount += 1
                let destinations = sortedUniqueLocations(locationsByWorktreeId[worktree.id, default: []])
                    .map { location in
                        RepoExplorerPaneDestination(
                            paneId: location.paneId,
                            repoId: repo.id,
                            worktreeId: worktree.id,
                            worktreeLabel: worktree.path.lastPathComponent,
                            tabId: location.tabId,
                            tabIndex: location.tabIndex,
                            paneIndexInTab: location.paneIndexInTab,
                            isActiveInTab: location.isActiveInTab,
                            paneDisplayLabel: paneRowFactsByPaneId[location.paneId]?.terminalTitle
                                ?? "Pane \(location.paneIndexInTab + 1)"
                        )
                    }
                    .sorted(by: paneDestinationPrecedes)
                if !destinations.isEmpty {
                    destinationsByWorktreeId[worktree.id] = destinations
                }
            }
        }
        return destinationsByWorktreeId
    }

    private static func paneDestinationsByRepoId(
        repos: [RepoPresentationItem],
        destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]]
    ) -> [UUID: [RepoExplorerPaneDestination]] {
        Dictionary(
            uniqueKeysWithValues: repos.compactMap { repo in
                let destinations = repo.worktrees
                    .flatMap { destinationsByWorktreeId[$0.id, default: []] }
                    .sorted(by: paneDestinationPrecedes)
                return destinations.isEmpty ? nil : (repo.id, destinations)
            }
        )
    }

    private static func paneDestinationPrecedes(
        _ lhs: RepoExplorerPaneDestination,
        _ rhs: RepoExplorerPaneDestination
    ) -> Bool {
        if lhs.tabIndex != rhs.tabIndex { return lhs.tabIndex < rhs.tabIndex }
        if lhs.paneIndexInTab != rhs.paneIndexInTab { return lhs.paneIndexInTab < rhs.paneIndexInTab }
        return lhs.paneId.uuidString < rhs.paneId.uuidString
    }

    private static func paneRowPrecedes(
        _ lhs: RepoExplorerPaneDestination,
        _ rhs: RepoExplorerPaneDestination,
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts],
        usesRecency: Bool
    ) -> Bool {
        if usesRecency {
            let lhsDate = paneRowFactsByPaneId[lhs.paneId]?.recencyReferenceDate
            let rhsDate = paneRowFactsByPaneId[rhs.paneId]?.recencyReferenceDate
            if lhsDate != rhsDate {
                return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
            }
        }
        return paneDestinationPrecedes(lhs, rhs)
    }

    private static func panePrimaryText(
        _ destination: RepoExplorerPaneDestination,
        terminalTitle: String?
    ) -> String {
        let paneText = "Pane \(destination.paneIndexInTab + 1)"
        let normalizedTitle = terminalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = normalizedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "zsh"
        return "\(paneText) · \(effectiveTitle)"
    }

    private static func tabPaneGroups(
        repos: [RepoPresentationItem],
        destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]],
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts],
        tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts]
    ) -> (groups: [RepoPresentationGroup], paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]]) {
        var reposById: [UUID: RepoPresentationItem] = [:]
        var destinationsByTabId: [UUID: [RepoExplorerPaneDestination]] = [:]
        for repo in repos {
            reposById[repo.id] = repo
            for worktree in repo.worktrees {
                for destination in destinationsByWorktreeId[worktree.id, default: []] {
                    destinationsByTabId[destination.tabId, default: []].append(destination)
                }
            }
        }

        var rowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:]
        let orderedTabs = destinationsByTabId.keys.sorted { lhs, rhs in
            let lhsIndex = destinationsByTabId[lhs]?.map(\.tabIndex).min() ?? .max
            let rhsIndex = destinationsByTabId[rhs]?.map(\.tabIndex).min() ?? .max
            return lhsIndex == rhsIndex ? lhs.uuidString < rhs.uuidString : lhsIndex < rhsIndex
        }
        let groups = orderedTabs.compactMap { tabId -> RepoPresentationGroup? in
            let destinations = (destinationsByTabId[tabId] ?? []).sorted { lhs, rhs in
                paneRowPrecedes(lhs, rhs, paneRowFactsByPaneId: paneRowFactsByPaneId, usesRecency: false)
            }
            guard !destinations.isEmpty else { return nil }
            let groupId = "tab:\(tabId.uuidString)"
            rowsByGroupId[groupId] = destinations.map { destination in
                RepoExplorerProjectedPaneRow(
                    groupId: groupId,
                    repoId: destination.repoId,
                    destination: destination,
                    rowId: "pane-row:\(groupId):\(destination.paneId.uuidString)",
                    primaryText: panePrimaryText(
                        destination,
                        terminalTitle: paneRowFactsByPaneId[destination.paneId]?.terminalTitle
                    ),
                    secondaryText: paneRowFactsByPaneId[destination.paneId]?.latestMessageText
                        ?? "No activity yet",
                    recencyText: paneRowFactsByPaneId[destination.paneId]?.recencyText ?? "Now",
                    isActive: paneRowFactsByPaneId[destination.paneId]?.isActive ?? false
                )
            }
            let groupRepos = destinations.reduce(into: [RepoPresentationItem]()) { result, destination in
                guard let repo = reposById[destination.repoId], !result.contains(where: { $0.id == repo.id }) else {
                    return
                }
                result.append(repo)
            }
            let fallbackOrdinal = (destinations.map(\.tabIndex).min() ?? 0) + 1
            return RepoPresentationGroup(
                id: groupId,
                repoTitle: tabGroupFactsByTabId[tabId]?.displayTitle ?? "Tab \(fallbackOrdinal)",
                organizationName: "\(destinations.count) \(destinations.count == 1 ? "pane" : "panes")",
                repos: groupRepos
            )
        }
        return (groups, rowsByGroupId)
    }

    private static func worktreeRowsByGroupId(
        from groups: [RepoPresentationGroup],
        checkoutColorHexByRepoId: [UUID: String]
    ) -> [String: [RepoExplorerProjectedWorktreeRow]] {
        Dictionary(
            uniqueKeysWithValues: groups.map { group in
                let rows = group.repos.flatMap { repo in
                    repo.worktrees.map { worktree in
                        RepoExplorerProjectedWorktreeRow(
                            groupId: group.id,
                            repo: repo,
                            worktree: worktree,
                            rowId: rowId(
                                groupId: group.id,
                                repoId: repo.id,
                                worktreeId: worktree.id,
                                location: nil
                            ),
                            checkoutColorHex: checkoutColorHexByRepoId[repo.id]
                                ?? RepoPresentationColoring.checkoutColorHex(
                                    for: repo,
                                    in: group
                                ),
                            placementContext: nil
                        )
                    }
                }
                return (group.id, rows)
            })
    }

    private static func rowId(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID,
        location: WorkspacePaneLocation?
    ) -> String {
        let placementToken = location.map { "pane:\($0.paneId.uuidString)" } ?? "inactive"
        return "worktree:\(groupId):\(repoId.uuidString):\(worktreeId.uuidString):\(placementToken)"
    }

    private static func sortedRepos(
        _ repos: [RepoPresentationItem],
        sortOrder: RepoExplorerSortOrder
    ) -> [RepoPresentationItem] {
        repos.sorted { lhs, rhs in
            compare(lhs.name, rhs.name, sortOrder: sortOrder)
        }
    }

    private static func sortedWorktrees(
        _ worktrees: [Worktree],
        sortOrder: RepoExplorerSortOrder
    ) -> [Worktree] {
        worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree
            }
            return compare(lhs.name, rhs.name, sortOrder: sortOrder)
        }
    }

    private static func compare(
        _ lhs: String,
        _ rhs: String,
        sortOrder: RepoExplorerSortOrder
    ) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        switch sortOrder {
        case .ascending:
            return comparison == .orderedAscending
        case .descending:
            return comparison == .orderedDescending
        }
    }

    private static func sortedUniqueLocations(_ locations: [WorkspacePaneLocation]) -> [WorkspacePaneLocation] {
        var seenPaneIds = Set<UUID>()
        return
            locations
            .sorted { lhs, rhs in
                if lhs.tabIndex != rhs.tabIndex {
                    return lhs.tabIndex > rhs.tabIndex
                }
                if lhs.paneIndexInTab != rhs.paneIndexInTab {
                    return lhs.paneIndexInTab > rhs.paneIndexInTab
                }
                return lhs.paneId.uuidString < rhs.paneId.uuidString
            }
            .filter { seenPaneIds.insert($0.paneId).inserted }
    }

}
