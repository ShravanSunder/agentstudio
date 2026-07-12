import Foundation

enum BridgePaneProductReviewMetadataSourceError: Error, Equatable {
    case integerOutOfRange
    case metadataEventExceedsByteLimit
    case unavailablePackage
    case unknownSubscription
}

typealias BridgePaneProductReviewMetadataEventSink =
    @Sendable (BridgeProductReviewMetadataEvent) async throws -> Void

protocol BridgePaneProductReviewMetadataProducing: Sendable {
    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws
    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws
    func cancel(subscriptionId: String) async
}

actor BridgeUnavailablePaneProductReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
    }

    func cancel(subscriptionId _: String) {}
}

actor BridgePaneProductReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private struct SubscriptionContext: Sendable {
        var package: BridgeReviewPackage
        var subscription: BridgeProductSubscriptionSnapshot
    }

    private static let maximumEncodedEventBytes =
        BridgeProductWireContract.maximumMetadataFrameBytes - 4096
    private static let preferredItemWindowCount = 64
    private static let preferredTreeWindowCount = 128

    private let currentPackage: @MainActor @Sendable () -> BridgeReviewPackage?
    private var contextBySubscriptionId: [String: SubscriptionContext] = [:]

    init(currentPackage: @escaping @MainActor @Sendable () -> BridgeReviewPackage?) {
        self.currentPackage = currentPackage
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        guard subscription.subscriptionKind == .reviewMetadata,
            case .reviewMetadata = subscription.interestState,
            let package = await currentPackage()
        else {
            throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
        }
        contextBySubscriptionId[subscription.subscriptionId] = .init(
            package: package,
            subscription: subscription
        )
        let events = [try Self.sourceAcceptedEvent(for: package)] + (try Self.windowEvents(for: package))
        try await emitIfCurrent(events, subscription: subscription, emit: emit)
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        guard let activeContext = contextBySubscriptionId[subscription.subscriptionId] else {
            throw BridgePaneProductReviewMetadataSourceError.unknownSubscription
        }
        guard subscription.subscriptionKind == .reviewMetadata,
            case .reviewMetadata = subscription.interestState,
            subscription.interestRevision >= activeContext.subscription.interestRevision,
            let package = await currentPackage()
        else {
            throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
        }
        contextBySubscriptionId[subscription.subscriptionId] = .init(
            package: package,
            subscription: subscription
        )
        guard package.revision != activeContext.package.revision else { return }

        let events: [BridgeProductReviewMetadataEvent]
        if Self.hasSameSourceIdentity(activeContext.package, package),
            Self.canApplyDelta(from: activeContext.package, to: package),
            let delta = try Self.deltaEvent(from: activeContext.package, to: package)
        {
            events = [.delta(delta)]
        } else {
            let identity = try Self.identity(for: package)
            events =
                [
                    .reset(.init(identity: identity, reason: .sourceChanged)),
                    try Self.sourceAcceptedEvent(for: package),
                ] + (try Self.windowEvents(for: package))
        }
        try await emitIfCurrent(events, subscription: subscription, emit: emit)
    }

    func cancel(subscriptionId: String) {
        contextBySubscriptionId.removeValue(forKey: subscriptionId)
    }

    private func emitIfCurrent(
        _ events: [BridgeProductReviewMetadataEvent],
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        for event in events {
            try Task.checkCancellation()
            guard let context = contextBySubscriptionId[subscription.subscriptionId],
                context.subscription.interestRevision == subscription.interestRevision
            else { return }
            try await emit(event)
        }
    }

    private static func sourceAcceptedEvent(
        for package: BridgeReviewPackage
    ) throws -> BridgeProductReviewMetadataEvent {
        .sourceAccepted(
            .init(
                identity: try identity(for: package)
            )
        )
    }

    fileprivate static func identity(
        for package: BridgeReviewPackage
    ) throws -> BridgeProductReviewMetadataIdentity {
        try .init(
            generation: package.reviewGeneration.rawValue,
            packageId: package.packageId,
            revision: package.revision,
            sourceIdentity: package.query.queryId
        )
    }

    private static func windowEvents(
        for package: BridgeReviewPackage
    ) throws -> [BridgeProductReviewMetadataEvent] {
        let projection = try ReviewPackageProjection(package: package)
        var events: [BridgeProductReviewMetadataEvent] = []
        var itemStartIndex = 0
        var treeStartIndex = 0
        var isSnapshot = true

        repeat {
            var itemCount = min(preferredItemWindowCount, projection.items.count - itemStartIndex)
            var treeCount = min(preferredTreeWindowCount, projection.treeRows.count - treeStartIndex)
            var event: BridgeProductReviewMetadataEvent
            while true {
                event = try projection.event(
                    isSnapshot: isSnapshot,
                    itemStartIndex: itemStartIndex,
                    itemCount: itemCount,
                    treeStartIndex: treeStartIndex,
                    treeCount: treeCount
                )
                if try encodedByteCount(event) <= maximumEncodedEventBytes { break }
                if itemCount >= treeCount, itemCount > 0 {
                    itemCount /= 2
                } else if treeCount > 0 {
                    treeCount /= 2
                } else {
                    throw BridgePaneProductReviewMetadataSourceError.metadataEventExceedsByteLimit
                }
            }
            guard itemCount > 0 || treeCount > 0 || (projection.items.isEmpty && projection.treeRows.isEmpty) else {
                throw BridgePaneProductReviewMetadataSourceError.metadataEventExceedsByteLimit
            }
            events.append(event)
            itemStartIndex += itemCount
            treeStartIndex += treeCount
            isSnapshot = false
        } while itemStartIndex < projection.items.count || treeStartIndex < projection.treeRows.count
        return events
    }

    private static func deltaEvent(
        from currentPackage: BridgeReviewPackage,
        to nextPackage: BridgeReviewPackage
    ) throws -> BridgeProductReviewDeltaEvent? {
        guard nextPackage.revision > currentPackage.revision else { return nil }
        let currentItems = currentPackage.itemsById
        let nextItems = nextPackage.itemsById
        let currentOrder = orderedItemIds(in: currentPackage)
        let nextOrder = orderedItemIds(in: nextPackage)
        let currentIds = Set(currentItems.keys)
        let nextIds = Set(nextItems.keys)
        let addedIds = nextOrder.filter { !currentIds.contains($0) }
        let removedIds = currentOrder.filter { !nextIds.contains($0) }
        let updatedIds = nextOrder.filter { itemId in
            guard let currentItem = currentItems[itemId], let nextItem = nextItems[itemId] else { return false }
            return currentItem != nextItem
        }
        let changedIds = addedIds + updatedIds
        let changedItems = changedIds.compactMap { nextItems[$0] }
        var operations: [BridgeProductReviewMetadataOperation] = try changedItems.map {
            .upsertItem(try productItem($0, loadedBy: .delta, lane: .active))
        }
        if !removedIds.isEmpty { operations.append(.removeItems(removedIds)) }
        if currentOrder != nextOrder { operations.append(.replaceItemOrder(nextOrder)) }

        let currentTreeRows = try productTreeRows(for: currentOrder.compactMap { currentItems[$0] }, loadedBy: .delta)
        let nextTreeRows = try productTreeRows(for: nextOrder.compactMap { nextItems[$0] }, loadedBy: .delta)
        if let treeSplice = treeSplice(from: currentTreeRows, to: nextTreeRows) {
            operations.append(treeSplice)
        }
        let extentFacts = try changedItems.flatMap(productExtentFacts)
        if !extentFacts.isEmpty { operations.append(.upsertExtentFacts(extentFacts)) }

        let previousDescriptorIds = (removedIds + updatedIds).flatMap { itemId in
            currentItems[itemId]?.contentRoles.allHandles.map(\.handleId) ?? []
        }
        let replacementDescriptorIds = updatedIds.flatMap { itemId in
            nextItems[itemId]?.contentRoles.allHandles.map(\.handleId) ?? []
        }
        let invalidatedDescriptorIds = Set(previousDescriptorIds + replacementDescriptorIds).sorted()
        if !invalidatedDescriptorIds.isEmpty {
            operations.append(.invalidateContentSources(invalidatedDescriptorIds))
        }
        let contentSources = try changedItems.flatMap { try productContentSources(for: $0, package: nextPackage) }
        guard isContractBoundedDelta(operations: operations, contentSources: contentSources) else { return nil }
        let event = try BridgeProductReviewDeltaEvent(
            identity: identity(for: nextPackage),
            contentSources: contentSources,
            fromRevision: currentPackage.revision,
            operations: operations,
            summary: try productSummary(nextPackage.summary),
            toRevision: nextPackage.revision
        )
        guard try encodedByteCount(.delta(event)) <= maximumEncodedEventBytes else { return nil }
        return event
    }

    private static func isContractBoundedDelta(
        operations: [BridgeProductReviewMetadataOperation],
        contentSources: [BridgeProductReviewContentSourceDescriptor]
    ) -> Bool {
        let maximumCount = BridgeProductReviewMetadataLimits.maximumWindowEntryCount
        guard operations.count <= maximumCount, contentSources.count <= maximumCount else { return false }
        return operations.allSatisfy { operation in
            switch operation {
            case .upsertItem:
                true
            case .removeItems(let itemIds), .replaceItemOrder(let itemIds):
                itemIds.count <= maximumCount
            case .spliceTreeRows(_, let deleteCount, let rows):
                deleteCount <= maximumCount && rows.count <= maximumCount
            case .upsertExtentFacts(let facts):
                facts.count <= maximumCount
            case .invalidateContentSources(let descriptorIds):
                descriptorIds.count <= maximumCount
            }
        }
    }

    private static func hasSameSourceIdentity(
        _ currentPackage: BridgeReviewPackage,
        _ nextPackage: BridgeReviewPackage
    ) -> Bool {
        currentPackage.packageId == nextPackage.packageId
            && currentPackage.reviewGeneration == nextPackage.reviewGeneration
            && currentPackage.query.queryId == nextPackage.query.queryId
    }

    private static func canApplyDelta(
        from currentPackage: BridgeReviewPackage,
        to nextPackage: BridgeReviewPackage
    ) -> Bool {
        nextPackage.revision > currentPackage.revision
            && currentPackage.query == nextPackage.query
            && currentPackage.baseEndpoint == nextPackage.baseEndpoint
            && currentPackage.headEndpoint == nextPackage.headEndpoint
    }

    fileprivate static func orderedItemIds(in package: BridgeReviewPackage) -> [String] {
        var seen = Set<String>()
        var itemIds = package.orderedItemIds.filter { package.itemsById[$0] != nil && seen.insert($0).inserted }
        itemIds.append(contentsOf: package.itemsById.keys.sorted().filter { seen.insert($0).inserted })
        return itemIds
    }

    private static func treeSplice(
        from currentRows: [BridgeProductReviewTreeRowValue],
        to nextRows: [BridgeProductReviewTreeRowValue]
    ) -> BridgeProductReviewMetadataOperation? {
        guard currentRows != nextRows else { return nil }
        var prefixCount = 0
        while prefixCount < min(currentRows.count, nextRows.count),
            currentRows[prefixCount] == nextRows[prefixCount]
        {
            prefixCount += 1
        }
        var suffixCount = 0
        while suffixCount < currentRows.count - prefixCount,
            suffixCount < nextRows.count - prefixCount,
            currentRows[currentRows.count - suffixCount - 1] == nextRows[nextRows.count - suffixCount - 1]
        {
            suffixCount += 1
        }
        return .spliceTreeRows(
            startIndex: prefixCount,
            deleteCount: currentRows.count - prefixCount - suffixCount,
            rows: Array(nextRows[prefixCount..<(nextRows.count - suffixCount)])
        )
    }

    private static func encodedByteCount(_ event: BridgeProductReviewMetadataEvent) throws -> Int {
        try JSONEncoder().encode(event).count
    }
}

