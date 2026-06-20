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
            #expect(controller.paneState.diff.packageMetadata?.query.worktreeId == worktreeId)
            #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-source"])
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
            ]

            for testCase in cases {
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
                #expect(request.headEndpoint.kind == .workingTree)
                #expect(request.headEndpoint.label == "Working tree")
                #expect(request.query.comparisonSemantics == .workingTreeDelta)
            }
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

        private func makeController(
            source: BridgePaneSource?,
            worktreeId: UUID?,
            provider: any BridgeReviewSourceProvider
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: source),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Review",
                    facets: PaneContextFacets(worktreeId: worktreeId)
                ),
                reviewSourceProvider: provider
            )
        }
    }
}
