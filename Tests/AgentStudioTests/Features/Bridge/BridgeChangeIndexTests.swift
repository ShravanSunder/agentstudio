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
    reviewGeneration: BridgeReviewGeneration
) -> BridgeReviewPackage {
    BridgeReviewPackage(
        packageId: "package",
        schemaVersion: 1,
        reviewGeneration: reviewGeneration,
        query: makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        ),
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        orderedItemIds: [],
        itemsById: [:],
        groups: [],
        summary: BridgeReviewPackageSummary(
            filesChanged: 0,
            additions: 0,
            deletions: 0,
            visibleFileCount: 0,
            hiddenFileCount: 0
        ),
        filterState: BridgeViewFilter(),
        generatedAtUnixMilliseconds: 200
    )
}