private struct ReviewPackageProjection {
    let baseEndpoint: BridgeProductReviewSourceEndpointValue
    let headEndpoint: BridgeProductReviewSourceEndpointValue
    let identity: BridgeProductReviewMetadataIdentity
    let items: [ReviewProjectedItem]
    let query: BridgeProductReviewQueryValue
    let summary: BridgeProductReviewPackageSummaryValue
    let treeRows: [BridgeProductReviewTreeRowValue]

    init(package: BridgeReviewPackage) throws {
        let itemIds = BridgePaneProductReviewMetadataSource.orderedItemIds(in: package)
        let reviewItems = itemIds.compactMap { package.itemsById[$0] }
        self.baseEndpoint = try productEndpoint(package.baseEndpoint)
        self.headEndpoint = try productEndpoint(package.headEndpoint)
        self.identity = try BridgePaneProductReviewMetadataSource.identity(for: package)
        self.items = try reviewItems.map { try ReviewProjectedItem(item: $0, package: package) }
        self.query = try productQuery(package.query)
        self.summary = try productSummary(package.summary)
        self.treeRows = try productTreeRows(for: reviewItems, loadedBy: .startupWindow)
    }

    func event(
        isSnapshot: Bool,
        itemStartIndex: Int,
        itemCount: Int,
        treeStartIndex: Int,
        treeCount: Int
    ) throws -> BridgeProductReviewMetadataEvent {
        let itemSlice = Array(items[itemStartIndex..<(itemStartIndex + itemCount)])
        let treeSlice = Array(treeRows[treeStartIndex..<(treeStartIndex + treeCount)])
        let itemWindow = try BridgeProductReviewItemWindow(
            finalWindow: itemStartIndex + itemCount == items.count,
            itemCount: itemCount,
            startIndex: itemStartIndex,
            totalItemCount: items.count
        )
        let treeWindow = try BridgeProductReviewTreeWindow(
            finalWindow: treeStartIndex + treeCount == treeRows.count,
            rowCount: treeCount,
            startIndex: treeStartIndex,
            totalRowCount: treeRows.count
        )
        if isSnapshot {
            return .snapshot(
                try .init(
                    identity: identity,
                    baseEndpoint: baseEndpoint,
                    contentSources: itemSlice.flatMap(\.contentSources),
                    extentFacts: itemSlice.flatMap(\.extentFacts),
                    headEndpoint: headEndpoint,
                    itemMetadata: itemSlice.map(\.metadata),
                    itemWindow: itemWindow,
                    query: query,
                    summary: summary,
                    treeRows: treeSlice,
                    treeWindow: treeWindow
                )
            )
        }
        return .window(
            try .init(
                identity: identity,
                contentSources: itemSlice.flatMap(\.contentSources),
                extentFacts: itemSlice.flatMap(\.extentFacts),
                itemMetadata: itemSlice.map(\.metadata),
                itemWindow: itemWindow,
                summary: summary,
                treeRows: treeSlice,
                treeWindow: treeWindow
            )
        )
    }
}

