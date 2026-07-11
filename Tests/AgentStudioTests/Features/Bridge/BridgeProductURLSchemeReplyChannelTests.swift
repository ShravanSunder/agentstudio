import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product URL scheme reply channel")
struct BridgeProductURLSchemeReplyChannelTests {
    @Test("send rendezvous completes only through iterator consumption")
    func sendRendezvousIsConsumedExactlyOnce() async throws {
        // Arrange
        let channel = BridgeProductURLSchemeReplyChannel<Int>()
        var iterator = channel.makeAsyncIterator()

        // Act
        let sendTask = Task {
            try await channel.send(41)
            return 42
        }
        let received = try await iterator.next()
        let senderResult = try await sendTask.value
        let firstFinish = await channel.finish()
        let duplicateFinish = await channel.finish()
        let terminal = try await iterator.next()

        // Assert
        #expect(received == 41)
        #expect(senderResult == 42)
        #expect(firstFinish)
        #expect(!duplicateFinish)
        #expect(terminal == nil)
    }

    @Test("consumer cancellation closes channel and cancels an attached producer")
    func consumerCancellationCancelsProducer() async throws {
        // Arrange
        let channel = BridgeProductURLSchemeReplyChannel<Int>()
        let producerGate = ReplyChannelProducerCancellationGate()
        let producerTask = Task { await producerGate.run() }
        channel.attachProducerTask(producerTask)
        var iterator = channel.makeAsyncIterator()

        // Act
        let receiveTask = Task { try await iterator.next() }
        receiveTask.cancel()
        _ = try? await receiveTask.value
        await producerGate.waitUntilCancelled()
        let sendWasRejected: Bool
        do {
            try await channel.send(1)
            sendWasRejected = false
        } catch {
            sendWasRejected = true
        }

        // Assert
        #expect(sendWasRejected)
        #expect(await channel.finish() == false)
    }

    @Test("failure is terminal exactly once and reaches a waiting iterator")
    func failureTerminatesExactlyOnce() async {
        // Arrange
        let channel = BridgeProductURLSchemeReplyChannel<Int>()
        var iterator = channel.makeAsyncIterator()

        // Act
        let firstFailure = await channel.fail(ReplyChannelTestError.expected)
        let duplicateFailure = await channel.fail(ReplyChannelTestError.expected)
        let observedExpectedFailure: Bool
        do {
            _ = try await iterator.next()
            observedExpectedFailure = false
        } catch ReplyChannelTestError.expected {
            observedExpectedFailure = true
        } catch {
            observedExpectedFailure = false
        }

        // Assert
        #expect(firstFailure)
        #expect(!duplicateFailure)
        #expect(observedExpectedFailure)
    }
}

private enum ReplyChannelTestError: Error {
    case expected
}

private actor ReplyChannelProducerCancellationGate {
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var wasCancelled = false

    func run() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || wasCancelled {
                    continuation.resume()
                } else {
                    cancellationContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitUntilCancelled() async {
        if wasCancelled { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    private func cancel() {
        wasCancelled = true
        cancellationContinuation?.resume()
        cancellationContinuation = nil
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
