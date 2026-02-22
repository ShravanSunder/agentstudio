import Foundation

/// Metadata carried by every pane for runtime routing and dynamic grouping.
///
/// This structure intentionally keeps compatibility with existing workspace data
/// while moving toward the richer pane-runtime contract surface.
struct PaneMetadata: Codable, Hashable, Sendable {
    enum PaneMetadataSource: Codable, Hashable, Sendable {
        case worktree(worktreeId: UUID, repoId: UUID)
        case floating(workingDirectory: URL?, title: String?)

        init(_ terminalSource: TerminalSource) {
            switch terminalSource {
            case .worktree(let worktreeId, let repoId):
                self = .worktree(worktreeId: worktreeId, repoId: repoId)
            case .floating(let workingDirectory, let title):
                self = .floating(workingDirectory: workingDirectory, title: title)
            }
        }

        var terminalSource: TerminalSource {
            switch self {
            case .worktree(let worktreeId, let repoId):
                return .worktree(worktreeId: worktreeId, repoId: repoId)
            case .floating(let workingDirectory, let title):
                return .floating(workingDirectory: workingDirectory, title: title)
            }
        }

        var worktreeId: UUID? {
            if case .worktree(let worktreeId, _) = self {
                return worktreeId
            }
            return nil
        }

        var repoId: UUID? {
            if case .worktree(_, let repoId) = self {
                return repoId
            }
            return nil
        }

        var workingDirectory: URL? {
            if case .floating(let workingDirectory, _) = self {
                return workingDirectory
            }
            return nil
        }
    }

    // Fixed-at-creation identity
    var paneId: PaneId?
    var contentType: PaneContentType
    var source: PaneMetadataSource
    var executionBackend: ExecutionBackend
    var createdAt: Date

    // Live fields
    var title: String
    var cwd: URL?
    var repoId: UUID?
    var worktreeId: UUID?
    var parentFolder: String?
    var checkoutRef: String?
    var agentType: AgentType?
    var tags: [String]

    init(
        paneId: PaneId? = nil,
        contentType: PaneContentType = .terminal,
        source: PaneMetadataSource,
        executionBackend: ExecutionBackend = .local,
        createdAt: Date = Date(),
        title: String = "Terminal",
        cwd: URL? = nil,
        repoId: UUID? = nil,
        worktreeId: UUID? = nil,
        parentFolder: String? = nil,
        checkoutRef: String? = nil,
        agentType: AgentType? = nil,
        tags: [String] = []
    ) {
        self.paneId = paneId
        self.contentType = contentType
        self.source = source
        self.executionBackend = executionBackend
        self.createdAt = createdAt
        self.title = title
        self.cwd = cwd ?? source.workingDirectory
        self.repoId = repoId ?? source.repoId
        self.worktreeId = worktreeId ?? source.worktreeId
        self.parentFolder = parentFolder
        self.checkoutRef = checkoutRef
        self.agentType = agentType
        self.tags = tags
    }

    /// Legacy compatibility initializer used throughout existing store/action flows.
    init(
        source: TerminalSource,
        title: String = "Terminal",
        cwd: URL? = nil,
        agentType: AgentType? = nil,
        tags: [String] = []
    ) {
        self.init(
            paneId: nil,
            contentType: .terminal,
            source: PaneMetadataSource(source),
            executionBackend: .local,
            createdAt: Date(),
            title: title,
            cwd: cwd,
            repoId: nil,
            worktreeId: nil,
            parentFolder: nil,
            checkoutRef: nil,
            agentType: agentType,
            tags: tags
        )
    }

    var terminalSource: TerminalSource {
        source.terminalSource
    }

    private enum CodingKeys: String, CodingKey {
        case paneId
        case contentType
        case source
        case executionBackend
        case createdAt
        case title
        case cwd
        case repoId
        case worktreeId
        case parentFolder
        case checkoutRef
        case agentType
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let source = try container.decode(PaneMetadataSource.self, forKey: .source)
        let titleFromSource: String
        if case .floating(_, let sourceTitle) = source {
            titleFromSource = sourceTitle ?? "Terminal"
        } else {
            titleFromSource = "Terminal"
        }

        self.paneId = try container.decodeIfPresent(PaneId.self, forKey: .paneId)
        self.contentType = try container.decodeIfPresent(PaneContentType.self, forKey: .contentType) ?? .terminal
        self.source = source
        self.executionBackend =
            try container.decodeIfPresent(ExecutionBackend.self, forKey: .executionBackend) ?? .local
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? titleFromSource
        self.cwd = try container.decodeIfPresent(URL.self, forKey: .cwd) ?? source.workingDirectory
        self.repoId = try container.decodeIfPresent(UUID.self, forKey: .repoId) ?? source.repoId
        self.worktreeId = try container.decodeIfPresent(UUID.self, forKey: .worktreeId) ?? source.worktreeId
        self.parentFolder = try container.decodeIfPresent(String.self, forKey: .parentFolder)
        self.checkoutRef = try container.decodeIfPresent(String.self, forKey: .checkoutRef)
        self.agentType = try container.decodeIfPresent(AgentType.self, forKey: .agentType)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
