import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge Git read scheduler and construction capacity integration")
struct BridgeCapacityIntegrationTests {
    // Keep this as one continuous Arrange/Act/Assert journey: splitting the orchestration
    // would obscure the cross-subsystem capacity and final-residue assertions.
    @Test("multi-worktree admission and shared Review construction drain exactly")
    // swiftlint:disable:next function_body_length
    func multiWorktreeAdmissionAndSharedReviewConstructionDrainExactly() async throws {
        // Arrange
        let fixture = try BridgeCapacityIntegrationGitFixture.make()
        defer { fixture.destroy() }
        let worktreeKeys = fixture.worktreeURLs.map {
            BridgeGitReadWorktreeKey(token: $0.standardizedFileURL.path)
        }
        let deadlineScheduler = BridgeGitReadManualDeadlineScheduler()
        let schedulerEventProbe = BridgeGitReadSchedulerEventProbe()
        let scheduler = BridgeGitReadScheduler(
            topology: makeBridgeGitReadSchedulerTopology(
                metadataSlotCount: 1,
                contentSlotCount: 1,
                maximumQueuedOperationCountPerClass: 8
            ),
            deadlineScheduler: deadlineScheduler,
            eventSink: schedulerEventProbe.eventSink
        )
        for (index, worktreeKey) in worktreeKeys.enumerated() {
            await scheduler.updatePaneActivity(
                paneKey: BridgeGitReadPaneKey(token: "hidden-pane-\(index)"),
                worktreeKey: worktreeKey,
                rank: .loadedHidden
            )
        }
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "foreground-pane-a"),
            worktreeKey: worktreeKeys[0],
            rank: .foreground
        )
        await scheduler.updatePaneActivity(
            paneKey: BridgeGitReadPaneKey(token: "foreground-pane-b"),
            worktreeKey: worktreeKeys[0],
            rank: .foreground
        )

        let heldMetadataGate = BridgeGitReadOperationGate(returnValue: "held-metadata")
        let heldMetadataRead = Task {
            try await scheduler.read(
                request: makeCapacityIntegrationReadRequest(
                    worktreeKey: worktreeKeys[0],
                    key: "held-metadata"
                )
            ) {
                await heldMetadataGate.run()
            }
        }
        await heldMetadataGate.waitUntilStarted()
        _ = await schedulerEventProbe.waitFor(.started)
        #expect(deadlineScheduler.fireNextActiveDeadline())
        _ = await schedulerEventProbe.waitFor(.draining)
        assertCapacityIntegrationTimedOut(await heldMetadataRead.result)

        let queuedMetadata = await makeQueuedMetadataReads(
            scheduler: scheduler,
            eventProbe: schedulerEventProbe,
            worktreeKeys: worktreeKeys
        )

        // Act
        let blockedMetadataSnapshot = await scheduler.snapshot()
        let blockedMetadataInvocationCounts = await queuedMetadata.allGates.asyncMap { gate in
            await gate.recordedInvocationCount()
        }
        let selectedContentGate = BridgeGitReadOperationGate(returnValue: "selected-content")
        let selectedContentRead = Task {
            try await scheduler.read(
                request: makeCapacityIntegrationReadRequest(
                    worktreeKey: worktreeKeys[0],
                    operationClass: .selectedVisibleContent,
                    key: "selected-content"
                )
            ) {
                await selectedContentGate.run()
            }
        }
        await selectedContentGate.waitUntilStarted()
        let peakSchedulerSnapshot = await scheduler.snapshot()
        let mainActorHeartbeat = await Task { @MainActor in
            for _ in 0..<32 {
                await Task.yield()
            }
            return 32
        }.value
        await selectedContentGate.release()
        let selectedContent = try await selectedContentRead.value

        await heldMetadataGate.release()
        let selectedMetadataStart = await schedulerEventProbe.waitFor(.started, occurrence: 3)
        await queuedMetadata.selectedForegroundGate.release()
        let firstHiddenStart = await schedulerEventProbe.waitFor(.started, occurrence: 4)
        await queuedMetadata.firstHiddenWorktreeGate.release()
        let fairPeerStart = await schedulerEventProbe.waitFor(.started, occurrence: 5)
        for gate in queuedMetadata.allGates {
            await gate.release()
        }
        let queuedResults = try await queuedMetadata.tasks.asyncMap { task in
            try await task.value
        }
        _ = await schedulerEventProbe.waitFor(.slotReleased, occurrence: 10)
        await scheduler.shutdown()
        let closedSchedulerSnapshot = await scheduler.snapshot()

        let constructionEventProbe = BridgeWorktreeProductConstructionEventProbe()
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator(
            eventSink: constructionEventProbe.eventSink
        )
        let backgroundOwner = makeBridgeConstructionOwner(
            repo: fixture.repositoryURLs[4].standardizedFileURL.path,
            worktree: fixture.worktreeURLs[4].standardizedFileURL.path,
            root: fixture.repositoryURLs[4].standardizedFileURL.path,
            provider: "capacity-integration-provider"
        )
        let duplicateReviewKey = makeBridgeReviewConstructionKey(owner: backgroundOwner)
        let distinctReviewKey = makeBridgeReviewConstructionKey(
            owner: backgroundOwner,
            pathScope: ["Tests"]
        )
        let duplicateGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact()
        )
        let distinctGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact()
        )
        let oldDuplicateA = Task {
            try await constructionCoordinator.acquire(
                key: duplicateReviewKey,
                build: duplicateGate.run
            )
        }
        let oldDuplicateB = Task {
            try await constructionCoordinator.acquire(
                key: duplicateReviewKey,
                build: duplicateGate.run
            )
        }
        let oldDistinct = Task {
            try await constructionCoordinator.acquire(
                key: distinctReviewKey,
                build: distinctGate.run
            )
        }
        await duplicateGate.waitUntilStarted()
        await distinctGate.waitUntilStarted()
        _ = await constructionEventProbe.waitFor(.consumerJoined)
        let firstConstructionPeak = await constructionCoordinator.snapshot()

        _ = await constructionCoordinator.invalidate(worktree: duplicateReviewKey.worktree)
        _ = await constructionCoordinator.invalidate(worktree: duplicateReviewKey.worktree)
        _ = await constructionCoordinator.invalidate(worktree: duplicateReviewKey.worktree)
        assertCapacityIntegrationInvalidated(await oldDuplicateA.result)
        assertCapacityIntegrationInvalidated(await oldDuplicateB.result)
        assertCapacityIntegrationInvalidated(await oldDistinct.result)
        let invalidatedConstructionSnapshot = await constructionCoordinator.snapshot()

        let currentDuplicateA = Task {
            try await constructionCoordinator.acquire(
                key: duplicateReviewKey,
                build: duplicateGate.run
            )
        }
        let currentDuplicateB = Task {
            try await constructionCoordinator.acquire(
                key: duplicateReviewKey,
                build: duplicateGate.run
            )
        }
        let currentDistinct = Task {
            try await constructionCoordinator.acquire(
                key: distinctReviewKey,
                build: distinctGate.run
            )
        }
        await duplicateGate.waitUntilStarted(count: 2)
        await distinctGate.waitUntilStarted(count: 2)
        _ = await constructionEventProbe.waitFor(.consumerJoined, occurrence: 2)
        let rebuildingConstructionPeak = await constructionCoordinator.snapshot()

        await duplicateGate.release(invocation: 1)
        await distinctGate.release(invocation: 1)
        _ = await constructionEventProbe.waitFor(.staleCompletionDropped, occurrence: 2)
        await duplicateGate.release(invocation: 2)
        await distinctGate.release(invocation: 2)
        let duplicateLeaseA = try await currentDuplicateA.value
        let duplicateLeaseB = try await currentDuplicateB.value
        let distinctLease = try await currentDistinct.value
        let readyConstructionSnapshot = await constructionCoordinator.snapshot()

        // Assert
        #expect(blockedMetadataSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(blockedMetadataSnapshot.queuedCountByOperationClass[.reviewMetadata] == 8)
        #expect(blockedMetadataSnapshot.occupiedSlotIds.count == 1)
        #expect(blockedMetadataInvocationCounts.allSatisfy { $0 == 0 })
        #expect(peakSchedulerSnapshot.drainingCountByOperationClass[.reviewMetadata] == 1)
        #expect(peakSchedulerSnapshot.queuedCountByOperationClass[.reviewMetadata] == 8)
        #expect(peakSchedulerSnapshot.runningCountByOperationClass[.selectedVisibleContent] == 1)
        #expect(peakSchedulerSnapshot.occupiedSlotIds.count == 2)
        #expect(peakSchedulerSnapshot.activeOperationIds.count == 10)
        #expect(peakSchedulerSnapshot.admittedWorktreeKeys == Set(worktreeKeys))
        #expect(mainActorHeartbeat == 32)
        #expect(selectedContent == "selected-content")
        #expect(selectedMetadataStart.worktreeKey == worktreeKeys[0])
        #expect(firstHiddenStart.worktreeKey == worktreeKeys[1])
        #expect(fairPeerStart.worktreeKey == worktreeKeys[2])
        #expect(queuedResults.count == 8)
        #expect(Set(queuedResults).count == 8)
        assertCapacityIntegrationSchedulerClosedAndEmpty(closedSchedulerSnapshot)

        #expect(firstConstructionPeak.entryCount == 2)
        #expect(firstConstructionPeak.waiterCount == 3)
        #expect(firstConstructionPeak.inFlightCount == 2)
        #expect(invalidatedConstructionSnapshot.entryCount == 2)
        #expect(invalidatedConstructionSnapshot.waiterCount == 0)
        #expect(invalidatedConstructionSnapshot.inFlightCount == 2)
        #expect(invalidatedConstructionSnapshot.drainingTombstoneCount == 2)
        #expect(rebuildingConstructionPeak.entryCount == 4)
        #expect(rebuildingConstructionPeak.waiterCount == 3)
        #expect(rebuildingConstructionPeak.inFlightCount == 4)
        #expect(rebuildingConstructionPeak.drainingTombstoneCount == 2)
        #expect(duplicateLeaseA.entryNonce == duplicateLeaseB.entryNonce)
        #expect(duplicateLeaseA.leaseNonce != duplicateLeaseB.leaseNonce)
        #expect(distinctLease.entryNonce != duplicateLeaseA.entryNonce)
        #expect(await duplicateGate.recordedInvocationCount() == 2)
        #expect(await distinctGate.recordedInvocationCount() == 2)
        #expect(readyConstructionSnapshot.entryCount == 2)
        #expect(readyConstructionSnapshot.waiterCount == 0)
        #expect(readyConstructionSnapshot.leaseCount == 3)
        #expect(readyConstructionSnapshot.payloadCount == 2)
        #expect(readyConstructionSnapshot.inFlightCount == 0)
        #expect(readyConstructionSnapshot.drainingTombstoneCount == 0)
        #expect(readyConstructionSnapshot.retainedArtifactByteCount == 256)

        await constructionCoordinator.release(duplicateLeaseA)
        await constructionCoordinator.release(duplicateLeaseB)
        await constructionCoordinator.release(distinctLease)
        await assertBridgeConstructionCoordinatorDrained(constructionCoordinator)
        await constructionCoordinator.shutdown()
        await assertBridgeConstructionCoordinatorDrained(constructionCoordinator)
    }
}

