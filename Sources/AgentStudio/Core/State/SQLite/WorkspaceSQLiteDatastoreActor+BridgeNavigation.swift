import Foundation
import os.log

private let bridgeNavigationDatastoreLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeNavigationPersistence"
)

/// Result of preparing receiver navigation for hydration.
package struct BridgeNavigationHydration: Equatable, Sendable {
    /// Decoded records of receivers that are live or retained by available undo.
    package let records: [BridgeReceiver: BridgeNavigationRecord]
    /// Standalone Bridge panes whose legacy source could not be imported. Their
    /// legacy core payload stays intact and they present as unavailable.
    package let failedConversionPaneIDs: Set<UUID>

    package init(records: [BridgeReceiver: BridgeNavigationRecord], failedConversionPaneIDs: Set<UUID>) {
        self.records = records
        self.failedConversionPaneIDs = failedConversionPaneIDs
    }

    package static let empty = Self(records: [:], failedConversionPaneIDs: [])
}

extension WorkspaceSQLiteDatastoreActor {
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
                failedConversionPaneIDs: Set(legacyPayloads.map(\.paneId))
            )
        }

        let existingRows: [BridgeNavigationRow]
        do {
            existingRows = try localRepository.fetchBridgeNavigationRows()
        } catch {
            preserveUnimportedLegacyPayloads(legacyPayloads)
            return BridgeNavigationHydration(
                records: [:],
                failedConversionPaneIDs: Set(legacyPayloads.map(\.paneId))
            )
        }

        let importedPaneIDs = importLegacyPayloads(
            legacyPayloads.filter { payload in
                !existingRows.contains { $0.receiver.paneId == payload.paneId }
            },
            existingRowPaneIDs: Set(existingRows.map(\.receiver.paneId)),
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
        return BridgeNavigationHydration(records: records, failedConversionPaneIDs: failedConversionPaneIDs)
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
            let rows = try payloadsToImport.map { payload in
                try BridgeNavigationPayloadCodec.encodeRow(
                    BridgeLegacySourceConversion.importedRecord(
                        for: payload,
                        knownWorktreeIdsByCanonicalRootPath: knownWorktreeIDsByCanonicalRoot,
                        canonicalize: Self.canonicalPath
                    ),
                    for: .standalone(payload.paneId)
                )
            }
            return try localRepository.insertBridgeNavigationRowsIfAbsent(rows, updatedAt: importedAt)
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
        let rows: [BridgeNavigationRow]
        let retainedPaneIDs: Set<UUID>
        do {
            rows = try localRepository.fetchBridgeNavigationRows()
            retainedPaneIDs = try coreRepository.fetchLivePaneIDs(workspaceID: workspaceID)
                .union(coreRepository.fetchAvailableUndoMemberPaneIDs(workspaceID: workspaceID))
        } catch {
            bridgeNavigationDatastoreLogger.error("Bridge navigation rows could not be loaded; receivers default")
            return [:]
        }
        var records: [BridgeReceiver: BridgeNavigationRecord] = [:]
        for row in rows where retainedPaneIDs.contains(row.receiver.paneId) {
            do {
                records[row.receiver] = try BridgeNavigationPayloadCodec.decodeRecord(from: row)
            } catch {
                // A malformed row defaults only its own receiver.
                bridgeNavigationDatastoreLogger.error("Bridge navigation row is malformed; receiver defaults")
            }
        }
        return records
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
            bridgeNavigationRows: try retainedBridgeNavigationRows(bundle, coreRepository: backend.coreRepository),
            localRepository: localRepository
        )
    }

    /// Rows to write for an ordinary save: records of receivers that are live
    /// in the saved composition or retained by available undo. Everything else
    /// is dropped from the table here — eligible cleanup through the same path.
    func retainedBridgeNavigationRows(
        _ bundle: WorkspaceSQLiteSaveBundle,
        coreRepository: WorkspaceCoreRepository
    ) throws -> [BridgeNavigationRow]? {
        guard let bridgeNavigation = bundle.bridgeNavigation else { return nil }
        let retainedPaneIDs = Set(bundle.workspace.panes.map(\.id))
            .union(try coreRepository.fetchAvailableUndoMemberPaneIDs(workspaceID: bundle.id))
        return try bridgeNavigation.records
            .filter { retainedPaneIDs.contains($0.key.paneId) }
            .sorted { $0.key.paneId.uuidString < $1.key.paneId.uuidString }
            .map { try BridgeNavigationPayloadCodec.encodeRow($0.value, for: $0.key) }
    }

    static func canonicalPath(_ path: String) -> String {
        DarwinFSEventPathCanonicalizer.canonicalURL(URL(fileURLWithPath: path)).path
    }
}
