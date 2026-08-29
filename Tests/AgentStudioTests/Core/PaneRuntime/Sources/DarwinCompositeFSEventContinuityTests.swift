import AgentStudioGit
import CoreServices
import Darwin
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinCompositeFSEventContinuity")
struct DarwinCompositeFSEventContinuityTests {
    @Test("unchanged shared ancestor ambiguity resolves without full Git fallback")
    func unchangedAncestorAmbiguityResolvesWithoutFallback() async throws {
        let fixture = try CompositeContinuityFixture()
        let authority = try #require(await fixture.prepareAuthority())

        fixture.streamFactory.send(
            path: fixture.ancestorEventPath,
            eventId: 280,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        )

        let renewedAuthority = await waitForRenewedAuthority(
            client: fixture.client,
            authority: authority
        )
        let performance = fixture.client.snapshotAndResetIngressPerformance()

        #expect(renewedAuthority?.resolvedAncestorAmbiguityEpoch == 1)
        #expect(performance.sharedFullRefreshEmissionCount == 0)
    }

    @Test("shared activity cursor waits for MustScan ancestor verification")
    func activityCursorWaitsForMustScanVerification() async throws {
        let fingerprintGate = CompositeFingerprintGate()
        let fixture = try CompositeContinuityFixture(
            regularFileOpened: fingerprintGate.regularFileOpened
        )
        _ = try #require(await fixture.prepareAuthority())
        fingerprintGate.blockNextRead()

        fixture.streamFactory.send(
            path: fixture.ancestorEventPath,
            eventId: 281,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        )
        await fingerprintGate.waitUntilOpened()

        let pendingBarrier = try #require(await fixture.client.captureActivityBarrier())
        #expect(fixture.sharedDeliveredEventID(in: pendingBarrier) == 0)

        fingerprintGate.allowRead()
        let settledBarrier = try #require(
            await waitForSharedActivitySettlement(fixture: fixture, eventID: 281)
        )
        #expect(fixture.sharedDeliveredEventID(in: settledBarrier) == 281)
        let completionBatch = try #require(
            fixture.activityObservationBatches.last { $0.processedThroughEventID == 281 }
        )
        #expect(completionBatch.qualifyingWorktreeIds.isEmpty)
        #expect(completionBatch.coverageLostWorktreeIds.isEmpty)
    }

    @Test("changed qualifying shared item records activity before cursor settlement")
    func changedQualifyingSharedItemRecordsActivityBeforeSettlement() async throws {
        let fixture = try CompositeContinuityFixture(sharedItemName: "packed-refs")
        _ = try #require(await fixture.prepareAuthority())
        try Data("changed".utf8).write(to: fixture.configurationPath)

        fixture.streamFactory.send(
            path: fixture.ancestorEventPath,
            eventId: 282,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        )

        let settledBarrier = try #require(
            await waitForSharedActivitySettlement(fixture: fixture, eventID: 282)
        )
        let completionBatch = try #require(
            fixture.activityObservationBatches.first {
                $0.processedThroughEventID == 282
                    && $0.qualifyingWorktreeIds == [fixture.worktreeId]
            }
        )
        #expect(completionBatch.qualifyingWorktreeIds == [fixture.worktreeId])
        #expect(completionBatch.coverageLostWorktreeIds.isEmpty)
        #expect(fixture.sharedDeliveredEventID(in: settledBarrier) == 282)
    }

    @Test("missing qualifying shared item restarts activity coverage")
    func missingQualifyingSharedItemRestartsCoverage() async throws {
        let fixture = try CompositeContinuityFixture(sharedItemName: "packed-refs")
        try FileManager.default.removeItem(at: fixture.configurationPath)
        _ = try #require(await fixture.prepareAuthority())
        try Data("created".utf8).write(to: fixture.configurationPath)
        try FileManager.default.removeItem(at: fixture.configurationPath)

        fixture.streamFactory.send(
            path: fixture.ancestorEventPath,
            eventId: 286,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        )

        let settledBarrier = try #require(
            await waitForSharedActivitySettlement(fixture: fixture, eventID: 286)
        )
        let completionBatch = try #require(
            fixture.activityObservationBatches.last { $0.processedThroughEventID == 286 }
        )
        #expect(completionBatch.qualifyingWorktreeIds.isEmpty)
        #expect(completionBatch.coverageLostWorktreeIds == [fixture.worktreeId])
        #expect(fixture.sharedDeliveredEventID(in: settledBarrier) == 286)
    }

    @Test("unreadable shared item restarts activity coverage before cursor settlement")
    func unreadableSharedItemRestartsCoverageBeforeSettlement() async throws {
        let fixture = try CompositeContinuityFixture()
        _ = try #require(await fixture.prepareAuthority())
        try FileManager.default.removeItem(at: fixture.configurationPath)
        try FileManager.default.createDirectory(
            at: fixture.configurationPath,
            withIntermediateDirectories: false
        )

        fixture.streamFactory.send(
            path: fixture.ancestorEventPath,
            eventId: 283,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        )

        let settledBarrier = try #require(
            await waitForSharedActivitySettlement(fixture: fixture, eventID: 283)
        )
        let completionBatch = try #require(
            fixture.activityObservationBatches.last { $0.processedThroughEventID == 283 }
        )
        #expect(completionBatch.qualifyingWorktreeIds.isEmpty)
        #expect(completionBatch.coverageLostWorktreeIds == [fixture.worktreeId])
        #expect(fixture.sharedDeliveredEventID(in: settledBarrier) == 283)
    }

    @Test("nonqualifying exact hit preserves remaining ancestor activity scope")
    func nonqualifyingExactHitPreservesRemainingAncestorScope() async throws {
        let fingerprintGate = CompositeFingerprintGate()
        let fixture = try CompositeContinuityFixture(
            additionalSharedItemNames: ["packed-refs"],
            regularFileOpened: fingerprintGate.regularFileOpened
        )
        _ = try #require(await fixture.prepareAuthority())
        fingerprintGate.blockNextRead()

        fixture.streamFactory.send(
            path: fixture.ancestorEventPath,
            eventId: 284,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        )
        await fingerprintGate.waitUntilOpened()
        fixture.streamFactory.send(
            path: fixture.configurationEventPath,
            eventId: 285,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        )

        let pendingBarrier = try #require(await fixture.client.captureActivityBarrier())
        #expect(fixture.sharedDeliveredEventID(in: pendingBarrier) == 0)

        fingerprintGate.allowRead()
        let settledBarrier = try #require(
            await waitForSharedActivitySettlement(fixture: fixture, eventID: 285)
        )
        #expect(fixture.sharedDeliveredEventID(in: settledBarrier) == 285)
        #expect(
            fixture.activityObservationBatches.contains {
                $0.processedThroughEventID == 285
                    && $0.coverageLostWorktreeIds == [fixture.worktreeId]
            }
        )
    }

    @Test("stable shared fingerprint baseline renews with its resolved ambiguity epoch")
    func stableSharedFingerprintBaselineRenews() async throws {
        let fixture = try CompositeContinuityFixture()

        let authority = try #require(await fixture.prepareAuthority())
        let renewal = await fixture.client.renew(authority)

        #expect(authority.resolvedAncestorAmbiguityEpoch == 0)
        #expect(renewal == .authoritative(authority))
    }

    @Test("pre-prepare ancestor ambiguity is superseded by the exact scan")
    func prePrepareAncestorAmbiguityIsSuperseded() async throws {
        let fixture = try CompositeContinuityFixture()
        _ = try #require(await fixture.prepare())
        fixture.streamFactory.send(path: fixture.ancestorEventPath, eventId: 290)

        let authority = try #require(await fixture.prepareAuthority())

        #expect(authority.resolvedAncestorAmbiguityEpoch == 1)
        #expect(await fixture.client.renew(authority) == .authoritative(authority))
    }

    @Test("shared item replacement during fingerprinting rejects commit")
    func sharedItemReplacementDuringFingerprintingRejectsCommit() async throws {
        let fingerprintGate = CompositeFingerprintGate()
        let fixture = try CompositeContinuityFixture(
            regularFileOpened: fingerprintGate.regularFileOpened
        )
        let barrier = try #require(await fixture.prepare())
        fingerprintGate.blockNextRead()
        let commitTask = Task { await fixture.client.commit(barrier) }

        await fingerprintGate.waitUntilOpened()
        try Data("changed".utf8).write(to: fixture.configurationPath)
        fingerprintGate.allowRead()

        #expect((await commitTask.value).requiresExact)
    }

    @Test(
        "shared mutation during each composite flush window rejects continuity",
        arguments: CompositeFlushWindow.allCases
    )
    func sharedMutationDuringFlushRejectsContinuity(
        window: CompositeFlushWindow
    ) async throws {
        let fixture = try CompositeContinuityFixture(blockedFlushNumber: window.flushNumber)
        defer { fixture.streamFactory.allowBlockedFlush(result: true) }

        let operationTask: Task<Bool, Never>
        switch window {
        case .prepare:
            operationTask = Task {
                await fixture.prepare() == nil
            }
        case .commitBeforeFingerprint, .commitAfterFingerprint:
            let barrier = try #require(await fixture.prepare())
            operationTask = Task {
                (await fixture.client.commit(barrier)).requiresExact
            }
        case .renew:
            let authority = try #require(await fixture.prepareAuthority())
            operationTask = Task {
                (await fixture.client.renew(authority)).requiresExact
            }
        }

        await fixture.streamFactory.waitUntilBlockedFlushBegins()
        fixture.streamFactory.send(
            path: fixture.configurationEventPath,
            eventId: FSEventStreamEventId(300 + window.flushNumber)
        )
        fixture.streamFactory.allowBlockedFlush(result: true)

        #expect(await operationTask.value)
    }

    @Test("shared generation replacement after retain rejects commit")
    func sharedGenerationReplacementAfterRetainRejectsCommit() async throws {
        let fixture = try CompositeContinuityFixture(blockedFlushNumber: 2)
        defer { fixture.streamFactory.allowBlockedFlush(result: true) }
        let barrier = try #require(await fixture.prepare())
        let commitTask = Task { await fixture.client.commit(barrier) }

        await fixture.streamFactory.waitUntilBlockedFlushBegins()
        fixture.streamFactory.send(
            path: fixture.configurationEventPath,
            eventId: 320,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        )
        fixture.streamFactory.allowBlockedFlush(result: true)

        #expect((await commitTask.value).requiresExact)
    }

    @Test("unregister overlapping a retained composite flush rejects commit")
    func unregisterDuringRetainedCompositeFlushRejectsCommit() async throws {
        let fixture = try CompositeContinuityFixture(blockedFlushNumber: 2)
        defer { fixture.streamFactory.allowBlockedFlush(result: true) }
        let barrier = try #require(await fixture.prepare())
        let commitTask = Task { await fixture.client.commit(barrier) }

        await fixture.streamFactory.waitUntilBlockedFlushBegins()
        fixture.client.unregister(worktreeId: fixture.worktreeId)
        fixture.streamFactory.allowBlockedFlush(result: true)

        #expect((await commitTask.value).requiresExact)
    }

    @Test("shared flush failure rejects preparation")
    func sharedFlushFailureRejectsPreparation() async throws {
        let fixture = try CompositeContinuityFixture(blockedFlushNumber: 1)
        defer { fixture.streamFactory.allowBlockedFlush(result: false) }
        let prepareTask = Task { await fixture.prepare() }

        await fixture.streamFactory.waitUntilBlockedFlushBegins()
        fixture.streamFactory.allowBlockedFlush(result: false)

        #expect(await prepareTask.value == nil)
    }
}

