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
        case terminal(provider: SessionProvider, lifetime: SessionLifetime, zmxSessionID: ZmxSessionID)
        case webview(url: URL, title: String, showNavigation: Bool)
        case codeViewer(filePath: URL, scrollToLine: Int?)
        /// `contentType` and `payloadKind` are routing/index tokens; `payloadJSON`
        /// is the content-specific representation for payload-backed pane types.
        case payload(contentType: PaneContentType, payloadKind: String, payloadJSON: String)

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
        var launchDirectory: URL?
        var executionBackend: ExecutionBackend
        var createdAt: Date
        var title: String
        var note: String?
        var checkoutRef: String?
        var durableFacets: DurableFacetsRecord

        init(
            launchDirectory: URL? = nil,
            executionBackend: ExecutionBackend,
            createdAt: Date,
            title: String,
            note: String? = nil,
            checkoutRef: String? = nil,
            durableFacets: DurableFacetsRecord = .init()
        ) {
            self.launchDirectory = launchDirectory
            self.executionBackend = executionBackend
            self.createdAt = createdAt
            self.title = title
            self.note = normalizedOptionalString(note)
            self.checkoutRef = normalizedOptionalString(checkoutRef)
            self.durableFacets = durableFacets.fillingNilFields(
                from: .init(
                    cwd: launchDirectory
                )
            )
        }
    }

    struct DurableFacetsRecord: Equatable, Sendable {
        var repoId: UUID?
        var worktreeId: UUID?
        var cwd: URL?

        init(repoId: UUID? = nil, worktreeId: UUID? = nil, cwd: URL? = nil) {
            self.repoId = repoId
            self.worktreeId = worktreeId
            self.cwd = cwd
        }

        func fillingNilFields(from defaults: Self) -> Self {
            .init(
                repoId: repoId ?? defaults.repoId,
                worktreeId: worktreeId ?? defaults.worktreeId,
                cwd: cwd ?? defaults.cwd
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

private func decodePaneRecord(_ database: Database, row: Row) throws -> WorkspaceCoreRepository.PaneRecord {
    let idString: String = row["id"]
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedPaneId(idString)
    }
    let contentTypeString: String = row["content_type"]
    let contentType = try decodePaneContentType(contentTypeString)
    let content = try decodePaneContentRecord(database, paneId: id, contentType: contentType)
    let launchDirectoryPath: String? = row["launch_directory"]
    let executionBackendString: String = row["execution_backend"]
    let executionBackend = try decodeExecutionBackend(executionBackendString)
    let createdAt: Double = row["created_at"]
    let title: String = row["title"]
    let note: String? = row["note"]
    let checkoutRef: String? = row["checkout_ref"]
    let sourceRepoIdString: String? = row["facet_repo_id"]
    let sourceWorktreeIdString: String? = row["facet_worktree_id"]
    let cwdPath: String? = row["cwd"]
    let durableRepoId = try decodeOptionalUUID(
        sourceRepoIdString,
        malformedError: WorkspaceCoreRepositoryError.malformedRepoId
    )
    let durableWorktreeId = try decodeOptionalUUID(
        sourceWorktreeIdString,
        malformedError: WorkspaceCoreRepositoryError.malformedWorktreeId
    )
    let metadata = WorkspaceCoreRepository.PaneMetadataRecord(
        launchDirectory: launchDirectoryPath.map { URL(fileURLWithPath: $0) },
        executionBackend: executionBackend,
        createdAt: Date(timeIntervalSince1970: createdAt),
        title: title,
        note: note,
        checkoutRef: checkoutRef,
        durableFacets: .init(
            repoId: durableRepoId,
            worktreeId: durableWorktreeId,
            cwd: cwdPath.map { URL(fileURLWithPath: $0) }
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
