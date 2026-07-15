import Foundation

enum BridgePaneProductFileMetadataSourceError: Error, Equatable {
    case unavailableAuthority
}

struct BridgePaneProductFileSourceAuthority: Sendable {
    let paneId: UUID
    let worktree: Worktree
}

struct BridgePaneProductFileMetadataEmission: Sendable {
    let event: BridgeProductFileMetadataEvent
    let subscriptionId: String
}

typealias BridgePaneProductFileMetadataEventSink =
    @Sendable (BridgeProductFileMetadataEvent) async throws -> Void

typealias BridgePaneProductFileIgnorePolicyLoader =
    @Sendable (URL) async -> BridgeWorktreeFileIgnorePolicy

protocol BridgePaneProductFileMetadataProducing: Sendable {
    func currentSource() async -> BridgeProductFileSourceCurrentResult
    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws
    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws
    func cancel(subscriptionId: String) async
    func publish(status: GitWorkingTreeStatus) async -> [BridgePaneProductFileMetadataEmission]
    func publish(changeset: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission]
    func authoritativePath(for request: BridgeProductFileContentRequest) async -> String?
    func contentReadPlan(
        for request: BridgeProductFileContentRequest
    ) async -> BridgePaneProductFileContentReadPlan?
}

extension BridgePaneProductFileMetadataProducing {
    func authoritativePath(for _: BridgeProductFileContentRequest) async -> String? { nil }
}

actor BridgeUnavailablePaneProductFileMetadataSource: BridgePaneProductFileMetadataProducing {
    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        throw BridgePaneProductFileMetadataSourceError.unavailableAuthority
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        throw BridgePaneProductFileMetadataSourceError.unavailableAuthority
    }

    func cancel(subscriptionId _: String) {}

    func publish(status _: GitWorkingTreeStatus) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(changeset _: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func authoritativePath(for _: BridgeProductFileContentRequest) -> String? { nil }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest
    ) -> BridgePaneProductFileContentReadPlan? { nil }
}

