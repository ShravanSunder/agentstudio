import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalRestorePurityTests", .serialized)
struct TerminalRestorePurityTests {
    @Test("restore returns exact durable identity without inventory or persistence mutation")
    func restoreReturnsExactDurableIdentityWithoutInventoryOrPersistenceMutation() throws {
        let storedText = "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-5566778899001122"
        let storedSessionID = try #require(ZmxSessionID(restoring: storedText))
        let unrelatedRepoID = UUIDv7.generate()
        let unrelatedWorktreeID = UUIDv7.generate()
        let pane = Pane(
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: storedSessionID
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/current-cwd-must-not-affect-identity"),
                title: "Restored terminal",
                facets: PaneContextFacets(
                    repoId: unrelatedRepoID,
                    worktreeId: unrelatedWorktreeID,
                    cwd: URL(filePath: "/tmp/another-current-cwd")
                )
            )
        )
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        let restoredSessionID = try #require(runtime.zmxSessionID(for: pane))

        #expect(restoredSessionID == storedSessionID)
        #expect(restoredSessionID.rawValue == storedText)
    }
}
