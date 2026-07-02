import Foundation

struct BridgeReviewProtocolSnapshotBuildRequest: Equatable, Sendable {
    let paneId: String
    let sourceIdentity: String
    let streamId: String
    let sequence: Int
    let package: BridgeReviewPackage
    let selectedItemId: String?
    let visibleItemIds: [String]
    let changesetCluster: BridgeReviewChangesetClusterMetadata?

    init(
        paneId: String,
        sourceIdentity: String,
        streamId: String,
        sequence: Int,
        package: BridgeReviewPackage,
        selectedItemId: String? = nil,
        visibleItemIds: [String]? = nil,
        changesetCluster: BridgeReviewChangesetClusterMetadata?
    ) {
        self.paneId = paneId
        self.sourceIdentity = sourceIdentity
        self.streamId = streamId
        self.sequence = sequence
        self.package = package
        self.selectedItemId = selectedItemId ?? package.orderedItemIds.first
        self.visibleItemIds = visibleItemIds ?? package.orderedItemIds
        self.changesetCluster = changesetCluster
    }
}

struct BridgeReviewProtocolDeltaBuildRequest: Equatable, Sendable {
    let paneId: String
    let sourceIdentity: String
    let streamId: String
    let sequence: Int
    let fromRevision: Int
    let toRevision: Int
    let package: BridgeReviewPackage
    var operations = BridgeReviewDelta.Operations()
}

struct BridgeReviewProtocolMetadataWindowBuildRequest: Equatable, Sendable {
    let paneId: String
    let sourceIdentity: String
    let streamId: String
    let sequence: Int
    let package: BridgeReviewPackage
    let itemIds: [String]
    var loadedBy: BridgeReviewMetadataLoadedBy = .idle
    var lane: BridgeDemandLane = .idle
}

struct BridgeReviewProtocolResetBuildRequest: Equatable, Sendable {
    let sourceIdentity: String
    let streamId: String
    let generation: Int
    let sequence: Int
    let reason: String
}

struct BridgeReviewProtocolInvalidationBuildRequest: Equatable, Sendable {
    let streamId: String
    let generation: Int
    let sequence: Int
    let scope: String
    let itemIds: [String]?
    let pathHints: [String]?
    let reason: String
}

enum BridgeReviewProtocolFrameBuilderError: Error, Equatable, Sendable {
    case invalidContentResourceUrl(String)
    case contentResourceIdMismatch(handleId: String, resourceId: String)
}

enum BridgeReviewProtocolFrameBuilder {
    static func snapshot(
        request: BridgeReviewProtocolSnapshotBuildRequest
    ) throws -> BridgeReviewSnapshotFrame {
        let reviewItems = metadataItemsForSnapshot(request: request)
        let contentDescriptors = try contentDescriptors(
            for: reviewItems,
            paneId: request.paneId,
            sourceIdentity: request.sourceIdentity,
            streamId: request.streamId,
            package: request.package
        )
        let itemMetadata = reviewItems.map {
            projectionInputItem(for: $0, loadedBy: .startupWindow, lane: .foreground)
        }

        return BridgeReviewSnapshotFrame(
            streamId: request.streamId,
            generation: request.package.reviewGeneration.rawValue,
            sequence: request.sequence,
            comparison: BridgeReviewComparisonIdentity(
                packageId: request.package.packageId,
                sourceIdentity: request.sourceIdentity,
                generation: request.package.reviewGeneration.rawValue,
                revision: request.package.revision,
                baseEndpoint: request.package.baseEndpoint,
                headEndpoint: request.package.headEndpoint,
                contentDescriptors: contentDescriptors,
                changesetCluster: request.changesetCluster
            ),
            selectedItemId: request.selectedItemId,
            visibleItemIds: request.visibleItemIds,
            itemMetadata: itemMetadata,
            treeRows: treeRowsMetadata(for: reviewItems, loadedBy: .startupWindow, lane: .foreground),
            extentFacts: reviewItems.flatMap { extentFacts(for: $0) },
            summary: request.package.summary
        )
    }

    static func metadataWindow(
        request: BridgeReviewProtocolMetadataWindowBuildRequest
    ) throws -> BridgeReviewMetadataWindowFrame {
        let reviewItems = metadataItems(itemIds: request.itemIds, package: request.package)
        let contentDescriptors = try contentDescriptors(
            for: reviewItems,
            paneId: request.paneId,
            sourceIdentity: request.sourceIdentity,
            streamId: request.streamId,
            package: request.package
        )

        return BridgeReviewMetadataWindowFrame(
            streamId: request.streamId,
            generation: request.package.reviewGeneration.rawValue,
            sequence: request.sequence,
            packageId: request.package.packageId,
            revision: request.package.revision,
            itemMetadata: reviewItems.map {
                projectionInputItem(for: $0, loadedBy: request.loadedBy, lane: request.lane)
            },
            treeRows: treeRowsMetadata(for: reviewItems, loadedBy: request.loadedBy, lane: request.lane),
            extentFacts: reviewItems.flatMap { extentFacts(for: $0) },
            summary: request.package.summary,
            contentDescriptors: contentDescriptors
        )
    }

