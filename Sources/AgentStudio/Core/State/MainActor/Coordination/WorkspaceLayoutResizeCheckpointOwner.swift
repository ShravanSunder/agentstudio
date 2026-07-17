import Foundation

enum WorkspaceLayoutResizeCheckpointOfferResult: Equatable, Sendable {
    case accepted(LatestValueSettleOfferResult)
    case rejectedTargetMismatch(
        expected: WorkspaceLayoutResizeTarget,
        actual: WorkspaceLayoutResizeTarget
    )
}

@MainActor
final class WorkspaceLayoutResizeCheckpointOwner {
    typealias Committer = @MainActor (WorkspaceLayoutResizeCheckpoint) -> WorkspaceLayoutResizePersistenceResult
    typealias Observer =
        @MainActor (
            WorkspaceLayoutResizeCheckpoint,
            WorkspaceLayoutResizePersistenceResult
        ) -> Void

    private let target: WorkspaceLayoutResizeTarget
    private let settleGate: LatestValueSettleGate<WorkspaceLayoutResizeCheckpoint>

    convenience init(
        target: WorkspaceLayoutResizeTarget,
        quietWindow: Duration,
        committer: @escaping Committer,
        observer: @escaping Observer
    ) {
        self.init(
            target: target,
            quietWindow: quietWindow,
            clock: ContinuousClock(),
            committer: committer,
            observer: observer
        )
    }

    init<SettleClock: Clock & Sendable>(
        target: WorkspaceLayoutResizeTarget,
        quietWindow: Duration,
        clock: SettleClock,
        committer: @escaping Committer,
        observer: @escaping Observer
    ) where SettleClock.Duration == Duration {
        self.target = target
        settleGate = LatestValueSettleGate(
            quietWindow: quietWindow,
            clock: clock
        ) { checkpoint in
            let result = committer(checkpoint)
            observer(checkpoint, result)
        }
    }

    var diagnostics: LatestValueSettleGateDiagnostics { settleGate.diagnostics }

    func offer(
        _ checkpoint: WorkspaceLayoutResizeCheckpoint
    ) -> WorkspaceLayoutResizeCheckpointOfferResult {
        guard checkpoint.target == target else {
            return .rejectedTargetMismatch(expected: target, actual: checkpoint.target)
        }
        return .accepted(settleGate.offer(checkpoint))
    }

    func flushNow() -> LatestValueSettleFlushResult { settleGate.flushNow() }

    func close() -> LatestValueSettleCloseResult { settleGate.close() }
}
