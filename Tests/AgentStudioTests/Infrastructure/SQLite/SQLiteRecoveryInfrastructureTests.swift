import Foundation
import Testing

@testable import AgentStudioInfrastructure

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
}
