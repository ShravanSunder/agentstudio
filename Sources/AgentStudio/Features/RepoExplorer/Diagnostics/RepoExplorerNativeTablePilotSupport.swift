import AgentStudioInfrastructure
import AppKit
import Foundation

@MainActor
final class PilotAdapterReference {
    weak var adapter: RepoExplorerProjectionAdapter?
}

@MainActor
final class PilotScaleRuntime {
    let fixture: PilotFixture
    let eventChannel = PilotHostEventChannel()
    let host: RepoExplorerMaterializationHost
    let window: NSWindow
    let projectionAdapter: RepoExplorerProjectionAdapter

    private let adapterReference = PilotAdapterReference()

    init(
        topology: PilotTopology,
        representedRowCount: Int,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?,
        project:
            @escaping @Sendable (RepoExplorerProjectionWork) throws(CancellationError)
            -> RepoExplorerProjectionResult
    ) {
        let preparedFixture = PilotFixture(
            topology: topology,
            representedRowCount: representedRowCount
        )
        fixture = preparedFixture
        let eventChannel = eventChannel
        let adapterReference = adapterReference
        host = RepoExplorerMaterializationHost(
            lifetimeID: RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate()),
            initialDemandEpoch: 0,
            initialPresentation: .noRepositories,
            makeContentChild: { preparedFixture.contentChild },
            onFeedback: { feedback in
                adapterReference.adapter?.receiveMaterializationFeedback(feedback)
                eventChannel.receive(feedback)
            }
        )
        let viewportHeight = PilotLayout.rowHeight * CGFloat(representedRowCount)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: viewportHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        projectionAdapter = RepoExplorerProjectionAdapter(
            performanceTraceRecorder: performanceTraceRecorder,
            project: project
        )
        adapterReference.adapter = projectionAdapter
    }

    func cleanup() async {
        await projectionAdapter.stopAndDrain()
        eventChannel.finish()
        host.detach()
        window.contentView = nil
        window.close()
        fixture.detach()
        adapterReference.adapter = nil
    }
}

struct PilotHostEvent: Equatable, Sendable {
    let candidateID: UInt64
    let visibleGeneration: UInt64
}

enum PilotEventWaitOutcome: Equatable, Sendable {
    case accepted(PilotHostEvent)
    case timedOut
    case cancelled
    case invalidEvent
    case streamClosed
}
@MainActor
final class PilotHostEventChannel {
    let stream: AsyncStream<PilotHostEvent>
    private var continuation: AsyncStream<PilotHostEvent>.Continuation?

    init() {
        let pair = AsyncStream.makeStream(
            of: PilotHostEvent.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    func receive(_ feedback: RepoExplorerMaterializationFeedback) {
        guard case .accepted(let identity, let baseline) = feedback,
            case .candidate(let candidateID) = identity
        else {
            return
        }
        continuation?.yield(
            PilotHostEvent(
                candidateID: candidateID.rawValue,
                visibleGeneration: baseline.visibleGeneration
            )
        )
    }

    func finish() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.finish()
    }
}

enum PilotScale: String {
    case baseline
    case doubled
}

enum PilotLayout {
    static let rowHeight: CGFloat = 20
}

struct ScaleResult {
    let measurements: [Double]
    let p95Milliseconds: Double
    let exactness: Bool
    let failureReason: RepoExplorerNativeTablePilotResult.FailureReason?
    let livenessProjectionCount: Int
    let drainCompleted: Bool
    let templatePairCount: Int

    static func failed(
        _ reason: RepoExplorerNativeTablePilotResult.FailureReason,
        livenessProjectionCount: Int = 0,
        drainCompleted: Bool = false,
        templatePairCount: Int = 0
    ) -> Self {
        Self(
            measurements: [],
            p95Milliseconds: 0,
            exactness: false,
            failureReason: reason,
            livenessProjectionCount: livenessProjectionCount,
            drainCompleted: drainCompleted,
            templatePairCount: templatePairCount
        )
    }
}

struct PilotReplayScenario: Sendable {
    let source: RepoExplorerMaterializationPresentation
    let target: RepoExplorerMaterializationPresentation
    let templates: RepoExplorerNativeUpdatePlanTemplatePair

