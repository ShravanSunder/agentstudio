import Foundation
import Network
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct AgentStudioOTLPBootstrapSmokeTests {
    @Test
    func otelConfigurationAppliesExplicitLogBatchBackpressurePolicy() throws {
        let configuration = try AgentStudioOTLPBootstrapper.otelConfiguration(
            record: AgentStudioOTLPProjectedLogRecord(
                timeUnixNano: 123,
                severityText: .info,
                body: "runtime.otlp.configuration",
                traceID: nil,
                spanID: nil,
                parentSpanID: nil,
                resource: ["service.name": "agentstudio-test"],
                scope: .init(name: "agentstudio-test", version: "test-version"),
                attributes: [:]
            ),
            context: AgentStudioOTLPTraceSinkContext(
                endpoint: #require(URL(string: "http://127.0.0.1:4318")),
                otlpProtocol: .httpProtobuf
            )
        )

        #expect(configuration.logs.batchLogRecordProcessor.maxQueueSize == AppPolicies.Diagnostics.otlpLogMaxQueueSize)
        #expect(
            configuration.logs.batchLogRecordProcessor.maxExportBatchSize
                == AppPolicies.Diagnostics.otlpLogMaxExportBatchSize
        )
    }

    @Test
    func liveOTLPSinkPostsLogRecordToLoopbackHTTPCollector() async throws {
        let collector = try LoopbackOTLPHTTPCollector()
        try await collector.start()
        defer { collector.cancel() }
        let worktreeId = UUID()
        let identityStore = AgentStudioTraceIdentityStore()
        await identityStore.update(
            AgentStudioTraceIdentitySnapshot(
                worktreeIdentitiesByWorktreeId: [
                    worktreeId: AgentStudioTraceWorktreeIdentity(
                        repoHash: "repo-hash-live",
                        worktreeHash: "worktree-hash-live",
                        branch: "feature/otel-live"
                    )
                ]
            )
        )

        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "otlp",
                "AGENTSTUDIO_TRACE_NAME": "live-otlp-smoke",
                "AGENTSTUDIO_TRACE_TAGS": "app.startup,runtime,performance,bridge.performance.webkit",
                "OTEL_EXPORTER_OTLP_ENDPOINT": try collector.endpoint().absoluteString,
            ]),
            processIdentifier: 951,
            serviceVersion: "smoke-version",
            sessionID: "smoke-session",
            sinkFactory: Self.isolatedOTLPSinkFactory(),
            identityStore: identityStore,
            timeUnixNano: { 123_456_789 }
        )

        await runtime.record(
            tag: .appStartup,
            body: "app.process.start"
        )
        await runtime.record(
            tag: .runtime,
            body: "runtime.otlp.smoke",
            attributes: [
                "agentstudio.runtime.event": .string("otlp-smoke"),
                "agentstudio.worktree.id": .string(worktreeId.uuidString),
            ]
        )
        await runtime.record(
            tag: .performance,
            body: "performance.git.status",
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(12.5),
                "agentstudio.performance.git.pending.count": .int(7),
                "agentstudio.performance.git.running.count": .int(3),
            ]
        )
        await runtime.record(
            tag: .bridgePerformanceWebKit,
            body: "performance.bridge.webkit.push_envelope",
            traceID: "11111111111111111111111111111111",
            spanID: "2222222222222222",
            attributes: [
                "agentstudio.bridge.content.byte_size_bucket": .int(100_000),
                "agentstudio.bridge.content.line_count_bucket": .int(500),
                "agentstudio.bridge.phase": .string("transport"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("review_metadata"),
                "agentstudio.bridge.transport": .string("push"),
                "agentstudio.performance.elapsed_ms": .double(8.5),
            ]
        )
        try await runtime.shutdown()

        let request = try #require(
            await collector.waitForRequest(containing: "worktree-hash-live", timeout: .seconds(5))
        )
        #expect(request.method == "POST")
        #expect(request.path.hasSuffix("/v1/logs"))
        #expect(request.bodyByteCount > 0)
        #expect(request.headers["content-type"]?.contains("application/x-protobuf") == true)
        #expect(request.bodyContains("worktree-hash-live"))
        #expect(request.bodyContains("feature/otel-live"))
        #expect(request.bodyContains("live-otlp-smoke"))
        #expect(request.bodyContains("agentstudio.event.time_unix_nano"))

        let metricsRequest = try #require(
            await collector.waitForRequest(containing: "agentstudio_performance_events_total", timeout: .seconds(5))
        )
        #expect(metricsRequest.method == "POST")
        #expect(metricsRequest.path.hasSuffix("/v1/metrics"))
        #expect(metricsRequest.bodyByteCount > 0)
        #expect(metricsRequest.headers["content-type"]?.contains("application/x-protobuf") == true)
        #expect(metricsRequest.bodyContains("performance.git.status"))
        #expect(metricsRequest.bodyContains("agentstudio_performance_event_elapsed_ms"))
        #expect(metricsRequest.bodyContains("agentstudio_performance_git_pending_count"))
        #expect(metricsRequest.bodyContains("review_metadata"))

        try await assertBridgeOTLPTraceRequests(collector)
    }

    private func assertBridgeOTLPTraceRequests(_ collector: LoopbackOTLPHTTPCollector) async throws {
        let bridgeLogRequest = try #require(
            await collector.waitForRequest(
                pathSuffix: "/v1/logs",
                containing: "performance.bridge.webkit.push_envelope",
                timeout: .seconds(5)
            )
        )
        #expect(bridgeLogRequest.bodyContains(hexEncodedBytes: "11111111111111111111111111111111"))

        let bridgeTraceRequest = try #require(
            await collector.waitForRequest(
                pathSuffix: "/v1/traces",
                containing: "performance.bridge.webkit.push_envelope",
                timeout: .seconds(5)
            )
        )
        #expect(bridgeTraceRequest.method == "POST")
        #expect(bridgeTraceRequest.path.hasSuffix("/v1/traces"))
        #expect(bridgeTraceRequest.bodyContains(hexEncodedBytes: "11111111111111111111111111111111"))
        #expect(bridgeTraceRequest.bodyContains(hexEncodedBytes: "2222222222222222"))
    }

    private static func isolatedOTLPSinkFactory() -> AgentStudioTraceSinkFactory {
        let bootstrapper = AgentStudioOTLPBootstrapper()
        return AgentStudioTraceSinkFactory(
            makeJSONLSink: { _ in fatalError("JSONL sink is not used by this OTLP-only smoke") },
            makeOTLPSink: { context in
                AgentStudioOTLPTraceSink(context: context, bootstrapper: bootstrapper)
            }
        )
    }
}

