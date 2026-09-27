import Foundation
import Testing

@testable import AgentStudioInfrastructure

extension GitRefreshPerformanceWorkloadScriptTests {
    @Test("owned zmx cleanup rejects a deadline with a numeric prefix and invalid suffix")
    func ownedZmxCleanupRejectsInvalidListDeadline() async throws {
        let fixtureRoot = URL(fileURLWithPath: "/tmp/asw.invalid-deadline-\(UUIDv7.generate().uuidString)")
        let artifact = fixtureRoot.appendingPathComponent("cleanup.env")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try await runScript(
            arguments: [
                "scripts/cleanup-owned-zmx-sessions.sh", "/must-not-run/zmx", fixtureRoot.path, artifact.path, "owned",
            ],
            environment: ["OWNED_ZMX_LIST_DEADLINE_SECONDS": "10oops"]
        )

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("invalid OWNED_ZMX_LIST_DEADLINE_SECONDS: 10oops"))
    }
}
