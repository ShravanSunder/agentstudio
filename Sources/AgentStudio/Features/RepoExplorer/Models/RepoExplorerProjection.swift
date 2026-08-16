import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

enum RepoExplorerEmptyState: Equatable, Sendable {
    case content
    case searchNoResults
}

enum RepoExplorerSidebarSectionKind: String, Equatable, Sendable {
    case favorites
    case panes
    case repositories
    case tabs
    case ungrouped

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .panes: "Panes"
        case .repositories: "Repositories"
        case .tabs: "Tabs"
        case .ungrouped: "Ungrouped"
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

    var id: UUID { paneId }

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

struct RepoExplorerProjectedPaneRow: Equatable, Sendable {
    let groupId: String
    let repoId: UUID
    let destination: RepoExplorerPaneDestination
    let rowId: String
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
    private struct PlacementEntry {
        let repo: RepoPresentationItem
        let worktree: Worktree
        let location: WorkspacePaneLocation?
    }

    static func project(_ snapshot: RepoExplorerSnapshot) -> RepoExplorerSidebarProjection {
        projectCancellable(snapshot, cancellationCheck: {})
    }

    static func projectCancellable(
        _ snapshot: RepoExplorerSnapshot,
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
        let paneDestinationsByWorktreeId = paneDestinationsByWorktreeId(
            repos: snapshot.repos,
            locationsByWorktreeId: snapshot.paneLocationsByWorktreeId
        )
        let paneDestinationsByRepoId = paneDestinationsByRepoId(
            repos: snapshot.repos,
            destinationsByWorktreeId: paneDestinationsByWorktreeId
        )
        let unassociatedPaneDestinations = unassociatedPaneDestinations(snapshot)
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
                destinationsByWorktreeId: paneDestinationsByWorktreeId
            )
            resolvedGroups = paneProjection.groups
            projectedRowsByGroupId = [:]
            projectedPaneRowsByGroupId = paneProjection.paneRowsByGroupId
        case .tab:
            let placementProjection = try placementGroups(
                repos: filteredResolvedRepos,
                locationsByWorktreeId: snapshot.paneLocationsByWorktreeId,
                mode: .tab,
                sortOrder: snapshot.sortOrder,
                checkoutColorHexByRepoId: checkoutColorHexByRepoId,
                cancellationCheck: cancellationCheck
            )
            let partitionedProjection = partitionTabGroups(
                groups: placementProjection.groups,
                worktreeRowsByGroupId: placementProjection.worktreeRowsByGroupId
            )
            resolvedGroups = partitionedProjection.groups
            projectedRowsByGroupId = partitionedProjection.worktreeRowsByGroupId
            projectedPaneRowsByGroupId = [:]
        }

