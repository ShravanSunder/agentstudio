import Foundation
import os.log

private let bridgeNavigationDatastoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeNavigationPersistence"
)

/// Raw pane and topology facts copied at a link command's effect point.
/// Owner resolution and CWD admission happen in the datastore actor.
package struct BridgeReceiverTopologySnapshot: Sendable {
    package let sourcePaneId: UUID
    package let paneStatesByID: [UUID: PaneGraphState]
    package let companionEntriesBySourceID: [UUID: ZoomCompanionMetadata]
    package let repositoryTopology: RepositoryTopologyReadSnapshot

    package init(
        sourcePaneId: UUID, paneStatesByID: [UUID: PaneGraphState],
        companionEntriesBySourceID: [UUID: ZoomCompanionMetadata],
        repositoryTopology: RepositoryTopologyReadSnapshot
    ) {
        self.sourcePaneId = sourcePaneId
        self.paneStatesByID = paneStatesByID
        self.companionEntriesBySourceID = companionEntriesBySourceID
        self.repositoryTopology = repositoryTopology
    }
}

/// All link-dependent UI decisions prepared off MainActor after a durable
/// commit. The App adapter only applies this value to the atom and mounted UI.
package struct BridgeCommittedLinkApplication: Sendable {
    package let record: BridgeNavigationRecord
    package let openedDocumentUpdates: [BridgeOpenedDocumentAtomUpdate]
    package let memberRoots: [UUID: String]
    package let reviewReplacement: BridgeNavigationSurface?

    package init(
        record: BridgeNavigationRecord,
        openedDocumentUpdates: [BridgeOpenedDocumentAtomUpdate],
        memberRoots: [UUID: String],
        reviewReplacement: BridgeNavigationSurface?
    ) {
        self.record = record
        self.openedDocumentUpdates = openedDocumentUpdates
        self.memberRoots = memberRoots
        self.reviewReplacement = reviewReplacement
    }
}

/// Repository-prepared removal preview. Draft-barrier admission stays off
/// MainActor; the App only invokes the barrier when this value requests it.
package struct BridgeMemberRemovalPreview: Sendable {
    package let result: BridgeMemberContributionRemoval
    package let requiresDraftBarrier: Bool

    package init(result: BridgeMemberContributionRemoval, requiresDraftBarrier: Bool) {
        self.result = result
        self.requiresDraftBarrier = requiresDraftBarrier
    }
}

/// Result of preparing receiver navigation for hydration.
package struct BridgeNavigationHydration: Equatable, Sendable {
    /// Decoded records of receivers that are live or retained by available undo.
    package let records: [BridgeReceiver: BridgeNavigationRecord]
    /// Standalone Bridge panes whose legacy source could not be imported. Their
    /// legacy core payload stays intact and they present as unavailable.
    package let failedConversionPaneIDs: Set<UUID>
    package let generationFloor: Int

    package init(
        records: [BridgeReceiver: BridgeNavigationRecord], failedConversionPaneIDs: Set<UUID>, generationFloor: Int
    ) {
        self.records = records
        self.failedConversionPaneIDs = failedConversionPaneIDs
        self.generationFloor = generationFloor
    }

    package static let empty = Self(records: [:], failedConversionPaneIDs: [], generationFloor: 0)
}

extension WorkspaceSQLiteDatastoreActor {
    package func prepareBridgeCommittedLinkApplication(
        committedRecord: BridgeNavigationRecord, latestUIRecord: BridgeNavigationRecord,
        topologySnapshot: BridgeReceiverTopologySnapshot, removedWorktreeID: UUID?,
        removedRoot: String?
    ) async -> BridgeCommittedLinkApplication {
        var roots = topologySnapshot.effectiveMemberRoots(in: latestUIRecord)
        if let removedRoot {
            // A catalog unregistration carries the old root because the
            // current topology no longer admits that worktree. Invalid input
            // keeps the committed projection, never the newer stale UI rows.
            guard let removedWorktreeID, removedRoot.hasPrefix("/") else {
                return BridgeCommittedLinkApplication(
                    record: committedRecord,
                    openedDocumentUpdates: BridgeOpenedDocumentAtomUpdate.difference(
                        from: latestUIRecord, to: committedRecord),
                    memberRoots: roots,
                    reviewReplacement: committedRecord.reviewSelection == latestUIRecord.reviewSelection
                        ? nil : committedRecord.surface)
            }
            roots[removedWorktreeID] =
                DarwinFSEventPathCanonicalizer.canonicalURL(
                    URL(fileURLWithPath: removedRoot)
                ).path
        } else if let removedWorktreeID, roots[removedWorktreeID] == nil,
            let removed = topologySnapshot.knownWorktree(removedWorktreeID)
        {
            roots[removedWorktreeID] = DarwinFSEventPathCanonicalizer.canonicalURL(removed.path).path
        }
        let reconciled = BridgeNavigationRules.reconcilingCommittedLinks(
            committedRecord, with: latestUIRecord, removedWorktreeId: removedWorktreeID,
            memberRootsByWorktreeId: roots)
        return BridgeCommittedLinkApplication(
            record: reconciled,
            openedDocumentUpdates: BridgeOpenedDocumentAtomUpdate.difference(
                from: latestUIRecord, to: reconciled),
            memberRoots: roots,
            reviewReplacement: reconciled.reviewSelection == latestUIRecord.reviewSelection
                ? nil : reconciled.surface)
    }

