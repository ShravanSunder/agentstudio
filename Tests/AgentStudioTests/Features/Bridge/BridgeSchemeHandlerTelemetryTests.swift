import Foundation
import Testing
import WebKit

@testable import AgentStudio

@Suite(.serialized)
struct BridgeSchemeHandlerTelemetryTests {
    private actor RecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            _ = receivedAtUnixNano
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            firstRejectedEventName: String?,
            receivedAtUnixNano: UInt64
        ) async {
            _ = reason
            _ = droppedCount
            _ = firstRejectedEventName
            _ = receivedAtUnixNano
        }

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }

        func drain() async throws {}
    }

    @Test
    func telemetryPostRouteAdmitsSingleDecodedBatch() async throws {
        let recorder = RecorderSpy()
        let installation = try BridgeTelemetrySessionInstallation.make(
            enabledScopes: [.web],
            endpointURL: "agentstudio://telemetry/batch",
            policy: .live,
            projector: BridgeTelemetryNativeProjector(recorder: recorder).project
        )
        let owner = BridgePaneTelemetrySessionOwner(initialInstallation: installation)
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            telemetryRecorder: recorder,
            telemetrySessionOwner: owner
        )
        let sample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: BridgeTelemetryPlane.observability.rawValue,
                priority: BridgeTelemetryPriority.bestEffort.rawValue,
                slice: BridgeTelemetrySlice.telemetryDrop.rawValue,
                transport: "scheme",
                extraStrings: [
                    "agentstudio.bridge.telemetry.drop_reason": BridgeTelemetryDropReason.queueSaturated.rawValue,
                    "agentstudio.bridge.telemetry.event_name": "performance.bridge.web.rpc_send",
                    "agentstudio.bridge.telemetry.lane": "warm",
                    "agentstudio.bridge.telemetry.result": "success",
                ],
                extraNumbers: ["agentstudio.bridge.telemetry.dropped_count": 1]
            )
        )
        let batch = BridgeTelemetryBatchRequest(
            telemetrySessionId: installation.bootstrap.telemetrySessionId,
            batchSequence: 1,
            samples: [
                BridgeTelemetryStampedSample(
                    producerId: .main,
                    producerSequence: 1,
                    sample: .optionalEvent(
                        BridgeTelemetryEventCompactSample(
                            timestampMilliseconds: 10,
                            sample: sample
                        )
                    )
                )
            ],
            lossSummaries: []
        )
        var request = URLRequest(url: try #require(URL(string: "agentstudio://telemetry/batch")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            installation.bootstrap.telemetryCapability,
            forHTTPHeaderField: BridgeTelemetryWorkerWireContract.capabilityHeaderName
        )
        request.httpBody = try JSONEncoder().encode(batch)

        var events: [URLSchemeTaskResult] = []
        for try await result in handler.reply(for: request) {
            events.append(result)
        }

        let responseBody = events.compactMap { event -> Data? in
            guard case .data(let data) = event else { return nil }
            return data
        }.first
        let response = try JSONDecoder().decode(
            BridgeTelemetryBatchResponse.self,
            from: try #require(responseBody)
        )

        #expect(events.count == 2)
        #expect(response.type == "accepted")
        #expect(await recorder.samples().map(\.name) == ["performance.bridge.web.telemetry_drop"])
    }

    @Test("wrong capability is rejected before body stream access")
    func wrongCapabilityIsRejectedBeforeBodyStreamAccess() async throws {
        // Arrange
        let fixture = try Self.makeFixture()
        let stream = BridgeProductObservedBodyInputStream(data: Data("not-json".utf8))
        let request = try Self.telemetryRequest(
            capability: "wrong-telemetry-capability-value",
            bodyStream: stream
        )

        // Act
        let reply = try await Self.collectReply(handler: fixture.handler, request: request)

        // Assert
        #expect(reply.statusCode == 403)
        #expect(stream.readInvocationCount == 0)
        #expect(await fixture.recorder.samples().isEmpty)
    }

    @Test("telemetry body admits the exact configured cap and rejects cap plus one")
    func telemetryBodyAdmitsExactConfiguredCapAndRejectsCapPlusOne() async throws {
        // Arrange
        let fixture = try Self.makeFixture()
        let encodedBatch = try Self.encodedDiagnosticBatch(
            installation: fixture.installation,
            batchSequence: 1
        )
        let maximumBytes = BridgeTelemetryWorkerPolicy.live.batchMaxBytes
        let exactBody = bridgeProductSchemePaddedBody(encodedBatch, byteCount: maximumBytes)
        let oversizedBody = bridgeProductSchemePaddedBody(encodedBatch, byteCount: maximumBytes + 1)

        // Act
        let exactReply = try await Self.collectReply(
            handler: fixture.handler,
            request: try Self.telemetryRequest(
                capability: fixture.installation.bootstrap.telemetryCapability,
                body: exactBody
            )
        )
        let oversizedReply = try await Self.collectReply(
            handler: fixture.handler,
            request: try Self.telemetryRequest(
                capability: fixture.installation.bootstrap.telemetryCapability,
                body: oversizedBody
            )
        )

        // Assert
        #expect(exactReply.statusCode == 200)
        let acceptedResponse = try JSONDecoder().decode(
            BridgeTelemetryBatchResponse.self,
            from: try #require(exactReply.body)
        )
        #expect(acceptedResponse.type == "accepted")
        #expect(oversizedReply.statusCode == 413)
        #expect(oversizedReply.body == nil)
    }

    @Test("session replacement rejects the stale capability without reading its body")
    func sessionReplacementRejectsStaleCapabilityWithoutReadingItsBody() async throws {
        // Arrange
        let fixture = try Self.makeFixture()
        let staleCapability = fixture.installation.bootstrap.telemetryCapability
        let replacement = try await fixture.owner.replace(
            enabledScopes: [.web],
            endpointURL: "agentstudio://telemetry/batch",
            policy: .live,
            projector: BridgeTelemetryNativeProjector(recorder: fixture.recorder).project
        )
        let stream = BridgeProductObservedBodyInputStream(data: Data("not-json".utf8))

        // Act
        let staleReply = try await Self.collectReply(
            handler: fixture.handler,
            request: try Self.telemetryRequest(capability: staleCapability, bodyStream: stream)
        )
        let replacementReply = try await Self.collectReply(
            handler: fixture.handler,
            request: try Self.telemetryRequest(
                capability: replacement.bootstrap.telemetryCapability,
                body: try Self.encodedDiagnosticBatch(
                    installation: replacement,
                    batchSequence: 1
                )
            )
        )

        // Assert
        #expect(staleReply.statusCode == 403)
        #expect(stream.readInvocationCount == 0)
        #expect(replacementReply.statusCode == 200)
    }

    private struct Fixture {
        let recorder: RecorderSpy
        let installation: BridgeTelemetrySessionInstallation
        let owner: BridgePaneTelemetrySessionOwner
        let handler: BridgeSchemeHandler
    }

    private struct CollectedReply {
        let statusCode: Int?
        let body: Data?
    }

    private static func makeFixture() throws -> Fixture {
        let recorder = RecorderSpy()
        let installation = try BridgeTelemetrySessionInstallation.make(
            enabledScopes: [.web],
            endpointURL: "agentstudio://telemetry/batch",
            policy: .live,
            projector: BridgeTelemetryNativeProjector(recorder: recorder).project
        )
        let owner = BridgePaneTelemetrySessionOwner(initialInstallation: installation)
        return Fixture(
            recorder: recorder,
            installation: installation,
            owner: owner,
            handler: BridgeSchemeHandler(
                paneId: UUID(),
                telemetryRecorder: recorder,
                telemetrySessionOwner: owner
            )
        )
    }

    private static func encodedDiagnosticBatch(
        installation: BridgeTelemetrySessionInstallation,
        batchSequence: Int
    ) throws -> Data {
        try JSONEncoder().encode(
            BridgeTelemetryBatchRequest(
                telemetrySessionId: installation.bootstrap.telemetrySessionId,
                batchSequence: batchSequence,
                samples: [
                    BridgeTelemetryStampedSample(
                        producerId: .main,
                        producerSequence: 1,
                        sample: .diagnostic(
                            BridgeTelemetryDiagnosticCompactSample(
                                code: .workerQueueDepth,
                                timestampMilliseconds: 10,
                                value: 1
                            )
                        )
                    )
                ],
                lossSummaries: []
            )
        )
    }

    private static func telemetryRequest(
        capability: String,
        body: Data? = nil,
        bodyStream: InputStream? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: try #require(URL(string: "agentstudio://telemetry/batch")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            capability,
            forHTTPHeaderField: BridgeTelemetryWorkerWireContract.capabilityHeaderName
        )
        if let body {
            request.httpBody = body
        }
        if let bodyStream {
            request.httpBodyStream = bodyStream
        }
        return request
    }

    private static func collectReply(
        handler: BridgeSchemeHandler,
        request: URLRequest
    ) async throws -> CollectedReply {
        var statusCode: Int?
        var body: Data?
        for try await event in handler.reply(for: request) {
            switch event {
            case .response(let response):
                statusCode = (response as? HTTPURLResponse)?.statusCode
            case .data(let data):
                body = data
            @unknown default:
                break
            }
        }
        return CollectedReply(statusCode: statusCode, body: body)
    }
}
