import Foundation
import Synchronization

package final class AgentStudioTraceEventQueue: @unchecked Sendable {
    package struct CompletenessSnapshot: Equatable, Sendable {
        package let droppedRecordCount: Int
        package let highWaterMark: Int
        package let pendingRequestCount: Int
    }

    private struct CompletenessState: Sendable {
        var droppedRecordCount = 0
        var highWaterMark = 0
        var pendingRequestCount = 0
    }

    private final class CompletenessTracker: Sendable {
        let state = Mutex(CompletenessState())
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
    private let completenessTracker = CompletenessTracker()

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
        accountForEnqueueAttempt()
        let yieldResult = continuation?.yield(.record(request))
        lock.unlock()
        guard let yieldResult else { return }
        let droppedFlushContinuation = accountForYieldResult(yieldResult)
        droppedFlushContinuation?.resume(throwing: CancellationError())
    }

    package func flush() async throws {
        let isOpen: Bool = lock.withLock {
            guard !isClosed else { return false }
            ensureWorkerStartedLocked()
            return true
        }
        guard isOpen else {
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
            accountForEnqueueAttempt()
            let yieldResult = continuation.yield(.flush(flushContinuation))
            lock.unlock()
            let droppedFlushContinuation = accountForYieldResult(yieldResult, isRecord: false)
            let didTerminate: Bool
            switch yieldResult {
            case .terminated:
                didTerminate = true
            case .enqueued, .dropped:
                didTerminate = false
            @unknown default:
                didTerminate = true
            }
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
        completenessTracker.state.withLock { state in
            CompletenessSnapshot(
                droppedRecordCount: state.droppedRecordCount,
                highWaterMark: state.highWaterMark,
                pendingRequestCount: state.pendingRequestCount
            )
        }
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
        let completenessTracker = completenessTracker
        // Detached worker avoids inheriting MainActor while trace I/O drains.
        // swiftlint:disable:next no_task_detached
        workerTask = Task.detached(priority: .utility) {
            for await request in stream {
                let requestBacklogSnapshot = completenessTracker.state.withLock { state in
                    state.pendingRequestCount = max(0, state.pendingRequestCount - 1)
                    return CompletenessSnapshot(
                        droppedRecordCount: state.droppedRecordCount,
                        highWaterMark: state.highWaterMark,
                        pendingRequestCount: state.pendingRequestCount
                    )
                }
                switch request {
                case .record(let request):
                    var attributes = request.attributes
                    if request.tag == .performance {
                        attributes["agentstudio.performance.trace_queue.dropped_record.count"] = .int(
                            requestBacklogSnapshot.droppedRecordCount
                        )
                        attributes["agentstudio.performance.trace_queue.high_watermark"] = .int(
                            requestBacklogSnapshot.highWaterMark
                        )
                        attributes["agentstudio.performance.trace_queue.pending_request.count"] = .int(
                            requestBacklogSnapshot.pendingRequestCount
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
                        await traceRuntime.record(
                            tag: .performance,
                            body: "performance.trace_queue.completeness",
                            attributes: [
                                "agentstudio.performance.trace_queue.dropped_record.count": .int(
                                    requestBacklogSnapshot.droppedRecordCount
                                ),
                                "agentstudio.performance.trace_queue.high_watermark": .int(
                                    requestBacklogSnapshot.highWaterMark
                                ),
                                "agentstudio.performance.trace_queue.pending_request.count": .int(
                                    requestBacklogSnapshot.pendingRequestCount
                                ),
                            ]
                        )
                        try await traceRuntime.flush()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func accountForYieldResult(
        _ yieldResult: AsyncStream<TraceRequest>.Continuation.YieldResult,
        isRecord: Bool = true
    ) -> UnsafeContinuation<Void, Error>? {
        switch yieldResult {
        case .enqueued(let remainingCapacity):
            completenessTracker.state.withLock { state in
                state.highWaterMark = max(state.highWaterMark, bufferLimit - remainingCapacity)
            }
            return nil
        case .dropped(let droppedRequest):
            completenessTracker.state.withLock { state in
                state.highWaterMark = bufferLimit
                state.pendingRequestCount = max(0, state.pendingRequestCount - 1)
                if case .record = droppedRequest {
                    state.droppedRecordCount += 1
                }
            }
            switch droppedRequest {
            case .record:
                return nil
            case .flush(let continuation):
                return continuation
            }
        case .terminated:
            completenessTracker.state.withLock { state in
                state.pendingRequestCount = max(0, state.pendingRequestCount - 1)
                if isRecord {
                    state.droppedRecordCount += 1
                }
            }
            return nil
        @unknown default:
            completenessTracker.state.withLock { state in
                state.pendingRequestCount = max(0, state.pendingRequestCount - 1)
            }
            return nil
        }
    }

    private func accountForEnqueueAttempt() {
        completenessTracker.state.withLock { state in
            state.pendingRequestCount += 1
        }
    }
}