private struct BridgeCapacityIntegrationQueuedMetadata {
    let tasks: [Task<String, any Error>]
    let selectedForegroundGate: BridgeGitReadOperationGate<String>
    let firstHiddenWorktreeGate: BridgeGitReadOperationGate<String>
    let allGates: [BridgeGitReadOperationGate<String>]
}

private struct BridgeCapacityIntegrationGitFixture {
    let repositoryURLs: [URL]
    let linkedWorktreeURLs: [URL]

    var worktreeURLs: [URL] {
        repositoryURLs + linkedWorktreeURLs
    }

    static func make() throws -> Self {
        var repositoryURLs: [URL] = []
        var linkedWorktreeURLs: [URL] = []
        do {
            for repositoryIndex in 0..<5 {
                let repositoryURL = try FilesystemTestGitRepo.create(
                    named: "bridge-capacity-repo-\(repositoryIndex)"
                )
                repositoryURLs.append(repositoryURL)
                try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
            }
            for repositoryIndex in 0..<2 {
                let linkedWorktreeURL = repositoryURLs[repositoryIndex]
                    .deletingLastPathComponent()
                    .appending(path: "bridge-capacity-linked-\(UUID().uuidString)")
                try FilesystemTestGitRepo.runGit(
                    at: repositoryURLs[repositoryIndex],
                    args: [
                        "worktree", "add", "-b", "capacity-linked-\(UUID().uuidString)",
                        linkedWorktreeURL.path,
                    ]
                )
                linkedWorktreeURLs.append(linkedWorktreeURL)
            }
            return Self(
                repositoryURLs: repositoryURLs,
                linkedWorktreeURLs: linkedWorktreeURLs
            )
        } catch {
            destroy(
                repositoryURLs: repositoryURLs,
                linkedWorktreeURLs: linkedWorktreeURLs
            )
            throw error
        }
    }

