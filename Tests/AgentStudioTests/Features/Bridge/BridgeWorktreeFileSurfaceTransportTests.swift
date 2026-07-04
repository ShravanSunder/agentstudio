import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileSurfaceTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("open source stream returns control outcome and delivers native Worktree/File snapshot by intake")
        func openSourceStreamReturnsControlOutcomeAndDeliversNativeSnapshotByIntake() async throws {
            let openedStream = try await openSourcesScopedStreamWithBridgeFile()
            let eventCapture = openedStream.eventCapture
            let fixture = openedStream.fixture
            let paneId = fixture.paneId
            let repoId = fixture.repoId
            let worktreeId = fixture.worktreeId
            let rootURL = fixture.rootURL
            defer { try? FileManager.default.removeItem(at: rootURL) }
            let controller = fixture.controller
            let response = openedStream.response
            assertAcceptedOpenResponse(response, paneId: paneId)

            await controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await controller.activeWorktreeFileTreeWindowTask?.value
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let snapshotJSON = try #require(await eventCapture.intakeFrames().first)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                snapshotJSON,
                as: BridgeWorktreeSnapshotFrame.self
            )
            #expect(snapshotEnvelope.kind == "snapshot")
            #expect(snapshotEnvelope.streamId == response.result.streamId)
            #expect(snapshotEnvelope.generation == response.result.generation)
            #expect(snapshotEnvelope.payload.frameKind == "worktree.snapshot")
            #expect(snapshotEnvelope.payload.source.repoId == repoId.uuidString)
            #expect(snapshotEnvelope.payload.source.worktreeId == worktreeId.uuidString)
            #expect(snapshotEnvelope.payload.source.subscriptionGeneration == 1)
            #expect(snapshotEnvelope.payload.statusPatch != nil)
            #expect(snapshotEnvelope.payload.requestSelector?.pathScope == ["Sources"])
            #expect(snapshotEnvelope.payload.treeRows.count == 2)
            let fileRow = try #require(
                snapshotEnvelope.payload.treeRows.first(where: { $0.path == "Sources/BridgeFileView.swift" })
            )
            #expect(fileRow.name == "BridgeFileView.swift")
            #expect(fileRow.parentPath == "Sources")
            #expect(fileRow.isDirectory == false)
            #expect(fileRow.fileId != nil)
            #expect(snapshotEnvelope.payload.treeSizeFacts.extentKind == .estimatedTotalHeight)
            #expect(snapshotEnvelope.payload.treeSizeFacts.pathCount == nil)
            #expect(controller.paneState.diff.packageMetadata == nil)

            controller.teardown()
        }

        @Test("Worktree/File intake ready rejects stale generations before flushing pending frames")
        func worktreeFileIntakeReadyRejectsStaleGenerationBeforeFlushingPendingFrames() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let fileURL = fixture.rootURL.appending(path: "BridgeFileView.swift")
            try "let bridgeFileView = true\n".write(to: fileURL, atomically: true, encoding: .utf8)

            let firstOutcome = try await fixture.controller.handleWorktreeFileSurfaceOpenSourceStream(
                sourceSpec(fixture: fixture, clientRequestId: "stale-ready-1", pathScope: [])
            )
            let secondOutcome = try await fixture.controller.handleWorktreeFileSurfaceOpenSourceStream(
                sourceSpec(fixture: fixture, clientRequestId: "stale-ready-2", pathScope: [])
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value

            #expect(firstOutcome.generation == 1)
            #expect(secondOutcome.generation == 2)
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 1)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: firstOutcome.streamId,
                    generation: firstOutcome.generation
                )
            )

            // Drain fence: if the stale-generation guard were removed, the
            // rejected ready would open the gate and schedule a detached
            // drain; without this wait the assertions below could race it
            // and pass falsely.
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 1)
            #expect(await eventCapture.intakeFrames().isEmpty)

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: secondOutcome.streamId,
                    generation: secondOutcome.generation
                )
            )

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 0)
            #expect(await eventCapture.intakeFrames().count == 1)

            fixture.controller.teardown()
        }

        @Test("Worktree/File intake flush retains queued frames after transport failure")
        func worktreeFileIntakeFlushRetainsQueuedFramesAfterTransportFailure() async throws {
            let intakeCapture = FailingWorktreeFileIntakeCapture(failureCount: 1)
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    try await intakeCapture.record(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            for index in 0..<210 {
                let fileURL = fixture.rootURL.appending(path: String(format: "File-%03d.swift", index))
                try "let value\(index) = \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let outcome = try await fixture.controller.handleWorktreeFileSurfaceOpenSourceStream(
                sourceSpec(fixture: fixture, clientRequestId: "retry-ready", pathScope: [])
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            // 210 rows enqueue two scheduler jobs: the foreground snapshot
            // (200-row startup window) and one idle continuation window.
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 2)

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            // The first delivery fails: the scheduler closes the gate and
            // retains the failed job at the front of its lane, so no queued
            // work is lost and nothing is delivered.
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 2)
            #expect(await intakeCapture.frames().isEmpty)

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: outcome.streamId,
                    generation: outcome.generation
                )
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            // Reopening the gate retries in order, delivering the retained
            // frames exactly once and in sequence order.
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 0)
            let deliveredFrames = await intakeCapture.frames()
            #expect(deliveredFrames.count == 2)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                deliveredFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            let windowEnvelope = try decodeIntakeEnvelope(
                deliveredFrames[1],
                as: BridgeWorktreeTreeWindowFrame.self
            )
            #expect(snapshotEnvelope.payload.frameKind == "worktree.snapshot")
            #expect(snapshotEnvelope.sequence == 0)
            #expect(windowEnvelope.payload.frameKind == "worktree.treeWindow")
            #expect(windowEnvelope.sequence == 1)

            fixture.controller.teardown()
        }

        @Test("failed descriptor delivery rolls back its sequence and redelivers without a gap")
        func failedDescriptorDeliveryRollsBackSequenceAndRedeliversWithoutGap() async throws {
            let intakeCapture = FailingWorktreeFileIntakeCapture(failingCallIndices: [1])
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    try await intakeCapture.record(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let fileURL = fixture.rootURL.appending(path: "File-000.swift")
            try "let value = 0\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-sequence-rollback",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-sequence-rollback",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let snapshot = try decodeIntakeEnvelope(
                try #require(await intakeCapture.frames().first),
                as: BridgeWorktreeSnapshotFrame.self
            )
            let selectedRow = try #require(snapshot.payload.treeRows.first { $0.path == "File-000.swift" })

            // Call 1 (the first descriptor delivery attempt) fails at the
            // transport: the scheduler retains the job, and the sequence
            // reservation must roll back so the retry redelivers with the
            // SAME sequence — a gap would wedge the browser's monotonic
            // intake gate into resetRequired.
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-sequence-rollback-descriptor",
                sourceIdentity: snapshot.payload.source,
                row: selectedRow,
                path: "File-000.swift",
                lane: .foreground
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect(await intakeCapture.frames().count == 1)
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 1)

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let deliveredFrames = await intakeCapture.frames()
            #expect(deliveredFrames.count == 2)
            let descriptorEnvelope = try decodeDescriptorEnvelope(try #require(deliveredFrames.last))
            #expect(descriptorEnvelope.sequence == 1)
            #expect(fixture.controller.activeWorktreeFileSurfaceSource?.nextSequence == 2)
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 0)

            fixture.controller.teardown()
        }

        private func openSourcesScopedStreamWithBridgeFile() async throws
            -> (
                fixture: BridgeWorktreeFileSurfaceControllerFixture,
                eventCapture: BridgeWorktreeFileSurfaceEventCapture,
                response: BridgeWorktreeFileSurfaceSuccessResponse
            )
        {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let scopedFileURL = fixture.rootURL
                .appending(path: "Sources")
                .appending(path: "BridgeFileView.swift")
            try FileManager.default.createDirectory(
                at: scopedFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "let bridgeFileView = true\n".write(to: scopedFileURL, atomically: true, encoding: .utf8)
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-1",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-1",
                        pathScope: ["Sources"]
                    )
                ).jsonString()
            )

            return (
                fixture: fixture,
                eventCapture: eventCapture,
                response: try await decodedResponse(from: responseCapture)
            )
        }

        private func assertAcceptedOpenResponse(
            _ response: BridgeWorktreeFileSurfaceSuccessResponse,
            paneId: UUID
        ) {
            #expect(response.jsonrpc == "2.0")
            #expect(response.id == "open-1")
            #expect(response.result.status == "accepted")
            #expect(response.result.protocolId == "worktree-file")
            #expect(response.result.streamId == "worktree-file:\(paneId.uuidString)")
            #expect(response.result.generation == 1)
        }

        @Test("open source stream continues file tree metadata after startup window")
        func openSourceStreamContinuesFileTreeMetadataAfterStartupWindow() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            for index in 0..<260 {
                let fileURL = fixture.rootURL.appending(path: String(format: "File-%03d.swift", index))
                try "let value\(index) = \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let capturedResponse = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await capturedResponse.set(responseJSON)
            }

            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-root",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-root-windowed-tree",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: capturedResponse)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 2)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                intakeFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            let windowEnvelope = try decodeIntakeEnvelope(
                intakeFrames[1],
                as: BridgeWorktreeTreeWindowFrame.self
            )
            #expect(snapshotEnvelope.payload.treeRows.count == 200)
            #expect(windowEnvelope.payload.frameKind == "worktree.treeWindow")
            #expect(windowEnvelope.payload.treeSizeFacts.extentKind == .exactPathCount)
            #expect(windowEnvelope.payload.treeSizeFacts.pathCount == 260)
            #expect(windowEnvelope.payload.treeSizeFacts.windowStartIndex == 200)
            #expect(windowEnvelope.payload.treeSizeFacts.windowRowCount == 60)
            #expect(windowEnvelope.payload.rows.count == 60)
            #expect(windowEnvelope.payload.rows.first?.path == "File-200.swift")
            #expect(windowEnvelope.payload.rows.last?.path == "File-259.swift")

            fixture.controller.teardown()
        }

        @Test("native metadata lanes expose startup and idle lineage with percentile capable timing")
        func nativeMetadataLanesExposeStartupAndIdleLineageWithPercentileCapableTiming() async throws {
            let telemetryRecorder = BridgeWorktreeFileTelemetryRecorderSpy()
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                telemetryRecorder: telemetryRecorder,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            for index in 0..<260 {
                let fileURL = fixture.rootURL.appending(path: String(format: "File-%03d.swift", index))
                try "let value\(index) = \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-native-lanes",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-native-lanes",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 2)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                intakeFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            let idleWindowEnvelope = try decodeIntakeEnvelope(
                intakeFrames[1],
                as: BridgeWorktreeTreeWindowFrame.self
            )
            #expect(snapshotEnvelope.sequence < idleWindowEnvelope.sequence)
            #expect(snapshotEnvelope.payload.treeRows.count == 200)
            #expect(idleWindowEnvelope.payload.rows.count == 60)
            #expect(idleWindowEnvelope.payload.treeSizeFacts.pathCount == 260)

            let snapshotRows = try treeRows(from: intakeFrames[0], rowsKey: "treeRows")
            let idleWindowRows = try treeRows(from: intakeFrames[1], rowsKey: "rows")
            #expect(
                try metadataLineage(from: intakeFrames[0])
                    == ["loadedBy": "startup_window", "lane": "foreground"]
            )
            #expect(try metadataLineage(from: intakeFrames[1]) == ["loadedBy": "idle", "lane": "idle"])
            #expect(snapshotRows.allSatisfy { $0["loaded_by"] == nil && $0["lane"] == nil })
            #expect(idleWindowRows.allSatisfy { $0["loaded_by"] == nil && $0["lane"] == nil })

            let selectedRow = try #require(snapshotEnvelope.payload.treeRows.first { $0.path == "File-000.swift" })
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-content-after-metadata-lanes",
                sourceIdentity: snapshotEnvelope.payload.source,
                row: selectedRow,
                path: "File-000.swift",
                lane: .foreground
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let demandFrames = await eventCapture.intakeFrames()
            #expect(demandFrames.count == 3)
            let descriptorEnvelope = try decodeDescriptorEnvelope(demandFrames[2])
            #expect(descriptorEnvelope.payload.frameKind == "worktree.fileDescriptor")
            #expect(descriptorEnvelope.sequence > idleWindowEnvelope.sequence)

            let windowSamples = await telemetryRecorder.samples(
                named: "performance.bridge.swift.worktree_file_tree_window_batch"
            )
            let timingSummary = BridgeWorktreeFileTimingPercentileSummary(
                samples: windowSamples.compactMap(\.durationMilliseconds)
            )
            #expect(timingSummary.sampleCount == windowSamples.count)
            #expect(timingSummary.p95Milliseconds != nil)
            #expect(timingSummary.p99Milliseconds != nil)
            let openToFirstWindowSamples = await telemetryRecorder.samples(
                named: "performance.bridge.native.metadata_open_to_first_window"
            )
            let fullManifestSamples = await telemetryRecorder.samples(
                named: "performance.bridge.native.metadata_full_manifest_complete"
            )
            assertNativeMetadataManifestTelemetry(
                openToFirstWindowSamples: openToFirstWindowSamples,
                fullManifestSamples: fullManifestSamples
            )

            fixture.controller.teardown()
        }

        private func assertNativeMetadataManifestTelemetry(
            openToFirstWindowSamples: [BridgeTelemetrySample],
            fullManifestSamples: [BridgeTelemetrySample]
        ) {
            #expect(openToFirstWindowSamples.count == 1)
            #expect(fullManifestSamples.count == 1)
            #expect(openToFirstWindowSamples.first?.durationMilliseconds != nil)
            #expect(fullManifestSamples.first?.durationMilliseconds != nil)
            #expect(
                fullManifestSamples.first?.numericAttributes[
                    "agentstudio.bridge.metadata_manifest.expected_total"
                ] == 260
            )
            #expect(
                fullManifestSamples.first?.numericAttributes[
                    "agentstudio.bridge.metadata_manifest.emitted_total"
                ] == 260
            )
            #expect(
                fullManifestSamples.first?.numericAttributes[
                    "agentstudio.bridge.metadata_manifest.remaining_total"
                ] == 0
            )
        }

        @Test("open source stream replays queued multi-window tree metadata when intake is late")
        func openSourceStreamReplaysQueuedMultiWindowTreeMetadataWhenIntakeIsLate() async throws {
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            for index in 0..<520 {
                let fileURL = fixture.rootURL.appending(path: String(format: "File-%03d.swift", index))
                try "let value\(index) = \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let capturedResponse = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await capturedResponse.set(responseJSON)
            }

            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-root-late-ready",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-root-late-ready-tree",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: capturedResponse)
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            #expect(await eventCapture.intakeFrames().isEmpty)
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 3)

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 3)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                intakeFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            let firstWindow = try decodeIntakeEnvelope(
                intakeFrames[1],
                as: BridgeWorktreeTreeWindowFrame.self
            )
            let secondWindow = try decodeIntakeEnvelope(
                intakeFrames[2],
                as: BridgeWorktreeTreeWindowFrame.self
            )
            #expect(snapshotEnvelope.sequence == 0)
            #expect(firstWindow.sequence == 1)
            #expect(secondWindow.sequence == 2)
            #expect(snapshotEnvelope.payload.treeRows.count == 200)
            #expect(firstWindow.payload.treeSizeFacts.windowStartIndex == 200)
            #expect(firstWindow.payload.treeSizeFacts.windowRowCount == 200)
            #expect(firstWindow.payload.treeSizeFacts.extentKind == .estimatedTotalHeight)
            #expect(firstWindow.payload.treeSizeFacts.pathCount == nil)
            #expect(secondWindow.payload.treeSizeFacts.windowStartIndex == 400)
            #expect(secondWindow.payload.treeSizeFacts.windowRowCount == 120)
            #expect(secondWindow.payload.treeSizeFacts.extentKind == .exactPathCount)
            #expect(secondWindow.payload.treeSizeFacts.pathCount == 520)
            #expect(secondWindow.payload.rows.last?.path == "File-519.swift")

            fixture.controller.teardown()
        }

        @Test("Worktree/File sequence reservation advances from the latest active cursor")
        func worktreeFileSequenceReservationAdvancesFromLatestActiveCursor() async throws {
            let fixture = try makeControllerFixture()
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }

            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-sequence-reservation",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-sequence-reservation",
                        pathScope: []
                    )
                ).jsonString()
            )

            _ = try await decodedResponse(from: responseCapture)
            fixture.controller.activeWorktreeFileTreeWindowTask?.cancel()
            fixture.controller.activeWorktreeFileTreeWindowTask = nil
            let activeSource = try #require(fixture.controller.activeWorktreeFileSurfaceSource)

            let firstReservation = try fixture.controller.reserveWorktreeFileSurfaceSequenceBlock(
                count: 2,
                source: activeSource.source,
                streamId: activeSource.streamId
            )
            let secondReservation = try fixture.controller.reserveWorktreeFileSurfaceSequenceBlock(
                count: 1,
                source: activeSource.source,
                streamId: activeSource.streamId
            )

            #expect(firstReservation == 0)
            #expect(secondReservation == 2)
            #expect(fixture.controller.activeWorktreeFileSurfaceSource?.nextSequence == 3)

            fixture.controller.teardown()
        }

    }
}

