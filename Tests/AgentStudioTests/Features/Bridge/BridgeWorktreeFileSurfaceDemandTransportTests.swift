import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileSurfaceDemandTransportTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("foreground descriptor demand does not starve behind a queued idle tree window")
        func foregroundDescriptorDemandDoesNotStarveBehindQueuedIdleTreeWindow() async throws {
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
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-tree-publishing",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-tree-publishing",
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
                try #require(await eventCapture.intakeFrames().first),
                as: BridgeWorktreeSnapshotFrame.self
            )
            let selectedRow = try #require(snapshot.payload.treeRows.first { $0.path == "File-000.swift" })
            let baselineFrameCount = await eventCapture.intakeFrames().count

            await fixture.controller.worktreeFileMetadataScheduler.closeGate(protocolId: "worktree-file")
            await fixture.controller.handleIncomingRPC(
                """
                {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(response.result.streamId)","generation":\(response.result.generation),"paths":["File-250.swift"],"lane":"idle"},"id":"descriptor-starve-idle-window"}
                """
            )
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "request-foreground-descriptor",
                sourceIdentity: snapshot.payload.source,
                row: selectedRow,
                path: "File-000.swift",
                lane: .foreground
            )
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 2)

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 0)

            let contendedFrameKinds = Array(await eventCapture.intakeFrames().dropFirst(baselineFrameCount))
                .compactMap { worktreeFrameKind(from: $0) }
            let descriptorIndex = try #require(
                contendedFrameKinds.firstIndex(of: "worktree.fileDescriptor")
            )
            let treeWindowIndex = try #require(
                contendedFrameKinds.firstIndex(of: "worktree.treeWindow")
            )
            #expect(descriptorIndex < treeWindowIndex)

            fixture.controller.teardown()
        }

        @Test("foreground metadata interest does not starve behind queued idle tree windows")
        func foregroundMetadataInterestDoesNotStarveBehindQueuedIdleTreeWindows() async throws {
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
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-worktree-interest",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-worktree-interest",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 2)

            await fixture.controller.handleIncomingRPC(
                """
                {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(response.result.streamId)","generation":\(response.result.generation),"paths":["File-240.swift"],"lane":"foreground"},"id":"worktree-foreground-interest"}
                """
            )
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: response.result.streamId,
                    generation: response.result.generation
                )
            )

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 3)
            let snapshotFrame = try #require(intakeFrames.first)
            let foregroundWindowFrame = try #require(intakeFrames.dropFirst().first)
            let idleWindowFrame = try #require(intakeFrames.dropFirst(2).first)
            let snapshot = try decodeIntakeEnvelope(snapshotFrame, as: BridgeWorktreeSnapshotFrame.self)
            let foregroundWindow = try decodeIntakeEnvelope(
                foregroundWindowFrame,
                as: BridgeWorktreeTreeWindowFrame.self
            )
            let idleWindow = try decodeIntakeEnvelope(idleWindowFrame, as: BridgeWorktreeTreeWindowFrame.self)
            #expect(snapshot.payload.frameKind == "worktree.snapshot")
            #expect(foregroundWindow.payload.rows.contains { $0.path == "File-240.swift" })
            #expect(idleWindow.payload.rows.first?.path == "File-200.swift")

            let foregroundRows = try treeRows(from: foregroundWindowFrame, rowsKey: "rows")
            let idleRows = try treeRows(from: idleWindowFrame, rowsKey: "rows")
            #expect(stringValues(in: foregroundRows, forKey: "loaded_by") == ["foreground"])
            #expect(stringValues(in: foregroundRows, forKey: "lane") == ["foreground"])
            #expect(stringValues(in: idleRows, forKey: "loaded_by") == ["idle"])
            #expect(stringValues(in: idleRows, forKey: "lane") == ["idle"])

            fixture.controller.teardown()
        }

        @Test("metadata interest records spec loaded_by lineage for each demand lane")
        func metadataInterestRecordsSpecLoadedByLineageForEachDemandLane() async throws {
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
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-worktree-lanes",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-worktree-lanes",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            let laneExpectations: [(lane: String, path: String, loadedBy: String)] = [
                ("foreground", "File-240.swift", "foreground"),
                ("active", "File-241.swift", "foreground"),
                ("visible", "File-242.swift", "visible"),
                ("nearby", "File-243.swift", "nearby"),
                ("speculative", "File-244.swift", "speculative"),
                ("idle", "File-245.swift", "idle"),
            ]
            for laneExpectation in laneExpectations {
                await fixture.controller.handleIncomingRPC(
                    """
                    {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(response.result.streamId)","generation":\(response.result.generation),"paths":["\(laneExpectation.path)"],"lane":"\(laneExpectation.lane)"},"id":"worktree-\(laneExpectation.lane)-interest"}
                    """
                )
            }

            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: response.result.streamId,
                    generation: response.result.generation
                )
            )
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 8)
            var probeIndexByPath: [String: Int] = [:]
            var continuationWindowIndex: Int?
            for (index, frameJSON) in intakeFrames.enumerated() {
                guard let rows = worktreeWindowRows(from: frameJSON) else { continue }
                if rows.count == 1, let path = rows[0]["path"] as? String {
                    probeIndexByPath[path] = index
                } else {
                    continuationWindowIndex = index
                }
            }
            for laneExpectation in laneExpectations {
                let frameIndex = try #require(probeIndexByPath[laneExpectation.path])
                let rows = try treeRows(from: intakeFrames[frameIndex], rowsKey: "rows")
                #expect(rows.contains { $0["path"] as? String == laneExpectation.path })
                #expect(stringValues(in: rows, forKey: "loaded_by") == [laneExpectation.loadedBy])
                #expect(stringValues(in: rows, forKey: "lane") == [laneExpectation.lane])
            }

            let budget = AppPolicies.Bridge.metadataIdleNoStarvationBudget
            let continuationIndex = try #require(continuationWindowIndex)
            let foregroundIndex = try #require(probeIndexByPath["File-240.swift"])
            let activeIndex = try #require(probeIndexByPath["File-241.swift"])
            let visibleIndex = try #require(probeIndexByPath["File-242.swift"])
            let nearbyIndex = try #require(probeIndexByPath["File-243.swift"])
            let speculativeIndex = try #require(probeIndexByPath["File-244.swift"])
            let idleProbeIndex = try #require(probeIndexByPath["File-245.swift"])
            #expect(continuationIndex == budget)
            #expect(foregroundIndex < continuationIndex)
            #expect(activeIndex < continuationIndex)
            #expect(visibleIndex < continuationIndex)
            #expect(continuationIndex < nearbyIndex)
            #expect(continuationIndex < speculativeIndex)
            #expect(nearbyIndex < idleProbeIndex)
            #expect(speculativeIndex < idleProbeIndex)
            #expect(idleProbeIndex == intakeFrames.count - 1)

            let idleContinuationRows = try treeRows(from: intakeFrames[continuationIndex], rowsKey: "rows")
            #expect(idleContinuationRows.count == 60)
            #expect(idleContinuationRows.first?["path"] as? String == "File-200.swift")
            #expect(stringValues(in: idleContinuationRows, forKey: "loaded_by") == ["idle"])
            #expect(stringValues(in: idleContinuationRows, forKey: "lane") == ["idle"])

            fixture.controller.teardown()
        }

        @Test("metadata interest rejects stale Worktree/File stream identity and generation")
        func metadataInterestRejectsStaleWorktreeFileStreamIdentityAndGeneration() async throws {
            let fixture = try makeControllerFixture()
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            let fileURL = fixture.rootURL.appending(path: "File.swift")
            try "let file = true\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let outcome = try await fixture.controller.handleWorktreeFileSurfaceOpenSourceStream(
                sourceSpec(
                    fixture: fixture,
                    clientRequestId: "request-stale-interest",
                    pathScope: []
                )
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value

            await #expect(throws: Error.self) {
                try await fixture.controller.handleWorktreeFileMetadataInterestUpdate(
                    ReviewMethods.MetadataInterestUpdateMethod.Params(
                        protocolId: "worktree-file",
                        streamId: "worktree-file:stale",
                        generation: outcome.generation,
                        itemIds: nil,
                        paths: ["File.swift"],
                        lane: .foreground,
                        loadedBy: nil
                    )
                )
            }
            await #expect(throws: Error.self) {
                try await fixture.controller.handleWorktreeFileMetadataInterestUpdate(
                    ReviewMethods.MetadataInterestUpdateMethod.Params(
                        protocolId: "worktree-file",
                        streamId: outcome.streamId,
                        generation: outcome.generation + 1,
                        itemIds: nil,
                        paths: ["File.swift"],
                        lane: .foreground,
                        loadedBy: nil
                    )
                )
            }
            #expect(await fixture.controller.worktreeFileMetadataScheduler.queuedJobCount == 1)

            fixture.controller.teardown()
        }

        @Test("tree window publication records per-window latency telemetry")
        func treeWindowPublicationRecordsPerWindowLatencyTelemetry() async throws {
            let telemetryRecorder = BridgeWorktreeFileTelemetryRecorderSpy()
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                telemetryRecorder: telemetryRecorder,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
            for index in 0..<430 {
                let fileURL = fixture.rootURL.appending(path: "Sources/File-\(String(format: "%03d", index)).swift")
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "let value\(index) = \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-tree-telemetry",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-tree-telemetry",
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

            let windowSamples = await telemetryRecorder.samples(
                named: "performance.bridge.swift.worktree_file_tree_window_batch"
            )
            #expect(windowSamples.count >= 2)
            #expect(
                windowSamples.allSatisfy {
                    $0.numericAttributes["agentstudio.bridge.worktree_file.tree.window.row.count"] ?? 0 > 0
                }
            )
            #expect(
                windowSamples.allSatisfy {
                    $0.durationMilliseconds != nil
                }
            )

            fixture.controller.teardown()
        }
    }
}
