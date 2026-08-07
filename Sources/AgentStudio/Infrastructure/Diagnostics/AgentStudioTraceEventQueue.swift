import Foundation

package final class AgentStudioTraceEventQueue: @unchecked Sendable {
    package struct CompletenessSnapshot: Equatable, Sendable {
        package let droppedRecordCount: Int
        package let highWaterMark: Int
    }

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
    private let bufferLimit: Int
    private let lock = NSLock()
    private var continuation: AsyncStream<TraceRequest>.Continuation?
    private var workerTask: Task<Void, Never>?
    private var isClosed = false
    private var droppedRecordCount = 0
    private var highWaterMark = 0

    package convenience init(traceRuntime: AgentStudioTraceRuntime) {
        self.init(
            traceRuntime: traceRuntime,
            bufferLimit: AppPolicies.Diagnostics.traceEventQueueBufferLimit
        )
    }

    package init(traceRuntime: AgentStudioTraceRuntime, bufferLimit: Int) {
        precondition(bufferLimit > 0)
        self.traceRuntime = traceRuntime
        self.bufferLimit = bufferLimit
    }

    deinit {
        cancel()
    }

    package func record(
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
        let yieldResult = continuation?.yield(.record(request))
        let droppedFlushContinuation = accountForYieldResultLocked(yieldResult)
        lock.unlock()
        droppedFlushContinuation?.resume(throwing: CancellationError())
    }

    package func flush() async throws {
        guard prepareWorkerForFlush() else {
            try await traceRuntime.flush()
            return
        }

        try await withUnsafeThrowingContinuation { (flushContinuation: UnsafeContinuation<Void, Error>) in
            lock.lock()
            guard !isClosed, let continuation else {
                lock.unlock()
                flushContinuation.resume(throwing: CancellationError())
                return
            }
            let yieldResult = continuation.yield(.flush(flushContinuation))
            let droppedFlushContinuation = accountForYieldResultLocked(yieldResult)
            let didTerminate: Bool
            switch yieldResult {
            case .terminated:
                didTerminate = true
            case .enqueued, .dropped:
                didTerminate = false
            @unknown default:
                didTerminate = true
            }
            lock.unlock()
            droppedFlushContinuation?.resume(throwing: CancellationError())
            if didTerminate {
                flushContinuation.resume(throwing: CancellationError())
            }
        }
    }

    package func drain() async throws {
        let (continuation, workerTask) = closeForDrain()
        continuation?.finish()
        await workerTask?.value
        try await traceRuntime.flush()
    }

    package func cancel() {
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

    package func completenessSnapshot() -> CompletenessSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return CompletenessSnapshot(
            droppedRecordCount: droppedRecordCount,
            highWaterMark: highWaterMark
        )
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
            bufferingPolicy: .bufferingNewest(bufferLimit)
        )
        self.continuation = continuation
        let traceRuntime = traceRuntime
        // Detached worker avoids inheriting MainActor while trace I/O drains.
        // swiftlint:disable:next no_task_detached
        workerTask = Task.detached(priority: .utility) { [weak self] in
            for await request in stream {
                switch request {
                case .record(let request):
                    var attributes = request.attributes
                    if request.tag == .performance, let completenessSnapshot = self?.completenessSnapshot() {
                        attributes["agentstudio.performance.trace_queue.dropped_record.count"] = .int(
                            completenessSnapshot.droppedRecordCount
                        )
                        attributes["agentstudio.performance.trace_queue.high_watermark"] = .int(
                            completenessSnapshot.highWaterMark
                        )
                    }
                    let completeAttributes = attributes
                    await traceRuntime.record(
                        tag: request.tag,
                        body: request.body,
                        traceID: request.traceID,
                        spanID: request.spanID,
                        parentSpanID: request.parentSpanID,
                        eventTimeUnixNano: request.eventTimeUnixNano,
                        attributes: completeAttributes
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

    private func prepareWorkerForFlush() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return false }
        ensureWorkerStartedLocked()
        return true
    }

    private func accountForYieldResultLocked(
        _ yieldResult: AsyncStream<TraceRequest>.Continuation.YieldResult?
    ) -> UnsafeContinuation<Void, Error>? {
        guard let yieldResult else { return nil }
        switch yieldResult {
        case .enqueued(let remainingCapacity):
            highWaterMark = max(highWaterMark, bufferLimit - remainingCapacity)
            return nil
        case .dropped(let droppedRequest):
            highWaterMark = bufferLimit
            switch droppedRequest {
            case .record:
                droppedRecordCount += 1
                return nil
            case .flush(let continuation):
                return continuation
            }
        case .terminated:
            return nil
        @unknown default:
            return nil
        }
    }
}
