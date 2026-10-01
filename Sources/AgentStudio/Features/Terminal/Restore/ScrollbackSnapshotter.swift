import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// Compile-only S3 boundary. Behavior is deliberately absent until red is
/// verified; this shell admits no captures and schedules no work.
package actor ScrollbackSnapshotter {
    package init(
        clock: any Clock<Duration>, store: ScrollbackStore,
        inventory: @escaping @Sendable () async -> ZmxSessionInventory,
        paneBindings: @escaping @Sendable () async throws -> [ScrollbackPaneBinding],
        capture: @escaping @Sendable (ZmxSessionID) async -> ScrollbackCaptureResult,
        maximumConcurrentCaptures: Int = AppPolicies.Restore.maximumConcurrentCaptures,
        factSink: (@Sendable (ScrollbackSnapshotterScope, ScrollbackSnapshotterFact) -> Void)? = nil
    ) {}

    package func start() async {}

    package func captureForQuit(requestID: UUID, budget: Duration) async -> ScrollbackQuitOutcome {
        .cancelled
    }

    package func retire(operationID: UUID, paneIDs: Set<PaneId>) async throws {}

    package func shutdown() async {}
}
