import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceSQLiteTraceRecorderTests")
struct WorkspaceSQLiteTraceRecorderTests {
    @Test("operation records use persistence operation tag and normalized database path")
    func operationRecordsUsePersistenceOperationTagAndNormalizedDatabasePath() async throws {
        let traceRuntime = makeTraceRuntime(tags: "persistence.operation")
        let recorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
        let workspaceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let databaseURL = URL(
            fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/AgentStudio/core.sqlite"
        )

        await recorder.recordOperation(
            .workspaceSave,
            phase: .stageCore,
            lane: .workspace,
            outcome: .started,
            workspaceId: workspaceId,
            database: .core,
            databaseURL: databaseURL
        )
        try await traceRuntime.flush()

        let contents = try traceContents(from: traceRuntime)
        #expect(contents.contains("\"body\":\"persistence.operation.phase\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.operation\""))
        #expect(contents.contains("\"agentstudio.persistence.backend\":\"sqlite\""))
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"workspace.save\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"stage_core\""))
        #expect(contents.contains("\"agentstudio.persistence.lane\":\"workspace\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"started\""))
        #expect(contents.contains("\"agentstudio.workspace.id\":\"\(workspaceId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.sqlite.database\":\"core\""))
        #expect(
            contents.contains(
                "\"agentstudio.sqlite.database_path\":\"~/Library/Application Support/AgentStudio/core.sqlite\""
            )
        )
        #expect(!contents.contains(NSHomeDirectory()))
    }

    @Test("recovery records use persistence recovery tag")
    func recoveryRecordsUsePersistenceRecoveryTag() async throws {
        let traceRuntime = makeTraceRuntime(tags: "persistence.recovery")
        let recorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
        let workspaceId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        await recorder.recordRecovery(
            .init(
                recoveryKind: .localQuarantine,
                operation: .workspaceLoad,
                phase: .quarantineSidecars,
                lane: .local,
                outcome: .quarantined,
                workspaceId: workspaceId,
                database: .local,
                databaseURL: URL(fileURLWithPath: "/tmp/\(workspaceId.uuidString).local.sqlite"),
                error: nil
            )
        )
        try await traceRuntime.flush()

        let contents = try traceContents(from: traceRuntime)
        #expect(contents.contains("\"body\":\"persistence.recovery.quarantined\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.recovery\""))
        #expect(contents.contains("\"agentstudio.persistence.operation\":\"workspace.load\""))
        #expect(contents.contains("\"agentstudio.persistence.phase\":\"quarantine_sidecars\""))
        #expect(contents.contains("\"agentstudio.persistence.lane\":\"local\""))
        #expect(contents.contains("\"agentstudio.persistence.outcome\":\"quarantined\""))
        #expect(contents.contains("\"agentstudio.persistence.recovery.kind\":\"local_quarantine\""))
        #expect(contents.contains("\"agentstudio.sqlite.database\":\"local\""))
    }

    @Test("snapshot records expose bounded workspace graph diagnostics")
    func snapshotRecordsExposeBoundedWorkspaceGraphDiagnostics() async throws {
        let traceRuntime = makeTraceRuntime(tags: "persistence.snapshot")
        let recorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
        let workspaceId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        await recorder.recordSnapshot(
            .init(
                snapshot: .snapshotWithArrangementPaneMissingFromTab(workspaceId: workspaceId),
                operation: .workspaceSave,
                phase: .commitCore,
                outcome: .failed,
                error: WorkspaceSQLiteDatastoreError.missingConfiguration
            )
        )
        try await traceRuntime.flush()

        let contents = try traceContents(from: traceRuntime)
        #expect(contents.contains("\"body\":\"persistence.snapshot.failed\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"persistence.snapshot\""))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.has_tab_membership_mismatch\":true"))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.tab_membership_mismatches\""))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.pane_count\":2"))
        #expect(contents.contains("\"agentstudio.persistence.error.description\":\"missingConfiguration\""))
    }

    @Test("snapshot records expose drawer view membership mismatch diagnostics")
    func snapshotRecordsExposeDrawerViewMembershipMismatchDiagnostics() async throws {
        let traceRuntime = makeTraceRuntime(tags: "persistence.snapshot")
        let recorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)

        await recorder.recordSnapshot(
            .init(
                snapshot: .snapshotWithDrawerViewPaneMissingFromTab(),
                operation: .workspaceSave,
                phase: .commitCore,
                outcome: .failed,
                error: nil
            )
        )
        try await traceRuntime.flush()

        let contents = try traceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.workspace.snapshot.has_tab_membership_mismatch\":true"))
        #expect(contents.contains("source=drawer_view"))
        #expect(contents.contains("drawer="))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.drawer_view_pane_counts\""))
    }

    @Test("snapshot records expose orphaned tab membership diagnostics")
    func snapshotRecordsExposeOrphanedTabMembershipDiagnostics() async throws {
        let traceRuntime = makeTraceRuntime(tags: "persistence.snapshot")
        let recorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)

        await recorder.recordSnapshot(
            .init(
                snapshot: .snapshotWithMembershipPaneMissingFromArrangements(),
                operation: .workspaceSave,
                phase: .commitCore,
                outcome: .failed,
                error: nil
            )
        )
        try await traceRuntime.flush()

        let contents = try traceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.workspace.snapshot.has_tab_membership_mismatch\":true"))
        #expect(contents.contains("source=membership_orphan"))
    }

    @Test("snapshot records retired source facet mismatch diagnostics as empty")
    func snapshotRecordsRetiredSourceFacetMismatchDiagnosticsAsEmpty() async throws {
        let traceRuntime = makeTraceRuntime(tags: "persistence.snapshot")
        let recorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)

        await recorder.recordSnapshot(
            .init(
                snapshot: .snapshotWithArrangementPaneMissingFromTab(),
                operation: .workspaceSave,
                phase: .stageCore,
                outcome: .started,
                error: nil
            )
        )
        try await traceRuntime.flush()

        let contents = try traceContents(from: traceRuntime)
        #expect(contents.contains("\"agentstudio.workspace.snapshot.has_source_facet_mismatch\":false"))
        #expect(contents.contains("\"agentstudio.workspace.snapshot.source_facet_mismatches\""))
        #expect(!contents.contains("sourceRepo="))
        #expect(!contents.contains("facetRepo="))
    }

    private func makeTraceRuntime(tags: String) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_NAME": "sqlite-trace-recorder",
                "AGENTSTUDIO_TRACE_TAGS": tags,
            ]),
            processIdentifier: 910,
            timeUnixNano: { 1000 }
        )
    }

    private func traceContents(from traceRuntime: AgentStudioTraceRuntime) throws -> String {
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        return try String(contentsOf: outputFileURL, encoding: .utf8)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-sqlite-trace-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
