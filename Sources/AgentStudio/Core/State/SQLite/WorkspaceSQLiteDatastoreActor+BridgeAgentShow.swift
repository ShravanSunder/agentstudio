import Foundation

extension WorkspaceSQLiteDatastoreActor {
    package func prepareAgentShow(
        workspaceID: UUID, receiver: BridgeReceiver, target: BridgeAgentShowTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot,
        currentEntries: [BridgeDocumentLocation: BridgeOpenedDocumentEntry]
    ) async throws -> BridgeAgentShowPreparation {
        switch topologySnapshot.ownerDisposition(for: receiver) {
        case .current: break
        case .staleOwner, .staleReceiver: return .paneUnavailable
        }
        guard let worktree = topologySnapshot.knownWorktree(target.worktree),
            let location = await BridgeAgentShowFileResolver.resolve(
                root: worktree.path, relativePath: target.relativePath)
        else { return .notFound }

        let repository = try preparedLocalRepository(workspaceId: workspaceID)
        guard try !repository.isBridgeReceiverRetired(receiver) else { return .paneUnavailable }
        if currentEntries[location] != nil {
            return .prepared(
                location: location,
                entry: prepareOpenedDocumentEntry(
                    receiver: receiver, location: location, currentEntries: currentEntries,
                    provenance: nil, openedLine: target.line))
        }
        let committed = try repository.readBridgeReceivers().records[receiver]
        let provenance: BridgeKnownWorktreeProvenance? =
            committed?.committedMemberWorktreeIds.contains(target.worktree) == true
            ? .init(
                repoId: worktree.repoId, worktreeId: target.worktree,
                relativePath: target.relativePath)
            : nil
        return .prepared(
            location: location,
            entry: prepareOpenedDocumentEntry(
                receiver: receiver, location: location, currentEntries: currentEntries,
                provenance: provenance, openedLine: target.line))
    }

    /// Both agent show and human displayed-selection admissions pass through
    /// this receiver-owned mint point. An existing location keeps its key and
    /// original provenance; a fresh location advances the logical floor.
    package func prepareOpenedDocumentEntry(
        receiver: BridgeReceiver, location: BridgeDocumentLocation,
        currentEntries: [BridgeDocumentLocation: BridgeOpenedDocumentEntry],
        provenance: BridgeKnownWorktreeProvenance?, openedLine: Int?
    ) -> BridgeOpenedDocumentEntry {
        if let current = currentEntries[location] {
            return BridgeOpenedDocumentEntry(
                provenance: current.provenance, openedLine: openedLine,
                sortKey: current.sortKey)
        }
        let capturedFloor =
            currentEntries.values.compactMap {
                openedDocumentSortKeyMillis($0.sortKey)
            }.max() ?? 0
        let floor = max(bridgeOpenedDocumentFloorMillisByReceiver[receiver] ?? 0, capturedFloor)
        let minted = mintOpenedDocumentSortKey(
            wallMillis: UInt64(Date().timeIntervalSince1970 * 1000), floorMillis: floor)
        // No suspension between floor read and write: actor reentrancy cannot
        // give two accepted opens the same logical millisecond.
        bridgeOpenedDocumentFloorMillisByReceiver[receiver] = minted.newFloorMillis
        return BridgeOpenedDocumentEntry(
            provenance: provenance, openedLine: openedLine, sortKey: minted.key)
    }

    /// The page's displayed receipt is already tied to a canonical collection
    /// identity. Validate its member against copied topology and mint through
    /// the same receiver floor as agent show.
    package func prepareDisplayedFilesSelection(
        receiver: BridgeReceiver, location: BridgeDocumentLocation,
        memberWorktreeID: UUID?, memberRelativePath: String?,
        record: BridgeNavigationRecord, topology: BridgeReceiverTopologySnapshot
    ) -> BridgeNavigationRecord? {
        let provenance: BridgeKnownWorktreeProvenance?
        if let memberWorktreeID {
            guard let memberRelativePath, record.containsMember(memberWorktreeID),
                let worktree = topology.knownWorktree(memberWorktreeID)
            else { return nil }
            provenance = BridgeKnownWorktreeProvenance(
                repoId: worktree.repoId, worktreeId: memberWorktreeID,
                relativePath: memberRelativePath)
        } else {
            guard memberRelativePath == nil else { return nil }
            provenance = nil
        }
        let entry = prepareOpenedDocumentEntry(
            receiver: receiver, location: location,
            currentEntries: record.openedDocuments, provenance: provenance,
            openedLine: nil)
        return BridgeNavigationRules.recordingDisplayedFilesSelection(
            entry, at: location, in: record)
    }
}

private enum BridgeAgentShowFileResolver {
    @concurrent nonisolated static func resolve(
        root: URL, relativePath: String
    ) async -> BridgeDocumentLocation? {
        let canonicalRoot = DarwinFSEventPathCanonicalizer.canonicalURL(root)
        let canonicalFile = DarwinFSEventPathCanonicalizer.canonicalURL(
            canonicalRoot.appendingPathComponent(relativePath, isDirectory: false))
        guard let location = BridgeDocumentLocation(canonicalPath: canonicalFile.path),
            location.isContained(inCanonicalRoot: canonicalRoot.path),
            let attributes = try? FileManager.default.attributesOfItem(atPath: canonicalFile.path),
            attributes[.type] as? FileAttributeType == .typeRegular
        else { return nil }
        return location
    }
}
