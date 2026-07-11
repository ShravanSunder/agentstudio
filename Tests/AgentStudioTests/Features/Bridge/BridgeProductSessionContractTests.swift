import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductSessionContractTests {
    @Test("product transport vocabulary and ceilings are fixed")
    func productTransportVocabularyAndCeilingsAreFixed() {
        #expect(BridgeProductWireContract.requestMethod == "POST")
        #expect(BridgeProductWireContract.commandRoute == "agentstudio://rpc/command")
        #expect(BridgeProductWireContract.streamRoute == "agentstudio://rpc/stream")
        #expect(BridgeProductWireContract.contentRoute == "agentstudio://rpc/content")
        #expect(
            BridgeProductWireContract.capabilityHeaderName
                == "X-AgentStudio-Bridge-Product-Capability")
        #expect(BridgeProductWireContract.maximumRequestBodyBytes == 256 * 1024)
        #expect(BridgeProductWireContract.maximumContentFrameBytes == 256 * 1024)
        #expect(BridgeProductWireContract.maximumContentDataPayloadBytes == 128 * 1024)
    }

    @Test("shared product-session corpus decodes and round-trips every v2 union")
    func sharedProductSessionCorpusDecodesAndRoundTripsEveryV2Union() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )

        #expect(try #require(corpus["wireVersion"] as? Int) == BridgeProductWireContract.version)
        let bootstrapObject = try #require(corpus["bootstrap"] as? [String: Any])
        let bootstrap = try #require(
            decodeAndVerifyRoundTrips(BridgeProductSessionBootstrap.self, from: [bootstrapObject]).first
        )
        let controlRequests = try decodeAndVerifyRoundTrips(
            BridgeProductControlRequest.self,
            from: try fixtureArray(named: "controlRequests", in: corpus)
        )
        let controlResponses = try decodeAndVerifyRoundTrips(
            BridgeProductControlResponse.self,
            from: try fixtureArray(named: "controlResponses", in: corpus)
        )
        _ = try decodeAndVerifyRoundTrips(
            BridgeProductMetadataStreamRequest.self,
            from: try fixtureArray(named: "metadataStreamRequests", in: corpus)
        )
        let metadataFrames = try decodeAndVerifyRoundTrips(
            BridgeProductMetadataFrame.self,
            from: try fixtureArray(named: "metadataFrames", in: corpus)
        )
        let contentRequests = try decodeAndVerifyRoundTrips(
            BridgeProductContentRequest.self,
            from: try fixtureArray(named: "contentRequests", in: corpus)
        )
        let contentHeaders = try decodeAndVerifyRoundTrips(
            BridgeProductContentHeader.self,
            from: try fixtureArray(named: "contentHeaders", in: corpus)
        )

        #expect(
            Set(controlRequests.map(\.kind)) == [
                "workerSession.open",
                "product.call",
                "subscription.open",
                "subscription.updateBatch",
                "subscription.cancel",
                "workerSession.resync",
            ])
        #expect(
            Set(controlResponses.map(\.kind)) == [
                "workerSession.accepted",
                "call.completed",
                "subscription.openAccepted",
                "subscription.updateBatchAccepted",
                "subscription.cancelAccepted",
                "resync.accepted",
                "request.error",
            ])
        #expect(
            Set(metadataFrames.map(\.kind)) == [
                "metadataStream.accepted",
                "subscription.accepted",
                "subscription.interestsCommitted",
                "subscription.data",
                "subscription.reset",
                "subscription.end",
                "subscription.cancelled",
                "content.cancelled",
                "metadataStream.error",
            ])
        #expect(contentRequests.map(\.kind) == ["content.open"])
        #expect(
            Set(contentHeaders.map(\.kind)) == [
                "content.accepted",
                "content.data",
                "content.end",
                "content.error",
                "content.reset",
            ])
        #expect(bootstrap.paneSessionId == "pane-session-1")

        for capabilityCase in try fixtureArray(named: "capabilityHeaderCases", in: corpus) {
            let byteValues = try #require(capabilityCase["bytes"] as? [Int])
            let capabilityBytes = try byteValues.map { try #require(UInt8(exactly: $0)) }
            let expectedHeader = try #require(capabilityCase["encoded"] as? String)
            #expect(try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes) == expectedHeader)
            #expect(!expectedHeader.contains("+"))
            #expect(!expectedHeader.contains("/"))
            #expect(!expectedHeader.contains("="))
        }
    }

    @Test("pane-scoped product boundaries reject global worker epoch fields")
    func paneScopedBoundariesRejectGlobalWorkerEpochFields() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let controlRequests = try fixtureArray(named: "controlRequests", in: corpus)
        let paneRequestKinds = ["workerSession.open", "workerSession.resync"]

        for requestKind in paneRequestKinds {
            var request = try #require(
                controlRequests.first { $0["kind"] as? String == requestKind }
            )
            if requestKind == "workerSession.resync" {
                let activeSubscriptions = try #require(
                    request["activeSubscriptions"] as? [[String: Any]]
                )
                request["activeSubscriptions"] = activeSubscriptions.map { subscription in
                    var canonicalSubscription = subscription
                    canonicalSubscription["workerDerivationEpoch"] = 3
                    return canonicalSubscription
                }
            }
            verifyPaneScopedEpochContract(BridgeProductControlRequest.self, object: request)
        }
        for response in try fixtureArray(named: "controlResponses", in: corpus) {
            verifyPaneScopedEpochContract(BridgeProductControlResponse.self, object: response)
        }
        for streamRequest in try fixtureArray(named: "metadataStreamRequests", in: corpus) {
            verifyPaneScopedEpochContract(BridgeProductMetadataStreamRequest.self, object: streamRequest)
        }
    }

    @Test("surface requests require derivation epoch and derive surface from closed kind")
    func surfaceRequestsRequireDerivationEpochAndDeriveSurfaceFromKind() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let controlRequests = try fixtureArray(named: "controlRequests", in: corpus)
        let surfaceRequestKinds = [
            "product.call",
            "subscription.open",
            "subscription.updateBatch",
            "subscription.cancel",
        ]

        for requestKind in surfaceRequestKinds {
            let matchingRequests = controlRequests.filter { $0["kind"] as? String == requestKind }
            #expect(!matchingRequests.isEmpty)
            for request in matchingRequests {
                #expect(expectedSurfaceForControlRequest(request) != nil)
                verifySurfaceScopedEpochContract(BridgeProductControlRequest.self, object: request)
            }
        }

        let contentRequest = try #require(
            fixtureArray(named: "contentRequests", in: corpus).first
        )
        #expect(contentRequest["contentKind"] as? String == "file.content")
        verifySurfaceScopedEpochContract(BridgeProductContentRequest.self, object: contentRequest)
    }

    @Test("resync carries independent surface epochs and rejects same-surface disagreement")
    func resyncCarriesIndependentSurfaceEpochs() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let requests = try fixtureArray(named: "controlRequests", in: corpus)
        var resync = try #require(requests.first { $0["kind"] as? String == "workerSession.resync" })
        resync.removeValue(forKey: "workerEpoch")
        resync.removeValue(forKey: "workerDerivationEpoch")
        let reviewSubscription = try #require(
            (resync["activeSubscriptions"] as? [[String: Any]])?.first
        )
        var review = reviewSubscription
        review["workerDerivationEpoch"] = 41
        var file = reviewSubscription
        file["subscriptionId"] = "file-subscription-1"
        file["subscriptionKind"] = "file.metadata"
        file["interestSha256"] =
            "51ce8b03041697e18e2a24d5311e14bb1df4da119635bb84246c1b047316e46b"
        file["workerDerivationEpoch"] = 73
        resync["activeSubscriptions"] = [review, file]

        let decoded = decodedValue(BridgeProductControlRequest.self, object: resync)
        #expect(decoded != nil)
        if let decoded {
            let encoded = try encodedJSONObject(decoded)
            let activeSubscriptions = try #require(
                encoded["activeSubscriptions"] as? [[String: Any]]
            )
            #expect(
                activeSubscriptions.compactMap { $0["workerDerivationEpoch"] as? Int }
                    == [41, 73]
            )
            #expect(encoded["workerEpoch"] == nil)
            #expect(encoded["workerDerivationEpoch"] == nil)
        }

        var conflictingReview = review
        conflictingReview["subscriptionId"] = "review-subscription-2"
        conflictingReview["workerDerivationEpoch"] = 42
        var conflictingResync = resync
        conflictingResync["activeSubscriptions"] = [review, conflictingReview, file]
        #expect(decodingFails(BridgeProductControlRequest.self, object: conflictingResync))

        var globalEpochResync = resync
        globalEpochResync["workerDerivationEpoch"] = 73
        #expect(decodingFails(BridgeProductControlRequest.self, object: globalEpochResync))
    }

    @Test("resumable cursors reserve accepted and terminal successor sequences")
    func resumableStreamCursorsStopBeforeMaximumSafeInteger() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let controlRequests = try fixtureArray(named: "controlRequests", in: corpus)
        let controlResponses = try fixtureArray(named: "controlResponses", in: corpus)
        let metadataStreamRequests = try fixtureArray(named: "metadataStreamRequests", in: corpus)
        let resumableStreamSequence = BridgeProductWireContract.maximumResumableStreamSequence
        let firstNonresumableStreamSequence = resumableStreamSequence + 1

        var resyncRequest = try #require(
            controlRequests.first { $0["kind"] as? String == "workerSession.resync" }
        )
        resyncRequest["lastAcceptedRequestSequence"] =
            BridgeProductWireContract.maximumControlRequestSequence - 1
        resyncRequest["requestSequence"] = BridgeProductWireContract.maximumControlRequestSequence
        #expect(!decodingFails(BridgeProductControlRequest.self, object: resyncRequest))
        resyncRequest["lastAcceptedRequestSequence"] =
            BridgeProductWireContract.maximumControlRequestSequence
        resyncRequest["requestSequence"] = BridgeProductWireContract.maximumSafeInteger
        #expect(decodingFails(BridgeProductControlRequest.self, object: resyncRequest))

        resyncRequest = try #require(
            controlRequests.first { $0["kind"] as? String == "workerSession.resync" }
        )
        resyncRequest["lastAcceptedStreamSequence"] = resumableStreamSequence
        #expect(!decodingFails(BridgeProductControlRequest.self, object: resyncRequest))
        resyncRequest["lastAcceptedStreamSequence"] = firstNonresumableStreamSequence
        #expect(decodingFails(BridgeProductControlRequest.self, object: resyncRequest))

        var resyncAccepted = try #require(
            controlResponses.first { $0["kind"] as? String == "resync.accepted" }
        )
        resyncAccepted["resumeFromStreamSequence"] = resumableStreamSequence
        #expect(!decodingFails(BridgeProductControlResponse.self, object: resyncAccepted))
        resyncAccepted["resumeFromStreamSequence"] = firstNonresumableStreamSequence
        #expect(decodingFails(BridgeProductControlResponse.self, object: resyncAccepted))

        var metadataStreamRequest = try #require(metadataStreamRequests.first)
        metadataStreamRequest["resumeFromStreamSequence"] = resumableStreamSequence
        #expect(!decodingFails(BridgeProductMetadataStreamRequest.self, object: metadataStreamRequest))
        metadataStreamRequest["resumeFromStreamSequence"] = firstNonresumableStreamSequence
        #expect(decodingFails(BridgeProductMetadataStreamRequest.self, object: metadataStreamRequest))
    }

    @Test("shared interest-state vectors have byte-for-byte and SHA-256 parity")
    func sharedInterestStateVectorsHaveByteAndDigestParity() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let vectors = try fixtureArray(named: "interestStateVectors", in: corpus)

        for vector in vectors {
            let stateObject = try #require(vector["state"] as? [String: Any])
            let stateData = try JSONSerialization.data(withJSONObject: stateObject, options: [.sortedKeys])
            let state = try JSONDecoder().decode(BridgeProductSubscriptionInterestState.self, from: stateData)
            let expectedBytes = try decodedBase64(named: "encodedBase64", in: vector)
            let expectedSha256 = try #require(vector["sha256"] as? String)

            #expect(try state.encodedData() == expectedBytes)
            #expect(try state.sha256Hex() == expectedSha256)
        }
    }

    @Test("interest-state JSON rejects lone surrogates and accepts valid scalar pairs")
    func interestStateJSONRequiresUnicodeScalarValues() throws {
        let firstLoneSurrogate =
            #"{"interests":[{"lane":"foreground","paths":["\uD800"]}],"pathScope":[],"subscriptionKind":"file.metadata"}"#
        let secondLoneSurrogate =
            #"{"interests":[{"lane":"foreground","paths":["\uDBFF"]}],"pathScope":[],"subscriptionKind":"file.metadata"}"#
        let loneTrailingSurrogate =
            #"{"interests":[{"lane":"foreground","paths":["\uDFFF"]}],"pathScope":[],"subscriptionKind":"file.metadata"}"#
        let validScalarPair =
            #"{"interests":[{"lane":"foreground","paths":["\uD83D\uDE80"]}],"pathScope":[],"subscriptionKind":"file.metadata"}"#

        #expect(
            decodingFails(
                BridgeProductSubscriptionInterestState.self,
                data: Data(firstLoneSurrogate.utf8)
            )
        )
        #expect(
            decodingFails(
                BridgeProductSubscriptionInterestState.self,
                data: Data(secondLoneSurrogate.utf8)
            )
        )
        #expect(
            decodingFails(
                BridgeProductSubscriptionInterestState.self,
                data: Data(loneTrailingSurrogate.utf8)
            )
        )
        _ = try JSONDecoder().decode(
            BridgeProductSubscriptionInterestState.self,
            from: Data(validScalarPair.utf8)
        )
    }

    @Test("interest state and deltas compare path members by exact UTF-8 identity")
    func interestStateAndDeltasUseExactUTF8PathIdentity() throws {
        let composedPath = "src/\u{00e9}.swift"
        let decomposedPath = "src/e\u{0301}.swift"
        let interestStateJSON =
            #"{"interests":[{"lane":"foreground","paths":["src/\u00e9.swift","src/e\u0301.swift"]}],"pathScope":["scope/\u00e9","scope/e\u0301"],"subscriptionKind":"file.metadata"}"#
        let deltaJSON =
            #"{"add":[{"lane":"foreground","path":"src/\u00e9.swift"}],"addPathScope":["scope/\u00e9"],"removePathScope":["scope/e\u0301"],"removePaths":["src/e\u0301.swift"],"subscriptionKind":"file.metadata"}"#

        #expect(composedPath == decomposedPath)
        #expect(Data(composedPath.utf8) != Data(decomposedPath.utf8))
        let interestState = try JSONDecoder().decode(
            BridgeProductSubscriptionInterestState.self,
            from: Data(interestStateJSON.utf8)
        )
        _ = try interestState.encodedData()
        _ = try JSONDecoder().decode(
            BridgeProductFileMetadataInterestDelta.self,
            from: Data(deltaJSON.utf8)
        )
    }

    @Test("review interest state and deltas compare item IDs by exact UTF-8 identity")
    func reviewInterestStateAndDeltasUseExactUTF8ItemIdentity() throws {
        let composedItemId = "review-\u{00e9}"
        let decomposedItemId = "review-e\u{0301}"
        let interestStateJSON =
            #"{"interests":[{"itemIds":["review-\u00e9","review-e\u0301"],"lane":"foreground"}],"subscriptionKind":"review.metadata"}"#
        let deltaJSON =
            #"{"add":[{"itemId":"review-\u00e9","lane":"foreground"}],"removeItemIds":["review-e\u0301"],"subscriptionKind":"review.metadata"}"#

        #expect(composedItemId == decomposedItemId)
        #expect(Data(composedItemId.utf8) != Data(decomposedItemId.utf8))
        let interestState = try JSONDecoder().decode(
            BridgeProductSubscriptionInterestState.self,
            from: Data(interestStateJSON.utf8)
        )
        _ = try interestState.encodedData()
        _ = try JSONDecoder().decode(
            BridgeProductReviewMetadataInterestDelta.self,
            from: Data(deltaJSON.utf8)
        )
    }

    @Test("canonical interest state accepts exactly 256 KiB and rejects the next byte")
    func canonicalInterestStateHasExactAggregateByteCeiling() throws {
        let maximumState = try decodeBoundaryFileInterestState(finalPathByteLength: 49)

        #expect(BridgeProductWireContract.maximumSubscriptionInterestStateBytes == 256 * 1024)
        #expect(
            maximumState.canonicalEncodingPreflight()
                == .accepted(canonicalByteCount: 256 * 1024, visitedTextValueCount: 65)
        )
        #expect(try maximumState.encodedData().count == 256 * 1024)
        #expect(throws: (any Error).self) {
            _ = try decodeBoundaryFileInterestState(finalPathByteLength: 50)
        }
    }

    @Test("interest-state preflight stops before retaining the theoretical 82,010,010 bytes")
    func maximumFileInterestStatePreflightStopsAtTheByteCeiling() throws {
        let maximumLengthPath = String(repeating: "x", count: 4096)
        let maximumCountPaths = Array(repeating: maximumLengthPath, count: 10_000)
        let interest = try BridgeProductFileMetadataInterestStateGroup(
            lane: .foreground,
            paths: maximumCountPaths
        )
        let state = BridgeProductSubscriptionInterestState.fileMetadata(
            interests: [interest],
            pathScope: maximumCountPaths
        )
        let theoreticalCanonicalByteCount =
            10 + 10_000 * (5 + maximumLengthPath.utf8.count)
            + 10_000 * (4 + maximumLengthPath.utf8.count)

        #expect(theoreticalCanonicalByteCount == 82_010_010)
        #expect(
            state.canonicalEncodingPreflight()
                == .exceedsMaximum(
                    canonicalByteCountLowerBound: 262_474,
                    maximumCanonicalByteCount: 256 * 1024,
                    visitedTextValueCount: 64
                )
        )
        #expect(throws: (any Error).self) {
            try state.validateForCanonicalEncoding()
        }
        #expect(throws: (any Error).self) {
            try state.encodedData()
        }
    }

    @Test("shared TypeScript wire vectors decode incrementally in Swift")
    func sharedTypeScriptWireVectorsDecodeIncrementallyInSwift() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let wireVectors = try #require(corpus["wireVectors"] as? [String: Any])

        let metadataVector = try #require(wireVectors["metadataAccepted"] as? [String: Any])
        let metadataBytes = try decodedBase64(named: "encodedBase64", in: metadataVector)
        let metadataDecoder = try BridgeProductMetadataFrameDecoder()
        var metadataFrames: [BridgeProductMetadataFrame] = []
        for byte in metadataBytes {
            metadataFrames.append(contentsOf: try metadataDecoder.append(Data([byte])))
        }
        try metadataDecoder.finish()
        #expect(metadataFrames.map(\.kind) == ["metadataStream.accepted"])

        let contentDataVector = try #require(wireVectors["contentData"] as? [String: Any])
        let contentStreamVector = try #require(wireVectors["contentStream"] as? [String: Any])
        let expectedDataFrame = try decodedBase64(named: "encodedBase64", in: contentDataVector)
        let contentBytes = try decodedBase64(named: "encodedBase64", in: contentStreamVector)
        let expectedPayload = try decodedBase64(named: "payloadBase64", in: contentDataVector)
        #expect(contentBytes.count == contentStreamVector["encodedByteLength"] as? Int)
        let contentDecoder = try BridgeProductContentFrameDecoder()
        var contentFrames: [BridgeProductContentFrame] = []
        for byte in contentBytes {
            contentFrames.append(contentsOf: try contentDecoder.append(Data([byte])))
        }
        try contentDecoder.finish()
        #expect(contentFrames.count == contentStreamVector["frameCount"] as? Int)
        #expect(contentFrames.map(\.header.kind) == ["content.accepted", "content.data", "content.end"])
        #expect(contentFrames[1].payload == expectedPayload)
        #expect(try BridgeProductContentFrameCodec.encode(contentFrames[1]) == expectedDataFrame)
    }

    @Test("shared hostile product-session corpus is rejected at its named Swift boundary")
    func sharedHostileProductSessionCorpusIsRejectedAtItsNamedSwiftBoundary() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/invalid/bridge-product-session-corpus.json"
        )
        let hostileCases = try fixtureArray(named: "cases", in: corpus)

        for hostileCase in hostileCases {
            let name = try #require(hostileCase["name"] as? String)
            let contract = try #require(hostileCase["contract"] as? String)
            let value = try #require(hostileCase["value"] as? [String: Any])
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])

            let rejected: Bool
            switch contract {
            case "bootstrap":
                rejected = decodingFails(BridgeProductSessionBootstrap.self, data: data)
            case "controlRequest":
                rejected = decodingFails(BridgeProductControlRequest.self, data: data)
            case "controlResponse":
                rejected = decodingFails(BridgeProductControlResponse.self, data: data)
            case "metadataStreamRequest":
                rejected = decodingFails(BridgeProductMetadataStreamRequest.self, data: data)
            case "metadataFrame":
                rejected = decodingFails(BridgeProductMetadataFrame.self, data: data)
            case "contentRequest":
                rejected = decodingFails(BridgeProductContentRequest.self, data: data)
            case "contentHeader":
                rejected = decodingFails(BridgeProductContentHeader.self, data: data)
            default:
                Issue.record("Unknown hostile product-session contract: \(contract)")
                continue
            }
            #expect(rejected, "Hostile fixture was accepted: \(name)")
        }
    }

    @Test("raw hostile control requests reject duplicate and lookalike members before typed admission")
    func rawHostileControlRequestsRejectBeforeTypedAdmission() {
        let duplicateRequestId = Data(
            #"{"kind":"workerSession.open","wireVersion":2,"paneSessionId":"pane-session-1","workerInstanceId":"worker-instance-1","requestId":"request-open-1","requestId":"request-open-spoof","requestSequence":1}"#
                .utf8
        )
        let lookalikeWorkerInstanceId = Data(
            #"{"kind":"workerSession.open","wireVersion":2,"paneSessionId":"pane-session-1","workerInstanceId":"worker-instance-1","wor\u212AerInstanceId":"worker-instance-spoof","requestId":"request-open-1","requestSequence":1}"#
                .utf8
        )

        #expect(throws: BridgeProductStrictJSONError.duplicateObjectMember) {
            _ = try BridgeProductStrictJSON.decode(
                BridgeProductControlRequest.self,
                from: duplicateRequestId
            )
        }
        #expect(throws: BridgeProductStrictJSONError.invalidJSON) {
            _ = try BridgeProductStrictJSON.decode(
                BridgeProductControlRequest.self,
                from: lookalikeWorkerInstanceId
            )
        }
    }

    @Test("strict nested objects and required null fields reject silent widening")
    func strictNestedObjectsAndRequiredNullFieldsRejectSilentWidening() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let controlRequests = try fixtureArray(named: "controlRequests", in: corpus)
        let controlResponses = try fixtureArray(named: "controlResponses", in: corpus)
        let contentRequests = try fixtureArray(named: "contentRequests", in: corpus)

        var productCall = try #require(controlRequests.first { $0["kind"] as? String == "product.call" })
        var call = try #require(productCall["call"] as? [String: Any])
        var request = try #require(call["request"] as? [String: Any])
        request["futurePayload"] = true
        call["request"] = request
        productCall["call"] = call
        #expect(decodingFails(BridgeProductControlRequest.self, object: productCall))

        var workerOpen = try #require(controlRequests.first { $0["kind"] as? String == "workerSession.open" })
        workerOpen.removeValue(forKey: "request")
        #expect(decodingFails(BridgeProductControlRequest.self, object: workerOpen))

        var callCompleted = try #require(controlResponses.first { $0["kind"] as? String == "call.completed" })
        var completedCall = try #require(callCompleted["call"] as? [String: Any])
        completedCall.removeValue(forKey: "result")
        callCompleted["call"] = completedCall
        #expect(decodingFails(BridgeProductControlResponse.self, object: callCompleted))

        var contentRequest = try #require(contentRequests.first)
        var descriptor = try #require(contentRequest["descriptor"] as? [String: Any])
        var source = try #require(descriptor["source"] as? [String: Any])
        source["rawPath"] = "/private/source"
        descriptor["source"] = source
        contentRequest["descriptor"] = descriptor
        #expect(decodingFails(BridgeProductContentRequest.self, object: contentRequest))

        var invalidUUIDContentRequest = try #require(contentRequests.first)
        var invalidUUIDDescriptor = try #require(invalidUUIDContentRequest["descriptor"] as? [String: Any])
        var invalidUUIDSource = try #require(invalidUUIDDescriptor["source"] as? [String: Any])
        invalidUUIDSource["repoId"] = "00000000-0000-0000-0000-000000000001"
        invalidUUIDDescriptor["source"] = invalidUUIDSource
        invalidUUIDContentRequest["descriptor"] = invalidUUIDDescriptor
        #expect(decodingFails(BridgeProductContentRequest.self, object: invalidUUIDContentRequest))
    }

    @Test("product-session bootstrap rejects capability, surface, and route fields")
    func productSessionBootstrapRejectsMainOwnedOrSecretFields() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let bootstrap = try #require(corpus["bootstrap"] as? [String: Any])

        var capabilityBootstrap = bootstrap
        capabilityBootstrap["productCapabilityBytes"] = Array(0..<32)
        #expect(decodingFails(BridgeProductSessionBootstrap.self, object: capabilityBootstrap))

        var surfaceBootstrap = bootstrap
        surfaceBootstrap["initialSurface"] = "review"
        #expect(decodingFails(BridgeProductSessionBootstrap.self, object: surfaceBootstrap))

        var routeBootstrap = bootstrap
        routeBootstrap["routes"] = [
            "command": ["method": "POST", "url": "agentstudio://rpc/command"]
        ]
        #expect(decodingFails(BridgeProductSessionBootstrap.self, object: routeBootstrap))
    }

    @Test("control response factories preserve correlation and typed subscription acknowledgement")
    func controlResponseFactoriesPreserveCorrelationAndTypedSubscriptionAcknowledgement() throws {
        let corpus = try fixtureJSONObject(
            relativePath: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let requestObjects = try fixtureArray(named: "controlRequests", in: corpus)
        let requests = try requestObjects.map { object in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return try BridgeProductStrictJSON.decode(BridgeProductControlRequest.self, from: data)
        }
        let workerOpen = try #require(requests.first { $0.kind == "workerSession.open" })
        let productCall = try #require(requests.first { $0.kind == "product.call" })
        let subscriptionOpen = try #require(requests.first { $0.kind == "subscription.open" })
        let subscriptionUpdateBatch = try #require(requests.first { $0.kind == "subscription.updateBatch" })
        let subscriptionCancel = try #require(requests.first { $0.kind == "subscription.cancel" })
        let resync = try #require(requests.first { $0.kind == "workerSession.resync" })

        #expect(workerOpen.paneSessionId == "pane-session-1")
        #expect(workerOpen.workerInstanceId == "worker-instance-1")
        #expect(workerOpen.requestId == "request-open-1")
        #expect(workerOpen.requestSequence == 1)

        let accepted = try BridgeProductControlResponse.workerSessionAccepted(correlating: workerOpen)
        #expect(accepted.correlation == workerOpen.correlation)
        let completed = try BridgeProductControlResponse.callCompleted(
            correlating: productCall,
            result: .reviewMarkFileViewed
        )
        #expect(completed.correlation == productCall.correlation)

        let subscriptionResponses = [
            try BridgeProductControlResponse.subscriptionOpenAccepted(
                correlating: subscriptionOpen,
                interestSha256: "1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6"
            ),
            try BridgeProductControlResponse.subscriptionUpdateBatchAccepted(
                correlating: subscriptionUpdateBatch,
                disposition: .committed
            ),
            try BridgeProductControlResponse.subscriptionCancelAccepted(correlating: subscriptionCancel),
        ]
        let subscriptionObjects = try subscriptionResponses.map(encodedJSONObject)
        #expect(
            subscriptionObjects.map { $0["kind"] as? String }
                == [
                    "subscription.openAccepted",
                    "subscription.updateBatchAccepted",
                    "subscription.cancelAccepted",
                ]
        )
        #expect(
            subscriptionObjects.map { $0["subscriptionKind"] as? String }
                == ["review.metadata", "review.metadata", "file.metadata"]
        )

        let resyncResponse = try BridgeProductControlResponse.resyncAccepted(
            correlating: resync,
            nextExpectedRequestSequence: 8,
            resumeFromStreamSequence: 6
        )
        #expect(resyncResponse.correlation == resync.correlation)

        let errorResponse = try BridgeProductControlResponse.requestError(
            correlating: productCall,
            code: .internal,
            nextExpectedRequestSequence: nil,
            retryAfterMilliseconds: nil,
            retryable: false,
            safeMessage: nil
        )
        let errorObject = try encodedJSONObject(errorResponse)
        #expect(errorObject.keys.contains("nextExpectedRequestSequence"))
        #expect(errorObject.keys.contains("retryAfterMilliseconds"))
        #expect(errorObject.keys.contains("safeMessage"))
        #expect(errorObject["nextExpectedRequestSequence"] is NSNull)
        #expect(errorObject["retryAfterMilliseconds"] is NSNull)
        #expect(errorObject["safeMessage"] is NSNull)
        let responseObjects = try
            ([accepted, completed]
            + subscriptionResponses
            + [resyncResponse, errorResponse]).map(encodedJSONObject)
        for responseObject in responseObjects {
            #expect(responseObject["workerEpoch"] == nil)
            #expect(responseObject["workerDerivationEpoch"] == nil)
        }

        #expect(throws: BridgeProductControlResponseFactoryError.mismatchedRequestKind) {
            _ = try BridgeProductControlResponse.workerSessionAccepted(correlating: productCall)
        }
        #expect(throws: (any Error).self) {
            _ = try BridgeProductControlCorrelation(
                paneSessionId: "pane session",
                requestId: "request-1",
                requestSequence: 1,
                workerInstanceId: "worker-1"
            )
        }
    }

    private func decodeAndVerifyRoundTrips<CodableValue: Codable>(
        _ type: CodableValue.Type,
        from objects: [[String: Any]]
    ) throws -> [CodableValue] {
        try objects.map { object in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let value = try BridgeProductStrictJSON.decode(type, from: data)
            let encodedData = try JSONEncoder().encode(value)
            let encodedObject = try #require(JSONSerialization.jsonObject(with: encodedData) as? NSDictionary)
            #expect(encodedObject.isEqual(to: object))
            return value
        }
    }

    private func verifyPaneScopedEpochContract<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) {
        var canonical = object
        canonical.removeValue(forKey: "workerEpoch")
        canonical.removeValue(forKey: "workerDerivationEpoch")
        #expect(!decodingFails(type, object: canonical))

        var withWorkerEpoch = canonical
        withWorkerEpoch["workerEpoch"] = 3
        #expect(decodingFails(type, object: withWorkerEpoch))

        var withDerivationEpoch = canonical
        withDerivationEpoch["workerDerivationEpoch"] = 3
        #expect(decodingFails(type, object: withDerivationEpoch))
    }

    private func verifySurfaceScopedEpochContract<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) {
        var canonical = object
        let epoch = canonical.removeValue(forKey: "workerEpoch") ?? 3
        canonical["workerDerivationEpoch"] = epoch
        canonical.removeValue(forKey: "surface")
        #expect(!decodingFails(type, object: canonical))

        var withoutDerivationEpoch = canonical
        withoutDerivationEpoch.removeValue(forKey: "workerDerivationEpoch")
        #expect(decodingFails(type, object: withoutDerivationEpoch))

        var withLegacyWorkerEpoch = withoutDerivationEpoch
        withLegacyWorkerEpoch["workerEpoch"] = epoch
        #expect(decodingFails(type, object: withLegacyWorkerEpoch))

        var withRepeatedSurface = canonical
        withRepeatedSurface["surface"] = expectedSurfaceForControlRequest(canonical) ?? "file"
        #expect(decodingFails(type, object: withRepeatedSurface))
    }

    private func expectedSurfaceForControlRequest(_ object: [String: Any]) -> String? {
        switch object["kind"] as? String {
        case "product.call":
            guard
                let call = object["call"] as? [String: Any],
                let method = call["method"] as? String
            else { return nil }
            switch method {
            case "review.markFileViewed": return "review"
            default: return nil
            }
        case "subscription.open":
            guard
                let subscription = object["subscription"] as? [String: Any],
                let subscriptionKind = subscription["subscriptionKind"] as? String
            else { return nil }
            return expectedSurface(forSubscriptionKind: subscriptionKind)
        case "subscription.updateBatch", "subscription.cancel":
            guard let subscriptionKind = object["subscriptionKind"] as? String else {
                return nil
            }
            return expectedSurface(forSubscriptionKind: subscriptionKind)
        case "content.open":
            switch object["contentKind"] as? String {
            case "file.content": return "file"
            default: return nil
            }
        default:
            return nil
        }
    }

    private func expectedSurface(forSubscriptionKind subscriptionKind: String) -> String? {
        switch subscriptionKind {
        case "review.metadata": return "review"
        case "file.metadata": return "file"
        default: return nil
        }
    }

    private func decodedValue<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) -> CodableValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return try? BridgeProductStrictJSON.decode(type, from: data)
    }

    private func decodingFails<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return true
        }
        return decodingFails(type, data: data)
    }

    private func decodingFails<CodableValue: Codable>(
        _ type: CodableValue.Type,
        data: Data
    ) -> Bool {
        do {
            _ = try BridgeProductStrictJSON.decode(type, from: data)
            return false
        } catch {
            return true
        }
    }

    private func decodedBase64(named name: String, in object: [String: Any]) throws -> Data {
        let value = try #require(object[name] as? String)
        return try #require(Data(base64Encoded: value))
    }

    private func decodeBoundaryFileInterestState(
        finalPathByteLength: Int
    ) throws -> BridgeProductSubscriptionInterestState {
        let paths =
            (0..<64).map { makeFixedLengthASCIIPath(index: $0, byteLength: 4090) }
            + [makeFixedLengthASCIIPath(index: 64, byteLength: finalPathByteLength)]
        let object: [String: Any] = [
            "interests": [["lane": "foreground", "paths": paths]],
            "pathScope": [],
            "subscriptionKind": "file.metadata",
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(BridgeProductSubscriptionInterestState.self, from: data)
    }

    private func makeFixedLengthASCIIPath(index: Int, byteLength: Int) -> String {
        let prefix = String(format: "%05d:", index)
        return prefix + String(repeating: "x", count: byteLength - prefix.utf8.count)
    }

    private func encodedJSONObject<CodableValue: Codable>(
        _ value: CodableValue
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureArray(named name: String, in object: [String: Any]) throws -> [[String: Any]] {
        try #require(object[name] as? [[String: Any]])
    }

    private func fixtureJSONObject(relativePath: String) throws -> [String: Any] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let data = try Data(contentsOf: projectRoot.appending(path: relativePath))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
