import Foundation

struct InboxNotificationSourceDisplay: Sendable, Equatable {
    enum RowContext: Sendable, Equatable {
        case globalInbox
        case paneInbox(parentPaneId: UUID)
    }

    let sourceLine: String
    let placementLine: String?
    let searchText: String

    private let repoGroupLabel: String
    private let paneGroupLabel: String
    private let tabGroupLabel: String
    private let filterLabels: [InboxFilter: String]

    init(
        notification: InboxNotification,
        rowContext: RowContext = .globalInbox
    ) {
        switch notification.source {
        case .global:
            self.sourceLine = "Workspace event"
            self.placementLine = nil
            self.searchText = Self.joinSearchTerms([
                notification.title,
                notification.body,
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
                notification.title,
                notification.body,
                sourceLine,
                placementLine,
                source.runtimeDisplayLabel,
                source.tabDisplayLabel,
                source.paneDisplayLabel,
                source.parentPaneDisplayLabel,
            ])
            self.repoGroupLabel = Self.nonBlank(source.repo?.name) ?? "Pane"
            self.paneGroupLabel = Self.paneGroupLabel(for: source)
            self.tabGroupLabel = Self.nonBlank(source.tabDisplayLabel) ?? "Pane"
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
        if let repoName = nonBlank(source.repo?.name) {
            if let worktreeName = nonBlank(source.worktree?.name) {
                if let branchName = nonBlank(source.branchName), branchName != worktreeName {
                    return "\(repoName) · \(worktreeName) / \(branchName)"
                }
                return "\(repoName) · \(worktreeName)"
            }
            return repoName
        }

        if let worktreeName = nonBlank(source.worktree?.name) {
            if let branchName = nonBlank(source.branchName), branchName != worktreeName {
                return "\(worktreeName) / \(branchName)"
            }
            return worktreeName
        }

        if let branchName = nonBlank(source.branchName) {
            return branchName
        }

        if let runtimeDisplayLabel = nonBlank(source.runtimeDisplayLabel) {
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
            if let tabDisplayLabel = nonBlank(source.tabDisplayLabel) {
                parts.append("Tab \(tabDisplayLabel)")
            }
            appendPanePlacement(for: source, to: &parts)
        case .paneInbox(let parentPaneId):
            if source.paneRole == .drawerChild,
                source.parentPaneId == parentPaneId,
                let paneDisplayLabel = nonBlank(source.paneDisplayLabel)
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
            if let paneDisplayLabel = nonBlank(source.paneDisplayLabel) {
                parts.append("Pane \(paneDisplayLabel)")
            }
        case .drawerChild:
            if let parentPaneDisplayLabel = nonBlank(source.parentPaneDisplayLabel) {
                parts.append("Pane \(parentPaneDisplayLabel)")
            }
            if let paneDisplayLabel = nonBlank(source.paneDisplayLabel) {
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
            return nonBlank(source.paneDisplayLabel)
                ?? nonBlank(source.worktree?.name)
                ?? nonBlank(source.branchName)
                ?? nonBlank(source.runtimeDisplayLabel)
                ?? "Pane"
        case .drawerChild:
            let parentTitle = nonBlank(source.parentPaneDisplayLabel) ?? "Pane"
            if let paneTitle = nonBlank(source.paneDisplayLabel) {
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
            labels[.repo(id: repoId)] = nonBlank(source.repo?.name) ?? "Filtered repo"
        }
        if let worktreeId = source.worktree?.id {
            labels[.worktree(id: worktreeId)] = nonBlank(source.worktree?.name) ?? "Filtered worktree"
        }
        return labels
    }

    private static func joinSearchTerms(_ terms: [String?]) -> String {
        terms
            .compactMap(nonBlank)
            .joined(separator: " ")
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
