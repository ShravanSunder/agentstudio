import Foundation

enum WorkspaceSQLiteTraceOperation: String, Sendable {
    case activeWorkspaceSelect = "active_workspace.select"
    case inboxLoad = "inbox.load"
    case inboxSave = "inbox.save"
    case legacyImport = "legacy_import"
    case repoCacheLoad = "repo_cache.load"
    case repoCacheSave = "repo_cache.save"
    case sidebarLoad = "sidebar.load"
    case sidebarSave = "sidebar.save"
    case snapshotStatus = "snapshot.status"
    case uiStateLoad = "ui_state.load"
    case uiStateSave = "ui_state.save"
    case workspaceLoad = "workspace.load"
    case workspaceSave = "workspace.save"
}

enum WorkspaceSQLiteTracePhase: String, Sendable {
    case archiveLegacy = "archive_legacy"
    case classifyRecovery = "classify_recovery"
    case commitCore = "commit_core"
    case openCore = "open_core"
    case openLocalRestore = "open_local_restore"
    case openLocalSave = "open_local_save"
    case quarantineSidecars = "quarantine_sidecars"
    case repairLocal = "repair_local"
    case stageCore = "stage_core"
    case synthesizeDefaults = "synthesize_defaults"
    case writeLocal = "write_local"
}

enum WorkspaceSQLiteTraceLane: String, Sendable {
    case core
    case inbox
    case legacyImport = "legacy_import"
    case local
    case repoCache = "repo_cache"
    case sidebar
    case uiState = "ui_state"
    case workspace
}

enum WorkspaceSQLiteTraceOutcome: String, Sendable {
    case failed
    case partial
    case quarantined
    case recovered
    case reset
    case skipped
    case started
    case succeeded
}

enum WorkspaceSQLiteTraceDatabase: String, Sendable {
    case core
    case local
}

enum WorkspaceSQLiteRecoveryKind: String, Sendable {
    case coreQuarantine = "core_quarantine"
    case incompleteSnapshot = "incomplete_snapshot"
    case legacyImportFailed = "legacy_import_failed"
    case localQuarantine = "local_quarantine"
    case localRepairFailed = "local_repair_failed"
    case notADatabase = "not_a_database"
    case quarantineFailed = "quarantine_failed"
    case saveFailed = "save_failed"
}

struct WorkspaceSQLiteRecoveryTraceRecord: Sendable {
    var recoveryKind: WorkspaceSQLiteRecoveryKind
    var operation: WorkspaceSQLiteTraceOperation
    var phase: WorkspaceSQLiteTracePhase
    var lane: WorkspaceSQLiteTraceLane
    var outcome: WorkspaceSQLiteTraceOutcome
    var workspaceId: UUID?
    var database: WorkspaceSQLiteTraceDatabase?
    var databaseURL: URL?
    var error: (any Error)?
}

struct WorkspaceSQLiteSnapshotTraceRecord: Sendable {
    var snapshot: WorkspaceSQLiteSnapshot
    var operation: WorkspaceSQLiteTraceOperation
    var phase: WorkspaceSQLiteTracePhase
    var outcome: WorkspaceSQLiteTraceOutcome
    var error: (any Error)?
}

struct WorkspaceSQLiteTraceRecorder: Sendable {
    private struct TraceRecord {
        var operation: WorkspaceSQLiteTraceOperation
        var phase: WorkspaceSQLiteTracePhase
        var lane: WorkspaceSQLiteTraceLane
        var outcome: WorkspaceSQLiteTraceOutcome
        var workspaceId: UUID?
        var database: WorkspaceSQLiteTraceDatabase?
        var databaseURL: URL?
        var recoveryKind: WorkspaceSQLiteRecoveryKind?
        var error: (any Error)?
    }

    private let traceRuntime: AgentStudioTraceRuntime?

    init(traceRuntime: AgentStudioTraceRuntime?) {
        self.traceRuntime = traceRuntime
    }

