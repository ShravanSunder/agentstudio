import Foundation
import Testing
import WebKit

@testable import AgentStudio

@Suite("Bridge product scheme adapter transcript")
struct BridgeProductSchemeAdapterTranscriptTests {
    @Test("shared fixture identity and content observation command branch are frozen")
    func sharedFixtureAndContentObservationBranchAreFrozen() throws {
        // Arrange
        let fixture = try BridgeProductSchemeTranscriptFixture.load()

        // Act
        let command = try fixture.decodeObservationRequest(
            BridgeProductCommandPackage.self,
            named: "content-accepted-sequence-zero"
        )

        // Assert
        #expect(fixture.sha256Hex == BridgeProductSchemeTranscriptFixture.expectedSHA256)
        #expect(fixture.transcriptCount == 27)
        #expect(fixture.observationCaseCount == 16)
        guard case .contentFrameAcknowledgement = command else {
            Issue.record("Content observation did not decode through the V0b command branch")
            return
        }
    }

    @Test("shared Review interest update is valid against the production state codec")
    func sharedReviewInterestUpdateIsValidAgainstProductionStateCodec() throws {
        // Arrange
        let fixture = try BridgeProductSchemeTranscriptFixture.load()
        let updateCommand = try fixture.decodeTranscriptValue(
            BridgeProductControlRequest.self,
            named: "review-selection-demand"
        )
        guard case .subscriptionUpdateBatch(let updateRequest) = updateCommand else {
            Issue.record("Shared Review update did not decode to its required command branch")
            return
        }

        // Act
        let emptyState = BridgeProductSubscriptionState.emptyInterestState(
            for: .reviewMetadata
        )
        let candidateState = try BridgeProductSubscriptionInterestMutation.apply(
            [updateRequest.delta],
            to: emptyState,
            subscriptionKind: .reviewMetadata
        )
        let candidateSHA256 = try candidateState.sha256Hex()

        // Assert
        #expect(try emptyState.sha256Hex() == updateRequest.baseInterestSha256)
        #expect(candidateSHA256 == updateRequest.targetInterestSha256)
    }

    @Test("mixed File and Review streams pace independently with bodyless observations")
    func mixedFileAndReviewStreamsPaceIndependently() async throws {
        // Arrange
        let fixture = try BridgeProductSchemeTranscriptFixture.load()
        let workerOpen = try fixture.decodeTranscriptValue(
            BridgeProductControlRequest.self,
            named: "worker-session-open"
        )
        let harness = try BridgeProductSchemeAdapterTranscriptHarness.make(
            paneSessionId: workerOpen.paneSessionId,
            workerInstanceId: workerOpen.workerInstanceId,
            reviewSourceData: try fixture.subscriptionData(named: "review-source-accepted"),
            fileSourceData: try fixture.subscriptionData(named: "file-source-accepted")
        )
        var retainedReplies: [BridgeProductSchemeReplyWithRoutingTask] = []

        do {
            retainedReplies.append(
                try await startMetadataStreamBlockedOnReview(
                    fixture: fixture,
                    harness: harness
                )
            )
            retainedReplies.append(
                try await startFileContentStream(
                    fixture: fixture,
                    harness: harness
                )
            )
            try await assertContentObservationAndReviewUpdate(
                fixture: fixture,
                harness: harness
            )
        } catch {
            _ = await harness.teardown(
                routingTasks: retainedReplies.map(\.routingTask)
            )
            throw error
        }

        // Assert teardown
        let teardown = await harness.teardown(
            routingTasks: retainedReplies.map(\.routingTask)
        )
        #expect(teardown.revoked)
        #expect(teardown.producerSnapshot.hasZeroResidue)
        #expect(teardown.providerSnapshot.acknowledgedLifecycleCount == 2)
        #expect(teardown.providerSnapshot.metadataRequestCount == 1)
        #expect(teardown.providerSnapshot.contentRequestCount == 1)
        #expect(teardown.providerSnapshot.producerFailureCount == 0)
    }

