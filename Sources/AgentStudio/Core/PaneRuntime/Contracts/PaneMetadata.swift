import Foundation

/// Metadata carried by every pane for runtime routing and dynamic grouping.
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
    let paneId: PaneId
    let contentType: PaneContentType
    let source: PaneMetadataSource
    let executionBackend: ExecutionBackend
    let createdAt: Date

    // Live fields
    private(set) var title: String
    private(set) var facets: PaneContextFacets
    private(set) var checkoutRef: String?
    private(set) var agentType: AgentType?

    init(
        paneId: PaneId = PaneId(),
        contentType: PaneContentType = .terminal,
        source: PaneMetadataSource,
        executionBackend: ExecutionBackend = .local,
        createdAt: Date = Date(),
        title: String = "Terminal",
        facets: PaneContextFacets = .empty,
        checkoutRef: String? = nil,
        agentType: AgentType? = nil
    ) {
        self.paneId = paneId
        self.contentType = contentType
        self.source = source
        self.executionBackend = executionBackend
        self.createdAt = createdAt
        self.title = title
        let sourceFacets = PaneContextFacets(
            repoId: source.repoId,
            worktreeId: source.worktreeId,
            cwd: source.workingDirectory
        )
        self.facets = facets.fillingNilFields(from: sourceFacets)
        self.checkoutRef = checkoutRef
        self.agentType = agentType
    }

    var terminalSource: TerminalSource {
        source.terminalSource
    }

    mutating func updateTitle(_ newTitle: String) {
        title = newTitle
    }

    mutating func updateFacets(_ newFacets: PaneContextFacets) {
        facets = newFacets
    }

    mutating func updateCWD(_ newCWD: URL?) {
        facets.cwd = newCWD
    }

    mutating func updateAgentType(_ newAgentType: AgentType?) {
        agentType = newAgentType
    }

    mutating func updateCheckoutRef(_ newCheckoutRef: String?) {
        checkoutRef = newCheckoutRef
    }

    mutating func updateTags(_ newTags: [String]) {
        facets.tags = newTags
    }

    func canonicalizedIdentity(
        paneId: PaneId,
        contentType: PaneContentType
    ) -> Self {
        Self(
            paneId: paneId,
            contentType: contentType,
            source: source,
            executionBackend: executionBackend,
            createdAt: createdAt,
            title: title,
            facets: facets,
            checkoutRef: checkoutRef,
            agentType: agentType
        )
    }

    // MARK: - Facet Convenience Accessors

    var cwd: URL? { facets.cwd }

    var repoId: UUID? { facets.repoId }

    var repoName: String? { facets.repoName }

    var worktreeId: UUID? { facets.worktreeId }

    var worktreeName: String? { facets.worktreeName }

    var parentFolder: String? { facets.parentFolder }

    var organizationName: String? { facets.organizationName }

    var origin: String? { facets.origin }

    var upstream: String? { facets.upstream }

    var tags: [String] { facets.tags }

    private enum CodingKeys: String, CodingKey {
        case paneId
        case contentType
        case source
        case executionBackend
        case createdAt
        case title
        case facets
        case checkoutRef
        case agentType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.paneId = try container.decode(PaneId.self, forKey: .paneId)
        self.contentType = try container.decode(PaneContentType.self, forKey: .contentType)
        self.source = try container.decode(PaneMetadataSource.self, forKey: .source)
        self.executionBackend = try container.decode(ExecutionBackend.self, forKey: .executionBackend)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.title = try container.decode(String.self, forKey: .title)
        self.facets = try container.decode(PaneContextFacets.self, forKey: .facets)
        self.checkoutRef = try container.decodeIfPresent(String.self, forKey: .checkoutRef)
        self.agentType = try container.decodeIfPresent(AgentType.self, forKey: .agentType)
    }
}
