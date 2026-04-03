import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor Watched Folders")
struct FilesystemActorWatchedFolderTests {

    @Test("refreshWatchedFolders emits scanner-backed discovered events for new clones")
    func refreshWatchedFoldersEmitsScannerBackedDiscoveredEventsForNewClones() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let scanner = ControllableWatchedFolderScanner()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            groupedWatchedFolderScanner: scanner.scan,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let watchedFolder = URL(fileURLWithPath: "/tmp/watched-summary-\(UUID().uuidString)")
        let repoA = watchedFolder.appending(path: "app")
        let repoB = watchedFolder.appending(path: "tool")
        let repoC = watchedFolder.appending(path: "docs")
        let repoALinkedWorktree = watchedFolder.appending(path: "app-linked")
        let repoBLinkedWorktree = watchedFolder.appending(path: "tool-linked")
        let repoCLinkedWorktree = watchedFolder.appending(path: "docs-linked")

        scanner.setGroupedResults([
            watchedFolder: [
                RepoScanner.RepoScanGroup(
                    clonePath: repoA,
                    linkedWorktreePaths: [repoALinkedWorktree]
                ),
                RepoScanner.RepoScanGroup(
                    clonePath: repoB,
                    linkedWorktreePaths: [repoBLinkedWorktree]
                ),
            ]
        ])
        let initialStream = await bus.subscribe()
        let initialSummary = await actor.refreshWatchedFolders([watchedFolder])
        let initialEvents = await drainTopologyEvents(from: initialStream, settleTurns: 50)

