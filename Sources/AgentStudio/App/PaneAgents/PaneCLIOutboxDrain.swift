import AgentStudioCLIStore
import AgentStudioInfrastructure
import AgentStudioSessions
import Foundation

/// Compile-only S2 red boundary. Admission and durable cursor handling are
/// intentionally absent until the Lead verifies the outbox behavior tests.
actor PaneCLIOutboxDrain {
    enum RefusalReason: String, Sendable {
        case malformedEnvelope
        case ineligibleMethod
        case ineligibleVariant
        case foreignPane
        case unknownKind
        case invalidStoredRow
        case qualificationRejected
        case foreignStore
    }

    struct DrainReport: Equatable, Sendable {
        var admittedEntryCount = 0
        var refusedEntryCount = 0
        var malformedEntryCount = 0
        var retryableEntryCount = 0
        var refusedStoreCount = 0
        var importedLegacyLineCount = 0
    }

    init(
        admission: AgentStudioIPCSessionsAdapter,
        sqliteAccess: any SessionsSQLiteAccess,
        expectedChannel: CLIStoreChannel,
        maximumPayloadBytes: Int = AppPolicies.IPC.spoolDrainMaximumLineBytes,
        refusalProbe: @escaping @Sendable (RefusalReason) -> Void = { _ in }
    ) throws {}

    func drain(storeURL: URL, legacySpoolDirectory: URL? = nil) async -> DrainReport {
        DrainReport()
    }
}
