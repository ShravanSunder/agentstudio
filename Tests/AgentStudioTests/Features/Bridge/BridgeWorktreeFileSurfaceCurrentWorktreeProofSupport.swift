import Foundation
import Testing

@testable import AgentStudio

actor BridgeCurrentWorktreeProofIntakeDeliveryCapture {
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

struct BridgeCurrentWorktreeProofIntakeDeliveryRecord: Sendable {
    let deliveredAt: Date
    let frameJSON: String
}

struct BridgeCurrentWorktreeFrameKindProbe: Decodable {
    let frameKind: String
}

struct BridgeCurrentWorktreeManifestFacts {
    let expectedFilePaths: Set<String>
    let finalRemainingRowCount: Int
    let firstWindowRowCount: Int
    let laneValues: Set<String>
    let loadedByValues: Set<String>
    let uniquePathCount: Int
    let uniqueFilePaths: Set<String>
    var missingExpectedFilePaths: Set<String> {
        expectedFilePaths.subtracting(uniqueFilePaths)
    }
    var unexpectedPublishedFilePaths: Set<String> {
        uniqueFilePaths.subtracting(expectedFilePaths)
    }
}

struct BridgeCurrentWorktreeManifestRowAccumulator {
    private(set) var filePaths = Set<String>()
    private(set) var laneValues = Set<String>()
    private(set) var loadedByValues = Set<String>()
    private(set) var paths = Set<String>()

    mutating func recordRows(
        _ rows: [[String: Any]],
        treeWindowKey: String?,
        metadataLineage: BridgeWorktreeFileMetadataLineage
    ) {
        guard treeWindowKey?.hasPrefix("worktree-interest-") != true else {
            return
        }
        paths.formUnion(rows.compactMap { $0["path"] as? String })
        filePaths.formUnion(
            rows.compactMap { row in
                guard row["isDirectory"] as? Bool == false else { return nil }
                return row["path"] as? String
            }
        )
        // S2 frame-level lineage: collect one entry per non-interest frame from
        // the frame's `metadataLineage`. Rows no longer carry per-row lineage.
        loadedByValues.insert(metadataLineage.loadedBy)
        laneValues.insert(metadataLineage.lane)
    }
}

struct BridgeCurrentWorktreeDemandLaneFacts: Encodable {
    let allInterestBeforeIdleContinuation: Bool
    let firstIdleContinuationDeliveryIndex: Int?
    let probes: [BridgeCurrentWorktreeDemandLaneProbe]
}

struct BridgeCurrentWorktreeDemandLaneProbeResults {
    let probesByLane: [BridgeDemandLane: BridgeCurrentWorktreeDemandLaneProbe]
    let requestTimings: [BridgeCurrentWorktreeMetadataInterestRequestTiming]
}

struct BridgeCurrentWorktreeDemandLaneProbe: Encodable {
    let expectedLoadedBy: String
    let expectedPath: String
    let lane: String
    var deliveryIndex: Int?
    var sequence: Int?
}

struct BridgeCurrentWorktreeMetadataInterestRequestTiming {
    let expectedPath: String
    let lane: String
    let requestStartedAt: Date
}

struct BridgeCurrentWorktreeMetadataInterestTimingFacts: Encodable {
    let measurementName: String
    let measurementScope: String
    let sampleCount: Int
    let sampleCountByLane: [String: Int]
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?
    let samples: [BridgeCurrentWorktreeMetadataInterestTimingSample]
}

struct BridgeCurrentWorktreeMetadataInterestTimingSample: Encodable {
    let deliveredFrameSequence: Int
    let deliveryIndex: Int
    let durationMilliseconds: Double
    let expectedPath: String
    let lane: String
}

struct BridgeCurrentWorktreeNoStarvationProgress: Encodable {
    let initialEmittedRows: Int
    let interestRowsBeforeIdleContinuation: Int
    let idleContinuationRowsAfterInterest: Int
    let expectedTotal: Int
    let emittedTotal: Int
    let remainingTotal: Int
    let completed: Bool
}

struct BridgeCurrentWorktreeTimingProof {
    let fullManifestSample: BridgeTelemetrySample
    let openToFirstWindowSummary: BridgeCurrentWorktreeTimingPercentileSummary
    let treeWindowTimingSummary: BridgeCurrentWorktreeTimingPercentileSummary
}
struct BridgeCurrentWorktreeContentDemandProof: Encodable {
    let contentDescriptorDemand: BridgeCurrentWorktreePhaseTimingFacts
    let contentFetch: BridgeCurrentWorktreePhaseTimingFacts
    let demandedPath: String
}
struct BridgeCurrentWorktreeGatedBenchmarkProof: Encodable {
    let completed: Bool
    let contentFetch: BridgeCurrentWorktreePhaseTimingFacts
    let metadataInterestRequestToDeliveredFrame: BridgeCurrentWorktreeMetadataInterestTimingFacts
    let queueWaitByLane: [String: BridgeCurrentWorktreePhaseTimingFacts]
}
struct BridgeCurrentWorktreeGatedBenchmarkProofRequest {
    let controller: BridgePaneController
    let deliveryCapture: BridgeCurrentWorktreeProofIntakeDeliveryCapture
    let eventCapture: BridgeWorktreeFileSurfaceEventCapture
    let fixture: BridgeWorktreeFileSurfaceControllerFixture
    let generation: Int
    let manifestIndex: BridgeWorktreeFileManifestIndex
    let streamId: String
    let telemetryRecorder: BridgeWorktreeFileCurrentWorktreeTelemetryRecorder
}
struct BridgeCurrentWorktreeProofHarness {
    let eventCapture: BridgeWorktreeFileSurfaceEventCapture
    let fixture: BridgeWorktreeFileSurfaceControllerFixture
    let intakeDeliveryCapture: BridgeCurrentWorktreeProofIntakeDeliveryCapture
    let projectRoot: URL
    let responseCapture: BridgeWorktreeFileSurfaceResponseCapture
    let telemetryRecorder: BridgeWorktreeFileCurrentWorktreeTelemetryRecorder
}
struct BridgeCurrentWorktreeTimingPercentileSummary {
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
struct BridgeCurrentWorktreePhaseTimingFacts: Encodable {
    let measurementName: String
    let measurementScope: String
    let sampleCount: Int
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?

    init(
        measurementName: String,
        measurementScope: String,
        samples: [Double]
    ) {
        let summary = BridgeCurrentWorktreeTimingPercentileSummary(samples: samples)
        self.measurementName = measurementName
        self.measurementScope = measurementScope
        self.sampleCount = summary.sampleCount
        self.p95Milliseconds = summary.p95Milliseconds
        self.p99Milliseconds = summary.p99Milliseconds
    }

    init(
        measurementName: String,
        measurementScope: String,
        summary: BridgeCurrentWorktreeTimingPercentileSummary
    ) {
        self.measurementName = measurementName
        self.measurementScope = measurementScope
        self.sampleCount = summary.sampleCount
        self.p95Milliseconds = summary.p95Milliseconds
        self.p99Milliseconds = summary.p99Milliseconds
    }
}
struct BridgeCurrentWorktreeManifestProofArtifact: Encodable {
    let scenarioId: String
    let runtime: String
    let contentDescriptorDemand: BridgeCurrentWorktreePhaseTimingFacts
    let contentFetch: BridgeCurrentWorktreePhaseTimingFacts
    let contentDemandedPath: String
    let demandLaneFacts: BridgeCurrentWorktreeDemandLaneFacts
    let expectedMetadataFileTotal: Int
    let expectedMetadataRowTotal: Int
    let emittedMetadataRowTotal: Int
    let emittedMetadataFileTotal: Int
    let missingExpectedFilePaths: [String]
    let remainingMetadataRowTotal: Int
    let unexpectedPublishedFilePaths: [String]
    let uniquePathCount: Int
    let firstWindowRowCount: Int
    let loadedByValues: [String]
    let laneValues: [String]
    let gatedBenchmark: BridgeCurrentWorktreeGatedBenchmarkProof?
    let queueWaitByLane: [String: BridgeCurrentWorktreePhaseTimingFacts]
    let metadataApply: BridgeCurrentWorktreePhaseTimingFacts
    let metadataInterestRequestToDeliveredFrame: BridgeCurrentWorktreeMetadataInterestTimingFacts
    let noStarvationProgress: BridgeCurrentWorktreeNoStarvationProgress
    let openToFirstWindow: CurrentWorktreeTimingProofArtifact
    let treeWindowBatch: CurrentWorktreeTimingProofArtifact
    let fullManifestComplete: CurrentWorktreeTimingProofArtifact
}
struct CurrentWorktreeTimingProofArtifact: Encodable {
    let sampleCount: Int
    let p95Milliseconds: Double?
    let p99Milliseconds: Double?

    init(_ summary: BridgeCurrentWorktreeTimingPercentileSummary) {
        self.sampleCount = summary.sampleCount
        self.p95Milliseconds = summary.p95Milliseconds
        self.p99Milliseconds = summary.p99Milliseconds
    }
}
struct CurrentWorktreeProofArtifactWriteRequest {
    let demandLaneFacts: BridgeCurrentWorktreeDemandLaneFacts
    let contentDemandProof: BridgeCurrentWorktreeContentDemandProof
    let fullManifestSample: BridgeTelemetrySample
    let manifestFacts: BridgeCurrentWorktreeManifestFacts
    let metadataInterestTiming: BridgeCurrentWorktreeMetadataInterestTimingFacts
    let noStarvationProgress: BridgeCurrentWorktreeNoStarvationProgress
    let openToFirstWindowSummary: BridgeCurrentWorktreeTimingPercentileSummary
    let projectRoot: URL
    let gatedBenchmark: BridgeCurrentWorktreeGatedBenchmarkProof?
    let schedulerQueueWaitByLane: [String: BridgeCurrentWorktreePhaseTimingFacts]
    let treeWindowTimingSummary: BridgeCurrentWorktreeTimingPercentileSummary
}

func writeCurrentWorktreeManifestProofArtifact(
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
        contentDescriptorDemand: request.contentDemandProof.contentDescriptorDemand,
        contentFetch: request.contentDemandProof.contentFetch,
        contentDemandedPath: request.contentDemandProof.demandedPath,
        demandLaneFacts: request.demandLaneFacts,
        expectedMetadataFileTotal: request.manifestFacts.expectedFilePaths.count,
        expectedMetadataRowTotal: expectedTotal,
        emittedMetadataRowTotal: emittedTotal,
        emittedMetadataFileTotal: request.manifestFacts.uniqueFilePaths.count,
        missingExpectedFilePaths: request.manifestFacts.missingExpectedFilePaths.sorted(),
        remainingMetadataRowTotal: remainingTotal,
        unexpectedPublishedFilePaths: request.manifestFacts.unexpectedPublishedFilePaths.sorted(),
        uniquePathCount: request.manifestFacts.uniquePathCount,
        firstWindowRowCount: request.manifestFacts.firstWindowRowCount,
        loadedByValues: request.manifestFacts.loadedByValues.sorted(),
        laneValues: request.manifestFacts.laneValues.sorted(),
        gatedBenchmark: request.gatedBenchmark,
        queueWaitByLane: request.schedulerQueueWaitByLane,
        metadataApply: BridgeCurrentWorktreePhaseTimingFacts(
            measurementName: "metadata_apply",
            measurementScope: "headless Swift metadata frame preparation and dispatch timing",
            summary: request.treeWindowTimingSummary
        ),
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

func queueWaitByLaneFacts(from samples: [BridgeTelemetrySample]) -> [String: BridgeCurrentWorktreePhaseTimingFacts] {
    let samplesByLane = Dictionary(grouping: samples) { sample in
        sample.stringAttributes["agentstudio.bridge.demand.lane"] ?? "unknown"
    }
    return samplesByLane.mapValues { laneSamples in
        BridgeCurrentWorktreePhaseTimingFacts(
            measurementName: "metadata_scheduler_queue_wait_by_lane",
            measurementScope: "native scheduler enqueue-to-dequeue queue wait for lane",
            samples: laneSamples.compactMap { sample in
                sample.numericAttributes["agentstudio.bridge.demand.scheduler_queue_wait_ms"]
                    ?? sample.durationMilliseconds
            }
        )
    }
}
func proofArtifactDirectoryURL(_ proofDirectory: String, projectRoot: URL) -> URL {
    let proofDirectoryURL = URL(fileURLWithPath: proofDirectory)
    if proofDirectoryURL.path.hasPrefix("/") {
        return proofDirectoryURL
    }
    return projectRoot.appending(path: proofDirectory)
}
actor BridgeWorktreeFileCurrentWorktreeTelemetryRecorder: BridgePerformanceTraceRecording {
    private let forwardingRecorder: BridgePerformanceTraceRecorder?
    private let traceRuntime: AgentStudioTraceRuntime?
    private var recordedSamples: [BridgeTelemetrySample] = []

    init(traceRuntime: AgentStudioTraceRuntime? = nil) {
        self.traceRuntime = traceRuntime
        if let traceRuntime {
            self.forwardingRecorder = BridgePerformanceTraceRecorder(
                traceRuntime: traceRuntime,
                scenario: "bridge_headless_manifest_gated_benchmark"
            )
        } else {
            self.forwardingRecorder = nil
        }
    }

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
        recordedSamples.append(sample)
        await forwardingRecorder?.record(sample: sample, receivedAtUnixNano: receivedAtUnixNano)
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

    func drain() async throws {
        try await forwardingRecorder?.drain()
        try await traceRuntime?.shutdown()
    }

    func samples(named sampleName: String) -> [BridgeTelemetrySample] {
        recordedSamples.filter { $0.name == sampleName }
    }
}

func currentWorktreeProofTraceRuntime() -> AgentStudioTraceRuntime? {
    let environment = ProcessInfo.processInfo.environment
    guard environment["AGENTSTUDIO_BRIDGE_HEADLESS_VICTORIA_MODE"] == "1" else {
        return nil
    }
    return AgentStudioTraceRuntime.fromEnvironment(environment)
}

@MainActor
extension WebKitSerializedTests.BridgeWorktreeFileSurfaceCurrentWorktreeProofTests {
    func currentWorktreeGatedBenchmarkProof(
        _ request: BridgeCurrentWorktreeGatedBenchmarkProofRequest
    ) async throws -> BridgeCurrentWorktreeGatedBenchmarkProof? {
        guard
            ProcessInfo.processInfo.environment[
                "AGENTSTUDIO_BRIDGE_HEADLESS_BENCHMARK_MODE"
            ] == "1"
        else {
            return nil
        }
        let probePlan = try await gatedBenchmarkInterestProbePlan(from: request.manifestIndex)
        let benchmarkStartedRecordCount = await request.deliveryCapture.intakeRecords().count
        let queueWaitStartedSampleCount = await request.telemetryRecorder.samples(
            named: "performance.bridge.swift.metadata_scheduler_queue_wait"
        ).count
        let requestTimings = try await requestGatedBenchmarkInterestProbes(
            controller: request.controller,
            generation: request.generation,
            probePlan: probePlan,
            streamId: request.streamId
        )
        await request.controller.worktreeFileMetadataScheduler.waitUntilDrained()
        let deliveryRecords = Array(
            await request.deliveryCapture.intakeRecords().dropFirst(benchmarkStartedRecordCount)
        )
        let metadataInterestTiming = try currentWorktreeMetadataInterestTiming(
            deliveryRecords: deliveryRecords,
            requestTimings: requestTimings,
            minimumSampleCount: 100
        )
        let allQueueWaitSamples = await request.telemetryRecorder.samples(
            named: "performance.bridge.swift.metadata_scheduler_queue_wait"
        )
        let queueWaitByLane = queueWaitByLaneFacts(
            from: Array(allQueueWaitSamples.dropFirst(queueWaitStartedSampleCount))
        )
        let contentFetch = try await currentWorktreeGatedBenchmarkContentFetch(
            eventCapture: request.eventCapture,
            fixture: request.fixture,
            telemetryRecorder: request.telemetryRecorder
        )
        #expect(metadataInterestTiming.sampleCount >= 100)
        #expect((metadataInterestTiming.sampleCountByLane["foreground"] ?? 0) >= 50)
        #expect((metadataInterestTiming.sampleCountByLane["visible"] ?? 0) >= 50)
        #expect((queueWaitByLane["foreground"]?.sampleCount ?? 0) >= 50)
        #expect((queueWaitByLane["visible"]?.sampleCount ?? 0) >= 50)
        #expect((queueWaitByLane["foreground"]?.p95Milliseconds ?? .infinity) < 32)
        #expect((queueWaitByLane["foreground"]?.p99Milliseconds ?? .infinity) < 64)
        #expect((queueWaitByLane["visible"]?.p95Milliseconds ?? .infinity) < 64)
        #expect((queueWaitByLane["visible"]?.p99Milliseconds ?? .infinity) < 100)
        #expect(contentFetch.sampleCount >= 20)
        return BridgeCurrentWorktreeGatedBenchmarkProof(
            completed: true,
            contentFetch: contentFetch,
            metadataInterestRequestToDeliveredFrame: metadataInterestTiming,
            queueWaitByLane: queueWaitByLane
        )
    }

    private func gatedBenchmarkInterestProbePlan(
        from manifestIndex: BridgeWorktreeFileManifestIndex
    ) async throws -> [(lane: BridgeDemandLane, path: String)] {
        let requiredProbeCount = 100
        let candidatePaths = await manifestIndex.orderedPaths(
            startIndex: 0,
            limit: requiredProbeCount * 2
        )
        #expect(candidatePaths.count >= requiredProbeCount)
        let selectedPaths = Array(candidatePaths.prefix(requiredProbeCount))
        return selectedPaths.enumerated().map { index, path in
            (
                lane: index < 50 ? BridgeDemandLane.foreground : BridgeDemandLane.visible,
                path: path
            )
        }
    }

    private func requestGatedBenchmarkInterestProbes(
        controller: BridgePaneController,
        generation: Int,
        probePlan: [(lane: BridgeDemandLane, path: String)],
        streamId: String
    ) async throws -> [BridgeCurrentWorktreeMetadataInterestRequestTiming] {
        var requestTimings: [BridgeCurrentWorktreeMetadataInterestRequestTiming] = []
        for (index, probe) in probePlan.enumerated() {
            let requestStartedAt = Date()
            try await controller.handleWorktreeFileMetadataInterestUpdate(
                ReviewMethods.MetadataInterestUpdateMethod.Params(
                    protocolId: "worktree-file",
                    streamId: streamId,
                    generation: generation,
                    itemIds: nil,
                    paths: [probe.path],
                    lane: probe.lane,
                    loadedBy: nil
                )
            )
            await controller.worktreeFileMetadataScheduler.waitUntilDrained()
            requestTimings.append(
                BridgeCurrentWorktreeMetadataInterestRequestTiming(
                    expectedPath: probe.path,
                    lane: probe.lane.rawValue,
                    requestStartedAt: requestStartedAt
                )
            )
            #expect(index < probePlan.count)
        }
        return requestTimings
    }

    private func currentWorktreeGatedBenchmarkContentFetch(
        eventCapture: BridgeWorktreeFileSurfaceEventCapture,
        fixture: BridgeWorktreeFileSurfaceControllerFixture,
        telemetryRecorder: BridgeWorktreeFileCurrentWorktreeTelemetryRecorder
    ) async throws -> BridgeCurrentWorktreePhaseTimingFacts {
        let intakeFramesBeforeDemand = await eventCapture.intakeFrames()
        let demandRows = try contentDemandRows(
            from: intakeFramesBeforeDemand,
            limit: 20
        )
        let sourceIdentity = try firstSourceIdentity(from: intakeFramesBeforeDemand)
        let schemeHandler = BridgeSchemeHandler(
            paneId: fixture.paneId,
            worktreeFileResourceStore: fixture.controller.worktreeFileResourceStore,
            resourceLeaseRegistry: fixture.controller.resourceLeaseRegistry,
            telemetryRecorder: telemetryRecorder
        )
        var contentFetchSamples: [Double] = []
        for sampleIndex in 0..<20 {
            let row = demandRows[sampleIndex % demandRows.count]
            let frameCountBeforeDemand = await eventCapture.intakeFrames().count
            try await requestFileDescriptor(
                controller: fixture.controller,
                requestId: "current-worktree-gated-content-\(sampleIndex)",
                sourceIdentity: sourceIdentity,
                row: row,
                path: row.path,
                lane: .foreground
            )
            await waitForIntakeFrameCount(
                frameCountBeforeDemand + 1,
                from: eventCapture,
                description: "Gated benchmark content descriptor demand should emit descriptor frame"
            )
            let descriptorFrameJSON = try #require(await eventCapture.intakeFrames().last)
            let descriptorEnvelope = try decodeDescriptorEnvelope(descriptorFrameJSON)
            let contentFetchStart = Date()
            let contentBody = try await resourceBody(
                url: descriptorEnvelope.payload.descriptor.contentDescriptor.descriptor.resourceUrl,
                handler: schemeHandler
            )
            contentFetchSamples.append(Date().timeIntervalSince(contentFetchStart) * 1000)
            #expect(!contentBody.isEmpty)
        }
        return BridgeCurrentWorktreePhaseTimingFacts(
            measurementName: "content_fetch",
            measurementScope: "headless Swift descriptor body read through BridgeSchemeHandler",
            samples: contentFetchSamples
        )
    }

    private func contentDemandRows(
        from intakeFrames: [String],
        limit: Int
    ) throws -> [BridgeWorktreeTreeRowMetadata] {
        var rowsByPath: [String: BridgeWorktreeTreeRowMetadata] = [:]
        for intakeFrame in intakeFrames {
            let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
            let candidateRows: [BridgeWorktreeTreeRowMetadata]
            switch probe.payload.frameKind {
            case "worktree.snapshot":
                candidateRows = try decodeIntakeEnvelope(
                    intakeFrame,
                    as: BridgeWorktreeSnapshotFrame.self
                ).payload.treeRows
            case "worktree.treeWindow":
                candidateRows = try decodeIntakeEnvelope(
                    intakeFrame,
                    as: BridgeWorktreeTreeWindowFrame.self
                ).payload.rows
            default:
                continue
            }
            for row in candidateRows where row.fileId != nil && !row.isDirectory {
                let sizeBytes = row.sizeBytes ?? 0
                guard sizeBytes <= 128 * 1024 else { continue }
                rowsByPath[row.path] = row
                if rowsByPath.count >= limit {
                    return rowsByPath.keys.sorted().compactMap { rowsByPath[$0] }
                }
            }
        }
        let rows = rowsByPath.keys.sorted().compactMap { rowsByPath[$0] }
        #expect(!rows.isEmpty)
        return rows
    }

    func firstSourceIdentity(
        from intakeFrames: [String]
    ) throws -> BridgeWorktreeFileSurfaceSourceIdentity {
        for intakeFrame in intakeFrames {
            let probe = try decodeIntakeEnvelope(intakeFrame, as: BridgeCurrentWorktreeFrameKindProbe.self)
            switch probe.payload.frameKind {
            case "worktree.snapshot":
                return try decodeIntakeEnvelope(
                    intakeFrame,
                    as: BridgeWorktreeSnapshotFrame.self
                ).payload.source
            case "worktree.treeWindow":
                return try decodeIntakeEnvelope(
                    intakeFrame,
                    as: BridgeWorktreeTreeWindowFrame.self
                ).payload.projectionIdentity.source
            default:
                continue
            }
        }
        Issue.record("Expected metadata frame with source identity")
        throw BridgeProviderFailure.providerFailed(message: "missingSourceIdentity")
    }
}

func expectedRelativePath(fileURL: URL, rootURL: URL) -> String {
    let rootPath = rootURL.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    let prefix = rootPath == "/" ? "/" : rootPath + "/"
    guard let range = filePath.range(of: prefix, options: [.anchored]) else {
        return fileURL.lastPathComponent
    }
    return String(filePath[range.upperBound...])
}

func isNestedExpectedWorktreeRoot(_ directoryURL: URL, rootURL: URL) -> Bool {
    let canonicalDirectoryURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
    let canonicalRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    guard canonicalDirectoryURL.path != canonicalRootURL.path else {
        return false
    }
    return FileManager.default.fileExists(atPath: canonicalDirectoryURL.appending(path: ".git").path)
}
