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

enum RepoExplorerPaneSecondaryLine: Equatable, Sendable {
    case note(String)
    case terminalOutput(String)

    var text: String {
        switch self {
        case .note(let text), .terminalOutput(let text): text
        }
    }

    var iconSystemName: String {
        switch self {
        case .note: "long.text.page.and.pencil"
        case .terminalOutput: "apple.terminal"
        }
    }

    var isTerminalOutput: Bool {
        if case .terminalOutput = self { return true }
        return false
    }
}

struct RepoExplorerPaneRowFacts: Equatable, Sendable {
    let terminalTitle: String
    let noteText: String?
    let latestMessageText: String?
    let recencyReferenceDate: Date
    let recencyText: String
    let recencyTier: RepoExplorerPaneRecencyTier
    let isActive: Bool
    let isDrawerPane: Bool

    init(
        terminalTitle: String,
        noteText: String? = nil,
        latestMessageText: String?,
        recencyReferenceDate: Date,
        recencyText: String,
        recencyTier: RepoExplorerPaneRecencyTier = .strongBlue,
        isActive: Bool,
        isDrawerPane: Bool = false
    ) {
        self.terminalTitle = terminalTitle
        self.noteText = noteText
        self.latestMessageText = latestMessageText
        self.recencyReferenceDate = recencyReferenceDate
        self.recencyText = recencyText
        self.recencyTier = recencyTier
        self.isActive = isActive
        self.isDrawerPane = isDrawerPane
    }

    var secondaryLine: RepoExplorerPaneSecondaryLine? {
        if let noteText = normalizedSecondaryText(noteText) {
            return .note(noteText)
        }
        return normalizedSecondaryText(latestMessageText).map(RepoExplorerPaneSecondaryLine.terminalOutput)
    }

    var sidebarTerminalTitle: String {
        let normalizedTitle = terminalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDrawerPane, normalizedTitle.caseInsensitiveCompare("Drawer") == .orderedSame else {
            return terminalTitle
        }
        return "zsh"
    }

    private func normalizedSecondaryText(_ text: String?) -> String? {
        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedText, !normalizedText.isEmpty else { return nil }
        return normalizedText
    }
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

enum RepoExplorerPaneRecencyTier: Equatable, Sendable {
    case strongBlue
    case mediumBlue
    case mutedBlue
    case faintBlue
    case grey

    static func classify(referenceDate: Date, now: Date) -> Self {
        let elapsed = max(0, now.timeIntervalSince(referenceDate))
        if elapsed < AppPolicies.EntityRecency.strongBlueDuration { return .strongBlue }
        if elapsed < AppPolicies.EntityRecency.mediumBlueDuration { return .mediumBlue }
        if elapsed < AppPolicies.EntityRecency.mutedBlueDuration { return .mutedBlue }
        if elapsed < AppPolicies.EntityRecency.faintBlueDuration { return .faintBlue }
        return .grey
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
    let unassociatedPaneLocations: [WorkspacePaneLocation]
    let bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]]

    init(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode = .repo,
        sortOrder: RepoExplorerSortOrder = .default,
        query: String,
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:],
        unassociatedPaneLocations: [WorkspacePaneLocation] = [],
        bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]] = [:]
    ) {
        self.repos = repos
        self.repoEnrichmentSnapshotByRepoId = repoEnrichmentByRepoId
        self.groupingMode = groupingMode
        self.sortOrder = sortOrder
        self.query = query
        self.paneLocationsByWorktreeId = paneLocationsByWorktreeId
        self.unassociatedPaneLocations = unassociatedPaneLocations
        self.bridgePaneCommandCandidatesByWorktreeId = bridgePaneCommandCandidatesByWorktreeId
    }
}
