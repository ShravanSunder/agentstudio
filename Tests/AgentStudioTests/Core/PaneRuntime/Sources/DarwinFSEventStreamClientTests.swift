import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinFSEventStreamClient")
struct DarwinFSEventStreamClientTests {
    @Test("filesystem ingress does not retain more fine batches than its configured capacity")
    func ingressRetainsAtMostConfiguredFineBatchCapacity() async throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 2)
        let worktreeId = UUID()
        ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: ["first"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: ["second"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: ["third"]))
        ingressBuffer.finish()

        var retainedBatches: [FSEventBatch] = []
        for await batch in ingressBuffer.events() {
            retainedBatches.append(batch)
        }

        #expect(retainedBatches.count <= 2)
        #expect(ingressBuffer.consumeOverflowRecoveries().map(\.worktreeId) == [worktreeId])
    }

    @Test("overflow debt coalesces per affected worktree and stays isolated")
    func overflowDebtCoalescesPerAffectedWorktree() {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 1)
        let retainedWorktreeId = UUID()
        let overflowedWorktreeId = UUID()
        let otherOverflowedWorktreeId = UUID()

        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["first"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["second"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: otherOverflowedWorktreeId, paths: ["other"]))

        let recoveries = ingressBuffer.consumeOverflowRecoveries()
        #expect(Set(recoveries.map(\.worktreeId)) == [overflowedWorktreeId, otherOverflowedWorktreeId])
        #expect(recoveries.first { $0.worktreeId == overflowedWorktreeId }?.paths == ["first", "second"])
        #expect(recoveries.first { $0.worktreeId == otherOverflowedWorktreeId }?.paths == ["other"])
        #expect(ingressBuffer.consumeOverflowRecoveries().isEmpty)
        ingressBuffer.finish()
    }

    @Test("overflow recovery preserves known path scope")
    func overflowRecoveryPreservesKnownPathScope() throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 1)
        let retainedWorktreeId = UUIDv7.generate()
        let overflowedWorktreeId = UUIDv7.generate()

        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(
            FSEventBatch(
                worktreeId: overflowedWorktreeId,
                paths: ["Sources/First.swift", "Sources/Second.swift"]
            )
        )

        let recovery = try #require(ingressBuffer.consumeOverflowRecoveries().first)
        #expect(recovery.worktreeId == overflowedWorktreeId)
        #expect(recovery.paths == ["Sources/First.swift", "Sources/Second.swift"])
        ingressBuffer.finish()
    }

    @Test("overflow recovery becomes coarse when retained path scope exceeds its bound")
    func overflowRecoveryBecomesCoarseWhenScopeExceedsBound() throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: 1,
            maximumRetainedOverflowPathsPerRegistration: 2
        )
        let retainedWorktreeId = UUIDv7.generate()
        let overflowedWorktreeId = UUIDv7.generate()
        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(
            FSEventBatch(
                worktreeId: overflowedWorktreeId,
                paths: ["one", "two", "three"]
            )
        )
        ingressBuffer.yield(FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["later"]))

        let recovery = try #require(ingressBuffer.consumeOverflowRecoveries().first)
        #expect(recovery.worktreeId == overflowedWorktreeId)
        #expect(recovery.paths == nil)
        ingressBuffer.finish()
    }

    @Test("shutdown terminates ingress without minting new overflow debt")
    func shutdownTerminatesIngressWithoutNewDebt() {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 1)
        ingressBuffer.finish()

        ingressBuffer.yield(FSEventBatch(worktreeId: UUID(), paths: ["post-shutdown"]))

        #expect(ingressBuffer.consumeOverflowRecoveries().isEmpty)
    }

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