    func recordOperation(
        _ operation: WorkspaceSQLiteTraceOperation,
        phase: WorkspaceSQLiteTracePhase,
        lane: WorkspaceSQLiteTraceLane,
        outcome: WorkspaceSQLiteTraceOutcome,
        workspaceId: UUID? = nil,
        database: WorkspaceSQLiteTraceDatabase? = nil,
        databaseURL: URL? = nil,
        error: (any Error)? = nil
    ) async {
        await traceRuntime?.record(
            tag: .persistenceOperation,
            body: "persistence.operation.phase",
            severity: outcome == .failed ? .error : .info,
            attributes: attributes(
                for: TraceRecord(
                    operation: operation,
                    phase: phase,
                    lane: lane,
                    outcome: outcome,
                    workspaceId: workspaceId,
                    database: database,
                    databaseURL: databaseURL,
                    recoveryKind: nil,
                    error: error
                ))
        )
    }

    func recordRecovery(_ record: WorkspaceSQLiteRecoveryTraceRecord) async {
        await traceRuntime?.record(
            tag: .persistenceRecovery,
            body: "persistence.recovery.\(record.outcome.rawValue)",
            severity: recoverySeverity(record.outcome),
            attributes: attributes(
                for: TraceRecord(
                    operation: record.operation,
                    phase: record.phase,
                    lane: record.lane,
                    outcome: record.outcome,
                    workspaceId: record.workspaceId,
                    database: record.database,
                    databaseURL: record.databaseURL,
                    recoveryKind: record.recoveryKind,
                    error: record.error
                ))
        )
    }

    func recordSnapshot(_ record: WorkspaceSQLiteSnapshotTraceRecord) async {
        await traceRuntime?.record(
            tag: .persistenceSnapshot,
            body: "persistence.snapshot.\(record.outcome.rawValue)",
            severity: record.outcome == .failed ? .error : .debug,
            attributes: snapshotAttributes(for: record)
        )
    }

    private func attributes(for record: TraceRecord) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.persistence.backend": .string("sqlite"),
            "agentstudio.persistence.lane": .string(record.lane.rawValue),
            "agentstudio.persistence.operation": .string(record.operation.rawValue),
            "agentstudio.persistence.outcome": .string(record.outcome.rawValue),
            "agentstudio.persistence.phase": .string(record.phase.rawValue),
        ]

        if let workspaceId = record.workspaceId {
            attributes["agentstudio.workspace.id"] = .string(workspaceId.uuidString)
        }
        if let database = record.database {
            attributes["agentstudio.sqlite.database"] = .string(database.rawValue)
        }
        if let databaseURL = record.databaseURL {
            attributes["agentstudio.sqlite.database_path"] = .string(Self.normalizedDisplayPath(databaseURL))
        }
        if let recoveryKind = record.recoveryKind {
            attributes["agentstudio.persistence.recovery.kind"] = .string(recoveryKind.rawValue)
        }
        if let error = record.error {
            attributes["agentstudio.persistence.error.description"] = .string(String(describing: error))
        }

        return attributes
    }

    private func snapshotAttributes(
        for record: WorkspaceSQLiteSnapshotTraceRecord
    ) -> [String: AgentStudioTraceValue] {
        var attributes = WorkspaceSQLiteSnapshotDiagnostics(snapshot: record.snapshot).attributes(error: record.error)
        attributes["agentstudio.persistence.backend"] = .string("sqlite")
        attributes["agentstudio.persistence.operation"] = .string(record.operation.rawValue)
        attributes["agentstudio.persistence.outcome"] = .string(record.outcome.rawValue)
        attributes["agentstudio.persistence.phase"] = .string(record.phase.rawValue)
        attributes["agentstudio.workspace.id"] = .string(record.snapshot.id.uuidString)
        return attributes
    }

    private func recoverySeverity(_ outcome: WorkspaceSQLiteTraceOutcome) -> AgentStudioTraceSeverity {
        switch outcome {
        case .failed:
            .error
        case .partial, .quarantined, .recovered, .reset:
            .warn
        case .skipped, .started, .succeeded:
            .info
        }
    }

    private static func normalizedDisplayPath(_ url: URL) -> String {
        let standardizedPath = NSString(string: url.path).standardizingPath
        let homePath = NSString(string: NSHomeDirectory()).standardizingPath
        if standardizedPath == homePath {
            return "~"
        }
        let homePrefix = "\(homePath)/"
        if standardizedPath.hasPrefix(homePrefix) {
            return "~/" + standardizedPath.dropFirst(homePrefix.count)
        }
        return standardizedPath
    }
}
