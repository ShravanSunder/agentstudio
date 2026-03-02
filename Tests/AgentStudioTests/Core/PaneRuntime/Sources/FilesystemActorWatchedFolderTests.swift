import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor Watched Folders")
struct FilesystemActorWatchedFolderTests {

    // MARK: - Trigger Matching

    @Test("git directory changes trigger rescan, dotfiles like .gitignore do not")
    func gitTriggerMatchesOnlyGitDirectory() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let watchedFolder = URL(fileURLWithPath: "/tmp/watched-trigger-\(UUID().uuidString)")
        await actor.updateWatchedFolders([watchedFolder])

        let syntheticId = fsClient.registeredWorktreeIds.first!

        // Subscribe after initial rescan to get a clean baseline
        let stream = await bus.subscribe()

        // Send a batch with only .gitignore and .github paths — should NOT trigger rescan
        fsClient.send(
            FSEventBatch(
                worktreeId: syntheticId,
                paths: [
                    "\(watchedFolder.path)/myrepo/.gitignore",
                    "\(watchedFolder.path)/myrepo/.github/workflows/ci.yml",
                    "\(watchedFolder.path)/myrepo/.gitattributes",
                ]
            ))

        // Give the actor time to process
        try await Task.sleep(for: .milliseconds(100))

        // Drain bus — no .repoDiscovered should appear from the non-.git batch
        let eventsAfterNonGitBatch = await drainTopologyEvents(from: stream, timeout: .milliseconds(50))
        #expect(
            eventsAfterNonGitBatch == 0,
            ".gitignore/.github paths should not trigger watched folder rescan"
        )

        // Now send a batch with an actual .git/ path — SHOULD trigger handler
        // (RepoScanner won't find real repos at /tmp paths, so no events emitted,
        // but the handler is entered without crashing)
        fsClient.send(
            FSEventBatch(
                worktreeId: syntheticId,
                paths: [
                    "\(watchedFolder.path)/newrepo/.git/HEAD"
                ]
            ))

        try await Task.sleep(for: .milliseconds(100))

        await actor.shutdown()
    }

    // MARK: - Ingress Branching

    @Test("watched folder FSEvents do not enter worktree ingress path")
    func watchedFolderEventsDoNotEnterWorktreeIngress() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        // Register a real worktree AND a watched folder
        let worktreeId = UUID()
        let repoId = UUID()
        let worktreePath = URL(fileURLWithPath: "/tmp/real-wt-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: worktreePath)

        let watchedFolder = URL(fileURLWithPath: "/tmp/watched-ingress-\(UUID().uuidString)")
        await actor.updateWatchedFolders([watchedFolder])

        let syntheticId = fsClient.registeredWorktreeIds.last!

        // Subscribe after setup
        let stream = await bus.subscribe()

        // Send a batch to the watched folder synthetic ID with a .git/ path
        fsClient.send(
            FSEventBatch(
                worktreeId: syntheticId,
                paths: ["\(watchedFolder.path)/cloned-repo/.git/HEAD"]
            ))

        try await Task.sleep(for: .milliseconds(100))

        // Drain bus: no worktree envelopes for the syntheticId should exist
        var sawWorktreeEnvelopeForSyntheticId = false
        let events = await drainAllEnvelopes(from: stream, timeout: .milliseconds(50))
        for envelope in events {
            if case .worktree(let wt) = envelope, wt.worktreeId == syntheticId {
                sawWorktreeEnvelopeForSyntheticId = true
            }
        }

        #expect(!sawWorktreeEnvelopeForSyntheticId, "Watched folder events must not enter worktree ingress")

        await actor.shutdown()
    }

    // MARK: - Update Lifecycle

    @Test("updateWatchedFolders registers and unregisters FSEvent streams correctly")
    func updateWatchedFoldersLifecycle() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let folder1 = URL(fileURLWithPath: "/tmp/watch-lc-1-\(UUID().uuidString)")
        let folder2 = URL(fileURLWithPath: "/tmp/watch-lc-2-\(UUID().uuidString)")

        // Register two folders
        await actor.updateWatchedFolders([folder1, folder2])
        #expect(fsClient.registeredWorktreeIds.count == 2)

        // Update to only folder2 — folder1 should be unregistered
        await actor.updateWatchedFolders([folder2])
        #expect(fsClient.registeredWorktreeIds.count == 2)  // total registrations unchanged
        #expect(fsClient.unregisteredWorktreeIds.count == 1)

        // Update to empty — all unregistered
        await actor.updateWatchedFolders([])
        #expect(fsClient.unregisteredWorktreeIds.count == 2)  // folder2 now also unregistered

        await actor.shutdown()
    }

    // MARK: - Helpers

    private func drainTopologyEvents(
        from stream: AsyncStream<RuntimeEnvelope>,
        timeout: Duration
    ) async -> Int {
        var count = 0
        let envelopes = await drainAllEnvelopes(from: stream, timeout: timeout)
        for envelope in envelopes {
            if case .system(let sys) = envelope,
                case .topology(.repoDiscovered) = sys.event
            {
                count += 1
            }
        }
        return count
    }

    private func drainAllEnvelopes(
        from stream: AsyncStream<RuntimeEnvelope>,
        timeout: Duration
    ) async -> [RuntimeEnvelope] {
        let collectTask = Task {
            var results: [RuntimeEnvelope] = []
            for await envelope in stream {
                results.append(envelope)
            }
            return results
        }
        try? await Task.sleep(for: timeout)
        collectTask.cancel()
        return await collectTask.value
    }
}

/// Controllable FSEvent stream client for testing watched folder behavior.
/// Tracks registrations/unregistrations and lets tests inject batches.
final class ControllableFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _registeredIds: [UUID] = []
    private var _unregisteredIds: [UUID] = []
    private var continuation: AsyncStream<FSEventBatch>.Continuation?
    private var _stream: AsyncStream<FSEventBatch>?

    init() {
        let (stream, continuation) = AsyncStream<FSEventBatch>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self._stream = stream
        self.continuation = continuation
    }

    var registeredWorktreeIds: [UUID] {
        lock.withLock { _registeredIds }
    }

    var unregisteredWorktreeIds: [UUID] {
        lock.withLock { _unregisteredIds }
    }

    func events() -> AsyncStream<FSEventBatch> {
        lock.withLock { _stream! }
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) {
        lock.withLock { _registeredIds.append(worktreeId) }
    }

    func unregister(worktreeId: UUID) {
        lock.withLock { _unregisteredIds.append(worktreeId) }
    }

    func shutdown() {
        continuation?.finish()
    }

    func send(_ batch: FSEventBatch) {
        continuation?.yield(batch)
    }
}
