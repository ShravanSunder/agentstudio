import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

actor VisibleTierCallRecorder {
    private var labels: [String] = []
    private var countObservers: [UUID: AsyncStream<Int>.Continuation] = [:]

    var count: Int { labels.count }
    var isEmpty: Bool { labels.isEmpty }

    func record(_ label: String) -> Int {
        labels.append(label)
        for observer in countObservers.values {
            observer.yield(labels.count)
        }
        return labels.count
    }

    func waitForCount(_ expectedCount: Int) async {
        guard labels.count < expectedCount else { return }
        let observerId = UUIDv7.generate()
        let updates = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(1))
        countObservers[observerId] = updates.continuation
        defer { countObservers.removeValue(forKey: observerId)?.finish() }
        await withTaskCancellationHandler {
            for await count in updates.stream where count >= expectedCount {
                return
            }
        } onCancel: {
            updates.continuation.finish()
        }
    }
}

actor VisibleTierStatusGate {
    private(set) var labels: [String] = []
    private var waiters: [String: AsyncStream<Void>.Continuation] = [:]
    private var labelObservers: [UUID: AsyncStream<[String]>.Continuation] = [:]
    private(set) var maximumInFlightCount = 0
    private var remainsOpen = false

    func recordAndWait(_ label: String) async {
        labels.append(label)
        for observer in labelObservers.values {
            observer.yield(labels)
        }
        guard !remainsOpen else { return }
        let release = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        waiters[label] = release.continuation
        maximumInFlightCount = max(maximumInFlightCount, waiters.count)
        await withTaskCancellationHandler {
            for await _ in release.stream {
                return
            }
        } onCancel: {
            release.continuation.finish()
        }
        waiters.removeValue(forKey: label)?.finish()
    }

    func releaseFirst(containing fragment: String) {
        guard let key = waiters.keys.sorted().first(where: { $0.contains(fragment) }) else { return }
        let continuation = waiters.removeValue(forKey: key)
        continuation?.yield(())
        continuation?.finish()
    }

    func releaseAll() {
        let continuations = waiters.values
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.yield(())
            continuation.finish()
        }
    }

    func releaseAllAndRemainOpen() {
        remainsOpen = true
        releaseAll()
    }

    func waitForLabelCount(_ expectedCount: Int) async {
        guard labels.count < expectedCount else { return }
        await waitForLabels { $0.count >= expectedCount }
    }

    func waitForLabel(containing fragment: String) async {
        guard !labels.contains(where: { $0.contains(fragment) }) else { return }
        await waitForLabels { labels in labels.contains(where: { $0.contains(fragment) }) }
    }

    private func waitForLabels(matching condition: @escaping @Sendable ([String]) -> Bool) async {
        guard !condition(labels) else { return }
        let observerId = UUIDv7.generate()
        let updates = AsyncStream.makeStream(of: [String].self, bufferingPolicy: .bufferingNewest(1))
        labelObservers[observerId] = updates.continuation
        defer { labelObservers.removeValue(forKey: observerId)?.finish() }
        await withTaskCancellationHandler {
            for await labels in updates.stream where condition(labels) {
                return
            }
        } onCancel: {
            updates.continuation.finish()
        }
    }
}

func withStartedVisibleTierProjector(
    _ projector: GitWorkingDirectoryProjector,
    gate: VisibleTierStatusGate? = nil,
    operation: () async throws -> Void
) async throws {
    await projector.start()
    do {
        try await operation()
        await gate?.releaseAllAndRemainOpen()
        await projector.shutdown()
    } catch {
        await gate?.releaseAllAndRemainOpen()
        await projector.shutdown()
        throw error
    }
}

func waitForVisibleTierStatusCompletion(
    _ projector: GitWorkingDirectoryProjector,
    worktreeId: UUID
) async {
    let statusTask = await projector.worktreeTasks[worktreeId]
    await statusTask?.value
}

func advanceVisibleDeadline(
    _ projector: GitWorkingDirectoryProjector,
    _ clock: TestPushClock,
    _ worktreeId: UUID,
    cadence: Duration,
    stoppingBeforeDeadlineBy: Duration = .zero
) async throws {
    let deadline = try #require(await projector.automaticRefreshDeadlineByWorktreeId[worktreeId])
    let lastStart = try #require(await projector.lastAutomaticStartAtByWorktreeId[worktreeId])
    #expect(deadline >= lastStart + cadence)
    let clockNow = await projector.deadlineClock.now
    clock.advance(by: max(.zero, deadline - clockNow - stoppingBeforeDeadlineBy))
}

func visibleTierWorktreeId(
    forBackgroundStripe targetStripe: Int,
    policy: AppPolicies.GitRefresh.Policy
) -> UUID {
    for candidateIndex in 0..<10_000 {
        let candidate = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", candidateIndex))!
        if policy.backgroundStripe(for: candidate) == targetStripe {
            return candidate
        }
    }
    preconditionFailure("Unable to find deterministic UUID for background stripe \(targetStripe)")
}

func visibleTierTopologyAssertion(
    generation: UInt64,
    rootPathsByWorktreeId: [UUID: URL]
) -> FilesystemTopologyAssertion {
    FilesystemTopologyAssertion(
        generation: generation,
        contextsByWorktreeId: Dictionary(
            uniqueKeysWithValues: rootPathsByWorktreeId.map { worktreeId, rootPath in
                (worktreeId, WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath))
            }
        )
    )
}

func visibleTierFilesChangedEnvelope(
    seq: UInt64,
    worktreeId: UUID,
    rootPath: URL,
    batchSeq: UInt64,
    paths: [String]? = nil,
    containsGitInternalChanges: Bool = false
) -> RuntimeEnvelope {
    .worktree(
        WorktreeEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            seq: seq,
            timestamp: ContinuousClock().now,
            repoId: worktreeId,
            worktreeId: worktreeId,
            event: .filesystem(
                .filesChanged(
                    changeset: FileChangeset(
                        worktreeId: worktreeId,
                        rootPath: rootPath,
                        paths: paths ?? ["tracked-\(batchSeq).txt"],
                        containsGitInternalChanges: containsGitInternalChanges,
                        timestamp: ContinuousClock().now,
                        batchSeq: batchSeq
                    )
                )
            )
        )
    )
}
