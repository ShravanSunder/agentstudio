import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgeChangeIndexTests {
    @Test("change index records endpoints checkpoints package revisions and generation")
    func changeIndexRecordsEndpointsCheckpointsPackageRevisionsAndGeneration() async throws {
        let index = BridgeChangeIndex()
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .promptCheckpoint)
        let checkpoint = makeBridgeReviewCheckpoint(
            checkpointId: "checkpoint-prompt",
            checkpointKind: .prompt,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 3
        )

        await index.recordEndpoint(baseEndpoint)
        await index.recordCheckpoint(checkpoint)
        await index.recordPackage(
            makeBridgeReviewPackage(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                reviewGeneration: 4
            ),
            revision: 1
        )
        await index.recordDelta(
            BridgeReviewDelta(
                packageId: "package",
                reviewGeneration: 4,
                revision: 2,
                operations: BridgeReviewDelta.Operations()
            )
        )

        let snapshot = await index.snapshot()

        #expect(snapshot.activeReviewGeneration == 4)
        #expect(snapshot.endpointsById["base"] == baseEndpoint)
        #expect(snapshot.checkpointsById["checkpoint-prompt"] == checkpoint)
        #expect(snapshot.packageRevisionsById["package"] == 2)
        #expect(snapshot.packagesById["package"]?.packageId == "package")
        #expect(await index.checkpointIds(kind: .prompt) == ["checkpoint-prompt"])
    }

    @Test("change index advances review generations monotonically")
    func changeIndexAdvancesReviewGenerationsMonotonically() async {
        let index = BridgeChangeIndex(activeReviewGeneration: 10)

        let firstGeneration = await index.nextReviewGeneration()
        let secondGeneration = await index.nextReviewGeneration()

        #expect(firstGeneration == 11)
        #expect(secondGeneration == 12)
    }

    @Test("change index builds deltas for explicit package reloads")
    func changeIndexBuildsDeltasForExplicitPackageReloads() async throws {
        let index = BridgeChangeIndex()
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let currentPackage = makeBridgeReviewPackage(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 4,
            orderedItemIds: ["item-old"],
            summary: BridgeReviewPackageSummary(
                filesChanged: 1,
                additions: 1,
                deletions: 1,
                visibleFileCount: 1,
                hiddenFileCount: 0
            )
        )
        let nextPackage = makeBridgeReviewPackage(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 4,
            orderedItemIds: ["item-new"],
            summary: BridgeReviewPackageSummary(
                filesChanged: 1,
                additions: 2,
                deletions: 0,
                visibleFileCount: 1,
                hiddenFileCount: 0
            )
        )

        let firstLoad = try await index.prepareExplicitLoad(
            currentPackage,
            productAdmission: productAdmission
        )
        #expect(await index.snapshot().packagesById.isEmpty)
        #expect(await index.recordCommittedLoad(firstLoad, productAdmission: productAdmission))
        let secondLoad = try await index.prepareExplicitLoad(
            nextPackage,
            productAdmission: productAdmission
        )
        let snapshotBeforeSecondCommit = await index.snapshot()
        #expect(await index.recordCommittedLoad(secondLoad, productAdmission: productAdmission))

        #expect(firstLoad.delta == nil)
        let delta = try #require(secondLoad.delta)
        #expect(delta.packageId == "package")
        #expect(delta.reviewGeneration == 4)
        #expect(delta.revision == 1)
        #expect(delta.operations.addItems.map(\.itemId) == ["item-new"])
        #expect(delta.operations.removeItems == ["item-old"])
        #expect(delta.operations.updateSummary?.additions == 2)
        #expect(snapshotBeforeSecondCommit.packagesById["package"]?.orderedItemIds == ["item-old"])
        let snapshot = await index.snapshot()
        #expect(snapshot.packageRevisionsById["package"] == 1)
        #expect(snapshot.packagesById["package"]?.revision == 1)
        #expect(snapshot.packagesById["package"]?.orderedItemIds == ["item-new"])
    }

    @Test("origin-only same-lineage movement advances revision without an item delta")
    func originOnlySameLineageMovementAdvancesRevisionWithoutItemDelta() async throws {
        let index = BridgeChangeIndex()
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let currentBase = bridgeChangeIndexEndpoint(
            endpointId: "base",
            kind: .gitRef,
            providerIdentity: "base-a"
        )
        let successorBase = bridgeChangeIndexEndpoint(
            endpointId: "base",
            kind: .gitRef,
            providerIdentity: "base-b"
        )
        let head = bridgeChangeIndexEndpoint(
            endpointId: "working-tree",
            kind: .workingTree,
            providerIdentity: "working-tree"
        )
        let current = replacingBridgeChangeIndexAuthority(
            in: makeBridgeReviewPackage(
                baseEndpoint: currentBase,
                headEndpoint: head,
                reviewGeneration: 7,
                orderedItemIds: ["item"]
            ),
            baseEndpoint: currentBase,
            resolvedTargetOID: "target-a"
        )
        let successor = replacingBridgeChangeIndexAuthority(
            in: current,
            baseEndpoint: successorBase,
            resolvedTargetOID: "target-b"
        )
        let initialLoad = try await index.prepareExplicitLoad(
            current,
            productAdmission: productAdmission
        )
        #expect(await index.recordCommittedLoad(initialLoad, productAdmission: productAdmission))

        let prepared = try await index.prepareExplicitLoad(
            successor,
            fallbackRevision: current.revision,
            productAdmission: productAdmission
        )

        #expect(prepared.delta == nil)
        #expect(prepared.package.reviewGeneration == current.reviewGeneration)
        #expect(prepared.package.revision == current.revision + 1)
        #expect(prepared.package.comparisonOrigin == successor.comparisonOrigin)
        #expect(prepared.package.orderedItemIds == current.orderedItemIds)
        #expect(prepared.package.itemsById == current.itemsById)
    }

    @Test("change index replaces newer generation package reloads without cross-generation deltas")
    func changeIndexReplacesNewerGenerationPackageReloads() async throws {
        let index = BridgeChangeIndex()
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let currentPackage = makeBridgeReviewPackage(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 4,
            orderedItemIds: ["item-old"]
        )
        let nextPackage = makeBridgeReviewPackage(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 5,
            orderedItemIds: ["item-new"]
        )

        let firstLoad = try await index.prepareExplicitLoad(
            currentPackage,
            productAdmission: productAdmission
        )
        #expect(await index.recordCommittedLoad(firstLoad, productAdmission: productAdmission))
        let secondLoad = try await index.prepareExplicitLoad(
            nextPackage,
            productAdmission: productAdmission
        )
        #expect(await index.recordCommittedLoad(secondLoad, productAdmission: productAdmission))

        #expect(firstLoad.delta == nil)
        #expect(secondLoad.delta == nil)
        let snapshot = await index.snapshot()
        #expect(snapshot.activeReviewGeneration == 5)
        #expect(snapshot.packageRevisionsById["package"] == 0)
        #expect(snapshot.packagesById["package"]?.orderedItemIds == ["item-new"])
    }

    @Test("change index drops stale generation package reloads")
    func changeIndexDropsStaleGenerationPackageReloads() async throws {
        let index = BridgeChangeIndex(activeReviewGeneration: 10)
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let stalePackage = makeBridgeReviewPackage(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 9
        )

        let preparedLoad = try await index.prepareExplicitLoad(
            stalePackage,
            productAdmission: productAdmission
        )

        #expect(preparedLoad.delta == nil)
        let snapshot = await index.snapshot()
        #expect(snapshot.activeReviewGeneration == 10)
        #expect(snapshot.packagesById["package"] == nil)
    }

    @Test("change index rejects closed admission without mutating its snapshot")
    func changeIndexRejectsClosedAdmissionWithoutMutatingItsSnapshot() async throws {
        let index = BridgeChangeIndex()
        let productAdmissionGate = BridgeProductAdmissionGate()
        let productAdmission = try #require(productAdmissionGate.acquire())
        let package = makeBridgeReviewPackage(
            baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
            headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
            reviewGeneration: 1,
            orderedItemIds: ["item"]
        )
        let beforeClose = await index.snapshot()

        productAdmissionGate.close()

        await #expect(throws: BridgeChangeIndexError.admissionClosed) {
            try await index.prepareExplicitLoad(
                package,
                productAdmission: productAdmission
            )
        }
        #expect(await index.snapshot() == beforeClose)
    }

    @Test("closed admission suppresses post-commit index recording without mutation")
    func closedAdmissionSuppressesPostCommitRecordingWithoutMutation() async throws {
        let index = BridgeChangeIndex()
        let productAdmissionGate = BridgeProductAdmissionGate()
        let productAdmission = try #require(productAdmissionGate.acquire())
        let package = makeBridgeReviewPackage(
            baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
            headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
            reviewGeneration: 1,
            orderedItemIds: ["item"]
        )
        let preparedLoad = try await index.prepareExplicitLoad(
            package,
            productAdmission: productAdmission
        )
        let beforeClose = await index.snapshot()

        productAdmissionGate.close()
        let wasRecorded = await index.recordCommittedLoad(
            preparedLoad,
            productAdmission: productAdmission
        )

        #expect(!wasRecorded)
        #expect(await index.snapshot() == beforeClose)
    }
}

