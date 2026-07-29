import Foundation

/// Metadata carried by every pane for runtime routing and dynamic grouping.
package struct PaneMetadata: Codable, Hashable, Sendable {
    // Fixed-at-creation identity
    package let paneId: PaneId
    package let contentType: PaneContentType
    package let launchDirectory: URL?
    package let executionBackend: ExecutionBackend
    package let createdAt: Date

    // Live fields
    package private(set) var title: String
    package private(set) var facets: PaneContextFacets
    package private(set) var checkoutRef: String?
    package private(set) var note: String?

    package init(
        paneId: PaneId = PaneId.generateUUIDv7(),
        contentType: PaneContentType = .terminal,
        launchDirectory: URL? = nil,
        executionBackend: ExecutionBackend = .local,
        createdAt: Date = Date(),
        title: String = "Terminal",
        facets: PaneContextFacets = .empty,
        checkoutRef: String? = nil,
        note: String? = nil,
        fillNilLaunchDirectoryFacet: Bool = true
    ) {
        self.paneId = paneId
        self.contentType = contentType
        self.launchDirectory = launchDirectory
        self.executionBackend = executionBackend
        self.createdAt = createdAt
        self.title = title
        let launchFacets = PaneContextFacets(cwd: launchDirectory)
        self.facets = fillNilLaunchDirectoryFacet ? facets.fillingNilFields(from: launchFacets) : facets
        self.checkoutRef = checkoutRef
        self.note = note
    }

    package mutating func updateTitle(_ newTitle: String) {
        title = newTitle
    }

    package mutating func updateFacets(_ newFacets: PaneContextFacets) {
        facets = newFacets
    }

    package mutating func updateCWD(_ newCWD: URL?) {
        facets.cwd = newCWD
    }

    package mutating func updateCheckoutRef(_ newCheckoutRef: String?) {
        checkoutRef = newCheckoutRef
    }

    package mutating func updateNote(_ newNote: String?) {
        note = Self.normalizedNote(newNote)
    }

    package func canonicalizedIdentity(
        paneId: PaneId,
        contentType: PaneContentType,
        fillNilLaunchDirectoryFacet: Bool = true
    ) -> Self {
        Self(
            paneId: paneId,
            contentType: contentType,
            launchDirectory: launchDirectory,
            executionBackend: executionBackend,
            createdAt: createdAt,
            title: title,
            facets: facets,
            checkoutRef: checkoutRef,
            note: note,
            fillNilLaunchDirectoryFacet: fillNilLaunchDirectoryFacet
        )
    }

    // MARK: - Facet Convenience Accessors

    package var cwd: URL? { facets.cwd }

    package var repoId: UUID? { facets.repoId }

    package var repoName: String? { facets.repoName }

    package var worktreeId: UUID? { facets.worktreeId }

    package var worktreeName: String? { facets.worktreeName }

    package var parentFolder: String? { facets.parentFolder }

    package var organizationName: String? { facets.organizationName }

    package var origin: String? { facets.origin }

    package var upstream: String? { facets.upstream }

    private enum CodingKeys: String, CodingKey {
        case paneId
        case contentType
        case launchDirectory
        case executionBackend
        case createdAt
        case title
        case facets
        case checkoutRef
        case note
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case source
    }

    private enum LegacySource: Codable {
        case worktree(worktreeId: UUID, repoId: UUID, launchDirectory: URL)
        case floating(launchDirectory: URL?, title: String?)

        var repoId: UUID? {
            if case .worktree(_, let repoId, _) = self {
                return repoId
            }
            return nil
        }

        var worktreeId: UUID? {
            if case .worktree(let worktreeId, _, _) = self {
                return worktreeId
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

        var facets: PaneContextFacets {
            PaneContextFacets(
                repoId: repoId,
                worktreeId: worktreeId,
                cwd: launchDirectory
            )
        }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacySource = try legacyContainer.decodeIfPresent(LegacySource.self, forKey: .source)

        self.paneId = try container.decode(PaneId.self, forKey: .paneId)
        self.contentType = try container.decode(PaneContentType.self, forKey: .contentType)
        self.launchDirectory =
            try container.decodeIfPresent(URL.self, forKey: .launchDirectory)
            ?? legacySource?.launchDirectory
        self.executionBackend = try container.decode(ExecutionBackend.self, forKey: .executionBackend)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.title = try container.decode(String.self, forKey: .title)
        if let decodedFacets = try container.decodeIfPresent(PaneContextFacets.self, forKey: .facets) {
            self.facets = decodedFacets.fillingNilFields(from: legacySource?.facets ?? .empty)
        } else if let legacySource {
            self.facets = legacySource.facets
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.facets,
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "PaneMetadata.facets is required unless legacy source is present"
                )
            )
        }
        self.checkoutRef = try container.decodeIfPresent(String.self, forKey: .checkoutRef)
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    private static func normalizedNote(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
