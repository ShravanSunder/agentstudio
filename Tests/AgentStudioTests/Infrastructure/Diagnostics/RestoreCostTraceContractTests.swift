import Foundation
import Testing

@testable import AgentStudioInfrastructure

enum RestoreCostTraceTestPhase: String, CaseIterable, Sendable {
    case gathering = "performance.restore.foreground.gather"
    case scheduling = "performance.restore.foreground.schedule"
    case probing = "performance.restore.foreground.probe"
    case watching = "performance.restore.foreground.watch"
    case deciding = "performance.restore.resume.decide"
}

extension AgentStudioPerformanceTraceRecorderTests {
    @Test(
        "each restore phase records its fixed event through recordDuration",
        arguments: RestoreCostTraceTestPhase.allCases)
    func restorePhaseUsesDurationRecorder(phase: RestoreCostTraceTestPhase) async throws {
        let event = try #require(AgentStudioPerformanceTraceRecorder.Event(rawValue: phase.rawValue))
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "restore-cost-trace-\(UUIDv7.generate().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl", "AGENTSTUDIO_TRACE_DIR": directory.path,
                "AGENTSTUDIO_TRACE_NAME": "restore-cost-contract", "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]), processIdentifier: 909, timeUnixNano: { 117 })
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        recorder.recordDuration(
            event, duration: .milliseconds(2),
            attributes: [
                "agentstudio.performance.restore.execution.count": .int(1),
                "agentstudio.performance.restore.main_thread.execution.count": .int(1),
                "agentstudio.performance.restore.main_thread.elapsed_ms": .double(0.5),
            ])
        try await recorder.drain()
        let output = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: output, encoding: .utf8)
        #expect(contents.contains("\"body\":\"\(phase.rawValue)\""))
        #expect(contents.contains("\"agentstudio.performance.elapsed_ms\":2"))
        #expect(contents.contains("\"agentstudio.performance.restore.execution.count\":1"))
        #expect(contents.contains("\"agentstudio.performance.restore.main_thread.execution.count\":1"))
        #expect(contents.contains("\"agentstudio.performance.restore.main_thread.elapsed_ms\":0.5"))
    }
}

extension AgentStudioOTLPTraceProjectionTests {
    @Test(
        "restore phase projection preserves measured scalars and proof scope while removing private payloads",
        arguments: RestoreCostTraceTestPhase.allCases)
    func restorePhaseProjectionIsScalarOnly(phase: RestoreCostTraceTestPhase) {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 90, severityText: .info, body: phase.rawValue,
            traceID: nil, spanID: nil, parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio", "dev.runtime.flavor": "debug",
                "agent.proof.marker": "restore-cost-contract", "agent.proof.launch": "restore-cost-launch",
            ],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(2),
                "agentstudio.performance.restore.execution.count": .int(1),
                "agentstudio.performance.restore.main_thread.execution.count": .int(1),
                "agentstudio.performance.restore.main_thread.elapsed_ms": .double(0.5),
                "agentstudio.performance.restore.pane_id": .string("019be3be-7c00-7000-8000-000000000099"),
                "agentstudio.performance.restore.argv": .string("claude --resume private-session"),
                "agentstudio.performance.restore.prompt": .string("private restore prompt"),
                "agentstudio.performance.restore.raw_path": .string("/private/restore-store"),
            ])
        let projection = AgentStudioOTLPTraceProjection.project(record)
        #expect(projection.body == phase.rawValue)
        #expect(projection.resource["agent.proof.marker"] == "restore-cost-contract")
        #expect(projection.resource["agent.proof.launch"] == "restore-cost-launch")
        #expect(projection.attributes["agentstudio.performance.elapsed_ms"] == .double(2))
        #expect(projection.attributes["agentstudio.performance.restore.execution.count"] == .int(1))
        #expect(projection.attributes["agentstudio.performance.restore.main_thread.execution.count"] == .int(1))
        #expect(projection.attributes["agentstudio.performance.restore.main_thread.elapsed_ms"] == .double(0.5))
        let rendered = "\(projection.body)\n\(projection.resource)\n\(projection.attributes)"
        for forbidden in [
            "019be3be-7c00-7000-8000-000000000099", "claude --resume private-session",
            "private restore prompt", "/private/restore-store",
        ] {
            #expect(!rendered.contains(forbidden))
        }
    }
}
