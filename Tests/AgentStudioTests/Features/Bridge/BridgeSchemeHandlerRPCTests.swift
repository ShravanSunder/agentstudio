import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeSchemeHandlerRPCTests {
    @Test
    func productReplyUsesOnePhysicalResponseContinuationWithoutNestedRelay() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let relaySource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler+RPC.swift"
            ),
            encoding: .utf8
        )
        let adapterSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSchemeAdapter.swift"
            ),
            encoding: .utf8
        )

        // Act
        let relaysAdapterSequence = relaySource.contains(
            "for try await result in transportClaim.adapter.reply(for: request)"
        )
        let adapterCreatesNestedReplyChannel = adapterSource.contains(
            "BridgeProductURLSchemeReplyChannel<URLSchemeTaskResult>()"
        )

        // Assert
        #expect(!relaysAdapterSequence)
        #expect(!adapterCreatesNestedReplyChannel)
        #expect(
            relaySource.contains(
                "transportClaim.adapter.route(request, continuation: continuation)"
            )
        )
    }

    @Test
    func productRoutesAreTheOnlyRPCPostRoutes() {
        // Arrange
        let productRoutes = [
            BridgeProductWireContract.commandRoute,
            BridgeProductWireContract.streamRoute,
            BridgeProductWireContract.contentRoute,
        ]

        // Act and assert
        for productRoute in productRoutes {
            let classification = BridgeSchemeHandler.classifyPath(productRoute)

            #expect(classification == .product)
            #expect(classification.supportsPostRequests)
        }
        #expect(BridgeSchemeHandler.classifyPath("agentstudio://rpc/legacy") == .invalid)
    }

    @Test
    func productCommandRouteUsesOnlyTheActiveSessionInstallation() async throws {
        // Arrange
        let paneSessionId = "pane-session-scheme-handler"
        let provider = BridgeProductSchemeProviderSpy(
            holdFirstControlResponse: false,
            contentReturnsWithoutTerminal: false
        )
        let installation = try BridgeProductSessionInstallation.make(
            paneSessionId: paneSessionId,
            provider: provider
        )
        let router = BridgeProductSchemeSessionRouter(activeInstallation: installation)
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            productSessionRouter: router
        )
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        )
        let requestBody = try JSONSerialization.data(
            withJSONObject: [
                "kind": "workerSession.open",
                "paneSessionId": paneSessionId,
                "request": NSNull(),
                "requestId": "request-open-scheme-handler",
                "requestSequence": 1,
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
        let request = bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: capabilityHeader,
            body: requestBody
        )

        // Act
        let activeReply = try await collectBridgeSchemeHandlerReply(
            handler: handler,
            request: request
        )
        await router.clear()
        let inactiveRouteReason = await collectBridgeSchemeHandlerRouteFailure(
            handler: handler,
            request: request
        )

        // Assert
        #expect(activeReply.response?.statusCode == 200)
        #expect(activeReply.response?.mimeType == "application/json")
        #expect(
            activeReply.response?.value(forHTTPHeaderField: "Access-Control-Allow-Methods")
                == "OPTIONS, POST"
        )
        let response = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: activeReply.body
        )
        guard case .workerSessionAccepted(let accepted) = response else {
            Issue.record("Expected a typed workerSession.accepted response")
            return
        }
        #expect(accepted.correlation.paneSessionId == paneSessionId)
        #expect(accepted.correlation.workerInstanceId == installation.bootstrap.workerInstanceId)
        #expect((await provider.snapshot).controlRequests.count == 1)
        #expect(inactiveRouteReason == "product-session-unavailable")
    }

    @Test
    func productMetadataRouteDeliversLaterFramesAndRetiresAfterCancellation() async throws {
        // Arrange
        let paneSessionId = "pane-session-scheme-handler-metadata"
        let provider = BridgeProductSchemeProviderSpy(
            holdFirstControlResponse: false,
            contentReturnsWithoutTerminal: false,
            metadataProgressFrameCount: 2
        )
        let installation = try BridgeProductSessionInstallation.make(
            paneSessionId: paneSessionId,
            provider: provider
        )
        let router = BridgeProductSchemeSessionRouter(activeInstallation: installation)
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            productSessionRouter: router
        )
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        )
        let openBody = try JSONSerialization.data(
            withJSONObject: [
                "kind": "workerSession.open",
                "paneSessionId": paneSessionId,
                "request": NSNull(),
                "requestId": "request-open-scheme-handler-metadata",
                "requestSequence": 1,
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
        let openReply = try await collectBridgeSchemeHandlerReply(
            handler: handler,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: capabilityHeader,
                body: openBody
            )
        )
        #expect(openReply.response?.statusCode == 200)
        let metadataBody = try JSONSerialization.data(
            withJSONObject: [
                "kind": "metadataStream.open",
                "metadataStreamId": "metadata-stream-scheme-handler",
                "paneSessionId": paneSessionId,
                "resumeFromStreamSequence": NSNull(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
        let metadataRequest = bridgeProductSchemeRequest(
            route: BridgeProductWireContract.streamRoute,
            capability: capabilityHeader,
            body: metadataBody
        )
        let recorder = BridgeProductSchemeReplyEventRecorder()

        // Act
        let consumer = Task {
            do {
                for try await result in handler.reply(for: metadataRequest) {
                    switch result {
                    case .response:
                        await recorder.record(.response)
                    case .data:
                        await recorder.record(.data)
                    @unknown default:
                        Issue.record("Unexpected URL scheme task result")
                    }
                }
            } catch is CancellationError {
                // Cancellation is the action under test after all later frames arrive.
            } catch {
                Issue.record("Unexpected metadata reply failure: \(error)")
            }
        }
        await recorder.waitUntilCount(4)
        consumer.cancel()
        _ = await consumer.value
        await router.waitForDrain()
        await provider.waitUntilAcknowledgedLifecycleCount(1)

        // Assert
        #expect(await recorder.snapshot == [.response, .data, .data, .data])
        #expect((await installation.session.producerSnapshot()).hasZeroResidue)
        #expect((await router.snapshot).hasZeroResidue)
        let providerSnapshot = await provider.snapshot
        #expect(providerSnapshot.metadataRequestCount == 1)
        #expect(providerSnapshot.acknowledgedLifecycleCount == 1)
        #expect(providerSnapshot.producerFailureCount == 0)
    }

    @Test
    func productPreflightUsesCapabilityAwareAdapterHeaders() async throws {
        // Arrange
        let provider = BridgeProductSchemeProviderSpy(
            holdFirstControlResponse: false,
            contentReturnsWithoutTerminal: false
        )
        let installation = try BridgeProductSessionInstallation.make(
            paneSessionId: "pane-session-product-preflight",
            provider: provider
        )
        let router = BridgeProductSchemeSessionRouter(
            activeInstallation: installation
        )
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            productSessionRouter: router
        )
        var request = URLRequest(
            url: try #require(URL(string: BridgeProductWireContract.commandRoute))
        )
        request.httpMethod = "OPTIONS"

        // Act
        let reply = try await collectBridgeSchemeHandlerReply(
            handler: handler,
            request: request
        )
        await router.clear()
        let inactiveRouteReason = await collectBridgeSchemeHandlerRouteFailure(
            handler: handler,
            request: request
        )

        // Assert
        #expect(reply.response?.statusCode == 204)
        #expect(
            reply.response?.value(forHTTPHeaderField: "Access-Control-Allow-Headers")
                == "Content-Type, \(BridgeProductWireContract.capabilityHeaderName)"
        )
        #expect(
            reply.response?.value(forHTTPHeaderField: "Access-Control-Allow-Methods")
                == "OPTIONS, POST"
        )
        #expect(reply.body.isEmpty)
        #expect(inactiveRouteReason == "product-session-unavailable")
    }
}

private func collectBridgeSchemeHandlerReply(
    handler: BridgeSchemeHandler,
    request: URLRequest
) async throws -> BridgeProductSchemeReplyObservation {
    var body = Data()
    var events: [BridgeProductSchemeReplyObservation.Event] = []
    var response: HTTPURLResponse?
    for try await result in handler.reply(for: request) {
        switch result {
        case .response(let emittedResponse):
            events.append(.response)
            response = emittedResponse as? HTTPURLResponse
        case .data(let chunk):
            events.append(.data)
            body.append(chunk)
        @unknown default:
            Issue.record("Unexpected URL scheme task result")
        }
    }
    return .init(body: body, events: events, response: response)
}

private func collectBridgeSchemeHandlerRouteFailure(
    handler: BridgeSchemeHandler,
    request: URLRequest
) async -> String? {
    do {
        for try await _ in handler.reply(for: request) {}
        return nil
    } catch BridgeSchemeError.invalidRoute(let reason) {
        return reason
    } catch {
        Issue.record("Expected an invalid product-session route, received \(error)")
        return nil
    }
}