private actor FailingWorktreeFileIntakeCapture {
    private var failureCount: Int
    private let failingCallIndices: Set<Int>
    private var callIndex = 0
    private var deliveredFrames: [String] = []

    init(failureCount: Int) {
        self.failureCount = failureCount
        self.failingCallIndices = []
    }

    /// Fails specific 0-based delivery attempts so a test can target one
    /// frame kind (for example the first descriptor after a successful
    /// snapshot) instead of the first N calls.
    init(failingCallIndices: Set<Int>) {
        self.failureCount = 0
        self.failingCallIndices = failingCallIndices
    }

    func record(_ frameJSON: String) throws {
        let index = callIndex
        callIndex += 1
        if failureCount > 0 {
            failureCount -= 1
            throw BridgeProviderFailure.providerFailed(message: "Injected Worktree/File intake failure")
        }
        if failingCallIndices.contains(index) {
            throw BridgeProviderFailure.providerFailed(message: "Injected Worktree/File intake failure")
        }
        deliveredFrames.append(frameJSON)
    }

    func frames() -> [String] {
        deliveredFrames
    }
}

private struct RichWorktreeTreeResourceBody: Decodable {
    struct Row: Decodable {
        let rowId: String
        let path: String
        let name: String
        let parentPath: String?
        let isDirectory: Bool
        let fileId: String?
    }