    func destroy() {
        Self.destroy(
            repositoryURLs: repositoryURLs,
            linkedWorktreeURLs: linkedWorktreeURLs
        )
    }

    private static func destroy(
        repositoryURLs: [URL],
        linkedWorktreeURLs: [URL]
    ) {
        for (repositoryURL, linkedWorktreeURL) in zip(repositoryURLs, linkedWorktreeURLs) {
            _ = try? FilesystemTestGitRepo.runGit(
                at: repositoryURL,
                args: ["worktree", "remove", "--force", linkedWorktreeURL.path]
            )
            FilesystemTestGitRepo.destroy(linkedWorktreeURL)
        }
        for repositoryURL in repositoryURLs {
            FilesystemTestGitRepo.destroy(repositoryURL)
        }
    }
}

private func makeQueuedMetadataReads(
    scheduler: BridgeGitReadScheduler,
    eventProbe: BridgeGitReadSchedulerEventProbe,
    worktreeKeys: [BridgeGitReadWorktreeKey]
) async -> BridgeCapacityIntegrationQueuedMetadata {
    let specifications: [(worktreeIndex: Int, key: String)] = [
        (1, "hidden-one-a"),
        (1, "hidden-one-b"),
        (2, "hidden-two"),
        (3, "hidden-three"),
        (4, "hidden-four"),
        (5, "linked-zero"),
        (6, "linked-one"),
        (0, "selected-foreground"),
    ]
    let gates = specifications.map {
        BridgeGitReadOperationGate(returnValue: $0.key)
    }
    var tasks: [Task<String, any Error>] = []
    for (index, pair) in zip(specifications, gates).enumerated() {
        let task = Task {
            try await scheduler.read(
                request: makeCapacityIntegrationReadRequest(
                    worktreeKey: worktreeKeys[pair.0.worktreeIndex],
                    key: pair.0.key
                )
            ) {
                await pair.1.run()
            }
        }
        tasks.append(task)
        _ = await eventProbe.waitFor(.queued, occurrence: index + 2)
    }
    return BridgeCapacityIntegrationQueuedMetadata(
        tasks: tasks,
        selectedForegroundGate: gates[7],
        firstHiddenWorktreeGate: gates[0],
        allGates: gates
    )
}