    @concurrent nonisolated static func prepare(
        source: RepoExplorerMaterializationPresentation
    ) async -> Result<Self, RepoExplorerNativeTablePilotResult.FailureReason> {
        guard case .content(let sourceSnapshot, _) = source,
            sourceSnapshot.rows.count > 4
        else {
            return .failure(.fixtureInvalid)
        }
        var targetRows = sourceSnapshot.rows
        let removedRow = targetRows.removeLast()
        let displacedRowCount = max(1, targetRows.count / 4)
        let displacedRows = Array(targetRows.suffix(displacedRowCount))
        targetRows.removeLast(displacedRowCount)
        targetRows.insert(contentsOf: displacedRows, at: 0)
        let insertedRowID = RepoExplorerRowID.group(
            groupID: "pilot-inserted-\(sourceSnapshot.rows.count)"
        )
        let insertedPresentation = RepoExplorerMaterializedRowPresentation.unresolved(insertedRowID)
        targetRows.insert(
            RepoExplorerMaterializedRow(
                id: insertedRowID,
                contentRevision: RepoExplorerRowContentRevision(
                    presentation: insertedPresentation
                ),
                layout: RepoExplorerRowLayout.make(for: insertedPresentation),
                representedRepoID: removedRow.representedRepoID,
                representedWorktreeID: nil
            ),
            at: displacedRowCount
        )
        let targetSnapshot = RepoExplorerMaterializationSnapshot(rows: targetRows)
        let target = RepoExplorerMaterializationPresentation.content(
            snapshot: targetSnapshot,
            fingerprint: .make(snapshot: targetSnapshot)
        )
        switch RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: source,
            target: target
        ) {
        case .success(let templates):
            return .success(Self(source: source, target: target, templates: templates))
        case .failure:
            return .failure(.transactionInvalid)
        }
    }
}

struct PilotReplayState: Sendable {
    let seedEvent: PilotHostEvent
    let scenario: PilotReplayScenario
}

enum PilotReplayPreparationOutcome: Sendable {
    case ready(PilotReplayState)
    case failed(ScaleResult)
}

@MainActor
struct PreparedPilotScale {
    let runtime: PilotScaleRuntime
    let replayState: PilotReplayState
    let scale: PilotScale
}

enum PilotScalePreparationOutcome {
    case ready(PreparedPilotScale)
    case failed(ScaleResult)
}

struct PairedScaleResult {
    let baseline: ScaleResult
    let doubled: ScaleResult
}

enum PairedScaleReplayOutcome {
    case completed(PairedScaleResult)
    case failed(RepoExplorerNativeTablePilotResult.FailureReason)
}

