import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileSurfaceCurrentWorktreeProofTests: BridgeWorktreeFileSurfaceTransportTestHelpers {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("current worktree manifest proof records completeness lineage and percentiles")
        func currentWorktreeManifestProofRecordsCompletenessLineageAndPercentiles() async throws {
            let projectRoot = currentProjectRoot()
            let telemetryRecorder = BridgeWorktreeFileCurrentWorktreeTelemetryRecorder()
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let intakeDeliveryCapture = BridgeCurrentWorktreeProofIntakeDeliveryCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: projectRoot,
                telemetryRecorder: telemetryRecorder,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                    await intakeDeliveryCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            defer { fixture.controller.teardown() }

            let response = try await openCurrentWorktreeHeadlessProofStream(
                fixture: fixture,
                responseCapture: responseCapture
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            let interestProbePaths = try demandLaneInterestProbePaths(
                from: fixture.controller.pendingWorktreeFileIntakeFrames
            )
            let laneProbeResults = try await requestDemandLaneInterestProbes(
                controller: fixture.controller,
                generation: response.result.generation,
                paths: interestProbePaths,
                streamId: response.result.streamId
            )
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: response.result.streamId,
                    generation: response.result.generation
                )
            )

            let manifestFacts = try await currentWorktreeManifestFacts(from: eventCapture)
            let demandLaneFacts = try await currentWorktreeDemandLaneFacts(
                from: await eventCapture.intakeFrames(),
                laneProbeResults: laneProbeResults.probesByLane
            )
            let timingProof = try await currentWorktreeTimingProof(
                telemetryRecorder: telemetryRecorder
            )
            let metadataInterestTiming = try await currentWorktreeMetadataInterestTiming(
                deliveryRecords: intakeDeliveryCapture.intakeRecords(),
                requestTimings: laneProbeResults.requestTimings
            )
            let noStarvationProgress = try currentWorktreeNoStarvationProgress(
                from: await eventCapture.intakeFrames(),
                demandLaneFacts: demandLaneFacts,
                fullManifestSample: timingProof.fullManifestSample,
                manifestFacts: manifestFacts
            )
            assertCurrentWorktreeManifestFacts(
                manifestFacts,
                fullManifestSample: timingProof.fullManifestSample
            )
            try writeCurrentWorktreeManifestProofArtifact(
                CurrentWorktreeProofArtifactWriteRequest(
                    demandLaneFacts: demandLaneFacts,
                    fullManifestSample: timingProof.fullManifestSample,
                    manifestFacts: manifestFacts,
                    metadataInterestTiming: metadataInterestTiming,
                    noStarvationProgress: noStarvationProgress,
                    openToFirstWindowSummary: timingProof.openToFirstWindowSummary,
                    projectRoot: projectRoot,
                    treeWindowTimingSummary: timingProof.treeWindowTimingSummary
                )
            )
            try assertCurrentWorktreeBenchmarkArtifactHasDemandLoadingFields(projectRoot: projectRoot)
        }

        private func currentProjectRoot() -> URL {
            let projectRoot = URL(
                fileURLWithPath: ProcessInfo.processInfo.environment["PROJECT_ROOT"]
                    ?? FileManager.default.currentDirectoryPath
            ).standardizedFileURL
            #expect(FileManager.default.fileExists(atPath: projectRoot.appending(path: "Package.swift").path))
            return projectRoot
        }

        private func openCurrentWorktreeHeadlessProofStream(
            fixture: BridgeWorktreeFileSurfaceControllerFixture,
            responseCapture: BridgeWorktreeFileSurfaceResponseCapture
        ) async throws -> BridgeWorktreeFileSurfaceSuccessResponse {
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-current-worktree-headless-proof",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-current-worktree-headless-proof",
                        pathScope: []
                    )
                ).jsonString()
            )
            return try await decodedResponse(from: responseCapture)
        }

        private func demandLaneInterestProbePaths(
            from pendingFrames: [String]
        ) throws -> [BridgeDemandLane: String] {
            let idlePaths = try pendingFrames.compactMap { pendingFrame -> [String]? in
                let probe = try decodeIntakeEnvelope(pendingFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
                guard probe.payload.frameKind == "worktree.treeWindow" else { return nil }
                let window = try decodeIntakeEnvelope(pendingFrame, as: BridgeWorktreeTreeWindowFrame.self)
                return window.payload.rows.map(\.path)
            }.flatMap { $0 }
            #expect(idlePaths.count >= Self.demandLaneProofOrder.count)
            return Dictionary(
                uniqueKeysWithValues: zip(
                    Self.demandLaneProofOrder,
                    idlePaths.prefix(Self.demandLaneProofOrder.count)
                )
            )
        }

        private func requestDemandLaneInterestProbes(
            controller: BridgePaneController,
            generation: Int,
            paths: [BridgeDemandLane: String],
            streamId: String
        ) async throws -> BridgeCurrentWorktreeDemandLaneProbeResults {
            var results: [BridgeDemandLane: BridgeCurrentWorktreeDemandLaneProbe] = [:]
            var requestTimings: [BridgeCurrentWorktreeMetadataInterestRequestTiming] = []
            for lane in Self.demandLaneProofOrder {
                let path = try #require(paths[lane])
                let requestStartedAt = Date()
                await controller.handleIncomingRPC(
                    """
                    {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(streamId)","generation":\(generation),"paths":["\(path)"],"lane":"\(lane.rawValue)"},"id":"current-worktree-\(lane.rawValue)-interest"}
                    """
                )
                requestTimings.append(
                    BridgeCurrentWorktreeMetadataInterestRequestTiming(
                        expectedPath: path,
                        lane: lane.rawValue,
                        requestStartedAt: requestStartedAt
                    )
                )
                results[lane] = BridgeCurrentWorktreeDemandLaneProbe(
                    expectedLoadedBy: Self.expectedLoadedBy(for: lane),
                    expectedPath: path,
                    lane: lane.rawValue
                )
            }
            return BridgeCurrentWorktreeDemandLaneProbeResults(
                probesByLane: results,
                requestTimings: requestTimings
            )
        }

        private static let demandLaneProofOrder: [BridgeDemandLane] = [
            .foreground,
            .active,
            .visible,
            .nearby,
            .speculative,
            .idle,
        ]

        private static func expectedLoadedBy(for lane: BridgeDemandLane) -> String {
            switch lane {
            case .foreground, .active:
                "foreground"
            case .visible:
                "visible"
            case .nearby:
                "nearby"
            case .speculative:
                "speculative"
            case .idle:
                "idle"
            }
        }

        private func currentWorktreeManifestFacts(
            from eventCapture: BridgeWorktreeFileSurfaceEventCapture
        ) async throws -> BridgeCurrentWorktreeManifestFacts {
            var paths = Set<String>()
            var loadedByValues = Set<String>()
            var laneValues = Set<String>()
            var firstWindowRowCount = 0
            var latestExpectedTotal = 0
            var latestEmittedTotal = 0
            for intakeFrame in await eventCapture.intakeFrames() {
                let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
                switch probe.payload.frameKind {
                case "worktree.snapshot":
                    let snapshot = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeSnapshotFrame.self)
                    firstWindowRowCount = snapshot.payload.treeRows.count
                    try recordRows(
                        from: intakeFrame,
                        rowsKey: "treeRows",
                        paths: &paths,
                        loadedBy: &loadedByValues,
                        lanes: &laneValues
                    )
                    latestExpectedTotal = snapshot.payload.treeSizeFacts.pathCount ?? latestExpectedTotal
                    latestEmittedTotal = max(latestEmittedTotal, paths.count)
                case "worktree.treeWindow":
                    let window = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeTreeWindowFrame.self)
                    try recordRows(
                        from: intakeFrame,
                        rowsKey: "rows",
                        paths: &paths,
                        loadedBy: &loadedByValues,
                        lanes: &laneValues
                    )
                    latestExpectedTotal = window.payload.treeSizeFacts.pathCount ?? latestExpectedTotal
                    latestEmittedTotal = max(latestEmittedTotal, paths.count)
                default:
                    continue
                }
            }
            return BridgeCurrentWorktreeManifestFacts(
                finalRemainingRowCount: max(latestExpectedTotal - latestEmittedTotal, 0),
                firstWindowRowCount: firstWindowRowCount,
                laneValues: laneValues,
                loadedByValues: loadedByValues,
                uniquePathCount: paths.count
            )
        }

        private func currentWorktreeDemandLaneFacts(
            from intakeFrames: [String],
            laneProbeResults: [BridgeDemandLane: BridgeCurrentWorktreeDemandLaneProbe]
        ) async throws -> BridgeCurrentWorktreeDemandLaneFacts {
            var matchedProbes: [BridgeCurrentWorktreeDemandLaneProbe] = []
            var matchedLanes = Set<BridgeDemandLane>()
            var firstIdleDeliveryIndex: Int?
            for (deliveryIndex, intakeFrame) in intakeFrames.enumerated() {
                let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
                guard probe.payload.frameKind == "worktree.treeWindow" else { continue }
                let window = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeTreeWindowFrame.self)
                let rows = try treeRows(from: intakeFrame, rowsKey: "rows")
                let rowLanes = Set(rows.compactMap { $0["lane"] as? String })
                let rowLoadedByValues = Set(rows.compactMap { $0["loaded_by"] as? String })
                if rowLanes == ["idle"], rows.count > 1, firstIdleDeliveryIndex == nil {
                    firstIdleDeliveryIndex = deliveryIndex
                }
                for lane in Self.demandLaneProofOrder {
                    guard let expectedProbe = laneProbeResults[lane],
                        !matchedLanes.contains(lane),
                        rows.contains(where: { $0["path"] as? String == expectedProbe.expectedPath })
                    else {
                        continue
                    }
                    #expect(rowLanes == [expectedProbe.lane])
                    #expect(rowLoadedByValues == [expectedProbe.expectedLoadedBy])
                    matchedProbes.append(
                        BridgeCurrentWorktreeDemandLaneProbe(
                            expectedLoadedBy: expectedProbe.expectedLoadedBy,
                            expectedPath: expectedProbe.expectedPath,
                            lane: expectedProbe.lane,
                            deliveryIndex: deliveryIndex,
                            sequence: window.sequence
                        )
                    )
                    matchedLanes.insert(lane)
                }
            }
            let probeDeliveryIndices = matchedProbes.compactMap(\.deliveryIndex)
            let allInterestBeforeIdle =
                if let firstIdleDeliveryIndex {
                    probeDeliveryIndices.allSatisfy { $0 < firstIdleDeliveryIndex }
                } else {
                    false
                }
            #expect(matchedProbes.count == Self.demandLaneProofOrder.count)
            #expect(allInterestBeforeIdle)
            return BridgeCurrentWorktreeDemandLaneFacts(
                allInterestBeforeIdleContinuation: allInterestBeforeIdle,
                firstIdleContinuationDeliveryIndex: firstIdleDeliveryIndex,
                probes: matchedProbes.sorted { $0.lane < $1.lane }
            )
        }

        private func currentWorktreeMetadataInterestTiming(
            deliveryRecords: [BridgeCurrentWorktreeProofIntakeDeliveryRecord],
            requestTimings: [BridgeCurrentWorktreeMetadataInterestRequestTiming]
        ) throws -> BridgeCurrentWorktreeMetadataInterestTimingFacts {
            let samples = try requestTimings.map { requestTiming in
                let deliveryIndex = try #require(
                    deliveryRecords.firstIndex { record in
                        guard
                            let rows = optionalTreeRows(from: record.frameJSON, rowsKey: "rows")
                        else {
                            return false
                        }
                        return rows.contains {
                            $0["path"] as? String == requestTiming.expectedPath
                                && $0["lane"] as? String == requestTiming.lane
                        }
                    }
                )
                let deliveredRecord = deliveryRecords[deliveryIndex]
                let window = try decodeIntakeEnvelope(
                    deliveredRecord.frameJSON,
                    as: BridgeWorktreeTreeWindowFrame.self
                )
                let durationMilliseconds =
                    deliveredRecord.deliveredAt.timeIntervalSince(requestTiming.requestStartedAt) * 1000
                #expect(durationMilliseconds >= 0)
                return BridgeCurrentWorktreeMetadataInterestTimingSample(
                    deliveredFrameSequence: window.sequence,
                    deliveryIndex: deliveryIndex,
                    durationMilliseconds: durationMilliseconds,
                    expectedPath: requestTiming.expectedPath,
                    lane: requestTiming.lane
                )
            }
            let summary = BridgeCurrentWorktreeTimingPercentileSummary(
                samples: samples.map(\.durationMilliseconds)
            )
            #expect(samples.count == Self.demandLaneProofOrder.count)
            #expect(summary.p95Milliseconds != nil)
            #expect(summary.p99Milliseconds != nil)
            return BridgeCurrentWorktreeMetadataInterestTimingFacts(
                measurementName: "metadata_interest_request_to_delivered_intake_frame",
                measurementScope:
                    "headless Swift intake delivery; includes intake-ready wait and does not claim provider queue wait",
                sampleCount: summary.sampleCount,
                p95Milliseconds: summary.p95Milliseconds,
                p99Milliseconds: summary.p99Milliseconds,
                samples: samples.sorted { $0.lane < $1.lane }
            )
        }

        private func currentWorktreeNoStarvationProgress(
            from intakeFrames: [String],
            demandLaneFacts: BridgeCurrentWorktreeDemandLaneFacts,
            fullManifestSample: BridgeTelemetrySample,
            manifestFacts: BridgeCurrentWorktreeManifestFacts
        ) throws -> BridgeCurrentWorktreeNoStarvationProgress {
            let expectedTotal = Int(
                fullManifestSample.numericAttributes[
                    "agentstudio.bridge.metadata_manifest.expected_total"
                ] ?? Double(manifestFacts.uniquePathCount)
            )
            let emittedTotal = Int(
                fullManifestSample.numericAttributes[
                    "agentstudio.bridge.metadata_manifest.emitted_total"
                ] ?? Double(manifestFacts.uniquePathCount)
            )
            let remainingTotal = Int(
                fullManifestSample.numericAttributes[
                    "agentstudio.bridge.metadata_manifest.remaining_total"
                ] ?? Double(manifestFacts.finalRemainingRowCount)
            )
            let completed =
                fullManifestSample.booleanAttributes[
                    "agentstudio.bridge.metadata_manifest.complete"
                ] == true
            let probeDeliveryIndices = Set(demandLaneFacts.probes.compactMap(\.deliveryIndex))
            let firstIdleContinuationDeliveryIndex = try #require(
                demandLaneFacts.firstIdleContinuationDeliveryIndex
            )
            var interestRowsBeforeIdleContinuation = 0
            var idleContinuationRowsAfterInterest = 0
            for (deliveryIndex, intakeFrame) in intakeFrames.enumerated() {
                let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
                guard probe.payload.frameKind == "worktree.treeWindow" else { continue }
                let rows = try treeRows(from: intakeFrame, rowsKey: "rows")
                if probeDeliveryIndices.contains(deliveryIndex),
                    deliveryIndex < firstIdleContinuationDeliveryIndex
                {
                    interestRowsBeforeIdleContinuation += rows.count
                    continue
                }
                let rowLanes = Set(rows.compactMap { $0["lane"] as? String })
                if deliveryIndex >= firstIdleContinuationDeliveryIndex,
                    rowLanes == ["idle"],
                    rows.count > 1
                {
                    idleContinuationRowsAfterInterest += rows.count
                }
            }
            #expect(manifestFacts.firstWindowRowCount > 0)
            #expect(interestRowsBeforeIdleContinuation >= Self.demandLaneProofOrder.count)
            #expect(idleContinuationRowsAfterInterest > 0)
            #expect(expectedTotal == emittedTotal)
            #expect(remainingTotal == 0)
            #expect(completed)
            return BridgeCurrentWorktreeNoStarvationProgress(
                initialEmittedRows: manifestFacts.firstWindowRowCount,
                interestRowsBeforeIdleContinuation: interestRowsBeforeIdleContinuation,
                idleContinuationRowsAfterInterest: idleContinuationRowsAfterInterest,
                expectedTotal: expectedTotal,
                emittedTotal: emittedTotal,
                remainingTotal: remainingTotal,
                completed: completed
            )
        }

        private func currentWorktreeTimingProof(
            telemetryRecorder: BridgeWorktreeFileCurrentWorktreeTelemetryRecorder
        ) async throws -> BridgeCurrentWorktreeTimingProof {
            let fullManifestSamples = await telemetryRecorder.samples(
                named: "performance.bridge.native.metadata_full_manifest_complete"
            )
            let fullManifestSample = try #require(fullManifestSamples.first)
            #expect(fullManifestSamples.count == 1)
            #expect(fullManifestSample.booleanAttributes["agentstudio.bridge.metadata_manifest.complete"] == true)
            #expect(fullManifestSample.durationMilliseconds != nil)

            let openToFirstWindowSamples = await telemetryRecorder.samples(
                named: "performance.bridge.native.metadata_open_to_first_window"
            )
            let openToFirstWindowSummary = BridgeCurrentWorktreeTimingPercentileSummary(
                samples: openToFirstWindowSamples.compactMap(\.durationMilliseconds)
            )
            #expect(openToFirstWindowSummary.sampleCount > 0)
            #expect(openToFirstWindowSummary.p95Milliseconds != nil)
            #expect(openToFirstWindowSummary.p99Milliseconds != nil)

            let timingSamples = await telemetryRecorder.samples(
                named: "performance.bridge.swift.worktree_file_tree_window_batch"
            )
            let timingSummary = BridgeCurrentWorktreeTimingPercentileSummary(
                samples: timingSamples.compactMap(\.durationMilliseconds)
            )
            #expect(timingSummary.sampleCount > 0)
            #expect(timingSummary.p95Milliseconds != nil)
            #expect(timingSummary.p99Milliseconds != nil)
            return BridgeCurrentWorktreeTimingProof(
                fullManifestSample: fullManifestSample,
                openToFirstWindowSummary: openToFirstWindowSummary,
                treeWindowTimingSummary: timingSummary
            )
        }

        private func assertCurrentWorktreeManifestFacts(
            _ manifestFacts: BridgeCurrentWorktreeManifestFacts,
            fullManifestSample: BridgeTelemetrySample
        ) {
            let expectedTotal = fullManifestSample.numericAttributes[
                "agentstudio.bridge.metadata_manifest.expected_total"
            ]
            let emittedTotal = fullManifestSample.numericAttributes[
                "agentstudio.bridge.metadata_manifest.emitted_total"
            ]
            #expect(expectedTotal == emittedTotal)
            #expect(Int(expectedTotal ?? 0) == manifestFacts.uniquePathCount)
            #expect(manifestFacts.uniquePathCount > 200)
            #expect(manifestFacts.loadedByValues.isSuperset(of: ["startup_window", "idle"]))
            #expect(manifestFacts.laneValues.isSuperset(of: ["foreground", "idle"]))
            #expect(manifestFacts.firstWindowRowCount == 200)
            #expect(manifestFacts.finalRemainingRowCount == 0)
        }

        private func recordRows(
            from intakeFrame: String,
            rowsKey: String,
            paths: inout Set<String>,
            loadedBy: inout Set<String>,
            lanes: inout Set<String>
        ) throws {
            let data = try #require(intakeFrame.data(using: .utf8))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let payload = try #require(object["payload"] as? [String: Any])
            let rows = try #require(payload[rowsKey] as? [[String: Any]])
            paths.formUnion(rows.compactMap { $0["path"] as? String })
            loadedBy.formUnion(rows.compactMap { $0["loaded_by"] as? String })
            lanes.formUnion(rows.compactMap { $0["lane"] as? String })
        }

        private func treeRows(from intakeFrame: String, rowsKey: String) throws -> [[String: Any]] {
            let data = try #require(intakeFrame.data(using: .utf8))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let payload = try #require(object["payload"] as? [String: Any])
            return try #require(payload[rowsKey] as? [[String: Any]])
        }

        private func optionalTreeRows(from intakeFrame: String, rowsKey: String) -> [[String: Any]]? {
            guard
                let data = intakeFrame.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = object["payload"] as? [String: Any]
            else {
                return nil
            }
            return payload[rowsKey] as? [[String: Any]]
        }

        private func assertCurrentWorktreeBenchmarkArtifactHasDemandLoadingFields(projectRoot: URL) throws {
            guard
                let proofDirectory = ProcessInfo.processInfo.environment[
                    "AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR"
                ],
                !proofDirectory.isEmpty
            else {
                return
            }
            let artifactURL = proofArtifactDirectoryURL(
                proofDirectory,
                projectRoot: projectRoot
            ).appending(path: "current-worktree-manifest-proof.json")
            let artifactData = try Data(contentsOf: artifactURL)
            let artifactObject = try #require(
                JSONSerialization.jsonObject(with: artifactData) as? [String: Any]
            )
            let metadataInterestTiming = try #require(
                artifactObject["metadataInterestRequestToDeliveredFrame"] as? [String: Any]
            )
            #expect(
                metadataInterestTiming["measurementName"] as? String
                    == "metadata_interest_request_to_delivered_intake_frame"
            )
            #expect(metadataInterestTiming["sampleCount"] as? Int == Self.demandLaneProofOrder.count)
            #expect(metadataInterestTiming["p95Milliseconds"] != nil)
            #expect(metadataInterestTiming["p99Milliseconds"] != nil)
            let noStarvationProgress = try #require(
                artifactObject["noStarvationProgress"] as? [String: Any]
            )
            #expect(noStarvationProgress["initialEmittedRows"] as? Int == 200)
            #expect(
                noStarvationProgress["interestRowsBeforeIdleContinuation"] as? Int
                    ?? 0 >= Self.demandLaneProofOrder.count
            )
            #expect(noStarvationProgress["idleContinuationRowsAfterInterest"] as? Int ?? 0 > 0)
            #expect(noStarvationProgress["expectedTotal"] as? Int == noStarvationProgress["emittedTotal"] as? Int)
            #expect(noStarvationProgress["remainingTotal"] as? Int == 0)
            #expect(noStarvationProgress["completed"] as? Bool == true)
        }
    }
}

