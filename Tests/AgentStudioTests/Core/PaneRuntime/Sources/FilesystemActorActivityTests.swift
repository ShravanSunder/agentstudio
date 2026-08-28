import AgentStudioInfrastructure
import AgentStudioTestSupport
import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("FilesystemActor repository activity", .serialized)
struct FilesystemActorActivityTests {
    @Test("shutdown commits accepted activity before retiring streams")
    func shutdownCommitsAcceptedActivityBeforeRetiringStreams() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "filesystem-activity-shutdown-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamClient = DarwinFSEventStreamClient()
        let activityCommitRecorder = FilesystemActivityCommitRecorder()
        let activityProjector = RepositoryLocalActivityProjector { commit in
            await activityCommitRecorder.record(commit)
        }
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: streamClient,
            repositoryLocalActivityProjector: activityProjector,
            sleepClock: clock,
            debounceWindow: .seconds(60),
            maxFlushLatency: .seconds(120)
        )
        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let repositoryStableKey = "1111111122222222"
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: fixtureRoot)
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: fixtureRoot)
                ],
                repositoryStableKeysByWorktreeId: [worktreeId: repositoryStableKey]
            )
        )
        let changedPath = DarwinFSEventPathCanonicalizer.canonicalURL(fixtureRoot)
            .appending(path: "Sources/Shutdown.swift").path
        streamClient.receiveLocalRawEvents(
            worktreeId: worktreeId,
            rawEvents: [
                (
                    path: changedPath,
                    eventId: 77,
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
                )
            ]
        )

        await actor.shutdown()

        let commits = await activityCommitRecorder.commits
        #expect(commits.count == 1)
        #expect(commits.first?.repositoryUpdates.first?.repositoryStableKey == repositoryStableKey)
        #expect(commits.first?.repositoryUpdates.first?.qualifyingActivityAt != nil)
        #expect(commits.first?.cursorWatermarks.first?.lastEventID == 77)
    }

    @Test("activity burst uses one existing filesystem drain checkpoint")
    func activityBurstUsesOneExistingFilesystemDrainCheckpoint() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "filesystem-activity-checkpoint-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamClient = DarwinFSEventStreamClient()
        let activityCommitRecorder = FilesystemActivityCommitRecorder()
        let activityProjector = RepositoryLocalActivityProjector { commit in
            await activityCommitRecorder.record(commit)
        }
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: streamClient,
            repositoryLocalActivityProjector: activityProjector,
            sleepClock: clock,
            debounceWindow: .seconds(1),
            maxFlushLatency: .seconds(10)
        )
        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let repositoryStableKey = "eeeeeeeeffffffff"
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: fixtureRoot)
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: fixtureRoot)
                ],
                repositoryStableKeysByWorktreeId: [worktreeId: repositoryStableKey]
            )
        )
        await clock.waitForPendingSleepCount()
        clock.advance(by: .seconds(1))
        #expect(await waitUntil { await activityCommitRecorder.commits.count == 1 })
        await activityCommitRecorder.reset()
        #expect(await waitUntil { await actor.drainTaskLogicalDebtCount == 0 })
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 2,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: fixtureRoot)
                ],
                repositoryStableKeysByWorktreeId: [worktreeId: repositoryStableKey]
            )
        )
        #expect(await actor.drainTaskLogicalDebtCount == 0)
        #expect(clock.pendingSleepCount == 0)

        let canonicalRoot = DarwinFSEventPathCanonicalizer.canonicalURL(fixtureRoot)
        for eventID in 41...43 {
            streamClient.receiveLocalRawEvents(
                worktreeId: worktreeId,
                rawEvents: [
                    (
                        path: canonicalRoot.appending(path: "Sources/File\(eventID).swift").path,
                        eventId: FSEventStreamEventId(eventID),
                        flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
                    )
                ]
            )
        }

        await clock.waitForPendingSleepCount()
        clock.advance(by: .seconds(1))
        let burstCommitted = await waitUntil {
            await activityCommitRecorder.commits.count == 1
        }
        #expect(burstCommitted)
        let commits = await activityCommitRecorder.commits
        #expect(commits.count == 1)
        #expect(commits.first?.repositoryUpdates.first?.qualifyingActivityAt != nil)
        await actor.shutdown()
    }

    @Test("activity fence consumes retained activity loss before acknowledgement")
    func activityFenceConsumesRetainedActivityLossBeforeAcknowledgement() async throws {
        let streamClient = ControllableFSEventStreamClient()
        let activityCommitRecorder = FilesystemActivityCommitRecorder()
        let activityProjector = RepositoryLocalActivityProjector { commit in
            await activityCommitRecorder.record(commit)
        }
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: streamClient,
            repositoryLocalActivityProjector: activityProjector,
            sleepClock: TestPushClock(),
            debounceWindow: .seconds(60),
            maxFlushLatency: .seconds(120)
        )
        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let repositoryStableKey = "aaaaaaaabbbbbbbb"
        let participant = FSEventParticipant(
            scopeKey: "local-\(worktreeId.uuidString)",
            generation: 1,
            volumeIdentifier: "volume-1"
        )
        await actor.register(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: URL(filePath: "/tmp/activity-overflow-\(worktreeId.uuidString)")
        )
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(
                        repoId: repoId,
                        rootPath: URL(filePath: "/tmp/activity-overflow-\(worktreeId.uuidString)")
                    )
                ],
                repositoryStableKeysByWorktreeId: [worktreeId: repositoryStableKey]
            )
        )
        await activityProjector.replaceParticipants(
            [
                RepositoryLocalActivityParticipant(
                    scopeKey: participant.scopeKey,
                    generation: participant.generation,
                    volumeIdentifier: participant.volumeIdentifier,
                    repositoryStableKeys: [repositoryStableKey]
                )
            ],
            coverageRestartedAt: Date(timeIntervalSince1970: 100)
        )
        let fenceID = FSEventActivityProcessingFenceID(rawValue: 1)
        streamClient.sendActivityOverflowRecovery(
            participant: participant,
            processedThroughEventID: 42,
            coverageLostWorktreeIds: [worktreeId]
        )

        streamClient.sendActivityProcessingFence(fenceID)

        let fenceWasAcknowledged = await waitUntil {
            streamClient.acknowledgedActivityProcessingFenceIDs.contains(fenceID)
        }
        #expect(fenceWasAcknowledged)
        let didCommit = try await activityProjector.commitBarrier(
            RepositoryLocalActivityBarrier(
                deliveredEventIDByParticipant: [
                    RepositoryLocalActivityParticipantIdentity(
                        scopeKey: participant.scopeKey,
                        generation: participant.generation
                    ): 42
                ],
                completedAt: Date(timeIntervalSince1970: 120)
            )
        )
        #expect(didCommit)
        let commit = try #require(await activityCommitRecorder.commits.first)
        guard case .restart = commit.repositoryUpdates.first?.coverageChange else {
            Issue.record("activity loss was not projected before fence acknowledgement")
            await actor.shutdown()
            return
        }
        await actor.shutdown()
    }

    @Test("activity barrier waits for FilesystemActor ingress acknowledgement")
    func activityBarrierWaitsForFilesystemActorIngressAcknowledgement() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "filesystem-activity-fence-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamClient = DarwinFSEventStreamClient()
        let activityCommitRecorder = FilesystemActivityCommitRecorder()
        let activityProjector = RepositoryLocalActivityProjector { commit in
            await activityCommitRecorder.record(commit)
        }
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: streamClient,
            repositoryLocalActivityProjector: activityProjector,
            sleepClock: TestPushClock(),
            debounceWindow: .seconds(60),
            maxFlushLatency: .seconds(120)
        )
        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let repositoryStableKey = "ccccccccdddddddd"
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: fixtureRoot)
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: fixtureRoot)
                ],
                repositoryStableKeysByWorktreeId: [worktreeId: repositoryStableKey]
            )
        )
        streamClient.receiveLocalRawEvents(
            worktreeId: worktreeId,
            rawEvents: [
                (
                    path: DarwinFSEventPathCanonicalizer.canonicalURL(fixtureRoot)
                        .appending(path: "Sources/Changed.swift").path,
                    eventId: 42,
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
                )
            ]
        )

        let barrier = try #require(await streamClient.captureActivityBarrier())

        let participant = try #require(
            barrier.bindings.first(where: { $0.worktreeId == worktreeId })?.participant
        )
        #expect(barrier.deliveredEventIDByParticipant[participant] ?? 0 >= 42)
        await activityProjector.replaceParticipants(
            [
                RepositoryLocalActivityParticipant(
                    scopeKey: participant.scopeKey,
                    generation: participant.generation,
                    volumeIdentifier: participant.volumeIdentifier,
                    repositoryStableKeys: [repositoryStableKey]
                )
            ],
            coverageRestartedAt: Date(timeIntervalSince1970: 100)
        )
        let didCommit = try await activityProjector.commitBarrier(
            RepositoryLocalActivityBarrier(
                deliveredEventIDByParticipant: [
                    RepositoryLocalActivityParticipantIdentity(
                        scopeKey: participant.scopeKey,
                        generation: participant.generation
                    ): barrier.deliveredEventIDByParticipant[participant] ?? 0
                ],
                completedAt: Date(timeIntervalSince1970: 120)
            )
        )
        #expect(didCommit)
        let commit = try #require(await activityCommitRecorder.commits.first)
        #expect(commit.repositoryUpdates.first?.qualifyingActivityAt != nil)
        #expect(commit.repositoryUpdates.first?.repositoryStableKey == repositoryStableKey)
        await actor.shutdown()
    }

    private func waitUntil(
        maxTurns: Int = 10_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }
}

private actor FilesystemActivityCommitRecorder {
    private(set) var commits: [RepositoryLocalActivityCommit] = []

    func record(_ commit: RepositoryLocalActivityCommit) {
        commits.append(commit)
    }

    func reset() {
        commits.removeAll(keepingCapacity: true)
    }
}