private func waitForRenewedAuthority(
    client: DarwinFSEventStreamClient,
    authority: GitCleanContinuityAuthority
) async -> GitCleanContinuityAuthority? {
    for _ in 0..<1000 {
        if case .authoritative(let renewedAuthority) = await client.renew(authority) {
            return renewedAuthority
        }
        await Task.yield()
    }
    return nil
}

private func waitForSharedActivitySettlement(
    fixture: CompositeContinuityFixture,
    eventID: UInt64
) async -> FSEventActivityBarrier? {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while clock.now < deadline {
        if let barrier = await fixture.client.captureActivityBarrier(),
            fixture.sharedDeliveredEventID(in: barrier) == eventID
        {
            return barrier
        }
        await Task.yield()
    }
    return nil
}

enum CompositeFlushWindow: Int, CaseIterable, Sendable {
    case prepare = 1
    case commitBeforeFingerprint = 2
    case commitAfterFingerprint = 3
    case renew = 4

    var flushNumber: Int { rawValue }
}

private typealias CompositeRegularFileOpened =
    DarwinSharedExactItemFingerprintReader.RegularFileOpened

private final class CompositeContinuityFixture: @unchecked Sendable {
    let client: DarwinFSEventStreamClient
    let streamFactory: CompositeFlushStreamFactory
    let worktreeId = UUIDv7.generate()
    let worktreeRoot: URL
    let configurationPath: URL
    let configurationEventPath: String
    let ancestorEventPath: String
    let observationPlan: AgentStudioGit.GitStatusObservationPlan