private actor BridgeCurrentWorktreeProofIntakeDeliveryCapture {
    private var records: [BridgeCurrentWorktreeProofIntakeDeliveryRecord] = []

    func recordIntake(_ frameJSON: String) {
        records.append(
            BridgeCurrentWorktreeProofIntakeDeliveryRecord(
                deliveredAt: Date(),
                frameJSON: frameJSON
            )
        )
    }

    func intakeRecords() -> [BridgeCurrentWorktreeProofIntakeDeliveryRecord] {
        records
    }
}

private struct BridgeCurrentWorktreeProofIntakeDeliveryRecord: Sendable {
    let deliveredAt: Date
    let frameJSON: String
}

private struct BridgeCurrentWorktreeFrameKindProbe: Decodable {
    let frameKind: String
}

private struct BridgeCurrentWorktreeManifestFacts {
    let finalRemainingRowCount: Int
    let firstWindowRowCount: Int
    let laneValues: Set<String>
    let loadedByValues: Set<String>
    let uniquePathCount: Int
}

private struct BridgeCurrentWorktreeDemandLaneFacts: Encodable {
    let allInterestBeforeIdleContinuation: Bool
    let firstIdleContinuationDeliveryIndex: Int?
    let probes: [BridgeCurrentWorktreeDemandLaneProbe]
}

