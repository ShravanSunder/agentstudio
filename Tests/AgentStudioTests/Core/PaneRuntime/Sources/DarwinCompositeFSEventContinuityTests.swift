import AgentStudioGit
import CoreServices
import Darwin
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinCompositeFSEventContinuity")
struct DarwinCompositeFSEventContinuityTests {
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
        case .commit:
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

enum CompositeFlushWindow: Int, CaseIterable, Sendable {
    case prepare = 1
    case commit = 2
    case renew = 3

    var flushNumber: Int { rawValue }
}

private final class CompositeContinuityFixture: @unchecked Sendable {
    let client: DarwinFSEventStreamClient
    let streamFactory: CompositeFlushStreamFactory
    let worktreeId = UUIDv7.generate()
    let worktreeRoot: URL
    let configurationPath: URL
    let configurationEventPath: String
    let observationPlan: AgentStudioGit.GitStatusObservationPlan

    private let fixtureRoot: URL

    init(blockedFlushNumber: Int) throws {
        fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-composite-continuity-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        worktreeRoot = fixtureRoot.appending(path: "worktree", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        configurationPath = externalParent.appending(path: "configuration")
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try Data().write(to: configurationPath)
        configurationEventPath = try #require(
            configurationPath.withUnsafeFileSystemRepresentation { pathPointer -> String? in
                guard let pathPointer, let resolvedPointer = Darwin.realpath(pathPointer, nil) else {
                    return nil
                }
                defer { free(resolvedPointer) }
                return String(cString: resolvedPointer)
            }
        )

        streamFactory = CompositeFlushStreamFactory(blockedFlushNumber: blockedFlushNumber)
        client = DarwinFSEventStreamClient(
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        observationPlan = AgentStudioGit.GitStatusObservationPlan(
            identity: AgentStudioGit.GitStatusObservationIdentity(rawValue: "composite-continuity"),
            scopes: [
                AgentStudioGit.GitStatusObservationScope(kind: .subtree, path: worktreeRoot),
                AgentStudioGit.GitStatusObservationScope(kind: .item, path: configurationPath),
            ],
            support: .supported
        )
        client.register(worktreeId: worktreeId, repoId: UUIDv7.generate(), rootPath: worktreeRoot)
    }

    deinit {
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
