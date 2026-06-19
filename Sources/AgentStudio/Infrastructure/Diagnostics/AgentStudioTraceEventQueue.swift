import Foundation

final class AgentStudioTraceEventQueue: @unchecked Sendable {
    private enum TraceRequest: Sendable {
        case record(RecordRequest)
        case flush(UnsafeContinuation<Void, Error>)
    }

    private struct RecordRequest: Sendable {
        var tag: AgentStudioTraceTag
        var body: String
        var traceID: String?
        var spanID: String?
        var parentSpanID: String?
        var eventTimeUnixNano: UInt64?
        var attributes: [String: AgentStudioTraceValue]
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
        spanID: String? = nil,
        parentSpanID: String? = nil,
        eventTimeUnixNano: UInt64? = nil,
        attributes: [String: AgentStudioTraceValue]
    ) {
        let request = RecordRequest(
            tag: tag,
            body: body,
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            eventTimeUnixNano: eventTimeUnixNano,
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
        continuation?.yield(.record(request))
    }

    func flush() async throws {
        let continuation = openContinuationForFlush()
        guard let continuation else {
            try await traceRuntime.flush()
            return
        }

        try await withUnsafeThrowingContinuation { (flushContinuation: UnsafeContinuation<Void, Error>) in
            switch continuation.yield(.flush(flushContinuation)) {
            case .enqueued:
                break
            case .dropped, .terminated:
                flushContinuation.resume(throwing: CancellationError())
            @unknown default:
                flushContinuation.resume(throwing: CancellationError())
            }
        }
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

    private func openContinuationForFlush() -> AsyncStream<TraceRequest>.Continuation? {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return nil
        }
        ensureWorkerStartedLocked()
        let continuation = continuation
        lock.unlock()
        return continuation
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
                switch request {
                case .record(let request):
                    await traceRuntime.record(
                        tag: request.tag,
                        body: request.body,
                        traceID: request.traceID,
                        spanID: request.spanID,
                        parentSpanID: request.parentSpanID,
                        eventTimeUnixNano: request.eventTimeUnixNano,
                        attributes: request.attributes
                    )
                case .flush(let continuation):
                    do {
                        try await traceRuntime.flush()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
