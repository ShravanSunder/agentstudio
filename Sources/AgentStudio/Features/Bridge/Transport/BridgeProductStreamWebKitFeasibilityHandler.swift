import Foundation
import WebKit

struct BridgeProductStreamWebKitFeasibilitySchemeHandler: URLSchemeHandler, Sendable {
    let expectedCapability: String
    let workerSource: String
    let oracle: BridgeProductStreamWebKitFeasibilityOracle
    let configuration: BridgeProductStreamWebKitFeasibilityConfiguration

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            let task = Task {
                await route(request, continuation: continuation)
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
    }

    private func route(
        _ request: URLRequest,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        guard let url = request.url,
            url.scheme == "agentstudio",
            url.host() == "s2a"
        else {
            reject(statusCode: 404, url: request.url, continuation: continuation)
            return
        }

        if request.httpMethod == "GET", url.path() == "/index.html" {
            emitPage(url: url, continuation: continuation)
            return
        }
        if request.httpMethod == "OPTIONS" {
            emitResponse(statusCode: 204, url: url, continuation: continuation)
            continuation.finish()
            return
        }
        guard request.httpMethod == BridgeProductWireContract.requestMethod else {
            reject(statusCode: 405, url: url, continuation: continuation)
            return
        }
        guard BridgeProductStreamProbeRequestBody.supports(route: url.path()) else {
            reject(statusCode: 404, url: url, continuation: continuation)
            return
        }

        let admission = BridgeProductStreamWebKitFeasibilityAdmission(
            expectedCapability: expectedCapability,
            maximumRequestBodyBytes: configuration.maximumRequestBodyBytes
        ).admit(request, route: url.path())
        switch admission {
        case .rejected(let observation, let statusCode):
            await oracle.recordRequestAPIObservation(observation)
            emitResponse(statusCode: statusCode, url: url, continuation: continuation)
            continuation.finish()
        case .accepted(let body, let observation):
            await routeAcceptedBody(
                body,
                admissionObservation: observation,
                url: url,
                continuation: continuation
            )
        }
    }

    private func routeAcceptedBody(
        _ body: BridgeProductStreamProbeRequestBody,
        admissionObservation: BridgeWebKitRequestAPIObservation,
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        await oracle.recordRequestAPIObservation(
            admissionObservation.recordingAcceptedBodyProviderCall())
        switch body {
        case .workerStarted:
            await oracle.recordWorkerStartPost()
            emitResponse(statusCode: 204, url: url, continuation: continuation)
            continuation.finish()
        case .streamOpen:
            await runProducerTask(
                producer: .completedStream,
                url: url,
                continuation: continuation
            ) {
                await emitCompletedFramedStream(url: url, continuation: continuation)
            }
        case .cancelStreamOpen:
            await runProducerTask(
                producer: .cancellableStream,
                url: url,
                continuation: continuation
            ) {
                await emitCancellableFramedStream(url: url, continuation: continuation)
            }
        case .nearCap:
            emitResponse(statusCode: 204, url: url, continuation: continuation)
            continuation.finish()
        case .frameObserved(let receipt):
            guard await oracle.recordFrameObserved(receipt) else {
                emitResponse(statusCode: 409, url: url, continuation: continuation)
                continuation.finish()
                return
            }
            emitResponse(statusCode: 204, url: url, continuation: continuation)
            continuation.finish()
        case .result(let result):
            guard await oracle.waitUntilZeroProducerResidue(), !Task.isCancelled else {
                continuation.finish()
                return
            }
            let producerSnapshot = await oracle.snapshot().producers
            guard producerSnapshot.activeProducerCount == 0,
                producerSnapshot.activeProducerTaskCount == 0,
                producerSnapshot.queuedFrameCount == 0,
                producerSnapshot.postTerminalFrameCount == 0
            else {
                emitResponse(statusCode: 409, url: url, continuation: continuation)
                continuation.finish()
                return
            }
            await oracle.recordWorkerResult(
                exactFrames: result.workerObservedExactFrames,
                incrementalFrames: result.workerObservedIncrementalFrames,
                cancellationObserved: result.cancellationObserved,
                nearCapTiming: result.nearCapTiming
            )
            emitResponse(statusCode: 200, url: url, continuation: continuation)
            continuation.finish()
        }
    }

