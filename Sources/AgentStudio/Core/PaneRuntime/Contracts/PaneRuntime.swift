import Foundation

/// Runtime contract implemented by each pane runtime (terminal, browser, diff, etc.).
///
/// The runtime owns command execution, event emission, lifecycle state, and replay queries
/// for exactly one pane identity (`paneId`).
@MainActor
protocol PaneRuntime: AnyObject {
    /// Stable runtime identity for registry routing and envelope attribution.
    var paneId: PaneId { get }
    /// Runtime-owned pane metadata snapshot used for routing and command validation.
    var metadata: PaneMetadata { get }
    /// Current lifecycle state used to gate command handling.
    var lifecycle: PaneRuntimeLifecycle { get }
    /// Declared runtime capabilities for command validation.
    var capabilities: Set<PaneCapability> { get }

    /// Handle a routed runtime command envelope.
    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult
    /// Subscribe to the live event stream emitted by this runtime.
    /// Each call returns an independent stream for that subscriber.
    func subscribe() -> AsyncStream<PaneEventEnvelope>
    /// Capture an instant runtime state snapshot.
    func snapshot() -> PaneRuntimeSnapshot
    /// Fetch replayable events strictly after `seq`.
    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult
    /// Begin shutdown and return any command IDs that were canceled.
    func shutdown(timeout: Duration) async -> [UUID]
}

/// Marker for runtimes that publish `RuntimeEnvelope` payloads directly onto `PaneRuntimeEventBus`.
///
/// Legacy/fake runtimes that only support `subscribe()` are bridged to the bus
/// by `PaneCoordinator`.
@MainActor
protocol BusPostingPaneRuntime: PaneRuntime {}
