import Foundation
import Testing
import WebKit

@testable import AgentStudio

@Suite("Bridge product scheme adapter")
struct BridgeProductSchemeAdapterTests {
    @Test("only the three canonical routes accept POST application/json")
    func canonicalRoutesMethodsAndMediaTypesAreClosed() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        let canonicalRoutes = [
            BridgeProductWireContract.commandRoute,
            BridgeProductWireContract.streamRoute,
            BridgeProductWireContract.contentRoute,
        ]

        // Act and assert
        #expect(
            canonicalRoutes == [
                "agentstudio://rpc/command",
                "agentstudio://rpc/stream",
                "agentstudio://rpc/content",
            ])
        for route in canonicalRoutes {
            let methodRejection = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: bridgeProductSchemeRequest(
                    route: route,
                    capability: harness.capabilityHeader,
                    method: "GET",
                    body: Data("{}".utf8)
                )
            )
            #expect(methodRejection.response?.statusCode == 405)

            let mediaTypeRejection = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: bridgeProductSchemeRequest(
                    route: route,
                    capability: harness.capabilityHeader,
                    contentType: "application/json-patch+json",
                    body: Data("{}".utf8)
                )
            )
            #expect(mediaTypeRejection.response?.statusCode == 415)

            let preflight = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: bridgeProductSchemeRequest(
                    route: route,
                    capability: nil,
                    method: "OPTIONS"
                )
            )
            #expect(preflight.response?.statusCode == 204)
        }
        for alias in [
            "agentstudio://rpc/command/",
            "agentstudio://rpc/command?request=1",
            "agentstudio://rpc/stream/extra",
            "agentstudio://rpc/content#fragment",
        ] {
            let rejection = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: bridgeProductSchemeRequest(
                    route: alias,
                    capability: harness.capabilityHeader,
                    body: bridgeProductSchemeWorkerOpenBody()
                )
            )
            #expect(rejection.response?.statusCode == 404)
        }
        let accepted = try await harness.openSession(
            contentType: "application/json; charset=UTF-8"
        )
        #expect(accepted.response?.statusCode == 200)
        #expect((await harness.provider.snapshot).controlRequests.count == 1)
    }

    @Test("capability authentication rejects before any body representation is read")
    func capabilityAuthenticationPrecedesBodyAccess() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        let routes = [
            BridgeProductWireContract.commandRoute,
            BridgeProductWireContract.streamRoute,
            BridgeProductWireContract.contentRoute,
        ]

        // Act and assert
        for route in routes {
            let stream = BridgeProductObservedBodyInputStream(
                data: bridgeProductSchemeWorkerOpenBody()
            )
            let rejection = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: bridgeProductSchemeRequest(
                    route: route,
                    capability: "wrong-capability",
                    bodyStream: stream
                )
            )
            #expect(rejection.response?.statusCode == 403)
            #expect(stream.readInvocationCount == 0)
        }
        let missingCapabilityStream = BridgeProductObservedBodyInputStream(
            data: bridgeProductSchemeWorkerOpenBody()
        )
        let missingCapability = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: nil,
                bodyStream: missingCapabilityStream
            )
        )
        #expect(missingCapability.response?.statusCode == 401)
        #expect(missingCapabilityStream.readInvocationCount == 0)
        #expect((await harness.provider.snapshot).controlRequests.isEmpty)
    }

    @Test("actual streamed request bytes accept 256 KiB and reject cap plus one without Content-Length")
    func actualStreamedBodyEnforcesFrozenCapWithoutContentLength() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        let exactBody = bridgeProductSchemePaddedBody(
            bridgeProductSchemeWorkerOpenBody(),
            byteCount: BridgeProductWireContract.maximumRequestBodyBytes
        )
        let exactStream = BridgeProductObservedBodyInputStream(data: exactBody)
        let exactRequest = bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: harness.capabilityHeader,
            bodyStream: exactStream
        )
        #expect(exactRequest.value(forHTTPHeaderField: "Content-Length") == nil)

        // Act
        let accepted = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: exactRequest
        )
        let oversizedBody = exactBody + Data([0x20])
        let oversizedStream = BridgeProductObservedBodyInputStream(data: oversizedBody)
        let rejected = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: harness.capabilityHeader,
                bodyStream: oversizedStream
            )
        )

        // Assert
        #expect(accepted.response?.statusCode == 200)
        #expect(exactStream.readInvocationCount > 0)
        #expect(rejected.response?.statusCode == 413)
        #expect(oversizedStream.readInvocationCount > 0)
        #expect((await harness.provider.snapshot).controlRequests.count == 1)
    }

    @Test("command dispatch receives the strict typed request and exact retry replays provider bytes")
    func commandDispatchIsTypedAndExactReplayIsProviderFree() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        let openBody = bridgeProductSchemeWorkerOpenBody()
        let expectedRequest = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: openBody
        )
        let request = bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: harness.capabilityHeader,
            body: openBody
        )

        // Act
        let first = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: request
        )
        let replay = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: request
        )

        // Assert
        #expect(first.response?.statusCode == 200)
        #expect(replay.response?.statusCode == 200)
        #expect(!first.body.isEmpty)
        #expect(replay.body == first.body)
        let snapshot = await harness.provider.snapshot
        #expect(snapshot.controlRequests == [expectedRequest])
        #expect(snapshot.controlCompletionCount == 1)
    }

    @Test("decoded sequence rejection is a correlated typed request error")
    func decodedControlRejectionReturnsTypedRequestError() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        #expect(try await harness.openSession().response?.statusCode == 200)
        let rejectedRequestBody = bridgeProductSchemeReviewCallBody(requestSequence: 3)

        // Act
        let rejection = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: harness.capabilityHeader,
                body: rejectedRequestBody
            )
        )
        let response = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: rejection.body
        )

        // Assert
        #expect(rejection.response?.statusCode == 200)
        guard case .requestError(let requestError) = response else {
            Issue.record("Expected a typed request.error response")
            return
        }
        #expect(requestError.code == .sequenceConflict)
        #expect(requestError.nextExpectedRequestSequence == 2)
        #expect(requestError.correlation.requestId == "request-call-adapter")
        #expect((await harness.provider.snapshot).controlRequests.count == 1)
    }

    @Test("cancellation before provider dispatch abandons admission and permits retry")
    func preDispatchCancellationAbandonsAdmission() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        let body = bridgeProductSchemeWorkerOpenBody()
        let blockedStream = BridgeProductObservedBodyInputStream(
            data: body,
            blockFirstRead: true
        )
        let blockedRequest = bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: harness.capabilityHeader,
            bodyStream: blockedStream
        )
        let consumer = Task {
            try? await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: blockedRequest
            )
        }
        await blockedStream.waitUntilFirstRead()

        // Act
        consumer.cancel()
        blockedStream.releaseFirstRead()
        _ = await consumer.value
        let retry = try await harness.openSession(body: body)

        // Assert
        #expect(retry.response?.statusCode == 200)
        #expect((await harness.session.snapshot).pendingRequestKind == nil)
        #expect((await harness.provider.snapshot).controlRequests.count == 1)
    }

    @Test("cancellation after provider dispatch finishes and caches the exact response")
    func postDispatchCancellationCannotAbandonReplayState() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make(
            holdFirstControlResponse: true
        )
        let body = bridgeProductSchemeWorkerOpenBody()
        let request = bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: harness.capabilityHeader,
            body: body
        )
        let consumer = Task {
            try? await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: request
            )
        }
        await harness.provider.waitUntilControlStarted(1)

        // Act
        consumer.cancel()
        await harness.provider.releaseHeldControlResponse()
        await harness.provider.waitUntilControlCompleted(1)
        _ = await consumer.value
        let replay = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: request
        )

        // Assert
        #expect(replay.response?.statusCode == 200)
        #expect(!replay.body.isEmpty)
        #expect((await harness.session.snapshot).pendingRequestKind == nil)
        let snapshot = await harness.provider.snapshot
        #expect(snapshot.controlRequests.count == 1)
        #expect(snapshot.controlCompletionCount == 1)
    }

    @Test("metadata and content responses are emitted before their first frame bytes")
    func streamResponsesPrecedeFrameBytes() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make()
        #expect(try await harness.openSession().response?.statusCode == 200)
        let metadataRequest = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-stream-adapter",
            resumeFromStreamSequence: nil
        )
        let contentRequest = try bridgeProductFileContentRequest(
            identitySuffix: "adapter",
            workerDerivationEpoch: 1
        )

        // Act and assert
        for (route, body) in [
            (BridgeProductWireContract.streamRoute, try JSONEncoder().encode(metadataRequest)),
            (BridgeProductWireContract.contentRoute, try JSONEncoder().encode(contentRequest)),
        ] {
            let recorder = BridgeProductSchemeReplyEventRecorder()
            let request = bridgeProductSchemeRequest(
                route: route,
                capability: harness.capabilityHeader,
                body: body
            )
            let consumer = Task {
                do {
                    for try await result in harness.adapter.reply(for: request) {
                        switch result {
                        case .response:
                            await recorder.record(.response)
                        case .data:
                            await recorder.record(.data)
                        @unknown default:
                            break
                        }
                    }
                } catch {
                    // Cancellation is the action under test after the first frame.
                }
            }
            await recorder.waitUntilCount(2)
            consumer.cancel()
            _ = await consumer.value
            #expect(Array((await recorder.snapshot).prefix(2)) == [.response, .data])
            #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        }
        let snapshot = await harness.provider.snapshot
        #expect(snapshot.metadataRequestCount == 1)
        #expect(snapshot.contentRequestCount == 1)
        #expect(snapshot.acknowledgedLifecycleCount == 2)
        #expect(snapshot.producerFailureCount == 0)
    }

    @Test("provider completion without a terminal frame fails instead of clean EOF")
    func missingTerminalFrameFailsTheResponse() async throws {
        // Arrange
        let harness = try BridgeProductSchemeAdapterHarness.make(
            contentReturnsWithoutTerminal: true
        )
        #expect(try await harness.openSession().response?.statusCode == 200)
        let contentRequest = try bridgeProductFileContentRequest(
            identitySuffix: "missing-terminal",
            workerDerivationEpoch: 1
        )

        // Act
        let rejectedAsProtocolFailure: Bool
        do {
            _ = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: bridgeProductSchemeRequest(
                    route: BridgeProductWireContract.contentRoute,
                    capability: harness.capabilityHeader,
                    body: try JSONEncoder().encode(contentRequest)
                )
            )
            rejectedAsProtocolFailure = false
        } catch BridgeProductSchemeAdapterError.frameDeliveryRejected {
            rejectedAsProtocolFailure = true
        } catch {
            rejectedAsProtocolFailure = false
        }

        // Assert
        #expect(rejectedAsProtocolFailure)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        let providerSnapshot = await harness.provider.snapshot
        #expect(providerSnapshot.contentRequestCount == 1)
        #expect(providerSnapshot.acknowledgedLifecycleCount == 1)
    }

    @Test("the off-path adapter is not registered by the live pane or legacy scheme handler")
    func adapterRemainsUnregisteredInLiveBridge() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let liveSources = [
            "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift",
            "Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift",
        ]

        // Act
        let source = try liveSources.map { relativePath in
            try String(
                contentsOf: projectRoot.appending(path: relativePath),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        // Assert
        #expect(!source.contains("BridgeProductSchemeAdapter"))
    }
}
