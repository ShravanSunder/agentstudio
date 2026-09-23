import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinFSEventStreamClient activation")
struct DarwinFSEventStreamClientActivationTests {
    @Test("successor callbacks wait for the new client registration before replay")
    func successorCallbacksWaitForClientRegistrationBeforeReplay() async throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-client-activation-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let eventId: FSEventStreamEventId = 501
        let canonicalSecondRoot = DarwinFSEventPathCanonicalizer.canonicalURL(secondRoot)
        let streamFactory = ClientActivationBoundaryLocalFSEventStreamFactory(
            successorEvent: DarwinLocalFSEventRawEvent(
                path: canonicalSecondRoot.appending(path: "Changed.swift").path,
                eventId: eventId,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
            )
        )
        let client = DarwinFSEventStreamClient(localStreamFactory: streamFactory.makeStream)
        defer { client.shutdown() }
        let repositoryId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        client.register(worktreeId: firstWorktreeId, repoId: repositoryId, rootPath: firstRoot)
        let deliveredBatch = Task<FSEventBatch?, Never> {
            for await ingressItem in client.events() {
                guard case .batch(let batch) = ingressItem,
                    batch.worktreeId == secondWorktreeId,
                    batch.observations.contains(where: { $0.eventID == eventId })
                else {
                    continue
                }
                return batch
            }
            return nil
        }

        // Act
        client.register(worktreeId: secondWorktreeId, repoId: repositoryId, rootPath: secondRoot)

        // Assert — `deliveredBatch` is already the waiter: it returns the instant the
        // matching batch arrives, and nil if `client.events()` finishes. Racing a clock
        // against it only added a machine-speed verdict, which matters here because the
        // fake parks a cooperative thread on a semaphore during replacement.
        let batch = try #require(await deliveredBatch.value)
        #expect(batch.paths.contains(where: { $0.hasSuffix("/Changed.swift") }))
    }

    @Test("activity barrier fails closed while a physical replacement is pending")
    func activityBarrierFailsClosedDuringPhysicalReplacement() async throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-barrier-activation-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = PendingReplacementLocalFSEventStreamFactory()
        let client = DarwinFSEventStreamClient(localStreamFactory: streamFactory.makeStream)
        defer { client.shutdown() }
        let repositoryId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        client.register(worktreeId: firstWorktreeId, repoId: repositoryId, rootPath: firstRoot)
        let fenceConsumer = Task {
            for await ingressItem in client.events() {
                guard case .activityProcessingFence(let fenceID) = ingressItem else { continue }
                client.acknowledgeActivityProcessingFence(fenceID)
            }
        }
        defer { fenceConsumer.cancel() }
        // The fake blocks synchronous FlushSync; detached execution keeps the
        // controlling test task available to inspect and release that boundary.
        // swiftlint:disable:next no_task_detached
        let registrationTask = Task.detached {
            client.register(worktreeId: secondWorktreeId, repoId: repositoryId, rootPath: secondRoot)
        }
        await streamFactory.waitUntilReplacementFlushStarts()

        // Act / Assert
        #expect(await client.captureActivityBarrier() == nil)

        streamFactory.releaseReplacementFlush()
        await registrationTask.value
        let settledBarrier = try #require(await client.captureActivityBarrier())
        #expect(Set(settledBarrier.bindings.map(\.worktreeId)) == [firstWorktreeId, secondWorktreeId])
    }

}

private final class PendingReplacementLocalFSEventStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseFlush = DispatchSemaphore(value: 0)
    private let flushStarted: AsyncStream<Void>
    private let flushStartedContinuation: AsyncStream<Void>.Continuation
    private var streamCount = 0
    private var flushCount = 0

    init() {
        (flushStarted, flushStartedContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func makeStream(
        request _: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        let streamIndex = lock.withLock { () -> Int in
            streamCount += 1
            return streamCount
        }
        return ClientActivationBoundaryLocalFSEventStreamLifetime(
            flush: { [weak self] in
                guard let self else { return false }
                let flushNumber = lock.withLock { () -> Int in
                    flushCount += 1
                    return flushCount
                }
                if streamIndex == 1, flushNumber == 1 {
                    flushStartedContinuation.yield()
                    releaseFlush.wait()
                }
                return true
            }
        )
    }

    func waitUntilReplacementFlushStarts() async {
        var iterator = flushStarted.makeAsyncIterator()
        _ = await iterator.next()
    }

    func releaseReplacementFlush() {
        releaseFlush.signal()
    }
}

private final class ClientActivationBoundaryLocalFSEventStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let successorEvent: DarwinLocalFSEventRawEvent
    private var eventHandlers: [@Sendable ([DarwinLocalFSEventRawEvent]) -> Void] = []

    init(successorEvent: DarwinLocalFSEventRawEvent) {
        self.successorEvent = successorEvent
    }

    func makeStream(
        request: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        let streamIndex = lock.withLock { () -> Int in
            eventHandlers.append(request.eventHandler)
            return eventHandlers.count
        }
        return ClientActivationBoundaryLocalFSEventStreamLifetime(
            flush: { [weak self] in
                guard let self else { return false }
                if streamIndex == 1 {
                    lock.withLock { eventHandlers.last }?([successorEvent])
                }
                return true
            }
        )
    }
}

private final class ClientActivationBoundaryLocalFSEventStreamLifetime:
    DarwinLocalFSEventStreamLifetime, @unchecked Sendable
{
    private let flushHandler: @Sendable () -> Bool

    init(flush: @escaping @Sendable () -> Bool) {
        flushHandler = flush
    }

    func flush() -> Bool {
        flushHandler()
    }

    func retire() {}

    func scheduleRetirement() {}
}
