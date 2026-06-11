import Foundation
import GRDB

extension WorkspaceCoreRepository {
    struct PaneGraphRecord: Equatable, Sendable {
        var panes: [PaneRecord]
    }

    struct PaneRecord: Equatable, Sendable {
        let id: UUID
        var content: PaneContentRecord
        var metadata: PaneMetadataRecord
        var residency: PaneResidencyRecord
        var placement: PanePlacementRecord
        var drawer: DrawerRecord?
        var updatedAt: Date
    }

    enum PaneContentRecord: Equatable, Sendable {
        case terminal(provider: SessionProvider, lifetime: SessionLifetime, zmxSessionId: String?)
        case webview(url: URL, title: String, showNavigation: Bool)
        case codeViewer(filePath: URL, scrollToLine: Int?)
        /// `contentType` and `payloadKind` are routing/index tokens; `payloadJSON`
        /// is the content-specific representation for payload-backed pane types.
        case payload(contentType: PaneContentType, payloadKind: String, payloadJSON: String)

        /// Anchor-less convenience for terminal records (test fixtures and
        /// call sites that have no spawn-time session id in hand).
        static func terminal(
            provider: SessionProvider,
            lifetime: SessionLifetime
        ) -> Self {
            .terminal(provider: provider, lifetime: lifetime, zmxSessionId: nil)
        }

        var contentType: PaneContentType {
            switch self {
            case .terminal:
                .terminal
            case .webview:
                .browser
            case .codeViewer:
                .codeViewer
            case .payload(let contentType, _, _):
                contentType
            }
        }
    }

    struct PaneMetadataRecord: Equatable, Sendable {
        var source: PaneSourceRecord
        var executionBackend: ExecutionBackend
        var createdAt: Date
        var title: String
        var note: String?
        var checkoutRef: String?
        var durableFacets: DurableFacetsRecord

        init(
            source: PaneSourceRecord,
            executionBackend: ExecutionBackend,
            createdAt: Date,
            title: String,
            note: String? = nil,
            checkoutRef: String? = nil,
            durableFacets: DurableFacetsRecord = .init()
        ) {
            self.source = source
            self.executionBackend = executionBackend
            self.createdAt = createdAt
            self.title = title
            self.note = normalizedOptionalString(note)
            self.checkoutRef = normalizedOptionalString(checkoutRef)
            self.durableFacets = durableFacets.fillingNilFields(
                from: .init(
                    repoId: source.repoId,
                    worktreeId: source.worktreeId,
                    cwd: source.launchDirectory
                )
            )
        }
    }

    enum PaneSourceRecord: Equatable, Sendable {
        case worktree(repoId: UUID, worktreeId: UUID, launchDirectory: URL)
        case floating(launchDirectory: URL?)

        var repoId: UUID? {
            switch self {
            case .worktree(let repoId, _, _):
                repoId
            case .floating:
                nil
            }
        }

        var worktreeId: UUID? {
            switch self {
            case .worktree(_, let worktreeId, _):
                worktreeId
            case .floating:
                nil
            }
        }

        var launchDirectory: URL? {
            switch self {
            case .worktree(_, _, let launchDirectory):
                launchDirectory
            case .floating(let launchDirectory):
                launchDirectory
            }
        }
    }

    struct DurableFacetsRecord: Equatable, Sendable {
        var repoId: UUID?
        var worktreeId: UUID?
        var cwd: URL?
        var tags: [String]

        init(repoId: UUID? = nil, worktreeId: UUID? = nil, cwd: URL? = nil, tags: [String] = []) {
            self.repoId = repoId
            self.worktreeId = worktreeId
            self.cwd = cwd
            self.tags = canonicalTags(tags)
        }

        func fillingNilFields(from defaults: Self) -> Self {
            .init(
                repoId: repoId ?? defaults.repoId,
                worktreeId: worktreeId ?? defaults.worktreeId,
                cwd: cwd ?? defaults.cwd,
                tags: tags.isEmpty ? defaults.tags : tags
            )
        }
    }

