import Foundation

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
    let finalRemainingRowCount: Int
    let firstWindowRowCount: Int
    let laneValues: Set<String>
    let loadedByValues: Set<String>
    let uniquePathCount: Int
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
    let expectedMetadataRowTotal: Int
    let emittedMetadataRowTotal: Int
    let remainingMetadataRowTotal: Int
    let uniquePathCount: Int
    let firstWindowRowCount: Int
    let loadedByValues: [String]
    let laneValues: [String]
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
        expectedMetadataRowTotal: expectedTotal,
        emittedMetadataRowTotal: emittedTotal,
        remainingMetadataRowTotal: remainingTotal,
        uniquePathCount: request.manifestFacts.uniquePathCount,
        firstWindowRowCount: request.manifestFacts.firstWindowRowCount,
        loadedByValues: request.manifestFacts.loadedByValues.sorted(),
        laneValues: request.manifestFacts.laneValues.sorted(),
        queueWaitByLane: queueWaitByLaneFacts(from: request.metadataInterestTiming),
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

func queueWaitByLaneFacts(
    from metadataInterestTiming: BridgeCurrentWorktreeMetadataInterestTimingFacts
) -> [String: BridgeCurrentWorktreePhaseTimingFacts] {
    Dictionary(
        uniqueKeysWithValues: metadataInterestTiming.samples.map { sample in
            (
                sample.lane,
                BridgeCurrentWorktreePhaseTimingFacts(
                    measurementName: "metadata_interest_queue_wait_by_lane",
                    measurementScope: "headless Swift metadata interest request to delivered frame for lane",
                    samples: [sample.durationMilliseconds]
                )
            )
        }
    )
}
func proofArtifactDirectoryURL(_ proofDirectory: String, projectRoot: URL) -> URL {
    let proofDirectoryURL = URL(fileURLWithPath: proofDirectory)
    if proofDirectoryURL.path.hasPrefix("/") {
        return proofDirectoryURL
    }
    return projectRoot.appending(path: proofDirectory)
}
actor BridgeWorktreeFileCurrentWorktreeTelemetryRecorder: BridgePerformanceTraceRecording {
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
