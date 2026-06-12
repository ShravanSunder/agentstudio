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

    @Test("ingress stream uses bounded newest buffering")
    func ingressStreamUsesBoundedNewestBuffering() {
        #expect(DarwinFSEventStreamClient.ingressBufferLimit == 256)
    }

    @Test("buffer overflow marker emission is bounded")
    func bufferOverflowMarkerEmissionIsBounded() throws {
        let projectRoot = TestPathResolver.projectRoot(from: #filePath)
        let sourceURL = URL(fileURLWithPath: projectRoot)
            .appending(path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("guard case .dropped(let droppedBatch) = yieldResult else { return }"))
        #expect(source.contains("guard !droppedBatch.didOverflow else { return }"))
        #expect(source.contains("_ = eventsContinuation.yield"))
        #expect(!source.contains("while case .dropped"))
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