    private static func metadataItemsForSnapshot(
        request: BridgeReviewProtocolSnapshotBuildRequest
    ) -> [BridgeReviewItemDescriptor] {
        var includedItemIds = Set(request.visibleItemIds)
        if let selectedItemId = request.selectedItemId,
            request.package.itemsById[selectedItemId] != nil
        {
            includedItemIds.insert(selectedItemId)
        }
        return request.package.orderedItemIds.compactMap { itemId in
            guard includedItemIds.contains(itemId) else {
                return nil
            }
            return request.package.itemsById[itemId]
        }
    }

    private static func metadataItems(
        itemIds: [String],
        package: BridgeReviewPackage
    ) -> [BridgeReviewItemDescriptor] {
        let includedItemIds: Set<String> = Set(itemIds)
        return package.orderedItemIds.compactMap { itemId -> BridgeReviewItemDescriptor? in
            guard includedItemIds.contains(itemId) else { return nil }
            return package.itemsById[itemId]
        }
    }

    static func delta(
        request: BridgeReviewProtocolDeltaBuildRequest
    ) throws -> BridgeReviewDeltaFrame {
        let deltaItems = deltaMetadataItems(
            operations: request.operations,
            package: request.package
        )
        let contentDescriptors = try contentDescriptors(
            for: deltaItems,
            paneId: request.paneId,
            sourceIdentity: request.sourceIdentity,
            streamId: request.streamId,
            package: request.package
        )

        return BridgeReviewDeltaFrame(
            streamId: request.streamId,
            generation: request.package.reviewGeneration.rawValue,
            sequence: request.sequence,
            packageId: request.package.packageId,
            fromRevision: request.fromRevision,
            toRevision: request.toRevision,
            operations: metadataOperations(
                operations: request.operations,
                package: request.package
            ),
            summary: request.package.summary,
            contentDescriptors: contentDescriptors
        )
    }

    private static func contentDescriptors(
        for reviewItems: [BridgeReviewItemDescriptor],
        paneId: String,
        sourceIdentity: String,
        streamId: String,
        package: BridgeReviewPackage
    ) throws -> [BridgeAttachedResourceDescriptor] {
        try reviewItems
            .flatMap(\.contentRoles.allHandles)
            .sorted { left, right in left.handleId < right.handleId }
            .map { handle in
                try contentDescriptor(
                    handle: handle,
                    paneId: paneId,
                    sourceIdentity: sourceIdentity,
                    streamId: streamId,
                    package: package
                )
            }
    }

    static func reset(request: BridgeReviewProtocolResetBuildRequest) -> BridgeReviewResetFrame {
        BridgeReviewResetFrame(
            streamId: request.streamId,
            generation: request.generation,
            sequence: request.sequence,
            reason: request.reason,
            sourceIdentity: request.sourceIdentity
        )
    }

    static func invalidation(
        request: BridgeReviewProtocolInvalidationBuildRequest
    ) -> BridgeReviewInvalidationFrame {
        BridgeReviewInvalidationFrame(
            streamId: request.streamId,
            generation: request.generation,
            sequence: request.sequence,
            invalidation: BridgeReviewInvalidationFrame.Invalidation(
                scope: request.scope,
                itemIds: request.itemIds,
                pathHints: request.pathHints,
                reason: request.reason
            )
        )
    }

