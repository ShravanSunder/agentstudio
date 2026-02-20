import Foundation
import Observation

/// Result builder for declaring push slices in a PushPlan.
/// Accepts both `Slice` and `EntitySlice` via type-erased `AnyPushSlice`.
///
/// Design doc section 6.7.
@resultBuilder
struct PushPlanBuilder<State: Observable & AnyObject> {
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
/// Design doc section 6.7.
@MainActor
final class PushPlan<State: Observable & AnyObject> {
    private let state: State
    private let transport: PushTransport
    private let revisions: RevisionClock
    private let epochProvider: EpochProvider
    private let slices: [AnyPushSlice<State>]
    private var tasks: [Task<Void, Never>] = []

    /// Guards against post-stop emissions. Task cancellation is cooperative —
    /// an in-flight iteration between `for await` yield and `pushJSON` won't
    /// see cancellation until the next suspension point. This flag is checked
    /// by the guarded transport wrapper before forwarding to the real transport.
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
        isStopped = false
        let guardedTransport = StopGuardedTransport(plan: self, inner: transport)
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

/// Wraps a real transport and drops pushes if the owning plan has been stopped.
/// Prevents post-stop emissions from in-flight slice iterations that haven't
/// yet observed task cancellation.
@MainActor
private final class StopGuardedTransport<State: Observable & AnyObject>: PushTransport {
    private weak var plan: PushPlan<State>?
    private let inner: PushTransport

    init(plan: PushPlan<State>, inner: PushTransport) {
        self.plan = plan
        self.inner = inner
    }

    func pushJSON(
        store: StoreKey, op: PushOp, level: PushLevel,
        revision: Int, epoch: Int, json: Data
    ) async {
        guard plan?.isStopped == false else { return }
        await inner.pushJSON(
            store: store, op: op, level: level,
            revision: revision, epoch: epoch, json: json
        )
    }
}
