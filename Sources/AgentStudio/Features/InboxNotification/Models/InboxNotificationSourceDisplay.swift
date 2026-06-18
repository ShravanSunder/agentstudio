import Foundation

struct InboxNotificationSourceDisplay: Sendable, Equatable {
    struct GroupHeaderText: Sendable, Equatable {
        let primary: String
        let secondary: String?
    }

    enum RowContext: Sendable, Equatable {
        case globalInbox
        case paneInbox(parentPaneId: UUID)
    }

    let primaryText: String
    let sourceLine: String
    let placementLine: String?
    let detailText: String?
    let searchText: String

    private let repoGroupLabel: String
    private let paneGroupHeaderText: GroupHeaderText
    private let tabGroupHeaderText: GroupHeaderText
    private let filterLabels: [InboxFilter: String]

    init(
        notification: InboxNotification,
        rowContext: RowContext = .globalInbox,
        grouping: InboxNotificationGrouping = .none
    ) {
        let title = notification.title.trimmedNonEmpty
        let body = notification.body.trimmedNonEmpty
        self.primaryText = title ?? body ?? Self.kindLabel(notification.kind)
        self.detailText = title == nil ? nil : Self.detailText(for: body)
        switch notification.source {
        case .global:
            self.sourceLine = "Workspace event"
            self.placementLine = nil
            self.searchText = Self.joinSearchTerms([
                primaryText,
                detailText,
                "Workspace event",
            ])
            self.repoGroupLabel = "Workspace"
            self.paneGroupHeaderText = .init(primary: "Workspace", secondary: nil)
            self.tabGroupHeaderText = .init(primary: "Workspace", secondary: nil)
            self.filterLabels = [:]
        case .pane(let source):
            let sourceLine = Self.sourceLine(for: source, grouping: grouping)
            let placementLine = Self.placementLine(for: source, rowContext: rowContext, grouping: grouping)
            self.sourceLine = sourceLine
            self.placementLine = placementLine
            self.searchText = Self.joinSearchTerms([
                primaryText,
                detailText,
                Self.sourceLine(for: source),
                Self.defaultPlacementLine(for: source, rowContext: rowContext),
                sourceLine,
                placementLine,
                source.runtimeDisplayLabel,
                source.tabDisplayLabel,
                source.paneDisplayLabel,
                source.parentPaneDisplayLabel,
            ])
            self.repoGroupLabel = (source.repo?.name).trimmedNonEmpty ?? "Pane"
            self.paneGroupHeaderText = Self.paneGroupHeaderText(for: source)
            self.tabGroupHeaderText = Self.tabGroupHeaderText(for: source)
            self.filterLabels = Self.filterLabels(for: source)
        }
    }

    func groupLabel(for grouping: InboxNotificationGrouping) -> String? {
        switch grouping {
        case .none:
            return nil
        case .byRepo:
            return repoGroupLabel
        case .byPane:
            return paneGroupHeaderText.primary
        case .byTab:
            return tabGroupHeaderText.primary
        }
    }

    func groupHeaderText(for grouping: InboxNotificationGrouping) -> GroupHeaderText? {
        switch grouping {
        case .none:
            return nil
        case .byRepo:
            return GroupHeaderText(primary: repoGroupLabel, secondary: nil)
        case .byPane:
            return paneGroupHeaderText
        case .byTab:
            return tabGroupHeaderText
        }
    }

    func filterLabel(for filter: InboxFilter) -> String? {
        filterLabels[filter]
    }

    private static func detailText(for body: String?) -> String? {
        guard body != "Output appeared while you were away" else { return nil }
        return body
    }

    private static func sourceLine(
        for source: InboxNotification.PaneSource,
        grouping: InboxNotificationGrouping = .none
    ) -> String {
        if grouping == .byRepo, let tabLine = tabPlacementLine(for: source) {
            return tabLine
        }
        return repoSourceLine(for: source)
    }