private func makeBridgeReviewCheckpoint(
    checkpointId: String,
    checkpointKind: BridgeReviewCheckpoint.Kind,
    baseEndpoint: BridgeSourceEndpoint,
    headEndpoint: BridgeSourceEndpoint,
    reviewGeneration: BridgeReviewGeneration
) -> BridgeReviewCheckpoint {
    BridgeReviewCheckpoint(
        checkpointId: checkpointId,
        checkpointKind: checkpointKind,
        repoId: baseEndpoint.repoId,
        worktreeId: baseEndpoint.worktreeId,
        paneId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        createdAtUnixMilliseconds: 100,
        reviewGeneration: reviewGeneration,
        baseEndpointId: baseEndpoint.endpointId,
        headEndpointId: headEndpoint.endpointId,
        eventSequenceStart: 1,
        eventSequenceEnd: 2,
        batchSequenceStart: 1,
        batchSequenceEnd: 1,
        contentSetHash: headEndpoint.contentSetHash ?? "sha256:head",
        agentSessionId: "session",
        promptId: "prompt",
        summary: "Prompt checkpoint"
    )
}

private func makeBridgeReviewPackage(
    baseEndpoint: BridgeSourceEndpoint,
    headEndpoint: BridgeSourceEndpoint,
    reviewGeneration: BridgeReviewGeneration,
    orderedItemIds: [String] = [],
    summary: BridgeReviewPackageSummary? = nil
) -> BridgeReviewPackage {
    let itemsById = Dictionary(
        uniqueKeysWithValues: orderedItemIds.map { itemId in
            (
                itemId,
                makeBridgeReviewItemDescriptor(
                    itemId: itemId,
                    path: "\(itemId).swift",
                    fileClass: .source
                )
            )
        }
    )
    let resolvedSummary =
        summary
        ?? BridgeReviewPackageSummary(
            filesChanged: orderedItemIds.count,
            additions: 0,
            deletions: 0,
            visibleFileCount: orderedItemIds.count,
            hiddenFileCount: 0
        )
    return BridgeReviewPackage(
        packageId: "package",
        schemaVersion: 1,
        reviewGeneration: reviewGeneration,
        revision: 0,
        query: makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        ),
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        orderedItemIds: orderedItemIds,
        itemsById: itemsById,
        groups: [],
        summary: resolvedSummary,
        filterState: BridgeViewFilter(),
        generatedAtUnixMilliseconds: 200
    )
}