    package func previewBridgeCatalogMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver, worktreeID: UUID,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) throws -> BridgeMemberRemovalOutcome {
        try preparedLocalRepository(workspaceId: workspaceID).previewBridgeCatalogMemberRemoval(
            receiver: receiver, worktreeID: worktreeID, removedRoot: removedRoot,
            memberRootsByWorktreeID: memberRootsByWorktreeID)
    }

    package func commitBridgeCatalogMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver, worktreeID: UUID, generation: Int,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) throws -> BridgeCatalogMemberRemovalReceipt {
        let repository = try preparedLocalRepository(workspaceId: workspaceID)
        let (record, result, deletedContributors) = try repository.commitBridgeCatalogMemberRemoval(
            receiver: receiver, worktreeID: worktreeID, generation: generation,
            removedRoot: removedRoot, memberRootsByWorktreeID: memberRootsByWorktreeID)
        bridgeCommitSequence += 1
        return BridgeCatalogMemberRemovalReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration(),
            deletedContributors: deletedContributors
        )
    }

    package func previewBridgeMemberRemoval(
        workspaceID: UUID, receiver: BridgeReceiver,
        worktreeID: UUID, contributor: BridgeLinkContributor,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> BridgeMemberRemovalPreview {
        let result = try preparedLocalRepository(workspaceId: workspaceID).previewBridgeMemberRemoval(
            receiver: receiver, worktreeID: worktreeID, contributor: contributor,
            topologySnapshot: topologySnapshot)
        let requiresDraftBarrier: Bool
        if case .removed(_, let effect?, _) = result {
            requiresDraftBarrier = effect.clearedFilesSelection || effect.reviewFallback != .unchanged
        } else {
            requiresDraftBarrier = false
        }
        return BridgeMemberRemovalPreview(result: result, requiresDraftBarrier: requiresDraftBarrier)
    }

    package func commitBridgeMemberAddition(
        context: BridgeLinkMutationContext, worktreeID: UUID,
        contributor: BridgeLinkContributor, addedAt: Date
    ) throws -> BridgeLinkCommitReceipt<BridgeMemberAddResult> {
        let repository = try preparedLocalRepository(workspaceId: context.workspaceID)
        let (record, result) = try repository.commitBridgeMemberAddition(
            receiver: context.receiver,
            worktreeID: worktreeID, contributor: contributor, generation: context.generation,
            addedAt: addedAt, topologySnapshot: context.topologySnapshot)
        bridgeCommitSequence += 1
        return BridgeLinkCommitReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration())
    }

    package func commitBridgeMemberRemoval(
        context: BridgeLinkMutationContext, worktreeID: UUID,
        contributor: BridgeLinkContributor
    ) throws -> BridgeLinkCommitReceipt<BridgeMemberContributionRemoval> {
        let repository = try preparedLocalRepository(workspaceId: context.workspaceID)
        let (record, result) = try repository.commitBridgeMemberRemoval(
            receiver: context.receiver,
            worktreeID: worktreeID, contributor: contributor, generation: context.generation,
            topologySnapshot: context.topologySnapshot)
        bridgeCommitSequence += 1
        return BridgeLinkCommitReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration())
    }

    package func commitBridgePullRequestAddition(
        context: BridgeLinkMutationContext, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor, addedAt: Date
    ) throws -> BridgeLinkCommitReceipt<BridgePullRequestReferenceAddResult> {
        let repository = try preparedLocalRepository(workspaceId: context.workspaceID)
        let (record, result) = try repository.commitBridgePullRequestAddition(
            receiver: context.receiver,
            identity: identity, contributor: contributor, generation: context.generation,
            addedAt: addedAt, topologySnapshot: context.topologySnapshot)
        bridgeCommitSequence += 1
        return BridgeLinkCommitReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration())
    }

    package func commitBridgePullRequestRemoval(
        context: BridgeLinkMutationContext, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor
    ) throws -> BridgeLinkCommitReceipt<BridgePullRequestContributionRemoval> {
        let repository = try preparedLocalRepository(workspaceId: context.workspaceID)
        let (record, result) = try repository.commitBridgePullRequestRemoval(
            receiver: context.receiver,
            identity: identity, contributor: contributor, generation: context.generation,
            topologySnapshot: context.topologySnapshot)
        bridgeCommitSequence += 1
        return BridgeLinkCommitReceipt(
            record: record, result: result, commitSequence: bridgeCommitSequence,
            generationFloor: try repository.latestBridgeGeneration())
    }

    /// Run the ordered legacy conversion and load receiver navigation, before
    /// any mount or source-changing command.
    ///
    /// Order per legacy standalone Bridge pane: import its exact root and
    /// comparison into the local record, commit and acknowledge that write,
    /// then rewrite the core payload without the legacy field. The two
    /// databases never share a transaction: a failed local import keeps the
    /// legacy core payload intact (and protected from ordinary saves), and a
    /// failed core rewrite is retried on the next start without overwriting
    /// the already-imported local record.
    package func prepareBridgeNavigationHydration(
        workspaceID: UUID,
        knownWorktreeRootsByID: [UUID: URL],
        importedAt: Date = Date()
    ) async -> BridgeNavigationHydration {
        let coreRepository: WorkspaceCoreRepository
        let corePayloads: [(paneID: UUID, payloadJSON: String)]
        do {
            coreRepository = try journalRepository()
            corePayloads = try coreRepository.fetchBridgePanePayloads(workspaceID: workspaceID)
        } catch {
            bridgeNavigationDatastoreLogger.error("Bridge navigation core read failed: \(String(reflecting: error))")
            return .empty
        }

        let legacyPayloads = corePayloads.compactMap { stored -> BridgeLegacyPanePayload? in
            do {
                return try BridgeLegacySourceConversion.legacyPayload(
                    paneId: stored.paneID,
                    storedPayloadJSON: stored.payloadJSON
                )
            } catch {
                bridgeNavigationDatastoreLogger.error("Bridge pane payload is malformed; conversion skipped")
                return nil
            }
        }

        guard let localRepository = try? preparedLocalRepository(workspaceId: workspaceID) else {
            preserveUnimportedLegacyPayloads(legacyPayloads)
            return BridgeNavigationHydration(
                records: [:],
                failedConversionPaneIDs: Set(legacyPayloads.map(\.paneId)),
                generationFloor: 0
            )
        }

        let existingRows: BridgeReceiverReadback
        do {
            existingRows = try localRepository.readBridgeReceivers()
        } catch {
            preserveUnimportedLegacyPayloads(legacyPayloads)
            return BridgeNavigationHydration(
                records: [:],
                failedConversionPaneIDs: Set(legacyPayloads.map(\.paneId)),
                generationFloor: 0
            )
        }

        let importedPaneIDs = importLegacyPayloads(
            legacyPayloads.filter { payload in
                !existingRows.presentPaneIDs.contains(payload.paneId)
            },
            existingRowPaneIDs: Set(existingRows.records.keys.map(\.paneId)),
            knownWorktreeRootsByID: knownWorktreeRootsByID,
            localRepository: localRepository,
            importedAt: importedAt
        )

        var failedConversionPaneIDs = Set<UUID>()
        for payload in legacyPayloads {
            guard importedPaneIDs.contains(payload.paneId) else {
                failedConversionPaneIDs.insert(payload.paneId)
                continue
            }
            legacyBridgePayloadsAwaitingImport.removeValue(forKey: payload.paneId)
            do {
                try coreRepository.rewriteLegacyBridgePanePayload(
                    paneID: payload.paneId,
                    expectedPayloadJSON: payload.originalPayloadJSON,
                    convertedPayloadJSON: payload.convertedPayloadJSON
                )
            } catch {
                // The imported record is acknowledged; the next start retries only this step.
                bridgeNavigationDatastoreLogger.error("Bridge legacy core rewrite failed; retried on next start")
            }
        }

        let records = loadRetainedRecords(
            workspaceID: workspaceID,
            coreRepository: coreRepository,
            localRepository: localRepository
        )
        bridgeOpenedDocumentFloorMillisByReceiver = records.mapValues { record in
            record.openedDocuments.values.compactMap {
                openedDocumentSortKeyMillis($0.sortKey)
            }.max() ?? 0
        }
        return BridgeNavigationHydration(
            records: records, failedConversionPaneIDs: failedConversionPaneIDs,
            generationFloor: (try? localRepository.latestBridgeGeneration()) ?? 0)
    }

    /// Commit imported rows and return every legacy pane whose local record is
    /// present afterwards (already present or newly acknowledged).
    private func importLegacyPayloads(
        _ payloadsToImport: [BridgeLegacyPanePayload],
        existingRowPaneIDs: Set<UUID>,
        knownWorktreeRootsByID: [UUID: URL],
        localRepository: WorkspaceLocalRepository,
        importedAt: Date
    ) -> Set<UUID> {
        guard !payloadsToImport.isEmpty else { return existingRowPaneIDs }
        let knownWorktreeIDsByCanonicalRoot = Dictionary(
            knownWorktreeRootsByID.map { (Self.canonicalPath($0.value.path), $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        do {
            let records = Dictionary(
                uniqueKeysWithValues: payloadsToImport.map { payload in
                    (
                        BridgeReceiver.standalone(payload.paneId),
                        BridgeLegacySourceConversion.importedRecord(
                            for: payload,
                            knownWorktreeIdsByCanonicalRootPath: knownWorktreeIDsByCanonicalRoot,
                            canonicalize: Self.canonicalPath,
                            importedAt: importedAt
                        )
                    )
                })
            return try localRepository.insertBridgeReceiversIfAbsent(records)
        } catch {
            bridgeNavigationDatastoreLogger.error("Bridge legacy import failed; legacy payload kept intact")
            preserveUnimportedLegacyPayloads(payloadsToImport)
            return existingRowPaneIDs
        }
    }

    private func preserveUnimportedLegacyPayloads(_ payloads: [BridgeLegacyPanePayload]) {
        for payload in payloads {
            legacyBridgePayloadsAwaitingImport[payload.paneId] = payload.originalPayloadJSON
        }
    }

    private func loadRetainedRecords(
        workspaceID: UUID,
        coreRepository: WorkspaceCoreRepository,
        localRepository: WorkspaceLocalRepository
    ) -> [BridgeReceiver: BridgeNavigationRecord] {
        let readback: BridgeReceiverReadback
        let retainedPaneIDs: Set<UUID>
        do {
            readback = try localRepository.readBridgeReceivers()
            retainedPaneIDs = try coreRepository.fetchLivePaneIDs(workspaceID: workspaceID)
                .union(coreRepository.fetchAvailableUndoMemberPaneIDs(workspaceID: workspaceID))
        } catch {
            bridgeNavigationDatastoreLogger.error("Bridge navigation rows could not be loaded; receivers default")
            return [:]
        }
        return readback.records.filter { retainedPaneIDs.contains($0.key.paneId) }
    }

    /// Core write that keeps unimported legacy Bridge payloads byte-exact.
    func replaceCoreWorkspaceSnapshot(
        _ bundle: WorkspaceSQLiteSaveBundle,
        backend: WorkspaceSQLiteStoreBackend,
        undoChange: WorkspaceUndoJournalChange?
    ) throws -> WorkspaceUndoJournalReceipt? {
        try backend.replaceWorkspaceSnapshot(
            bundle,
            updatesActiveSelection: true,
            undoChange: undoChange,
            preservingLegacyBridgePayloads: legacyBridgePayloadsAwaitingImport
        )
    }

    /// Local write of an ordinary save: cursors, window state and the
    /// retained receiver navigation rows in one local transaction.
    func writeLocalWorkspaceSnapshot(
        _ bundle: WorkspaceSQLiteSaveBundle,
        backend: WorkspaceSQLiteStoreBackend,
        localRepository: WorkspaceLocalRepository
    ) throws {
        try backend.writeLocalSnapshot(
            bundle.workspace,
            bridgeNavigationRecords: try retainedBridgeNavigationRecords(
                bundle, coreRepository: backend.coreRepository),
            bridgeNavigationGeneration: bundle.bridgeNavigation?.revision,
            localRepository: localRepository
        )
    }

    /// Rows to write for an ordinary save: records of receivers that are live
    /// in the saved composition or retained by available undo. Everything else
    /// is dropped from the table here — eligible cleanup through the same path.
    func retainedBridgeNavigationRecords(
        _ bundle: WorkspaceSQLiteSaveBundle,
        coreRepository: WorkspaceCoreRepository
    ) throws -> [BridgeReceiver: BridgeNavigationRecord]? {
        guard let bridgeNavigation = bundle.bridgeNavigation else { return nil }
        let retainedPaneIDs = Set(bundle.workspace.panes.map(\.id))
            .union(try coreRepository.fetchAvailableUndoMemberPaneIDs(workspaceID: bundle.id))
        return bridgeNavigation.records
            .filter { retainedPaneIDs.contains($0.key.paneId) }
    }

    static func canonicalPath(_ path: String) -> String {
        DarwinFSEventPathCanonicalizer.canonicalURL(URL(fileURLWithPath: path)).path
    }
}
