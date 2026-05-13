import Foundation

struct InboxNotificationSourceDisplay: Sendable, Equatable {
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
    private let paneGroupLabel: String
    private let tabGroupLabel: String
    private let filterLabels: [InboxFilter: String]

    init(
        notification: InboxNotification,
        rowContext: RowContext = .globalInbox
    ) {
        let title = notification.title.trimmedNonEmpty
        let body = notification.body.trimmedNonEmpty
        self.primaryText = title ?? body ?? Self.kindLabel(notification.kind)
        self.detailText = title == nil ? nil : body
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
            self.paneGroupLabel = "Workspace"
            self.tabGroupLabel = "Workspace"
            self.filterLabels = [:]
        case .pane(let source):
            let sourceLine = Self.sourceLine(for: source)
            let placementLine = Self.placementLine(for: source, rowContext: rowContext)
            self.sourceLine = sourceLine
            self.placementLine = placementLine
            self.searchText = Self.joinSearchTerms([
                primaryText,
                detailText,
                sourceLine,
                placementLine,
                source.runtimeDisplayLabel,
                source.tabDisplayLabel,
                source.paneDisplayLabel,
                source.parentPaneDisplayLabel,
            ])
            self.repoGroupLabel = (source.repo?.name).trimmedNonEmpty ?? "Pane"
            self.paneGroupLabel = Self.paneGroupLabel(for: source)
            self.tabGroupLabel = source.tabDisplayLabel.trimmedNonEmpty ?? "Pane"
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
            return paneGroupLabel
        case .byTab:
            return tabGroupLabel
        }
    }

    func filterLabel(for filter: InboxFilter) -> String? {
        filterLabels[filter]
    }

    private static func sourceLine(for source: InboxNotification.PaneSource) -> String {
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
        rowContext: RowContext
    ) -> String? {
        var parts: [String] = []
        switch rowContext {
        case .globalInbox:
            if let tabDisplayLabel = source.tabDisplayLabel.trimmedNonEmpty {
                parts.append("Tab \(tabDisplayLabel)")
            }
            appendPanePlacement(for: source, to: &parts)
        case .paneInbox(let parentPaneId):
            if source.paneRole == .drawerChild,
                source.parentPaneId == parentPaneId,
                let paneDisplayLabel = source.paneDisplayLabel.trimmedNonEmpty
            {
                parts.append("Drawer \(paneDisplayLabel)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func appendPanePlacement(
        for source: InboxNotification.PaneSource,
        to parts: inout [String]
    ) {
        switch source.paneRole {
        case .main:
            if let paneDisplayLabel = source.paneDisplayLabel.trimmedNonEmpty {
                parts.append("Pane \(paneDisplayLabel)")
            }
        case .drawerChild:
            if let parentPaneDisplayLabel = source.parentPaneDisplayLabel.trimmedNonEmpty {
                parts.append("Pane \(parentPaneDisplayLabel)")
            }
            if let paneDisplayLabel = source.paneDisplayLabel.trimmedNonEmpty {
                parts.append("Drawer \(paneDisplayLabel)")
            } else if let drawerOrdinal = source.drawerOrdinal {
                parts.append("Drawer \(drawerOrdinal)")
            } else {
                parts.append("Drawer")
            }
        }
    }

    private static func paneGroupLabel(for source: InboxNotification.PaneSource) -> String {
        switch source.paneRole {
        case .main:
            return source.paneDisplayLabel.trimmedNonEmpty
                ?? (source.worktree?.name).trimmedNonEmpty
                ?? source.branchName.trimmedNonEmpty
                ?? source.runtimeDisplayLabel.trimmedNonEmpty
                ?? "Pane"
        case .drawerChild:
            let parentTitle = source.parentPaneDisplayLabel.trimmedNonEmpty ?? "Pane"
            if let paneTitle = source.paneDisplayLabel.trimmedNonEmpty {
                return "\(parentTitle) / Drawer \(paneTitle)"
            }
            if let drawerOrdinal = source.drawerOrdinal {
                return "\(parentTitle) / Drawer \(drawerOrdinal)"
            }
            return "\(parentTitle) / Drawer"
        }
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
        case .approvalRequested:
            return "Approval requested"
        case .securityEvent:
            return "Security event"
        }
    }
}
