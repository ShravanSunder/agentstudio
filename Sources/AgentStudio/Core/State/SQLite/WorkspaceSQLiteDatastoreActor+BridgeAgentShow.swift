import Foundation

extension WorkspaceSQLiteDatastoreActor {
    package func prepareAgentShow(
        workspaceID: UUID, receiver: BridgeReceiver, target: BridgeAgentShowTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot
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
        let committed = try repository.readBridgeReceivers().records[receiver]
        let provenance: BridgeKnownWorktreeProvenance? =
            committed?.committedMemberWorktreeIds.contains(target.worktree) == true
            ? .init(
                repoId: worktree.repoId, worktreeId: target.worktree,
                relativePath: target.relativePath)
            : nil
        return .prepared(.init(location: location, provenance: provenance, openedLine: target.line))
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