    private func runProducerTask(
        producer: BridgeWebKitFeasibilityProducerKind,
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation,
        operation: @escaping @Sendable () async -> Void
    ) async {
        let startGate = BridgeWebKitFeasibilityCancellationGate()
        let producerTask = Task {
            await startGate.wait()
            guard !Task.isCancelled else { return }
            await operation()
        }
        guard await oracle.registerProducer(producer, task: producerTask) else {
            producerTask.cancel()
            startGate.finish()
            await producerTask.value
            reject(statusCode: 409, url: url, continuation: continuation)
            return
        }
        startGate.finish()
        await withTaskCancellationHandler {
            await producerTask.value
        } onCancel: {
            producerTask.cancel()
        }
        await oracle.finalizeProducerRegistration(
            producer,
            cancelled: producerTask.isCancelled || Task.isCancelled
        )
    }

    private func emitCompletedFramedStream(
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        let producer = BridgeWebKitFeasibilityProducerKind.completedStream
        let fixture: BridgeProductStreamWebKitFeasibilityContentFrames.Fixture
        do {
            fixture = try BridgeProductStreamWebKitFeasibilityContentFrames.makeFixture()
        } catch {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish(throwing: error)
            return
        }
        guard !Task.isCancelled else {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish()
            return
        }
        emitResponse(
            statusCode: 200,
            url: url,
            continuation: continuation,
            contentType: "application/octet-stream",
            contentLength: nil
        )
        for (sequence, frame) in fixture.completedFrames.enumerated() {
            let terminal = sequence == fixture.completedFrames.count - 1
            guard await oracle.enqueueFrame(producer: producer, sequence: sequence, terminal: terminal),
                !Task.isCancelled
            else {
                await oracle.finishProducerWork(producer, cancelled: true)
                continuation.finish()
                return
            }
            continuation.yield(.data(frame))
            guard await oracle.recordFrameYielded(producer: producer, sequence: sequence),
                await oracle.waitUntilFrameObserved(.init(producer: producer, sequence: sequence)),
                !Task.isCancelled
            else {
                await oracle.finishProducerWork(producer, cancelled: true)
                continuation.finish()
                return
            }
        }
        await oracle.recordCompletedStream(firstFrameByteCount: fixture.completedFrames[0].count)
        await oracle.finishProducerWork(producer, cancelled: false)
        continuation.finish()
    }

    private func emitCancellableFramedStream(
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        let producer = BridgeWebKitFeasibilityProducerKind.cancellableStream
        let acceptedFrame: Data
        do {
            acceptedFrame = try BridgeProductStreamWebKitFeasibilityContentFrames.makeFixture().acceptedFrame
        } catch {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish(throwing: error)
            return
        }
        guard !Task.isCancelled else {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish()
            return
        }
        emitResponse(
            statusCode: 200,
            url: url,
            continuation: continuation,
            contentType: "application/octet-stream",
            contentLength: nil
        )
        guard await oracle.enqueueFrame(producer: producer, sequence: 0, terminal: false) else {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish()
            return
        }
        continuation.yield(.data(acceptedFrame))
        guard await oracle.recordFrameYielded(producer: producer, sequence: 0),
            await oracle.waitUntilFrameObserved(.init(producer: producer, sequence: 0)),
            !Task.isCancelled
        else {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish()
            return
        }

        let cancellationGate = BridgeWebKitFeasibilityCancellationGate()
        await withTaskCancellationHandler {
            await cancellationGate.wait()
        } onCancel: {
            cancellationGate.finish()
        }
        guard Task.isCancelled else {
            await oracle.finishProducerWork(producer, cancelled: true)
            continuation.finish()
            return
        }
        await oracle.finishProducerWork(producer, cancelled: true)
    }

