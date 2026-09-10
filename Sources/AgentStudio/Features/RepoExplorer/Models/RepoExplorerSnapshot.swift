import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

package typealias RepoExplorerGroupingMode = RepoSidebarGroupingMode
package typealias RepoExplorerSortOrder = SidebarSortDirection

extension RepoSidebarGroupingMode {
    var title: String {
        switch self {
        case .repo:
            return "Repo"
        case .activity:
            return "Activity"
        case .tab:
            return "Tab"
        }
    }

    var icon: CommandIcon {
        switch self {
        case .repo:
            return .system(.folder)
        case .activity:
            return .system(.clock)
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
    let activityAt: Date?
    let isPinned: Bool
    let noteText: String?
    let latestMessageText: String?
    let recencyReferenceDate: Date
    let recencyText: String
    let recencyTier: RepoExplorerPaneRecencyTier
    let isActive: Bool
    let isDrawerPane: Bool

    init(
        terminalTitle: String,
        activityAt: Date? = nil,
        isPinned: Bool = false,
        noteText: String? = nil,
        latestMessageText: String?,
        recencyReferenceDate: Date,
        recencyText: String,
        recencyTier: RepoExplorerPaneRecencyTier = .strongBlue,
        isActive: Bool,
        isDrawerPane: Bool = false
    ) {
        self.terminalTitle = terminalTitle
        self.activityAt = activityAt
        self.isPinned = isPinned
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

    static func nextPresentationChangeDate(referenceDate: Date, now: Date) -> Date {
        let elapsedSeconds = max(0, now.timeIntervalSince(referenceDate))
        let nextTextBoundary: TimeInterval
        if elapsedSeconds < 60 {
            nextTextBoundary = 60
        } else if elapsedSeconds < 60 * 60 {
            nextTextBoundary = (floor(elapsedSeconds / 60) + 1) * 60
        } else if elapsedSeconds < 24 * 60 * 60 {
            nextTextBoundary = (floor(elapsedSeconds / (60 * 60)) + 1) * 60 * 60
        } else {
            nextTextBoundary = (floor(elapsedSeconds / (24 * 60 * 60)) + 1) * 24 * 60 * 60
        }

        let tierBoundaries = [
            AppPolicies.EntityRecency.strongBlueDuration,
            AppPolicies.EntityRecency.mediumBlueDuration,
            AppPolicies.EntityRecency.mutedBlueDuration,
            AppPolicies.EntityRecency.faintBlueDuration,
        ]
        let nextTierBoundary = tierBoundaries.first { $0 > elapsedSeconds }
        return referenceDate.addingTimeInterval(min(nextTextBoundary, nextTierBoundary ?? nextTextBoundary))
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

extension SidebarSortDirection {
    var title: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

struct RepoExplorerSnapshot: Equatable, Sendable {
    let repos: [RepoPresentationItem]
    let repoEnrichmentSnapshotByRepoId: [UUID: RepoEnrichment]
    let surface: SidebarSurface
    let groupingMode: RepoExplorerGroupingMode
    let subgroupMode: SidebarSubgroupMode
    let sortField: SidebarSortField
    let showsPinned: Bool
    let referenceDate: Date
    let calendar: Calendar
    let sortOrder: RepoExplorerSortOrder
    let query: String
    let paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]]
    let unassociatedPaneLocations: [WorkspacePaneLocation]
    let bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]]

    init(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        surface: SidebarSurface = .repos,
        groupingMode: RepoExplorerGroupingMode = .repo,
        subgroupMode: SidebarSubgroupMode = .ungrouped,
        sortField: SidebarSortField = .name,
        showsPinned: Bool = true,
        referenceDate: Date = Date(timeIntervalSince1970: 0),
        calendar: Calendar = .current,
        sortOrder: RepoExplorerSortOrder = .default,
        query: String,
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:],
        unassociatedPaneLocations: [WorkspacePaneLocation] = [],
        bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]] = [:]
    ) {
        self.repos = repos
        self.repoEnrichmentSnapshotByRepoId = repoEnrichmentByRepoId
        self.surface = surface
        self.groupingMode = groupingMode
        self.subgroupMode = subgroupMode
        self.sortField = sortField
        self.showsPinned = showsPinned
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.sortOrder = sortOrder
        self.query = query
        self.paneLocationsByWorktreeId = paneLocationsByWorktreeId
        self.unassociatedPaneLocations = unassociatedPaneLocations
        self.bridgePaneCommandCandidatesByWorktreeId = bridgePaneCommandCandidatesByWorktreeId
    }

    func replacing(
        repos: [RepoPresentationItem]? = nil,
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]? = nil,
        surface: SidebarSurface? = nil,
        groupingMode: RepoExplorerGroupingMode? = nil,
        subgroupMode: SidebarSubgroupMode? = nil,
        sortField: SidebarSortField? = nil,
        showsPinned: Bool? = nil,
        referenceDate: Date? = nil,
        calendar: Calendar? = nil,
        sortOrder: RepoExplorerSortOrder? = nil,
        query: String? = nil,
        bridgePaneCommandCandidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]]? = nil
    ) -> Self {
        Self(
            repos: repos ?? self.repos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId ?? repoEnrichmentSnapshotByRepoId,
            surface: surface ?? self.surface,
            groupingMode: groupingMode ?? self.groupingMode,
            subgroupMode: subgroupMode ?? self.subgroupMode,
            sortField: sortField ?? self.sortField,
            showsPinned: showsPinned ?? self.showsPinned,
            referenceDate: referenceDate ?? self.referenceDate,
            calendar: calendar ?? self.calendar,
            sortOrder: sortOrder ?? self.sortOrder,
            query: query ?? self.query,
            paneLocationsByWorktreeId: paneLocationsByWorktreeId,
            unassociatedPaneLocations: unassociatedPaneLocations,
            bridgePaneCommandCandidatesByWorktreeId: bridgePaneCommandCandidatesByWorktreeId
                ?? self.bridgePaneCommandCandidatesByWorktreeId
        )
    }
}
