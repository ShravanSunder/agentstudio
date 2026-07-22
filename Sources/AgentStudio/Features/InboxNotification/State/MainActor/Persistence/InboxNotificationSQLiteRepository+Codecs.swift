import Foundation
import GRDB

enum InboxNotificationSQLiteCodecs {
    private static let paneSourceKind = "pane"
    private static let globalSourceKind = "global"

    static func arguments(
        workspaceId: UUID,
        notification: InboxNotification
    ) -> StatementArguments {
        let paneSource = paneSource(from: notification.source)
        let activityContext = notification.activityContext
        let claimKey = notification.claimKey
        return [
            notification.id.uuidString,
            workspaceId.uuidString,
            notification.timestamp.timeIntervalSince1970,
            notification.kind.rawValue,
            notification.title,
            notification.body,
            sourceKind(for: notification.source),
            paneSource?.paneId.uuidString,
            paneSource?.tabId?.uuidString,
            paneSource?.tabDisplayLabel,
            paneSource?.tabOrdinal,
            paneSource?.repo?.id?.uuidString,
            paneSource?.repo?.name,
            paneSource?.worktree?.id?.uuidString,
            paneSource?.worktree?.name,
            paneSource?.branchName,
            paneSource?.paneDisplayLabel,
            paneSource?.paneOrdinal,
            paneSource?.paneRole.rawValue,
            paneSource?.parentPaneId?.uuidString,
            paneSource?.parentPaneDisplayLabel,
            paneSource?.parentPaneOrdinal,
            paneSource?.drawerOrdinal,
            paneSource?.runtimeDisplayLabel,
            activityContext?.burstWindowId.uuidString,
            activityContext?.activitySessionId?.uuidString,
            activityContext?.eventCount,
            activityContext?.rowsAdded,
            activityContext?.thresholdRows,
            activityContext?.latestRows,
            claimKey?.paneId.uuidString,
            claimKey.map { SQLiteInboxNotificationClaimStorage.storageValue(for: $0.lane) },
            claimKey.map { claimSemanticStorageValue(for: $0.semantic) },
            claimKey?.sessionId?.uuidString,
            notification.isRead ? 1 : 0,
            notification.isDismissedFromPaneInbox ? 1 : 0,
        ]
    }

    static func notification(from row: Row) throws -> InboxNotification {
        let idString: String = row["id"]
        let id = try uuid(idString, InboxNotificationSQLiteRepositoryError.malformedNotificationId)
        let kindRawValue: String = row["kind"]

        return InboxNotification(
            id: id,
            timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            kind: try notificationKind(from: kindRawValue),
            title: row["title"],
            body: row["body"],
            source: try source(from: row, notificationId: id),
            activityContext: try activityContext(from: row, notificationId: id),
            claimKey: try claimKey(from: row, notificationId: id),
            isRead: (row["is_read"] as Int) == 1,
            isDismissedFromPaneInbox: (row["is_dismissed_from_pane_inbox"] as Int) == 1
        )
    }

