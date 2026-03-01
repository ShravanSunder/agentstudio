import Foundation
import Testing

@testable import AgentStudio

@Suite("DarwinFSEventStreamClient")
struct DarwinFSEventStreamClientTests {
    @Test("conforms to FSEventStreamClient protocol")
    func conformsToProtocol() {
        let client: any FSEventStreamClient = DarwinFSEventStreamClient()
        _ = client.events()
        client.shutdown()
    }

    @Test("register/unregister lifecycle is idempotent")
    func registerUnregisterLifecycleIsIdempotent() async {
        let client = DarwinFSEventStreamClient()
        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/darwin-fsevents-\(UUID().uuidString)")

        client.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        client.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        client.unregister(worktreeId: worktreeId)
        client.unregister(worktreeId: worktreeId)

        client.shutdown()
    }

    @Test("shutdown is idempotent and blocks future registration")
    func shutdownIsIdempotent() async {
        let client = DarwinFSEventStreamClient()
        client.shutdown()
        client.shutdown()

        client.register(
            worktreeId: UUID(),
            repoId: UUID(),
            rootPath: URL(fileURLWithPath: "/tmp/darwin-fsevents-post-shutdown-\(UUID().uuidString)")
        )
        client.unregister(worktreeId: UUID())
    }
}
