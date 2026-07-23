import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio

struct BridgeGitReviewBoundaryTests {
    @Test("AgentStudioGit adapter preserves gitlink modes and omits gitlink locators")
    func agentStudioGitAdapterPreservesGitlinkModesAndOmitsGitlinkLocators() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-gitlink-adapter-test")
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let gitClient = AgentStudioGitLocalClientFake(
            diffSnapshot: GitDiffSnapshot(
                files: [
                    GitDiffFile(
                        fileId: "submodule",
                        path: "Dependencies/Package",
                        previousPath: nil,
                        changeKind: .modified,
                        oldContentHash: "old-commit",
                        newContentHash: "new-file",
                        contentHashAlgorithm: "git-oid",
                        oldMode: 0o160000,
                        newMode: 0o100644,
                        additions: 1,
                        deletions: 1,
                        isBinary: false,
                        sizeBytes: 8
                    )
                ]
            )
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient,
            gitReadContext: makeBridgeGitReadContext(rootURL: repositoryPath)
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
                reviewGeneration: 3
            )
        )
        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package",
                query: query,
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 3,
                generatedAtUnixMilliseconds: 4
            )
        )

        #expect(comparison.changedFiles.first?.oldMode == 0o160000)
        #expect(comparison.changedFiles.first?.newMode == 0o100644)
        #expect(package.itemsById["item-submodule"]?.contentRoles.base == nil)
        #expect(package.itemsById["item-submodule"]?.contentRoles.head != nil)
        #expect(await adapter.registeredContentLocatorCount() == 1)
    }

    @Test("AgentStudioGit shared capture maps locked failures without exposing raw prose")
    func agentStudioGitSharedCaptureMapsLockedFailuresWithoutExposingRawProse() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-shared-capture-failure-test")
        let filePath = "Sources/App/View.swift"
        let rawMessage = "locked while reading /Users/example/private/repository"
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let changedFile = GitDiffFile(
            fileId: "source",
            path: filePath,
            previousPath: nil,
            changeKind: .modified,
            oldContentHash: "old-content",
            newContentHash: "new-content",
            contentHashAlgorithm: "git-oid",
            oldMode: 0o100644,
            newMode: 0o100644,
            additions: 1,
            deletions: 1,
            isBinary: false,
            sizeBytes: 8
        )
        let gitClient = AgentStudioGitLocalClientFake(
            diffSnapshot: GitDiffSnapshot(files: [changedFile]),
            contentFailureByLocator: [
                GitContentLocator(target: .workingTree, path: filePath): .locked(message: rawMessage)
            ]
        )
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient,
            gitReadContext: makeBridgeGitReadContext(rootURL: repositoryPath)
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
                reviewGeneration: 3
            )
        )
        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package",
                query: query,
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 3,
                generatedAtUnixMilliseconds: 4
            )
        )

        do {
            _ = try await adapter.captureSharedContent(
                handles: package.itemsById.values.flatMap(\.contentRoles.allHandles),
                freshnessKey: await adapter.gitReadFreshnessKey(for: 3)
            )
            Issue.record("Expected locked Git data-plane failure")
        } catch BridgeProviderFailure.providerFailed(let message) {
            #expect(message == "gitDataPlane:locked")
            #expect(!message.contains(rawMessage))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(type(of: error))")
        }
    }

    @Test("AgentStudioGit maps unsupported failures without exposing raw prose")
    func agentStudioGitMapsUnsupportedFailuresWithoutExposingRawProse() async {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-unsupported-failure-test")
        let adapter = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: AgentStudioGitLocalClientFake(),
            gitReadContext: makeBridgeGitReadContext(rootURL: repositoryPath)
        )

        let failure = await adapter.bridgeFailure(
            for: .unsupported(message: "unsupported at /Users/example/private/repository")
        )

        guard case .providerFailed(let message) = failure else {
            Issue.record("Expected providerFailed")
            return
        }
        #expect(message == "gitDataPlane:unsupported")
    }
}