private struct ReviewProjectedItem {
    let contentSources: [BridgeProductReviewContentSourceDescriptor]
    let extentFacts: [BridgeProductReviewExtentFactValue]
    let metadata: BridgeProductReviewItemMetadataValue

    init(item: BridgeReviewItemDescriptor, package: BridgeReviewPackage) throws {
        self.contentSources = try productContentSources(for: item, package: package)
        self.extentFacts = try productExtentFacts(item)
        self.metadata = try productItem(item, loadedBy: .startupWindow, lane: .foreground)
    }
}

private func productItem(
    _ item: BridgeReviewItemDescriptor,
    loadedBy: BridgeProductReviewMetadataLoadedBy,
    lane: BridgeProductDemandLane
) throws -> BridgeProductReviewItemMetadataValue {
    let roles = item.contentRoles
    return try .init(
        basePath: item.basePath,
        changeKind: item.changeKind,
        contentDescriptorIdsByRole: .init(
            base: roles.base?.handleId,
            diff: roles.diff?.handleId,
            file: roles.file?.handleId,
            head: roles.head?.handleId
        ),
        contentHashesByRole: .init(
            base: roles.base?.contentHash,
            diff: roles.diff?.contentHash,
            file: roles.file?.contentHash,
            head: roles.head?.contentHash
        ),
        contentRoles: roles.allHandles.map(\.role),
        fileExtension: item.extension,
        fileClass: item.fileClass,
        headPath: item.headPath,
        isHiddenByDefault: item.isHiddenByDefault,
        itemId: item.itemId,
        lane: lane,
        language: item.language,
        loadedBy: loadedBy,
        mimeTypes: Array(Set(roles.allHandles.map(\.mimeType))).sorted(),
        provenance: .init(
            agentSessionIds: item.provenance.agentSessionIds,
            operationIds: item.provenance.operationIds,
            promptIds: item.provenance.promptIds
        ),
        reviewPriority: item.reviewPriority,
        reviewState: item.reviewState
    )
}

