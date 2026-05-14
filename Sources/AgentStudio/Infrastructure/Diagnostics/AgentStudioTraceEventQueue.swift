import Foundation

final class AgentStudioTraceEventQueue: @unchecked Sendable {
    private struct TraceRequest: Sendable {
        let tag: AgentStudioTraceTag
        let body: String
        let traceID: String?
        let parentSpanID: String?
        let attributes: [String: AgentStudioTraceValue]
    }

    private let traceRuntime: AgentStudioTraceRuntime
    private let lock = NSLock()
    private var continuation: AsyncStream<TraceRequest>.Continuation?
    private var workerTask: Task<Void, Never>?
    private var isClosed = false

    init(traceRuntime: AgentStudioTraceRuntime) {
        self.traceRuntime = traceRuntime
    }

    deinit {
        cancel()
    }

    func record(
        tag: AgentStudioTraceTag,
        body: String,
        traceID: String? = nil,
        parentSpanID: String? = nil,
        attributes: [String: AgentStudioTraceValue]
    ) {
        let request = TraceRequest(
            tag: tag,
            body: body,
            traceID: traceID,
            parentSpanID: parentSpanID,
            attributes: attributes
        )
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        ensureWorkerStartedLocked()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(request)
    }

    func drain() async throws {
        let (continuation, workerTask) = closeForDrain()
        continuation?.finish()
        await workerTask?.value
        try await traceRuntime.flush()
    }

    func cancel() {
        lock.lock()
        isClosed = true
        let continuation = continuation
        self.continuation = nil
        let workerTask = workerTask
        self.workerTask = nil
        lock.unlock()
        continuation?.finish()
        workerTask?.cancel()
    }

    private func closeForDrain() -> (
        AsyncStream<TraceRequest>.Continuation?, Task<Void, Never>?
    ) {
        lock.lock()
        isClosed = true
        let continuation = continuation
        self.continuation = nil
        let workerTask = workerTask
        self.workerTask = nil
        lock.unlock()
        return (continuation, workerTask)
    }

    private func ensureWorkerStartedLocked() {
        guard workerTask == nil else { return }
        let (stream, continuation) = AsyncStream.makeStream(
            of: TraceRequest.self,
            bufferingPolicy: .bufferingNewest(AppPolicies.Diagnostics.traceEventQueueBufferLimit)
        )
        self.continuation = continuation
        let traceRuntime = traceRuntime
        // Detached worker avoids inheriting MainActor while trace I/O drains.
        // swiftlint:disable:next no_task_detached
        workerTask = Task.detached(priority: .utility) {
            for await request in stream {
                await traceRuntime.record(
                    tag: request.tag,
                    body: request.body,
                    traceID: request.traceID,
                    parentSpanID: request.parentSpanID,
                    attributes: request.attributes
                )
            }
        }
    }
}
