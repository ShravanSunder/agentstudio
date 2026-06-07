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
