import AgentStudioInfrastructure

package protocol ForgePerformanceRecording: Sendable {
    func record(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        attributes: @autoclosure () -> [String: AgentStudioTraceValue]
    )
}

extension AgentStudioPerformanceTraceRecorder: ForgePerformanceRecording {}