private struct BridgeCurrentWorktreeDemandLaneProbeResults {
    let probesByLane: [BridgeDemandLane: BridgeCurrentWorktreeDemandLaneProbe]
    let requestTimings: [BridgeCurrentWorktreeMetadataInterestRequestTiming]
}

private struct BridgeCurrentWorktreeDemandLaneProbe: Encodable {
    let expectedLoadedBy: String
    let expectedPath: String
    let lane: String
    var deliveryIndex: Int?
    var sequence: Int?
}

private struct BridgeCurrentWorktreeMetadataInterestRequestTiming {
    let expectedPath: String
    let lane: String
    let requestStartedAt: Date
}

private struct BridgeCurrentWorktreeMetadataInterestTimingFacts: Encodable {
    let measurementName: String
    let measurementScope: String
    let sampleCount: Int
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?
    let samples: [BridgeCurrentWorktreeMetadataInterestTimingSample]
}

private struct BridgeCurrentWorktreeMetadataInterestTimingSample: Encodable {
    let deliveredFrameSequence: Int
    let deliveryIndex: Int
    let durationMilliseconds: Double
    let expectedPath: String
    let lane: String
}

private struct BridgeCurrentWorktreeNoStarvationProgress: Encodable {
    let initialEmittedRows: Int
    let interestRowsBeforeIdleContinuation: Int
    let idleContinuationRowsAfterInterest: Int
    let expectedTotal: Int
    let emittedTotal: Int
    let remainingTotal: Int
    let completed: Bool
}

