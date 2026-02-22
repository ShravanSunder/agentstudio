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
    func shutdown(timeout: Duration) async -> [UUID]
}