private func productContentSources(
    for item: BridgeReviewItemDescriptor,
    package: BridgeReviewPackage
) throws -> [BridgeProductReviewContentSourceDescriptor] {
    try item.contentRoles.allHandles.map { handle in
        let digest: BridgeProductReviewContentDigest
        let unprefixedHash =
            handle.contentHash.hasPrefix("sha256:")
            ? String(handle.contentHash.dropFirst("sha256:".count))
            : handle.contentHash
        if handle.contentHashAlgorithm == "sha256",
            unprefixedHash.count == 64,
            unprefixedHash.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        {
            digest = .authoritativeSHA256(unprefixedHash)
        } else {
            digest = .provisional(algorithm: handle.contentHashAlgorithm, value: handle.contentHash)
        }
        return try .init(
            contentDigest: digest,
            descriptorId: handle.handleId,
            encoding: handle.isBinary ? nil : "utf-8",
            endpointId: handle.endpointId,
            handleId: handle.handleId,
            isBinary: handle.isBinary,
            itemId: handle.itemId,
            language: handle.language,
            mimeType: handle.mimeType,
            packageId: package.packageId,
            reviewGeneration: package.reviewGeneration.rawValue,
            role: handle.role,
            sourceIdentity: package.query.queryId,
            wholeByteLength: handle.sizeBytesIsExact ? handle.sizeBytes : nil
        )
    }
}

