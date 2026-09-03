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

        // Assert
        let batch = try #require(
            await firstCompletedValue(from: deliveredBatch, timeout: .seconds(1))
        )
        #expect(batch.paths.contains(where: { $0.hasSuffix("/Changed.swift") }))
    }

    private func firstCompletedValue<Value: Sendable>(
        from task: Task<Value?, Never>,
        timeout: Duration
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await AsyncDelay.taskSleep.wait(timeout)
                return nil
            }
            guard let value = await group.next() else {
                task.cancel()
                return nil
            }
            group.cancelAll()
            task.cancel()
            return value
        }
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