    private static func contentDescriptor(
        handle: BridgeContentHandle,
        paneId: String,
        sourceIdentity: String,
        streamId: String,
        package: BridgeReviewPackage
    ) throws -> BridgeAttachedResourceDescriptor {
        guard
            let resource = BridgeTransportResourceURL.parse(
                handle.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewContentResourceKinds
            )
        else {
            throw BridgeReviewProtocolFrameBuilderError.invalidContentResourceUrl(handle.resourceUrl)
        }
        guard resource.opaqueId == handle.handleId else {
            throw BridgeReviewProtocolFrameBuilderError.contentResourceIdMismatch(
                handleId: handle.handleId,
                resourceId: resource.opaqueId
            )
        }
        let identity = BridgeResourceIdentity(
            paneId: paneId,
            protocolId: "review",
            sourceId: sourceIdentity,
            packageId: package.packageId,
            generation: handle.reviewGeneration.rawValue,
            revision: resource.revision,
            streamId: streamId,
            cursor: resource.cursor
        )
        let descriptor = BridgeResourceDescriptor(
            descriptorId: resource.opaqueId,
            protocolId: "review",
            resourceKind: "content",
            resourceUrl: resource.canonicalURL,
            identity: identity,
            content: BridgeResourceContentDescriptor(
                mediaType: handle.mimeType,
                encoding: handle.isBinary ? .binary : .utf8,
                expectedBytes: handle.sizeBytesIsExact ? handle.sizeBytes : nil,
                maxBytes: handle.sizeBytesIsExact
                    ? max(handle.sizeBytes, 1)
                    : AppPolicies.Bridge.contentMaxBytesPerItem,
                integrity: contentIntegrityDescriptor(for: handle)
            ),
            window: nil
        )
        return attachedDescriptor(refIdentity: identity, descriptor: descriptor)
    }

    private static func contentIntegrityDescriptor(
        for handle: BridgeContentHandle
    ) -> BridgeIntegrityDescriptor? {
        guard handle.contentHashAlgorithm == "sha256", !handle.contentHash.isEmpty else {
            return nil
        }
        return BridgeIntegrityDescriptor(
            kind: .wholeHash,
            algorithm: "sha256",
            value: handle.contentHash,
            manifestResourceId: nil
        )
    }

    private static func attachedDescriptor(
        refIdentity: BridgeResourceIdentity,
        descriptor: BridgeResourceDescriptor
    ) -> BridgeAttachedResourceDescriptor {
        BridgeAttachedResourceDescriptor(
            ref: BridgeDescriptorRef(
                descriptorId: descriptor.descriptorId,
                expectedProtocol: descriptor.protocolId,
                expectedResourceKind: descriptor.resourceKind,
                expectedIdentity: refIdentity
            ),
            descriptor: descriptor
        )
    }

    private static func treeRowsMetadata(
        for items: [BridgeReviewItemDescriptor],
        loadedBy: BridgeReviewMetadataLoadedBy,
        lane: BridgeDemandLane
    ) -> [BridgeReviewTreeRowMetadata] {
        var rows: [BridgeReviewTreeRowMetadata] = []
        var seenRowIds: Set<String> = []
        func appendRow(_ row: BridgeReviewTreeRowMetadata) {
            guard !seenRowIds.contains(row.rowId) else { return }
            seenRowIds.insert(row.rowId)
            rows.append(row)
        }
        for item in items {
            appendAncestorTreeRows(for: path(for: item), loadedBy: loadedBy, lane: lane, appendRow: appendRow)
            appendRow(treeRowMetadata(for: item, loadedBy: loadedBy, lane: lane))
        }
        return rows
    }

