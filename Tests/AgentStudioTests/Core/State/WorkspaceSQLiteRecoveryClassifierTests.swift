import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("WorkspaceSQLiteRecoveryClassifierTests")
struct WorkspaceSQLiteRecoveryClassifierTests {
    @Test("only SQLite corruption errors require quarantine")
    func onlySQLiteCorruptionErrorsRequireQuarantine() {
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
