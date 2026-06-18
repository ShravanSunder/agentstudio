import Foundation

enum InboxNotificationTextPolicy {
    enum SecuritySummaryKind: Equatable {
        case networkEgressBlocked
        case filesystemAccessDenied(operation: String)
        case secretAccessed
        case processSpawnBlocked
    }

    static func bounded(title: String, body: String?) -> (title: String, body: String?) {
        let boundedTitle = limited(
            title.trimmedNonEmpty ?? title,
            to: AppPolicies.InboxNotification.maxTitleCharacters
        )
        let boundedBody = body.trimmedNonEmpty.map {
            limited($0, to: AppPolicies.InboxNotification.maxBodyCharacters)
        }
        return (boundedTitle, boundedBody)
    }

    static func limited(_ value: String, to maxCharacters: Int) -> String {
        guard value.count > maxCharacters || value.utf8.count > maxCharacters else { return value }
        var byteCount = 0
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            let scalarByteCount = String(scalar).utf8.count
            guard byteCount + scalarByteCount <= maxCharacters else { break }
            scalars.append(scalar)
            byteCount += scalarByteCount
        }
        return String(scalars)
    }

    static func approvalSummary(requestSummary: String) -> String {
        _ = requestSummary
        return "Approval is required for a privileged action"
    }

    static func securitySummary(kind: SecuritySummaryKind) -> String {
        switch kind {
        case .networkEgressBlocked:
            return "Network access was blocked by policy"
        case .filesystemAccessDenied(let operation):
            return "Filesystem \(safeOperationLabel(operation)) was blocked by policy"
        case .secretAccessed:
            return "A secret access event was reported"
        case .processSpawnBlocked:
            return "Process launch was blocked by policy"
        }
    }

    private static func safeOperationLabel(_ operation: String) -> String {
        switch operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "read":
            return "read"
        case "write":
            return "write"
        case "delete", "remove", "unlink":
            return "delete"
        case "execute", "exec", "run":
            return "execute"
        default:
            return "access"
        }
    }
}

enum InboxNotificationClaimCoalescencePolicy {
    static func canCoalesce(
        existing: InboxNotification,
        incoming: InboxNotification
    ) -> Bool {
        if !existing.isRead && !existing.isDismissedFromPaneInbox {
            return true
        }
        if canReopenReadClaim(existing: existing, incoming: incoming) {
            return true
        }
        return existing.isRead
            && existing.isDismissedFromPaneInbox
            && incoming.isRead
            && incoming.isDismissedFromPaneInbox
    }

    private static func canReopenReadClaim(
        existing: InboxNotification,
        incoming: InboxNotification
    ) -> Bool {
        guard
            existing.isRead,
            !incoming.isRead,
            let existingClaimKey = existing.claimKey,
            let incomingClaimKey = incoming.claimKey,
            existingClaimKey.paneId == incomingClaimKey.paneId,
            existingClaimKey.sessionId != nil,
            existingClaimKey.sessionId == incomingClaimKey.sessionId
        else {
            return false
        }
        return existingClaimKey.lane == .activity
            && (incomingClaimKey.lane == .actionNeeded || incomingClaimKey.lane == .safety
                || incomingClaimKey.lane == .settledAgent)
    }
}

enum InboxNotificationRetentionPolicy {
    static func droppedNotificationIds(
        from notifications: [InboxNotification],
        overflow: Int
    ) -> [UUID] {
        guard overflow > 0 else { return [] }
        return
            notifications
            .sorted { left, right in
                let leftKey = retentionSortKey(for: left)
                let rightKey = retentionSortKey(for: right)
                if leftKey.priority != rightKey.priority {
                    return leftKey.priority < rightKey.priority
                }
                if leftKey.timestamp != rightKey.timestamp {
                    return leftKey.timestamp < rightKey.timestamp
                }
                return left.id.uuidString < right.id.uuidString
            }
            .prefix(overflow)
            .map(\.id)
    }

    private static func retentionSortKey(
        for notification: InboxNotification
    ) -> (priority: Int, timestamp: Date) {
        switch (notification.isRead, notification.displayLane) {
        case (true, .activity):
            return (0, notification.timestamp)
        case (true, .actionNeeded), (true, .safety), (true, .settledAgent):
            return (1, notification.timestamp)
        case (false, .activity):
            return (2, notification.timestamp)
        case (false, .settledAgent):
            return (3, notification.timestamp)
        case (false, .actionNeeded), (false, .safety):
            return (3, notification.timestamp)
        }
    }
}