    private static func appendAncestorTreeRows(
        for path: String,
        loadedBy: BridgeReviewMetadataLoadedBy,
        lane: BridgeDemandLane,
        appendRow: (BridgeReviewTreeRowMetadata) -> Void
    ) {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }
        for componentCount in 1..<components.count {
            let ancestorPath = components.prefix(componentCount).joined(separator: "/")
            appendRow(directoryTreeRowMetadata(path: ancestorPath, loadedBy: loadedBy, lane: lane))
        }
    }

    private static func directoryTreeRowMetadata(
        path: String,
        loadedBy: BridgeReviewMetadataLoadedBy,
        lane: BridgeDemandLane
    ) -> BridgeReviewTreeRowMetadata {
        BridgeReviewTreeRowMetadata(
            rowId: "review-directory:\(path)",
            itemId: nil,
            path: path,
            depth: max(path.split(separator: "/").count - 1, 0),
            isDirectory: true,
            loadedBy: loadedBy,
            lane: lane
        )
    }

    private static func treeRowMetadata(
        for item: BridgeReviewItemDescriptor,
        loadedBy: BridgeReviewMetadataLoadedBy,
        lane: BridgeDemandLane
    ) -> BridgeReviewTreeRowMetadata {
        let path = path(for: item)
        return BridgeReviewTreeRowMetadata(
            rowId: "review-row:\(item.itemId)",
            itemId: item.itemId,
            path: path,
            depth: max(path.split(separator: "/").count - 1, 0),
            isDirectory: false,
            loadedBy: loadedBy,
            lane: lane
        )
    }

    private static func path(for item: BridgeReviewItemDescriptor) -> String {
        item.headPath ?? item.basePath ?? item.itemId
    }

    private static func extentFacts(for item: BridgeReviewItemDescriptor) -> [BridgeReviewExtentFact] {
        item.contentRoles.allHandles.map { handle in
            BridgeReviewExtentFact(
                itemId: item.itemId,
                contentRole: handle.role.rawValue,
                lineCount: lineCount(for: item, contentRole: handle.role)
            )
        }
    }

    private static func lineCount(
        for item: BridgeReviewItemDescriptor,
        contentRole: BridgeContentHandle.Role
    ) -> Int {
        switch contentRole {
        case .base:
            max(item.deletions, 1)
        case .head, .file:
            max(item.additions, 1)
        case .diff:
            max(item.additions + item.deletions, 1)
        }
    }

    private static func projectionInputItem(
        for item: BridgeReviewItemDescriptor,
        loadedBy: BridgeReviewMetadataLoadedBy,
        lane: BridgeDemandLane
    ) -> BridgeReviewProjectionInputItem {
        BridgeReviewProjectionInputItem(
            itemId: item.itemId,
            basePath: item.basePath,
            headPath: item.headPath,
            changeKind: item.changeKind.rawValue,
            fileClass: item.fileClass.rawValue,
            language: item.language,
            extension: item.extension,
            isHiddenByDefault: item.isHiddenByDefault,
            reviewPriority: item.reviewPriority.rawValue,
            reviewState: item.reviewState.rawValue,
            contentRoles: contentRoleNames(for: item),
            contentDescriptorIdsByRole: BridgeReviewProjectionContentDescriptorIdsByRole(
                base: item.contentRoles.base?.handleId,
                head: item.contentRoles.head?.handleId,
                diff: item.contentRoles.diff?.handleId,
                file: item.contentRoles.file?.handleId
            ),
            mimeTypes: mimeTypes(for: item),
            provenance: BridgeReviewProjectionItemProvenance(
                promptIds: item.provenance.promptIds,
                agentSessionIds: item.provenance.agentSessionIds,
                operationIds: item.provenance.operationIds
            ),
            loadedBy: loadedBy,
            lane: lane
        )
    }

    private static func contentRoleNames(for item: BridgeReviewItemDescriptor) -> [String] {
        [
            item.contentRoles.base?.role.rawValue,
            item.contentRoles.head?.role.rawValue,
            item.contentRoles.diff?.role.rawValue,
            item.contentRoles.file?.role.rawValue,
        ].compactMap { $0 }
    }

    private static func mimeTypes(for item: BridgeReviewItemDescriptor) -> [String] {
        Array(Set(item.contentRoles.allHandles.map(\.mimeType))).sorted()
    }

    private static func deltaMetadataItems(
        operations: BridgeReviewDelta.Operations,
        package: BridgeReviewPackage
    ) -> [BridgeReviewItemDescriptor] {
        let itemIds = Set(
            operations.addItems.map(\.itemId) + operations.updateItems.map(\.itemId)
        )
        return package.orderedItemIds.compactMap { itemId in
            guard itemIds.contains(itemId) else { return nil }
            return package.itemsById[itemId]
        }
    }

    private static func metadataOperations(
        operations: BridgeReviewDelta.Operations,
        package: BridgeReviewPackage
    ) -> [BridgeReviewMetadataOperation] {
        var metadataOperations: [BridgeReviewMetadataOperation] = []
        if !operations.addItems.isEmpty {
            metadataOperations.append(
                .appendItems(operations.addItems.map { projectionInputItem(for: $0, loadedBy: .delta, lane: .active) }))
            metadataOperations.append(
                .upsertTreeRows(treeRowsMetadata(for: operations.addItems, loadedBy: .delta, lane: .active)))
            metadataOperations.append(.upsertExtentFacts(operations.addItems.flatMap { extentFacts(for: $0) }))
        }
        for item in operations.updateItems {
            metadataOperations.append(
                .upsertItemMetadata(projectionInputItem(for: item, loadedBy: .delta, lane: .active)))
            metadataOperations.append(.upsertTreeRows(treeRowsMetadata(for: [item], loadedBy: .delta, lane: .active)))
            metadataOperations.append(.upsertExtentFacts(extentFacts(for: item)))
        }
        if !operations.removeItems.isEmpty {
            metadataOperations.append(.removeItems(operations.removeItems))
            metadataOperations.append(
                .removeTreeRows(rowIds: operations.removeItems.map { "review-row:\($0)" }, paths: nil))
        }
        if !operations.moveItems.isEmpty {
            metadataOperations.append(.replaceItemOrder(operations.moveItems))
        } else if !operations.addItems.isEmpty || !operations.removeItems.isEmpty {
            metadataOperations.append(.replaceItemOrder(package.orderedItemIds))
        }
        if !operations.invalidateContent.isEmpty {
            metadataOperations.append(.invalidateContentDescriptors(operations.invalidateContent))
        }
        return metadataOperations
    }
}
