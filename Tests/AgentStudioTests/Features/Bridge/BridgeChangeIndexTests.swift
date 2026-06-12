import Foundation
import Testing

@testable import AgentStudio

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

        let firstDelta = try await index.ingestExplicitLoad(currentPackage)
        let secondDelta = try await index.ingestExplicitLoad(nextPackage)

        #expect(firstDelta == nil)
        let delta = try #require(secondDelta)
        #expect(delta.packageId == "package")
        #expect(delta.reviewGeneration == 4)
        #expect(delta.revision == 1)
        #expect(delta.operations.addItems.map(\.itemId) == ["item-new"])
        #expect(delta.operations.removeItems == ["item-old"])
        #expect(delta.operations.updateSummary?.additions == 2)
        let snapshot = await index.snapshot()
        #expect(snapshot.packageRevisionsById["package"] == 1)
        #expect(snapshot.packagesById["package"]?.revision == 1)
        #expect(snapshot.packagesById["package"]?.orderedItemIds == ["item-new"])
    }

    @Test("change index replaces newer generation package reloads without cross-generation deltas")
    func changeIndexReplacesNewerGenerationPackageReloads() async throws {
        let index = BridgeChangeIndex()
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

        let firstDelta = try await index.ingestExplicitLoad(currentPackage)
        let secondDelta = try await index.ingestExplicitLoad(nextPackage)

        #expect(firstDelta == nil)
        #expect(secondDelta == nil)
        let snapshot = await index.snapshot()
        #expect(snapshot.activeReviewGeneration == 5)
        #expect(snapshot.packageRevisionsById["package"] == 0)
        #expect(snapshot.packagesById["package"]?.orderedItemIds == ["item-new"])
    }

    @Test("change index drops stale generation package reloads")
    func changeIndexDropsStaleGenerationPackageReloads() async throws {
        let index = BridgeChangeIndex(activeReviewGeneration: 10)
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let stalePackage = makeBridgeReviewPackage(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 9
        )

        let delta = try await index.ingestExplicitLoad(stalePackage)

        #expect(delta == nil)
        let snapshot = await index.snapshot()
        #expect(snapshot.activeReviewGeneration == 10)
        #expect(snapshot.packagesById["package"] == nil)
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
