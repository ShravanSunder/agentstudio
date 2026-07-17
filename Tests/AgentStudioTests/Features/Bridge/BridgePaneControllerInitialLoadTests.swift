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
                        "The operation couldn’t be completed. (AgentStudio.BridgeGitReadSchedulerError error 0.)"
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

        @Test("failed initial Review publication does not self-retry without new intake")
        func failedInitialReviewPublicationDoesNotSelfRetryWithoutNewIntake() async throws {
            // Arrange — the slash produces an invalid Review item identifier at the metadata
            // reservation boundary while leaving the native pane in its initial loading state.
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                    headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "nested/source",
                            path: "Sources/App/View.swift",
                            sizeBytes: 100
                        )
                    ]
                ),
                contentByHandleId: [:]
            )
            let controller = makeController(
                source: .workspace(rootPath: "/tmp/worktree", baseline: .unstaged),
                worktreeId: UUIDv7.generate(),
                provider: provider
            )
            defer { controller.teardown() }

            // Act — wait for the exact scheduled attempt, not for elapsed time. A completion
            // callback that manufactures another intake replaces activeReviewRefreshTask before
            // this captured task returns.
            controller.scheduleInitialReviewPackageLoadIfPossible(reason: .initialIntake)
            let firstAttempt = try #require(controller.activeReviewRefreshTask)
            await firstAttempt.value

            // Assert
            #expect(await provider.recordedComparisonRequestsCount() == 1)
            #expect(controller.activeReviewRefreshTask == nil)
            #expect(controller.paneState.diff.status == .loading)
            #expect(controller.paneState.diff.packageMetadata == nil)
        }

        @Test("real-git multi-window fixture commits one initial Review package")
        func realGitMultiWindowFixtureCommitsOneInitialReviewPackage() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(
                named: "bridge-review-initial-load-multi-window"
            )
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try seedRealGitMultiWindowFixture(at: repoURL)
            let paneId = UUIDv7.generate()
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let gitReadContext = makeBridgeGitReadContext(rootURL: repoURL)
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: repoURL.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(uuid: paneId),
                    contentType: .diff,
                    launchDirectory: repoURL,
                    title: "Real Git Initial Review",
                    facets: PaneContextFacets(
                        repoId: repoId,
                        worktreeId: worktreeId,
                        worktreeName: "real-git-initial-review",
                        cwd: repoURL
                    )
                ),
                reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repoURL,
                    gitReadContext: gitReadContext
                ),
                gitReadContext: gitReadContext,
                initialPaneActivity: .foreground
            )
            defer { controller.teardown() }

            // Act
            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            // Assert
            guard case .success = result else {
                Issue.record(
                    "Expected one real-git initial load to commit; result=\(String(describing: result)), status=\(controller.paneState.diff.status), error=\(controller.paneState.diff.error ?? "none"), publication=\(controller.reviewPublicationCoordinator.diagnosticSnapshot), generation=\(controller.nextReviewGeneration.rawValue)"
                )
                return
            }
            let package = try #require(controller.paneState.diff.packageMetadata)
            #expect(controller.paneState.diff.status == .ready)
            #expect(package.orderedItemIds.count >= 37)
            #expect(controller.reviewPublicationCoordinator.diagnosticSnapshot.active != nil)
        }

        @Test("real-git multi-window package fits Review metadata reservation")
        func realGitMultiWindowPackageFitsReviewMetadataReservation() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(
                named: "bridge-review-metadata-reservation-multi-window"
            )
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try seedRealGitMultiWindowFixture(at: repoURL)
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let provider = BridgeReviewSourceProviderFactory.gitProvider(
                repositoryPath: repoURL,
                gitReadContext: makeBridgeGitReadContext(rootURL: repoURL)
            )
            let pipeline = BridgeReviewPipeline(provider: provider)
            let productAdmission = try #require(BridgeProductAdmissionGate().acquire())
            let result = try await pipeline.loadPackage(
                makeRealGitMultiWindowPipelineRequest(
                    repoId: repoId,
                    worktreeId: worktreeId
                )
            )
            let source = BridgePaneProductReviewMetadataSource()

            // Act
            let reservation: BridgeReviewMetadataPublicationReservation
            do {
                reservation = try await source.reserve(
                    package: result.package,
                    publicationId: UUIDv7.generate(),
                    productAdmission: productAdmission
                )
            } catch {
                Issue.record(
                    "Expected Review metadata reservation to accept the real-git package; errorType=\(String(describing: type(of: error))), error=\(String(describing: error)), items=\(result.package.orderedItemIds.count)"
                )
                return
            }

            // Assert
            #expect(result.package.orderedItemIds.count >= 37)
            #expect(reservation.packageId == result.package.packageId)
            #expect(reservation.reviewGeneration == result.package.reviewGeneration)
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
                reviewSourceProvider: provider,
                initialPaneActivity: .foreground
            )
        }

        private func seedRealGitMultiWindowFixture(at repoURL: URL) throws {
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
            for index in 0..<36 {
                let directory = repoURL.appending(
                    path: String(format: "Sources/Group%02d", index / 9)
                )
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try "review item \(index)\n".write(
                    to: directory.appending(path: String(format: "item-%03d.txt", index)),
                    atomically: true,
                    encoding: .utf8
                )
            }
            let largeBody = (0..<520).map { "large line \($0)" }.joined(separator: "\n")
            try "\(largeBody)\n".write(
                to: repoURL.appending(path: "Sources/Group00/large-position.txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        private func makeRealGitMultiWindowPipelineRequest(
            repoId: UUID,
            worktreeId: UUID
        ) -> BridgeReviewPipelineRequest {
            let base = BridgeSourceEndpoint(
                endpointId: "baseline-local-default",
                kind: .gitRef,
                repoId: repoId,
                worktreeId: worktreeId,
                label: "main",
                createdAtUnixMilliseconds: 1,
                contentSetHash: nil,
                providerIdentity: "main"
            )
            let head = BridgeSourceEndpoint(
                endpointId: "working-tree",
                kind: .workingTree,
                repoId: repoId,
                worktreeId: worktreeId,
                label: "Working tree",
                createdAtUnixMilliseconds: 1,
                contentSetHash: nil,
                providerIdentity: "working-tree:\(worktreeId.uuidString)"
            )
            return BridgeReviewPipelineRequest(
                packageId: "real-git-multi-window-package",
                query: BridgeReviewQuery(
                    queryId: "real-git-multi-window-query",
                    queryKind: .compare,
                    repoId: repoId,
                    worktreeId: worktreeId,
                    baseEndpointId: base.endpointId,
                    headEndpointId: head.endpointId,
                    comparisonSemantics: .workingTreeDelta,
                    pathScope: [],
                    fileTarget: nil,
                    viewFilter: BridgeViewFilter(),
                    grouping: BridgeChangeGrouping(kind: .flat),
                    provenanceFilter: BridgeProvenanceFilter()
                ),
                baseEndpoint: base,
                headEndpoint: head,
                checkpointIds: [],
                reviewGeneration: 1,
                generatedAtUnixMilliseconds: 1
            )
        }
    }
}
