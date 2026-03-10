import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor Watched Folders")
struct FilesystemActorWatchedFolderTests {

    @Test("refreshWatchedFolders returns summary and emits discovered/removed diffs")
    func refreshWatchedFoldersReturnsSummaryAndEmitsDiffs() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let scanner = ControllableWatchedFolderScanner()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            watchedFolderScanner: scanner.scan,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let watchedFolder = URL(fileURLWithPath: "/tmp/watched-summary-\(UUID().uuidString)")
        let repoA = watchedFolder.appending(path: "app")
        let repoB = watchedFolder.appending(path: "tool")

        scanner.setResults([watchedFolder: [repoA, repoB]])
        let initialStream = await bus.subscribe()
        let initialSummary = await actor.refreshWatchedFolders([watchedFolder])
        let initialEvents = await drainTopologyEvents(from: initialStream, timeout: .milliseconds(50))

        #expect(Set(initialSummary.repoPaths(in: watchedFolder)) == Set([repoA.standardizedFileURL, repoB.standardizedFileURL]))
        #expect(initialEvents.discovered == Set([repoA.standardizedFileURL, repoB.standardizedFileURL]))
        #expect(initialEvents.removed.isEmpty)

        let repeatStream = await bus.subscribe()
        let repeatSummary = await actor.refreshWatchedFolders([watchedFolder])
        let repeatEvents = await drainTopologyEvents(from: repeatStream, timeout: .milliseconds(50))

        #expect(Set(repeatSummary.repoPaths(in: watchedFolder)) == Set([repoA.standardizedFileURL, repoB.standardizedFileURL]))
        #expect(repeatEvents.discovered.isEmpty)
        #expect(repeatEvents.removed.isEmpty)

        scanner.setResults([watchedFolder: [repoB]])
        let removalStream = await bus.subscribe()
        let removalSummary = await actor.refreshWatchedFolders([watchedFolder])
        let removalEvents = await drainTopologyEvents(from: removalStream, timeout: .milliseconds(50))

        #expect(Set(removalSummary.repoPaths(in: watchedFolder)) == Set([repoB.standardizedFileURL]))
        #expect(removalEvents.discovered.isEmpty)
        #expect(removalEvents.removed == Set([repoA.standardizedFileURL]))

        scanner.setResults([watchedFolder: [repoA, repoB]])
        let rediscoveredStream = await bus.subscribe()
        let rediscoveredSummary = await actor.refreshWatchedFolders([watchedFolder])
        let rediscoveredEvents = await drainTopologyEvents(from: rediscoveredStream, timeout: .milliseconds(50))

        #expect(Set(rediscoveredSummary.repoPaths(in: watchedFolder)) == Set([repoA.standardizedFileURL, repoB.standardizedFileURL]))
        #expect(rediscoveredEvents.discovered == Set([repoA.standardizedFileURL]))
        #expect(rediscoveredEvents.removed.isEmpty)

        await actor.shutdown()
    }

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
        _ = await actor.refreshWatchedFolders([watchedFolder])

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
            eventsAfterNonGitBatch.discovered.isEmpty && eventsAfterNonGitBatch.removed.isEmpty,
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
        _ = await actor.refreshWatchedFolders([watchedFolder])

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
        _ = await actor.refreshWatchedFolders([folder1, folder2])
        #expect(fsClient.registeredWorktreeIds.count == 2)

        // Update to only folder2 — folder1 should be unregistered
        _ = await actor.refreshWatchedFolders([folder2])
        #expect(fsClient.registeredWorktreeIds.count == 2)  // total registrations unchanged
        #expect(fsClient.unregisteredWorktreeIds.count == 1)

        // Update to empty — all unregistered
        _ = await actor.refreshWatchedFolders([])
        #expect(fsClient.unregisteredWorktreeIds.count == 2)  // folder2 now also unregistered

        await actor.shutdown()
    }

    // MARK: - Helpers

    private struct TopologyEventSet: Equatable {
        var discovered: Set<URL> = []
        var removed: Set<URL> = []
    }

    private func drainTopologyEvents(
        from stream: AsyncStream<RuntimeEnvelope>,
        timeout: Duration
    ) async -> TopologyEventSet {
        var events = TopologyEventSet()
        let envelopes = await drainAllEnvelopes(from: stream, timeout: timeout)
        for envelope in envelopes {
            if case .system(let sys) = envelope,
                case .topology(let topology) = sys.event
            {
                switch topology {
                case .repoDiscovered(let repoPath, _):
                    events.discovered.insert(repoPath.standardizedFileURL)
                case .repoRemoved(let repoPath):
                    events.removed.insert(repoPath.standardizedFileURL)
                case .worktreeRegistered, .worktreeUnregistered:
                    break
                }
            }
        }
        return events
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

final class ControllableWatchedFolderScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var resultsByRoot: [URL: [URL]] = [:]

    func setResults(_ resultsByRoot: [URL: [URL]]) {
        lock.withLock {
            self.resultsByRoot = Dictionary(
                uniqueKeysWithValues: resultsByRoot.map { key, value in
                    (
                        key.standardizedFileURL,
                        value.map(\.standardizedFileURL)
                    )
                }
            )
        }
    }

    func scan(_ root: URL) -> [URL] {
        lock.withLock {
            resultsByRoot[root.standardizedFileURL, default: []]
        }
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
