import Foundation
import Testing

@testable import AgentStudio

@Suite("ZmxBackendTypedIdentityTests", .serialized)
struct ZmxBackendTypedIdentityTests {
    @Test("attach and kill use the exact opaque identity")
    func attachAndKillUseExactOpaqueIdentity() async throws {
        let executor = MockProcessExecutor()
        let backend = ZmxBackend(
            executor: executor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx-typed-identity-test",
            retryPolicy: .singleAttempt
        )
        let storedText = "as-d--bc219f0a5b7c8d9e--a1234f00b16e1aa2"
        let storedSessionID = try #require(ZmxSessionID(restoring: storedText))
        let handle = PaneSessionHandle(id: storedSessionID)
        executor.enqueueSuccess()

        let attachCommand = backend.attachCommand(for: handle)
        try await backend.destroyPaneSession(handle)

        #expect(attachCommand.contains("\"\(storedText)\""))
        #expect(executor.calls.single?.args == ["kill", storedText])
    }

    @Test("inventory parses UUID and legacy opaque identities without rewriting")
    func inventoryParsesUUIDAndLegacyOpaqueIdentitiesWithoutRewriting() async throws {
        let executor = MockProcessExecutor()
        let backend = ZmxBackend(
            executor: executor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx-typed-inventory-test",
            retryPolicy: .singleAttempt
        )
        let uuidV4Text = "550E8400-E29B-41D4-A716-446655440000"
        let legacyText = "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-5566778899001122"
        executor.enqueueSuccess(
            "name=\(uuidV4Text)\tpid=123\nname=\(legacyText)\tpid=456\nname=\tpid=789"
        )

        let inventory = await backend.discoverAgentStudioSessions()

        let expectedUUIDV4 = try #require(ZmxSessionID(restoring: uuidV4Text))
        let expectedLegacy = try #require(ZmxSessionID(restoring: legacyText))
        #expect(inventory.sessionIDs == Set([expectedUUIDV4, expectedLegacy]))
    }
}
