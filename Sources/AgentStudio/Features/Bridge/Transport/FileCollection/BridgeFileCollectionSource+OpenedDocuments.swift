import AgentStudioCore
import Foundation

extension BridgeFileCollectionSource {
    func emitOpenedDocumentRows(
        _ entries: [BridgeFileCollectionLayout.OpenedDocumentEntry],
        subscriptionId: String
    ) async throws {
        guard !entries.isEmpty, let context = contextBySubscriptionId[subscriptionId] else { return }
        var rows: [BridgeProductFileTreeRow] = []
        if context.emittedPathsBySource[.openedDocuments]?.contains(
            BridgeFileCollectionLayout.openedDocumentsGroupPath
        ) != true {
            rows.append(
                try BridgeFileCollectionRows.groupRow(
                    path: BridgeFileCollectionLayout.openedDocumentsGroupPath,
                    identityPrefix: BridgeFileCollectionRows.openedDocumentsGroupIdentityPrefix
                )
            )
        }
        for entry in entries {
            rows.append(
                try BridgeFileCollectionRows.openedDocumentRow(
                    entry,
                    metadata: await openedDocumentRowReader(entry.location)
                )
            )
        }
        try await emitCollectionRows(
            rows,
            from: .openedDocuments,
            subscriptionId: subscriptionId,
            expectedSource: context.productSource
        )
    }

    /// Issue a descriptor for each demanded opened document. The document's own
    /// parent directory is the read root and its name the only readable path, so
    /// the descriptor authorizes that exact file and nothing beside it.
    func publishDemandedOpenedDocumentDescriptors(subscriptionId: String) async throws {
        guard let context = contextBySubscriptionId[subscriptionId] else { return }
        let revision = context.subscription.interestRevision
        let demandedPaths = BridgePaneProductFileMetadataEncoding.highestPriorityLaneByPath(
            context.subscription.interestState.fileMetadataState?.interests ?? []
        )
        let entries = layout.openedDocuments.filter { entry in
            demandedPaths[entry.displayPath] != nil
                && context.openedDocumentInterestRevisionByPath[entry.displayPath] != revision
        }
        for entry in entries {
            try Task.checkCancellation()
            guard var current = contextBySubscriptionId[subscriptionId],
                current.productSource == context.productSource
            else { return }
            current.openedDocumentInterestRevisionByPath[entry.displayPath] = revision
            contextBySubscriptionId[subscriptionId] = current
            let payload = try await openedDocumentPayload(entry, source: context.productSource)
            guard var latest = contextBySubscriptionId[subscriptionId],
                latest.productSource == context.productSource,
                layout.openedDocument(at: entry.displayPath)?.location == entry.location
            else { return }
            if case .available(let descriptor) = payload.availability {
                latest.issuedDescriptorsById[descriptor.descriptorId] = .init(
                    collectionDescriptor: descriptor,
                    displayPath: entry.displayPath,
                    origin: .openedDocument(entry.location)
                )
                contextBySubscriptionId[subscriptionId] = latest
            }
            try await latest.emit(.descriptorReady(.init(payload: payload)))
        }
    }

    private func openedDocumentPayload(
        _ entry: BridgeFileCollectionLayout.OpenedDocumentEntry,
        source: BridgeProductFileSourceIdentity
    ) async throws -> BridgeProductFileDescriptorReadyPayload {
        let fileId = BridgeFileCollectionRows.openedDocumentFileId(entry)
        let rowId = "\(entry.identityPrefix)row"
        let metadata = await openedDocumentRowReader(entry.location)
        let materialized = try await descriptorMaterializer(
            .init(
                relativePath: entry.location.displayName,
                rootURL: entry.location.fileURL.deletingLastPathComponent(),
                row: BridgeWorktreeTreeRowMetadata(
                    rowId: rowId,
                    path: entry.location.displayName,
                    name: entry.location.displayName,
                    parentPath: nil,
                    depth: 0,
                    isDirectory: false,
                    fileId: fileId,
                    fileClass: metadata?.fileClass,
                    sizeBytes: metadata?.sizeBytes,
                    lineCount: metadata?.lineCount,
                    changeStatus: nil
                ),
                source: source
            )
        )
        let availability: BridgeProductFileDescriptorAvailability =
            switch materialized.payload.availability {
            case .available(let descriptor):
                .available(
                    try BridgeProductFileContentDescriptor(
                        declaredByteLength: descriptor.declaredByteLength,
                        descriptorId: BridgeFileCollectionLayout.namespacedIdentifier(
                            prefix: entry.identityPrefix,
                            identifier: descriptor.descriptorId
                        ),
                        expectedSha256: descriptor.expectedSha256,
                        fileId: fileId,
                        maximumBytes: descriptor.maximumBytes,
                        source: source,
                        window: descriptor.window
                    )
                )
            case .binary: .binary
            case .unavailable(let reason): .unavailable(reason)
            }
        return try materialized.payload.replacingCollectionIdentity(
            availability: availability,
            fileId: fileId,
            path: entry.displayPath,
            rowId: rowId,
            source: source
        )
    }
}