    private let fixtureRoot: URL
    private let activityObservationLock = NSLock()
    private var recordedActivityObservationBatches: [FSEventActivityObservationBatch] = []
    private var ingressTask: Task<Void, Never>?

    var activityObservationBatches: [FSEventActivityObservationBatch] {
        activityObservationLock.withLock { recordedActivityObservationBatches }
    }

    init(
        blockedFlushNumber: Int = .max,
        sharedItemName: String = "configuration",
        additionalSharedItemNames: [String] = [],
        regularFileOpened: @escaping CompositeRegularFileOpened = { _ in }
    ) throws {
        fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-composite-continuity-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        worktreeRoot = fixtureRoot.appending(path: "worktree", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        configurationPath = externalParent.appending(path: sharedItemName)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try Data().write(to: configurationPath)
        for additionalSharedItemName in additionalSharedItemNames {
            try Data().write(to: externalParent.appending(path: additionalSharedItemName))
        }
        configurationEventPath = try #require(
            configurationPath.withUnsafeFileSystemRepresentation { pathPointer -> String? in
                guard let pathPointer, let resolvedPointer = Darwin.realpath(pathPointer, nil) else {
                    return nil
                }
                defer { free(resolvedPointer) }
                return String(cString: resolvedPointer)
            }
        )
        ancestorEventPath = try #require(
            externalParent.withUnsafeFileSystemRepresentation { pathPointer -> String? in
                guard let pathPointer, let resolvedPointer = Darwin.realpath(pathPointer, nil) else {
                    return nil
                }
                defer { free(resolvedPointer) }
                return String(cString: resolvedPointer)
            }
        )

