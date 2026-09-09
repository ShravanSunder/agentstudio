import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("FilesystemActor Ownership Cache")
struct FilesystemActorOwnershipCacheTests {
    @Test("filesystem ingress reuses ownership until root topology changes")
    func filesystemIngressReusesOwnershipUntilRootTopologyChanges() async {
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: TestPushClock(),
            debounceWindow: .seconds(60),
            maxFlushLatency: .seconds(120)
        )
        let firstWorktreeID = UUIDv7.generate()
        let secondWorktreeID = UUIDv7.generate()

        #expect(await actor.rootOwnershipRevision == 0)
        await actor.register(
            worktreeId: firstWorktreeID,
            repoId: UUIDv7.generate(),
            rootPath: URL(fileURLWithPath: "/tmp/ownership-cache-first")
        )
        #expect(await actor.rootOwnershipRevision == 1)

        await actor.enqueueRawPaths(
            worktreeId: firstWorktreeID,
            paths: ["Sources/Changed.swift"]
        )
        await actor.setActivity(worktreeId: firstWorktreeID, isActiveInApp: true)
        #expect(await actor.rootOwnershipRevision == 1)

        await actor.register(
            worktreeId: secondWorktreeID,
            repoId: UUIDv7.generate(),
            rootPath: URL(fileURLWithPath: "/tmp/ownership-cache-second")
        )
        #expect(await actor.rootOwnershipRevision == 2)

        await actor.unregister(worktreeId: firstWorktreeID)
        #expect(await actor.rootOwnershipRevision == 3)
        await actor.shutdown()
    }
}
