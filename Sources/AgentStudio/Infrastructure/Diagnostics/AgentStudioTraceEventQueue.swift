import Foundation
import Synchronization

package final class AgentStudioTraceEventQueue: @unchecked Sendable {
    package struct CompletenessSnapshot: Equatable, Sendable {
        package let droppedRecordCount: Int
        package let highWaterMark: Int
    }

    private struct CompletenessState: Sendable {
        var droppedRecordCount = 0
        var highWaterMark = 0
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
        guard let continuation = continuationForEnqueue() else { return }
        let yieldResult = continuation.yield(.record(request))
        let droppedFlushContinuation = accountForYieldResult(yieldResult)
        droppedFlushContinuation?.resume(throwing: CancellationError())
    }

    package func flush() async throws {
        guard let continuation = continuationForEnqueue() else {
            try await traceRuntime.flush()
            return
        }

        try await withUnsafeThrowingContinuation { (flushContinuation: UnsafeContinuation<Void, Error>) in
            let yieldResult = continuation.yield(.flush(flushContinuation))
            let droppedFlushContinuation = accountForYieldResult(yieldResult)
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
                highWaterMark: state.highWaterMark
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
                switch request {
                case .record(let request):
                    var attributes = request.attributes
                    if request.tag == .performance {
                        let completenessSnapshot = completenessTracker.state.withLock { state in
                            CompletenessSnapshot(
                                droppedRecordCount: state.droppedRecordCount,
                                highWaterMark: state.highWaterMark
                            )
                        }
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
                        let completenessSnapshot = completenessTracker.state.withLock { state in
                            CompletenessSnapshot(
                                droppedRecordCount: state.droppedRecordCount,
                                highWaterMark: state.highWaterMark
                            )
                        }
                        await traceRuntime.record(
                            tag: .performance,
                            body: "performance.trace_queue.completeness",
                            attributes: [
                                "agentstudio.performance.trace_queue.dropped_record.count": .int(
                                    completenessSnapshot.droppedRecordCount
                                ),
                                "agentstudio.performance.trace_queue.high_watermark": .int(
                                    completenessSnapshot.highWaterMark
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

    private func continuationForEnqueue() -> AsyncStream<TraceRequest>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return nil }
        ensureWorkerStartedLocked()
        return continuation
    }

    private func accountForYieldResult(
        _ yieldResult: AsyncStream<TraceRequest>.Continuation.YieldResult
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
            return nil
        @unknown default:
            return nil
        }
    }
}