    enum PaneResidencyRecord: Equatable, Sendable {
        case active
        case backgrounded
        case pendingUndo(expiresAt: Date)
        case orphaned(worktreePath: String)
    }

    enum PanePlacementRecord: Equatable, Sendable {
        case layout
        case drawerChild(parentPaneId: UUID)
    }

    struct DrawerRecord: Equatable, Sendable {
        let drawerId: UUID
        let parentPaneId: UUID
        var childPaneIds: [UUID]
    }

    func replacePaneGraph(workspaceId: UUID, graph: PaneGraphRecord) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try validatePaneGraph(database, workspaceId: workspaceId, graph: graph)
            try replacePaneGraphRows(database, workspaceId: workspaceId, graph: graph)
        }
    }

    func fetchPaneGraph(workspaceId: UUID) throws -> PaneGraphRecord {
        try databaseWriter.read { database in
            try requireWorkspaceExists(database, id: workspaceId)
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT *
                    FROM pane
                    WHERE workspace_id = ?
                    ORDER BY created_at ASC, id ASC
                    """,
                arguments: [workspaceId.uuidString]
            )
            let panes = try rows.map { row in
                try decodePaneRecord(database, row: row)
            }
            return .init(panes: panes)
        }
    }
}

private func normalizedOptionalString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func canonicalTags(_ tags: [String]) -> [String] {
    Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
}

private func decodePaneRecord(_ database: Database, row: Row) throws -> WorkspaceCoreRepository.PaneRecord {
    let idString: String = row["id"]
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedPaneId(idString)
    }
    let contentTypeString: String = row["content_type"]
    let contentType = try decodePaneContentType(contentTypeString)
    let content = try decodePaneContentRecord(database, paneId: id, contentType: contentType)
    let source = try decodePaneSourceRecord(row)
    let executionBackendString: String = row["execution_backend"]
    let executionBackend = try decodeExecutionBackend(executionBackendString)
    let createdAt: Double = row["created_at"]
    let title: String = row["title"]
    let note: String? = row["note"]
    let checkoutRef: String? = row["checkout_ref"]
    let sourceRepoIdString: String? = row["source_repo_id"]
    let sourceWorktreeIdString: String? = row["source_worktree_id"]
    let cwdPath: String? = row["cwd"]
    let tags = try fetchPaneTags(database, paneId: id)
    let durableRepoId = try decodeOptionalUUID(
        sourceRepoIdString,
        malformedError: WorkspaceCoreRepositoryError.malformedRepoId
    )
    let durableWorktreeId = try decodeOptionalUUID(
        sourceWorktreeIdString,
        malformedError: WorkspaceCoreRepositoryError.malformedWorktreeId
    )
    let metadata = WorkspaceCoreRepository.PaneMetadataRecord(
        source: source,
        executionBackend: executionBackend,
        createdAt: Date(timeIntervalSince1970: createdAt),
        title: title,
        note: note,
        checkoutRef: checkoutRef,
        durableFacets: .init(
            repoId: durableRepoId,
            worktreeId: durableWorktreeId,
            cwd: cwdPath.map { URL(fileURLWithPath: $0) },
            tags: tags
        )
    )
    let residency = try decodePaneResidency(row)
    let placement = try decodePanePlacement(row)
    let drawer = try fetchDrawerRecord(database, parentPaneId: id)
    let updatedAt: Double = row["updated_at"]
    return .init(
        id: id,
        content: content,
        metadata: metadata,
        residency: residency,
        placement: placement,
        drawer: drawer,
        updatedAt: Date(timeIntervalSince1970: updatedAt)
    )
}

private func decodeOptionalUUID(
    _ value: String?,
    malformedError: (String) -> WorkspaceCoreRepositoryError
) throws -> UUID? {
    guard let value else { return nil }
    guard let id = UUID(uuidString: value) else {
        throw malformedError(value)
    }
    return id
}