private func bridgeChangeIndexEndpoint(
    endpointId: String,
    kind: BridgeSourceEndpoint.Kind,
    providerIdentity: String
) -> BridgeSourceEndpoint {
    BridgeSourceEndpoint(
        endpointId: endpointId,
        kind: kind,
        repoId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        worktreeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        label: endpointId,
        createdAtUnixMilliseconds: 1,
        contentSetHash: providerIdentity,
        providerIdentity: providerIdentity
    )
}

private func replacingBridgeChangeIndexAuthority(
    in package: BridgeReviewPackage,
    baseEndpoint: BridgeSourceEndpoint,
    resolvedTargetOID: String
) -> BridgeReviewPackage {
    BridgeReviewPackage(
        packageId: package.packageId,
        schemaVersion: package.schemaVersion,
        reviewGeneration: package.reviewGeneration,
        revision: package.revision,
        query: package.query,
        baseEndpoint: baseEndpoint,
        headEndpoint: package.headEndpoint,
        orderedItemIds: package.orderedItemIds,
        itemsById: package.itemsById,
        groups: package.groups,
        summary: package.summary,
        filterState: package.filterState,
        generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds,
        changesetCluster: package.changesetCluster,
        comparisonOrigin: .contribution(
            BridgeReviewContributionOrigin(
                symbolicTarget: .branch(name: "main"),
                resolvedTargetOID: resolvedTargetOID,
                reviewedHeadOID: "head",
                baseRole: .commonCommit,
                baseOID: "base"
            )
        ),
        reviewedSubjectLabel: package.reviewedSubjectLabel
    )
}
