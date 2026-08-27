import AgentStudioGit
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("GitWorkingDirectoryProjector exact-clean continuity")
struct GitWorkingDirectoryProjectorContinuityTests {
    @Test("verified clean checkpoint renews without facts or detail reads")
    func verifiedCleanCheckpointRenewsWithoutPhysicalReads() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let provider = VerifiedCleanProjectorProvider(initialOutcome: .clean)
        let actor = makeProjector(bus: bus, clock: clock, provider: provider)
        await actor.start()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/verified-clean-\(worktreeId.uuidString)")
        await actor.setActivePaneWorktree(worktreeId: worktreeId)
        await bus.post(registrationEnvelope(sequence: 1, worktreeId: worktreeId, rootPath: rootPath))
        #expect(
            await eventually {
                guard provider.exactFactsReadCount == 1 else { return false }
                return await actor.lastAcceptedStatusAtByWorktreeId[worktreeId] != nil
            }
        )
        #expect(provider.detailReadCount == 0)

        clock.advance(by: .seconds(1))
        #expect(await eventually { provider.renewalCount == 1 })

        #expect(provider.exactFactsReadCount == 1)
        #expect(provider.ordinaryFactsReadCount == 0)
        #expect(provider.detailReadCount == 0)
        #expect(await actor.pendingByWorktreeId[worktreeId] == nil)
        await actor.shutdown()
    }

    @Test("raced clean barrier triggers exactly one ordinary full fallback")
    func racedCleanBarrierTriggersOneFallback() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let provider = VerifiedCleanProjectorProvider(initialOutcome: .requiresExact)
        let actor = makeProjector(bus: bus, clock: clock, provider: provider)
        await actor.start()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/verified-clean-race-\(worktreeId.uuidString)")
        await actor.setActivePaneWorktree(worktreeId: worktreeId)
        await bus.post(registrationEnvelope(sequence: 1, worktreeId: worktreeId, rootPath: rootPath))

        #expect(
            await eventually {
                guard provider.ordinaryFactsReadCount == 1 else { return false }
                return await actor.lastAcceptedStatusAtByWorktreeId[worktreeId] != nil
            }
        )
        #expect(provider.exactFactsReadCount == 1)
        #expect(provider.ordinaryFactsReadCount == 1)
        #expect(provider.detailReadCount == 1)
        await actor.shutdown()
    }

    @Test("unregistration while renewal is suspended creates no fallback debt")
    func unregistrationDuringRenewalCreatesNoFallbackDebt() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let renewalGate = RenewalGate()
        let provider = VerifiedCleanProjectorProvider(
            initialOutcome: .clean,
            renewalGate: renewalGate
        )
        let actor = makeProjector(bus: bus, clock: clock, provider: provider)
        await actor.start()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/verified-clean-remove-\(worktreeId.uuidString)")
        await actor.setActivePaneWorktree(worktreeId: worktreeId)
        await bus.post(registrationEnvelope(sequence: 1, worktreeId: worktreeId, rootPath: rootPath))
        #expect(
            await eventually {
                guard provider.exactFactsReadCount == 1 else { return false }
                let authority = await actor.exactCleanAuthorityByWorktreeId[worktreeId]
                let deadline = await actor.automaticRefreshDeadlineByWorktreeId[worktreeId]
                return authority != nil && deadline != nil
            }
        )

        clock.advance(by: .seconds(1))
        await renewalGate.waitUntilStarted()
        await bus.post(unregistrationEnvelope(sequence: 2, worktreeId: worktreeId))
        await renewalGate.release()

        #expect(await eventually { await actor.rootPathByWorktreeId[worktreeId] == nil })
        #expect(provider.exactFactsReadCount == 1)
        #expect(provider.ordinaryFactsReadCount == 0)
        #expect(await actor.pendingByWorktreeId[worktreeId] == nil)
        #expect(await actor.automaticRefreshDeadlineByWorktreeId[worktreeId] == nil)
        await actor.shutdown()
    }

    @Test("renewal uncertainty triggers one exact fallback and restores authority")
    func renewalUncertaintyTriggersOneFallback() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let provider = VerifiedCleanProjectorProvider(
            initialOutcome: .clean,
            renewalOutcome: .requiresExact
        )
        let actor = makeProjector(bus: bus, clock: clock, provider: provider)
        await actor.start()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/verified-clean-uncertain-\(worktreeId.uuidString)")
        await actor.setActivePaneWorktree(worktreeId: worktreeId)
        await bus.post(registrationEnvelope(sequence: 1, worktreeId: worktreeId, rootPath: rootPath))
        #expect(
            await eventually {
                guard provider.exactFactsReadCount == 1 else { return false }
                let authority = await actor.exactCleanAuthorityByWorktreeId[worktreeId]
                let deadline = await actor.automaticRefreshDeadlineByWorktreeId[worktreeId]
                return authority != nil && deadline != nil
            }
        )

        clock.advance(by: .seconds(1))
        #expect(
            await eventually {
                provider.renewalCount == 1
                    && provider.exactFactsReadCount == 2
            }
        )

        #expect(provider.exactFactsReadCount == 2)
        #expect(provider.ordinaryFactsReadCount == 0)
        #expect(provider.detailReadCount == 0)
        #expect(await actor.exactCleanAuthorityByWorktreeId[worktreeId] != nil)
        #expect(await actor.pendingByWorktreeId[worktreeId] == nil)
        await actor.shutdown()
    }

    private func makeProjector(
        bus: EventBus<RuntimeEnvelope>,
        clock: TestPushClock,
        provider: VerifiedCleanProjectorProvider
    ) -> GitWorkingDirectoryProjector {
        GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: AppPolicies.GitRefresh.Policy(
                activePaneCadence: .seconds(1),
                visibleSidebarCadence: .seconds(2),
                openPaneCadence: .seconds(3),
                backgroundCadence: .seconds(4),
                lineDetailFreshnessInterval: .seconds(1)
            )
        )
    }

    private func registrationEnvelope(
        sequence: UInt64,
        worktreeId: UUID,
        rootPath: URL
    ) -> RuntimeEnvelope {
        .system(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeRegistered(
                        worktreeId: worktreeId,
                        repoId: worktreeId,
                        rootPath: rootPath
                    )
                ),
                source: .builtin(.filesystemWatcher),
                seq: sequence
            )
        )
    }

    private func unregistrationEnvelope(sequence: UInt64, worktreeId: UUID) -> RuntimeEnvelope {
        .system(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeUnregistered(worktreeId: worktreeId, repoId: worktreeId)
                ),
                source: .builtin(.filesystemWatcher),
                seq: sequence
            )
        )
    }

    private func eventually(
        maximumTurns: Int = 10_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<maximumTurns {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }
}

