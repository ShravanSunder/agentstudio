import Foundation

/// Recording seam the git working-directory projector depends on.
///
/// The projector emits performance-trace events (admission, status, backoff)
/// through this protocol instead of the concrete OTLP-bound recorder so its
/// telemetry, including the circuit-breaker open/close facts, can be observed
/// in unit tests with a spy. `AgentStudioPerformanceTraceRecorder` is the
/// production conformer; it forwards to OTLP/JSONL exactly as before.
protocol GitProjectorPerformanceRecording: Sendable {
    var isEnabled: Bool { get }

    func record(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        attributes: [String: AgentStudioTraceValue]
    )

    func recordDuration(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        duration: Duration,
        attributes: [String: AgentStudioTraceValue]
    )
}

extension AgentStudioPerformanceTraceRecorder: GitProjectorPerformanceRecording {}
