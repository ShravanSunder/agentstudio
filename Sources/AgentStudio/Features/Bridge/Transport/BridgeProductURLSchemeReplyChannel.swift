import Foundation

enum BridgeProductURLSchemeReplyChannelError: Error, Sendable {
    case closed
    case concurrentNext
    case concurrentSend
    case multipleIterators
}

actor BridgeProductURLSchemeReplyChannel<Element: Sendable>: AsyncSequence {
    struct Iterator: AsyncIteratorProtocol {
        private let channel: BridgeProductURLSchemeReplyChannel<Element>
        private let id: UUID
        private var isTerminal = false

        fileprivate init(
            channel: BridgeProductURLSchemeReplyChannel<Element>,
            id: UUID
        ) {
            self.channel = channel
            self.id = id
        }

        mutating func next() async throws -> Element? {
            guard !isTerminal else { return nil }
            do {
                let element = try await channel.next(iteratorId: id)
                if element == nil { isTerminal = true }
                return element
            } catch {
                isTerminal = true
                throw error
            }
        }
    }

    private enum Terminal {
        case consumerCancelled
        case failed(any Error)
        case finished
    }

    private struct PendingNext {
        let continuation: CheckedContinuation<Element?, Error>
        let id: UUID
        let iteratorId: UUID
    }

    private struct PendingSend {
        let continuation: CheckedContinuation<Void, Error>
        let element: Element
        let id: UUID
    }

    private nonisolated let producerAttachment =
        BridgeProductURLSchemeReplyProducerAttachment()
    private var activeIteratorId: UUID?
    private var pendingNext: PendingNext?
    private var pendingSend: PendingSend?
    private var terminal: Terminal?

    init() {}

    nonisolated func makeAsyncIterator() -> Iterator {
        Iterator(channel: self, id: UUID())
    }

    func send(_ result: Element) async throws {
        let sendId = UUID()
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard terminal == nil else {
                    continuation.resume(throwing: BridgeProductURLSchemeReplyChannelError.closed)
                    return
                }
                guard pendingSend == nil else {
                    continuation.resume(
                        throwing: BridgeProductURLSchemeReplyChannelError.concurrentSend
                    )
                    return
                }
                if let pendingNext {
                    self.pendingNext = nil
                    pendingNext.continuation.resume(returning: result)
                    continuation.resume()
                    return
                }
                pendingSend = .init(
                    continuation: continuation,
                    element: result,
                    id: sendId
                )
            }
        } onCancel: {
            Task { await self.cancelSend(id: sendId) }
        }
    }

    @discardableResult
    func finish() -> Bool {
        finish(with: .finished)
    }

    @discardableResult
    func fail(_ error: any Error) -> Bool {
        finish(with: .failed(error))
    }

    nonisolated func attachProducerTask(_ task: Task<Void, Never>) {
        producerAttachment.attach(task)
    }

    private func next(iteratorId: UUID) async throws -> Element? {
        try registerIterator(iteratorId)
        if Task.isCancelled {
            await closeForCancelledConsumer()
            throw CancellationError()
        }

        let nextId = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    pendingNext = .init(
                        continuation: continuation,
                        id: nextId,
                        iteratorId: iteratorId
                    )
                    Task { await self.cancelNext(id: nextId, iteratorId: iteratorId) }
                    return
                }
                if let pendingSend {
                    self.pendingSend = nil
                    continuation.resume(returning: pendingSend.element)
                    pendingSend.continuation.resume()
                    return
                }
                if let terminal {
                    resume(continuation, for: terminal)
                    return
                }
                guard pendingNext == nil else {
                    continuation.resume(
                        throwing: BridgeProductURLSchemeReplyChannelError.concurrentNext
                    )
                    return
                }
                pendingNext = .init(
                    continuation: continuation,
                    id: nextId,
                    iteratorId: iteratorId
                )
            }
        } onCancel: {
            Task { await self.cancelNext(id: nextId, iteratorId: iteratorId) }
        }
    }

    private func registerIterator(_ iteratorId: UUID) throws {
        if let activeIteratorId {
            guard activeIteratorId == iteratorId else {
                throw BridgeProductURLSchemeReplyChannelError.multipleIterators
            }
        } else {
            activeIteratorId = iteratorId
        }
    }

    private func cancelSend(id: UUID) {
        guard let pendingSend, pendingSend.id == id else { return }
        self.pendingSend = nil
        pendingSend.continuation.resume(throwing: CancellationError())
    }

    private func cancelNext(id: UUID, iteratorId: UUID) async {
        guard let pendingNext,
            pendingNext.id == id,
            pendingNext.iteratorId == iteratorId
        else {
            return
        }
        terminal = .consumerCancelled
        if let pendingSend {
            self.pendingSend = nil
            pendingSend.continuation.resume(
                throwing: BridgeProductURLSchemeReplyChannelError.closed
            )
        }
        await producerAttachment.cancelAndWaitForProducer()
        guard self.pendingNext?.id == id else { return }
        self.pendingNext = nil
        pendingNext.continuation.resume(throwing: CancellationError())
    }

    private func closeForCancelledConsumer() async {
        guard terminal == nil else { return }
        terminal = .consumerCancelled
        if let pendingSend {
            self.pendingSend = nil
            pendingSend.continuation.resume(
                throwing: BridgeProductURLSchemeReplyChannelError.closed
            )
        }
        await producerAttachment.cancelAndWaitForProducer()
    }

    private func finish(with terminal: Terminal) -> Bool {
        guard self.terminal == nil else { return false }
        self.terminal = terminal
        if pendingSend == nil, let pendingNext {
            self.pendingNext = nil
            resume(pendingNext.continuation, for: terminal)
        }
        return true
    }

    private func resume(
        _ continuation: CheckedContinuation<Element?, Error>,
        for terminal: Terminal
    ) {
        switch terminal {
        case .consumerCancelled:
            continuation.resume(throwing: CancellationError())
        case .failed(let error):
            continuation.resume(throwing: error)
        case .finished:
            continuation.resume(returning: nil)
        }
    }
}

private final class BridgeProductURLSchemeReplyProducerAttachment: @unchecked Sendable {
    private let lock = NSLock()
    private var producerTask: Task<Void, Never>?
    private var taskWaiters: [CheckedContinuation<Task<Void, Never>, Never>] = []

    func attach(_ task: Task<Void, Never>) {
        lock.lock()
        guard producerTask == nil else {
            lock.unlock()
            task.cancel()
            return
        }
        producerTask = task
        let waiters = taskWaiters
        taskWaiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume(returning: task)
        }
    }

    func cancelAndWaitForProducer() async {
        let task = await attachedTask()
        task.cancel()
        await task.value
    }

    private func attachedTask() async -> Task<Void, Never> {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let producerTask {
                lock.unlock()
                continuation.resume(returning: producerTask)
            } else {
                taskWaiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
