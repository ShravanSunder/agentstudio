import AgentStudioAppIPC
import Foundation
import Testing

@Suite("AgentStudio App IPC service auth modes", .serialized)
struct AgentStudioAppIPCServiceAuthModeTests {
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
