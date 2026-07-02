import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeReviewMetadataWindowTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("loadDiff replays queued multi-window review metadata when intake is late")
        func loadDiffReplaysQueuedMultiWindowReviewMetadataWhenIntakeIsLate() async throws {
            let capturedIntakeFrames = WebKitSerializedTests.BridgePaneControllerTests.SendableBox<[String]>([])
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFiles = (0..<245).map { index in
                makeBridgeEndpointChangedFile(
                    fileId: "changed-\(index)",
                    path: String(format: "Sources/App/Changed%03d.swift", index),
                    sizeBytes: 100
                )
            }
            let expectedReviewItemIds = changedFiles.map { "item-\($0.fileId)" }
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
            let commandId = UUID()

            let result = await controller.handleDiffCommand(
                DiffCommand.loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            #expect(await capturedIntakeFrames.get().isEmpty)
            #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 5)

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let capturedFrameJSON = await capturedIntakeFrames.get()
            let capturedFrames: [[String: Any]] = try capturedFrameJSON.map(Self.reviewIntakeFrameObject)
            #expect(capturedFrames.map { $0["sequence"] as? Int } == [0, 1, 2, 3, 4])
            let resetFrame = try #require(capturedFrames.first)
            #expect(resetFrame["kind"] as? String == "reset")
            let snapshotFrame = try #require(capturedFrames.dropFirst().first)
            let snapshotPayload = try #require(snapshotFrame["payload"] as? [String: Any])
            #expect(snapshotPayload["frameKind"] as? String == "review.metadataSnapshot")
            #expect(snapshotPayload["sequence"] as? Int == 1)
            #expect(snapshotPayload["selectedItemId"] as? String == "item-changed-0")
            let snapshotVisibleItemIds = try #require(snapshotPayload["visibleItemIds"] as? [String])
            #expect(snapshotVisibleItemIds.count == 80)
            #expect(snapshotVisibleItemIds.first == "item-changed-0")
            #expect(snapshotVisibleItemIds.last == "item-changed-79")
            let snapshotItems = try #require(snapshotPayload["itemMetadata"] as? [[String: Any]])
            #expect(snapshotItems.count == 80)
            let snapshotItemIds = snapshotItems.compactMap { $0["itemId"] as? String }
            #expect(snapshotItemIds == snapshotVisibleItemIds)
            let snapshotTreeRows = try #require(snapshotPayload["treeRows"] as? [[String: Any]])
            #expect(Self.uniqueStringValues(in: snapshotItems, forKey: "loaded_by") == ["startup_window"])
            #expect(Self.uniqueStringValues(in: snapshotItems, forKey: "lane") == ["foreground"])
            #expect(Self.uniqueStringValues(in: snapshotTreeRows, forKey: "loaded_by") == ["startup_window"])
            #expect(Self.uniqueStringValues(in: snapshotTreeRows, forKey: "lane") == ["foreground"])

            let metadataWindowPayloads = try capturedFrames.dropFirst(2).map { frame in
                let payload = try #require(frame["payload"] as? [String: Any])
                #expect(payload["frameKind"] as? String == "review.metadataWindow")
                return payload
            }
            let metadataWindowCounts = try metadataWindowPayloads.map { payload in
                try #require(payload["itemMetadata"] as? [[String: Any]]).count
            }
            #expect(metadataWindowCounts == [80, 80, 5])
            #expect(metadataWindowCounts.reduce(snapshotItems.count, +) == changedFiles.count)
            let metadataWindowItemIds = metadataWindowPayloads.flatMap { payload in
                (payload["itemMetadata"] as? [[String: Any]] ?? []).compactMap { $0["itemId"] as? String }
            }
            #expect(Set(snapshotItemIds).isDisjoint(with: Set(metadataWindowItemIds)))
            #expect(snapshotItemIds + metadataWindowItemIds == expectedReviewItemIds)
            #expect(metadataWindowPayloads.compactMap { $0["sequence"] as? Int } == [2, 3, 4])
            for metadataWindowPayload in metadataWindowPayloads {
                let windowItems = try #require(metadataWindowPayload["itemMetadata"] as? [[String: Any]])
                let windowTreeRows = try #require(metadataWindowPayload["treeRows"] as? [[String: Any]])
                #expect(Self.uniqueStringValues(in: windowItems, forKey: "loaded_by") == ["idle"])
                #expect(Self.uniqueStringValues(in: windowItems, forKey: "lane") == ["idle"])
                #expect(Self.uniqueStringValues(in: windowTreeRows, forKey: "loaded_by") == ["idle"])
                #expect(Self.uniqueStringValues(in: windowTreeRows, forKey: "lane") == ["idle"])
            }
            let lastWindowPayload = try #require(metadataWindowPayloads.last)
            let lastWindowItems = try #require(lastWindowPayload["itemMetadata"] as? [[String: Any]])
            let lastWindowPaths = lastWindowItems.compactMap { $0["headPath"] as? String }
            #expect(lastWindowPaths.last == "Sources/App/Changed244.swift")
        }

        @Test("review metadata windows record percentile-capable Swift timing samples")
        func reviewMetadataWindowsRecordPercentileCapableSwiftTimingSamples() async throws {
            let telemetryRecorder = BridgeReviewMetadataTelemetryRecorderSpy()
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFiles = (0..<245).map { index in
                makeBridgeEndpointChangedFile(
                    fileId: "changed-\(index)",
                    path: String(format: "Sources/App/Changed%03d.swift", index),
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
                telemetryRecorder: telemetryRecorder,
                intakeFrameSink: { _, _, _ in }
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()
            let commandId = UUID()

            let result = await controller.handleDiffCommand(
                DiffCommand.loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            // Window batch telemetry records inside scheduler jobs, so the
            // windows must drain through an open review gate first.
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let samples = await telemetryRecorder.samples(
                named: "performance.bridge.swift.review_metadata_window_batch"
            )
            #expect(samples.count == 3)
            #expect(samples.allSatisfy { $0.durationMilliseconds != nil })
            #expect(
                samples.allSatisfy { sample in
                    sample.stringAttributes["agentstudio.bridge.phase"] == "review_metadata_window_batch"
                        && sample.stringAttributes["agentstudio.bridge.plane"] == "data"
                        && sample.stringAttributes["agentstudio.bridge.priority"] == "cold"
                        && sample.stringAttributes["agentstudio.bridge.slice"] == "review_metadata"
                        && sample.stringAttributes["agentstudio.bridge.transport"] == "swift"
                })
            let timingSummary = BridgeReviewMetadataTimingPercentileSummary(
                samples: samples.compactMap(\.durationMilliseconds)
            )
            #expect(timingSummary.sampleCount == samples.count)
            #expect(timingSummary.p95Milliseconds != nil)
            #expect(timingSummary.p99Milliseconds != nil)
        }

        @Test("foreground metadata interest does not starve behind queued idle review windows")
        func foregroundMetadataInterestDoesNotStarveBehindQueuedIdleReviewWindows() async throws {
            let capturedIntakeFrames = WebKitSerializedTests.BridgePaneControllerTests.SendableBox<[String]>([])
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFiles = (0..<245).map { index in
                makeBridgeEndpointChangedFile(
                    fileId: "changed-\(index)",
                    path: String(format: "Sources/App/Changed%03d.swift", index),
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
            let commandId = UUID()

            let result = await controller.handleDiffCommand(
                DiffCommand.loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            #expect(await capturedIntakeFrames.get().isEmpty)
            #expect(await controller.worktreeFileMetadataScheduler.queuedJobCount == 5)
            await controller.handleIncomingRPC(
                """
                {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"review","streamId":"\(controller.reviewProtocolStreamId())","itemIds":["item-changed-160"],"lane":"foreground"},"id":"foreground-interest"}
                """
            )
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            // Sequences are consumed at dispatch inside the serialized drain,
            // so the foreground interest window still jumps ahead of the
            // queued speculative startup windows while the wire sequences
            // stay monotonic (the old buffer delivered [0, 1, 5, 2, 3, 4]).
            let capturedFrameJSON = await capturedIntakeFrames.get()
            let capturedFrames: [[String: Any]] = try capturedFrameJSON.map(Self.reviewIntakeFrameObject)
            #expect(capturedFrames.map { $0["sequence"] as? Int } == [0, 1, 2, 3, 4, 5])
            let foregroundPayload = try #require(capturedFrames.dropFirst(2).first?["payload"] as? [String: Any])
            let foregroundItems = try #require(foregroundPayload["itemMetadata"] as? [[String: Any]])
            #expect(foregroundPayload["frameKind"] as? String == "review.metadataWindow")
            #expect(foregroundItems.compactMap { $0["itemId"] as? String } == ["item-changed-160"])
            #expect(Self.uniqueStringValues(in: foregroundItems, forKey: "loaded_by") == ["foreground"])
            #expect(Self.uniqueStringValues(in: foregroundItems, forKey: "lane") == ["foreground"])
            let firstIdlePayload = try #require(capturedFrames.dropFirst(3).first?["payload"] as? [String: Any])
            let firstIdleItems = try #require(firstIdlePayload["itemMetadata"] as? [[String: Any]])
            #expect(Self.uniqueStringValues(in: firstIdleItems, forKey: "loaded_by") == ["idle"])
            #expect(Self.uniqueStringValues(in: firstIdleItems, forKey: "lane") == ["idle"])
        }

        @Test("metadata interest records Review loaded_by lineage for interactive demand lanes")
        func metadataInterestRecordsReviewLoadedByLineageForInteractiveDemandLanes() async throws {
            let capturedIntakeFrames = WebKitSerializedTests.BridgePaneControllerTests.SendableBox<[String]>([])
            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let changedFiles = (0..<245).map { index in
                makeBridgeEndpointChangedFile(
                    fileId: "changed-\(index)",
                    path: String(format: "Sources/App/Changed%03d.swift", index),
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
            let commandId = UUID()

            let result = await controller.handleDiffCommand(
                DiffCommand.loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )

            #expect(result == .success(commandId: commandId))
            let laneExpectations: [(lane: String, itemId: String, loadedBy: String)] = [
                ("active", "item-changed-150", "foreground"),
                ("visible", "item-changed-151", "visible"),
                ("nearby", "item-changed-152", "nearby"),
                ("speculative", "item-changed-153", "speculative"),
            ]
            for laneExpectation in laneExpectations {
                await controller.handleIncomingRPC(
                    """
                    {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"review","streamId":"\(controller.reviewProtocolStreamId())","itemIds":["\(laneExpectation.itemId)"],"lane":"\(laneExpectation.lane)"},"id":"review-\(laneExpectation.lane)-interest"}
                    """
                )
            }
            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "review", streamId: nil)
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()

            // Strict lane priority with dispatch-time sequences: active
            // (scheduled foreground), visible, and nearby interest drain
            // before the queued speculative startup windows; speculative
            // interest queues FIFO behind those windows in its own lane, so
            // it delivers last. Wire sequences stay monotonic (the old
            // buffer delivered [0, 1, 5, 6, 7, 8, 2, 3, 4]).
            let capturedFrameJSON = await capturedIntakeFrames.get()
            let capturedFrames: [[String: Any]] = try capturedFrameJSON.map(Self.reviewIntakeFrameObject)
            #expect(capturedFrames.map { $0["sequence"] as? Int } == [0, 1, 2, 3, 4, 5, 6, 7, 8])
            let interestFrameIndexByLane = [
                "active": 2,
                "visible": 3,
                "nearby": 4,
                "speculative": capturedFrames.count - 1,
            ]
            for laneExpectation in laneExpectations {
                let frameIndex = try #require(interestFrameIndexByLane[laneExpectation.lane])
                let payload = try #require(capturedFrames[frameIndex]["payload"] as? [String: Any])
                let items = try #require(payload["itemMetadata"] as? [[String: Any]])
                let treeRows = try #require(payload["treeRows"] as? [[String: Any]])
                #expect(payload["frameKind"] as? String == "review.metadataWindow")
                #expect(items.compactMap { $0["itemId"] as? String } == [laneExpectation.itemId])
                #expect(Self.uniqueStringValues(in: items, forKey: "loaded_by") == [laneExpectation.loadedBy])
                #expect(Self.uniqueStringValues(in: items, forKey: "lane") == [laneExpectation.lane])
                #expect(Self.uniqueStringValues(in: treeRows, forKey: "loaded_by") == [laneExpectation.loadedBy])
                #expect(Self.uniqueStringValues(in: treeRows, forKey: "lane") == [laneExpectation.lane])
            }
        }

        static func reviewIntakeFrameObject(_ frameJSON: String) throws -> [String: Any] {
            let frameData = try #require(frameJSON.data(using: .utf8))
            return try #require(JSONSerialization.jsonObject(with: frameData) as? [String: Any])
        }

        static func uniqueStringValues(in objects: [[String: Any]], forKey key: String) -> [String] {
            Array(Set(objects.compactMap { $0[key] as? String })).sorted()
        }
    }
}

private actor BridgeReviewMetadataTelemetryRecorderSpy: BridgePerformanceTraceRecording {
    private var recordedSamples: [BridgeTelemetrySample] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        _ = receivedAtUnixNano
        recordedSamples.append(sample)
    }

    func recordDrop(
        reason: BridgeTelemetryDropReason,
        droppedCount: Int,
        receivedAtUnixNano: UInt64
    ) async {
        _ = reason
        _ = droppedCount
        _ = receivedAtUnixNano
    }

    func drain() async throws {}

    func samples(named sampleName: String) -> [BridgeTelemetrySample] {
        recordedSamples.filter { $0.name == sampleName }
    }
}

private struct BridgeReviewMetadataTimingPercentileSummary {
    let sampleCount: Int
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?

    init(samples: [Double]) {
        let sortedSamples = samples.sorted()
        self.sampleCount = sortedSamples.count
        self.p95Milliseconds = Self.percentile(0.95, samples: sortedSamples)
        self.p99Milliseconds = Self.percentile(0.99, samples: sortedSamples)
    }

    private static func percentile(_ percentile: Double, samples: [Double]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }
        let rank = percentile * Double(samples.count - 1)
        let lowerIndex = Int(floor(rank))
        let upperIndex = Int(ceil(rank))
        guard lowerIndex != upperIndex else {
            return samples[lowerIndex]
        }
        let weight = rank - Double(lowerIndex)
        return samples[lowerIndex] + ((samples[upperIndex] - samples[lowerIndex]) * weight)
    }
}
