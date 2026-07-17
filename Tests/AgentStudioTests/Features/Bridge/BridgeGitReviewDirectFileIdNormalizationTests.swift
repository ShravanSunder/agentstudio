import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio

struct BridgeGitReviewDirectFileIdNormalizationTests {
    @Test("direct Git diff file IDs are deterministic wire-safe and bounded")
    func directGitDiffFileIdsAreDeterministicWireSafeAndBounded() async throws {
        // Arrange
        let safeFileId = "source-1"
        let nestedFileId = "Sources/App/View.swift"
        let otherNestedFileId = "Sources/App/Other.swift"
        let overlengthFileId = String(repeating: "x", count: 124)
        let gitClient = AgentStudioGitLocalClientFake(
            diffSnapshot: GitDiffSnapshot(
                files: [
                    directGitDiffFile(fileId: safeFileId, path: "Sources/Safe.swift"),
                    directGitDiffFile(fileId: nestedFileId, path: "Sources/App/View.swift"),
                    directGitDiffFile(fileId: overlengthFileId, path: "Sources/App/Large.swift"),
                    directGitDiffFile(fileId: nestedFileId, path: "Sources/App/ViewCopy.swift"),
                    directGitDiffFile(fileId: otherNestedFileId, path: "Sources/App/Other.swift"),
                ]
            )
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: URL(fileURLWithPath: "/tmp/agentstudio-git-direct-id-test"),
            client: gitClient
        )
        let request = BridgeEndpointComparisonRequest(
            query: makeBridgeReviewQuery(baseEndpointId: "base", headEndpointId: "working"),
            baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
            headEndpoint: makeBridgeEndpoint(endpointId: "working", kind: .workingTree),
            reviewGeneration: 1
        )

        // Act
        let firstComparison = try await adapter.compareEndpoints(request)
        let secondComparison = try await adapter.compareEndpoints(request)
        let firstIds = firstComparison.changedFiles.map(\.fileId)
        let secondIds = secondComparison.changedFiles.map(\.fileId)

        // Assert
        #expect(firstIds == secondIds)
        #expect(firstIds[0] == safeFileId)
        #expect(firstIds[1] == firstIds[3])
        #expect(firstIds[1] != firstIds[4])
        #expect(firstIds[1].hasPrefix("git-diff-"))
        #expect(firstIds[2].hasPrefix("git-diff-"))
        #expect(firstIds[1].utf8.count == 73)
        #expect(firstIds[2].utf8.count == 73)
        for fileId in firstIds {
            #expect(fileId.utf8.count <= 123)
            try BridgeProductContractDecoding.validateIdentifier(
                "item-\(fileId)",
                codingPath: []
            )
        }
    }
}

private func directGitDiffFile(fileId: String, path: String) -> GitDiffFile {
    GitDiffFile(
        fileId: fileId,
        path: path,
        previousPath: nil,
        changeKind: .modified,
        oldContentHash: "sha1:old",
        newContentHash: "sha1:new",
        contentHashAlgorithm: "git-blob-sha1",
        oldMode: nil,
        newMode: nil,
        additions: 1,
        deletions: 1,
        isBinary: false,
        sizeBytes: 10
    )
}