    static func uuid(
        _ rawValue: String,
        _ error: (String) -> InboxNotificationSQLiteRepositoryError
    ) throws -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else { throw error(rawValue) }
        return uuid
    }

    private static func source(
        from row: Row,
        notificationId: UUID
    ) throws -> InboxNotification.Source {
        let sourceKind: String = row["source_kind"]
        switch sourceKind {
        case globalSourceKind:
            return .global
        case paneSourceKind:
            guard let paneIdString: String = row["pane_id"] else {
                throw InboxNotificationSQLiteRepositoryError.missingPaneId(notificationId)
            }
            let paneRoleRawValue: String? = row["pane_role"]
            let paneRole = try paneRole(from: paneRoleRawValue)

            return .pane(
                .init(
                    paneId: try uuid(paneIdString, InboxNotificationSQLiteRepositoryError.malformedPaneId),
                    tabId: try optionalUUID(row["tab_id"], InboxNotificationSQLiteRepositoryError.malformedTabId),
                    tabDisplayLabel: row["tab_display_label"],
                    tabOrdinal: row["tab_ordinal"],
                    repoId: try optionalUUID(row["repo_id"], InboxNotificationSQLiteRepositoryError.malformedRepoId),
                    repoName: row["repo_name"],
                    worktreeId: try optionalUUID(
                        row["worktree_id"],
                        InboxNotificationSQLiteRepositoryError.malformedWorktreeId
                    ),
                    worktreeName: row["worktree_name"],
                    branchName: row["branch_name"],
                    paneDisplayLabel: row["pane_display_label"],
                    paneOrdinal: row["pane_ordinal"],
                    paneRole: paneRole,
                    parentPaneId: try optionalUUID(
                        row["parent_pane_id"],
                        InboxNotificationSQLiteRepositoryError.malformedPaneId
                    ),
                    parentPaneDisplayLabel: row["parent_pane_display_label"],
                    parentPaneOrdinal: row["parent_pane_ordinal"],
                    drawerOrdinal: row["drawer_ordinal"],
                    runtimeDisplayLabel: row["runtime_display_label"]
                )
            )
        default:
            throw InboxNotificationSQLiteRepositoryError.unsupportedSourceKind(sourceKind)
        }
    }

    private static func notificationKind(from rawValue: String) throws -> InboxNotificationKind {
        guard let kind = InboxNotificationKind(rawValue: rawValue) else {
            throw InboxNotificationSQLiteRepositoryError.unsupportedNotificationKind(rawValue)
        }
        return kind
    }

    private static func paneRole(from rawValue: String?) throws -> InboxNotification.PaneSource.PaneRole {
        guard let rawValue else { return .main }
        guard let paneRole = InboxNotification.PaneSource.PaneRole(rawValue: rawValue) else {
            throw InboxNotificationSQLiteRepositoryError.unsupportedPaneRole(rawValue)
        }
        return paneRole
    }

    private static func activityContext(
        from row: Row,
        notificationId: UUID
    ) throws -> InboxNotification.ActivityContext? {
        let burstWindowIdString: String? = row["activity_burst_window_id"]
        guard let burstWindowIdString else { return nil }
        guard
            let eventCount: Int = row["activity_event_count"],
            let rowsAdded: Int = row["activity_rows_added"],
            let thresholdRows: Int = row["activity_threshold_rows"],
            let latestRows: Int = row["activity_latest_rows"]
        else {
            throw InboxNotificationSQLiteRepositoryError.malformedActivityContext(notificationId)
        }

        return .init(
            burstWindowId: try uuid(
                burstWindowIdString,
                InboxNotificationSQLiteRepositoryError.malformedActivityBurstWindowId
            ),
            activitySessionId: try optionalUUID(
                row["activity_session_id"],
                InboxNotificationSQLiteRepositoryError.malformedActivitySessionId
            ),
            eventCount: eventCount,
            rowsAdded: rowsAdded,
            thresholdRows: thresholdRows,
            latestRows: latestRows
        )
    }

    private static func claimKey(
        from row: Row,
        notificationId: UUID
    ) throws -> InboxNotificationClaimKey? {
        let paneIdString: String? = row["claim_pane_id"]
        let laneRawValue: String? = row["claim_lane"]
        let semanticRawValue: String? = row["claim_semantic"]
        let sessionIdString: String? = row["claim_session_id"]
        guard paneIdString != nil || laneRawValue != nil || semanticRawValue != nil || sessionIdString != nil else {
            return nil
        }
        guard
            let paneIdString,
            let laneRawValue,
            let semanticRawValue
        else {
            throw InboxNotificationSQLiteRepositoryError.malformedClaimKey(notificationId)
        }
        guard let lane = InboxNotificationClaimLane(rawValue: laneRawValue) else {
            throw InboxNotificationSQLiteRepositoryError.unsupportedClaimLane(laneRawValue)
        }
        guard let semantic = InboxNotificationClaimSemantic(rawValue: semanticRawValue) else {
            throw InboxNotificationSQLiteRepositoryError.unsupportedClaimSemantic(semanticRawValue)
        }

        return .init(
            paneId: try uuid(paneIdString, InboxNotificationSQLiteRepositoryError.malformedPaneId),
            lane: lane,
            semantic: semantic,
            sessionId: try optionalUUID(sessionIdString, InboxNotificationSQLiteRepositoryError.malformedClaimSessionId)
        )
    }

    private static func claimSemanticStorageValue(for semantic: InboxNotificationClaimSemantic) -> String {
        switch semantic {
        case .approvalRequested: "approvalRequested"
        case .unseenActivity: "unseenActivity"
        case .commandFinished: "commandFinished"
        case .bell: "bell"
        case .desktopNotification: "desktopNotification"
        case .agentRpc: "agentRpc"
        case .agentSettled: "agentSettled"
        case .secureInput: "secureInput"
        case .progressError: "progressError"
        case .rendererUnhealthy: "rendererUnhealthy"
        case .persistenceRecovery: "persistenceRecovery"
        case .securityEvent: "securityEvent"
        }
    }

    private static func sourceKind(for source: InboxNotification.Source) -> String {
        switch source {
        case .pane:
            return paneSourceKind
        case .global:
            return globalSourceKind
        }
    }

    private static func paneSource(from source: InboxNotification.Source) -> InboxNotification.PaneSource? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource
    }

    private static func optionalUUID(
        _ rawValue: String?,
        _ error: (String) -> InboxNotificationSQLiteRepositoryError
    ) throws -> UUID? {
        guard let rawValue else { return nil }
        return try uuid(rawValue, error)
    }
}
