import AgentStudioCore
import Foundation

extension BridgeFileCollectionSource {
    /// Replace the collection's members and opened documents in place.
    ///
    /// Open subscriptions receive only the difference as tree deltas: a removed
    /// source's rows and descriptors go away, an added source's rows arrive, and
    /// every other row, key, selection and descriptor is untouched (R16). The
    /// worker's WebView and active editor are never recreated here.
    func applyMembership(
        members: [BridgeFileCollectionMemberSource],
        openedDocuments: [BridgeDocumentLocation]
    ) async throws {
        let previousIds = Set(layout.memberGroups.map(\.worktreeId))
        let nextIds = Set(members.map(\.member.worktreeId))
        let removedSources = previousIds.subtracting(nextIds).compactMap { memberSourcesById[$0] }
        let previousDocuments = Set(layout.openedDocuments.map(\.location))
        for member in members { memberSourcesById[member.member.worktreeId] = member }
        openedDocumentLocations = openedDocuments
        layout = layout.updating(members: members.map(\.member), openedDocuments: openedDocuments)
        let addedIds = layout.memberGroups.map(\.worktreeId).filter { !previousIds.contains($0) }
        let addedDocuments = layout.openedDocuments.filter { !previousDocuments.contains($0.location) }
        let retainedDocuments = Set(layout.openedDocuments.map(\.location))

        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            for removedSource in removedSources {
                try await removeMember(removedSource, subscriptionId: subscriptionId)
            }
            try await removeRowsNowOwnedByNestedMembers(subscriptionId: subscriptionId)
            try await removeOpenedDocuments(
                previousDocuments.subtracting(retainedDocuments),
                subscriptionId: subscriptionId
            )
            for worktreeId in addedIds {
                try await openMember(worktreeId, subscriptionId: subscriptionId)
                try await updateMember(worktreeId, subscriptionId: subscriptionId)
            }
            try await emitOpenedDocumentRows(addedDocuments, subscriptionId: subscriptionId)
        }
        for removedSource in removedSources {
            memberSourcesById.removeValue(forKey: removedSource.member.worktreeId)
        }
    }

    private func removeMember(
        _ memberSource: BridgeFileCollectionMemberSource,
        subscriptionId: String
    ) async throws {
        let worktreeId = memberSource.member.worktreeId
        guard var context = contextBySubscriptionId[subscriptionId],
            context.openedMemberIds.contains(worktreeId)
        else { return }
        await memberSource.producer.cancel(subscriptionId: subscriptionId)
        context.openedMemberIds.remove(worktreeId)
        context.memberAvailability.removeValue(forKey: worktreeId)
        let removedPaths = context.emittedPathsBySource.removeValue(forKey: .member(worktreeId)) ?? []
        let revokedDescriptors = context.issuedDescriptorsById.values.filter {
            if case .member(worktreeId, _) = $0.origin { return true }
            return false
        }
        for revoked in revokedDescriptors {
            context.issuedDescriptorsById.removeValue(forKey: revoked.collectionDescriptor.descriptorId)
        }
        contextBySubscriptionId[subscriptionId] = context
        try await emitRemoval(
            paths: removedPaths,
            revokedDescriptors: revokedDescriptors,
            context: context
        )
    }

    /// A newly added member nested inside an existing one takes over its
    /// subtree; the outer member's copies of those rows leave the tree.
    private func removeRowsNowOwnedByNestedMembers(subscriptionId: String) async throws {
        guard var context = contextBySubscriptionId[subscriptionId] else { return }
        var removedPaths: Set<String> = []
        for group in layout.memberGroups {
            let emitted = context.emittedPathsBySource[.member(group.worktreeId)] ?? []
            let nowNested = emitted.filter { path in
                guard path.hasPrefix(group.groupPath + "/") else { return false }
                return group.belongsToNestedMember(String(path.dropFirst(group.groupPath.count + 1)))
            }
            guard !nowNested.isEmpty else { continue }
            context.emittedPathsBySource[.member(group.worktreeId)] = emitted.subtracting(nowNested)
            removedPaths.formUnion(nowNested)
        }
        guard !removedPaths.isEmpty else { return }
        contextBySubscriptionId[subscriptionId] = context
        try await emitRemoval(paths: removedPaths, revokedDescriptors: [], context: context)
    }

    private func removeOpenedDocuments(
        _ locations: Set<BridgeDocumentLocation>,
        subscriptionId: String
    ) async throws {
        guard !locations.isEmpty, var context = contextBySubscriptionId[subscriptionId] else { return }
        let revokedDescriptors = context.issuedDescriptorsById.values.filter {
            if case .openedDocument(let location) = $0.origin { return locations.contains(location) }
            return false
        }
        for revoked in revokedDescriptors {
            context.issuedDescriptorsById.removeValue(forKey: revoked.collectionDescriptor.descriptorId)
        }
        let retainedPaths = Set(layout.openedDocuments.map(\.displayPath))
        let emitted = context.emittedPathsBySource[.openedDocuments] ?? []
        var removedPaths = emitted.filter {
            $0 != BridgeFileCollectionLayout.openedDocumentsGroupPath && !retainedPaths.contains($0)
        }
        if retainedPaths.isEmpty { removedPaths.insert(BridgeFileCollectionLayout.openedDocumentsGroupPath) }
        context.emittedPathsBySource[.openedDocuments] = emitted.subtracting(removedPaths)
        for path in removedPaths { context.openedDocumentInterestRevisionByPath.removeValue(forKey: path) }
        contextBySubscriptionId[subscriptionId] = context
        try await emitRemoval(paths: removedPaths, revokedDescriptors: revokedDescriptors, context: context)
    }

    private func emitRemoval(
        paths: Set<String>,
        revokedDescriptors: [IssuedDescriptor],
        context: SubscriptionContext
    ) async throws {
        for revoked in revokedDescriptors.sorted(by: { $0.displayPath < $1.displayPath }) {
            try await context.emit(
                .invalidated(
                    try .init(
                        fileId: revoked.collectionDescriptor.fileId,
                        path: revoked.displayPath,
                        reason: .filesystemEvent,
                        replacementDescriptor: nil,
                        source: context.productSource
                    )
                )
            )
        }
        for chunk in Self.boundedRemovalPathChunks(paths.sorted()) {
            try await context.emit(
                .treeDelta(
                    try .init(
                        operations: [.removeRows(paths: chunk, rowIds: [])],
                        source: context.productSource
                    )
                )
            )
        }
    }

    static func boundedRemovalPathChunks(_ paths: [String]) -> [[String]] {
        var chunks: [[String]] = []
        var currentChunk: [String] = []
        var currentByteCount = 0
        let maximumPayloadByteCount = BridgeProductWireContract.maximumMetadataFrameBytes - 4096
        for path in paths {
            let byteCount = path.utf8.count + 8
            if !currentChunk.isEmpty,
                currentChunk.count == BridgeProductWireContract.maximumFileMetadataDeltaMemberCount
                    || currentByteCount + byteCount > maximumPayloadByteCount
            {
                chunks.append(currentChunk)
                currentChunk = []
                currentByteCount = 0
            }
            currentChunk.append(path)
            currentByteCount += byteCount
        }
        if !currentChunk.isEmpty { chunks.append(currentChunk) }
        return chunks
    }
}
