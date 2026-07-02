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

        private func makeCurrentWorktreeProofHarness() throws -> BridgeCurrentWorktreeProofHarness {
            let projectRoot = currentProjectRoot()
            let telemetryRecorder = BridgeWorktreeFileCurrentWorktreeTelemetryRecorder(
                traceRuntime: currentWorktreeProofTraceRuntime()
            )
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
            return BridgeCurrentWorktreeProofHarness(
                eventCapture: eventCapture,
                fixture: fixture,
                intakeDeliveryCapture: intakeDeliveryCapture,
                projectRoot: projectRoot,
                responseCapture: responseCapture,
                telemetryRecorder: telemetryRecorder
            )
        }

        @Test("current worktree manifest proof records completeness lineage and percentiles")
        func currentWorktreeManifestProofRecordsCompletenessLineageAndPercentiles() async throws {
            let harness = try makeCurrentWorktreeProofHarness()
            defer { harness.fixture.controller.teardown() }

            let response = try await openCurrentWorktreeHeadlessProofStream(
                fixture: harness.fixture,
                responseCapture: harness.responseCapture
            )
            await harness.fixture.controller.activeWorktreeFileTreeWindowTask?.value
            let manifestIndex = try #require(harness.fixture.controller.activeWorktreeFileManifestIndex)
            let interestProbePaths = try await demandLaneInterestProbePaths(
                from: manifestIndex
            )
            let laneProbeResults = try await requestDemandLaneInterestProbes(
                controller: harness.fixture.controller,
                generation: response.result.generation,
                paths: interestProbePaths,
                streamId: response.result.streamId
            )
            await harness.fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(
                    protocolId: "worktree-file",
                    streamId: response.result.streamId,
                    generation: response.result.generation
                )
            )
            await harness.fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()

            let manifestFacts = try await currentWorktreeManifestFacts(
                from: harness.eventCapture,
                projectRoot: harness.projectRoot
            )
            let demandLaneFacts = try await currentWorktreeDemandLaneFacts(
                from: await harness.eventCapture.intakeFrames(),
                laneProbeResults: laneProbeResults.probesByLane
            )
            let timingProof = try await currentWorktreeTimingProof(
                telemetryRecorder: harness.telemetryRecorder
            )
            let metadataInterestTiming = try await currentWorktreeMetadataInterestTiming(
                deliveryRecords: harness.intakeDeliveryCapture.intakeRecords(),
                requestTimings: laneProbeResults.requestTimings
            )
            let schedulerQueueWaitByLane = try await currentWorktreeSchedulerQueueWaitByLane(
                telemetryRecorder: harness.telemetryRecorder
            )
            let contentDemandProof = try await currentWorktreeContentDemandProof(
                eventCapture: harness.eventCapture,
                fixture: harness.fixture
            )
            let gatedBenchmark = try await currentWorktreeGatedBenchmarkProof(
                BridgeCurrentWorktreeGatedBenchmarkProofRequest(
                    controller: harness.fixture.controller,
                    deliveryCapture: harness.intakeDeliveryCapture,
                    eventCapture: harness.eventCapture,
                    fixture: harness.fixture,
                    generation: response.result.generation,
                    manifestIndex: manifestIndex,
                    streamId: response.result.streamId,
                    telemetryRecorder: harness.telemetryRecorder
                )
            )
            let noStarvationProgress = try currentWorktreeNoStarvationProgress(
                from: await harness.eventCapture.intakeFrames(),
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
                    contentDemandProof: contentDemandProof,
                    fullManifestSample: timingProof.fullManifestSample,
                    manifestFacts: manifestFacts,
                    metadataInterestTiming: metadataInterestTiming,
                    noStarvationProgress: noStarvationProgress,
                    openToFirstWindowSummary: timingProof.openToFirstWindowSummary,
                    projectRoot: harness.projectRoot,
                    gatedBenchmark: gatedBenchmark,
                    schedulerQueueWaitByLane: schedulerQueueWaitByLane,
                    treeWindowTimingSummary: timingProof.treeWindowTimingSummary
                )
            )
            try await harness.telemetryRecorder.drain()
            try assertCurrentWorktreeBenchmarkArtifactHasDemandLoadingFields(projectRoot: harness.projectRoot)
        }

        @Test("manifest completeness ignores demand interest tree windows")
        func manifestCompletenessIgnoresDemandInterestTreeWindows() {
            var manifestRows = BridgeCurrentWorktreeManifestRowAccumulator()
            let interestOnlyRows: [[String: Any]] = [
                [
                    "path": "Sources/OnlyInDemandInterest.swift",
                    "isDirectory": false,
                    "loaded_by": "foreground",
                    "lane": "foreground",
                ]
            ]

            manifestRows.recordRows(
                interestOnlyRows,
                treeWindowKey: "worktree-interest-source-1-foreground-10"
            )

            #expect(manifestRows.paths.isEmpty)
            #expect(manifestRows.filePaths.isEmpty)
            #expect(manifestRows.loadedByValues.isEmpty)
            #expect(manifestRows.laneValues.isEmpty)

            manifestRows.recordRows(
                interestOnlyRows,
                treeWindowKey: "worktree-tree-source-1-200"
            )

            #expect(manifestRows.paths == ["Sources/OnlyInDemandInterest.swift"])
            #expect(manifestRows.filePaths == ["Sources/OnlyInDemandInterest.swift"])
            #expect(manifestRows.loadedByValues == ["foreground"])
            #expect(manifestRows.laneValues == ["foreground"])
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
            from manifestIndex: BridgeWorktreeFileManifestIndex
        ) async throws -> [BridgeDemandLane: String] {
            // Probe paths are manifest members past the startup window, so
            // each probe targets rows that would otherwise arrive as idle
            // continuation. The index is the manifest authority; no frame
            // buffer inspection and no re-enumeration.
            let idlePaths = await manifestIndex.orderedPaths(
                startIndex: AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit,
                limit: Self.demandLaneProofOrder.count * 4
            )
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
            from eventCapture: BridgeWorktreeFileSurfaceEventCapture,
            projectRoot: URL
        ) async throws -> BridgeCurrentWorktreeManifestFacts {
            let expectedFilePaths = try await expectedPublishedCurrentWorktreeFilePaths(
                rootURL: projectRoot
            )
            var manifestRows = BridgeCurrentWorktreeManifestRowAccumulator()
            var firstWindowRowCount = 0
            var latestExpectedTotal = 0
            var latestEmittedTotal = 0
            for intakeFrame in await eventCapture.intakeFrames() {
                let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
                switch probe.payload.frameKind {
                case "worktree.snapshot":
                    let snapshot = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeSnapshotFrame.self)
                    firstWindowRowCount = snapshot.payload.treeRows.count
                    let rows = try treeRows(from: intakeFrame, rowsKey: "treeRows")
                    manifestRows.recordRows(
                        rows,
                        treeWindowKey: nil,
                    )
                    latestExpectedTotal = snapshot.payload.treeSizeFacts.pathCount ?? latestExpectedTotal
                    latestEmittedTotal = max(latestEmittedTotal, manifestRows.paths.count)
                case "worktree.treeWindow":
                    let window = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeTreeWindowFrame.self)
                    let rows = try treeRows(from: intakeFrame, rowsKey: "rows")
                    manifestRows.recordRows(
                        rows,
                        treeWindowKey: window.payload.projectionIdentity.treeWindowKey,
                    )
                    latestExpectedTotal = window.payload.treeSizeFacts.pathCount ?? latestExpectedTotal
                    latestEmittedTotal = max(latestEmittedTotal, manifestRows.paths.count)
                default:
                    continue
                }
            }
            return BridgeCurrentWorktreeManifestFacts(
                expectedFilePaths: expectedFilePaths,
                finalRemainingRowCount: max(latestExpectedTotal - latestEmittedTotal, 0),
                firstWindowRowCount: firstWindowRowCount,
                laneValues: manifestRows.laneValues,
                loadedByValues: manifestRows.loadedByValues,
                uniquePathCount: manifestRows.paths.count,
                uniqueFilePaths: manifestRows.filePaths
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
                    // Interest windows serve exactly the requested paths, so a
                    // probe's window is the single-row frame for its path. The
                    // idle continuation batch also carries probe paths (it
                    // streams the whole manifest tail) and may deliver before
                    // later probes under the no-starvation budget, so a
                    // contains-only match would misattribute those probes.
                    guard let expectedProbe = laneProbeResults[lane],
                        !matchedLanes.contains(lane),
                        rows.count == 1,
                        rows.first?["path"] as? String == expectedProbe.expectedPath,
                        rowLanes == [expectedProbe.lane],
                        rowLoadedByValues == [expectedProbe.expectedLoadedBy]
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
            // Under the real scheduler the idle no-starvation budget services
            // one idle batch per N higher-lane jobs. The snapshot consumes one
            // budget slot, so exactly budget-1 probes are guaranteed to
            // precede the first idle continuation batch; later higher-lane
            // probes interleave per budget, and the idle-lane probe delivers
            // within the idle stream in arrival order.
            let guaranteedLanesBeforeIdle = Set(
                Self.demandLaneProofOrder
                    .prefix(AppPolicies.Bridge.metadataIdleNoStarvationBudget - 1)
                    .map(\.rawValue)
            )
            let guaranteedProbeDeliveryIndices =
                matchedProbes
                .filter { guaranteedLanesBeforeIdle.contains($0.lane) }
                .compactMap(\.deliveryIndex)
            let allInterestBeforeIdle =
                if let firstIdleDeliveryIndex {
                    guaranteedProbeDeliveryIndices.allSatisfy { $0 < firstIdleDeliveryIndex }
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

        func currentWorktreeMetadataInterestTiming(
            deliveryRecords: [BridgeCurrentWorktreeProofIntakeDeliveryRecord],
            requestTimings: [BridgeCurrentWorktreeMetadataInterestRequestTiming],
            minimumSampleCount: Int? = nil
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
            let sampleCountByLane = Dictionary(grouping: samples, by: \.lane)
                .mapValues(\.count)
            if let minimumSampleCount {
                #expect(samples.count >= minimumSampleCount)
            } else {
                #expect(samples.count == Self.demandLaneProofOrder.count)
            }
            #expect(summary.p95Milliseconds != nil)
            #expect(summary.p99Milliseconds != nil)
            return BridgeCurrentWorktreeMetadataInterestTimingFacts(
                measurementName: "metadata_interest_request_to_delivered_intake_frame",
                measurementScope:
                    "headless Swift intake delivery; includes intake-ready wait and does not claim provider queue wait",
                sampleCount: summary.sampleCount,
                sampleCountByLane: sampleCountByLane,
                p95Milliseconds: summary.p95Milliseconds,
                p99Milliseconds: summary.p99Milliseconds,
                samples: samples.sorted { $0.lane < $1.lane }
            )
        }

        private func currentWorktreeContentDemandProof(
            eventCapture: BridgeWorktreeFileSurfaceEventCapture,
            fixture: BridgeWorktreeFileSurfaceControllerFixture
        ) async throws -> BridgeCurrentWorktreeContentDemandProof {
            let intakeFramesBeforeDemand = await eventCapture.intakeFrames()
            let demandRow = try firstContentDemandRow(from: intakeFramesBeforeDemand)
            let sourceIdentity = try firstSourceIdentity(from: intakeFramesBeforeDemand)
            let descriptorDemandStart = Date()
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "current-worktree-content-descriptor-demand",
                sourceIdentity: sourceIdentity,
                row: demandRow,
                path: demandRow.path,
                lane: .foreground
            )
            await waitForIntakeFrameCount(
                intakeFramesBeforeDemand.count + 1,
                from: eventCapture,
                description: "Content descriptor demand should emit descriptor frame"
            )
            let intakeFramesAfterDemand = await eventCapture.intakeFrames()
            let descriptorFrameJSON = try #require(intakeFramesAfterDemand.last)
            let descriptorDemandMilliseconds = Date().timeIntervalSince(descriptorDemandStart) * 1000
            let descriptorEnvelope = try decodeDescriptorEnvelope(descriptorFrameJSON)
            #expect(descriptorEnvelope.payload.frameKind == "worktree.fileDescriptor")
            #expect(descriptorEnvelope.payload.descriptor.path == demandRow.path)
            let schemeHandler = BridgeSchemeHandler(
                paneId: fixture.paneId,
                worktreeFileResourceStore: fixture.controller.worktreeFileResourceStore,
                resourceLeaseRegistry: fixture.controller.resourceLeaseRegistry
            )
            let contentFetchStart = Date()
            let contentBody = try await resourceBody(
                url: descriptorEnvelope.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                handler: schemeHandler
            )
            let contentFetchMilliseconds = Date().timeIntervalSince(contentFetchStart) * 1000
            #expect(!contentBody.isEmpty)
            return BridgeCurrentWorktreeContentDemandProof(
                contentDescriptorDemand: BridgeCurrentWorktreePhaseTimingFacts(
                    measurementName: "content_descriptor_demand",
                    measurementScope: "headless Swift descriptor demand RPC to descriptor intake frame",
                    samples: [descriptorDemandMilliseconds]
                ),
                contentFetch: BridgeCurrentWorktreePhaseTimingFacts(
                    measurementName: "content_fetch",
                    measurementScope: "headless Swift descriptor body read through BridgeSchemeHandler",
                    samples: [contentFetchMilliseconds]
                ),
                demandedPath: demandRow.path
            )
        }

        private func currentWorktreeSchedulerQueueWaitByLane(
            telemetryRecorder: BridgeWorktreeFileCurrentWorktreeTelemetryRecorder
        ) async throws -> [String: BridgeCurrentWorktreePhaseTimingFacts] {
            let samples = await telemetryRecorder.samples(
                named: "performance.bridge.viewer.demand_queue_wait"
            )
            let factsByLane = queueWaitByLaneFacts(from: samples)
            for lane in Self.demandLaneProofOrder {
                let laneFacts = try #require(factsByLane[lane.rawValue])
                #expect(laneFacts.measurementName == "metadata_scheduler_queue_wait_by_lane")
                #expect(laneFacts.measurementScope == "native scheduler enqueue-to-dequeue queue wait for lane")
                #expect(laneFacts.sampleCount > 0)
                #expect(laneFacts.p95Milliseconds != nil)
                #expect(laneFacts.p99Milliseconds != nil)
            }
            return factsByLane
        }

        private func firstContentDemandRow(
            from intakeFrames: [String]
        ) throws -> BridgeWorktreeTreeRowMetadata {
            for intakeFrame in intakeFrames {
                let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
                switch probe.payload.frameKind {
                case "worktree.snapshot":
                    let snapshot = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeSnapshotFrame.self)
                    if let row = snapshot.payload.treeRows.first(where: { $0.fileId != nil && !$0.isDirectory }) {
                        return row
                    }
                case "worktree.treeWindow":
                    let window = try decodeIntakeEnvelope(intakeFrame, as: BridgeWorktreeTreeWindowFrame.self)
                    if let row = window.payload.rows.first(where: { $0.fileId != nil && !$0.isDirectory }) {
                        return row
                    }
                default:
                    continue
                }
            }
            Issue.record("Expected at least one file row for content descriptor demand proof")
            throw BridgeProviderFailure.providerFailed(message: "missingContentDemandRow")
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
            #expect(
                interestRowsBeforeIdleContinuation
                    >= AppPolicies.Bridge.metadataIdleNoStarvationBudget - 1
            )
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
            #expect(manifestFacts.expectedFilePaths.isEmpty == false)
            #expect(manifestFacts.uniqueFilePaths.count == manifestFacts.expectedFilePaths.count)
            #expect(manifestFacts.missingExpectedFilePaths.isEmpty)
            #expect(manifestFacts.unexpectedPublishedFilePaths.isEmpty)
            #expect(
                manifestFacts.uniquePathCount > AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
            )
            #expect(manifestFacts.loadedByValues.isSuperset(of: ["startup_window", "idle"]))
            #expect(manifestFacts.laneValues.isSuperset(of: ["foreground", "idle"]))
            #expect(
                manifestFacts.firstWindowRowCount
                    == AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
            )
            #expect(manifestFacts.finalRemainingRowCount == 0)
        }

        private func expectedPublishedCurrentWorktreeFilePaths(rootURL: URL) async throws -> Set<String> {
            let ignorePolicy = await BridgeWorktreeFileIgnorePolicy.load(rootURL: rootURL)
            var expectedFilePaths = Set<String>()
            var pendingDirectories = [rootURL.standardizedFileURL]

            while !pendingDirectories.isEmpty {
                let directoryURL = pendingDirectories.removeFirst()
                let childURLs = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: []
                )
                for childURL in childURLs {
                    let relativePath = expectedRelativePath(fileURL: childURL, rootURL: rootURL)
                    guard isExpectedPublishedPath(relativePath, ignorePolicy: ignorePolicy) else {
                        continue
                    }
                    let values = try? childURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                    if values?.isRegularFile == true {
                        expectedFilePaths.insert(relativePath)
                    } else if values?.isDirectory == true,
                        !isNestedExpectedWorktreeRoot(childURL, rootURL: rootURL)
                    {
                        pendingDirectories.append(childURL)
                    }
                }
            }

            return expectedFilePaths
        }

        private func isExpectedPublishedPath(
            _ relativePath: String,
            ignorePolicy: BridgeWorktreeFileIgnorePolicy
        ) -> Bool {
            guard relativePath.isEmpty == false,
                relativePath != ".",
                relativePath.hasPrefix("/") == false,
                relativePath != ".git",
                relativePath.hasPrefix(".git/") == false
            else {
                return false
            }
            let pathComponents = relativePath.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            guard pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                return false
            }
            return !ignorePolicy.isIgnored(relativePath: relativePath)
        }

        private func isNestedExpectedWorktreeRoot(_ directoryURL: URL, rootURL: URL) -> Bool {
            let canonicalDirectoryURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
            let canonicalRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalDirectoryURL.path != canonicalRootURL.path else {
                return false
            }
            return FileManager.default.fileExists(atPath: canonicalDirectoryURL.appending(path: ".git").path)
        }

        private func expectedRelativePath(fileURL: URL, rootURL: URL) -> String {
            let rootPath = rootURL.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            let prefix = rootPath == "/" ? "/" : rootPath + "/"
            guard let range = filePath.range(of: prefix, options: [.anchored]) else {
                return fileURL.lastPathComponent
            }
            return String(filePath[range.upperBound...])
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
            #expect(artifactObject["expectedMetadataFileTotal"] as? Int ?? 0 > 0)
            #expect(
                artifactObject["expectedMetadataFileTotal"] as? Int
                    == artifactObject["emittedMetadataFileTotal"] as? Int
            )
            #expect((artifactObject["missingExpectedFilePaths"] as? [String])?.isEmpty == true)
            #expect((artifactObject["unexpectedPublishedFilePaths"] as? [String])?.isEmpty == true)
            let noStarvationProgress = try #require(
                artifactObject["noStarvationProgress"] as? [String: Any]
            )
            #expect(
                noStarvationProgress["initialEmittedRows"] as? Int
                    == AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
            )
            #expect(
                noStarvationProgress["interestRowsBeforeIdleContinuation"] as? Int
                    ?? 0 >= AppPolicies.Bridge.metadataIdleNoStarvationBudget - 1
            )
            #expect(noStarvationProgress["idleContinuationRowsAfterInterest"] as? Int ?? 0 > 0)
            #expect(noStarvationProgress["expectedTotal"] as? Int == noStarvationProgress["emittedTotal"] as? Int)
            #expect(noStarvationProgress["remainingTotal"] as? Int == 0)
            #expect(noStarvationProgress["completed"] as? Bool == true)
            let queueWaitByLane = try #require(artifactObject["queueWaitByLane"] as? [String: Any])
            let foregroundQueueWait = try #require(queueWaitByLane["foreground"] as? [String: Any])
            #expect(
                foregroundQueueWait["measurementName"] as? String
                    == "metadata_scheduler_queue_wait_by_lane"
            )
            #expect(
                foregroundQueueWait["measurementScope"] as? String
                    == "native scheduler enqueue-to-dequeue queue wait for lane")
            #expect(foregroundQueueWait["p95Milliseconds"] != nil)
            #expect(foregroundQueueWait["p99Milliseconds"] != nil)
            let visibleQueueWait = try #require(queueWaitByLane["visible"] as? [String: Any])
            #expect(
                visibleQueueWait["measurementName"] as? String
                    == "metadata_scheduler_queue_wait_by_lane"
            )
            let metadataApply = try #require(artifactObject["metadataApply"] as? [String: Any])
            #expect(metadataApply["measurementName"] as? String == "metadata_apply")
            #expect(metadataApply["p95Milliseconds"] != nil)
            #expect(metadataApply["p99Milliseconds"] != nil)
            let contentFetch = try #require(artifactObject["contentFetch"] as? [String: Any])
            #expect(contentFetch["measurementName"] as? String == "content_fetch")
            #expect(contentFetch["p95Milliseconds"] != nil)
            #expect(contentFetch["p99Milliseconds"] != nil)
            let contentDescriptorDemand = try #require(
                artifactObject["contentDescriptorDemand"] as? [String: Any]
            )
            #expect(contentDescriptorDemand["measurementName"] as? String == "content_descriptor_demand")
            #expect(contentDescriptorDemand["sampleCount"] as? Int ?? 0 > 0)
        }
    }
}
