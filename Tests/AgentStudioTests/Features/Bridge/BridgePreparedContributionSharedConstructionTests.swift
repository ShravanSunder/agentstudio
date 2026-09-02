import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge prepared contribution shared construction")
struct BridgePreparedContributionSharedConstructionTests {
    @Test("content-only contribution capture advances metadata and retains demanded content")
    func contentOnlyContributionCaptureAdvancesMetadataAndRetainsDemandedContent() async throws {
        let predecessorContent = "head-a"
        let successorContent = "head-b"
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            contributionDiffSnapshot: contributionSnapshot(
                fileId: "app",
                path: "Sources/App.swift",
                oldContent: "base-a",
                newContent: predecessorContent
            )
        )
        defer { fixture.removeTestRoot() }
        let predecessorRequest = try await fixture.preparedContributionRequest(
            packageId: "contribution-a",
            generation: 1
        )
        let predecessor = try await fixture.firstBinder.acquire(predecessorRequest)
        let predecessorItem = try #require(predecessor.result.package.itemsById.values.first)
        let predecessorHandle = try #require(predecessorItem.contentRoles.head)
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let cache = BridgeReviewContentLoaderCache(provider: fixture.firstProvider)
        let demandedPredecessor = try await cache.load(
            handle: predecessorHandle,
            productAdmission: productAdmission.context
        )

        await fixture.gitClient.replaceContributionDiffSnapshot(
            contributionSnapshot(
                fileId: "app",
                path: "Sources/App.swift",
                oldContent: "base-a",
                newContent: successorContent
            )
        )
        await fixture.gitClient.replaceContent(
            gitContentPayload(successorContent),
            for: GitContentLocator(target: .workingTree, path: "Sources/App.swift")
        )
        let successorRequest = try await fixture.preparedContributionRequest(
            packageId: "contribution-b",
            generation: 2
        )

        let successor = try await fixture.firstBinder.acquire(successorRequest)
        let successorItem = try #require(successor.result.package.itemsById.values.first)
        let successorHandle = try #require(successorItem.contentRoles.head)
        let loadedPredecessor = try await cache.load(
            handle: predecessorHandle,
            productAdmission: productAdmission.context
        )
        let loadedSuccessor = try await cache.load(
            handle: successorHandle,
            productAdmission: productAdmission.context
        )

        #expect(
            predecessor.artifactPin.constructionLease.entryNonce
                != successor.artifactPin.constructionLease.entryNonce
        )
        #expect(predecessorItem.headContentHash == gitBlobSHA1ContentHash(predecessorContent))
        #expect(successorItem.headContentHash == gitBlobSHA1ContentHash(successorContent))
        #expect(demandedPredecessor.data == Data(predecessorContent.utf8))
        #expect(loadedPredecessor.data == Data(predecessorContent.utf8))
        #expect(loadedSuccessor.data == Data(successorContent.utf8))

        await cache.closeAndDrain()
        productAdmission.close()
        await successor.artifactPin.releaseAndWait()
        await predecessor.artifactPin.releaseAndWait()
        await assertPreparedContributionConstructionDrained(fixture)
    }

    @Test("membership and path-side contribution capture constructs fresh shared metadata")
    func membershipAndPathSideContributionCaptureConstructsFreshSharedMetadata() async throws {
        let predecessorPath = "Sources/App.swift"
        let successorPath = "Sources/New.swift"
        let predecessorContent = "head-a"
        let successorContent = "new-file"
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            contributionDiffSnapshot: contributionSnapshot(
                fileId: "app",
                path: predecessorPath,
                oldContent: "base-a",
                newContent: predecessorContent
            )
        )
        defer { fixture.removeTestRoot() }
        let predecessorRequest = try await fixture.preparedContributionRequest(
            packageId: "membership-a",
            generation: 1
        )
        let predecessor = try await fixture.firstBinder.acquire(predecessorRequest)
        let predecessorItem = try #require(predecessor.result.package.itemsById.values.first)
        let predecessorHandle = try #require(predecessorItem.contentRoles.head)

        await fixture.gitClient.replaceContributionDiffSnapshot(
            contributionSnapshot(
                fileId: "new",
                path: successorPath,
                oldContent: nil,
                newContent: successorContent,
                changeKind: .added
            )
        )
        await fixture.gitClient.replaceContent(
            gitContentPayload(successorContent),
            for: GitContentLocator(target: .workingTree, path: successorPath)
        )
        let successorRequest = try await fixture.preparedContributionRequest(
            packageId: "membership-b",
            generation: 2
        )

        let successor = try await fixture.firstBinder.acquire(successorRequest)
        let successorItem = try #require(successor.result.package.itemsById.values.first)
        let successorHandle = try #require(successorItem.contentRoles.head)
        let loadedPredecessor = try await fixture.firstProvider.loadContent(
            BridgeContentLoadRequest(handle: predecessorHandle, requestedGeneration: 1)
        )
        let loadedSuccessor = try await fixture.firstProvider.loadContent(
            BridgeContentLoadRequest(handle: successorHandle, requestedGeneration: 2)
        )

        #expect(
            predecessor.artifactPin.constructionLease.entryNonce
                != successor.artifactPin.constructionLease.entryNonce
        )
        #expect(predecessorItem.headPath == predecessorPath)
        #expect(successorItem.headPath == successorPath)
        #expect(predecessorItem.changeKind == .modified)
        #expect(successorItem.changeKind == .added)
        #expect(loadedPredecessor.data == Data(predecessorContent.utf8))
        #expect(loadedSuccessor.data == Data(successorContent.utf8))

        await successor.artifactPin.releaseAndWait()
        await predecessor.artifactPin.releaseAndWait()
        await assertPreparedContributionConstructionDrained(fixture)
    }
}

private func contributionSnapshot(
    fileId: String,
    path: String,
    oldContent: String?,
    newContent: String,
    changeKind: GitDiffChangeKind = .modified
) -> GitContributionDiffSnapshot {
    GitContributionDiffSnapshot(
        resolvedTarget: GitResolvedRevision(oid: "target-oid", shortName: "target"),
        reviewedHead: GitResolvedRevision(oid: "head-oid", shortName: "feature"),
        contributionBase: GitResolvedRevision(
            oid: String(repeating: "a", count: 40),
            shortName: nil
        ),
        diff: GitDiffSnapshot(
            files: [
                GitDiffFile(
                    fileId: fileId,
                    path: path,
                    previousPath: nil,
                    changeKind: changeKind,
                    oldContentHash: oldContent.map(gitBlobSHA1ContentHash),
                    newContentHash: gitBlobSHA1ContentHash(newContent),
                    contentHashAlgorithm: "git-blob-sha1",
                    oldMode: oldContent == nil ? nil : 0o100644,
                    newMode: 0o100644,
                    additions: 1,
                    deletions: oldContent == nil ? 0 : 1,
                    isBinary: false,
                    sizeBytes: Int64(newContent.utf8.count)
                )
            ]
        )
    )
}

private func assertPreparedContributionConstructionDrained(
    _ fixture: BridgeSharedReviewConstructionFixture
) async {
    await fixture.waitUntilConstructionEntryIsRemoved()
    let snapshot = await fixture.coordinator.snapshot()
    #expect(snapshot.entryCount == 0)
    #expect(snapshot.leaseCount == 0)
    #expect(snapshot.payloadCount == 0)
    #expect(snapshot.locatorCount == 0)
    #expect(snapshot.retainedArtifactByteCount == 0)
    #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
}
