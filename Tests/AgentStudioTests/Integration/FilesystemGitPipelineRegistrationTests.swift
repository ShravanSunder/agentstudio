import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

/// End-to-end proof for both membership ingress paths through `FilesystemGitPipeline`.
/// Direct candidate registration validates certain non-repository evidence; canonical topology
/// assertions reconcile their complete owner-supplied membership without becoming a second
/// discovery authority. See `GitWorktreeRegistrationValidatorTests` for validator unit coverage.
@MainActor
@Suite(.serialized)
struct FilesystemGitPipelineRegistrationTests {
    @Test(
        "registration still occurs when the probe cannot certainly confirm the repository",
        arguments: [
            GitRepositoryDiscoveryOutcome.timeout,
            .cancelled,
            .failure(.serviceFailed(detail: "boom")),
            .authoritativeNegative(.canonicalPathMismatch),
            .authoritativeNegative(.mainWorktreeMismatch),
            .authoritativeNegative(.submoduleWorktree),
        ]
    )
    func registrationOccursForNonCertainProbeOutcomes(
        outcome: GitRepositoryDiscoveryOutcome
    ) async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            registrationDiscoveryProvider: FixedOutcomeRegistrationDiscoveryProvider(outcome: outcome),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-non-certain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        let observed = ObservedRegistrationEvents()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let consumerTask = Task { @MainActor in
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)

        await pipeline.register(worktreeId: worktreeId, repoId: UUID(), rootPath: rootPath)

        let registered = await eventually(
            "filesystem actor should register despite a non-certain probe outcome"
        ) {
            await observed.isRegistered(worktreeId)
        }
        #expect(registered)

        await shutdownWorld(pipeline: pipeline, observerTasks: [consumerTask], bus: bus)
    }

    @Test(
        "certain non-repository evidence still rejects and never registers the worktree",
        arguments: [
            GitRepositoryAuthoritativeNegativeReason.exactCandidateIsNotRepository,
            .invalidRepository,
            .invalidWorktreeRegistration,
            .bareRepository,
        ]
    )
    func certainNonRepositoryEvidenceStillRejectsRegistration(
        reason: GitRepositoryAuthoritativeNegativeReason
    ) async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            registrationDiscoveryProvider: FixedOutcomeRegistrationDiscoveryProvider(
                outcome: .authoritativeNegative(reason)
            ),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-certain-reject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        let observed = ObservedRegistrationEvents()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let consumerTask = Task { @MainActor in
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)

        await pipeline.register(worktreeId: worktreeId, repoId: UUID(), rootPath: rootPath)

        let neverRegistered = await neverArrives(
            "filesystem actor should not register a certain non-repository path"
        ) {
            await observed.isRegistered(worktreeId)
        }
        #expect(neverRegistered)

        await shutdownWorld(pipeline: pipeline, observerTasks: [consumerTask], bus: bus)
    }

    @Test("canonical topology assertion registers the complete fleet without secondary discovery")
    func canonicalTopologyAssertionRegistersCompleteFleetWithoutSecondaryDiscovery() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let discoveryProvider = RecordingRegistrationDiscoveryProvider(
            outcome: .authoritativeNegative(.invalidRepository)
        )
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            registrationDiscoveryProvider: discoveryProvider,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero
        )
        await pipeline.start()

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-mass-registration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        var contextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:]
        for index in 0..<146 {
            let worktreeId = UUID()
            let worktreeRoot = fixtureRoot.appending(path: "worktree-\(index)")
            try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
            contextsByWorktreeId[worktreeId] = WorktreeFilesystemContext(
                repoId: UUID(),
                rootPath: worktreeRoot
            )
        }

        let observed = ObservedRegistrationEvents()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let consumerTask = Task { @MainActor in
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)

        await pipeline.assertTopology(
            FilesystemTopologyAssertion(generation: 1, contextsByWorktreeId: contextsByWorktreeId)
        )

        for worktreeId in contextsByWorktreeId.keys {
            let registered = await eventually("canonical topology worktree should remain registered") {
                await observed.isRegistered(worktreeId)
            }
            #expect(registered)
        }
        #expect(await discoveryProvider.callCount == 0)

        await shutdownWorld(pipeline: pipeline, observerTasks: [consumerTask], bus: bus)
    }

    private func eventually(
        _ description: String,
        maxTurns: Int = 50_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        Issue.record("\(description) timed out")
        return false
    }

    /// Proves a negative over a bounded scheduling window: scans for `maxTurns` yields and
    /// returns `true` only if `condition` never became true. This is a bounded scan of actual
    /// scheduler turns, not a wall-clock sleep — it never blocks on real time.
    private func neverArrives(
        _ description: String,
        maxTurns: Int = 2000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                Issue.record("\(description), but it arrived")
                return false
            }
            await Task.yield()
        }
        return true
    }

    private func waitForSubscriberCount(
        bus: EventBus<RuntimeEnvelope>,
        atLeast expectedCount: Int,
        maxTurns: Int = 2000
    ) async {
        let subscribed = await eventually("bus subscriber count should reach \(expectedCount)", maxTurns: maxTurns) {
            await bus.subscriberCount >= expectedCount
        }
        #expect(subscribed)
    }

    private func shutdownWorld(
        pipeline: FilesystemGitPipeline,
        observerTasks: [Task<Void, Never>],
        bus: EventBus<RuntimeEnvelope>
    ) async {
        await pipeline.shutdown()
        for observerTask in observerTasks {
            observerTask.cancel()
            await observerTask.value
        }
        let busDrained = await eventually("integration test world should leave no subscribers behind") {
            await bus.subscriberCount == 0
        }
        #expect(busDrained)
    }
}

/// Tracks only the `worktreeRegistered` topology fact `FilesystemActor.register` emits, which is
/// the direct, unambiguous signal that a worktree crossed the registration boundary.
private actor ObservedRegistrationEvents {
    private var registeredWorktreeIds: Set<UUID> = []

    func record(_ envelope: RuntimeEnvelope) {
        guard case .system(let systemEnvelope) = envelope,
            case .topology(.worktreeRegistered(let worktreeId, _, _)) = systemEnvelope.event
        else {
            return
        }
        registeredWorktreeIds.insert(worktreeId)
    }

    func isRegistered(_ worktreeId: UUID) -> Bool {
        registeredWorktreeIds.contains(worktreeId)
    }
}

/// Returns a fixed discovery outcome for every candidate path, used to exercise the
/// `GitWorktreeRegistrationValidator` accept/reject boundary through the full pipeline.
private struct FixedOutcomeRegistrationDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    let outcome: GitRepositoryDiscoveryOutcome

    func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome {
        outcome
    }
}

private actor RecordingRegistrationDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    let outcome: GitRepositoryDiscoveryOutcome
    private(set) var callCount = 0

    init(outcome: GitRepositoryDiscoveryOutcome) {
        self.outcome = outcome
    }

    func discoveryOutcome(for _: URL) async -> GitRepositoryDiscoveryOutcome {
        callCount += 1
        return outcome
    }
}

private final class SilentFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let stream: AsyncStream<FSEventIngressItem>
    private let continuation: AsyncStream<FSEventIngressItem>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: FSEventIngressItem.self)
        self.stream = stream
        self.continuation = continuation
    }

    func events() -> AsyncStream<FSEventIngressItem> {
        stream
    }

    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] {
        []
    }

    func register(worktreeId _: UUID, repoId _: UUID, rootPath _: URL) {}

    func unregister(worktreeId _: UUID) {}

    func shutdown() {
        continuation.finish()
    }
}
