import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests.BridgePaneControllerTests {

    @Test("filesystem context refresh preserves revisions across changed and no-op packages")
    func filesystemContextRefreshPreservesRevisionsAcrossChangedAndNoOpPackages() async throws {
        let fixture = makeRefreshRevisionFixture()
        defer { fixture.controller.teardown() }

        let loadResult = await fixture.controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: fixture.headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: fixture.commandId,
            correlationId: nil
        )

        await setRefreshComparison(fixture, changedFile: fixture.refreshedFile)
        await postRefreshEvent(fixture, path: "Sources/App/New.swift", batchSeq: 10)
        #expect(loadResult == .success(commandId: fixture.commandId))
        #expect(fixture.controller.paneState.diff.status == .ready)
        expectRefreshPackageState(
            fixture,
            itemId: "item-new",
            revision: 1,
            addedItemIds: ["item-new"],
            removedItemIds: ["item-old"]
        )

        await postRefreshEvent(fixture, path: "Sources/App/New.swift", batchSeq: 11)
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-new"])
        #expect(fixture.controller.paneState.diff.packageMetadata?.revision == 1)
        #expect(fixture.controller.paneState.diff.packageDelta == nil)

        await setRefreshComparison(fixture, changedFile: fixture.secondRefreshedFile)
        await postRefreshEvent(fixture, path: "Sources/App/Newer.swift", batchSeq: 12)
        expectRefreshPackageState(
            fixture,
            itemId: "item-newer",
            revision: 2,
            addedItemIds: ["item-newer"],
            removedItemIds: ["item-new"]
        )
        #expect(await fixture.provider.recordedComparisonRequestsCount() == 4)
    }

    @Test("filesystem context refresh coalesces overlapping refresh events")
    func filesystemContextRefreshCoalescesOverlappingRefreshEvents() async throws {
        let fixture = makeRefreshRevisionFixture()
        defer { fixture.controller.teardown() }
        let loadResult = await fixture.controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: fixture.headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: fixture.commandId,
            correlationId: nil
        )
        #expect(loadResult == .success(commandId: fixture.commandId))

        let gate = BridgeComparisonGate()
        await fixture.provider.setComparisonGate(gate)
        await setRefreshComparison(fixture, changedFile: fixture.refreshedFile)
        async let firstRefresh: Void = postRefreshEvent(
            fixture,
            path: "Sources/App/New.swift",
            batchSeq: 20
        )
        await gate.waitForStartedComparisonCount(1)

        await setRefreshComparison(fixture, changedFile: fixture.secondRefreshedFile)
        async let secondRefresh: Void = postRefreshEvent(
            fixture,
            path: "Sources/App/Newer.swift",
            batchSeq: 21
        )
        async let thirdRefresh: Void = postRefreshEvent(
            fixture,
            path: "Sources/App/Newer.swift",
            batchSeq: 22
        )
        await Task.yield()
        await Task.yield()

        #expect(await fixture.provider.recordedComparisonRequestsCount() == 2)
        await gate.releaseAll()
        _ = await (firstRefresh, secondRefresh, thirdRefresh)

        #expect(await fixture.provider.recordedComparisonRequestsCount() == 3)
        expectRefreshPackageState(
            fixture,
            itemId: "item-newer",
            revision: 2,
            addedItemIds: ["item-newer"],
            removedItemIds: ["item-new"]
        )
    }

    @Test("loadDiff ignores stale earlier generation completion")
    func loadDiff_ignores_stale_earlier_generation_completion() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let firstFile = makeBridgeEndpointChangedFile(
            fileId: "old",
            path: "Sources/App/Old.swift",
            sizeBytes: 100
        )
        let secondFile = makeBridgeEndpointChangedFile(
            fileId: "new",
            path: "Sources/App/New.swift",
            sizeBytes: 100
        )
        let provider = OutOfOrderBridgeReviewSourceProvider(
            firstGenerationComparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [firstFile]
            ),
            laterGenerationComparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [secondFile]
            )
        )
        let controller = makeController(
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider
        )
        defer { controller.teardown() }
        let firstCommandId = UUID()
        let secondCommandId = UUID()

        async let firstResult = controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: firstCommandId,
            correlationId: nil
        )
        await provider.waitForFirstGenerationStarted()
        let secondResult = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: secondCommandId,
            correlationId: nil
        )
        await provider.releaseFirstGeneration()

        #expect(secondResult == .success(commandId: secondCommandId))
        #expect(await firstResult == .failure(.invalidPayload(description: "Stale bridge review load")))
        #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-new"])
        #expect(controller.paneState.diff.packageMetadata?.itemsById["item-old"] == nil)
    }

    @Test("loadDiff does not leak absolute workspace root in review package")
    func loadDiff_does_not_leak_absolute_workspace_root_in_review_package() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [:]
        )
        let controller = makeController(
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider
        )
        defer { controller.teardown() }
        let commandId = UUID()

        let result = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: commandId,
            correlationId: nil
        )

        #expect(result == .success(commandId: commandId))
        let package = try #require(controller.paneState.diff.packageMetadata)
        #expect(package.orderedItemIds == ["item-source"])
        #expect(package.query.pathScope.isEmpty)
        #expect(package.headEndpoint.providerIdentity.contains("/tmp") == false)
        #expect(package.baseEndpoint.providerIdentity.contains("/tmp") == false)
    }

    @Test("loadDiff publishes typed provider unavailable failure")
    func loadDiff_publishes_typed_provider_unavailable_failure() async {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            )
        )
        defer { controller.teardown() }
        let commandId = UUID()
        let artifact = DiffArtifact(
            diffId: UUIDv7.generate(),
            worktreeId: UUIDv7.generate(),
            patchData: Data()
        )

        let result = await controller.handleDiffCommand(
            .loadDiff(artifact),
            commandId: commandId,
            correlationId: nil
        )

        #expect(result == .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider")))
        #expect(controller.paneState.diff.status == .error)
        #expect(controller.paneState.diff.error == "providerUnavailable")
        #expect(controller.paneState.diff.packageMetadata == nil)
    }
}
