import AgentStudioAppIPC
import Foundation
import Testing

@Suite("AgentStudio App IPC service auth modes", .serialized)
struct AgentStudioAppIPCServiceAuthModeTests {
    @Test("debug server without explicit escrow does not expose an automation token")
    func debugServerWithoutExplicitEscrowDoesNotExposeAutomationToken() throws {
        let fixture = try LiveServerFixture(
            channel: .debug,
            debugTokenEscrowEnabled: false
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.debugTokenURL.path))
    }

    @Test("non-debug server channels ignore debug token escrow")
    func nonDebugServerChannelsIgnoreDebugTokenEscrow() throws {
        let fixture = try LiveServerFixture(
            channel: .stable,
            debugTokenEscrowEnabled: true
        )
        defer {
            fixture.cleanup()
        }
        try fixture.server.start()

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.debugTokenURL.path))
    }
}