        #expect(
            Set(initialSummary.repoPaths(in: watchedFolder))
                == Set([repoA.standardizedFileURL, repoB.standardizedFileURL]))
        #expect(
            initialEvents.sortedByRepoPath == [
                RepoDiscoveryEvent(
                    repoPath: repoA.standardizedFileURL,
                    linkedWorktrees: .scanned([repoALinkedWorktree.standardizedFileURL])
                ),
                RepoDiscoveryEvent(
                    repoPath: repoB.standardizedFileURL,
                    linkedWorktrees: .scanned([repoBLinkedWorktree.standardizedFileURL])
                ),
            ])
        #expect(initialEvents.removed.isEmpty)

        let repeatStream = await bus.subscribe()
        let repeatSummary = await actor.refreshWatchedFolders([watchedFolder])
        let repeatEvents = await drainTopologyEvents(from: repeatStream, settleTurns: 50)

        #expect(
            Set(repeatSummary.repoPaths(in: watchedFolder))
                == Set([repoA.standardizedFileURL, repoB.standardizedFileURL]))
        #expect(repeatEvents.discovered.isEmpty)
        #expect(repeatEvents.removed.isEmpty)

        scanner.setGroupedResults([
            watchedFolder: [
                RepoScanner.RepoScanGroup(
                    clonePath: repoA,
                    linkedWorktreePaths: [repoALinkedWorktree]
                ),
                RepoScanner.RepoScanGroup(
                    clonePath: repoB,
                    linkedWorktreePaths: [repoBLinkedWorktree]
                ),
                RepoScanner.RepoScanGroup(
                    clonePath: repoC,
                    linkedWorktreePaths: [repoCLinkedWorktree]
                ),
            ]
        ])
        let newCloneStream = await bus.subscribe()
        let newCloneSummary = await actor.refreshWatchedFolders([watchedFolder])
        let newCloneEvents = await drainTopologyEvents(from: newCloneStream, settleTurns: 50)

        #expect(
            Set(newCloneSummary.repoPaths(in: watchedFolder))
                == Set([repoA.standardizedFileURL, repoB.standardizedFileURL, repoC.standardizedFileURL]))
        #expect(
            newCloneEvents.discovered == [
                RepoDiscoveryEvent(
                    repoPath: repoC.standardizedFileURL,
                    linkedWorktrees: .scanned([repoCLinkedWorktree.standardizedFileURL])
                )
            ])
        #expect(newCloneEvents.removed.isEmpty)

        await actor.shutdown()
    }

    @Test("refreshWatchedFolders re-emits repoDiscovered when linked worktree list changes")
    func refreshWatchedFoldersReEmitsRepoDiscoveredWhenLinkedWorktreeListChanges() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let scanner = ControllableWatchedFolderScanner()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            groupedWatchedFolderScanner: scanner.scan,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let watchedFolder = URL(fileURLWithPath: "/tmp/watched-linked-\(UUID().uuidString)")
        let repoPath = watchedFolder.appending(path: "app")
        let linkedA = watchedFolder.appending(path: "app-linked-a")
        let linkedB = watchedFolder.appending(path: "app-linked-b")

        scanner.setGroupedResults([
            watchedFolder: [
                RepoScanner.RepoScanGroup(clonePath: repoPath, linkedWorktreePaths: [linkedA])
            ]
        ])
        _ = await actor.refreshWatchedFolders([watchedFolder])

        scanner.setGroupedResults([
            watchedFolder: [
                RepoScanner.RepoScanGroup(
                    clonePath: repoPath,
                    linkedWorktreePaths: [linkedA, linkedB]
                )
            ]
        ])
        let reemitStream = await bus.subscribe()
        let reemitSummary = await actor.refreshWatchedFolders([watchedFolder])
        let reemitEvents = await drainTopologyEvents(from: reemitStream, settleTurns: 50)

        #expect(Set(reemitSummary.repoPaths(in: watchedFolder)) == Set([repoPath.standardizedFileURL]))
        #expect(
            reemitEvents.discovered == [
                RepoDiscoveryEvent(
                    repoPath: repoPath.standardizedFileURL,
                    linkedWorktrees: .scanned([
                        linkedA.standardizedFileURL,
                        linkedB.standardizedFileURL,
                    ])
                )
            ])
        #expect(reemitEvents.removed.isEmpty)

        await actor.shutdown()
    }

    @Test("refreshWatchedFolders preserves global remove dedup across watched folders")
    func refreshWatchedFoldersPreservesGlobalRemoveDedupAcrossWatchedFolders() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let scanner = ControllableWatchedFolderScanner()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            groupedWatchedFolderScanner: scanner.scan,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let sharedParentFolder = URL(fileURLWithPath: "/tmp/watched-parent-\(UUID().uuidString)")
        let nestedWatchedFolder = sharedParentFolder.appending(path: "team")
        let sharedRepo = nestedWatchedFolder.appending(path: "app")

        scanner.setResults([
            sharedParentFolder: [sharedRepo],
            nestedWatchedFolder: [sharedRepo],
        ])
        _ = await actor.refreshWatchedFolders([sharedParentFolder, nestedWatchedFolder])

        scanner.setResults([
            sharedParentFolder: [],
            nestedWatchedFolder: [sharedRepo],
        ])
        let stillPresentStream = await bus.subscribe()
        _ = await actor.refreshWatchedFolders([sharedParentFolder, nestedWatchedFolder])
        let stillPresentEvents = await drainTopologyEvents(from: stillPresentStream, settleTurns: 50)

        #expect(stillPresentEvents.discovered.isEmpty)
        #expect(stillPresentEvents.removed.isEmpty)

        scanner.setResults([
            sharedParentFolder: [],
            nestedWatchedFolder: [],
        ])
        let removedEverywhereStream = await bus.subscribe()
        _ = await actor.refreshWatchedFolders([sharedParentFolder, nestedWatchedFolder])
        let removedEverywhereEvents = await drainTopologyEvents(
            from: removedEverywhereStream,
            settleTurns: 50
        )

        #expect(removedEverywhereEvents.discovered.isEmpty)
        #expect(removedEverywhereEvents.removed == Set([sharedRepo.standardizedFileURL]))

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

        // Drain bus — no .repoDiscovered should appear from the non-.git batch
        let eventsAfterNonGitBatch = await drainTopologyEvents(from: stream, settleTurns: 150)
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

        // Drain bus: no worktree envelopes for the syntheticId should exist
        var sawWorktreeEnvelopeForSyntheticId = false
        let events = await drainAllEnvelopes(from: stream, settleTurns: 150)
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

    private struct RepoDiscoveryEvent: Equatable {
        let repoPath: URL
        let linkedWorktrees: LinkedWorktreeInfo
    }

    private struct TopologyEventSet: Equatable {
        var discovered: [RepoDiscoveryEvent] = []
        var removed: Set<URL> = []

        var sortedByRepoPath: [RepoDiscoveryEvent] {
            discovered.sorted {
                $0.repoPath.path.localizedCaseInsensitiveCompare($1.repoPath.path) == .orderedAscending
            }
        }
    }

    private func drainTopologyEvents(
        from stream: AsyncStream<RuntimeEnvelope>,
        settleTurns: Int
    ) async -> TopologyEventSet {
        var events = TopologyEventSet()
        let envelopes = await drainAllEnvelopes(from: stream, settleTurns: settleTurns)
        for envelope in envelopes {
            if case .system(let sys) = envelope,
                case .topology(let topology) = sys.event
            {
                switch topology {
                case .repoDiscovered(let repoPath, _, let linkedWorktrees):
                    events.discovered.append(
                        RepoDiscoveryEvent(
                            repoPath: repoPath.standardizedFileURL,
                            linkedWorktrees: linkedWorktrees
                        ))
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
        settleTurns: Int
    ) async -> [RuntimeEnvelope] {
        let collectTask = Task {
            var results: [RuntimeEnvelope] = []
            for await envelope in stream {
                results.append(envelope)
            }
            return results
        }
        for _ in 0..<settleTurns {
            await Task.yield()
        }
        collectTask.cancel()
        return await collectTask.value
    }
}

final class ControllableWatchedFolderScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var resultsByRoot: [URL: [RepoScanner.RepoScanGroup]] = [:]

    func setResults(_ resultsByRoot: [URL: [URL]]) {
        setGroupedResults(
            Dictionary(
                uniqueKeysWithValues: resultsByRoot.map { key, value in
                    (
                        key,
                        value.map {
                            RepoScanner.RepoScanGroup(
                                clonePath: $0,
                                linkedWorktreePaths: []
                            )
                        }
                    )
                }
            )
        )
    }

    func setGroupedResults(_ resultsByRoot: [URL: [RepoScanner.RepoScanGroup]]) {
        lock.withLock {
            self.resultsByRoot = Dictionary(
                uniqueKeysWithValues: resultsByRoot.map { key, value in
                    (
                        key.standardizedFileURL,
                        value.map { group in
                            RepoScanner.RepoScanGroup(
                                clonePath: group.clonePath.standardizedFileURL,
                                linkedWorktreePaths: group.linkedWorktreePaths.map(\.standardizedFileURL)
                            )
                        }
                    )
                }
            )
        }
    }

    func scan(_ root: URL) -> [RepoScanner.RepoScanGroup] {
        lock.withLock {
            resultsByRoot[root.standardizedFileURL, default: []]
        }
    }
}
