import Foundation

actor BridgePaneProductFileMetadataSource: BridgePaneProductFileMetadataProducing {
    struct SubscriptionContext: Sendable {
        let manifestIndex: BridgeWorktreeFileManifestIndex
        var openedSource: BridgeWorktreeFileOpenedSource
        var constructionLease: BridgeSharedFileSnapshotConsumerLease?
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        var descriptorByPath: [String: BridgeProductFileDescriptorReadyPayload]
        var descriptorInterestRevisionByPath: [String: Int]
        var inFlightDescriptorInterestRevisionByPath: [String: Int]
        var subscription: BridgeProductSubscriptionSnapshot
    }

    fileprivate struct DescriptorReconciliationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let rows: [BridgeWorktreeTreeRowMetadata]
        let subscription: BridgeProductSubscriptionSnapshot
    }

    fileprivate struct InitialTreeEnumerationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
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
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let rows: [BridgeWorktreeTreeRowMetadata]
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private struct MissingPathInvalidationRequest: Sendable {
        let emit: BridgePaneProductFileMetadataEventSink
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let missingPaths: Set<String>
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let subscription: BridgeProductSubscriptionSnapshot
    }

    private struct ChangesetEmissionRequest: Sendable {
        let changedPaths: Set<String>
        let containsGitInternalChanges: Bool
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let refreshed: BridgeWorktreeRefreshedTreeRows
        let removedRows: [BridgeWorktreeTreeRowMetadata]
        let subscriptionId: String
    }

    let authority: BridgePaneProductFileSourceAuthority
    let descriptorMaterializer: BridgePaneProductFileDescriptorMaterializer
    let sharedConstructionBinder: BridgePaneProductFileSharedConstructionBinder
    let treeRowRefresher: BridgePaneProductFileTreeRowRefresher
    var contextBySubscriptionId: [String: SubscriptionContext] = [:]
    var nextSourceGeneration = 0

    init(
        authority: BridgePaneProductFileSourceAuthority,
        gitReadContext: BridgeGitReadContext,
        constructionCoordinator: BridgeWorktreeProductConstructionCoordinator,
        statusProvider: any GitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(),
        snapshotPreparationLoader: BridgePaneProductFileSnapshotPreparationLoader? = nil,
        sharedSnapshotBuilder: @escaping BridgePaneProductFileSharedSnapshotBuilder =
            BridgeWorktreeFileMaterializer.buildSharedSnapshot,
        ignorePolicyLoader: BridgePaneProductFileIgnorePolicyLoader? = nil,
        treeRowRefresher: BridgePaneProductFileTreeRowRefresher? = nil,
        descriptorMaterializer: @escaping BridgePaneProductFileDescriptorMaterializer =
            BridgePaneProductFileContentSource.materialize
    ) {
        self.authority = authority
        self.descriptorMaterializer = descriptorMaterializer
        let resolvedPreparationLoader: BridgePaneProductFileSnapshotPreparationLoader =
            if let snapshotPreparationLoader {
                snapshotPreparationLoader
            } else if let ignorePolicyLoader {
                { rootURL, _ in
                    async let ignorePolicy = ignorePolicyLoader(rootURL)
                    async let statusResult = statusProvider.statusResult(for: rootURL)
                    let preparation = await BridgeSharedFileSnapshotPreparation(
                        ignorePolicy: ignorePolicy,
                        statusResult: statusResult,
                        retainedByteCount: 0
                    )
                    return BridgeSharedFileSnapshotPreparation(
                        ignorePolicy: preparation.ignorePolicy,
                        statusResult: preparation.statusResult,
                        retainedByteCount:
                            BridgeWorktreeFileMaterializer.estimatedPreparationRetainedByteCount(
                                ignorePolicy: preparation.ignorePolicy,
                                statusResult: preparation.statusResult
                            )
                    )
                }
            } else {
                { rootURL, constructionGitReadContext in
                    await BridgeWorktreeFileMaterializer.prepareSharedSnapshot(
                        rootURL: rootURL,
                        gitReadContext: constructionGitReadContext,
                        statusProvider: statusProvider
                    )
                }
            }
        self.sharedConstructionBinder = BridgePaneProductFileSharedConstructionBinder(
            coordinator: constructionCoordinator,
            gitReadContext: gitReadContext,
            preparationLoader: resolvedPreparationLoader,
            snapshotBuilder: sharedSnapshotBuilder,
            worktree: authority.worktree
        )
        self.treeRowRefresher =
            treeRowRefresher ?? { rootURL, relativePaths, includeAncestorDirectories in
                await BridgeWorktreeFileMaterializer.refreshTreeRows(
                    rootURL: rootURL,
                    relativePaths: relativePaths,
                    includeAncestorDirectories: includeAncestorDirectories
                )
            }
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard case .fileMetadata(let sourceSpec) = subscription.subscription,
            case .fileMetadata(_, let pathScope) = subscription.interestState
        else {
            return
        }
        await cancel(subscriptionId: subscription.subscriptionId)
        guard
            let context = try installContext(
                subscription: subscription,
                sourceSpec: sourceSpec,
                pathScope: pathScope,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return }
        let productSource = context.productSource
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return }
        try await emit(.sourceAccepted(.init(source: productSource)))
        let constructionLease = try await sharedConstructionBinder.acquire(
            openedSource: context.openedSource
        )
        guard
            attachConstructionLease(
                constructionLease,
                subscriptionId: subscription.subscriptionId,
                productSource: productSource,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else {
            await sharedConstructionBinder.release(constructionLease)
            return
        }
        do {
            let preparation = try await sharedConstructionBinder.preparation(for: constructionLease)
            guard
                let preparedContext = applyPreparation(
                    preparation,
                    subscriptionId: subscription.subscriptionId,
                    productSource: productSource,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                ),
                try await enumerateInitialTree(
                    .init(
                        emit: emit,
                        foregroundWorkAdmission: foregroundWorkAdmission,
                        manifestIndex: preparedContext.manifestIndex,
                        openedSource: preparedContext.openedSource,
                        pathScope: pathScope,
                        productAdmission: productAdmission,
                        productSource: productSource,
                        subscription: subscription
                    ),
                    constructionLease: constructionLease
                )
            else {
                await releaseContext(
                    subscriptionId: subscription.subscriptionId,
                    expectedSource: productSource
                )
                return
            }
            guard sourceSpec.includeStatuses else { return }
            try await publishCurrentStatus(
                preparation.statusResult,
                emit: emit,
                productAdmission: productAdmission,
                productSource: productSource,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        } catch {
            await releaseContext(
                subscriptionId: subscription.subscriptionId,
                expectedSource: productSource
            )
            throw error
        }
    }

    private func enumerateInitialTree(
        _ request: InitialTreeEnumerationRequest,
        constructionLease: BridgeSharedFileSnapshotConsumerLease
    ) async throws -> Bool {
        guard
            await request.manifestIndex.beginEnumeration(
                productAdmission: request.productAdmission,
                foregroundWorkAdmission: request.foregroundWorkAdmission
            )
        else { return false }
        var emittedWindow = false
        var cursor = BridgeSharedFileSnapshotCursor(nextWindowOrdinal: 0)
        readLoop: while true {
            let read = try await sharedConstructionBinder.nextRead(
                for: constructionLease,
                cursor: cursor
            )
            let batch: BridgeWorktreeTreeRowWindowBatch
            switch read {
            case .window(let window):
                batch = BridgeWorktreeTreeRowWindowBatch(
                    discoveredRowCount: window.discoveredRowCount,
                    isFinalWindow: window.isFinalWindow,
                    rows: window.rows,
                    startIndex: window.startIndex
                )
                cursor = BridgeSharedFileSnapshotCursor(
                    nextWindowOrdinal: cursor.nextWindowOrdinal + 1
                )
            case .completed:
                break readLoop
            }
            try Task.checkCancellation()
            guard
                isCurrent(
                    subscriptionId: request.subscription.subscriptionId,
                    source: request.productSource,
                    productAdmission: request.productAdmission
                ),
                request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (request.productAdmission.withValidAdmission { true }) == true
            else {
                return false
            }
            guard
                await request.manifestIndex.appendEnumeratedRows(
                    batch.rows,
                    productAdmission: request.productAdmission,
                    foregroundWorkAdmission: request.foregroundWorkAdmission
                )
            else { return false }
            guard try await emitInitialTreeWindowBatch(batch, request: request) else {
                return false
            }
            if let latestContext = contextBySubscriptionId[request.subscription.subscriptionId],
                latestContext.productSource == request.productSource,
                latestContext.productAdmission.matches(request.productAdmission),
                latestContext.subscription.interestRevision > 0
            {
                try await update(
                    subscription: latestContext.subscription,
                    productAdmission: request.productAdmission,
                    foregroundWorkAdmission: request.foregroundWorkAdmission,
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
            request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
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
            productAdmission: request.productAdmission,
            foregroundWorkAdmission: request.foregroundWorkAdmission
        )
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard case .fileMetadata(let interestGroups, _) = subscription.interestState else { return }
        var acceptedContext: SubscriptionContext?
        let didAcceptContext =
            foregroundWorkAdmission.withValidAdmission {
                productAdmission.withValidAdmission { () -> Bool in
                    guard var context = contextBySubscriptionId[subscription.subscriptionId],
                        context.productAdmission.matches(productAdmission),
                        subscription.interestRevision >= context.subscription.interestRevision
                    else { return false }
                    context.subscription = subscription
                    contextBySubscriptionId[subscription.subscriptionId] = context
                    acceptedContext = context
                    return true
                } ?? false
            } == true
        guard didAcceptContext, let context = acceptedContext else { return }
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
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
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
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            await context.manifestIndex.applyRefreshedRows(
                refreshed.rows,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return }
        guard
            case .applied = await context.manifestIndex.removePaths(
                refreshed.missingPaths,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return }
        try Task.checkCancellation()
        guard
            isCurrent(
                subscription,
                source: productSource,
                productAdmission: productAdmission
            ),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return }

        guard
            try await emitRefreshedTreeDeltas(
                .init(
                    demandedPaths: demandedPaths,
                    emit: emit,
                    foregroundWorkAdmission: foregroundWorkAdmission,
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
                foregroundWorkAdmission: foregroundWorkAdmission,
                productAdmission: productAdmission,
                productSource: productSource,
                rows: refreshed.rows.filter { !$0.isDirectory && demandedPaths[$0.path] != nil },
                subscription: subscription
            )
        )
        _ = try await emitMissingPathInvalidations(
            .init(
                emit: emit,
                foregroundWorkAdmission: foregroundWorkAdmission,
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
                    request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
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
            var acceptedContext: SubscriptionContext?
            let didAcceptContext =
                request.foregroundWorkAdmission.withValidAdmission {
                    request.productAdmission.withValidAdmission { () -> Bool in
                        guard
                            let currentContext = contextBySubscriptionId[
                                request.subscription.subscriptionId
                            ],
                            currentContext.productSource == request.productSource,
                            currentContext.productAdmission.matches(request.productAdmission),
                            currentContext.subscription.interestRevision
                                == request.subscription.interestRevision
                        else { return false }
                        acceptedContext = currentContext
                        return true
                    } ?? false
                } == true
            guard didAcceptContext, let currentContext = acceptedContext else { return false }
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
        for row in request.rows {
            guard try await reconcileDescriptor(row, request: request) else { return }
        }
    }

    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] {
        foregroundWorkAdmission.withValidAdmission {
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
        } ?? []
    }

    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] {
        guard changeset.worktreeId == authority.worktree.id,
            changeset.repoId == authority.worktree.repoId,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else {
            return []
        }
        var emissions: [BridgePaneProductFileMetadataEmission] = []
        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            guard let context = contextBySubscriptionId[subscriptionId],
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
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
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
                let currentContext = contextBySubscriptionId[subscriptionId],
                currentContext.productSource == productSource,
                currentContext.productAdmission.matches(productAdmission),
                await currentContext.manifestIndex.upsertRowsForForegroundRefresh(
                    refreshed.rows,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            else { return [] }
            let removedRows: [BridgeWorktreeTreeRowMetadata]
            switch await currentContext.manifestIndex.removePathsForForegroundRefresh(
                refreshed.missingPaths,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
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
                        foregroundWorkAdmission: foregroundWorkAdmission,
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
        guard request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (request.productAdmission.withValidAdmission { true }) == true
        else { return nil }
        var emissions = try BridgePaneProductFileMetadataEncoding.treeDeltaEmissions(
            refreshed: request.refreshed,
            removedRows: request.removedRows,
            source: request.productSource,
            subscriptionId: request.subscriptionId
        )
        guard var latestContext = contextBySubscriptionId[request.subscriptionId],
            latestContext.productSource == request.productSource,
            latestContext.productAdmission.matches(request.productAdmission)
        else { return nil }
        let invalidatedDescriptorsByPath = request.foregroundWorkAdmission.withValidAdmission {
            request.productAdmission.withValidAdmission {
                () -> [String: BridgeProductFileDescriptorReadyPayload] in
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
            }
        }.flatMap { $0 }
        guard let invalidatedDescriptorsByPath else { return nil }
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
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
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
            paneIdentity: authority.paneId,
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
            constructionLease: nil,
            productAdmission: productAdmission,
            productSource: productSource,
            descriptorByPath: [:],
            descriptorInterestRevisionByPath: [:],
            inFlightDescriptorInterestRevisionByPath: [:],
            subscription: subscription
        )
        return foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                nextSourceGeneration = sourceGeneration
                contextBySubscriptionId[subscription.subscriptionId] = context
                return context
            }
        }.flatMap { $0 }
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
    fileprivate func emitInitialTreeWindowBatch(
        _ batch: BridgeWorktreeTreeRowWindowBatch,
        request: InitialTreeEnumerationRequest
    ) async throws -> Bool {
        let rowChunks = try BridgePaneProductFileMetadataEncoding.boundedProductRowChunks(
            batch.rows
        )
        if rowChunks.isEmpty, batch.isFinalWindow {
            guard request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (request.productAdmission.withValidAdmission { true }) == true
            else { return false }
            try await request.emit(
                .treeWindow(
                    try .init(
                        finalWindow: true,
                        lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                        pathScope: request.pathScope,
                        rows: [],
                        source: request.productSource,
                        startIndex: batch.startIndex,
                        totalRowCount: batch.discoveredRowCount
                    )
                )
            )
            return true
        }
        var emittedRowCount = 0
        for (chunkIndex, rows) in rowChunks.enumerated() {
            let isLastChunk = chunkIndex + 1 == rowChunks.count
            guard request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (request.productAdmission.withValidAdmission { true }) == true
            else {
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
        return true
    }

    fileprivate func reconcileDescriptor(
        _ row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) async throws -> Bool {
        guard reserveDescriptorInterest(for: row, request: request) else { return false }
        let subscription = request.subscription
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
        guard descriptorInterestIsAdmitted(for: row, request: request) else {
            clearInFlightDescriptorInterest(
                path: row.path,
                revision: subscription.interestRevision,
                subscriptionId: subscription.subscriptionId,
                source: request.productSource
            )
            return false
        }
        do {
            try await request.emit(.descriptorReady(.init(payload: materialized.payload)))
        } catch {
            clearInFlightDescriptorInterest(
                path: row.path,
                revision: subscription.interestRevision,
                subscriptionId: subscription.subscriptionId,
                source: request.productSource
            )
            throw error
        }
        guard commitDescriptorInterest(materialized, for: row, request: request) else {
            clearInFlightDescriptorInterest(
                path: row.path,
                revision: subscription.interestRevision,
                subscriptionId: subscription.subscriptionId,
                source: request.productSource
            )
            return false
        }
        return true
    }

    fileprivate func reserveDescriptorInterest(
        for row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) -> Bool {
        let subscription = request.subscription
        return request.foregroundWorkAdmission.withValidAdmission({
            request.productAdmission.withValidAdmission {
                guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                    currentContext.productSource == request.productSource,
                    currentContext.productAdmission.matches(request.productAdmission),
                    currentContext.subscription.interestRevision == subscription.interestRevision,
                    currentContext.descriptorInterestRevisionByPath[row.path]
                        != subscription.interestRevision,
                    currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                        != subscription.interestRevision
                else { return false }
                currentContext.inFlightDescriptorInterestRevisionByPath[row.path] =
                    subscription.interestRevision
                contextBySubscriptionId[subscription.subscriptionId] = currentContext
                return true
            } ?? false
        }) == true
    }

    fileprivate func descriptorInterestIsAdmitted(
        for row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) -> Bool {
        let subscription = request.subscription
        return request.foregroundWorkAdmission.withValidAdmission({
            request.productAdmission.withValidAdmission {
                guard let currentContext = contextBySubscriptionId[subscription.subscriptionId],
                    currentContext.productSource == request.productSource,
                    currentContext.productAdmission.matches(request.productAdmission),
                    currentContext.subscription.interestRevision == subscription.interestRevision,
                    currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                        == subscription.interestRevision
                else { return false }
                return true
            } ?? false
        }) == true
    }

    fileprivate func commitDescriptorInterest(
        _ materialized: BridgePaneProductFileDescriptorMaterialization,
        for row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) -> Bool {
        let subscription = request.subscription
        return request.foregroundWorkAdmission.withValidAdmission({
            request.productAdmission.withValidAdmission {
                guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                    currentContext.productSource == request.productSource,
                    currentContext.productAdmission.matches(request.productAdmission),
                    currentContext.subscription.interestRevision == subscription.interestRevision,
                    currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                        == subscription.interestRevision
                else { return false }
                currentContext.inFlightDescriptorInterestRevisionByPath.removeValue(forKey: row.path)
                currentContext.descriptorInterestRevisionByPath[row.path] =
                    subscription.interestRevision
                currentContext.descriptorByPath[row.path] = materialized.payload
                contextBySubscriptionId[subscription.subscriptionId] = currentContext
                return true
            } ?? false
        }) == true
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
