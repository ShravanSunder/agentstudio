import Foundation

struct InboxNotificationSourceDisplay: Equatable, Sendable {
    enum RowContext: Equatable, Sendable {
        case globalInbox
        case paneInbox(parentPaneId: UUID)
    }

    let primaryText: String
    let sourceLine: String
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
        let placementLine = Self.placementLine(for: notification, rowContext: rowContext)
        let detailText =
            title == nil
            ? nil
            : Self.detailText(
                body: body,
                kind: notification.kind
            )

        self.primaryText = primaryText
        self.sourceLine = sourceLine
        self.placementLine = placementLine
        self.detailText = detailText
        self.searchText = [
            primaryText,
            sourceLine,
            placementLine,
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
            return panePlacementLabel(for: notification, includeParent: true) ?? "Other panes"
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

    private static func placementLine(
        for notification: InboxNotification,
        rowContext: RowContext
    ) -> String? {
        let runtimeLabel = notification.runtimeDisplayLabel
        let labels: [String?]
        switch rowContext {
        case .globalInbox:
            labels = [
                notification.tabDisplayLabel,
                panePlacementLabel(for: notification, includeParent: true),
                runtimeLabel,
            ]
        case .paneInbox(let parentPaneId):
            if notification.paneId == parentPaneId, notification.paneRole == .main {
                labels = [runtimeLabel]
            } else {
                labels = [
                    panePlacementLabel(for: notification, includeParent: false),
                    runtimeLabel,
                ]
            }
        }

        let normalizedLabels = orderedUnique(labels.compactMap { normalizedOptionalString($0) })
        guard !normalizedLabels.isEmpty else { return nil }
        return normalizedLabels.joined(separator: " · ")
    }

    private static func panePlacementLabel(
        for notification: InboxNotification,
        includeParent: Bool
    ) -> String? {
        guard let paneContext = notification.paneContext else { return nil }

        let runtimeLabel = paneContext.runtimeDisplayLabel
        let paneName =
            normalizedOptionalString(paneContext.paneDisplayLabel)
            ?? notification.worktreeName
            ?? notification.branchName
            ?? notification.tabDisplayLabel
        let visiblePaneName = paneName == runtimeLabel ? nil : paneName
        switch paneContext.paneRole {
        case .main:
            if let visiblePaneName {
                return "Main pane: \(visiblePaneName)"
            }
            return "Main pane"
        case .drawerChild:
            let drawerLabel = drawerPlacementPrefix(for: paneContext, includeParent: includeParent)
            if let visiblePaneName {
                return "\(drawerLabel): \(visiblePaneName)"
            }
            return drawerLabel
        }
    }

    private static func drawerPlacementPrefix(
        for paneContext: InboxNotification.PaneSource,
        includeParent: Bool
    ) -> String {
        let ordinalLabel = paneContext.drawerOrdinal.map { "Drawer \($0)" } ?? "Drawer"
        guard includeParent, let parentPaneDisplayLabel = paneContext.parentPaneDisplayLabel else {
            return ordinalLabel
        }
        return "\(parentPaneDisplayLabel) \(ordinalLabel.lowercased())"
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
