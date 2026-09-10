import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation Review proportional source capture")
struct ReviewAnnotationProportionalSourceCaptureTests {
    @Test("acknowledged successor opens only affected handles when unaffected demand is resident")
    func acknowledgedSuccessorOpensOnlyAffectedHandles() async throws {
        let fixture = try await makeDeltaFixture()
        _ = try await fixture.cache.load(
            handle: fixture.unaffectedHandle,
            productAdmission: fixture.productAdmission
        )
        try acknowledge(
            fixture.successor,
            expectedPredecessorID: fixture.predecessor.publicationId,
            coordinator: fixture.coordinator,
            productAdmission: fixture.productAdmission
        )
        #expect(
            fixture.coordinator.retainedPublication(
                matching: try annotationIdentity(fixture.predecessor),
                productAdmission: fixture.productAdmission
            ) == nil
        )

        let capture = try await capture(
            publication: fixture.successor,
            package: fixture.successor.package,
            coordinator: fixture.coordinator,
            cache: fixture.cache,
            productAdmission: fixture.productAdmission
        )

        #expect(try availableFileCount(capture) == 2)
        #expect(
            await fixture.provider.recordedContentRequestsCount(
                handleId: fixture.affectedHandle.handleId
            ) == 1
        )
        #expect(
            await fixture.provider.recordedContentRequestsCount(
                handleId: fixture.unaffectedHandle.handleId
            ) == 1
        )
    }

    @Test("known-empty structural delta uses cache-only loads for every demanded handle")
    func knownEmptyStructuralDeltaUsesCacheOnlyLoads() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let predecessorPackage = reviewPackage(itemCount: 2)
        let successorPackage = reorderedReviewPackage(predecessorPackage)
        let delta = try #require(
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: predecessorPackage,
                    nextPackage: successorPackage,
                    currentRevision: predecessorPackage.revision
                )
            )
        )
        let handles = try demandedHeadHandles(successorPackage)
        let provider = reviewProvider(package: successorPackage, handles: handles)
        let cache = BridgeReviewContentLoaderCache(provider: provider)
        for handle in handles {
            _ = try await cache.load(handle: handle, productAdmission: productAdmission.context)
        }
        let coordinator = BridgeReviewPublicationCoordinator()
        let predecessor = try await commit(
            package: predecessorPackage,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        try acknowledge(
            predecessor,
            expectedPredecessorID: nil,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        let successor = try await commit(
            package: successorPackage,
            delta: delta,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        try acknowledge(
            successor,
            expectedPredecessorID: predecessor.publicationId,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )

        let capture = try await capture(
            publication: successor,
            package: successorPackage,
            coordinator: coordinator,
            cache: cache,
            productAdmission: productAdmission.context
        )

        #expect(try availableFileCount(capture) == 2)
        #expect(await provider.recordedContentRequestsCount() == handles.count)
        #expect(
            WorktreeAnnotationSourceCapture.reviewSourceLoadAffectedItemIDs(
                publication: successor
            ) == Set<String>()
        )
    }

    @Test("evicted unaffected demand selects full-safe provider loading")
    func evictedUnaffectedDemandSelectsFullSafeProviderLoading() async throws {
        let fixture = try await makeDeltaFixture(contentCacheMaxBytes: "content".utf8.count)
        _ = try await fixture.cache.load(
            handle: fixture.unaffectedHandle,
            productAdmission: fixture.productAdmission
        )
        _ = try await fixture.cache.load(
            handle: fixture.evictionHandle,
            productAdmission: fixture.productAdmission
        )
        try acknowledge(
            fixture.successor,
            expectedPredecessorID: fixture.predecessor.publicationId,
            coordinator: fixture.coordinator,
            productAdmission: fixture.productAdmission
        )

        let capture = try await capture(
            publication: fixture.successor,
            package: fixture.successor.package,
            coordinator: fixture.coordinator,
            cache: fixture.cache,
            productAdmission: fixture.productAdmission
        )

        #expect(try availableFileCount(capture) == 2)
        #expect(
            await fixture.provider.recordedContentRequestsCount(
                handleId: fixture.affectedHandle.handleId
            ) == 1
        )
        #expect(
            await fixture.provider.recordedContentRequestsCount(
                handleId: fixture.unaffectedHandle.handleId
            ) == 2
        )
    }

    @Test("missing and replacement deltas use full-safe provider loading")
    func missingAndReplacementDeltasUseFullSafeProviderLoading() async throws {
        for package in [
            reviewPackage(itemCount: 2),
            replacementReviewPackage(itemCount: 2),
        ] {
            let productAdmission = try BridgeProductAdmissionTestContext.make()
            let handles = try demandedHeadHandles(package)
            let provider = reviewProvider(package: package, handles: handles)
            let cache = BridgeReviewContentLoaderCache(provider: provider)
            let coordinator = BridgeReviewPublicationCoordinator()
            let publication = try await commit(
                package: package,
                coordinator: coordinator,
                productAdmission: productAdmission.context
            )
            try acknowledge(
                publication,
                expectedPredecessorID: nil,
                coordinator: coordinator,
                productAdmission: productAdmission.context
            )

            let captured = try await capture(
                publication: publication,
                package: package,
                coordinator: coordinator,
                cache: cache,
                productAdmission: productAdmission.context
            )

            #expect(try availableFileCount(captured) == 2)
            #expect(await provider.recordedContentRequestsCount() == handles.count)
            #expect(
                WorktreeAnnotationSourceCapture.reviewSourceLoadAffectedItemIDs(
                    publication: publication
                ) == nil
            )
        }
    }

    @Test("operation-to-package mismatch uses full-safe provider loading")
    func operationToPackageMismatchUsesFullSafeProviderLoading() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let predecessorPackage = reviewPackage(itemCount: 2)
        let successorPackage = replacingReviewPackage(
            predecessorPackage,
            revision: predecessorPackage.revision + 1,
            itemsById: predecessorPackage.itemsById
        )
        let mismatchedItem = makeBridgeReviewItemDescriptor(
            itemId: "not-in-installed-package",
            path: "Sources/Mismatch.swift",
            fileClass: .source
        )
        let mismatchedDelta = BridgeReviewDelta(
            packageId: successorPackage.packageId,
            reviewGeneration: successorPackage.reviewGeneration,
            revision: successorPackage.revision,
            operations: .init(updateItems: [mismatchedItem])
        )
        let handles = try demandedHeadHandles(successorPackage)
        let provider = reviewProvider(package: successorPackage, handles: handles)
        let cache = BridgeReviewContentLoaderCache(provider: provider)
        let coordinator = BridgeReviewPublicationCoordinator()
        let publication = try await commit(
            package: successorPackage,
            delta: mismatchedDelta,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        try acknowledge(
            publication,
            expectedPredecessorID: nil,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )

        let captured = try await capture(
            publication: publication,
            package: successorPackage,
            coordinator: coordinator,
            cache: cache,
            productAdmission: productAdmission.context
        )

        #expect(try availableFileCount(captured) == 2)
        #expect(await provider.recordedContentRequestsCount() == handles.count)
        #expect(
            WorktreeAnnotationSourceCapture.reviewSourceLoadAffectedItemIDs(
                publication: publication
            ) == nil
        )
    }

    @Test("one failed shared handle isolates all dependents through finite projection")
    func failedSharedHandleIsolatesEveryDependentThread() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = reviewPackage(itemCount: 2)
        let availableItem = try #require(package.itemsById[package.orderedItemIds[0]])
        let unavailableItem = try #require(package.itemsById[package.orderedItemIds[1]])
        let availableHandle = try #require(availableItem.contentRoles.head)
        let unavailableHandle = try #require(unavailableItem.contentRoles.head)
        let unavailablePath = try #require(unavailableItem.headPath)
        let provider = reviewProvider(package: package, handles: [availableHandle])
        let cache = BridgeReviewContentLoaderCache(provider: provider)
        let coordinator = BridgeReviewPublicationCoordinator()
        let publication = try await commit(
            package: package,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        try acknowledge(
            publication,
            expectedPredecessorID: nil,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        let availableRequirement = try annotationRequirement(item: availableItem, threadIndex: 0)
        let unavailableLocatedRequirement = try annotationRequirement(
            item: unavailableItem,
            threadIndex: 1
        )
        let secondUnavailableLocatedRequirement = WorktreeAnnotationSourceRefreshRequirement(
            threadID: annotationThreadID(index: 2),
            origin: unavailableLocatedRequirement.origin
        )
        let unavailableWholeFileRequirement = WorktreeAnnotationSourceRefreshRequirement(
            threadID: annotationThreadID(index: 3),
            origin: .wholeFile(
                repositoryRelativePath: unavailablePath,
                sourceRole: .reviewHead
            )
        )
        let requirements = [
            availableRequirement,
            unavailableLocatedRequirement,
            secondUnavailableLocatedRequirement,
            unavailableWholeFileRequirement,
        ]

        let capture = try await WorktreeAnnotationSourceCapture.reviewRefresh(
            identity: try annotationIdentity(publication),
            publicationCoordinator: coordinator,
            contentLoaderCache: cache,
            requirements: requirements,
            productAdmission: productAdmission.context
        )
        let evaluated = try evaluatePartialFailure(
            capture: capture,
            requirements: requirements,
            reviewGeneration: package.reviewGeneration
        )

        #expect(evaluated.placements[availableRequirement.threadID]?.placement == .exact)
        #expect(
            evaluated.placements[unavailableLocatedRequirement.threadID]?.placement == .unavailable
        )
        #expect(
            evaluated.placements[secondUnavailableLocatedRequirement.threadID]?.placement
                == .unavailable
        )
        #expect(
            evaluated.placements[unavailableWholeFileRequirement.threadID]?.placement == .unavailable
        )
        #expect(await provider.recordedContentRequestsCount(handleId: availableHandle.handleId) == 1)
        #expect(await provider.recordedContentRequestsCount(handleId: unavailableHandle.handleId) == 1)

        let projectedContexts = try finiteProjectionMessageContexts(
            projectionCapture(
                evaluated,
                sourceGeneration: package.reviewGeneration.rawValue
            )
        )

        #expect(projectedContexts[availableRequirement.threadID.rawValue]?.placement == .exact)
        #expect(
            projectedContexts[unavailableLocatedRequirement.threadID.rawValue]?.placement
                == .unavailable
        )
        #expect(
            projectedContexts[secondUnavailableLocatedRequirement.threadID.rawValue]?.placement
                == .unavailable
        )
    }

    private func evaluatePartialFailure(
        capture: WorktreeAnnotationSourceRefreshCapture,
        requirements: [WorktreeAnnotationSourceRefreshRequirement],
        reviewGeneration: BridgeReviewGeneration
    ) throws -> PartialFailureEvaluationFixture {
        let sessionID = WorktreeAnnotationSessionID.generate()
        let session = WorktreeAnnotationSession(
            id: sessionID,
            repositoryID: capture.fingerprint.repositoryID,
            worktreeID: capture.fingerprint.worktreeID,
            lifecycle: .living,
            sourceRelationship: .applicable,
            acceptedSourceFingerprint: capture.fingerprint,
            semanticRevision: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            completedAt: nil
        )
        let threads = requirements.enumerated().map { index, requirement in
            WorktreeAnnotationThread(
                id: requirement.threadID,
                sessionID: sessionID,
                origin: requirement.origin,
                resolution: .open,
                createdOrdinal: index,
                semanticRevision: 0,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1),
                resolvedAt: nil
            )
        }
        let evaluation = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: session,
                threads: threads,
                surface: .review,
                sourceEpoch: String(reviewGeneration.rawValue),
                currentFingerprint: capture.fingerprint,
                material: capture.material
            )
        )
        return PartialFailureEvaluationFixture(
            placements: evaluation.placements,
            session: session,
            threads: threads
        )
    }

    private func projectionCapture(
        _ evaluated: PartialFailureEvaluationFixture,
        sourceGeneration: Int
    ) -> BridgeProductAnnotationProjectionCapture {
        let locatedThreadDetails = evaluated.threads.dropLast().enumerated().map { index, thread in
            WorktreeAnnotationThreadDetail(
                thread: thread,
                messages: [projectionMessage(thread: thread, index: index)]
            )
        }
        return BridgeProductAnnotationProjectionCapture(
            worktreeID: evaluated.session.worktreeID,
            recoveryStatus: .available,
            sessions: [evaluated.session],
            details: [
                WorktreeAnnotationSessionDetail(
                    session: evaluated.session,
                    threads: locatedThreadDetails
                )
            ],
            placementsByThreadID: evaluated.placements,
            projectionRevision: 1,
            sourceGeneration: sourceGeneration
        )
    }

    private func projectionMessage(
        thread: WorktreeAnnotationThread,
        index: Int
    ) -> WorktreeAnnotationMessage {
        WorktreeAnnotationMessage(
            id: .generate(),
            threadID: thread.id,
            ordinal: 0,
            semanticRevision: 1,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
            savedBody: "message-\(index)",
            savedRevision: 1,
            draft: nil,
            handled: false,
            status: .editable
        )
    }

    private func makeDeltaFixture(
        contentCacheMaxBytes: Int = AppPolicies.Bridge.contentCacheMaxBytes
    ) async throws -> ProportionalSourceCaptureFixture {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let predecessorPackage = reviewPackage(itemCount: 2)
        let affectedItemID = predecessorPackage.orderedItemIds[0]
        let unaffectedItemID = predecessorPackage.orderedItemIds[1]
        let successorPackage = replacingReviewItem(
            in: predecessorPackage,
            itemId: affectedItemID,
            fileClass: .config,
            revision: predecessorPackage.revision + 1
        )
        let delta = try #require(
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: predecessorPackage,
                    nextPackage: successorPackage,
                    currentRevision: predecessorPackage.revision
                )
            )
        )
        let affectedHandle = try #require(
            successorPackage.itemsById[affectedItemID]?.contentRoles.head
        )
        let unaffectedHandle = try #require(
            successorPackage.itemsById[unaffectedItemID]?.contentRoles.head
        )
        let evictionHandle = makeBridgeContentHandle(
            itemId: "eviction-pressure",
            role: .head,
            reviewGeneration: successorPackage.reviewGeneration,
            contentHash: bridgeSHA256ContentHash("content")
        )
        let provider = reviewProvider(
            package: successorPackage,
            handles: [affectedHandle, unaffectedHandle, evictionHandle]
        )
        let cache = BridgeReviewContentLoaderCache(
            provider: provider,
            contentCacheMaxBytes: contentCacheMaxBytes
        )
        let coordinator = BridgeReviewPublicationCoordinator()
        let predecessor = try await commit(
            package: predecessorPackage,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        try acknowledge(
            predecessor,
            expectedPredecessorID: nil,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        let successor = try await commit(
            package: successorPackage,
            delta: delta,
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        return ProportionalSourceCaptureFixture(
            affectedHandle: affectedHandle,
            cache: cache,
            coordinator: coordinator,
            evictionHandle: evictionHandle,
            predecessor: predecessor,
            productAdmission: productAdmission.context,
            provider: provider,
            successor: successor,
            unaffectedHandle: unaffectedHandle
        )
    }

    private func capture(
        publication: BridgeReviewCommittedPublication,
        package: BridgeReviewPackage,
        coordinator: BridgeReviewPublicationCoordinator,
        cache: BridgeReviewContentLoaderCache,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationSourceRefreshCapture {
        try await WorktreeAnnotationSourceCapture.reviewRefresh(
            identity: try annotationIdentity(publication),
            publicationCoordinator: coordinator,
            contentLoaderCache: cache,
            requirements: try package.orderedItemIds.enumerated().map { index, itemID in
                try annotationRequirement(
                    item: #require(package.itemsById[itemID]),
                    threadIndex: index
                )
            },
            productAdmission: productAdmission
        )
    }

    private func annotationRequirement(
        item: BridgeReviewItemDescriptor,
        threadIndex: Int
    ) throws -> WorktreeAnnotationSourceRefreshRequirement {
        let handle = try #require(item.contentRoles.head)
        let path = try #require(item.headPath)
        return WorktreeAnnotationSourceRefreshRequirement(
            threadID: annotationThreadID(index: threadIndex),
            origin: .located(
                WorktreeAnnotationLocatedOrigin(
                    repositoryRelativePath: path,
                    startLine: 1,
                    endLine: 1,
                    sourceRole: .reviewHead,
                    diffSide: .additions,
                    sourceIdentity: handle.handleId,
                    selectedExcerpt: "content",
                    contextBefore: nil,
                    contextAfter: nil
                )
            )
        )
    }

    private func annotationThreadID(index: Int) -> WorktreeAnnotationThreadID {
        WorktreeAnnotationThreadID(
            rawValue: UUID(uuidString: String(format: "00000000-0000-7000-8000-%012d", index + 1))!
        )
    }

    private func finiteProjectionMessageContexts(
        _ capture: BridgeProductAnnotationProjectionCapture
    ) throws -> [UUID: BridgeProductWorktreeAnnotationThreadContext] {
        let analysis = try BridgeProductAnnotationProjectionRecordAnalysis(capture: capture)
        var contexts: [UUID: BridgeProductWorktreeAnnotationThreadContext] = [:]
        for pageOrdinal in 0..<analysis.pageCount {
            var cursor = try analysis.makePageCursor(pageOrdinal: pageOrdinal)
            while let batch = try cursor.nextEncodedBatch() {
                for line in batch.split(separator: 0x0A) {
                    let record = try JSONDecoder().decode(
                        BridgeProductAnnotationProjectionRecord.self,
                        from: Data(line)
                    )
                    guard case .message(let message) = record else { continue }
                    contexts[message.context.threadId] = message.context
                }
            }
        }
        return contexts
    }

    private func commit(
        package: BridgeReviewPackage,
        delta: BridgeReviewDelta? = nil,
        coordinator: BridgeReviewPublicationCoordinator,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewCommittedPublication {
        let prepared = try #require(
            await BridgeReviewPreparedPublication.prepare(
                BridgeReviewPublicationCandidate(
                    package: package,
                    delta: delta,
                    contentHandles: package.itemsById.values.flatMap(\.contentRoles.allHandles)
                )
            )
        )
        let token = try #require(coordinator.stage(prepared, productAdmission: productAdmission))
        guard
            case .committed(let publication) = coordinator.commit(
                token,
                productAdmission: productAdmission,
                captureCommittedPresentation: reviewCommittedPresentationSnapshot,
                presentCommitted: { _ in }
            )
        else { throw WorktreeAnnotationSourceResolutionError.unavailable }
        return publication
    }

    private func acknowledge(
        _ publication: BridgeReviewCommittedPublication,
        expectedPredecessorID: UUID?,
        coordinator: BridgeReviewPublicationCoordinator,
        productAdmission: BridgeProductAdmissionContext
    ) throws {
        let workerID = "review-proportional-source-capture-worker"
        guard
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: expectedPredecessorID,
                candidatePublicationId: publication.publicationId,
                workerInstanceId: workerID,
                productAdmission: productAdmission
            ) == .admitted,
            coordinator.recordDisplayedApplication(
                publicationId: publication.publicationId,
                workerInstanceId: workerID,
                productAdmission: productAdmission
            ) == .advanced
        else { throw WorktreeAnnotationSourceResolutionError.unavailable }
    }

    private func annotationIdentity(
        _ publication: BridgeReviewCommittedPublication
    ) throws -> BridgeProductReviewAnnotationPublicationIdentity {
        try BridgeProductReviewAnnotationPublicationIdentity(
            packageId: publication.package.packageId,
            publicationId: publication.publicationId,
            reviewGeneration: publication.package.reviewGeneration.rawValue,
            revision: publication.package.revision,
            sourceIdentity: publication.package.query.queryId
        )
    }

    private func demandedHeadHandles(_ package: BridgeReviewPackage) throws -> [BridgeContentHandle] {
        try package.orderedItemIds.map { itemID in
            try #require(package.itemsById[itemID]?.contentRoles.head)
        }
    }

    private func availableFileCount(_ capture: WorktreeAnnotationSourceRefreshCapture) throws -> Int {
        guard case .available(let files) = capture.material else {
            throw WorktreeAnnotationSourceResolutionError.unavailable
        }
        return files.count
    }

    private func reviewPackage(itemCount: Int) -> BridgeReviewPackage {
        makeReviewPackage(
            itemCount: itemCount,
            comparisonOrigin: .contribution(
                BridgeReviewContributionOrigin(
                    symbolicTarget: .branch(name: "main"),
                    resolvedTargetOID: "resolved-target-oid",
                    reviewedHeadOID: "committed-head-oid",
                    baseRole: .commonCommit,
                    baseOID: "base-oid"
                )
            )
        )
    }

    private func replacementReviewPackage(itemCount: Int) -> BridgeReviewPackage {
        let replacement = replacingReviewSource(
            reviewPackage(itemCount: itemCount),
            packageId: "replacement-package",
            queryId: "replacement-query",
            generation: 8
        )
        let itemsById = replacement.itemsById.mapValues { item in
            makeBridgeReviewItemDescriptor(
                itemId: item.itemId,
                path: item.headPath ?? item.basePath ?? item.itemId,
                fileClass: item.fileClass,
                contentRoles: .init(
                    head: makeBridgeContentHandle(
                        itemId: item.itemId,
                        role: .head,
                        endpointId: replacement.headEndpoint.endpointId,
                        reviewGeneration: replacement.reviewGeneration
                    )
                )
            )
        }
        return replacingReviewPackage(
            replacement,
            revision: replacement.revision,
            itemsById: itemsById
        )
    }

    private func reorderedReviewPackage(_ package: BridgeReviewPackage) -> BridgeReviewPackage {
        BridgeReviewPackage(
            packageId: package.packageId,
            schemaVersion: package.schemaVersion,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision + 1,
            query: package.query,
            baseEndpoint: package.baseEndpoint,
            headEndpoint: package.headEndpoint,
            orderedItemIds: Array(package.orderedItemIds.reversed()),
            itemsById: package.itemsById,
            groups: package.groups,
            summary: package.summary,
            filterState: package.filterState,
            generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds,
            changesetCluster: package.changesetCluster,
            comparisonOrigin: package.comparisonOrigin,
            reviewedSubjectLabel: package.reviewedSubjectLabel
        )
    }

    private func reviewProvider(
        package: BridgeReviewPackage,
        handles: [BridgeContentHandle]
    ) -> BridgeReviewSourceProviderFake {
        BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: package.baseEndpoint,
                headEndpoint: package.headEndpoint,
                changedFiles: []
            ),
            contentByHandleId: Dictionary(
                uniqueKeysWithValues: handles.map { handle in
                    (handle.handleId, makeContentResult(handle: handle, data: "content"))
                }
            )
        )
    }
}

private struct ProportionalSourceCaptureFixture {
    let affectedHandle: BridgeContentHandle
    let cache: BridgeReviewContentLoaderCache
    let coordinator: BridgeReviewPublicationCoordinator
    let evictionHandle: BridgeContentHandle
    let predecessor: BridgeReviewCommittedPublication
    let productAdmission: BridgeProductAdmissionContext
    let provider: BridgeReviewSourceProviderFake
    let successor: BridgeReviewCommittedPublication
    let unaffectedHandle: BridgeContentHandle
}

private struct PartialFailureEvaluationFixture {
    let placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
    let session: WorktreeAnnotationSession
    let threads: [WorktreeAnnotationThread]
}