    private static func repoSourceLine(for source: InboxNotification.PaneSource) -> String {
        if let repoName = (source.repo?.name).trimmedNonEmpty {
            if let worktreeName = (source.worktree?.name).trimmedNonEmpty {
                if let branchName = source.branchName.trimmedNonEmpty, branchName != worktreeName {
                    return "\(repoName) · \(worktreeName) / \(branchName)"
                }
                return "\(repoName) · \(worktreeName)"
            }
            return repoName
        }

        if let worktreeName = (source.worktree?.name).trimmedNonEmpty {
            if let branchName = source.branchName.trimmedNonEmpty, branchName != worktreeName {
                return "\(worktreeName) / \(branchName)"
            }
            return worktreeName
        }

        if let branchName = source.branchName.trimmedNonEmpty {
            return branchName
        }

        if let runtimeDisplayLabel = source.runtimeDisplayLabel.trimmedNonEmpty {
            return runtimeDisplayLabel
        }

        return "Pane event"
    }

    private static func placementLine(
        for source: InboxNotification.PaneSource,
        rowContext: RowContext,
        grouping: InboxNotificationGrouping = .none
    ) -> String? {
        guard case .globalInbox = rowContext else {
            return paneInboxPlacementLine(for: source, rowContext: rowContext)
        }
        switch grouping {
        case .none:
            return defaultPlacementLine(for: source, rowContext: rowContext)
        case .byRepo, .byTab:
            return panePlacementLine(for: source)
        case .byPane:
            var parts: [String] = []
            if let tabLine = tabPlacementLine(for: source) {
                parts.append(tabLine)
            }
            if source.paneRole == .drawerChild, let drawerLine = drawerPlacementLine(for: source) {
                parts.append(drawerLine)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    private static func defaultPlacementLine(
        for source: InboxNotification.PaneSource,
        rowContext: RowContext
    ) -> String? {
        var parts: [String] = []
        switch rowContext {
        case .globalInbox:
            if let tabLine = tabPlacementLine(for: source) {
                parts.append(tabLine)
            }
            if let paneLine = panePlacementLine(for: source) {
                parts.append(paneLine)
            }
        case .paneInbox(let parentPaneId):
            if let paneInboxPlacementLine = paneInboxPlacementLine(
                for: source, rowContext: .paneInbox(parentPaneId: parentPaneId))
            {
                parts.append(paneInboxPlacementLine)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func paneInboxPlacementLine(
        for source: InboxNotification.PaneSource,
        rowContext: RowContext
    ) -> String? {
        guard case .paneInbox(let parentPaneId) = rowContext else { return nil }
        guard source.paneRole == .drawerChild, source.parentPaneId == parentPaneId else { return nil }
        return drawerPlacementLine(for: source)
    }

    private static func tabPlacementLine(for source: InboxNotification.PaneSource) -> String? {
        guard let tabDisplayLabel = source.tabDisplayLabel.trimmedNonEmpty else { return nil }
        if let tabOrdinal = source.tabOrdinal {
            return "Tab \(tabOrdinal) · \(tabDisplayLabel)"
        }
        return "Tab \(tabDisplayLabel)"
    }

    private static func panePlacementLine(for source: InboxNotification.PaneSource) -> String? {
        switch source.paneRole {
        case .main:
            return labelledOrdinalLine(
                ordinalPrefix: "Pane",
                ordinal: source.paneOrdinal,
                displayLabel: source.paneDisplayLabel.trimmedNonEmpty
            )
        case .drawerChild:
            var parts: [String] = []
            if let parentLine = labelledOrdinalLine(
                ordinalPrefix: "Pane",
                ordinal: source.parentPaneOrdinal,
                displayLabel: source.parentPaneDisplayLabel.trimmedNonEmpty
            ) {
                parts.append(parentLine)
            }
            if let drawerLine = drawerPlacementLine(for: source) {
                parts.append(drawerLine)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    private static func drawerPlacementLine(for source: InboxNotification.PaneSource) -> String? {
        if let paneDisplayLabel = source.paneDisplayLabel.trimmedNonEmpty {
            return labelledOrdinalLine(
                ordinalPrefix: "Drawer",
                ordinal: source.drawerOrdinal,
                displayLabel: paneDisplayLabel
            )
        }
        if let drawerOrdinal = source.drawerOrdinal {
            return "Drawer \(drawerOrdinal)"
        }
        return source.paneRole == .drawerChild ? "Drawer" : nil
    }

    private static func labelledOrdinalLine(
        ordinalPrefix: String,
        ordinal: Int?,
        displayLabel: String?
    ) -> String? {
        guard let displayLabel else {
            guard let ordinal else { return nil }
            return "\(ordinalPrefix) \(ordinal)"
        }
        guard let ordinal else { return "\(ordinalPrefix) \(displayLabel)" }
        return "\(ordinalPrefix) \(ordinal) · \(displayLabel)"
    }

    private static func paneGroupHeaderText(for source: InboxNotification.PaneSource) -> GroupHeaderText {
        switch source.paneRole {
        case .main:
            return GroupHeaderText(
                primary: source.paneDisplayLabel.trimmedNonEmpty
                    ?? (source.worktree?.name).trimmedNonEmpty
                    ?? source.branchName.trimmedNonEmpty
                    ?? source.runtimeDisplayLabel.trimmedNonEmpty
                    ?? "Pane",
                secondary: source.paneOrdinal.map { "Pane \($0)" }
            )
        case .drawerChild:
            return GroupHeaderText(
                primary: source.parentPaneDisplayLabel.trimmedNonEmpty
                    ?? (source.worktree?.name).trimmedNonEmpty
                    ?? source.branchName.trimmedNonEmpty
                    ?? source.runtimeDisplayLabel.trimmedNonEmpty
                    ?? "Pane",
                secondary: source.parentPaneOrdinal.map { "Pane \($0)" }
            )
        }
    }

    private static func tabGroupHeaderText(for source: InboxNotification.PaneSource) -> GroupHeaderText {
        GroupHeaderText(
            primary: source.tabDisplayLabel.trimmedNonEmpty ?? "Pane",
            secondary: source.tabOrdinal.map { "Tab \($0)" }
        )
    }

    private static func filterLabels(for source: InboxNotification.PaneSource) -> [InboxFilter: String] {
        var labels: [InboxFilter: String] = [:]
        if let repoId = source.repo?.id {
            labels[.repo(id: repoId)] = (source.repo?.name).trimmedNonEmpty ?? "Filtered repo"
        }
        if let worktreeId = source.worktree?.id {
            labels[.worktree(id: worktreeId)] = (source.worktree?.name).trimmedNonEmpty ?? "Filtered worktree"
        }
        return labels
    }

    private static func joinSearchTerms(_ terms: [String?]) -> String {
        terms
            .compactMap { $0.trimmedNonEmpty }
            .joined(separator: " ")
    }

    private static func kindLabel(_ kind: InboxNotificationKind) -> String {
        switch kind {
        case .agentDesktopNotification:
            return "Desktop notification"
        case .bellRang:
            return "Bell"
        case .commandFinished:
            return "Command finished"
        case .terminalSecureInputRequested:
            return "Secure input requested"
        case .terminalProgressError:
            return "Terminal progress error"
        case .terminalRendererUnhealthy:
            return "Terminal renderer unhealthy"
        case .persistenceRecovery:
            return "Persistence recovery"
        case .agentRpc:
            return "Agent notification"
        case .unseenActivity:
            return "New terminal activity"
        case .agentSettledActivity:
            return "Agent appears settled"
        case .approvalRequested:
            return "Approval requested"
        case .securityEvent:
            return "Security event"
        }
    }
}