@MainActor
extension RepoExplorerNativeTablePilot {
    static func replayPairedTransactions<C: Clock>(
        baseline: PreparedPilotScale,
        doubled: PreparedPilotScale,
        completionDeadline: C.Instant,
        clock: C
    ) -> PairedScaleReplayOutcome where C.Duration == Duration {
        let warmupCount = AppPolicies.SidebarPerformanceProof.warmupTransactionCountPerScale
        let measuredCount = AppPolicies.SidebarPerformanceProof.measuredTransactionCountPerScale
        var baselineMeasurements: [Double] = []
        var doubledMeasurements: [Double] = []
        baselineMeasurements.reserveCapacity(measuredCount)
        doubledMeasurements.reserveCapacity(measuredCount)

        for transactionIndex in 0..<(warmupCount + measuredCount) {
            guard !Task.isCancelled, clock.now < completionDeadline else {
                return .failed(Task.isCancelled ? .cancelled : .completionTimeout)
            }
            for scale in pairedScaleOrder(transactionIndex: transactionIndex) {
                let preparedScale = scale == .baseline ? baseline : doubled
                let transactionResult = applyReplayTransaction(
                    runtime: preparedScale.runtime,
                    replayState: preparedScale.replayState,
                    transactionIndex: transactionIndex
                )
                guard case .success(let elapsedMilliseconds) = transactionResult else {
                    return .failed(
                        preparedScale.runtime.fixture.contentChild.failureReason
                            ?? .transactionInvalid
                    )
                }
                guard transactionIndex >= warmupCount else { continue }
                switch preparedScale.scale {
                case .baseline:
                    baselineMeasurements.append(elapsedMilliseconds)
                case .doubled:
                    doubledMeasurements.append(elapsedMilliseconds)
                }
            }
        }

        guard baselineMeasurements.count == measuredCount,
            doubledMeasurements.count == measuredCount
        else {
            return .failed(.measurementCountMismatch)
        }
        return .completed(
            PairedScaleResult(
                baseline: completedScaleResult(
                    measurements: baselineMeasurements,
                    exactness: baseline.runtime.fixture.contentChild.isExact
                ),
                doubled: completedScaleResult(
                    measurements: doubledMeasurements,
                    exactness: doubled.runtime.fixture.contentChild.isExact
                )
            )
        )
    }

    static func preparedScaleFailure(
        _ reason: RepoExplorerNativeTablePilotResult.FailureReason
    ) -> ScaleResult {
        .failed(reason, livenessProjectionCount: 1, drainCompleted: true, templatePairCount: 1)
    }

    static func pairedScaleOrder(transactionIndex: Int) -> [PilotScale] {
        transactionIndex.isMultiple(of: 2)
            ? [.baseline, .doubled]
            : [.doubled, .baseline]
    }

    private static func applyReplayTransaction(
        runtime: PilotScaleRuntime,
        replayState: PilotReplayState,
        transactionIndex: Int
    ) -> Result<Double, RepoExplorerNativeTablePilotResult.FailureReason> {
        guard let currentBaseline = runtime.host.acceptedBaseline else {
            return .failure(.fixtureInvalid)
        }
        let candidateID = replayState.seedEvent.candidateID + UInt64(transactionIndex) + 1
        let visibleGeneration =
            replayState.seedEvent.visibleGeneration + UInt64(transactionIndex) + 1
        let isForward = transactionIndex.isMultiple(of: 2)
        let template =
            isForward
            ? replayState.scenario.templates.forward
            : replayState.scenario.templates.reverse
        let expectedPresentation =
            isForward
            ? replayState.scenario.target
            : replayState.scenario.source
        let candidateResult = template.instantiate(
            baseline: currentBaseline,
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: candidateID),
            requestGeneration: visibleGeneration,
            visibleGeneration: visibleGeneration
        )
        guard case .success(let candidate) = candidateResult,
            candidate.presentation == expectedPresentation,
            case .accepted(let acceptedBaseline) = runtime.host.apply(candidate),
            acceptedBaseline.presentation == expectedPresentation,
            acceptedBaseline.revision == currentBaseline.revision &+ 1,
            acceptedBaseline.visibleGeneration == visibleGeneration,
            runtime.fixture.contentChild.isExact,
            let elapsedMilliseconds = runtime.fixture.contentChild.takeLastMeasurement()
        else {
            return .failure(.transactionInvalid)
        }
        return .success(elapsedMilliseconds)
    }

    private static func completedScaleResult(
        measurements: [Double],
        exactness: Bool
    ) -> ScaleResult {
        ScaleResult(
            measurements: measurements,
            p95Milliseconds: nearestRankP95(measurements),
            exactness: exactness,
            failureReason: nil,
            livenessProjectionCount: 1,
            drainCompleted: true,
            templatePairCount: 1
        )
    }

    private static func nearestRankP95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sortedValues = values.sorted()
        let rank = max(1, Int(ceil(Double(sortedValues.count) * 0.95)))
        return sortedValues[rank - 1]
    }
}