    private func startMetadataStreamBlockedOnReview(
        fixture: BridgeProductSchemeTranscriptFixture,
        harness: BridgeProductSchemeAdapterTranscriptHarness
    ) async throws -> BridgeProductSchemeReplyWithRoutingTask {
        let openReply = try await routeControl(
            requestName: "worker-session-open",
            expectedResponseName: "worker-session-accepted",
            fixture: fixture,
            harness: harness
        )
        #expect(openReply.response?.statusCode == 200)
        let metadataReply = bridgeProductSchemeReplyWithRoutingTask(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.streamRoute,
                body: try fixture.transcriptValueData(named: "metadata-stream-open")
            )
        )
        do {
            var metadataIterator = metadataReply.stream.makeAsyncIterator()
            let metadataResponseResult = try #require(await metadataIterator.next())
            guard case .response(let metadataResponse) = metadataResponseResult else {
                Issue.record("Metadata stream did not start with a response")
                throw BridgeProductSchemeAdapterTranscriptTestError.unexpectedReplyEvent
            }
            #expect((metadataResponse as? HTTPURLResponse)?.statusCode == 200)
            let metadataFrameResult = try #require(await metadataIterator.next())
            guard case .data(let metadataFrameBytes) = metadataFrameResult else {
                Issue.record("Metadata stream did not emit its opening frame")
                throw BridgeProductSchemeAdapterTranscriptTestError.unexpectedReplyEvent
            }
            let metadataDecoder = try BridgeProductMetadataFrameDecoder()
            let openingMetadataFrames = try metadataDecoder.append(metadataFrameBytes)
            let expectedMetadataFrame = try fixture.decodeTranscriptValue(
                BridgeProductMetadataFrame.self,
                named: "metadata-stream-accepted-sequence-zero"
            )
            #expect(openingMetadataFrames == [expectedMetadataFrame])

            let controlCountBeforeMetadataObservation =
                await harness.provider.snapshot.controlRequestKinds.count
            let metadataObservation = try await collectBridgeProductSchemeReply(
                adapter: harness.adapter,
                request: harness.request(
                    route: BridgeProductWireContract.commandRoute,
                    body: try fixture.observationRequestData(named: "metadata-sequence-zero")
                )
            )
            #expect(metadataObservation.response?.statusCode == 204)
            #expect(metadataObservation.body.isEmpty)
            #expect(metadataObservation.events == [.response])
            #expect(
                await harness.provider.snapshot.controlRequestKinds.count
                    == controlCountBeforeMetadataObservation
            )