        let sections = sidebarSections(
            groupingMode: snapshot.groupingMode,
            resolvedGroups: resolvedGroups,
            loadingRepos: filteredLoadingRepos,
            unassociatedPaneDestinations: unassociatedPaneDestinations
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
                    loadingRepos: orderedLoadingRepos,
                    hasUnassociatedPanes: snapshot.groupingMode == .pane
                        && !unassociatedPaneDestinations.isEmpty
                )
            )
        )
    }

    private static func unassociatedPaneDestinations(
        _ snapshot: RepoExplorerSnapshot
    ) -> [RepoExplorerUnassociatedPaneDestination] {
        let destinations = RepoExplorerPaneLocationProjection.unassociatedDestinations(
            from: sortedUniqueLocations(snapshot.unassociatedPaneLocations)
        )
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return destinations }
        return destinations.filter { destination in
            let activeLabel = destination.isActiveInTab ? " active" : ""
            let searchableLabel =
                "ungrouped tab \(destination.tabIndex + 1) pane \(destination.paneIndexInTab + 1)\(activeLabel)"
            return searchableLabel.localizedCaseInsensitiveContains(query)
        }
    }

    private static func sidebarSections(
        groupingMode: RepoExplorerGroupingMode,
        resolvedGroups: [RepoPresentationGroup],
        loadingRepos: [RepoPresentationItem],
        unassociatedPaneDestinations: [RepoExplorerUnassociatedPaneDestination]
    ) -> [RepoExplorerSidebarSection] {
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
        if groupingMode == .pane && !unassociatedPaneDestinations.isEmpty {
            sections.append(
                RepoExplorerSidebarSection(
                    kind: .ungrouped,
                    resolvedGroups: [],
                    loadingRepos: [],
                    unassociatedPaneDestinations: unassociatedPaneDestinations
                )
            )
        }
        return sections
    }

    private static func partitionTabGroups(
        groups: [RepoPresentationGroup],
        worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]
    ) -> (groups: [RepoPresentationGroup], worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]]) {
        var favoriteGroups: [RepoPresentationGroup] = []
        var regularGroups: [RepoPresentationGroup] = []
        var partitionedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:]

        for group in groups {
            let rows = worktreeRowsByGroupId[group.id, default: []]
            let favoriteRows = rows.filter { $0.repo.isFavorite }
            let regularRows = rows.filter { !$0.repo.isFavorite }

            if !favoriteRows.isEmpty {
                let favoriteGroupId = "\(group.id):favorites"
                favoriteGroups.append(
                    RepoPresentationGroup(
                        id: favoriteGroupId,
                        repoTitle: group.repoTitle,
                        organizationName: group.organizationName,
                        repos: group.repos.filter(\.isFavorite)
                    )
                )
                partitionedRowsByGroupId[favoriteGroupId] = favoriteRows.map { row in
                    RepoExplorerProjectedWorktreeRow(
                        groupId: favoriteGroupId,
                        repo: row.repo,
                        worktree: row.worktree,
                        rowId: "\(row.rowId):favorites",
                        checkoutColorHex: row.checkoutColorHex,
                        placementContext: row.placementContext
                    )
                }
            }

            if !regularRows.isEmpty {
                regularGroups.append(
                    RepoPresentationGroup(
                        id: group.id,
                        repoTitle: group.repoTitle,
                        organizationName: group.organizationName,
                        repos: group.repos.filter { !$0.isFavorite }
                    )
                )
                partitionedRowsByGroupId[group.id] = regularRows
            }
        }

        return (favoriteGroups + regularGroups, partitionedRowsByGroupId)
    }

    private static func emptyState(
        snapshot: RepoExplorerSnapshot,
        resolvedGroups: [RepoPresentationGroup],
        loadingRepos: [RepoPresentationItem],
        hasUnassociatedPanes: Bool
    ) -> RepoExplorerEmptyState {
        guard resolvedGroups.isEmpty && loadingRepos.isEmpty && !hasUnassociatedPanes else { return .content }
        if !snapshot.query.isEmpty {
            return .searchNoResults
        }
        return .content
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
        destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]]
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
                .sorted(by: paneDestinationPrecedes)
            guard !destinations.isEmpty else { return nil }

            let groupId = "pane-repo:\(repo.id.uuidString)"
            paneRowsByGroupId[groupId] = destinations.map { destination in
                RepoExplorerProjectedPaneRow(
                    groupId: groupId,
                    repoId: repo.id,
                    destination: destination,
                    rowId: "pane-row:\(groupId):\(destination.paneId.uuidString)"
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
        locationsByWorktreeId: [UUID: [WorkspacePaneLocation]]
    ) -> [UUID: [RepoExplorerPaneDestination]] {
        var destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]] = [:]
        for repo in repos {
            for worktree in repo.worktrees {
                let destinations = sortedUniqueLocations(locationsByWorktreeId[worktree.id, default: []])
                    .map { location in
                        RepoExplorerPaneDestination(
                            paneId: location.paneId,
                            repoId: repo.id,
                            worktreeId: worktree.id,
                            worktreeLabel: worktree.name,
                            tabId: location.tabId,
                            tabIndex: location.tabIndex,
                            paneIndexInTab: location.paneIndexInTab,
                            isActiveInTab: location.isActiveInTab
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

    private static func placementGroups(
        repos: [RepoPresentationItem],
        locationsByWorktreeId: [UUID: [WorkspacePaneLocation]],
        mode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder,
        checkoutColorHexByRepoId: [UUID: String],
        cancellationCheck: () throws -> Void
    ) rethrows -> (groups: [RepoPresentationGroup], worktreeRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]])
    {
        let locations = sortedUniqueLocations(locationsByWorktreeId.values.flatMap { $0 })

        var entriesByGroupId: [String: [PlacementEntry]] = [:]
        var groupLabelsById: [String: (title: String, secondary: String?)] = [:]
        var paneModeSeenWorktreesByGroup: [String: Set<UUID>] = [:]

        func appendGroupIfNeeded(_ groupId: String, title: String, secondary: String? = nil) {
            guard groupLabelsById[groupId] == nil else { return }
            groupLabelsById[groupId] = (title, secondary)
        }

        var processedWorktreeCount = 0
        for repo in sortedRepos(repos, sortOrder: sortOrder) {
            for worktree in sortedWorktrees(repo.worktrees, sortOrder: sortOrder) {
                if processedWorktreeCount.isMultiple(of: 256) { try cancellationCheck() }
                processedWorktreeCount += 1
                let worktreeLocations = sortedUniqueLocations(locationsByWorktreeId[worktree.id] ?? [])
                guard !worktreeLocations.isEmpty else { continue }

                for location in worktreeLocations {
                    switch mode {
                    case .repo:
                        continue
                    case .pane:
                        let groupId = "pane:\(location.paneId.uuidString)"
                        if paneModeSeenWorktreesByGroup[groupId, default: []].contains(worktree.id) {
                            continue
                        }
                        paneModeSeenWorktreesByGroup[groupId, default: []].insert(worktree.id)
                        let paneOrdinal = location.paneIndexInTab + 1
                        let tabOrdinal = location.tabIndex + 1
                        appendGroupIfNeeded(groupId, title: "Pane \(paneOrdinal)", secondary: "Tab \(tabOrdinal)")
                        entriesByGroupId[groupId, default: []].append(
                            PlacementEntry(repo: repo, worktree: worktree, location: location)
                        )
                    case .tab:
                        let groupId = "tab:\(location.tabId.uuidString)"
                        let tabOrdinal = location.tabIndex + 1
                        appendGroupIfNeeded(groupId, title: "Tab \(tabOrdinal)")
                        entriesByGroupId[groupId, default: []].append(
                            PlacementEntry(repo: repo, worktree: worktree, location: location)
                        )
                    }
                }
            }
        }

        let activeGroupIds: [String] =
            switch mode {
            case .repo:
                []
            case .pane:
                locations.reduce(into: (ids: [String](), seen: Set<UUID>())) { result, location in
                    guard result.seen.insert(location.paneId).inserted else { return }
                    result.ids.append("pane:\(location.paneId.uuidString)")
                }.ids
            case .tab:
                RepoExplorerPaneLocationProjection.sortedUniqueTabIds(locations).map { "tab:\($0.uuidString)" }
            }
        let orderedGroupIds = activeGroupIds.filter { !(entriesByGroupId[$0] ?? []).isEmpty }

        var projectedRowsByGroupId: [String: [RepoExplorerProjectedWorktreeRow]] = [:]
        let groups: [RepoPresentationGroup] = orderedGroupIds.compactMap { groupId in
            guard let label = groupLabelsById[groupId], let entries = entriesByGroupId[groupId], !entries.isEmpty else {
                return nil
            }
            let orderedEntries = entries.filter(\.repo.isFavorite) + entries.filter { !$0.repo.isFavorite }
            projectedRowsByGroupId[groupId] = projectedWorktreeRows(
                from: orderedEntries,
                groupId: groupId,
                checkoutColorHexByRepoId: checkoutColorHexByRepoId
            )
            return RepoPresentationGroup(
                id: groupId,
                repoTitle: label.title,
                organizationName: label.secondary,
                repos: repoItems(from: orderedEntries)
            )
        }
        try cancellationCheck()
        return (groups, projectedRowsByGroupId)
    }

    private static func repoItems(from entries: [PlacementEntry]) -> [RepoPresentationItem] {
        var reposById: [UUID: RepoPresentationItem] = [:]
        var repoOrder: [UUID] = []
        for entry in entries {
            if reposById[entry.repo.id] == nil {
                var repo = entry.repo
                repo.worktrees = []
                reposById[entry.repo.id] = repo
                repoOrder.append(entry.repo.id)
            }
            reposById[entry.repo.id]?.worktrees.append(entry.worktree)
        }

        return repoOrder.compactMap { reposById[$0] }
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

    private static func projectedWorktreeRows(
        from entries: [PlacementEntry],
        groupId: String,
        checkoutColorHexByRepoId: [UUID: String]
    ) -> [RepoExplorerProjectedWorktreeRow] {
        entries.map { entry in
            RepoExplorerProjectedWorktreeRow(
                groupId: groupId,
                repo: entry.repo,
                worktree: entry.worktree,
                rowId: rowId(
                    groupId: groupId,
                    repoId: entry.repo.id,
                    worktreeId: entry.worktree.id,
                    location: entry.location
                ),
                checkoutColorHex: checkoutColorHexByRepoId[entry.repo.id]
                    ?? RepoPresentationGrouping.automaticPaletteHexes[0],
                placementContext: entry.location.map {
                    RepoExplorerPlacementContext(
                        paneId: $0.paneId,
                        tabId: $0.tabId,
                        tabIndex: $0.tabIndex,
                        paneIndexInTab: $0.paneIndexInTab,
                        isActiveInTab: $0.isActiveInTab
                    )
                }
            )
        }
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
