import Foundation

actor AgentStudioOTLPTraceSink: AgentStudioTraceSink {
    private let context: AgentStudioOTLPTraceSinkContext
    private let bootstrapper: any AgentStudioOTLPBootstrapping

    init(
        context: AgentStudioOTLPTraceSinkContext,
        bootstrapper: any AgentStudioOTLPBootstrapping = AgentStudioOTLPBootstrapper.shared
    ) {
        self.context = context
        self.bootstrapper = bootstrapper
    }

    func record(_ record: AgentStudioTraceRecord) async throws {
        let projectedRecord = AgentStudioOTLPTraceProjection.project(record)
        await bootstrapper.emit(projectedRecord, context: context)
    }

    func flush() async throws {
        await bootstrapper.flush()
    }

    func shutdown() async throws {
        await bootstrapper.shutdown()
    }

    func diagnostics() async -> AgentStudioTraceWriterDiagnostics {
        .empty
    }
}
