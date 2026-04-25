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
        let paneId: UUID
        let tabId: UUID?
        let repo: NamedSource?
        let worktree: NamedSource?
        let branchName: String?

        init(
            paneId: UUID,
            tabId: UUID? = nil,
            repoId: UUID? = nil,
            repoName: String? = nil,
            worktreeId: UUID? = nil,
            worktreeName: String? = nil,
            branchName: String? = nil
        ) {
            self.paneId = paneId
            self.tabId = tabId
            self.repo = NamedSource(
                id: repoId,
                name: repoName
            )
            self.worktree = NamedSource(
                id: worktreeId,
                name: worktreeName
            )
            self.branchName = branchName
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

    let id: UUID
    let timestamp: Date
    let kind: InboxNotificationKind
    let title: String
    let body: String?
    let source: Source

    var isRead: Bool
    var isDismissedFromDrawer: Bool

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
    case approvalRequested
    case securityEvent
}
