import AgentStudioCLIStore
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation

enum CLILifecycleRefusalReason: String, Equatable, Sendable {
    case invalidStoredRow, qualificationRejected, retiredPane, foreignStore, supersededByUnorderedReport
}

/// Dispositions the immutable CLI prefix through Sessions' existing local transaction owner.
actor CLILifecycleReportIntake: LifecycleReportIntaking {
    // S4 RED stand-in: dependencies are declared at the planned intake boundary.
    init(
        storeURL: URL, expectedChannel: CLIStoreChannel, admission: AgentStudioIPCSessionsAdapter,
        sqliteAccess: any SessionsSQLiteAccess,
        paneExists: @escaping @Sendable (UUID) async throws -> Bool,
        refusalProbe: @escaping @Sendable (CLILifecycleRefusalReason) -> Void = { _ in }
    ) {}

    // S4 RED stand-in: no store boundary is captured.
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary { .noStore }

    // S4 RED stand-in: no historical reports are applied.
    func takeIn(through boundary: LifecycleReportBoundary) async throws {}

    // S4 RED stand-in: the live lifecycle route earns no mutation or cursor.
    func recordLive(paneId: UUID, params: IPCSessionEventParams) async throws -> IPCSessionEventResult {
        .init(paneId: paneId, disposition: .unqualified, correlationId: params.correlationId)
    }
}
