import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductMetadataFrameCodecTests {
    @Test("metadata codec writes u32-prefixed strict JSON and decodes concatenated frames")
    func metadataCodecWritesLengthPrefixedJSONAndDecodesConcatenatedFrames() throws {
        let frame = try fixtureAcceptedFrame()
        let encoded = try BridgeProductMetadataFrameCodec.encode(frame)

        #expect(readUInt32BigEndian(encoded) == encoded.count - 4)
        let body = encoded.dropFirst(4)
        #expect(try BridgeProductStrictJSON.decode(BridgeProductMetadataFrame.self, from: body) == frame)

        let decoder = try BridgeProductMetadataFrameDecoder()
        var twoFrames = Data()
        twoFrames.append(encoded)
        twoFrames.append(encoded)
        #expect(try decoder.append(twoFrames) == [frame, frame])
        try decoder.finish()
        #expect(
            decoder.diagnostics
                == .init(
                    receivedByteCount: twoFrames.count,
                    consumedByteCount: twoFrames.count,
                    copiedByteCount: twoFrames.count,
                    retainedByteCount: 0,
                    peakRetainedByteCount: encoded.count,
                    emittedFrameCount: 2,
                    discardedTailByteCount: 0,
                    state: .finished,
                    failureCode: nil
                )
        )
        try decoder.finish()
        #expect(throws: (any Error).self) {
            _ = try decoder.append(encoded)
        }
        #expect(decoder.diagnostics.state == .finished)
        #expect(decoder.diagnostics.failureCode == nil)

        let fragmentedDecoder = try BridgeProductMetadataFrameDecoder()
        var fragmentedFrames: [BridgeProductMetadataFrame] = []
        for byte in encoded {
            fragmentedFrames.append(contentsOf: try fragmentedDecoder.append(Data([byte])))
        }
        try fragmentedDecoder.finish()
        #expect(fragmentedFrames == [frame])
        #expect(
            fragmentedDecoder.diagnostics
                == .init(
                    receivedByteCount: encoded.count,
                    consumedByteCount: encoded.count,
                    copiedByteCount: encoded.count,
                    retainedByteCount: 0,
                    peakRetainedByteCount: encoded.count,
                    emittedFrameCount: 1,
                    discardedTailByteCount: 0,
                    state: .finished,
                    failureCode: nil
                )
        )
        #expect(
            fragmentedDecoder.storageDiagnostics
                == .init(
                    ingressCopiedByteCount: encoded.count,
                    relocationCopiedByteCount: 0,
                    allocationCount: 2
                )
        )
    }

    @Test("metadata decoder admits only the length prefix from a hostile transport chunk")
    func metadataDecoderAdmitsOnlyLengthPrefixFromHostileTransportChunk() throws {
        var hostileChunk = dataWithUInt32Prefix(
            BridgeProductWireContract.maximumMetadataFrameBytes + 1
        )
        hostileChunk.append(Data(repeating: 0xa5, count: 4 * 1024 * 1024))
        let decoder = try BridgeProductMetadataFrameDecoder()

        #expect(throws: (any Error).self) {
            _ = try decoder.append(hostileChunk)
        }
        #expect(
            decoder.diagnostics
                == .init(
                    receivedByteCount: hostileChunk.count,
                    consumedByteCount: 4,
                    copiedByteCount: 4,
                    retainedByteCount: 0,
                    peakRetainedByteCount: 4,
                    emittedFrameCount: 0,
                    discardedTailByteCount: hostileChunk.count - 4,
                    state: .poisoned,
                    failureCode: .frameLengthExceedsCeiling
                )
        )
    }

    @Test("metadata decoder copies an exact-cap frame in 4 KiB fragments without relocation")
    func metadataDecoderCopiesExactCapFrameWithoutRelocation() throws {
        var exactCapWire = dataWithUInt32Prefix(
            BridgeProductWireContract.maximumMetadataFrameBytes
        )
        exactCapWire.append(
            Data(
                repeating: 0x7b,
                count: BridgeProductWireContract.maximumMetadataFrameBytes
            )
        )
        let decoder = try BridgeProductMetadataFrameDecoder()
        var rejectedMalformedBody = false

        for offset in stride(from: 0, to: exactCapWire.count, by: 4 * 1024) {
            do {
                _ = try decoder.append(
                    exactCapWire[offset..<min(offset + 4 * 1024, exactCapWire.count)]
                )
            } catch {
                rejectedMalformedBody = true
                break
            }
        }

        #expect(rejectedMalformedBody)
        #expect(decoder.diagnostics.copiedByteCount == exactCapWire.count)
        #expect(decoder.diagnostics.retainedByteCount == 0)
        #expect(decoder.diagnostics.state == .poisoned)
        #expect(decoder.diagnostics.failureCode == .frameDecodeInvalid)
        #expect(
            decoder.storageDiagnostics
                == .init(
                    ingressCopiedByteCount: exactCapWire.count,
                    relocationCopiedByteCount: 0,
                    allocationCount: 2
                )
        )
    }

    @Test("metadata decoder rejects invalid lengths, UTF-8, widened JSON, and truncation")
    func metadataDecoderRejectsMalformedFrames() throws {
        let frame = try fixtureAcceptedFrame()
        let encoded = try BridgeProductMetadataFrameCodec.encode(frame)
        let widenedJSON = Data(
            #"{"kind":"metadataStream.accepted","metadataStreamId":"stream-1","paneSessionId":"pane-1","resumeDisposition":"resumed","streamSequence":0,"surface":"review","wireVersion":2,"workerInstanceId":"worker-1"}"#
                .utf8
        )
        let malformedFrames = [
            dataWithUInt32Prefix(0),
            dataWithUInt32Prefix(BridgeProductWireContract.maximumMetadataFrameBytes + 1),
            manualMetadataFrame(body: Data([0xff])),
            manualMetadataFrame(body: widenedJSON),
        ]

        for malformedFrame in malformedFrames {
            let decoder = try BridgeProductMetadataFrameDecoder()
            #expect(throws: (any Error).self) {
                _ = try decoder.append(malformedFrame)
            }
        }

        let poisonedDecoder = try BridgeProductMetadataFrameDecoder()
        #expect(throws: (any Error).self) {
            _ = try poisonedDecoder.append(dataWithUInt32Prefix(0))
        }
        #expect(throws: (any Error).self) {
            _ = try poisonedDecoder.append(encoded)
        }

        var validFrameWithHostileTail = encoded
        validFrameWithHostileTail.append(
            dataWithUInt32Prefix(BridgeProductWireContract.maximumMetadataFrameBytes + 1)
        )
        validFrameWithHostileTail.append(Data(repeating: 0xee, count: 4 * 1024 * 1024))
        let atomicDecoder = try BridgeProductMetadataFrameDecoder()
        #expect(throws: (any Error).self) {
            _ = try atomicDecoder.append(validFrameWithHostileTail)
        }
        #expect(atomicDecoder.diagnostics.copiedByteCount == encoded.count + 4)
        #expect(atomicDecoder.diagnostics.retainedByteCount == 0)
        #expect(atomicDecoder.diagnostics.peakRetainedByteCount == encoded.count)
        #expect(atomicDecoder.diagnostics.emittedFrameCount == 0)
        #expect(
            atomicDecoder.diagnostics.discardedTailByteCount
                == validFrameWithHostileTail.count - encoded.count - 4
        )
        #expect(atomicDecoder.diagnostics.state == .poisoned)
        #expect(atomicDecoder.diagnostics.failureCode == .frameLengthExceedsCeiling)
        #expect(atomicDecoder.storageDiagnostics.relocationCopiedByteCount == 0)
        #expect(atomicDecoder.storageDiagnostics.ingressCopiedByteCount == encoded.count + 4)

        let truncatedDecoder = try BridgeProductMetadataFrameDecoder()
        #expect(try truncatedDecoder.append(encoded.dropLast()).isEmpty)
        #expect(truncatedDecoder.diagnostics.copiedByteCount == encoded.count - 1)
        #expect(truncatedDecoder.diagnostics.retainedByteCount == encoded.count - 1)
        #expect(truncatedDecoder.diagnostics.state == .awaitingFrameBody)
        #expect(throws: (any Error).self) {
            try truncatedDecoder.finish()
        }
        #expect(truncatedDecoder.diagnostics.retainedByteCount == 0)
        #expect(truncatedDecoder.diagnostics.discardedTailByteCount == encoded.count - 1)
        #expect(truncatedDecoder.diagnostics.state == .poisoned)
        #expect(truncatedDecoder.diagnostics.failureCode == .truncatedFrame)
        #expect(throws: (any Error).self) {
            _ = try truncatedDecoder.append(encoded)
        }
        #expect(truncatedDecoder.diagnostics.copiedByteCount == encoded.count - 1)
        #expect(throws: BridgeProductFrameCodecError.invalidConfiguration) {
            _ = try BridgeProductMetadataFrameDecoder(maximumFrameBytes: 0)
        }
        #expect(throws: BridgeProductFrameCodecError.invalidConfiguration) {
            _ = try BridgeProductMetadataFrameDecoder(
                maximumFrameBytes: BridgeProductWireContract.maximumMetadataFrameBytes + 1
            )
        }
    }

    @Test("metadata decoder rejects duplicate discriminant and derivation epoch before semantic decode")
    func metadataDecoderRejectsDuplicateMembers() throws {
        let frame = try fixtureAcceptedFrame()
        let canonicalJSON = try #require(String(data: JSONEncoder().encode(frame), encoding: .utf8))
        let subscriptionFrame = try fixtureSubscriptionAcceptedFrame()
        let subscriptionJSON = try #require(
            String(data: JSONEncoder().encode(subscriptionFrame), encoding: .utf8)
        )
        let duplicateBodies = [
            canonicalJSON.replacingOccurrences(
                of: #""kind":"metadataStream.accepted""#,
                with: #""kind":"metadataStream.error","kind":"metadataStream.accepted""#
            ),
            subscriptionJSON.replacingOccurrences(
                of: #""workerDerivationEpoch":"#,
                with: #""workerDerivationEpoch":999,"workerDerivationEpoch":"#
            ),
            canonicalJSON.replacingOccurrences(
                of: #""kind":"metadataStream.accepted""#,
                with: #""kind":"metadataStream.error","\u006bind":"metadataStream.accepted""#
            ),
        ]

        for duplicateBody in duplicateBodies {
            let decoder = try BridgeProductMetadataFrameDecoder()
            #expect(throws: (any Error).self) {
                _ = try decoder.append(manualMetadataFrame(body: Data(duplicateBody.utf8)))
            }
            #expect(decoder.diagnostics.emittedFrameCount == 0)
            #expect(decoder.diagnostics.failureCode == .frameDecodeInvalid)
            #expect(decoder.diagnostics.retainedByteCount == 0)
            #expect(decoder.diagnostics.state == .poisoned)
        }
    }

    @Test("one physical metadata stream and pane frames carry no derivation epoch")
    func paneMetadataStreamCorrelationCarriesNoDerivationEpoch() throws {
        let corpus = try fixtureCorpus()
        let streamRequests = try #require(corpus["metadataStreamRequests"] as? [[String: Any]])
        let frames = try #require(corpus["metadataFrames"] as? [[String: Any]])

        for streamRequest in streamRequests {
            verifyPaneMetadataEpochContract(
                BridgeProductMetadataStreamRequest.self,
                object: streamRequest
            )
        }
        for frameKind in ["metadataStream.accepted", "metadataStream.error"] {
            let matchingFrames = frames.filter { $0["kind"] as? String == frameKind }
            #expect(!matchingFrames.isEmpty)
            for frame in matchingFrames {
                verifyPaneMetadataEpochContract(BridgeProductMetadataFrame.self, object: frame)
            }
        }

        var canonicalRequest = try #require(streamRequests.first)
        canonicalRequest.removeValue(forKey: "workerEpoch")
        canonicalRequest.removeValue(forKey: "workerDerivationEpoch")
        if let request = decodedMetadataValue(
            BridgeProductMetadataStreamRequest.self,
            object: canonicalRequest
        ) {
            let accepted = try BridgeProductMetadataFrame.metadataStreamAccepted(
                for: request,
                resumeDisposition: .snapshotRequired
            )
            let encoded = try encodedJSONObject(accepted)
            #expect(encoded["workerEpoch"] == nil)
            #expect(encoded["workerDerivationEpoch"] == nil)
        } else {
            Issue.record("Epoch-free metadataStream.open did not decode")
        }
    }

    @Test("surface metadata frames require derivation epoch and omit repeated surface")
    func surfaceMetadataFramesRequireDerivationEpoch() throws {
        let corpus = try fixtureCorpus()
        let frames = try #require(corpus["metadataFrames"] as? [[String: Any]])
        let surfaceFrameKinds: Set<String> = [
            "subscription.accepted",
            "subscription.interestsCommitted",
            "subscription.data",
            "subscription.reset",
            "subscription.end",
            "subscription.cancelled",
            "content.cancelled",
        ]
        let surfaceFrames = frames.filter {
            guard let kind = $0["kind"] as? String else { return false }
            return surfaceFrameKinds.contains(kind)
        }

        #expect(Set(surfaceFrames.compactMap { $0["kind"] as? String }) == surfaceFrameKinds)
        for frame in surfaceFrames {
            #expect(expectedSurfaceForMetadataFrame(frame) != nil)
            verifySurfaceMetadataEpochContract(BridgeProductMetadataFrame.self, object: frame)
        }
    }

    @Test("older admitted lifecycle remains encodable after independent epoch advances")
    func olderAdmittedLifecycleRemainsWireValidAfterEpochAdvance() throws {
        let corpus = try fixtureCorpus()
        let frames = try #require(corpus["metadataFrames"] as? [[String: Any]])
        var oldReviewAccepted = try #require(
            frames.first {
                $0["kind"] as? String == "subscription.accepted"
                    && $0["subscriptionKind"] as? String == "review.metadata"
            }
        )
        var currentFileData = try #require(
            frames.first {
                $0["kind"] as? String == "subscription.data"
                    && $0["subscriptionKind"] as? String == "file.metadata"
            }
        )
        var oldReviewReset = try #require(
            frames.first { $0["kind"] as? String == "subscription.reset" }
        )
        var oldFileCancellation = try #require(
            frames.first { $0["kind"] as? String == "content.cancelled" }
        )

        oldReviewAccepted = surfaceMetadataFrame(oldReviewAccepted, derivationEpoch: 3)
        currentFileData = surfaceMetadataFrame(currentFileData, derivationEpoch: 29)
        oldReviewReset = surfaceMetadataFrame(oldReviewReset, derivationEpoch: 3)
        oldFileCancellation = surfaceMetadataFrame(oldFileCancellation, derivationEpoch: 7)
        let lifecycleObjects = [
            oldReviewAccepted,
            currentFileData,
            oldReviewReset,
            oldFileCancellation,
        ]

        let decodedFrames = lifecycleObjects.compactMap {
            decodedMetadataValue(BridgeProductMetadataFrame.self, object: $0)
        }
        #expect(decodedFrames.count == lifecycleObjects.count)
        for (frame, expectedObject) in zip(decodedFrames, lifecycleObjects) {
            let encoded = try encodedJSONObject(frame)
            #expect(encoded["workerDerivationEpoch"] as? Int == expectedObject["workerDerivationEpoch"] as? Int)
            #expect(encoded["workerEpoch"] == nil)
            #expect(encoded["surface"] == nil)
        }
    }

    @Test("metadata runtime factories construct every closed lifecycle variant")
    func metadataRuntimeFactoriesConstructEveryClosedLifecycleVariant() throws {
        let fixture = try metadataRuntimeFixture()

        let frames: [BridgeProductMetadataFrame] = [
            try .metadataStreamAccepted(
                for: fixture.streamRequest,
                resumeDisposition: .snapshotRequired
            ),
            try .subscriptionAccepted(
                stream: fixture.stream,
                streamSequence: 1,
                subscription: fixture.initialSubscription
            ),
            try .subscriptionInterestsCommitted(
                stream: fixture.stream,
                streamSequence: 2,
                subscription: fixture.updatedSubscription,
                subscriptionSequence: 1,
                updateId: "review-interest-update-1"
            ),
            try .subscriptionData(
                stream: fixture.stream,
                streamSequence: 3,
                subscription: fixture.updatedSubscription,
                subscriptionSequence: 2,
                data: fixture.event
            ),
            try .subscriptionReset(
                stream: fixture.stream,
                streamSequence: 4,
                subscription: fixture.updatedSubscription,
                subscriptionSequence: 3,
                reason: .interestMismatch
            ),
            try .subscriptionEnd(
                stream: fixture.stream,
                streamSequence: 5,
                subscription: fixture.updatedSubscription,
                subscriptionSequence: 4
            ),
            try .subscriptionCancelled(
                stream: fixture.stream,
                streamSequence: 6,
                subscription: fixture.updatedSubscription,
                subscriptionSequence: 5
            ),
            try .contentCancelled(
                stream: fixture.stream,
                streamSequence: 7,
                admission: fixture.contentRequest.admission,
                disposition: .stopped
            ),
            try .metadataStreamError(
                stream: fixture.stream,
                streamSequence: 8,
                code: .internal,
                retryable: false,
                safeMessage: nil
            ),
        ]

        #expect(
            frames.map(\.kind) == [
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
        for frame in frames {
            let encoded = try JSONEncoder().encode(frame)
            #expect(try BridgeProductStrictJSON.decode(BridgeProductMetadataFrame.self, from: encoded) == frame)
        }

        try verifyRuntimeFactoryRejections(
            stream: fixture.stream,
            subscription: fixture.updatedSubscription,
            event: fixture.event,
            contentRequests: fixture.contentRequests
        )
    }

    @Test("resumed and snapshot-required acceptance consume the next physical sequence")
    func resumedAcceptanceConsumesNextPhysicalSequence() throws {
        let corpus = try fixtureCorpus()
        let requestObjects = try #require(corpus["metadataStreamRequests"] as? [[String: Any]])
        var resumedRequestObject = try #require(requestObjects.first)
        resumedRequestObject["resumeFromStreamSequence"] = 6
        let resumedRequest = try decode(
            BridgeProductMetadataStreamRequest.self,
            from: resumedRequestObject
        )

        for disposition in [
            BridgeProductMetadataStreamResumeDisposition.resumed,
            .snapshotRequired,
        ] {
            let frame = try BridgeProductMetadataFrame.metadataStreamAccepted(
                for: resumedRequest,
                resumeDisposition: disposition
            )
            let frameObject = try encodedJSONObject(frame)
            #expect(frameObject["streamSequence"] as? Int == 7)
            #expect(frameObject["workerEpoch"] == nil)
            #expect(frameObject["workerDerivationEpoch"] == nil)
        }
    }

    @Test("metadata stream accepted factory rejects a negative physical sequence")
    func metadataStreamAcceptedFactoryRejectsNegativePhysicalSequence() throws {
        let fixture = try metadataRuntimeFixture()

        #expect(throws: (any Error).self) {
            _ = try BridgeProductMetadataStreamAcceptedFrame(
                stream: fixture.stream,
                streamSequence: -1,
                resumeDisposition: .snapshotRequired
            )
        }
    }

    private func metadataRuntimeFixture() throws -> MetadataRuntimeFixture {
        let corpus = try fixtureCorpus()
        let streamRequests = try #require(corpus["metadataStreamRequests"] as? [[String: Any]])
        let streamRequest = try decode(
            BridgeProductMetadataStreamRequest.self,
            from: try #require(streamRequests.first)
        )
        let contentRequests = try #require(corpus["contentRequests"] as? [[String: Any]])
        let contentRequest = try decode(
            BridgeProductContentRequest.self,
            from: try #require(contentRequests.first)
        )
        let initialSubscription = try BridgeProductSubscriptionFrameCorrelation(
            cursor: "review-cursor-1",
            interestRevision: 0,
            interestSha256: "1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6",
            sourceGeneration: 7,
            subscriptionId: "review-subscription-1",
            subscriptionKind: .reviewMetadata,
            workerDerivationEpoch: 7
        )
        let updatedSubscription = try BridgeProductSubscriptionFrameCorrelation(
            cursor: "review-cursor-commit-1",
            interestRevision: 1,
            interestSha256: "2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd",
            sourceGeneration: 7,
            subscriptionId: "review-subscription-1",
            subscriptionKind: .reviewMetadata,
            workerDerivationEpoch: 7
        )
        let event = try BridgeProductSubscriptionData.reviewMetadata(
            .init(
                generation: 7,
                packageId: "review-package-1",
                revision: 1,
                sourceIdentity: "review-source-1"
            )
        )
        return MetadataRuntimeFixture(
            contentRequest: contentRequest,
            contentRequests: contentRequests,
            event: event,
            initialSubscription: initialSubscription,
            stream: streamRequest.correlation,
            streamRequest: streamRequest,
            updatedSubscription: updatedSubscription
        )
    }

    private func verifyRuntimeFactoryRejections(
        stream: BridgeProductMetadataStreamCorrelation,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        event: BridgeProductSubscriptionData,
        contentRequests: [[String: Any]]
    ) throws {
        let mismatchedGenerationSubscription = try BridgeProductSubscriptionFrameCorrelation(
            cursor: subscription.cursor,
            interestRevision: subscription.interestRevision,
            interestSha256: subscription.interestSha256,
            sourceGeneration: event.sourceGeneration + 1,
            subscriptionId: subscription.subscriptionId,
            subscriptionKind: subscription.subscriptionKind,
            workerDerivationEpoch: subscription.workerDerivationEpoch
        )
        let fileSubscription = try BridgeProductSubscriptionFrameCorrelation(
            cursor: nil,
            interestRevision: 0,
            interestSha256: "51ce8b03041697e18e2a24d5311e14bb1df4da119635bb84246c1b047316e46b",
            sourceGeneration: 7,
            subscriptionId: "file-subscription-1",
            subscriptionKind: .fileMetadata,
            workerDerivationEpoch: 2
        )
        #expect(throws: BridgeProductMetadataFrameFactoryError.subscriptionDataMismatch) {
            _ = try BridgeProductMetadataFrame.subscriptionData(
                stream: stream,
                streamSequence: 8,
                subscription: fileSubscription,
                subscriptionSequence: 1,
                data: event
            )
        }
        #expect(throws: BridgeProductMetadataFrameFactoryError.subscriptionDataSourceGenerationMismatch) {
            _ = try BridgeProductMetadataFrame.subscriptionData(
                stream: stream,
                streamSequence: 8,
                subscription: mismatchedGenerationSubscription,
                subscriptionSequence: 1,
                data: event
            )
        }
        #expect(throws: (any Error).self) {
            _ = try BridgeProductMetadataFrame.subscriptionEnd(
                stream: stream,
                streamSequence: 0,
                subscription: subscription,
                subscriptionSequence: 1
            )
        }
        var foreignContentRequestObject = try #require(contentRequests.first)
        foreignContentRequestObject["paneSessionId"] = "pane-session-foreign"
        let foreignContentRequest = try decode(
            BridgeProductContentRequest.self,
            from: foreignContentRequestObject
        )
        #expect(throws: BridgeProductMetadataFrameFactoryError.contentSessionMismatch) {
            _ = try BridgeProductMetadataFrame.contentCancelled(
                stream: stream,
                streamSequence: 8,
                admission: foreignContentRequest.admission,
                disposition: .stopped
            )
        }
    }

    private func verifyPaneMetadataEpochContract<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) {
        var canonical = object
        canonical.removeValue(forKey: "workerEpoch")
        canonical.removeValue(forKey: "workerDerivationEpoch")
        #expect(!metadataDecodingFails(type, object: canonical))

        var withWorkerEpoch = canonical
        withWorkerEpoch["workerEpoch"] = 3
        #expect(metadataDecodingFails(type, object: withWorkerEpoch))

        var withDerivationEpoch = canonical
        withDerivationEpoch["workerDerivationEpoch"] = 3
        #expect(metadataDecodingFails(type, object: withDerivationEpoch))
    }

    private func verifySurfaceMetadataEpochContract<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) {
        let canonical = surfaceMetadataFrame(object, derivationEpoch: 3)
        #expect(!metadataDecodingFails(type, object: canonical))

        var withoutDerivationEpoch = canonical
        withoutDerivationEpoch.removeValue(forKey: "workerDerivationEpoch")
        #expect(metadataDecodingFails(type, object: withoutDerivationEpoch))

        var withLegacyWorkerEpoch = withoutDerivationEpoch
        withLegacyWorkerEpoch["workerEpoch"] = 3
        #expect(metadataDecodingFails(type, object: withLegacyWorkerEpoch))

        var withRepeatedSurface = canonical
        withRepeatedSurface["surface"] = expectedSurfaceForMetadataFrame(canonical) ?? "file"
        #expect(metadataDecodingFails(type, object: withRepeatedSurface))
    }

    private func surfaceMetadataFrame(
        _ object: [String: Any],
        derivationEpoch: Int
    ) -> [String: Any] {
        var canonical = object
        canonical.removeValue(forKey: "workerEpoch")
        canonical["workerDerivationEpoch"] = derivationEpoch
        canonical.removeValue(forKey: "surface")
        return canonical
    }

    private func expectedSurfaceForMetadataFrame(_ object: [String: Any]) -> String? {
        if let subscriptionKind = object["subscriptionKind"] as? String {
            switch subscriptionKind {
            case "review.metadata": return "review"
            case "file.metadata": return "file"
            default: return nil
            }
        }
        guard
            object["kind"] as? String == "content.cancelled",
            let identity = object["identity"] as? [String: Any]
        else { return nil }
        switch identity["contentKind"] as? String {
        case "file.content": return "file"
        default: return nil
        }
    }

    private func metadataDecodingFails<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) -> Bool {
        decodedMetadataValue(type, object: object) == nil
    }

    private func decodedMetadataValue<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) -> CodableValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return try? BridgeProductStrictJSON.decode(type, from: data)
    }

    private func fixtureAcceptedFrame() throws -> BridgeProductMetadataFrame {
        let corpus = try fixtureCorpus()
        let frames = try #require(corpus["metadataFrames"] as? [[String: Any]])
        let object = try #require(frames.first { $0["kind"] as? String == "metadataStream.accepted" })
        return try decode(BridgeProductMetadataFrame.self, from: object)
    }

    private func fixtureSubscriptionAcceptedFrame() throws -> BridgeProductMetadataFrame {
        let corpus = try fixtureCorpus()
        let frames = try #require(corpus["metadataFrames"] as? [[String: Any]])
        let object = try #require(frames.first { $0["kind"] as? String == "subscription.accepted" })
        return try decode(BridgeProductMetadataFrame.self, from: object)
    }

    private func decode<CodableValue: Codable>(
        _ type: CodableValue.Type,
        from object: [String: Any]
    ) throws -> CodableValue {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(type, from: data)
    }

    private func encodedJSONObject<CodableValue: Codable>(
        _ value: CodableValue
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureCorpus() throws -> [String: Any] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = projectRoot.appending(
            path: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let data = try Data(contentsOf: fixtureURL)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func manualMetadataFrame(body: Data) -> Data {
        var data = dataWithUInt32Prefix(body.count)
        data.append(body)
        return data
    }

    private func dataWithUInt32Prefix(_ value: Int) -> Data {
        let unsignedValue = UInt32(value)
        return Data([
            UInt8((unsignedValue >> 24) & 0xff),
            UInt8((unsignedValue >> 16) & 0xff),
            UInt8((unsignedValue >> 8) & 0xff),
            UInt8(unsignedValue & 0xff),
        ])
    }

    private func readUInt32BigEndian(_ data: Data) -> Int {
        Int(data[0]) << 24
            | Int(data[1]) << 16
            | Int(data[2]) << 8
            | Int(data[3])
    }

    private struct MetadataRuntimeFixture {
        let contentRequest: BridgeProductContentRequest
        let contentRequests: [[String: Any]]
        let event: BridgeProductSubscriptionData
        let initialSubscription: BridgeProductSubscriptionFrameCorrelation
        let stream: BridgeProductMetadataStreamCorrelation
        let streamRequest: BridgeProductMetadataStreamRequest
        let updatedSubscription: BridgeProductSubscriptionFrameCorrelation
    }
}