        streamFactory = CompositeFlushStreamFactory(blockedFlushNumber: blockedFlushNumber)
        client = DarwinFSEventStreamClient(
            sharedExactItemStreamFactory: streamFactory.makeStream,
            sharedExactItemFingerprintReader: DarwinSharedExactItemFingerprintReader(
                regularFileOpened: regularFileOpened
            )
        )
        observationPlan = AgentStudioGit.GitStatusObservationPlan(
            identity: AgentStudioGit.GitStatusObservationIdentity(rawValue: "composite-continuity"),
            scopes: [AgentStudioGit.GitStatusObservationScope(kind: .subtree, path: worktreeRoot)]
                + ([sharedItemName] + additionalSharedItemNames).map {
                    AgentStudioGit.GitStatusObservationScope(
                        kind: .item,
                        path: externalParent.appending(path: $0)
                    )
                },
            support: .supported
        )
        client.register(worktreeId: worktreeId, repoId: UUIDv7.generate(), rootPath: worktreeRoot)
        ingressTask = Task { [client, weak self] in
            for await item in client.events() {
                switch item {
                case .activityObservations(let batch):
                    self?.activityObservationLock.withLock {
                        self?.recordedActivityObservationBatches.append(batch)
                    }
                case .activityProcessingFence(let fenceID):
                    client.acknowledgeActivityProcessingFence(fenceID)
                case .batch:
                    break
                }
            }
        }
    }

    deinit {
        ingressTask?.cancel()
        streamFactory.allowBlockedFlush(result: false)
        client.shutdown()
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    func prepare() async -> GitCleanContinuityBarrier? {
        await client.prepare(
            worktreeId: worktreeId,
            rootPath: worktreeRoot,
            observationPlan: observationPlan
        )
    }

    func prepareAuthority() async -> GitCleanContinuityAuthority? {
        guard let barrier = await prepare() else { return nil }
        return await client.commit(barrier).authority
    }

    func sharedDeliveredEventID(in barrier: FSEventActivityBarrier) -> UInt64? {
        barrier.deliveredEventIDByParticipant.first { participant, _ in
            participant.scopeKey.hasPrefix("shared:")
        }?.value
    }
}