    private func emitPage(
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let encodedWorkerSource =
            (try? JSONEncoder().encode(workerSource))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let html = """
            <!doctype html>
            <html>
              <head><title>S2a Ready</title></head>
              <body>
                <script>
                  const bridgeProductStreamWorkerSource = \(encodedWorkerSource);
                  window.runBridgeProductStreamS2aProbe = function(
                    capability,
                    maxRequestBodyBytes,
                    nearCapWarmupRequestCount,
                    nearCapMeasuredRequestCount
                  ) {
                    const workerUrl = URL.createObjectURL(new Blob(
                      [bridgeProductStreamWorkerSource],
                      { type: 'application/javascript' }
                    ));
                    const worker = new Worker(workerUrl);
                    const isProductStreamCompletion = function(message) {
                      if (message === null || typeof message !== 'object') {
                        return false;
                      }
                      const keys = Object.keys(message).sort();
                      return keys.length === 3
                        && keys[0] === 'kind'
                        && keys[1] === 'mode'
                        && keys[2] === 'succeeded'
                        && message.kind === 's2a.completed'
                        && message.mode === 'product-stream-s2a'
                        && typeof message.succeeded === 'boolean';
                    };
                    if (
                      isProductStreamCompletion({ succeeded: true })
                      || isProductStreamCompletion({
                        kind: 's2a.completed',
                        mode: 'product-stream-s2a',
                        succeeded: true,
                        extra: true
                      })
                      || !isProductStreamCompletion({
                        kind: 's2a.completed',
                        mode: 'product-stream-s2a',
                        succeeded: true
                      })
                    ) {
                      document.title = 'S2a Fail';
                      worker.terminate();
                      URL.revokeObjectURL(workerUrl);
                      return;
                    }
                    worker.onmessage = function(event) {
                      document.title = isProductStreamCompletion(event.data)
                        && event.data.succeeded === true
                        ? 'S2a Pass'
                        : 'S2a Fail';
                      worker.terminate();
                      URL.revokeObjectURL(workerUrl);
                    };
                    worker.onerror = function() {
                      document.title = 'S2a Fail';
                      worker.terminate();
                      URL.revokeObjectURL(workerUrl);
                    };
                    worker.postMessage({
                      mode: 'product-stream-s2a',
                      endpointBaseUrl: 'agentstudio://s2a',
                      capability,
                      maxRequestBodyBytes,
                      nearCapWarmupRequestCount,
                      nearCapMeasuredRequestCount
                    });
                  };
                </script>
              </body>
            </html>
            """
        let data = Data(html.utf8)
        emitResponse(
            statusCode: 200,
            url: url,
            continuation: continuation,
            contentType: "text/html; charset=utf-8",
            contentLength: data.count
        )
        continuation.yield(.data(data))
        continuation.finish()
    }

    private func reject(
        statusCode: Int,
        url: URL?,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        guard let url else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing URL"))
            return
        }
        emitResponse(statusCode: statusCode, url: url, continuation: continuation)
        continuation.finish()
    }

    private func emitResponse(
        statusCode: Int,
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation,
        contentType: String = "application/json",
        contentLength: Int? = 0
    ) {
        var headers = [
            "Access-Control-Allow-Headers":
                "Content-Type, \(BridgeProductStreamWebKitFeasibilityPolicy.capabilityHeader)",
            "Access-Control-Allow-Methods": "GET, OPTIONS, POST",
            "Access-Control-Allow-Origin": "*",
            "Content-Type": contentType,
        ]
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }
        let response =
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
            ?? URLResponse(
                url: url,
                mimeType: contentType,
                expectedContentLength: contentLength ?? -1,
                textEncodingName: contentType.hasPrefix("text/") ? "utf-8" : nil
            )
        continuation.yield(.response(response))
    }

}

private final class BridgeWebKitFeasibilityCancellationGate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func wait() async {
        for await _ in stream {}
    }

    func finish() {
        continuation.finish()
    }
}
