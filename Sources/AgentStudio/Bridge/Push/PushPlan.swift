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
        tasks = slices.map { slice in
            slice.makeTask(state, transport, revisions, epochProvider)
        }
    }

    func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }
}