private func productExtentFacts(
    _ item: BridgeReviewItemDescriptor
) throws -> [BridgeProductReviewExtentFactValue] {
    try item.contentRoles.allHandles.map { handle in
        let lineCount: Int
        switch handle.role {
        case .base: lineCount = max(item.deletions, 1)
        case .head, .file: lineCount = max(item.additions, 1)
        case .diff: lineCount = max(item.additions + item.deletions, 1)
        }
        return try .init(contentRole: handle.role, itemId: item.itemId, lineCount: lineCount)
    }
}

private func productTreeRows(
    for items: [BridgeReviewItemDescriptor],
    loadedBy: BridgeProductReviewMetadataLoadedBy
) throws -> [BridgeProductReviewTreeRowValue] {
    var rows: [BridgeProductReviewTreeRowValue] = []
    var seenRowIds = Set<String>()
    for item in items {
        let path = item.headPath ?? item.basePath ?? item.itemId
        let components = path.split(separator: "/").map(String.init)
        if components.count > 1 {
            for componentCount in 1..<components.count {
                let ancestorPath = components.prefix(componentCount).joined(separator: "/")
                let rowId = BridgeProductReviewTreeRowIdentity.directoryRowId(path: ancestorPath)
                if seenRowIds.insert(rowId).inserted {
                    rows.append(
                        try .init(
                            depth: componentCount - 1,
                            isDirectory: true,
                            itemId: nil,
                            lane: .foreground,
                            loadedBy: loadedBy,
                            path: ancestorPath,
                            rowId: rowId
                        )
                    )
                }
            }
        }
        let rowId = BridgeProductReviewTreeRowIdentity.itemRowId(itemId: item.itemId)
        if seenRowIds.insert(rowId).inserted {
            rows.append(
                try .init(
                    depth: max(components.count - 1, 0),
                    isDirectory: false,
                    itemId: item.itemId,
                    lane: .foreground,
                    loadedBy: loadedBy,
                    path: path,
                    rowId: rowId
                )
            )
        }
    }
    return rows
}

