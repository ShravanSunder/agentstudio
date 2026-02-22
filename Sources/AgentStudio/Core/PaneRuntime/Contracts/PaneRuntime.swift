import Foundation

@MainActor
protocol PaneRuntime: AnyObject {
    var paneId: PaneId { get }
    var metadata: PaneMetadata { get }
    var lifecycle: PaneRuntimeLifecycle { get }
    var capabilities: Set<PaneCapability> { get }

    func handleCommand(_ envelope: PaneCommandEnvelope) async -> ActionResult
    func subscribe() -> AsyncStream<PaneEventEnvelope>
    func snapshot() -> PaneRuntimeSnapshot
    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult
    func shutdown(timeout: Duration) async -> [UUID]
}