    let rows: [Row]
}

private struct BridgeWorktreeFileTimingPercentileSummary {
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

func treeRows(from intakeFrameJSON: String, rowsKey: String) throws -> [[String: Any]] {
    let frameData = try #require(intakeFrameJSON.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: frameData) as? [String: Any])
    let payload = try #require(object["payload"] as? [String: Any])
    return try #require(payload[rowsKey] as? [[String: Any]])
}

/// S2 frame-level lineage: `worktree.snapshot` and `worktree.treeWindow`
/// payloads carry a required `metadataLineage` object (`loadedBy`/`lane`);
/// tree rows no longer carry per-row lineage.
func metadataLineage(from intakeFrameJSON: String) throws -> [String: String] {
    let frameData = try #require(intakeFrameJSON.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: frameData) as? [String: Any])
    let payload = try #require(object["payload"] as? [String: Any])
    return try #require(payload["metadataLineage"] as? [String: String])
}

func stringValues(in rows: [[String: Any]], forKey key: String) -> Set<String> {
    Set(rows.compactMap { $0[key] as? String })
}

/// Non-recording frame-kind probe. Unlike `treeRows`, this never asserts, so
/// it can classify a mixed delivery stream (snapshot / treeWindow /
/// descriptor) without failing on frames that lack the inspected key.
func worktreeFrameKind(from intakeFrameJSON: String) -> String? {
    guard let frameData = intakeFrameJSON.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: frameData) as? [String: Any],
        let payload = object["payload"] as? [String: Any]
    else {
        return nil
    }
    return payload["frameKind"] as? String
}

/// Non-recording accessor for a treeWindow frame's `rows`. Returns nil for
/// frames without a `rows` array (for example the snapshot, which carries
/// `treeRows`), so it can be used to classify frames in a mixed stream.
func worktreeWindowRows(from intakeFrameJSON: String) -> [[String: Any]]? {
    guard let frameData = intakeFrameJSON.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: frameData) as? [String: Any],
        let payload = object["payload"] as? [String: Any]
    else {
        return nil
    }
    return payload["rows"] as? [[String: Any]]
}

actor BridgeWorktreeFileTelemetryRecorderSpy: BridgePerformanceTraceRecording {
    private var recordedSamples: [BridgeTelemetrySample] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        recordedSamples.append(sample)
    }

    func recordDrop(
        reason: BridgeTelemetryDropReason,
        droppedCount: Int,
        firstRejectedEventName: String?,
        receivedAtUnixNano: UInt64
    ) async {
        _ = reason
        _ = droppedCount
        _ = firstRejectedEventName
        _ = receivedAtUnixNano
    }

    func drain() async throws {}

    func samples(named sampleName: String) -> [BridgeTelemetrySample] {
        recordedSamples.filter { $0.name == sampleName }
    }
}