private func productEndpoint(
    _ endpoint: BridgeSourceEndpoint
) throws -> BridgeProductReviewSourceEndpointValue {
    guard let createdAt = Int(exactly: endpoint.createdAtUnixMilliseconds) else {
        throw BridgePaneProductReviewMetadataSourceError.integerOutOfRange
    }
    return try .init(
        contentSetHash: endpoint.contentSetHash,
        createdAtUnixMilliseconds: createdAt,
        endpointId: endpoint.endpointId,
        kind: endpoint.kind,
        label: endpoint.label,
        providerIdentity: endpoint.providerIdentity,
        repoId: endpoint.repoId.uuidString,
        worktreeId: endpoint.worktreeId.uuidString
    )
}

private func productSummary(
    _ summary: BridgeReviewPackageSummary
) throws -> BridgeProductReviewPackageSummaryValue {
    try .init(
        additions: summary.additions,
        deletions: summary.deletions,
        filesChanged: summary.filesChanged,
        hiddenFileCount: summary.hiddenFileCount,
        visibleFileCount: summary.visibleFileCount
    )
}

private func productQuery(_ query: BridgeReviewQuery) throws -> BridgeProductReviewQueryValue {
    guard let createdAfter = query.provenanceFilter.createdAfterUnixMilliseconds.map(Int.init(exactly:)) ?? .some(nil),
        let createdBefore = query.provenanceFilter.createdBeforeUnixMilliseconds.map(Int.init(exactly:)) ?? .some(nil)
    else {
        throw BridgePaneProductReviewMetadataSourceError.integerOutOfRange
    }
    let filter = query.viewFilter
    return try .init(
        baseEndpointId: query.baseEndpointId,
        comparisonSemantics: query.comparisonSemantics,
        fileTarget: query.fileTarget,
        grouping: .init(kind: query.grouping.kind, label: query.grouping.label),
        headEndpointId: query.headEndpointId,
        pathScope: query.pathScope,
        provenanceFilter: .init(
            agentSessionIds: query.provenanceFilter.agentSessionIds,
            createdAfterUnixMilliseconds: createdAfter,
            createdBeforeUnixMilliseconds: createdBefore,
            operationIds: query.provenanceFilter.operationIds,
            paneIds: query.provenanceFilter.paneIds.map(\.uuidString),
            promptIds: query.provenanceFilter.promptIds,
            sourceKinds: query.provenanceFilter.sourceKinds.map(\.rawValue)
        ),
        queryId: query.queryId,
        queryKind: query.queryKind,
        repoId: query.repoId.uuidString,
        viewFilter: .init(
            changeKinds: filter.changeKinds,
            excludedExtensions: filter.excludedExtensions,
            excludedFileClasses: filter.excludedFileClasses,
            excludedPathGlobs: filter.excludedPathGlobs,
            includedExtensions: filter.includedExtensions,
            includedFileClasses: filter.includedFileClasses,
            includedPathGlobs: filter.includedPathGlobs,
            reviewStates: filter.reviewStates,
            showBinaryFiles: filter.showBinaryFiles,
            showHiddenFiles: filter.showHiddenFiles,
            showLargeFiles: filter.showLargeFiles
        ),
        worktreeId: query.worktreeId.uuidString
    )
}