private func makeCapacityIntegrationReadRequest(
    worktreeKey: BridgeGitReadWorktreeKey,
    operationClass: BridgeGitReadOperationClass = .reviewMetadata,
    key: String
) -> BridgeGitReadRequest {
    BridgeGitReadRequest(
        worktreeKey: worktreeKey,
        operationClass: operationClass,
        coalescingKey: BridgeGitReadCoalescingKey(token: key),
        freshnessKey: .unversioned,
        deadline: .seconds(30)
    )
}

private func assertCapacityIntegrationTimedOut<ReturnValue>(
    _ result: Result<ReturnValue, Error>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .failure(let error) = result else {
        Issue.record("Expected a logical timeout", sourceLocation: sourceLocation)
        return
    }
    #expect(
        error as? BridgeGitReadSchedulerError == .timedOut,
        sourceLocation: sourceLocation
    )
}

private func assertCapacityIntegrationInvalidated<ReturnValue>(
    _ result: Result<ReturnValue, Error>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .failure(let error) = result else {
        Issue.record("Expected construction invalidation", sourceLocation: sourceLocation)
        return
    }
    #expect(
        error as? BridgeWorktreeProductConstructionError == .invalidated,
        sourceLocation: sourceLocation
    )
}

private func assertCapacityIntegrationSchedulerClosedAndEmpty(
    _ snapshot: BridgeGitReadSchedulerSnapshot,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(snapshot.lifecycle == .closed, sourceLocation: sourceLocation)
    #expect(snapshot.queuedCountByOperationClass.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.runningCountByOperationClass.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.drainingCountByOperationClass.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.activeOperationIds.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.occupiedSlotIds.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.logicalWaiterCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.scheduledDeadlineCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.admittedWorktreeKeys.isEmpty, sourceLocation: sourceLocation)
    #expect(snapshot.paneActivityCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.fairnessHistoryCount == 0, sourceLocation: sourceLocation)
}

extension Array {
    fileprivate func asyncMap<Transformed>(
        _ transform: (Element) async throws -> Transformed
    ) async rethrows -> [Transformed] {
        var transformed: [Transformed] = []
        transformed.reserveCapacity(count)
        for element in self {
            transformed.append(try await transform(element))
        }
        return transformed
    }
}
