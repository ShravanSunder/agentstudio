import Foundation

struct InboxNotificationSourceDisplay: Equatable, Sendable {
    enum RowContext: Equatable, Sendable {
        case globalInbox
        case paneInbox(parentPaneId: UUID)
    }

    let primaryText: String
    let sourceLine: String
    let placementParts: [String]
    let placementLine: String?
    let detailText: String?
    let searchText: String

    init(
        notification: InboxNotification,
        rowContext: RowContext = .globalInbox
    ) {
        let title = normalizedOptionalString(notification.title)
        let body = normalizedOptionalString(notification.body)
        let primaryText = title ?? body ?? Self.kindLabel(notification.kind)
        let sourceLine = Self.sourceLine(for: notification)
        let placementParts = Self.placementParts(for: notification, rowContext: rowContext)
        let placementLine = placementParts.isEmpty ? nil : placementParts.joined(separator: " · ")
        let detailText =
            title == nil
            ? nil
            : Self.detailText(
                body: body,
                kind: notification.kind
            )

        self.primaryText = primaryText
        self.sourceLine = sourceLine
        self.placementParts = placementParts
        self.placementLine = placementLine
        self.detailText = detailText
        self.searchText = [
            primaryText,
            sourceLine,
            placementLine,
            notification.paneDisplayLabel,
            notification.parentPaneDisplayLabel,
            detailText,
        ]
        .compactMap { normalizedOptionalString($0) }
        .joined(separator: " ")
    }

    static func groupLabel(
        for notification: InboxNotification,
        grouping: InboxNotificationGrouping
    ) -> String {
        switch grouping {
        case .none:
            return ""
        case .byRepo:
            return notification.repoName ?? "Other sources"
        case .byPane:
            return panePlacementLabel(for: notification.paneContext, includeParent: true) ?? "Other panes"
        case .byTab:
            return notification.tabDisplayLabel ?? "Untitled Tab"
        }
    }

    static func filterLabel(
        for filter: InboxFilter,
        notifications: [InboxNotification]
    ) -> String {
        switch filter {
        case .repo(let repoId):
            return newestDisplayLabel(in: notifications) { notification in
                notification.repoId == repoId ? notification.repoName : nil
            } ?? "Filtered repo"
        case .worktree(let worktreeId):
            return newestDisplayLabel(in: notifications) { notification in
                notification.worktreeId == worktreeId ? notification.worktreeName : nil
            } ?? "Filtered worktree"
        }
    }

    private static func newestDisplayLabel(
        in notifications: [InboxNotification],
        label: (InboxNotification) -> String?
    ) -> String? {
        for notification in notifications.sorted(by: { $0.timestamp > $1.timestamp }) {
            if let label = normalizedOptionalString(label(notification)) {
                return label
            }
        }
        return nil
    }

    private static func sourceLine(for notification: InboxNotification) -> String {
        if let repoName = notification.repoName {
            if let worktreeName = notification.worktreeName {
                if let branchName = notification.branchName, branchName != worktreeName {
                    return "\(repoName) · \(worktreeName) / \(branchName)"
                }
                return "\(repoName) · \(worktreeName)"
            }
            if let branchName = notification.branchName, branchName != repoName {
                return "\(repoName) · \(branchName)"
            }
            return repoName
        }

        if let worktreeName = notification.worktreeName {
            if let branchName = notification.branchName, branchName != worktreeName {
                return "\(worktreeName) / \(branchName)"
            }
            return worktreeName
        }

        if let branchName = notification.branchName {
            return branchName
        }

        if case .global = notification.source {
            return "Agent Studio"
        }

        return notification.runtimeDisplayLabel ?? "Terminal"
    }

    private static func placementParts(
        for notification: InboxNotification,
        rowContext: RowContext
    ) -> [String] {
        guard let paneContext = notification.paneContext else {
            return orderedUnique([notification.runtimeDisplayLabel].compactMap { normalizedOptionalString($0) })
        }

        var parts: [String] = []
        if let tabDisplayLabel = normalizedOptionalString(paneContext.tabDisplayLabel) {
            parts.append(tabDisplayLabel)
        }

        switch rowContext {
        case .globalInbox:
            if let panePlacementLabel = panePlacementLabel(for: paneContext, includeParent: true) {
                parts.append(panePlacementLabel)
            }
        case .paneInbox(let parentPaneId):
            if !(paneContext.paneId == parentPaneId && paneContext.paneRole == .main),
                let panePlacementLabel = panePlacementLabel(for: paneContext, includeParent: true)
            {
                parts.append(panePlacementLabel)
            }
        }

        if let runtimeDisplayLabel = normalizedOptionalString(paneContext.runtimeDisplayLabel) {
            parts.append(runtimeDisplayLabel)
        }

        return orderedUnique(parts)
    }