private struct BridgeCurrentWorktreeTimingProof {
    let fullManifestSample: BridgeTelemetrySample
    let openToFirstWindowSummary: BridgeCurrentWorktreeTimingPercentileSummary
    let treeWindowTimingSummary: BridgeCurrentWorktreeTimingPercentileSummary
}

private struct BridgeCurrentWorktreeTimingPercentileSummary {
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

private struct BridgeCurrentWorktreeManifestProofArtifact: Encodable {
    let scenarioId: String
    let runtime: String
    let demandLaneFacts: BridgeCurrentWorktreeDemandLaneFacts
    let expectedMetadataRowTotal: Int
    let emittedMetadataRowTotal: Int
    let remainingMetadataRowTotal: Int
    let uniquePathCount: Int
    let firstWindowRowCount: Int
    let loadedByValues: [String]
    let laneValues: [String]
    let metadataInterestRequestToDeliveredFrame: BridgeCurrentWorktreeMetadataInterestTimingFacts
    let noStarvationProgress: BridgeCurrentWorktreeNoStarvationProgress
    let openToFirstWindow: CurrentWorktreeTimingProofArtifact
    let treeWindowBatch: CurrentWorktreeTimingProofArtifact
    let fullManifestComplete: CurrentWorktreeTimingProofArtifact
}

private struct CurrentWorktreeTimingProofArtifact: Encodable {
    let sampleCount: Int
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?

