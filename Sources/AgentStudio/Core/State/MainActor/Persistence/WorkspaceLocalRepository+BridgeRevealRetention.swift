import Foundation
import GRDB

private struct BridgeResolvedRevealTarget {
    let location: BridgeDocumentLocation
    let repositoryID: UUID
}

private struct BridgeStoredOpenedDocumentFloor {
    let generation: Int
    let isDeleted: Bool
    let retainedGeneration: Int?
}

private struct BridgeRetainedMetadataWrite {
    let location: BridgeDocumentLocation
    let item: BridgeRetainedOpenViewItem?
    let provenance: BridgeKnownWorktreeProvenance?
    let generation: Int
}

extension WorkspaceLocalRepository {
    func previewAgentReveal(
        receiver: BridgeReceiver, target: BridgeRevealFileTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> BridgeRevealAdmissionPreflight {
        try databaseWriter.read { database in
            if try WorkspaceLocalRepositoryStorage.isRetired(database, workspaceID: workspaceId, receiver: receiver) {
                return .staleReceiver
            }
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return .staleOwner
            case .staleReceiver: return .staleReceiver
            case .current: break
            }
            guard let resolved = Self.resolveRevealTarget(target, topologySnapshot: topologySnapshot) else {
                return .unsupportedTarget
            }
            return .eligible(location: resolved.location)
        }
    }

    func retainAgentReveal(
        receiver: BridgeReceiver, target: BridgeRevealFileTarget,
        requestedBy: BridgeLinkContributor, generation: Int, retainedAt: Date,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> (record: BridgeNavigationRecord, result: BridgeRevealRetentionResult) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return (current, .staleOwner)
            case .staleReceiver: return (current, .staleReceiver)
            case .current: break
            }
            guard case .agent = requestedBy,
                let resolved = Self.resolveRevealTarget(target, topologySnapshot: topologySnapshot)
            else { return (current, .unsupportedTarget) }
            let provenance: BridgeKnownWorktreeProvenance? =
                current.committedMemberWorktreeIds.contains(target.worktree)
                ? .init(
                    repoId: resolved.repositoryID, worktreeId: target.worktree,
                    relativePath: target.relativePath)
                : nil
            let floor = try Self.openedDocumentFloor(
                database, workspaceID: workspaceId, receiver: receiver, location: resolved.location)
            if let floor,
                (floor.retainedGeneration ?? -1) >= generation
                    || (floor.isDeleted && floor.generation >= generation)
            {
                return (current, .superseded)
            }

