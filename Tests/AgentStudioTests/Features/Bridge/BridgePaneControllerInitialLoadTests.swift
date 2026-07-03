import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerInitialLoadTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("source backed controller can load its initial review package")
        func sourceBackedControllerCanLoadInitialReviewPackage() async throws {
            let repoId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            let worktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100,
                            oldContentHash: bridgeSHA256ContentHash("old"),
                            newContentHash: bridgeSHA256ContentHash("new")
                        )
                    ]
                ),
                contentByHandleId: [:]
            )
            let controller = makeController(
                source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged),
                repoId: repoId,
                worktreeId: worktreeId,
                provider: provider
            )
            defer { controller.teardown() }

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            guard case .success = result else {
                Issue.record("Expected initial Bridge review package load to succeed")
                return
            }
            #expect(controller.paneState.diff.status == .ready)
            #expect(controller.paneState.diff.packageMetadata?.query.repoId == repoId)
            #expect(controller.paneState.diff.packageMetadata?.query.worktreeId == worktreeId)
            #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-source"])
            let request = try #require(await provider.recordedComparisonRequests().first)
            #expect(request.query.repoId == repoId)
            #expect(request.query.worktreeId == worktreeId)
            #expect(request.baseEndpoint.repoId == repoId)
            #expect(request.baseEndpoint.worktreeId == worktreeId)
            #expect(request.headEndpoint.repoId == repoId)
            #expect(request.headEndpoint.worktreeId == worktreeId)
            #expect(await provider.recordedContentRequestsCount() == 0)
        }

        @Test("workspace review compare targets select git ref baseline against working tree")
        func workspaceReviewCompareTargetsSelectGitRefBaselineAgainstWorkingTree() async throws {
            struct Case {
                let baseline: WorkspaceBaseline
                let expectedEndpointId: String
                let expectedLabel: String
                let expectedProviderIdentity: String
            }

            let cases = [
                Case(
                    baseline: .localDefaultBranch(branchName: "main"),
                    expectedEndpointId: "baseline-local-default",
                    expectedLabel: "main",
                    expectedProviderIdentity: "main"
                ),
                Case(
                    baseline: .originDefaultBranch(remoteName: "origin", branchName: "main"),
                    expectedEndpointId: "baseline-origin-default",
                    expectedLabel: "origin/main",
                    expectedProviderIdentity: "origin/main"
                ),
                Case(
                    baseline: .branch(name: "release/next"),
                    expectedEndpointId: "baseline-branch-release-next",
                    expectedLabel: "release/next",
                    expectedProviderIdentity: "release/next"
                ),
                Case(
                    baseline: .ref(name: "v1.2.3"),
                    expectedEndpointId: "baseline-ref-v1-2-3",
                    expectedLabel: "v1.2.3",
                    expectedProviderIdentity: "v1.2.3"
                ),
                Case(
                    baseline: .ref(name: "HEAD"),
                    expectedEndpointId: "baseline-ref-HEAD",
                    expectedLabel: "HEAD",
                    expectedProviderIdentity: "HEAD"
                ),
            ]

            for testCase in cases {
                let repoId = UUIDv7.generate()
                let worktreeId = UUIDv7.generate()
                let provider = BridgeReviewSourceProviderFake(
                    comparison: BridgeEndpointComparison(
                        baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                        headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                        changedFiles: [
                            makeBridgeEndpointChangedFile(
                                fileId: "source",
                                path: "Sources/App/View.swift",
                                sizeBytes: 100
                            )
                        ]
                    ),
                    contentByHandleId: [:]
                )
                let controller = makeController(
                    source: .workspace(rootPath: "/tmp/worktree", baseline: testCase.baseline),
                    repoId: repoId,
                    worktreeId: worktreeId,
                    provider: provider
                )
                defer { controller.teardown() }

                let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

                guard case .success = result else {
                    Issue.record("Expected initial Bridge review package load to succeed")
                    return
                }
                let requests = await provider.recordedComparisonRequests()
                let request = try #require(requests.first)
                #expect(request.baseEndpoint.endpointId == testCase.expectedEndpointId)
                #expect(request.baseEndpoint.kind == .gitRef)
                #expect(request.baseEndpoint.label == testCase.expectedLabel)
                #expect(request.baseEndpoint.providerIdentity == testCase.expectedProviderIdentity)
                #expect(request.baseEndpoint.repoId == repoId)
                #expect(request.baseEndpoint.worktreeId == worktreeId)
                #expect(request.headEndpoint.kind == .workingTree)
                #expect(request.headEndpoint.label == "Working tree")
                #expect(request.headEndpoint.repoId == repoId)
                #expect(request.headEndpoint.worktreeId == worktreeId)
                #expect(request.query.repoId == repoId)
                #expect(request.query.worktreeId == worktreeId)
                #expect(request.query.comparisonSemantics == .workingTreeDelta)
            }
        }

        @Test("workspace review falls back to unstaged comparison when HEAD is unresolved")
        func workspaceReviewFallsBackToUnstagedComparisonWhenHeadIsUnresolved() async throws {
            let worktreeId = UUIDv7.generate()
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "index", kind: .index),
                    headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "unborn",
                            path: "Sources/App/NewFile.swift",
                            sizeBytes: 100
                        )
                    ]
                ),
                contentByHandleId: [:],
                comparisonFailureByBaseProviderIdentity: [
                    "HEAD": .providerFailed(message: "revspec 'HEAD' not found")
                ]
            )
            let controller = makeController(
                source: .workspace(rootPath: "/tmp/worktree", baseline: .ref(name: "HEAD")),
                worktreeId: worktreeId,
                provider: provider
            )
            defer { controller.teardown() }

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            guard case .success = result else {
                Issue.record("Expected HEAD fallback review package load to succeed")
                return
            }
            let requests = await provider.recordedComparisonRequests()
            #expect(requests.count == 2)
            let headRequest = try #require(requests.first)
            #expect(headRequest.baseEndpoint.kind == .gitRef)
            #expect(headRequest.baseEndpoint.providerIdentity == "HEAD")
            let fallbackRequest = try #require(requests.last)
            #expect(fallbackRequest.baseEndpoint.kind == .index)
            #expect(fallbackRequest.headEndpoint.kind == .workingTree)
            #expect(fallbackRequest.query.comparisonSemantics == .workingTreeDelta)
            #expect(controller.paneState.diff.status == .ready)
        }

        @Test("workspace review exposes scrubbed git data-plane package load failures")
        func workspaceReviewExposesScrubbedGitDataPlanePackageLoadFailures() async throws {
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                    headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                    changedFiles: []
                ),
                contentByHandleId: [:],
                comparisonFailureByBaseProviderIdentity: [
                    "main": .providerFailed(
                        message:
                            "gitDataPlane:libgit2Failure:code=-1:klass=2:reason=operationNotPermitted"
                    )
                ]
            )
            let controller = makeController(
                source: .workspace(rootPath: "/tmp/worktree", baseline: .branch(name: "main")),
                worktreeId: UUIDv7.generate(),
                provider: provider
            )
            defer { controller.teardown() }

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            guard case .failure = result else {
                Issue.record("Expected native review package load to fail")
                return
            }
            #expect(controller.paneState.diff.status == .error)
            #expect(
                controller.paneState.diff.error
                    == "loadFailed:package:providerFailed:git.libgit2Failure:code=-1:klass=2:reason=operationNotPermitted"
            )
        }

        @Test("review package failure summaries scrub raw provider paths")
        func reviewPackageFailureSummariesScrubRawProviderPaths() {
            let rawPath = "/Users/shravansunder/Documents/dev/project-dev/secret.txt"

            let summary = BridgePaneController.reviewPackageLoadFailureSummary(
                for: BridgeProviderFailure.providerFailed(message: "Git path escapes repository: \(rawPath)"),
                stage: "package"
            )

            #expect(summary == "loadFailed:package:providerFailed:pathEscapesRepository")
            #expect(!summary.contains(rawPath))
        }

        @Test("review package failure summaries classify timeout-shaped provider messages")
        func reviewPackageFailureSummariesClassifyTimeoutShapedProviderMessages() {
            let summary = BridgePaneController.reviewPackageLoadFailureSummary(
                for: BridgeProviderFailure.providerFailed(
                    message:
                        "The operation couldn’t be completed. (AgentStudio.BridgeGitDataPlaneTimeoutError error 0.)"
                ),
                stage: "package"
            )

            #expect(summary == "loadFailed:package:providerFailed:gitDataPlaneTimeout")
        }

        @Test("generic controller skips initial review package load")
        func genericControllerSkipsInitialReviewPackageLoad() async {
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                    headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100
                        )
                    ]
                ),
                contentByHandleId: [:]
            )
            let controller = makeController(source: nil, worktreeId: nil, provider: provider)
            defer { controller.teardown() }

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            #expect(result == nil)
            #expect(controller.paneState.diff.status == .idle)
            #expect(controller.paneState.diff.packageMetadata == nil)
            #expect(await provider.recordedComparisonRequestsCount() == 0)
        }

        @Test("file viewer controller loads its initial review package for a review switch")
        func fileViewerControllerLoadsInitialReviewPackage() async {
            let worktreeId = UUIDv7.generate()
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                    headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100
                        )
                    ]
                ),
                contentByHandleId: [:]
            )
            let controller = makeController(
                panelKind: .fileViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged),
                worktreeId: worktreeId,
                provider: provider
            )
            defer { controller.teardown() }

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            guard case .success = result else {
                Issue.record("Expected a file-viewer pane to load its review package for a review switch")
                return
            }
            #expect(controller.paneState.diff.status == .ready)
            #expect(controller.paneState.diff.packageMetadata?.query.worktreeId == worktreeId)
            #expect(await provider.recordedComparisonRequestsCount() == 1)
        }

        private func makeController(
            panelKind: BridgePanelKind = .diffViewer,
            source: BridgePaneSource?,
            repoId: UUID? = nil,
            worktreeId: UUID?,
            provider: any BridgeReviewSourceProvider
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: panelKind, source: source),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Review",
                    facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId)
                ),
                reviewSourceProvider: provider
            )
        }
    }
}