    init(_ summary: BridgeCurrentWorktreeTimingPercentileSummary) {
        self.sampleCount = summary.sampleCount
        self.p95Milliseconds = summary.p95Milliseconds
        self.p99Milliseconds = summary.p99Milliseconds
    }
}

private struct CurrentWorktreeProofArtifactWriteRequest {
    let demandLaneFacts: BridgeCurrentWorktreeDemandLaneFacts
    let fullManifestSample: BridgeTelemetrySample
    let manifestFacts: BridgeCurrentWorktreeManifestFacts
    let metadataInterestTiming: BridgeCurrentWorktreeMetadataInterestTimingFacts
    let noStarvationProgress: BridgeCurrentWorktreeNoStarvationProgress
    let openToFirstWindowSummary: BridgeCurrentWorktreeTimingPercentileSummary
    let projectRoot: URL
    let treeWindowTimingSummary: BridgeCurrentWorktreeTimingPercentileSummary
}

private func writeCurrentWorktreeManifestProofArtifact(
    _ request: CurrentWorktreeProofArtifactWriteRequest
) throws {
    guard
        let proofDirectory = ProcessInfo.processInfo.environment[
            "AGENTSTUDIO_BRIDGE_HEADLESS_PROOF_DIR"
        ],
        !proofDirectory.isEmpty
    else {
        return
    }

    let proofDirectoryURL = proofArtifactDirectoryURL(
        proofDirectory,
        projectRoot: request.projectRoot
    )
    try FileManager.default.createDirectory(
        at: proofDirectoryURL,
        withIntermediateDirectories: true
    )

    let expectedTotal = Int(
        request.fullManifestSample.numericAttributes[
            "agentstudio.bridge.metadata_manifest.expected_total"
        ] ?? Double(request.manifestFacts.uniquePathCount)
    )
    let emittedTotal = Int(
        request.fullManifestSample.numericAttributes[
            "agentstudio.bridge.metadata_manifest.emitted_total"
        ] ?? Double(request.manifestFacts.uniquePathCount)
    )
    let remainingTotal = Int(
        request.fullManifestSample.numericAttributes[
            "agentstudio.bridge.metadata_manifest.remaining_total"
        ] ?? Double(request.manifestFacts.finalRemainingRowCount)
    )
    let fullManifestSummary = BridgeCurrentWorktreeTimingPercentileSummary(
        samples: [request.fullManifestSample.durationMilliseconds].compactMap { $0 }
    )
    let artifact = BridgeCurrentWorktreeManifestProofArtifact(
        scenarioId: "native-headless-manifest-completeness",
        runtime: "swift-headless",
        demandLaneFacts: request.demandLaneFacts,
        expectedMetadataRowTotal: expectedTotal,
        emittedMetadataRowTotal: emittedTotal,
        remainingMetadataRowTotal: remainingTotal,
        uniquePathCount: request.manifestFacts.uniquePathCount,
        firstWindowRowCount: request.manifestFacts.firstWindowRowCount,
        loadedByValues: request.manifestFacts.loadedByValues.sorted(),
        laneValues: request.manifestFacts.laneValues.sorted(),
        metadataInterestRequestToDeliveredFrame: request.metadataInterestTiming,
        noStarvationProgress: request.noStarvationProgress,
        openToFirstWindow: CurrentWorktreeTimingProofArtifact(
            request.openToFirstWindowSummary
        ),
        treeWindowBatch: CurrentWorktreeTimingProofArtifact(
            request.treeWindowTimingSummary
        ),
        fullManifestComplete: CurrentWorktreeTimingProofArtifact(
            fullManifestSummary
        )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let artifactData = try encoder.encode(artifact)
    try artifactData.write(
        to: proofDirectoryURL.appending(path: "current-worktree-manifest-proof.json"),
        options: .atomic
    )
}

private func proofArtifactDirectoryURL(_ proofDirectory: String, projectRoot: URL) -> URL {
    let proofDirectoryURL = URL(fileURLWithPath: proofDirectory)
    if proofDirectoryURL.path.hasPrefix("/") {
        return proofDirectoryURL
    }
    return projectRoot.appending(path: proofDirectory)
}

private actor BridgeWorktreeFileCurrentWorktreeTelemetryRecorder: BridgePerformanceTraceRecording {
    private var recordedSamples: [BridgeTelemetrySample] = []

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
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