            if current.openedDocument(at: resolved.location) == nil {
                var desired = current
                desired.openedDocuments.append(.init(location: resolved.location, provenance: provenance))
                try WorkspaceLocalRepositoryStorage.writeChanges(
                    database,
                    change: .init(
                        workspaceID: workspaceId, receiver: receiver, current: current,
                        desired: desired, generation: generation, includeItems: false,
                        forceDependentDeletes: false))
            }
            let item = BridgeRetainedOpenViewItem(
                target: target, requestedBy: requestedBy, retainedAt: retainedAt)
            let changed = try Self.updateRetainedMetadata(
                database, workspaceID: workspaceId, receiver: receiver,
                write: .init(
                    location: resolved.location, item: item,
                    provenance: provenance, generation: generation))
            guard changed else {
                return (
                    try WorkspaceLocalRepositoryStorage.readRecord(
                        database, workspaceID: workspaceId, receiver: receiver), .superseded
                )
            }
            return (
                try WorkspaceLocalRepositoryStorage.readRecord(
                    database, workspaceID: workspaceId, receiver: receiver), .retained(item)
            )
        }
    }

    func clearRetainedOpenViewItem(
        receiver: BridgeReceiver, location: BridgeDocumentLocation,
        generation: Int, topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> (record: BridgeNavigationRecord, result: BridgeRevealRetentionResult) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return (current, .staleOwner)
            case .staleReceiver: return (current, .staleReceiver)
            case .current: break
            }
            let floor = try Self.openedDocumentFloor(
                database, workspaceID: workspaceId, receiver: receiver, location: location)
            if let floor, (floor.retainedGeneration ?? -1) >= generation {
                return (current, .superseded)
            }
            guard let document = current.openedDocument(at: location) else {
                // A clear still consumes its ticket when an older retain has not
                // inserted the document yet. Keep that fence in the keyed row.
                try Self.fenceAbsentRetainedDocument(
                    database, workspaceID: workspaceId, receiver: receiver,
                    location: location, generation: generation)
                return (current, .alreadyAbsent)
            }
            let changed = try Self.updateRetainedMetadata(
                database, workspaceID: workspaceId, receiver: receiver,
                write: .init(
                    location: location, item: nil,
                    provenance: document.provenance, generation: generation))
            guard changed else { return (current, .superseded) }
            let updated = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            return (updated, document.retainedOpenViewItem == nil ? .alreadyAbsent : .cleared)
        }
    }

    func retainedOpenViewItems(receiver: BridgeReceiver) throws -> [BridgeRetainedOpenViewItem] {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver
            )
            .openedDocuments.compactMap(\.retainedOpenViewItem)
        }
    }

    private static func resolveRevealTarget(
        _ target: BridgeRevealFileTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) -> BridgeResolvedRevealTarget? {
        guard let worktree = topologySnapshot.knownWorktree(target.worktree) else { return nil }
        let root = DarwinFSEventPathCanonicalizer.canonicalURL(worktree.path)
        let file = DarwinFSEventPathCanonicalizer.canonicalURL(
            root.appendingPathComponent(target.relativePath, isDirectory: false))
        guard let location = BridgeDocumentLocation(canonicalPath: file.path),
            location.isContained(inCanonicalRoot: root.path)
        else { return nil }
        // The derived CWD is live-only. The transaction decides provenance
        // from committed contributions after reading its current receiver.
        return BridgeResolvedRevealTarget(location: location, repositoryID: worktree.repoId)
    }

    private static func openedDocumentFloor(
        _ database: Database, workspaceID: UUID, receiver: BridgeReceiver,
        location: BridgeDocumentLocation
    ) throws -> BridgeStoredOpenedDocumentFloor? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT generation, is_deleted, retained_generation FROM bridge_receiver_state
                    WHERE workspace_id = ? AND receiver_pane_id = ? AND kind = 'openedDocument' AND item_key = ?
                    """,
                arguments: [
                    workspaceID.uuidString, receiver.paneId.uuidString,
                    BridgeReceiverStateKeyCodec.document(location),
                ])
        else { return nil }
        let isDeleted: Int = row["is_deleted"]
        return BridgeStoredOpenedDocumentFloor(
            generation: row["generation"], isDeleted: isDeleted == 1,
            retainedGeneration: row["retained_generation"])
    }

    private static func updateRetainedMetadata(
        _ database: Database, workspaceID: UUID, receiver: BridgeReceiver,
        write: BridgeRetainedMetadataWrite
    ) throws -> Bool {
        let requester = write.item?.requestedBy
        let requesterKind: String?
        let requesterProvider: String?
        let requesterSessionRef: String?
        switch requester {
        case .app:
            requesterKind = "app"
            requesterProvider = nil
            requesterSessionRef = nil
        case .person:
            requesterKind = "person"
            requesterProvider = nil
            requesterSessionRef = nil
        case .agent(let identity):
            requesterKind = "agent"
            requesterProvider = identity.provider.value
            requesterSessionRef = identity.sessionRef.value
        case nil:
            requesterKind = nil
            requesterProvider = nil
            requesterSessionRef = nil
        }
        try database.execute(
            sql: """
                UPDATE bridge_receiver_state SET
                    provenance_repo_id = ?, provenance_worktree_id = ?, provenance_relative_path = ?,
                    retained_worktree_id = ?, retained_relative_path = ?, retained_line = ?,
                    retained_requester_key = ?, retained_requester_kind = ?,
                    retained_requester_provider = ?, retained_requester_session_ref = ?,
                    retained_at = ?, retained_generation = ?
                WHERE workspace_id = ? AND receiver_pane_id = ? AND kind = 'openedDocument'
                    AND item_key = ? AND is_deleted = 0
                    AND (retained_generation IS NULL OR retained_generation < ?)
                """,
            arguments: [
                write.provenance?.repoId.uuidString, write.provenance?.worktreeId.uuidString,
                write.provenance?.relativePath, write.item?.target.worktree.uuidString,
                write.item?.target.relativePath, write.item?.target.line,
                requester.map(BridgeLinkContributorKeyCodec.encode), requesterKind,
                requesterProvider, requesterSessionRef, write.item?.retainedAt.timeIntervalSince1970,
                write.generation, workspaceID.uuidString, receiver.paneId.uuidString,
                BridgeReceiverStateKeyCodec.document(write.location), write.generation,
            ])
        return database.changesCount == 1
    }

    private static func fenceAbsentRetainedDocument(
        _ database: Database, workspaceID: UUID, receiver: BridgeReceiver,
        location: BridgeDocumentLocation, generation: Int
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO bridge_receiver_state (
                    workspace_id, receiver_pane_id, receiver_kind, kind, item_key,
                    generation, is_deleted, document_path, retained_generation
                ) VALUES (?, ?, ?, 'openedDocument', ?, ?, 1, ?, ?)
                ON CONFLICT(workspace_id, receiver_pane_id, kind, item_key) DO UPDATE SET
                    generation = MAX(bridge_receiver_state.generation, excluded.generation),
                    retained_generation = excluded.retained_generation
                WHERE bridge_receiver_state.is_deleted = 1
                    AND (bridge_receiver_state.retained_generation IS NULL
                        OR bridge_receiver_state.retained_generation < excluded.retained_generation)
                """,
            arguments: [
                workspaceID.uuidString, receiver.paneId.uuidString, receiver.kind.rawValue,
                BridgeReceiverStateKeyCodec.document(location), generation,
                location.canonicalPath, generation,
            ])
    }
}
