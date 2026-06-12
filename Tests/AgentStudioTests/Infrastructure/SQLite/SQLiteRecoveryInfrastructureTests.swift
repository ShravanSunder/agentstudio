import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("SQLiteRecoveryInfrastructureTests")
struct SQLiteRecoveryInfrastructureTests {
    @Test("sidecar quarantine treats nothing to move as reset allowed")
    func sidecarQuarantineTreatsNothingToMoveAsResetAllowed() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-missing-sidecar-\(UUID().uuidString).sqlite")

        let result = SQLiteSidecarQuarantine.quarantine(databaseURL: databaseURL)

        #expect(result.status == .nothingToMove)
        #expect(result.succeeded)
        #expect(result.recoveryFilename == nil)
    }

    @Test("sidecar quarantine reports partial moves separately from full failure")
    func sidecarQuarantineReportsPartialMovesSeparately() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-partial-sidecar-\(UUID().uuidString).sqlite")
        let fixedDate = Date(timeIntervalSince1970: 100)

        let result = SQLiteSidecarQuarantine.quarantine(
            databaseURL: databaseURL,
            date: fixedDate,
            fileExists: { _ in true },
            moveItem: { sourceURL, _ in
                if sourceURL.lastPathComponent.hasSuffix("-wal") {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
        )

        #expect(result.status == .partiallyMoved)
        #expect(!result.succeeded)
        #expect(result.failedFilenames == ["\(databaseURL.lastPathComponent)-wal"])
        #expect(result.quarantinedFilenames.count == 2)
        #expect(result.recoveryFilename?.contains("quarantined:") == true)
        #expect(result.recoveryFilename?.contains("failed: \(databaseURL.lastPathComponent)-wal") == true)
    }

    @Test("recovery classifier only quarantines SQLite corruption errors")
    func recoveryClassifierOnlyQuarantinesSQLiteCorruptionErrors() {
        let corruptError = DatabaseError(resultCode: .SQLITE_CORRUPT)
        let notDatabaseError = DatabaseError(resultCode: .SQLITE_NOTADB)
        let busyError = DatabaseError(resultCode: .SQLITE_BUSY)
        let fileError = CocoaError(.fileReadNoPermission)

        #expect(WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(corruptError))
        #expect(WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(notDatabaseError))
        #expect(!WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(busyError))
        #expect(!WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(fileError))
    }
}