actor BridgePaneProductFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private struct SubscriptionContext: Sendable {
        let manifestIndex: BridgeWorktreeFileManifestIndex
        var openedSource: BridgeWorktreeFileOpenedSource
        let productSource: BridgeProductFileSourceIdentity
        var descriptorByPath: [String: BridgeProductFileDescriptorReadyPayload]
        var descriptorInterestRevisionByPath: [String: Int]
        var inFlightDescriptorInterestRevisionByPath: [String: Int]
        var subscription: BridgeProductSubscriptionSnapshot
    }

    private struct DescriptorReconciliationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let productSource: BridgeProductFileSourceIdentity
        let rows: [BridgeWorktreeTreeRowMetadata]
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private let authority: BridgePaneProductFileSourceAuthority
    private let descriptorMaterializer: BridgePaneProductFileDescriptorMaterializer
    private let ignorePolicyLoader: BridgePaneProductFileIgnorePolicyLoader
    private let statusProvider: any GitWorkingTreeStatusProvider
    private var contextBySubscriptionId: [String: SubscriptionContext] = [:]
    private var nextSourceGeneration = 0

    init(
        authority: BridgePaneProductFileSourceAuthority,
        statusProvider: any GitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(),
        ignorePolicyLoader: BridgePaneProductFileIgnorePolicyLoader? = nil,
        descriptorMaterializer: @escaping BridgePaneProductFileDescriptorMaterializer =
            BridgePaneProductFileContentSource.materialize
    ) {
        self.authority = authority
        self.descriptorMaterializer = descriptorMaterializer
        self.ignorePolicyLoader =
            ignorePolicyLoader ?? { rootURL in
                await BridgeWorktreeFileIgnorePolicy.load(
                    rootURL: rootURL,
                    statusProvider: AgentStudioGitWorkingTreeStatusProvider(
                        timeout: AppPolicies.Bridge.worktreeFileManifestStatusReadTimeout
                    )
                )
            }
        self.statusProvider = statusProvider
    }

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .available(
            BridgeProductFileSourceSpec(
                currentAuthorityRepoId: authority.worktree.repoId,
                currentAuthorityRootPathToken: authority.worktree.stableKey,
                currentAuthorityWorktreeId: authority.worktree.id
            )
        )
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard case .fileMetadata(let sourceSpec) = subscription.subscription,
            case .fileMetadata(_, let pathScope) = subscription.interestState
        else {
            return
        }
        let context = try installContext(
            subscription: subscription,
            sourceSpec: sourceSpec,
            pathScope: pathScope
        )
        let productSource = context.productSource
        try await emit(.sourceAccepted(.init(source: productSource)))

        let ignorePolicy = await ignorePolicyLoader(authority.worktree.path)
        try Task.checkCancellation()
        guard var preparedContext = contextBySubscriptionId[subscription.subscriptionId],
            preparedContext.productSource == productSource
        else { return }
        preparedContext.openedSource = preparedContext.openedSource.withIgnorePolicy(ignorePolicy)
        contextBySubscriptionId[subscription.subscriptionId] = preparedContext

        let manifestIndex = preparedContext.manifestIndex
        let openedSourceWithIgnorePolicy = preparedContext.openedSource
        await manifestIndex.beginEnumeration()
        var emittedWindow = false
        for try await batch in BridgeWorktreeFileMaterializer.materializeTreeRowWindows(
            request: BridgeWorktreeFileMaterializationRequest(
                rootURL: authority.worktree.path,
                openedSource: openedSourceWithIgnorePolicy
            ),
            afterCount: 0,
            windowSize: BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount
        ) {
            try Task.checkCancellation()
            guard isCurrent(subscriptionId: subscription.subscriptionId, source: productSource) else {
                return
            }
            await manifestIndex.appendEnumeratedRows(batch.rows)
            let rowChunks = try Self.boundedProductRowChunks(batch.rows)
            var emittedRowCount = 0
            for (chunkIndex, rows) in rowChunks.enumerated() {
                let isLastChunk = chunkIndex + 1 == rowChunks.count
                try await emit(
                    .treeWindow(
                        try .init(
                            finalWindow: batch.isFinalWindow && isLastChunk,
                            lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                            pathScope: pathScope,
                            rows: rows,
                            source: productSource,
                            startIndex: batch.startIndex + emittedRowCount,
                            totalRowCount: batch.isFinalWindow && isLastChunk
                                ? batch.discoveredRowCount
                                : nil
                        )
                    )
                )
                emittedRowCount += rows.count
            }
            if let latestContext = contextBySubscriptionId[subscription.subscriptionId],
                latestContext.productSource == productSource,
                latestContext.subscription.interestRevision > 0
            {
                try await update(subscription: latestContext.subscription, emit: emit)
            }
            emittedWindow = true
        }
        guard isCurrent(subscriptionId: subscription.subscriptionId, source: productSource) else {
            return
        }
        if !emittedWindow {
            try await emit(
                .treeWindow(
                    try .init(
                        finalWindow: true,
                        lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                        pathScope: pathScope,
                        rows: [],
                        source: productSource,
                        startIndex: 0,
                        totalRowCount: 0
                    )
                )
            )
        }
        await manifestIndex.markEnumerationComplete()
        guard sourceSpec.includeStatuses else { return }
        switch await statusProvider.statusResult(for: authority.worktree.path) {
        case .available(let status):
            try await emit(Self.statusEvent(status, source: productSource))
        case .unavailable:
            try await emit(
                .statusPatch(.init(patch: .invalidated, source: productSource))
            )
        }
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard var context = contextBySubscriptionId[subscription.subscriptionId],
            case .fileMetadata(let interestGroups, _) = subscription.interestState
        else {
            return
        }
        guard subscription.interestRevision >= context.subscription.interestRevision else { return }
        context.subscription = subscription
        contextBySubscriptionId[subscription.subscriptionId] = context
        let productSource = context.productSource

        let demandedPaths = Self.highestPriorityLaneByPath(interestGroups).filter { path, _ in
            context.descriptorInterestRevisionByPath[path] != subscription.interestRevision
                && context.inFlightDescriptorInterestRevisionByPath[path] != subscription.interestRevision
        }
        guard !demandedPaths.isEmpty else { return }
        let manifestPaths = await context.manifestIndex.memberPaths(of: Set(demandedPaths.keys))
        try Task.checkCancellation()
        guard isCurrent(subscription, source: productSource) else { return }
        let refreshed = await BridgeWorktreeFileMaterializer.refreshTreeRows(
            rootURL: authority.worktree.path,
            relativePaths: manifestPaths
        )
        try Task.checkCancellation()
        guard isCurrent(subscription, source: productSource) else { return }
        await context.manifestIndex.applyRefreshedRows(refreshed.rows)
        _ = await context.manifestIndex.removePaths(refreshed.missingPaths)
        try Task.checkCancellation()
        guard isCurrent(subscription, source: productSource) else { return }

        for lane in BridgeProductDemandLane.fileMetadataPriorityOrder {
            let laneRows = refreshed.rows.filter { demandedPaths[$0.path] == lane }
            for rows in try Self.boundedProductRowChunks(laneRows) {
                try Task.checkCancellation()
                guard isCurrent(subscription, source: productSource) else { return }
                try await emit(
                    .treeDelta(
                        try .init(
                            operations: [.upsertRows(rows)],
                            source: productSource
                        )
                    )
                )
            }
        }

        try await reconcileDescriptors(
            .init(
                emit: emit,
                productSource: productSource,
                rows: refreshed.rows.filter { !$0.isDirectory && demandedPaths[$0.path] != nil },
                subscription: subscription
            )
        )
        for missingPath in refreshed.missingPaths {
            try Task.checkCancellation()
            guard let currentContext = contextBySubscriptionId[subscription.subscriptionId],
                currentContext.productSource == productSource,
                currentContext.subscription.interestRevision == subscription.interestRevision
            else { return }
            try await emit(
                .invalidated(
                    try .init(
                        fileId: currentContext.descriptorByPath[missingPath]?.fileId,
                        path: missingPath,
                        reason: .filesystemEvent,
                        replacementDescriptor: nil,
                        source: productSource
                    )
                )
            )
        }
    }

    private func reconcileDescriptors(
        _ request: DescriptorReconciliationRequest
    ) async throws {
        let subscription = request.subscription
        for row in request.rows {
            guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                currentContext.productSource == request.productSource,
                currentContext.subscription.interestRevision == subscription.interestRevision,
                currentContext.descriptorInterestRevisionByPath[row.path] != subscription.interestRevision,
                currentContext.inFlightDescriptorInterestRevisionByPath[row.path] != subscription.interestRevision
            else { return }
            currentContext.inFlightDescriptorInterestRevisionByPath[row.path] = subscription.interestRevision
            contextBySubscriptionId[subscription.subscriptionId] = currentContext
            let materialized: BridgePaneProductFileDescriptorMaterialization
            do {
                materialized = try await descriptorMaterializer(
                    .init(
                        relativePath: row.path,
                        rootURL: authority.worktree.path,
                        row: row,
                        source: request.productSource
                    )
                )
            } catch {
                clearInFlightDescriptorInterest(
                    path: row.path,
                    revision: subscription.interestRevision,
                    subscriptionId: subscription.subscriptionId,
                    source: request.productSource
                )
                throw error
            }
            guard !Task.isCancelled else {
                clearInFlightDescriptorInterest(
                    path: row.path,
                    revision: subscription.interestRevision,
                    subscriptionId: subscription.subscriptionId,
                    source: request.productSource
                )
                throw CancellationError()
            }
            guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                currentContext.productSource == request.productSource,
                currentContext.subscription.interestRevision == subscription.interestRevision,
                currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                    == subscription.interestRevision
            else { return }
            currentContext.inFlightDescriptorInterestRevisionByPath.removeValue(forKey: row.path)
            currentContext.descriptorInterestRevisionByPath[row.path] = subscription.interestRevision
            currentContext.descriptorByPath[row.path] = materialized.payload
            contextBySubscriptionId[subscription.subscriptionId] = currentContext
            try await request.emit(.descriptorReady(.init(payload: materialized.payload)))
        }
    }

    func cancel(subscriptionId: String) {
        contextBySubscriptionId.removeValue(forKey: subscriptionId)
    }

    func publish(status: GitWorkingTreeStatus) -> [BridgePaneProductFileMetadataEmission] {
        contextBySubscriptionId.compactMap { subscriptionId, context in
            guard case .fileMetadata(let sourceSpec) = context.subscription.subscription,
                sourceSpec.includeStatuses
            else { return nil }
            return .init(
                event: Self.statusEvent(status, source: context.productSource),
                subscriptionId: subscriptionId
            )
        }
    }

    func publish(changeset: FileChangeset) async throws -> [BridgePaneProductFileMetadataEmission] {
        guard changeset.worktreeId == authority.worktree.id,
            changeset.repoId == authority.worktree.repoId
        else {
            return []
        }
        var emissions: [BridgePaneProductFileMetadataEmission] = []
        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            guard var context = contextBySubscriptionId[subscriptionId] else { continue }
            let changedPaths = Set(
                changeset.paths.filter {
                    BridgeWorktreeFileMaterializer.canMaterializeDemandPath(
                        $0,
                        openedSource: context.openedSource
                    )
                })
            let refreshed = await BridgeWorktreeFileMaterializer.refreshTreeRows(
                rootURL: authority.worktree.path,
                relativePaths: changedPaths,
                includeAncestorDirectories: true
            )
            await context.manifestIndex.upsertRows(refreshed.rows)
            let removedRows = await context.manifestIndex.removePaths(refreshed.missingPaths)
            for rows in try Self.boundedProductRowChunks(refreshed.rows) {
                emissions.append(
                    .init(
                        event: .treeDelta(
                            try .init(
                                operations: [.upsertRows(rows)],
                                source: context.productSource
                            )
                        ),
                        subscriptionId: subscriptionId
                    )
                )
            }
            for chunk in Self.boundedRemovalChunks(removedRows) {
                emissions.append(
                    .init(
                        event: .treeDelta(
                            try .init(
                                operations: [
                                    .removeRows(
                                        paths: chunk.map(\.path),
                                        rowIds: chunk.map(\.rowId)
                                    )
                                ],
                                source: context.productSource
                            )
                        ),
                        subscriptionId: subscriptionId
                    )
                )
            }
            for path in changedPaths.sorted() where !Self.isGitInternalPath(path) {
                let previousDescriptor = context.descriptorByPath.removeValue(forKey: path)
                context.descriptorInterestRevisionByPath.removeValue(forKey: path)
                context.inFlightDescriptorInterestRevisionByPath.removeValue(forKey: path)
                emissions.append(
                    .init(
                        event: .invalidated(
                            try .init(
                                fileId: previousDescriptor?.fileId,
                                path: path,
                                reason: .contentChanged,
                                replacementDescriptor: nil,
                                source: context.productSource
                            )
                        ),
                        subscriptionId: subscriptionId
                    )
                )
            }
            if changeset.containsGitInternalChanges {
                emissions.append(
                    .init(
                        event: .statusPatch(
                            .init(patch: .invalidated, source: context.productSource)
                        ),
                        subscriptionId: subscriptionId
                    )
                )
            }
            contextBySubscriptionId[subscriptionId] = context
        }
        return emissions
    }

    func authoritativePath(for request: BridgeProductFileContentRequest) -> String? {
        let descriptor = request.descriptor
        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            guard let context = contextBySubscriptionId[subscriptionId],
                context.productSource == descriptor.source
            else { continue }
            return context.descriptorByPath.values.first(where: {
                if case .available(let issuedDescriptor) = $0.availability {
                    issuedDescriptor == descriptor
                } else {
                    false
                }
            })?.path
        }
        return nil
    }

    func contentReadPlan(
        for request: BridgeProductFileContentRequest
    ) -> BridgePaneProductFileContentReadPlan? {
        let descriptor = request.descriptor
        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            guard let context = contextBySubscriptionId[subscriptionId],
                context.productSource == descriptor.source
            else { continue }
            guard
                let issuedPayload = context.descriptorByPath.values.first(where: {
                    if case .available(let issuedDescriptor) = $0.availability {
                        issuedDescriptor == descriptor
                    } else {
                        false
                    }
                })
            else { return nil }
            return BridgePaneProductFileContentReadPlan(
                descriptor: descriptor,
                relativePath: issuedPayload.path,
                rootURL: authority.worktree.path
            )
        }
        return nil
    }

    private func isCurrent(
        subscriptionId: String,
        source: BridgeProductFileSourceIdentity
    ) -> Bool {
        contextBySubscriptionId[subscriptionId]?.productSource == source
    }

    private func isCurrent(
        _ subscription: BridgeProductSubscriptionSnapshot,
        source: BridgeProductFileSourceIdentity
    ) -> Bool {
        guard let context = contextBySubscriptionId[subscription.subscriptionId] else { return false }
        return context.productSource == source
            && context.subscription.interestRevision == subscription.interestRevision
    }

    private func installContext(
        subscription: BridgeProductSubscriptionSnapshot,
        sourceSpec: BridgeProductFileSourceSpec,
        pathScope: [String]
    ) throws -> SubscriptionContext {
        nextSourceGeneration += 1
        let sourceGeneration = nextSourceGeneration
        let legacySourceSpec = try makeLegacySourceSpec(
            sourceSpec: sourceSpec,
            subscriptionId: subscription.subscriptionId,
            pathScope: pathScope
        )
        let openedSource = try BridgeWorktreeFileSourceProvider.openSource(
            spec: legacySourceSpec,
            worktree: authority.worktree,
            subscriptionGeneration: sourceGeneration
        )
        let productSource = try BridgeProductFileSourceIdentity(
            repoId: openedSource.source.repoId,
            rootRevisionToken: openedSource.source.rootRevisionToken,
            sourceCursor: openedSource.source.sourceCursor,
            sourceId: openedSource.source.sourceId,
            subscriptionGeneration: openedSource.source.subscriptionGeneration,
            worktreeId: openedSource.source.worktreeId
        )
        let context = SubscriptionContext(
            manifestIndex: .init(generation: sourceGeneration),
            openedSource: openedSource,
            productSource: productSource,
            descriptorByPath: [:],
            descriptorInterestRevisionByPath: [:],
            inFlightDescriptorInterestRevisionByPath: [:],
            subscription: subscription
        )
        contextBySubscriptionId[subscription.subscriptionId] = context
        return context
    }

    private func clearInFlightDescriptorInterest(
        path: String,
        revision: Int,
        subscriptionId: String,
        source: BridgeProductFileSourceIdentity
    ) {
        guard var context = contextBySubscriptionId[subscriptionId],
            context.productSource == source,
            context.inFlightDescriptorInterestRevisionByPath[path] == revision
        else { return }
        context.inFlightDescriptorInterestRevisionByPath.removeValue(forKey: path)
        contextBySubscriptionId[subscriptionId] = context
    }

    private func makeLegacySourceSpec(
        sourceSpec: BridgeProductFileSourceSpec,
        subscriptionId: String,
        pathScope: [String]
    ) throws -> BridgeWorktreeFileSurfaceSourceSpec {
        guard let repoId = UUID(uuidString: sourceSpec.repoId),
            let worktreeId = UUID(uuidString: sourceSpec.worktreeId)
        else {
            throw BridgeWorktreeFileSourceProviderError.worktreeMismatch
        }
        return .init(
            clientRequestId: subscriptionId,
            repoId: repoId,
            worktreeId: worktreeId,
            rootPathToken: sourceSpec.rootPathToken,
            cwdScope: sourceSpec.cwdScope,
            pathScope: pathScope,
            includeStatuses: sourceSpec.includeStatuses,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )
    }

    private static func productTreeRow(
        _ row: BridgeWorktreeTreeRowMetadata
    ) throws -> BridgeProductFileTreeRow {
        try .init(
            changeStatus: row.changeStatus.flatMap(BridgeProductFileChangeStatus.init(rawValue:)),
            depth: row.depth,
            fileId: row.fileId,
            isDirectory: row.isDirectory,
            lineCount: row.lineCount,
            name: row.name,
            parentPath: row.parentPath,
            path: row.path,
            rowId: row.rowId,
            sizeBytes: row.sizeBytes
        )
    }

    private static func boundedProductRowChunks(
        _ rows: [BridgeWorktreeTreeRowMetadata]
    ) throws -> [[BridgeProductFileTreeRow]] {
        var chunks: [[BridgeProductFileTreeRow]] = []
        var currentChunk: [BridgeProductFileTreeRow] = []
        var currentEncodedByteCount = 0
        let maximumPayloadByteCount = BridgeProductWireContract.maximumMetadataFrameBytes - 4096
        let encoder = JSONEncoder()
        for row in try rows.map(productTreeRow) {
            let encodedByteCount = try encoder.encode(row).count + 1
            if !currentChunk.isEmpty,
                currentChunk.count == BridgeProductWireContract.maximumFileMetadataDeltaMemberCount
                    || currentEncodedByteCount + encodedByteCount > maximumPayloadByteCount
            {
                chunks.append(currentChunk)
                currentChunk = []
                currentEncodedByteCount = 0
            }
            currentChunk.append(row)
            currentEncodedByteCount += encodedByteCount
        }
        if !currentChunk.isEmpty { chunks.append(currentChunk) }
        return chunks
    }

    private static func boundedRemovalChunks(
        _ rows: [BridgeWorktreeTreeRowMetadata]
    ) -> [[BridgeWorktreeTreeRowMetadata]] {
        var chunks: [[BridgeWorktreeTreeRowMetadata]] = []
        var currentChunk: [BridgeWorktreeTreeRowMetadata] = []
        var currentEncodedByteCount = 0
        let maximumPayloadByteCount = BridgeProductWireContract.maximumMetadataFrameBytes - 4096
        for row in rows {
            let encodedByteCount = row.path.utf8.count + row.rowId.utf8.count + 32
            if !currentChunk.isEmpty,
                currentChunk.count == BridgeProductWireContract.maximumFileMetadataDeltaMemberCount
                    || currentEncodedByteCount + encodedByteCount > maximumPayloadByteCount
            {
                chunks.append(currentChunk)
                currentChunk = []
                currentEncodedByteCount = 0
            }
            currentChunk.append(row)
            currentEncodedByteCount += encodedByteCount
        }
        if !currentChunk.isEmpty { chunks.append(currentChunk) }
        return chunks
    }

    private static func statusEvent(
        _ status: GitWorkingTreeStatus,
        source: BridgeProductFileSourceIdentity
    ) -> BridgeProductFileMetadataEvent {
        .statusPatch(
            .init(
                patch: .summary(
                    .init(
                        ahead: status.summary.aheadCount,
                        behind: status.summary.behindCount,
                        branchName: status.branch,
                        staged: status.summary.staged,
                        unstaged: status.summary.changed,
                        untracked: status.summary.untracked
                    )
                ),
                source: source
            )
        )
    }

    private static func highestPriorityLaneByPath(
        _ interestGroups: [BridgeProductFileMetadataInterestStateGroup]
    ) -> [String: BridgeProductDemandLane] {
        var laneByPath: [String: BridgeProductDemandLane] = [:]
        for group in interestGroups {
            for path in group.paths
            where group.lane.priority < (laneByPath[path]?.priority ?? Int.max) {
                laneByPath[path] = group.lane
            }
        }
        return laneByPath
    }

    private static func isGitInternalPath(_ path: String) -> Bool {
        path == ".git" || path.hasPrefix(".git/")
    }
}

extension BridgeProductDemandLane {
    fileprivate static let fileMetadataPriorityOrder: [Self] = [
        .foreground, .active, .visible, .nearby, .speculative, .idle,
    ]

    fileprivate var priority: Int {
        Self.fileMetadataPriorityOrder.firstIndex(of: self) ?? Int.max
    }
}
