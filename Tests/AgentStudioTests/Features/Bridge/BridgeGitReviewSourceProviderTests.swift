import AgentStudioGit
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

struct BridgeGitReviewSourceProviderTests {
    @Test("AgentStudioGit adapter maps diff metadata and lazily loads Bridge content handles")
    func agentStudioGitAdapterMapsDiffMetadataAndLazilyLoadsBridgeContentHandles() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-adapter-test")
        let filePath = "Sources/App/View.swift"
        let baseContent = "old source"
        let headContent = "new source"
        let baseEndpoint = makeBridgeEndpoint(endpointId: "abc123", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working", kind: .workingTree)
        let gitClient = AgentStudioGitLocalClientFake(
            diffSnapshot: GitDiffSnapshot(
                files: [
                    GitDiffFile(
                        fileId: "source",
                        path: filePath,
                        previousPath: nil,
                        changeKind: .modified,
                        oldContentHash: gitBlobSHA1ContentHash(baseContent),
                        newContentHash: gitBlobSHA1ContentHash(headContent),
                        contentHashAlgorithm: "git-blob-sha1",
                        oldMode: nil,
                        newMode: nil,
                        additions: 1,
                        deletions: 1,
                        isBinary: false,
                        sizeBytes: Int64(headContent.utf8.count)
                    )
                ]
            ),
            contentByLocator: [
                GitContentLocator(target: .commit("abc123"), path: filePath): gitContentPayload(baseContent),
                GitContentLocator(target: .workingTree, path: filePath): gitContentPayload(headContent),
            ]
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient
        )
        let provider = BridgeGitReviewSourceProvider(client: adapter)
        let query = makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        )