private struct LoopbackOTLPHTTPRequest: Equatable, Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let bodyByteCount: Int
    let body: Data

    func bodyContains(_ value: String) -> Bool {
        let needle = Array(value.utf8)
        guard !needle.isEmpty else { return true }
        return body.indices.contains { index in
            body[index...].starts(with: needle)
        }
    }

    func bodyContains(hexEncodedBytes value: String) -> Bool {
        guard let needle = Data(hexEncoded: value), !needle.isEmpty else { return false }
        return body.indices.contains { index in
            body[index...].starts(with: needle)
        }
    }
}

private final class LoopbackOTLPHTTPCollector: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "agentstudio.tests.otlp-collector")
    private let requestLock = NSLock()
    private var recordedRequests: [LoopbackOTLPHTTPRequest] = []
    private let requestStream: AsyncStream<LoopbackOTLPHTTPRequest>
    private let requestContinuation: AsyncStream<LoopbackOTLPHTTPRequest>.Continuation
    private let readyStream: AsyncStream<Void>
    private let readyContinuation: AsyncStream<Void>.Continuation

    init() throws {
        self.listener = try NWListener(using: .tcp, on: .any)

        var requestContinuation: AsyncStream<LoopbackOTLPHTTPRequest>.Continuation!
        self.requestStream = AsyncStream { continuation in
            requestContinuation = continuation
        }
        self.requestContinuation = requestContinuation

        var readyContinuation: AsyncStream<Void>.Continuation!
        self.readyStream = AsyncStream { continuation in
            readyContinuation = continuation
        }
        self.readyContinuation = readyContinuation
    }

    func endpoint() throws -> URL {
        guard let port = listener.port?.rawValue else {
            throw LoopbackOTLPHTTPCollectorError.missingPort
        }
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    func start() async throws {
        listener.stateUpdateHandler = { [readyContinuation] state in
            switch state {
            case .ready:
                readyContinuation.yield(())
            case .failed:
                readyContinuation.finish()
            case .setup, .waiting, .cancelled:
                break
            @unknown default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        guard await waitForReady(timeout: .seconds(5)) else {
            throw LoopbackOTLPHTTPCollectorError.notReady
        }
    }

    func cancel() {
        listener.cancel()
        requestContinuation.finish()
        readyContinuation.finish()
    }

    func waitForFirstRequest(timeout: Duration) async -> LoopbackOTLPHTTPRequest? {
        if let firstRequest = firstRecordedRequest() {
            return firstRequest
        }

        let clock = ContinuousClock()
        return await withTaskGroup(of: LoopbackOTLPHTTPRequest?.self) { group in
            group.addTask { [requestStream] in
                for await request in requestStream {
                    return request
                }
                return nil
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return nil
                }
                return nil
            }

            let result = await group.next()
            group.cancelAll()
            switch result {
            case .some(.some(let request)):
                return request
            case .some(.none), .none:
                return nil
            }
        }
    }

    func waitForRequest(containing value: String, timeout: Duration) async -> LoopbackOTLPHTTPRequest? {
        if let request = firstRecordedRequest(containing: value) {
            return request
        }

        let clock = ContinuousClock()
        return await withTaskGroup(of: LoopbackOTLPHTTPRequest?.self) { group in
            group.addTask { [requestStream] in
                for await request in requestStream {
                    if request.bodyContains(value) {
                        return request
                    }
                }
                return nil
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return nil
                }
                return nil
            }

            let result = await group.next()
            group.cancelAll()
            switch result {
            case .some(.some(let request)):
                return request
            case .some(.none), .none:
                return nil
            }
        }
    }

    func waitForRequest(
        pathSuffix: String,
        containing value: String,
        timeout: Duration
    ) async -> LoopbackOTLPHTTPRequest? {
        if let request = firstRecordedRequest(pathSuffix: pathSuffix, containing: value) {
            return request
        }

        let clock = ContinuousClock()
        return await withTaskGroup(of: LoopbackOTLPHTTPRequest?.self) { group in
            group.addTask { [requestStream] in
                for await request in requestStream {
                    if request.path.hasSuffix(pathSuffix), request.bodyContains(value) {
                        return request
                    }
                }
                return nil
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return nil
                }
                return nil
            }

            let result = await group.next()
            group.cancelAll()
            switch result {
            case .some(.some(let request)):
                return request
            case .some(.none), .none:
                return nil
            }
        }
    }

    private func waitForReady(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { [readyStream] in
                for await _ in readyStream {
                    return true
                }
                return false
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return false
                }
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536,
            completion: receiveHandler(on: connection, buffer: buffer)
        )
    }

    private func receiveHandler(
        on connection: NWConnection,
        buffer: Data
    ) -> @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void {
        { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
            }

            if let request = Self.parseRequest(nextBuffer) {
                self.record(request)
                self.sendOK(on: connection)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func sendOK(on connection: NWConnection) {
        let response = Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(
            content: response,
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }

    private func record(_ request: LoopbackOTLPHTTPRequest) {
        requestLock.lock()
        recordedRequests.append(request)
        requestLock.unlock()
        requestContinuation.yield(request)
    }

    private func firstRecordedRequest() -> LoopbackOTLPHTTPRequest? {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedRequests.first
    }

    private func firstRecordedRequest(containing value: String) -> LoopbackOTLPHTTPRequest? {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedRequests.first { $0.bodyContains(value) }
    }

    private func firstRecordedRequest(pathSuffix: String, containing value: String) -> LoopbackOTLPHTTPRequest? {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedRequests.first { request in
            request.path.hasSuffix(pathSuffix) && request.bodyContains(value)
        }
    }

    private static func parseRequest(_ data: Data) -> LoopbackOTLPHTTPRequest? {
        let headerTerminator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: headerTerminator) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let expectedBodyLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyData = data[headerRange.upperBound...]
        guard bodyData.count >= expectedBodyLength else { return nil }

        return LoopbackOTLPHTTPRequest(
            method: requestParts[0],
            path: requestParts[1],
            headers: headers,
            bodyByteCount: expectedBodyLength,
            body: Data(bodyData.prefix(expectedBodyLength))
        )
    }
}

private enum LoopbackOTLPHTTPCollectorError: Error {
    case missingPort
    case notReady
}

extension Data {
    fileprivate init?(hexEncoded value: String) {
        guard value.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)

        var currentIndex = value.startIndex
        while currentIndex < value.endIndex {
            let nextIndex = value.index(currentIndex, offsetBy: 2)
            guard let byte = UInt8(value[currentIndex..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            currentIndex = nextIndex
        }

        self.init(bytes)
    }
}