    private static func panePlacementLabel(
        for paneContext: InboxNotification.PaneSource?,
        includeParent: Bool
    ) -> String? {
        guard let paneContext else { return nil }
        switch paneContext.paneRole {
        case .main:
            return mainPaneLabel(for: paneContext)
        case .drawerChild:
            return drawerPlacementLabel(for: paneContext, includeParent: includeParent)
        }
    }

    private static func mainPaneLabel(for paneContext: InboxNotification.PaneSource) -> String {
        let prefix = paneContext.paneOrdinal.map { "Pane \($0)" } ?? "Main pane"
        let runtimeDisplayLabel = normalizedOptionalString(paneContext.runtimeDisplayLabel)
        if let paneDisplayLabel = normalizedOptionalString(paneContext.paneDisplayLabel) {
            guard paneDisplayLabel != runtimeDisplayLabel else { return prefix }
            return "\(prefix): \(paneDisplayLabel)"
        }
        return prefix
    }

    private static func drawerPlacementLabel(
        for paneContext: InboxNotification.PaneSource,
        includeParent: Bool
    ) -> String {
        let drawerPrefix: String
        if let drawerOrdinal = paneContext.drawerOrdinal {
            drawerPrefix = "Drawer \(drawerOrdinal)"
        } else {
            drawerPrefix = "Drawer"
        }

        let drawerLabel: String
        let paneDisplayLabel = normalizedOptionalString(paneContext.paneDisplayLabel)
        let runtimeDisplayLabel = normalizedOptionalString(paneContext.runtimeDisplayLabel)
        if let paneDisplayLabel, paneDisplayLabel != runtimeDisplayLabel {
            drawerLabel = "\(drawerPrefix): \(paneDisplayLabel)"
        } else {
            drawerLabel = drawerPrefix
        }

        return includeParent
            ? drawerPlacementLabel(drawerLabel: drawerLabel, paneContext: paneContext)
            : drawerLabel
    }

    private static func drawerPlacementLabel(
        drawerLabel: String,
        paneContext: InboxNotification.PaneSource
    ) -> String {
        let runtimeDisplayLabel = normalizedOptionalString(paneContext.runtimeDisplayLabel)
        if let parentPaneDisplayLabel = normalizedOptionalString(paneContext.parentPaneDisplayLabel),
            parentPaneDisplayLabel != runtimeDisplayLabel
        {
            return "Parent \(parentPaneDisplayLabel) · \(drawerLabel)"
        }
        if let paneOrdinal = paneContext.paneOrdinal {
            return "Pane \(paneOrdinal) · \(drawerLabel)"
        }
        return drawerLabel
    }

    private static func orderedUnique(_ labels: [String]) -> [String] {
        var seen: Set<String> = []
        return labels.filter { label in
            seen.insert(label).inserted
        }
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
        case .approvalRequested:
            return "Approval requested"
        case .securityEvent:
            return "Security event"
        }
    }

    private static func detailText(
        body: String?,
        kind: InboxNotificationKind
    ) -> String? {
        guard kind == .commandFinished else { return body }
        guard let body else { return nil }
        guard let separatorRange = body.range(of: " · ") else { return body }

        let suffix = body[separatorRange.upperBound...]
        guard let minutes = legacyDurationMinutes(from: String(suffix)) else { return body }
        guard minutes > 7 * 24 * 60 else { return body }

        return normalizedOptionalString(String(body[..<separatorRange.lowerBound]))
    }

    private static func legacyDurationMinutes(from value: String) -> Int? {
        guard let minuteMarker = value.range(of: "m ") else { return nil }
        return Int(value[..<minuteMarker.lowerBound])
    }
}

private func normalizedOptionalString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