            let reviewOpenReply = try await routeControl(
                requestName: "review-subscription-open",
                expectedResponseName: "review-subscription-open-accepted",
                fixture: fixture,
                harness: harness
            )
            #expect(reviewOpenReply.response?.statusCode == 200)
            let blockedReviewFrameResult = try #require(await metadataIterator.next())
            guard case .data(let blockedReviewFrameBytes) = blockedReviewFrameResult else {
                Issue.record("Review subscription did not emit a metadata frame")
                throw BridgeProductSchemeAdapterTranscriptTestError.unexpectedReplyEvent
            }
            let reviewFrames = try metadataDecoder.append(blockedReviewFrameBytes)
            guard case .subscriptionAccepted(let reviewAccepted) = try #require(reviewFrames.first)
            else {
                Issue.record("Review subscription did not emit subscription.accepted")
                throw BridgeProductSchemeAdapterTranscriptTestError.unexpectedMetadataFrame
            }
            #expect(reviewAccepted.frameIdentity.streamSequence == 1)
            #expect(reviewAccepted.subscriptionIdentity.subscriptionKind == .reviewMetadata)
            return metadataReply
        } catch {
            metadataReply.routingTask.cancel()
            await metadataReply.routingTask.value
            throw error
        }
    }

    private func startFileContentStream(
        fixture: BridgeProductSchemeTranscriptFixture,
        harness: BridgeProductSchemeAdapterTranscriptHarness
    ) async throws -> BridgeProductSchemeReplyWithRoutingTask {
        let fileOpenReply = try await routeControl(
            requestName: "file-subscription-open",
            expectedResponseName: "file-subscription-open-accepted",
            fixture: fixture,
            harness: harness
        )
        #expect(fileOpenReply.response?.statusCode == 200)
        let contentReply = bridgeProductSchemeReplyWithRoutingTask(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.contentRoute,
                body: try fixture.transcriptValueData(named: "file-content-open")
            )
        )
        do {
            var contentIterator = contentReply.stream.makeAsyncIterator()
            let contentResponseResult = try #require(await contentIterator.next())
            guard case .response(let contentResponse) = contentResponseResult else {
                Issue.record("Content stream did not start with a response")
                throw BridgeProductSchemeAdapterTranscriptTestError.unexpectedReplyEvent
            }
            #expect((contentResponse as? HTTPURLResponse)?.statusCode == 200)
            let contentFrameResult = try #require(await contentIterator.next())
            guard case .data(let contentFrameBytes) = contentFrameResult else {
                Issue.record("Content stream did not emit its opening frame")
                throw BridgeProductSchemeAdapterTranscriptTestError.unexpectedReplyEvent
            }
            let contentDecoder = try BridgeProductContentFrameDecoder()
            let openingContentFrames = try contentDecoder.append(contentFrameBytes)
            let expectedContentHeader = try fixture.decodeTranscriptValue(
                BridgeProductContentHeader.self,
                named: "file-content-accepted"
            )
            #expect(
                openingContentFrames == [
                    BridgeProductContentFrame(header: expectedContentHeader, payload: Data())
                ]
            )

            let pacedSnapshot = await harness.session.producerSnapshot()
            #expect(pacedSnapshot.activeContentLeaseCount == 1)
            #expect(
                pacedSnapshot.inFlightFrameReceiptCount == 2,
                "Metadata and content must each retain one independently observed frame"
            )
            #expect(pacedSnapshot.pendingFrameWaiterCount == 0)
            return contentReply
        } catch {
            contentReply.routingTask.cancel()
            await contentReply.routingTask.value
            throw error
        }
    }

    private func assertContentObservationAndReviewUpdate(
        fixture: BridgeProductSchemeTranscriptFixture,
        harness: BridgeProductSchemeAdapterTranscriptHarness
    ) async throws {
        let contentObservationBody = try fixture.observationRequestData(
            named: "content-accepted-sequence-zero"
        )
        let unauthorizedBodyStream = BridgeProductObservedBodyInputStream(
            data: contentObservationBody
        )
        let unauthorizedObservation = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.commandRoute,
                body: contentObservationBody,
                capability: "wrong-capability",
                bodyStream: unauthorizedBodyStream
            )
        )
        #expect(unauthorizedObservation.response?.statusCode == 403)
        #expect(unauthorizedObservation.body.isEmpty)
        #expect(unauthorizedBodyStream.readInvocationCount == 0)

        let controlCountBeforeContentObservation =
            await harness.provider.snapshot.controlRequestKinds.count
        let contentObservation = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.commandRoute,
                body: contentObservationBody
            )
        )
        #expect(
            contentObservation.response?.statusCode == 204,
            "Content frame observations must route outside the ordinary control mux"
        )
        #expect(contentObservation.body.isEmpty)
        #expect(contentObservation.events == [.response])

        let contentObservationReplay = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.commandRoute,
                body: contentObservationBody
            )
        )
        #expect(contentObservationReplay.response?.statusCode == 204)
        #expect(contentObservationReplay.body.isEmpty)
        #expect(contentObservationReplay.events == [.response])

        let foreignContentObservation = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.commandRoute,
                body: try fixture.observationRequestData(named: "content-foreign-lease")
            )
        )
        #expect(foreignContentObservation.response?.statusCode == 409)
        #expect(foreignContentObservation.body.isEmpty)
        #expect(foreignContentObservation.events == [.response])
        #expect(
            await harness.provider.snapshot.controlRequestKinds.count
                == controlCountBeforeContentObservation
        )

        let reviewUpdateReply = try await routeControl(
            requestName: "review-selection-demand",
            expectedResponseName: "review-selection-demand-accepted",
            fixture: fixture,
            harness: harness
        )
        #expect(reviewUpdateReply.response?.statusCode == 200)
        #expect(
            await harness.provider.snapshot.controlRequestKinds == [
                "workerSession.open",
                "subscription.open",
                "subscription.open",
                "subscription.updateBatch",
            ]
        )
    }

    private func routeControl(
        requestName: String,
        expectedResponseName: String,
        fixture: BridgeProductSchemeTranscriptFixture,
        harness: BridgeProductSchemeAdapterTranscriptHarness
    ) async throws -> BridgeProductSchemeReplyObservation {
        let observation = try await collectBridgeProductSchemeReply(
            adapter: harness.adapter,
            request: harness.request(
                route: BridgeProductWireContract.commandRoute,
                body: try fixture.transcriptValueData(named: requestName)
            )
        )
        let response = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: observation.body
        )
        let expectedResponse = try fixture.decodeTranscriptValue(
            BridgeProductControlResponse.self,
            named: expectedResponseName
        )
        #expect(response == expectedResponse, Comment(rawValue: requestName))
        return observation
    }
}

enum BridgeProductSchemeAdapterTranscriptTestError: Error {
    case unexpectedMetadataFrame
    case unexpectedReplyEvent
}