private final class CompositeFingerprintGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let openedEvents: AsyncStream<Void>
    private let openedContinuation: AsyncStream<Void>.Continuation
    private var shouldBlockNextRead = false
    private var mayRead = true

    init() {
        (openedEvents, openedContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    var regularFileOpened: DarwinSharedExactItemFingerprintReader.RegularFileOpened {
        { [weak self] _ in
            guard let self else { return }
            condition.lock()
            guard shouldBlockNextRead else {
                condition.unlock()
                return
            }
            openedContinuation.yield()
            while !mayRead {
                condition.wait()
            }
            shouldBlockNextRead = false
            condition.unlock()
        }
    }

    func blockNextRead() {
        condition.withLock {
            shouldBlockNextRead = true
            mayRead = false
        }
    }

    func waitUntilOpened() async {
        for await _ in openedEvents {
            return
        }
    }

    func allowRead() {
        condition.withLock {
            mayRead = true
            condition.broadcast()
        }
    }
}

private final class CompositeFlushStreamFactory: @unchecked Sendable {
    private let condition = NSCondition()
    private let blockedFlushNumber: Int
    private let flushEvents: AsyncStream<Int>
    private let flushEventsContinuation: AsyncStream<Int>.Continuation
    private var completedBlockedFlushResult: Bool?
    private var eventHandler: (@Sendable ([DarwinSharedExactItemRawEvent]) -> Void)?
    private var flushCount = 0

    init(blockedFlushNumber: Int) {
        self.blockedFlushNumber = blockedFlushNumber
        (flushEvents, flushEventsContinuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func makeStream(
        parentKey _: DarwinSharedExactItemParentKey,
        streamGeneration _: UInt64,
        eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        condition.withLock {
            self.eventHandler = eventHandler
        }
        return CompositeFlushStreamLifetime(
            flush: performFlush,
            retire: {}
        )
    }

    func waitUntilBlockedFlushBegins() async {
        for await flushNumber in flushEvents where flushNumber == blockedFlushNumber {
            return
        }
    }

    func allowBlockedFlush(result: Bool) {
        condition.withLock {
            guard completedBlockedFlushResult == nil else { return }
            completedBlockedFlushResult = result
            condition.broadcast()
        }
    }

    func send(
        path: String,
        eventId: FSEventStreamEventId,
        flags: FSEventStreamEventFlags = 0
    ) {
        let handler = condition.withLock { eventHandler }
        handler?([
            DarwinSharedExactItemRawEvent(path: path, eventId: eventId, flags: flags)
        ])
    }

    private func performFlush() -> Bool {
        condition.lock()
        flushCount += 1
        let currentFlushNumber = flushCount
        guard currentFlushNumber == blockedFlushNumber else {
            condition.unlock()
            return true
        }
        flushEventsContinuation.yield(currentFlushNumber)
        while completedBlockedFlushResult == nil {
            condition.wait()
        }
        let result = completedBlockedFlushResult == true
        condition.unlock()
        return result
    }
}

private final class CompositeFlushStreamLifetime:
    DarwinSharedExactItemStreamLifetime, @unchecked Sendable
{
    private let flushAction: @Sendable () -> Bool
    private let retireAction: @Sendable () -> Void

    init(
        flush: @escaping @Sendable () -> Bool,
        retire: @escaping @Sendable () -> Void
    ) {
        flushAction = flush
        retireAction = retire
    }

    func flush() -> Bool {
        flushAction()
    }

    func retire() {
        retireAction()
    }
}

extension GitCleanContinuityAuthorityValidation {
    fileprivate var authority: GitCleanContinuityAuthority? {
        guard case .authoritative(let authority) = self else { return nil }
        return authority
    }

    fileprivate var requiresExact: Bool {
        guard case .requiresExact = self else { return false }
        return true
    }
}
