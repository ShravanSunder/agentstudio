import Foundation

actor BridgePaneProductFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private struct SubscriptionContext: Sendable {
        let manifestIndex: BridgeWorktreeFileManifestIndex
        var openedSource: BridgeWorktreeFileOpenedSource
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        var descriptorByPath: [String: BridgeProductFileDescriptorReadyPayload]
        var descriptorInterestRevisionByPath: [String: Int]
        var inFlightDescriptorInterestRevisionByPath: [String: Int]
        var subscription: BridgeProductSubscriptionSnapshot
    }

    private struct DescriptorReconciliationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let rows: [BridgeWorktreeTreeRowMetadata]
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private struct InitialTreeEnumerationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let manifestIndex: BridgeWorktreeFileManifestIndex
        let openedSource: BridgeWorktreeFileOpenedSource
        let pathScope: [String]
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private struct RefreshedTreeDeltaRequest: Sendable {
        let demandedPaths: [String: BridgeProductDemandLane]
        let emit: BridgePaneProductFileMetadataEventSink
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let rows: [BridgeWorktreeTreeRowMetadata]
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private struct MissingPathInvalidationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let missingPaths: Set<String>
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private struct ChangesetEmissionRequest: Sendable {
        let changedPaths: Set<String>
        let containsGitInternalChanges: Bool
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let refreshed: BridgeWorktreeRefreshedTreeRows
        let removedRows: [BridgeWorktreeTreeRowMetadata]
        let subscriptionId: String
    }

    private let authority: BridgePaneProductFileSourceAuthority
    private let descriptorMaterializer: BridgePaneProductFileDescriptorMaterializer
    private let ignorePolicyLoader: BridgePaneProductFileIgnorePolicyLoader
    private let treeRowRefresher: BridgePaneProductFileTreeRowRefresher
    private let statusProvider: any GitWorkingTreeStatusProvider
    private var contextBySubscriptionId: [String: SubscriptionContext] = [:]
    private var nextSourceGeneration = 0

    init(
        authority: BridgePaneProductFileSourceAuthority,
        statusProvider: any GitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(),
        ignorePolicyLoader: BridgePaneProductFileIgnorePolicyLoader? = nil,
        treeRowRefresher: BridgePaneProductFileTreeRowRefresher? = nil,
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
        self.treeRowRefresher =
            treeRowRefresher ?? { rootURL, relativePaths, includeAncestorDirectories in
                await BridgeWorktreeFileMaterializer.refreshTreeRows(
                    rootURL: rootURL,
                    relativePaths: relativePaths,
                    includeAncestorDirectories: includeAncestorDirectories
                )
            }
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
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard case .fileMetadata(let sourceSpec) = subscription.subscription,
            case .fileMetadata(_, let pathScope) = subscription.interestState
        else {
            return
        }
        guard
            let context = try installContext(
                subscription: subscription,
                sourceSpec: sourceSpec,
                pathScope: pathScope,
                productAdmission: productAdmission
            )
        else { return }
        let productSource = context.productSource
        guard (productAdmission.withValidAdmission { true }) == true else { return }
        try await emit(.sourceAccepted(.init(source: productSource)))

        let ignorePolicy = await ignorePolicyLoader(authority.worktree.path)
        try Task.checkCancellation()
        guard
            let preparedContext = productAdmission.withValidAdmission({
                () -> SubscriptionContext? in
                guard var preparedContext = contextBySubscriptionId[subscription.subscriptionId],
                    preparedContext.productSource == productSource,
                    preparedContext.productAdmission.matches(productAdmission)
                else { return nil }
                preparedContext.openedSource = preparedContext.openedSource.withIgnorePolicy(ignorePolicy)
                contextBySubscriptionId[subscription.subscriptionId] = preparedContext
                return preparedContext
            }).flatMap({ $0 })
        else { return }

        guard
            try await enumerateInitialTree(
                .init(
                    emit: emit,
                    manifestIndex: preparedContext.manifestIndex,
                    openedSource: preparedContext.openedSource,
                    pathScope: pathScope,
                    productAdmission: productAdmission,
                    productSource: productSource,
                    subscription: subscription
                )
            )
        else { return }
        guard sourceSpec.includeStatuses else { return }
        try await publishCurrentStatus(
            emit: emit,
            productAdmission: productAdmission,
            productSource: productSource
        )
    }

    private func enumerateInitialTree(
        _ request: InitialTreeEnumerationRequest
    ) async throws -> Bool {
        guard
            await request.manifestIndex.beginEnumeration(
                productAdmission: request.productAdmission
            )
        else { return false }
        var emittedWindow = false
        for try await batch in BridgeWorktreeFileMaterializer.materializeTreeRowWindows(
            request: BridgeWorktreeFileMaterializationRequest(
                rootURL: authority.worktree.path,
                openedSource: request.openedSource
            ),
            afterCount: 0,
            windowSize: BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount
        ) {
            try Task.checkCancellation()
            guard
                isCurrent(
                    subscriptionId: request.subscription.subscriptionId,
                    source: request.productSource,
                    productAdmission: request.productAdmission
                ),
                (request.productAdmission.withValidAdmission { true }) == true
            else {
                return false
            }
            guard
                await request.manifestIndex.appendEnumeratedRows(
                    batch.rows,
                    productAdmission: request.productAdmission
                )
            else { return false }
            let rowChunks = try BridgePaneProductFileMetadataEncoding.boundedProductRowChunks(
                batch.rows
            )
            var emittedRowCount = 0
            for (chunkIndex, rows) in rowChunks.enumerated() {
                let isLastChunk = chunkIndex + 1 == rowChunks.count
                guard (request.productAdmission.withValidAdmission { true }) == true else {
                    return false
                }
                try await request.emit(
                    .treeWindow(
                        try .init(
                            finalWindow: batch.isFinalWindow && isLastChunk,
                            lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                            pathScope: request.pathScope,
                            rows: rows,
                            source: request.productSource,
                            startIndex: batch.startIndex + emittedRowCount,
                            totalRowCount: batch.isFinalWindow && isLastChunk
                                ? batch.discoveredRowCount
                                : nil
                        )
                    )
                )
                emittedRowCount += rows.count
            }
            if let latestContext = contextBySubscriptionId[request.subscription.subscriptionId],
                latestContext.productSource == request.productSource,
                latestContext.productAdmission.matches(request.productAdmission),
                latestContext.subscription.interestRevision > 0
            {
                try await update(
                    subscription: latestContext.subscription,
                    productAdmission: request.productAdmission,
                    emit: request.emit
                )
            }
            emittedWindow = true
        }
        guard
            isCurrent(
                subscriptionId: request.subscription.subscriptionId,
                source: request.productSource,
                productAdmission: request.productAdmission
            ),
            (request.productAdmission.withValidAdmission { true }) == true
        else {
            return false
        }
        if !emittedWindow {
            try await request.emit(
                .treeWindow(
                    try .init(
                        finalWindow: true,
                        lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                        pathScope: request.pathScope,
                        rows: [],
                        source: request.productSource,
                        startIndex: 0,
                        totalRowCount: 0
                    )
                )
            )
        }
        return await request.manifestIndex.markEnumerationComplete(
            productAdmission: request.productAdmission
        )
    }

    private func publishCurrentStatus(
        emit: BridgePaneProductFileMetadataEventSink,
        productAdmission: BridgeProductAdmissionContext,
        productSource: BridgeProductFileSourceIdentity
    ) async throws {
        switch await statusProvider.statusResult(for: authority.worktree.path) {
        case .available(let status):
            guard (productAdmission.withValidAdmission { true }) == true else { return }
            try await emit(
                BridgePaneProductFileMetadataEncoding.statusEvent(
                    status,
                    source: productSource
                )
            )
        case .unavailable:
            guard (productAdmission.withValidAdmission { true }) == true else { return }
            try await emit(
                .statusPatch(.init(patch: .invalidated, source: productSource))
            )
        }
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard case .fileMetadata(let interestGroups, _) = subscription.interestState,
            let context = productAdmission.withValidAdmission({ () -> SubscriptionContext? in
                guard var context = contextBySubscriptionId[subscription.subscriptionId],
                    context.productAdmission.matches(productAdmission),
                    subscription.interestRevision >= context.subscription.interestRevision
                else { return nil }
                context.subscription = subscription
                contextBySubscriptionId[subscription.subscriptionId] = context
                return context
            }).flatMap({ $0 })
        else { return }
        let productSource = context.productSource

        let demandedPaths = BridgePaneProductFileMetadataEncoding.highestPriorityLaneByPath(
            interestGroups
        ).filter { path, _ in
            context.descriptorInterestRevisionByPath[path] != subscription.interestRevision
                && context.inFlightDescriptorInterestRevisionByPath[path] != subscription.interestRevision
        }
        guard !demandedPaths.isEmpty else { return }
        let manifestPaths = await context.manifestIndex.memberPaths(of: Set(demandedPaths.keys))
        try Task.checkCancellation()
        guard
            isCurrent(
                subscription,
                source: productSource,
                productAdmission: productAdmission
            ),
            (productAdmission.withValidAdmission { true }) == true
        else { return }
        let refreshed = await treeRowRefresher(authority.worktree.path, manifestPaths, false)
        try Task.checkCancellation()
        guard
            isCurrent(
                subscription,
                source: productSource,
                productAdmission: productAdmission
            ),
            await context.manifestIndex.applyRefreshedRows(
                refreshed.rows,
                productAdmission: productAdmission
            )
        else { return }
        guard
            case .applied = await context.manifestIndex.removePaths(
                refreshed.missingPaths,
                productAdmission: productAdmission
            )
        else { return }
        try Task.checkCancellation()
        guard
            isCurrent(
                subscription,
                source: productSource,
                productAdmission: productAdmission
            ),
            (productAdmission.withValidAdmission { true }) == true
        else { return }

        guard
            try await emitRefreshedTreeDeltas(
                .init(
                    demandedPaths: demandedPaths,
                    emit: emit,
                    productAdmission: productAdmission,
                    productSource: productSource,
                    rows: refreshed.rows,
                    subscription: subscription
                )
            )
        else { return }

        try await reconcileDescriptors(
            .init(
                emit: emit,
                productAdmission: productAdmission,
                productSource: productSource,
                rows: refreshed.rows.filter { !$0.isDirectory && demandedPaths[$0.path] != nil },
                subscription: subscription
            )
        )
        _ = try await emitMissingPathInvalidations(
            .init(
                emit: emit,
                missingPaths: refreshed.missingPaths,
                productAdmission: productAdmission,
                productSource: productSource,
                subscription: subscription
            )
        )
    }

    private func emitRefreshedTreeDeltas(
        _ request: RefreshedTreeDeltaRequest
    ) async throws -> Bool {
        for lane in BridgeProductDemandLane.fileMetadataPriorityOrder {
            let laneRows = request.rows.filter { request.demandedPaths[$0.path] == lane }
            for rows in try BridgePaneProductFileMetadataEncoding.boundedProductRowChunks(
                laneRows
            ) {
                try Task.checkCancellation()
                guard
                    isCurrent(
                        request.subscription,
                        source: request.productSource,
                        productAdmission: request.productAdmission
                    ),
                    (request.productAdmission.withValidAdmission { true }) == true
                else { return false }
                try await request.emit(
                    .treeDelta(
                        try .init(
                            operations: [.upsertRows(rows)],
                            source: request.productSource
                        )
                    )
                )
            }
        }
        return true
    }

    private func emitMissingPathInvalidations(
        _ request: MissingPathInvalidationRequest
    ) async throws -> Bool {
        for missingPath in request.missingPaths {
            try Task.checkCancellation()
            guard
                let currentContext = request.productAdmission.withValidAdmission({
                    () -> SubscriptionContext? in
                    guard
                        let currentContext = contextBySubscriptionId[
                            request.subscription.subscriptionId
                        ],
                        currentContext.productSource == request.productSource,
                        currentContext.productAdmission.matches(request.productAdmission),
                        currentContext.subscription.interestRevision
                            == request.subscription.interestRevision
                    else { return nil }
                    return currentContext
                }).flatMap({ $0 })
            else { return false }
            try await request.emit(
                .invalidated(
                    try .init(
                        fileId: currentContext.descriptorByPath[missingPath]?.fileId,
                        path: missingPath,
                        reason: .filesystemEvent,
                        replacementDescriptor: nil,
                        source: request.productSource
                    )
                )
            )
        }
        return true
    }

    private func reconcileDescriptors(
        _ request: DescriptorReconciliationRequest
    ) async throws {
        let subscription = request.subscription
        for row in request.rows {
            guard
                (request.productAdmission.withValidAdmission {
                    guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                        currentContext.productSource == request.productSource,
                        currentContext.productAdmission.matches(request.productAdmission),
                        currentContext.subscription.interestRevision
                            == subscription.interestRevision,
                        currentContext.descriptorInterestRevisionByPath[row.path]
                            != subscription.interestRevision,
                        currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                            != subscription.interestRevision
                    else { return false }
                    currentContext.inFlightDescriptorInterestRevisionByPath[row.path] =
                        subscription.interestRevision
                    contextBySubscriptionId[subscription.subscriptionId] = currentContext
                    return true
                }) == true
            else { return }
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
            guard
                (request.productAdmission.withValidAdmission {
                    guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                        currentContext.productSource == request.productSource,
                        currentContext.productAdmission.matches(request.productAdmission),
                        currentContext.subscription.interestRevision
                            == subscription.interestRevision,
                        currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                            == subscription.interestRevision
                    else { return false }
                    currentContext.inFlightDescriptorInterestRevisionByPath.removeValue(
                        forKey: row.path
                    )
                    currentContext.descriptorInterestRevisionByPath[row.path] =
                        subscription.interestRevision
                    currentContext.descriptorByPath[row.path] = materialized.payload
                    contextBySubscriptionId[subscription.subscriptionId] = currentContext
                    return true
                }) == true
            else {
                clearInFlightDescriptorInterest(
                    path: row.path,
                    revision: subscription.interestRevision,
                    subscriptionId: subscription.subscriptionId,
                    source: request.productSource
                )
                return
            }
            try await request.emit(.descriptorReady(.init(payload: materialized.payload)))
        }
    }

    func cancel(subscriptionId: String) {
        contextBySubscriptionId.removeValue(forKey: subscriptionId)
    }

    func diagnosticSnapshot() async -> BridgeFileMetadataSourceDiagnostics {
        let contexts = Array(contextBySubscriptionId.values)
        var manifestRowCount = 0
        for context in contexts {
            manifestRowCount += await context.manifestIndex.count
        }
        return BridgeFileMetadataSourceDiagnostics(
            descriptorCount: contexts.reduce(0) { $0 + $1.descriptorByPath.count },
            inFlightDescriptorCount: contexts.reduce(0) {
                $0 + $1.inFlightDescriptorInterestRevisionByPath.count
            },
            manifestRowCount: manifestRowCount,
            subscriptionCount: contexts.count
        )
    }

    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext
    ) -> [BridgePaneProductFileMetadataEmission] {
        productAdmission.withValidAdmission {
            contextBySubscriptionId.compactMap { subscriptionId, context in
                guard case .fileMetadata(let sourceSpec) = context.subscription.subscription,
                    context.productAdmission.matches(productAdmission),
                    sourceSpec.includeStatuses
                else { return nil }
                return .init(
                    event: BridgePaneProductFileMetadataEncoding.statusEvent(
                        status,
                        source: context.productSource
                    ),
                    subscriptionId: subscriptionId
                )
            }
        } ?? []
    }

    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> [BridgePaneProductFileMetadataEmission] {
        guard changeset.worktreeId == authority.worktree.id,
            changeset.repoId == authority.worktree.repoId,
            (productAdmission.withValidAdmission { true }) == true
        else {
            return []
        }
        var emissions: [BridgePaneProductFileMetadataEmission] = []
        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            guard let context = contextBySubscriptionId[subscriptionId],
                context.productAdmission.matches(productAdmission)
            else { return [] }
            let productSource = context.productSource
            let changedPaths = Set(
                changeset.paths.filter {
                    BridgeWorktreeFileMaterializer.canMaterializeDemandPath(
                        $0,
                        openedSource: context.openedSource
                    )
                })
            let refreshed = await treeRowRefresher(
                authority.worktree.path,
                changedPaths,
                true
            )
            guard let currentContext = contextBySubscriptionId[subscriptionId],
                currentContext.productSource == productSource,
                currentContext.productAdmission.matches(productAdmission),
                await currentContext.manifestIndex.upsertRows(
                    refreshed.rows,
                    productAdmission: productAdmission
                )
            else { return [] }
            let removedRows: [BridgeWorktreeTreeRowMetadata]
            switch await currentContext.manifestIndex.removePaths(
                refreshed.missingPaths,
                productAdmission: productAdmission
            ) {
            case .applied(let rows):
                removedRows = rows
            case .rejected:
                return []
            }
            guard
                let subscriptionEmissions = try makeChangesetEmissions(
                    .init(
                        changedPaths: changedPaths,
                        containsGitInternalChanges: changeset.containsGitInternalChanges,
                        productAdmission: productAdmission,
                        productSource: productSource,
                        refreshed: refreshed,
                        removedRows: removedRows,
                        subscriptionId: subscriptionId
                    )
                )
            else { return [] }
            emissions.append(contentsOf: subscriptionEmissions)
        }
        return emissions
    }

    private func makeChangesetEmissions(
        _ request: ChangesetEmissionRequest
    ) throws -> [BridgePaneProductFileMetadataEmission]? {
        guard (request.productAdmission.withValidAdmission { true }) == true else { return nil }
        var emissions = try BridgePaneProductFileMetadataEncoding.treeDeltaEmissions(
            refreshed: request.refreshed,
            removedRows: request.removedRows,
            source: request.productSource,
            subscriptionId: request.subscriptionId
        )
        guard
            let invalidatedDescriptorsByPath = request.productAdmission.withValidAdmission({
                () -> [String: BridgeProductFileDescriptorReadyPayload]? in
                guard var latestContext = contextBySubscriptionId[request.subscriptionId],
                    latestContext.productSource == request.productSource,
                    latestContext.productAdmission.matches(request.productAdmission)
                else { return nil }
                var invalidatedDescriptorsByPath: [String: BridgeProductFileDescriptorReadyPayload] = [:]
                for path in request.changedPaths
                where !BridgePaneProductFileMetadataEncoding.isGitInternalPath(path) {
                    if let previousDescriptor = latestContext.descriptorByPath.removeValue(
                        forKey: path
                    ) {
                        invalidatedDescriptorsByPath[path] = previousDescriptor
                    }
                    latestContext.descriptorInterestRevisionByPath.removeValue(forKey: path)
                    latestContext.inFlightDescriptorInterestRevisionByPath.removeValue(
                        forKey: path
                    )
                }
                contextBySubscriptionId[request.subscriptionId] = latestContext
                return invalidatedDescriptorsByPath
            }).flatMap({ $0 })
        else { return nil }
        let invalidationEmissions: [BridgePaneProductFileMetadataEmission] =
            try request.changedPaths.sorted().compactMap { path in
                guard !BridgePaneProductFileMetadataEncoding.isGitInternalPath(path) else {
                    return nil
                }
                return .init(
                    event: .invalidated(
                        try .init(
                            fileId: invalidatedDescriptorsByPath[path]?.fileId,
                            path: path,
                            reason: .contentChanged,
                            replacementDescriptor: nil,
                            source: request.productSource
                        )
                    ),
                    subscriptionId: request.subscriptionId
                )
            }
        guard (request.productAdmission.withValidAdmission { true }) == true else { return nil }
        emissions.append(contentsOf: invalidationEmissions)
        if request.containsGitInternalChanges {
            emissions.append(
                .init(
                    event: .statusPatch(
                        .init(patch: .invalidated, source: request.productSource)
                    ),
                    subscriptionId: request.subscriptionId
                )
            )
        }
        return emissions
    }

    private func isCurrent(
        subscriptionId: String,
        source: BridgeProductFileSourceIdentity,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard let context = contextBySubscriptionId[subscriptionId] else { return false }
        return context.productSource == source
            && context.productAdmission.matches(productAdmission)
    }

    private func isCurrent(
        _ subscription: BridgeProductSubscriptionSnapshot,
        source: BridgeProductFileSourceIdentity,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard let context = contextBySubscriptionId[subscription.subscriptionId] else { return false }
        return context.productSource == source
            && context.productAdmission.matches(productAdmission)
            && context.subscription.interestRevision == subscription.interestRevision
    }

    private func installContext(
        subscription: BridgeProductSubscriptionSnapshot,
        sourceSpec: BridgeProductFileSourceSpec,
        pathScope: [String],
        productAdmission: BridgeProductAdmissionContext
    ) throws -> SubscriptionContext? {
        let sourceGeneration = nextSourceGeneration + 1
        let legacySourceSpec = try BridgePaneProductFileMetadataEncoding.legacySourceSpec(
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
            manifestIndex: .init(
                generation: sourceGeneration,
                productAdmission: productAdmission
            ),
            openedSource: openedSource,
            productAdmission: productAdmission,
            productSource: productSource,
            descriptorByPath: [:],
            descriptorInterestRevisionByPath: [:],
            inFlightDescriptorInterestRevisionByPath: [:],
            subscription: subscription
        )
        return productAdmission.withValidAdmission {
            nextSourceGeneration = sourceGeneration
            contextBySubscriptionId[subscription.subscriptionId] = context
            return context
        }
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

}

extension BridgePaneProductFileMetadataSource {
    func authoritativePath(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) -> String? {
        productAdmission.withValidAdmission { () -> String? in
            let descriptor = request.descriptor
            for subscriptionId in contextBySubscriptionId.keys.sorted() {
                guard let context = contextBySubscriptionId[subscriptionId],
                    context.productSource == descriptor.source,
                    context.productAdmission.matches(productAdmission)
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
        }.flatMap({ $0 })
    }

    func contentReadPlan(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? {
        productAdmission.withValidAdmission { () -> BridgePaneProductFileContentReadPlan? in
            let descriptor = request.descriptor
            for subscriptionId in contextBySubscriptionId.keys.sorted() {
                guard let context = contextBySubscriptionId[subscriptionId],
                    context.productSource == descriptor.source,
                    context.productAdmission.matches(productAdmission)
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
        }.flatMap({ $0 })
    }
}
