import Foundation

/// A single notification entry in the inbox.
///
/// Source context is denormalized at emit time so history stays readable even
/// after the source pane or worktree disappears.
struct InboxNotification: Identifiable, Sendable, Codable, Equatable {
    enum Source: Sendable, Codable, Equatable {
        case pane(PaneSource)
        case global
    }

    struct PaneSource: Sendable, Codable, Equatable {
        enum PaneRole: String, Sendable, Codable, Equatable {
            case main
            case drawerChild
        }

        let paneId: UUID
        let tabId: UUID?
        let tabDisplayLabel: String?
        let tabOrdinal: Int?
        let repo: NamedSource?
        let worktree: NamedSource?
        let branchName: String?
        let paneDisplayLabel: String?
        let paneOrdinal: Int?
        let paneRole: PaneRole
        let parentPaneId: UUID?
        let parentPaneDisplayLabel: String?
        let parentPaneOrdinal: Int?
        let drawerOrdinal: Int?
        let runtimeDisplayLabel: String?

        private enum CodingKeys: String, CodingKey {
            case paneId
            case tabId
            case tabDisplayLabel
            case tabOrdinal
            case repo
            case worktree
            case branchName
            case paneDisplayLabel
            case paneOrdinal
            case paneRole
            case parentPaneId
            case parentPaneDisplayLabel
            case parentPaneOrdinal
            case drawerOrdinal
            case runtimeDisplayLabel
        }

        init(
            paneId: UUID,
            tabId: UUID? = nil,
            tabDisplayLabel: String? = nil,
            tabOrdinal: Int? = nil,
            repoId: UUID? = nil,
            repoName: String? = nil,
            worktreeId: UUID? = nil,
            worktreeName: String? = nil,
            branchName: String? = nil,
            paneDisplayLabel: String? = nil,
            paneOrdinal: Int? = nil,
            paneRole: PaneRole = .main,
            parentPaneId: UUID? = nil,
            parentPaneDisplayLabel: String? = nil,
            parentPaneOrdinal: Int? = nil,
            drawerOrdinal: Int? = nil,
            runtimeDisplayLabel: String? = nil
        ) {
            self.paneId = paneId
            self.tabId = tabId
            self.tabDisplayLabel = tabDisplayLabel
            self.tabOrdinal = tabOrdinal
            self.repo = NamedSource(
                id: repoId,
                name: repoName
            )
            self.worktree = NamedSource(
                id: worktreeId,
                name: worktreeName
            )
            self.branchName = branchName
            self.paneDisplayLabel = paneDisplayLabel
            self.paneOrdinal = paneOrdinal
            self.paneRole = paneRole
            self.parentPaneId = parentPaneId
            self.parentPaneDisplayLabel = parentPaneDisplayLabel
            self.parentPaneOrdinal = parentPaneOrdinal
            self.drawerOrdinal = drawerOrdinal
            self.runtimeDisplayLabel = runtimeDisplayLabel
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.paneId = try container.decode(UUID.self, forKey: .paneId)
            self.tabId = try container.decodeIfPresent(UUID.self, forKey: .tabId)
            self.tabDisplayLabel = try container.decodeIfPresent(String.self, forKey: .tabDisplayLabel)
            self.tabOrdinal = try container.decodeIfPresent(Int.self, forKey: .tabOrdinal)
            self.repo = try container.decodeIfPresent(NamedSource.self, forKey: .repo)
            self.worktree = try container.decodeIfPresent(NamedSource.self, forKey: .worktree)
            self.branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
            self.paneDisplayLabel = try container.decodeIfPresent(String.self, forKey: .paneDisplayLabel)
            self.paneOrdinal = try container.decodeIfPresent(Int.self, forKey: .paneOrdinal)
            self.paneRole = try container.decodeIfPresent(PaneRole.self, forKey: .paneRole) ?? .main
            self.parentPaneId = try container.decodeIfPresent(UUID.self, forKey: .parentPaneId)
            self.parentPaneDisplayLabel = try container.decodeIfPresent(String.self, forKey: .parentPaneDisplayLabel)
            self.parentPaneOrdinal = try container.decodeIfPresent(Int.self, forKey: .parentPaneOrdinal)
            self.drawerOrdinal = try container.decodeIfPresent(Int.self, forKey: .drawerOrdinal)
            self.runtimeDisplayLabel = try container.decodeIfPresent(String.self, forKey: .runtimeDisplayLabel)
        }
    }

    struct NamedSource: Sendable, Codable, Equatable {
        let id: UUID?
        let name: String?

        init?(
            id: UUID?,
            name: String?
        ) {
            guard id != nil || name != nil else { return nil }
            self.id = id
            self.name = name
        }

        init(id: UUID?, name: String) {
            self.id = id
            self.name = name
        }
    }

    struct ActivityContext: Sendable, Codable, Equatable {
        let burstWindowId: UUID
        let activitySessionId: UUID?
        let eventCount: Int
        let rowsAdded: Int
        let thresholdRows: Int
        let latestRows: Int

        init(
            burstWindowId: UUID,
            activitySessionId: UUID? = nil,
            eventCount: Int,
            rowsAdded: Int,
            thresholdRows: Int,
            latestRows: Int
        ) {
            self.burstWindowId = burstWindowId
            self.activitySessionId = activitySessionId
            self.eventCount = eventCount
            self.rowsAdded = rowsAdded
            self.thresholdRows = thresholdRows
            self.latestRows = latestRows
        }

        func coalesced(with newerContext: Self) -> Self {
            Self(
                burstWindowId: newerContext.burstWindowId,
                activitySessionId: newerContext.activitySessionId ?? activitySessionId,
                eventCount: eventCount + newerContext.eventCount,
                rowsAdded: max(rowsAdded, newerContext.rowsAdded),
                thresholdRows: newerContext.thresholdRows,
                latestRows: newerContext.latestRows
            )
        }
    }

    let id: UUID
    let timestamp: Date
    let kind: InboxNotificationKind
    let title: String
    let body: String?
    let source: Source
    var activityContext: ActivityContext?
    let claimKey: InboxNotificationClaimKey?

    var isRead: Bool
    var isDismissedFromPaneInbox: Bool

    init(
        id: UUID,
        timestamp: Date,
        kind: InboxNotificationKind,
        title: String,
        body: String?,
        source: Source,
        activityContext: ActivityContext? = nil,
        claimKey: InboxNotificationClaimKey? = nil,
        isRead: Bool,
        isDismissedFromPaneInbox: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.body = body
        self.source = source
        self.activityContext = activityContext
        self.claimKey = claimKey
        self.isRead = isRead
        self.isDismissedFromPaneInbox = isDismissedFromPaneInbox
    }

    var paneId: UUID? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.paneId
    }

    var tabId: UUID? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.tabId
    }

    var repoId: UUID? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.repo?.id
    }

    var repoName: String? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.repo?.name
    }

    var worktreeId: UUID? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.worktree?.id
    }

    var worktreeName: String? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.worktree?.name
    }

    var branchName: String? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.branchName
    }
}

enum InboxNotificationKind: String, Sendable, Codable, Equatable {
    case agentDesktopNotification
    case bellRang
    case commandFinished
    case terminalSecureInputRequested
    case terminalProgressError
    case terminalRendererUnhealthy
    case persistenceRecovery
    case agentRpc
    case unseenActivity
    case approvalRequested
    case securityEvent
}
