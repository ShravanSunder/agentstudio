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
        let repo: NamedSource?
        let worktree: NamedSource?
        let branchName: String?
        let paneDisplayLabel: String?
        let paneOrdinal: Int?
        let paneRole: PaneRole
        let parentPaneId: UUID?
        let parentPaneDisplayLabel: String?
        let drawerOrdinal: Int?
        let runtimeDisplayLabel: String?

        init(
            paneId: UUID,
            tabId: UUID? = nil,
            tabDisplayLabel: String? = nil,
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
            drawerOrdinal: Int? = nil,
            runtimeDisplayLabel: String? = nil
        ) {
            self.paneId = paneId
            self.tabId = tabId
            self.tabDisplayLabel = normalizedOptionalString(tabDisplayLabel)
            self.repo = NamedSource(
                id: repoId,
                name: repoName
            )
            self.worktree = NamedSource(
                id: worktreeId,
                name: worktreeName
            )
            self.branchName = normalizedOptionalString(branchName)
            self.paneDisplayLabel = normalizedOptionalString(paneDisplayLabel)
            self.paneOrdinal = paneOrdinal
            self.paneRole = paneRole
            self.parentPaneId = parentPaneId
            self.parentPaneDisplayLabel = normalizedOptionalString(parentPaneDisplayLabel)
            self.drawerOrdinal = drawerOrdinal
            self.runtimeDisplayLabel = normalizedOptionalString(runtimeDisplayLabel)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            paneId = try container.decode(UUID.self, forKey: .paneId)
            tabId = try container.decodeIfPresent(UUID.self, forKey: .tabId)
            tabDisplayLabel = normalizedOptionalString(
                try container.decodeIfPresent(String.self, forKey: .tabDisplayLabel))
            repo = try container.decodeIfPresent(NamedSource.self, forKey: .repo)
            worktree = try container.decodeIfPresent(NamedSource.self, forKey: .worktree)
            branchName = normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .branchName))
            paneDisplayLabel = normalizedOptionalString(
                try container.decodeIfPresent(String.self, forKey: .paneDisplayLabel))
            paneOrdinal = try container.decodeIfPresent(Int.self, forKey: .paneOrdinal)
            paneRole = try container.decodeIfPresent(PaneRole.self, forKey: .paneRole) ?? .main
            parentPaneId = try container.decodeIfPresent(UUID.self, forKey: .parentPaneId)
            parentPaneDisplayLabel =
                normalizedOptionalString(try container.decodeIfPresent(String.self, forKey: .parentPaneDisplayLabel))
            drawerOrdinal = try container.decodeIfPresent(Int.self, forKey: .drawerOrdinal)
            runtimeDisplayLabel = normalizedOptionalString(
                try container.decodeIfPresent(String.self, forKey: .runtimeDisplayLabel))
        }

        private enum CodingKeys: String, CodingKey {
            case paneId
            case tabId
            case tabDisplayLabel
            case repo
            case worktree
            case branchName
            case paneDisplayLabel
            case paneOrdinal
            case paneRole
            case parentPaneId
            case parentPaneDisplayLabel
            case drawerOrdinal
            case runtimeDisplayLabel
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
    var isDismissedFromPaneInbox: Bool

    var paneId: UUID? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.paneId
    }

    var tabId: UUID? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource.tabId
    }

    var paneContext: PaneSource? {
        guard case .pane(let paneSource) = source else { return nil }
        return paneSource
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

    var tabDisplayLabel: String? { paneContext?.tabDisplayLabel }
    var paneDisplayLabel: String? { paneContext?.paneDisplayLabel }
    var paneOrdinal: Int? { paneContext?.paneOrdinal }
    var paneRole: PaneSource.PaneRole? { paneContext?.paneRole }
    var parentPaneDisplayLabel: String? { paneContext?.parentPaneDisplayLabel }
    var runtimeDisplayLabel: String? { paneContext?.runtimeDisplayLabel }
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

private func normalizedOptionalString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
