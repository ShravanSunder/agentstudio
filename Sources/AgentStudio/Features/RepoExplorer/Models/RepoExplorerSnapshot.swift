import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

package typealias RepoExplorerGroupingMode = RepoSidebarGroupingMode

extension RepoSidebarGroupingMode {
    var title: String {
        switch self {
        case .repo:
            return "By Repo"
        case .pane:
            return "All Panes"
        case .tab:
            return "By Tab"
        }
    }

    var icon: CommandIcon {
        switch self {
        case .repo:
            return .system(.folder)
        case .pane:
            return .system(.rectangleSplit2x1)
        case .tab:
            return .system(.rectangleStack)
        }
    }
}

struct RepoExplorerPaneRowFacts: Equatable, Sendable {
    let terminalTitle: String
    let latestMessageText: String?
    let recencyReferenceDate: Date
    let recencyText: String
    let isActive: Bool
}

struct RepoExplorerTabGroupFacts: Equatable, Sendable {
    let displayTitle: String
}

enum RepoExplorerPaneRecencyText {
    static func display(lastInteractedAt: Date, now: Date) -> String {
        let elapsedSeconds = max(0, now.timeIntervalSince(lastInteractedAt))
        let elapsedMinutes = Int(elapsedSeconds / 60)
        if elapsedMinutes < 1 { return "Now" }
        if elapsedMinutes < 60 { return "\(elapsedMinutes)m" }
        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 { return "\(elapsedHours)h" }
        return "\(elapsedHours / 24)d"
    }
}

package enum RepoExplorerSortOrder: String, CaseIterable, Codable, Hashable, Sendable {
    case ascending
    case descending

    package static let `default`: Self = .ascending

    package var toggled: Self {
        switch self {
        case .ascending:
            return .descending
        case .descending:
            return .ascending
        }
    }

    var title: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }
}

struct RepoExplorerSnapshot: Equatable, Sendable {
    let repos: [RepoPresentationItem]
    let repoEnrichmentSnapshotByRepoId: [UUID: RepoEnrichment]
    let groupingMode: RepoExplorerGroupingMode
    let sortOrder: RepoExplorerSortOrder
    let query: String
    let paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]]
    let bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]]

    init(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode = .repo,
        sortOrder: RepoExplorerSortOrder = .default,
        query: String,
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:],
        bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]] = [:]
    ) {
        self.repos = repos
        self.repoEnrichmentSnapshotByRepoId = repoEnrichmentByRepoId
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
        self.query = query
        self.paneLocationsByWorktreeId = paneLocationsByWorktreeId
        self.bridgePaneCommandCandidatesByWorktreeId = bridgePaneCommandCandidatesByWorktreeId
    }
}
