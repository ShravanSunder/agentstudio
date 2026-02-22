import Foundation
import Observation
import os.log

/// Result builder for declaring push slices in a PushPlan.
/// Accepts both `Slice` and `EntitySlice` via type-erased `AnyPushSlice`.
///
@resultBuilder
struct PushPlanBuilder<State: Observable & AnyObject> {
    static func buildExpression(
        _ slice: AnyPushSlice<State>
    ) -> AnyPushSlice<State> {
        slice
    }

    static func buildExpression<Snapshot: Encodable & Equatable>(
        _ slice: Slice<State, Snapshot>
    ) -> AnyPushSlice<State> {
        slice.erased()
    }

    static func buildExpression<Key: Hashable, Entity: Encodable>(
        _ slice: EntitySlice<State, Key, Entity>
    ) -> AnyPushSlice<State> {
        slice.erased()
    }

    static func buildBlock(_ slices: AnyPushSlice<State>...) -> [AnyPushSlice<State>] {
        Array(slices)
    }
}

/// Declarative push configuration for one state object.
/// Creates one observation task per slice. All slices share
/// the same RevisionClock and EpochProvider.
///
@MainActor
final class PushPlan<State: Observable & AnyObject> {
    private let state: State
    private let transport: PushTransport
    private let revisions: RevisionClock
    private let epochProvider: EpochProvider
    private let slices: [AnyPushSlice<State>]
    private var tasks: [Task<Void, Never>] = []

    /// Monotonically increasing generation counter for restart-safe cancellation.
    /// Each start() increments this. StopGuardedTransport captures the generation
    /// at creation time and drops pushes when the captured generation doesn't match
    /// the current one. This prevents late emissions from a previous generation's
    /// in-flight tasks from leaking through after a stop→start restart.
    private(set) var generation: Int = 0

    /// Whether the plan is stopped (no active generation).
    /// True when no tasks are running (initial state or after stop()).
    private(set) var isStopped = true

    /// Number of active observation tasks. Exposed for testing.
    var taskCount: Int { tasks.count }

    init(
        state: State,
        transport: PushTransport,
        revisions: RevisionClock,
        epoch: @escaping EpochProvider,
        @PushPlanBuilder<State> slices: () -> [AnyPushSlice<State>]
    ) {
        self.state = state
        self.transport = transport
        self.revisions = revisions
        self.epochProvider = epoch
        self.slices = slices()
    }

    func start() {
        stop()
        generation += 1
        isStopped = false
        let guardedTransport = StopGuardedTransport(
            plan: self, inner: transport, validGeneration: generation
        )
        tasks = slices.map { slice in
            slice.makeTask(state, guardedTransport, revisions, epochProvider)
        }
    }

    func stop() {
        isStopped = true
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }
}

// MARK: - Stop-Guarded Transport

/// Wraps a real transport and drops pushes from stale generations.
/// Captures the generation counter at creation time and only forwards pushes
/// when the plan's current generation matches. This is restart-safe:
/// stop→start creates a new generation, and any late emissions from the
/// previous generation's in-flight tasks are silently dropped.
@MainActor
private final class StopGuardedTransport<State: Observable & AnyObject>: PushTransport {
    private let logger = Logger(subsystem: "com.agentstudio", category: "PushPlan")

    private weak var plan: PushPlan<State>?
    private let inner: PushTransport
    private let validGeneration: Int

    init(plan: PushPlan<State>, inner: PushTransport, validGeneration: Int) {
        self.plan = plan
        self.inner = inner
        self.validGeneration = validGeneration
    }

    func pushJSON(
        store: StoreKey, op: PushOp, level: PushLevel,
        revision: Int, epoch: Int, json: Data
    ) async {
        guard let plan, !plan.isStopped, plan.generation == validGeneration else {
            logger.debug("StopGuardedTransport dropped push for stale generation or stopped plan")
            return
        }
        await inner.pushJSON(
            store: store, op: op, level: level,
            revision: revision, epoch: epoch, json: json
        )
    }
}