private final class VerifiedCleanProjectorProvider: GitExactCleanStatusProviding, @unchecked Sendable {
    enum InitialOutcome {
        case clean
        case requiresExact
    }

    enum RenewalOutcome {
        case renewed
        case requiresExact
    }

    private let lock = NSLock()
    private let initialOutcome: InitialOutcome
    private let renewalOutcome: RenewalOutcome
    private let renewalGate: RenewalGate?
    private var _exactFactsReadCount = 0
    private var _ordinaryFactsReadCount = 0
    private var _detailReadCount = 0
    private var _renewalCount = 0

    init(
        initialOutcome: InitialOutcome,
        renewalOutcome: RenewalOutcome = .renewed,
        renewalGate: RenewalGate? = nil
    ) {
        self.initialOutcome = initialOutcome
        self.renewalOutcome = renewalOutcome
        self.renewalGate = renewalGate
    }

    var exactFactsReadCount: Int { lock.withLock { _exactFactsReadCount } }
    var ordinaryFactsReadCount: Int { lock.withLock { _ordinaryFactsReadCount } }
    var detailReadCount: Int { lock.withLock { _detailReadCount } }
    var renewalCount: Int { lock.withLock { _renewalCount } }

    func statusResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusResult {
        switch await statusFactsResult(for: rootPath, pathspecs: pathspecs) {
        case .available(let facts):
            .available(facts.composing(GitWorkingTreeLineDetail(linesAdded: 0, linesDeleted: 0)))
        case .unavailable(let unavailable):
            .unavailable(unavailable)
        }
    }

    func statusFactsResult(
        for _: URL,
        pathspecs _: [String]?
    ) async -> GitWorkingTreeStatusFactsResult {
        lock.withLock { _ordinaryFactsReadCount += 1 }
        return .available(Self.cleanFacts())
    }

    func lineDetailResult(for _: URL) async -> GitWorkingTreeLineDetailResult {
        lock.withLock { _detailReadCount += 1 }
        return .available(GitWorkingTreeLineDetail(linesAdded: 0, linesDeleted: 0))
    }

    func exactCleanStatusFactsResult(
        for worktreeId: UUID,
        rootPath _: URL
    ) async -> GitExactCleanStatusFactsResult {
        lock.withLock { _exactFactsReadCount += 1 }
        switch initialOutcome {
        case .clean:
            let identity = AgentStudioGit.GitStatusObservationIdentity(rawValue: "projector-test")
            let authority = GitCleanContinuityAuthority(
                registrationId: worktreeId,
                observationIdentity: identity,
                registrationGeneration: 1,
                mutationEpoch: 0,
                uncertaintyEpoch: 0
            )
            return .available(Self.cleanFacts(authority: authority))
        case .requiresExact:
            return .requiresExact(.eventStreamUncertain)
        }
    }

    func renewExactCleanAuthority(
        _ authority: GitCleanContinuityAuthority
    ) async -> GitExactCleanRenewalResult {
        lock.withLock { _renewalCount += 1 }
        await renewalGate?.suspend()
        switch renewalOutcome {
        case .renewed:
            return .renewed(authority)
        case .requiresExact:
            return .requiresExact(.eventStreamUncertain)
        }
    }

    func retireExactCleanAuthority(worktreeId _: UUID, rootPath _: URL) {}

    private static func cleanFacts(
        authority: GitCleanContinuityAuthority? = nil
    ) -> GitWorkingTreeStatusFacts {
        GitWorkingTreeStatusFacts(
            status: GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            ),
            exactCleanAuthority: authority
        )
    }
}

private actor RenewalGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        started = true
        let currentStartWaiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in currentStartWaiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        let currentReleaseWaiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in currentReleaseWaiters { waiter.resume() }
    }
}
