import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests.BridgePaneControllerTests {
    @Test("review intake delivery failure retains queued jobs and redelivers with the same sequences")
    func reviewIntakeDeliveryFailureRetainsQueuedJobsAndRedeliversWithSameSequences() async {
        let intakeCapture = FailingBridgeIntakeCapture(failureCount: 1)
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            intakeFrameSink: { _, frameJSON, _ in
                try await intakeCapture.record(frameJSON)
            }
        )
        defer { controller.teardown() }
        // Review frames emit as scheduler jobs whose sequences are consumed
        // at dispatch inside the serialized drain. Queue two review jobs
        // behind the closed gate against the controller's initial review
        // generation.
        await controller.worktreeFileMetadataScheduler.acceptGeneration(0, protocolId: "review")
        await controller.enqueueReviewProtocolEncodedFrameJob(lane: .foreground, generation: 0) { sequence in
            #"{"kind":"snapshot","sequence":\#(sequence)}"#
        }
        await controller.enqueueReviewProtocolEncodedFrameJob(lane: .foreground, generation: 0) { sequence in
            #"{"kind":"delta","sequence":\#(sequence)}"#
        }

        controller.handleBridgeReady()
        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()

        // The first delivery fails: the scheduler closes the review gate,
        // retains the failed job at its lane front, and the sequence rolls
        // back so the retry redelivers without a gap.
        #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 2)
        #expect(await intakeCapture.frames().isEmpty)

        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()

        #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 0)
        #expect(
            await intakeCapture.frames() == [
                #"{"kind":"snapshot","sequence":0}"#,
                #"{"kind":"delta","sequence":1}"#,
            ]
        )
    }

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

    @Test("initial review load streams metadata windows beyond visible startup budget")
    func initialReviewLoadStreamsMetadataWindowsBeyondVisibleStartupBudget() async throws {
        let capturedIntakeFrames = SendableBox<[String]>([])
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let changedFiles = (0..<85).map { index in
            makeBridgeEndpointChangedFile(
                fileId: "changed-\(index)",
                path: index < 80
                    ? "BridgeWeb/src/Changed\(index).tsx"
                    : "Sources/App/Changed\(index).swift",
                sizeBytes: 100
            )
        }
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: changedFiles
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
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()
        let capturedFrames = try await capturedIntakeFrames.get().map(Self.reviewIntakeFrameObject)
        let snapshotFrame = try #require(capturedFrames.first { $0["kind"] as? String == "snapshot" })
        let snapshotPayload = try #require(snapshotFrame["payload"] as? [String: Any])
        let snapshotItems = try #require(snapshotPayload["itemMetadata"] as? [[String: Any]])
        #expect(snapshotItems.count == 80)
        let metadataWindowFrame = try #require(
            capturedFrames.first { frame in
                guard let payload = frame["payload"] as? [String: Any] else { return false }
                return payload["frameKind"] as? String == "review.metadataWindow"
            }
        )
        #expect(metadataWindowFrame["kind"] as? String == "delta")
        let metadataWindowPayload = try #require(metadataWindowFrame["payload"] as? [String: Any])
        let windowItems = try #require(metadataWindowPayload["itemMetadata"] as? [[String: Any]])
        let windowPaths = windowItems.compactMap { $0["headPath"] as? String }
        #expect(windowPaths.contains("Sources/App/Changed84.swift"))
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
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()
        let capturedFrames = await capturedIntakeFrames.get()
        #expect(capturedFrames.count == 2)
        let snapshotFrameJSON = try #require(capturedFrames.last)
        let snapshotFrameObject = try Self.reviewIntakeFrameObject(snapshotFrameJSON)
        #expect(snapshotFrameObject["kind"] as? String == "snapshot")
        #expect(snapshotFrameObject["sequence"] as? Int == 1)
        let payload = try #require(snapshotFrameObject["payload"] as? [String: Any])
        #expect(payload["sequence"] as? Int == 1)
        let comparison = try #require(payload["comparison"] as? [String: Any])
        #expect(payload["kind"] as? String == "metadataSnapshot")
        #expect(payload["frameKind"] as? String == "review.metadataSnapshot")
        #expect(comparison["rootDescriptor"] == nil)
        #expect(payload["itemMetadata"] != nil)
        #expect(payload["treeRows"] != nil)
        #expect(payload["extentFacts"] != nil)
    }

    @Test("loadDiff metadata descriptor content is served by native content stream")
    func loadDiffMetadataDescriptorContentIsServedByNativeContentStream() async throws {
        let fixture = try Self.makeNativeReviewContentStreamFixture()
        defer { fixture.controller.teardown() }

        let contentBody = try #require(await Self.loadNativeReviewContentStreamBody(fixture))

        #expect(contentBody == fixture.headText)
        #expect(
            await fixture.provider.recordedContentRequestsCount(
                handleId: fixture.expectedHeadHandle.handleId
            ) == 1
        )
    }

    private struct NativeReviewContentStreamFixture {
        let capturedIntakeFrames: SendableBox<[String]>
        let expectedHeadHandle: BridgeContentHandle
        let headEndpoint: BridgeSourceEndpoint
        let headText: String
        let paneId: UUID
        let provider: BridgeReviewSourceProviderFake
        let controller: BridgePaneController
    }

    private static func makeNativeReviewContentStreamFixture() throws -> NativeReviewContentStreamFixture {
        let capturedIntakeFrames = SendableBox<[String]>([])
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let baseText = "base content"
        let headText = "head content"
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: Data(headText.utf8).count,
            oldContentHash: bridgeSHA256ContentHash(baseText),
            newContentHash: bridgeSHA256ContentHash(headText)
        )
        let expectedBaseHandle = BridgeReviewPackageBuilder.contentHandle(
            for: changedFile,
            endpoint: baseEndpoint,
            role: .base,
            reviewGeneration: 1
        )
        let expectedHeadHandle = BridgeReviewPackageBuilder.contentHandle(
            for: changedFile,
            endpoint: headEndpoint,
            role: .head,
            reviewGeneration: 1
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [
                expectedBaseHandle.handleId: makeContentResult(handle: expectedBaseHandle, data: baseText),
                expectedHeadHandle.handleId: makeContentResult(handle: expectedHeadHandle, data: headText),
            ]
        )
        let paneId = UUIDv7.generate()
        let controller = BridgePaneController(
            paneId: paneId,
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

        return NativeReviewContentStreamFixture(
            capturedIntakeFrames: capturedIntakeFrames,
            expectedHeadHandle: expectedHeadHandle,
            headEndpoint: headEndpoint,
            headText: headText,
            paneId: paneId,
            provider: provider,
            controller: controller
        )
    }

    private static func loadNativeReviewContentStreamBody(
        _ fixture: NativeReviewContentStreamFixture
    ) async throws -> String? {
        let controller = fixture.controller
        controller.handleBridgeReady()
        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )

        let result = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: fixture.headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: UUID(),
            correlationId: nil
        )

        guard case .success = result else {
            Issue.record("Expected Review diff load to succeed")
            return nil
        }
        await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
        let capturedFrames = await fixture.capturedIntakeFrames.get()
        let snapshotFrameJSON = try #require(capturedFrames.last)
        let snapshotFrameObject = try Self.reviewIntakeFrameObject(snapshotFrameJSON)
        let payload = try #require(snapshotFrameObject["payload"] as? [String: Any])
        let comparison = try #require(payload["comparison"] as? [String: Any])
        let descriptors = try #require(comparison["contentDescriptors"] as? [[String: Any]])
        let headDescriptor = try #require(
            descriptors.first { descriptor in
                guard let descriptorBody = descriptor["descriptor"] as? [String: Any] else {
                    return false
                }
                return descriptorBody["descriptorId"] as? String == fixture.expectedHeadHandle.handleId
            }
        )
        let descriptorBody = try #require(headDescriptor["descriptor"] as? [String: Any])
        let resourceURL = try #require(descriptorBody["resourceUrl"] as? String)
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                resourceURL,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        )
        #expect(await controller.resourceLeaseRegistry.contains(resource, paneId: fixture.paneId))
        let schemeHandler = BridgeSchemeHandler(
            paneId: fixture.paneId,
            contentStore: controller.reviewContentStore,
            resourceLeaseRegistry: controller.resourceLeaseRegistry
        )
        let request = URLRequest(url: try #require(URL(string: resourceURL)))
        var contentBody = Data()
        for try await result in schemeHandler.reply(for: request) {
            switch result {
            case .response:
                break
            case .data(let chunk):
                contentBody.append(chunk)
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }
        return String(data: contentBody, encoding: .utf8)
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
        #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 2)

        await controller.handleBridgeIntakeReady(
            BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
        )
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()

        let deliveredFrames = await capturedIntakeFrames.get()
        #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 0)
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
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()
        let deliveredFrames = await capturedIntakeFrames.get()
        #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 0)
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

        await controller.worktreeFileMetadataScheduler.waitUntilDrained()
        let capturedFrameJSON = await capturedIntakeFrames.get()
        let capturedFrames = try capturedFrameJSON.map(Self.reviewIntakeFrameObject)
        let invalidationIndex = try #require(
            capturedFrames.firstIndex { $0["kind"] as? String == "invalidate" }
        )
        let invalidationFrame = capturedFrames[invalidationIndex]
        let initialSnapshotFrame = try #require(capturedFrames.first { $0["kind"] as? String == "snapshot" })
        // Sequences are consumed at dispatch, so the invalidation's sequence
        // equals its delivery position in the stream (the concurrent package
        // refresh may legally emit its frames before or after it) and never
        // echoes the filesystem batch sequence.
        #expect(invalidationFrame["sequence"] as? Int == invalidationIndex)
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
        await controller.worktreeFileMetadataScheduler.waitUntilDrained()
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

private actor FailingBridgeIntakeCapture {
    private var failureCount: Int
    private var deliveredFrames: [String] = []

    init(failureCount: Int) {
        self.failureCount = failureCount
    }

    func record(_ frameJSON: String) throws {
        if failureCount > 0 {
            failureCount -= 1
            throw BridgeProviderFailure.providerFailed(message: "Injected intake transport failure")
        }
        deliveredFrames.append(frameJSON)
    }

    func frames() -> [String] {
        deliveredFrames
    }
}