        let comparison = try await provider.compareEndpoints(
            BridgeEndpointComparisonRequest(
                query: query,
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                reviewGeneration: 9
            )
        )
        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package",
                query: query,
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 9,
                generatedAtUnixMilliseconds: 10
            )
        )
        let item = try #require(package.itemsById["item-source"])
        let headHandle = try #require(item.contentRoles.head)
        let contentStore = BridgeContentStore(provider: provider)

        await contentStore.activate(
            handles: package.itemsById.values.flatMap(\.contentRoles.allHandles),
            reviewGeneration: 9
        )
        let loadedContent = try await contentStore.load(
            handleId: headHandle.handleId,
            requestedGeneration: 9
        )

        #expect(comparison.changedFiles.first?.path == filePath)
        #expect(comparison.changedFiles.first?.oldContentHash == gitBlobSHA1ContentHash(baseContent))
        #expect(comparison.changedFiles.first?.newContentHash == gitBlobSHA1ContentHash(headContent))
        #expect(comparison.changedFiles.first?.contentHashAlgorithm == "git-blob-sha1")
        #expect(!headHandle.handleId.contains("/"))
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                headHandle.resourceUrl,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        #expect(BridgeSchemeHandler.classifyPath(headHandle.resourceUrl) == .leasedContent(resource))
        #expect(loadedContent.data == Data(headContent.utf8))
        #expect(loadedContent.contentHash == gitBlobSHA1ContentHash(headContent))
        #expect(loadedContent.contentHashAlgorithm == "git-blob-sha1")
        #expect(
            await gitClient.recordedDiffRequests() == [
                GitDiffRequest(repositoryPath: repositoryPath, base: .commit("abc123"), compare: .workingTree)
            ]
        )
        #expect(
            await gitClient.recordedContentRequests() == [
                GitContentRequest(
                    repositoryPath: repositoryPath,
                    target: .workingTree,
                    path: filePath,
                    maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                )
            ]
        )
    }

    @Test("AgentStudioGit adapter reads every git-ref tree path scope")
    func agentStudioGitAdapterReadsEveryGitRefTreePathScope() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-tree-test")
        let endpoint = makeBridgeEndpoint(endpointId: "abc123", kind: .gitRef)
        let sourcesRequest = GitTreeReadRequest(
            repositoryPath: repositoryPath,
            revision: .named("abc123"),
            path: "Sources"
        )
        let testsRequest = GitTreeReadRequest(
            repositoryPath: repositoryPath,
            revision: .named("abc123"),
            path: "Tests"
        )
        let gitClient = AgentStudioGitLocalClientFake(
            treeSnapshotByRequest: [
                sourcesRequest: gitTreeSnapshot(path: "Sources/App/View.swift", oid: "source-oid"),
                testsRequest: gitTreeSnapshot(path: "Tests/App/ViewTests.swift", oid: "test-oid"),
            ]
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient
        )
        let provider = BridgeGitReviewSourceProvider(client: adapter)

        let result = try await provider.readTree(
            BridgeTreeReadRequest(
                endpoint: endpoint,
                pathScope: ["Sources", "Tests"],
                reviewGeneration: 3
            )
        )

        #expect(result.descriptors.map(\.headPath) == ["Sources/App/View.swift", "Tests/App/ViewTests.swift"])
        #expect(await gitClient.recordedTreeRequests() == [sourcesRequest, testsRequest])
    }

    @Test("AgentStudioGit adapter rejects tree reads for non-revision endpoint kinds")
    func agentStudioGitAdapterRejectsTreeReadsForNonRevisionEndpointKinds() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-tree-test")
        let endpoint = makeBridgeEndpoint(endpointId: "working", kind: .workingTree)
        let gitClient = AgentStudioGitLocalClientFake()
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient
        )
        let provider = BridgeGitReviewSourceProvider(client: adapter)

        await #expect(throws: BridgeProviderFailure.self) {
            try await provider.readTree(
                BridgeTreeReadRequest(
                    endpoint: endpoint,
                    pathScope: [],
                    reviewGeneration: 3
                )
            )
        }
        #expect(await gitClient.recordedTreeRequests().isEmpty)
    }

    @Test("AgentStudioGit adapter returns hidden large descriptor when open file content exceeds the cap")
    func agentStudioGitAdapterReturnsLargeDescriptorWhenOpenFileContentExceedsCap() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-large-file-test")
        let endpoint = makeBridgeEndpoint(endpointId: "working", kind: .workingTree)
        let filePath = "Sources/App/LargeView.swift"
        let locator = GitContentLocator(target: .workingTree, path: filePath)
        let gitClient = AgentStudioGitLocalClientFake(
            contentFailureByLocator: [
                locator: .contentTooLarge(
                    path: filePath,
                    sizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem + 1),
                    maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                )
            ]
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient
        )
        let provider = BridgeGitReviewSourceProvider(client: adapter)

        let descriptor = try await provider.readReviewItemDescriptor(
            BridgeReviewItemDescriptorRequest(
                endpoint: endpoint,
                path: filePath,
                reviewGeneration: 4
            )
        )

        #expect(descriptor.fileClass == .large)
        #expect(descriptor.isHiddenByDefault)
        #expect(descriptor.contentRoles.allHandles.isEmpty)
        #expect(descriptor.sizeBytes == AppPolicies.Bridge.contentMaxBytesPerItem + 1)
        #expect(
            await gitClient.recordedContentRequests() == [
                GitContentRequest(
                    repositoryPath: repositoryPath,
                    target: .workingTree,
                    path: filePath,
                    maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                )
            ]
        )
    }

    @Test("AgentStudioGit adapter prunes stale content locators when review generation advances")
    func agentStudioGitAdapterPrunesStaleContentLocatorsWhenReviewGenerationAdvances() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-adapter-prune-test")
        let filePath = "Sources/App/View.swift"
        let headContent = "new source"
        let baseEndpoint = makeBridgeEndpoint(endpointId: "abc123", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working", kind: .workingTree)
        let changedFile = GitDiffFile(
            fileId: "source",
            path: filePath,
            previousPath: nil,
            changeKind: .modified,
            oldContentHash: gitBlobSHA1ContentHash("old source"),
            newContentHash: gitBlobSHA1ContentHash(headContent),
            contentHashAlgorithm: "git-blob-sha1",
            oldMode: nil,
            newMode: nil,
            additions: 1,
            deletions: 1,
            isBinary: false,
            sizeBytes: Int64(headContent.utf8.count)
        )
        let gitClient = AgentStudioGitLocalClientFake(
            diffSnapshot: GitDiffSnapshot(files: [changedFile]),
            contentByLocator: [
                GitContentLocator(target: .workingTree, path: filePath): gitContentPayload(headContent)
            ]
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient
        )
        let provider = BridgeGitReviewSourceProvider(client: adapter)
        let query = makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        )

        let generationOnePackage = try await buildPackage(
            provider: provider,
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 1
        )
        let staleHandle = try #require(generationOnePackage.itemsById["item-source"]?.contentRoles.head)
        let generationTwoPackage = try await buildPackage(
            provider: provider,
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: 2
        )
        let currentHandle = try #require(generationTwoPackage.itemsById["item-source"]?.contentRoles.head)

        await #expect(throws: BridgeProviderFailure.self) {
            try await provider.loadContent(
                BridgeContentLoadRequest(handle: staleHandle, requestedGeneration: 1)
            )
        }
        let currentContent = try await provider.loadContent(
            BridgeContentLoadRequest(handle: currentHandle, requestedGeneration: 2)
        )

        #expect(currentContent.data == Data(headContent.utf8))
    }

    @Test("git review source provider forwards through backend-neutral client")
    func gitReviewSourceProviderForwardsThroughBackendNeutralClient() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100
        )
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [changedFile]
        )
        let client = BridgeGitReviewDataClientFake(comparison: comparison)
        let provider = BridgeGitReviewSourceProvider(client: client)
        let query = makeBridgeReviewQuery()

        let result = try await provider.compareEndpoints(
            BridgeEndpointComparisonRequest(
                query: query,
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                reviewGeneration: 1
            )
        )

        #expect(result == comparison)
        #expect(await client.recordedComparisonRequestsCount() == 1)
    }

    @Test("git review source provider preserves content handle identity")
    func gitReviewSourceProviderPreservesContentHandleIdentity() async throws {
        let handle = makeBridgeContentHandle(itemId: "item-source", role: .head, reviewGeneration: 2)
        let expectedResult = makeContentResult(handle: handle, data: "content")
        let client = BridgeGitReviewDataClientFake(contentResult: expectedResult)
        let provider = BridgeGitReviewSourceProvider(client: client)

        let result = try await provider.loadContent(
            BridgeContentLoadRequest(handle: handle, requestedGeneration: 2)
        )

        #expect(result == expectedResult)
        #expect(await client.recordedContentRequestsCount() == 1)
    }
}

