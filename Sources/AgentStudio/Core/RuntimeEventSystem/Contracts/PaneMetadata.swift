import Foundation

/// Metadata carried by every pane for runtime routing and dynamic grouping.
struct PaneMetadata: Codable, Hashable, Sendable {
    enum PaneMetadataSource: Codable, Hashable, Sendable {
        case worktree(worktreeId: UUID, repoId: UUID, launchDirectory: URL)
        case floating(launchDirectory: URL?, title: String?)

        init(_ terminalSource: TerminalSource) {
            switch terminalSource {
            case .worktree(let worktreeId, let repoId, let launchDirectory):
                self = .worktree(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    launchDirectory: launchDirectory
                )
            case .floating(let launchDirectory, let title):
                self = .floating(launchDirectory: launchDirectory, title: title)
            }
        }

        var terminalSource: TerminalSource {
            switch self {
            case .worktree(let worktreeId, let repoId, let launchDirectory):
                return .worktree(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    launchDirectory: launchDirectory
                )
            case .floating(let launchDirectory, let title):
                return .floating(launchDirectory: launchDirectory, title: title)
            }
        }

        var worktreeId: UUID? {
            if case .worktree(let worktreeId, _, _) = self {
                return worktreeId
            }
            return nil
        }

        var repoId: UUID? {
            if case .worktree(_, let repoId, _) = self {
                return repoId
            }
            return nil
        }

        var launchDirectory: URL? {
            switch self {
            case .worktree(_, _, let launchDirectory):
                return launchDirectory
            case .floating(let launchDirectory, _):
                return launchDirectory
            }
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

    init(
        paneId: PaneId = PaneId(),
        contentType: PaneContentType = .terminal,
        source: PaneMetadataSource,
        executionBackend: ExecutionBackend = .local,
        createdAt: Date = Date(),
        title: String = "Terminal",
        facets: PaneContextFacets = .empty,
        checkoutRef: String? = nil
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
            cwd: source.launchDirectory
        )
        self.facets = facets.fillingNilFields(from: sourceFacets)
        self.checkoutRef = checkoutRef
    }

    var terminalSource: TerminalSource {
        source.terminalSource
    }

    var launchDirectory: URL? {
        source.launchDirectory
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
            checkoutRef: checkoutRef
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
    }
}
