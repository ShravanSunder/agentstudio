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
            sourceSnapshot.rows.count > 1
        else {
            return .failure(.fixtureInvalid)
        }
        var targetRows = sourceSnapshot.rows
        let movedRow = targetRows.removeLast()
        targetRows.insert(movedRow, at: 0)
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
