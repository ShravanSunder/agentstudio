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

    @Test("loadDiff publishes review descriptors without eager body facts")
    func loadDiff_publishes_review_descriptors_without_eager_body_facts() async throws {
        let capturedIntakeFrames = SendableBox<[String]>([])
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
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider,
            intakeFrameSink: { _, frameJSON, _ in
                await capturedIntakeFrames.update { frames in
                    frames + [frameJSON]
                }
            }
        )
        defer { controller.teardown() }
        controller.handleBridgeReady()
        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )
        let commandId = UUID()

        let result = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: commandId,
            correlationId: nil
        )

        #expect(result == .success(commandId: commandId))
        let capturedFrames = await capturedIntakeFrames.get()
        #expect(capturedFrames.count == 2)
        let snapshotFrameJSON = try #require(capturedFrames.last)
        let snapshotFrameObject = try Self.reviewIntakeFrameObject(snapshotFrameJSON)
        #expect(snapshotFrameObject["kind"] as? String == "snapshot")
        #expect(snapshotFrameObject["sequence"] as? Int == 1)
        let payload = try #require(snapshotFrameObject["payload"] as? [String: Any])
        #expect(payload["sequence"] as? Int == 1)
        let package = try #require(payload["package"] as? [String: Any])
        let rootDescriptor = try #require(package["rootDescriptor"] as? [String: Any])
        let descriptor = try #require(rootDescriptor["descriptor"] as? [String: Any])
        let content = try #require(descriptor["content"] as? [String: Any])
        #expect(content["expectedBytes"] == nil)
        #expect(content["integrity"] == nil)
    }

    @Test("loadDiff waits for review intake ready after bridge ready")
    func loadDiff_waits_for_review_intake_ready_after_bridge_ready() async throws {
        let capturedIntakeFrames = SendableBox<[String]>([])
        let comparisonGate = BridgeComparisonGate()
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
            contentByHandleId: [:],
            comparisonGate: comparisonGate
        )
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider,
            intakeFrameSink: { _, frameJSON, _ in
                await capturedIntakeFrames.update { frames in
                    frames + [frameJSON]
                }
            }
        )
        defer { controller.teardown() }
        let commandId = UUID()

        async let result = controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: commandId,
            correlationId: nil
        )
        await comparisonGate.waitForStartedComparisonCount(1)
        controller.handleBridgeReady()
        await comparisonGate.releaseAll()

        #expect(await result == .success(commandId: commandId))
        #expect(await capturedIntakeFrames.get().isEmpty)
        #expect(controller.pendingReviewProtocolIntakeFrames.count == 2)

        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )

        let deliveredFrames = await capturedIntakeFrames.get()
        #expect(controller.pendingReviewProtocolIntakeFrames.isEmpty)
        #expect(deliveredFrames.count == 2)
        let resetFrame = try Self.reviewIntakeFrameObject(try #require(deliveredFrames.first))
        let snapshotFrame = try Self.reviewIntakeFrameObject(try #require(deliveredFrames.last))
        #expect(resetFrame["kind"] as? String == "reset")
        #expect(resetFrame["sequence"] as? Int == 0)
        #expect(snapshotFrame["kind"] as? String == "snapshot")
        #expect(snapshotFrame["sequence"] as? Int == 1)
    }

    @Test("loadDiff accepts review intake ready before bridge ready")
    func loadDiff_accepts_review_intake_ready_before_bridge_ready() async throws {
        let capturedIntakeFrames = SendableBox<[String]>([])
        let comparisonGate = BridgeComparisonGate()
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
            contentByHandleId: [:],
            comparisonGate: comparisonGate
        )
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider,
            intakeFrameSink: { _, frameJSON, _ in
                await capturedIntakeFrames.update { frames in
                    frames + [frameJSON]
                }
            }
        )
        defer { controller.teardown() }
        let commandId = UUID()

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.intakeReady","params":{"protocolId":"review","streamId":null}}"#
        )
        async let result = controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: commandId,
            correlationId: nil
        )
        await comparisonGate.waitForStartedComparisonCount(1)
        controller.handleBridgeReady()
        await comparisonGate.releaseAll()

        #expect(await result == .success(commandId: commandId))
        let deliveredFrames = await capturedIntakeFrames.get()
        #expect(controller.pendingReviewProtocolIntakeFrames.isEmpty)
        #expect(deliveredFrames.count == 2)
        let resetFrame = try Self.reviewIntakeFrameObject(try #require(deliveredFrames.first))
        let snapshotFrame = try Self.reviewIntakeFrameObject(try #require(deliveredFrames.last))
        #expect(resetFrame["kind"] as? String == "reset")
        #expect(resetFrame["sequence"] as? Int == 0)
        #expect(snapshotFrame["kind"] as? String == "snapshot")
        #expect(snapshotFrame["sequence"] as? Int == 1)
    }

    @Test("review invalidation uses stream sequence instead of filesystem batch sequence")
    func review_invalidation_uses_stream_sequence_instead_of_filesystem_batch_sequence() async throws {
        let capturedIntakeFrames = SendableBox<[String]>([])
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let initialFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100
        )
        let refreshedFile = makeBridgeEndpointChangedFile(
            fileId: "refreshed",
            path: "Sources/App/New.swift",
            sizeBytes: 100
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [initialFile]
            ),
            contentByHandleId: [:]
        )
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider,
            intakeFrameSink: { _, frameJSON, _ in
                await capturedIntakeFrames.update { frames in
                    frames + [frameJSON]
                }
            }
        )
        defer { controller.teardown() }
        controller.handleBridgeReady()
        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )
        let commandId = UUID()
        let loadResult = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: commandId,
            correlationId: nil
        )
        #expect(loadResult == .success(commandId: commandId))

        await provider.setComparison(
            BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [refreshedFile]
            )
        )
        await controller.handlePaneFilesystemContextEvent(
            .cwdSubtreeChanged(
                context: PaneFilesystemContext(
                    paneId: PaneId(uuid: controller.paneId),
                    repoId: headEndpoint.repoId,
                    cwd: URL(fileURLWithPath: "/tmp/worktree"),
                    worktreeId: headEndpoint.worktreeId
                ),
                paths: ["Sources/App/New.swift"],
                batchSeq: 10
            )
        )

        let capturedFrameJSON = await capturedIntakeFrames.get()
        let capturedFrames = try capturedFrameJSON.map(Self.reviewIntakeFrameObject)
        let invalidationFrame = try #require(capturedFrames.first { $0["kind"] as? String == "invalidate" })
        let initialSnapshotFrame = try #require(capturedFrames.first { $0["kind"] as? String == "snapshot" })
        #expect(invalidationFrame["sequence"] as? Int == 2)
        #expect(invalidationFrame["sequence"] as? Int != 10)
        #expect(invalidationFrame["generation"] as? Int == initialSnapshotFrame["generation"] as? Int)
    }

    @Test("loadDiff publishes typed provider unavailable failure")
    func loadDiff_publishes_typed_provider_unavailable_failure() async throws {
        let capturedIntakeFrames = SendableBox<[String]>([])
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            intakeFrameSink: { _, frameJSON, _ in
                await capturedIntakeFrames.update { frames in
                    frames + [frameJSON]
                }
            }
        )
        defer { controller.teardown() }
        controller.handleBridgeReady()
        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )
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
        let capturedFrames = await capturedIntakeFrames.get()
        #expect(capturedFrames.count == 2)
        let resetFrameJSON = try #require(capturedFrames.first)
        let errorFrameJSON = try #require(capturedFrames.last)
        let resetFrameObject = try Self.reviewIntakeFrameObject(resetFrameJSON)
        let errorFrameObject = try Self.reviewIntakeFrameObject(errorFrameJSON)
        #expect(resetFrameObject["kind"] as? String == "reset")
        #expect(resetFrameObject["sequence"] as? Int == 0)
        let resetPayload = try #require(resetFrameObject["payload"] as? [String: Any])
        #expect(resetPayload["frameKind"] as? String == "review.reset")
        #expect(resetPayload["kind"] as? String == "reset")
        #expect(errorFrameObject["kind"] as? String == "error")
        #expect(errorFrameObject["generation"] as? Int == resetFrameObject["generation"] as? Int)
        #expect(errorFrameObject["sequence"] as? Int == 1)
        #expect(errorFrameObject["message"] as? String == "providerUnavailable")
        #expect(errorFrameObject["payload"] == nil)
    }
}