private struct GitContentLocator: Hashable, Sendable {
    let target: GitDiffTarget
    let path: String
}

private func gitTreeSnapshot(path: String, oid: String) -> GitTreeSnapshot {
    GitTreeSnapshot(
        revision: GitResolvedRevision(oid: "abc123", shortName: nil),
        entries: [
            GitTreeEntry(
                path: path,
                oid: oid,
                mode: 0o100644,
                isTree: false,
                sizeBytes: 100
            )
        ]
    )
}

private func gitContentPayload(_ content: String) -> GitContentPayload {
    GitContentPayload(
        data: Data(content.utf8),
        contentHash: bridgeSHA256ContentHash(content),
        contentHashAlgorithm: "sha256",
        isBinary: false
    )
}

private func gitBlobSHA1ContentHash(_ content: String) -> String {
    let data = Data(content.utf8)
    var blobData = Data("blob \(data.count)\0".utf8)
    blobData.append(data)
    return Insecure.SHA1.hash(data: blobData).map { String(format: "%02x", $0) }.joined()
}

private actor AgentStudioGitLocalClientFake: AgentStudioGitLocalClient {
    private let diffSnapshot: GitDiffSnapshot
    private let contentByLocator: [GitContentLocator: GitContentPayload]
    private let contentFailureByLocator: [GitContentLocator: GitDataPlaneError]
    private let treeSnapshotByRequest: [GitTreeReadRequest: GitTreeSnapshot]
    private var diffRequests: [GitDiffRequest] = []
    private var contentRequests: [GitContentRequest] = []
    private var treeRequests: [GitTreeReadRequest] = []

    init(
        diffSnapshot: GitDiffSnapshot = GitDiffSnapshot(files: []),
        contentByLocator: [GitContentLocator: GitContentPayload] = [:],
        contentFailureByLocator: [GitContentLocator: GitDataPlaneError] = [:],
        treeSnapshotByRequest: [GitTreeReadRequest: GitTreeSnapshot] = [:]
    ) {
        self.diffSnapshot = diffSnapshot
        self.contentByLocator = contentByLocator
        self.contentFailureByLocator = contentFailureByLocator
        self.treeSnapshotByRequest = treeSnapshotByRequest
    }

    func repositoryIdentity(for worktreePath: URL) async throws(GitDataPlaneError) -> GitRepositoryIdentity {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func worktrees(for repositoryPath: URL) async throws(GitDataPlaneError) -> [GitWorktreeSnapshot] {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func validateWorktree(_ request: GitValidateWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeValidation
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func pruneStaleWorktree(_ request: GitPruneStaleWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreePruneResult
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func removeWorktree(_ request: GitRemoveWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeRemovalResult
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func lockWorktree(_ request: GitLockWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func unlockWorktree(_ request: GitUnlockWorktreeRequest) async throws(GitDataPlaneError)
        -> GitWorktreeSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func status(for worktreePath: URL, options: GitStatusOptions) async throws(GitDataPlaneError)
        -> GitStatusSnapshot
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func branches(for repositoryPath: URL) async throws(GitDataPlaneError) -> [GitBranchSnapshot] {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func resolveRevision(_ request: GitRevisionResolutionRequest) async throws(GitDataPlaneError)
        -> GitResolvedRevision
    {
        throw GitDataPlaneError.unsupported(message: "not used")
    }

    func readTree(_ request: GitTreeReadRequest) async throws(GitDataPlaneError) -> GitTreeSnapshot {
        treeRequests.append(request)
        guard let treeSnapshot = treeSnapshotByRequest[request] else {
            throw GitDataPlaneError.unsupported(message: "missing tree for \(request.path ?? "<root>")")
        }
        return treeSnapshot
    }

    func diff(_ request: GitDiffRequest) async throws(GitDataPlaneError) -> GitDiffSnapshot {
        diffRequests.append(request)
        return diffSnapshot
    }

    func content(_ request: GitContentRequest) async throws(GitDataPlaneError) -> GitContentPayload {
        contentRequests.append(request)
        let locator = GitContentLocator(target: request.target, path: request.path)
        if let failure = contentFailureByLocator[locator] {
            throw failure
        }
        guard let content = contentByLocator[locator] else {
            throw GitDataPlaneError.unsupported(message: "missing content for \(request.path)")
        }
        return content
    }

    func recordedDiffRequests() -> [GitDiffRequest] {
        diffRequests
    }

    func recordedContentRequests() -> [GitContentRequest] {
        contentRequests
    }

    func recordedTreeRequests() -> [GitTreeReadRequest] {
        treeRequests
    }
}

private func buildPackage(
    provider: BridgeGitReviewSourceProvider,
    query: BridgeReviewQuery,
    baseEndpoint: BridgeSourceEndpoint,
    headEndpoint: BridgeSourceEndpoint,
    reviewGeneration: BridgeReviewGeneration
) async throws -> BridgeReviewPackage {
    let comparison = try await provider.compareEndpoints(
        BridgeEndpointComparisonRequest(
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: reviewGeneration
        )
    )
    return try BridgeReviewPackageBuilder.build(
        request: BridgeReviewPackageBuildRequest(
            packageId: "package-\(reviewGeneration.rawValue)",
            query: query,
            comparison: comparison,
            checkpointIds: [],
            reviewGeneration: reviewGeneration,
            generatedAtUnixMilliseconds: Int64(reviewGeneration.rawValue)
        )
    )
}

private actor BridgeGitReviewDataClientFake: BridgeGitReviewDataClient {
    private let comparison: BridgeEndpointComparison?
    private let contentResult: BridgeContentLoadResult?
    private var comparisonRequests: [BridgeEndpointComparisonRequest] = []
    private var contentRequests: [BridgeContentLoadRequest] = []

    init(
        comparison: BridgeEndpointComparison? = nil,
        contentResult: BridgeContentLoadResult? = nil
    ) {
        self.comparison = comparison
        self.contentResult = contentResult
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        request.endpoint
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        comparisonRequests.append(request)
        if let comparison {
            return comparison
        }
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: []
        )
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        BridgeTreeReadResult(endpoint: request.endpoint, descriptors: [])
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        makeBridgeReviewItemDescriptor(itemId: "item-\(request.path)", path: request.path, fileClass: .source)
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint {
        makeBridgeEndpoint(endpointId: request.checkpointId, kind: .promptCheckpoint)
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        contentRequests.append(request)
        if let contentResult {
            return contentResult
        }
        throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
    }

    func recordedComparisonRequestsCount() -> Int {
        comparisonRequests.count
    }

    func recordedContentRequestsCount() -> Int {
        contentRequests.count
    }
}
