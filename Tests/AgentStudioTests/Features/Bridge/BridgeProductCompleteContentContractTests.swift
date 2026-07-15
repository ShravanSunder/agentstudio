import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

extension BridgeProductContentFrameCodecTests {
    @Test("empty File content admits an exact zero-byte maximum and terminal")
    func emptyFileContentAdmitsExactZeroByteMaximumAndTerminal() throws {
        // Arrange
        let emptyData = Data()
        let emptySHA256 = SHA256.hash(data: emptyData)
            .map { String(format: "%02x", $0) }
            .joined()
        var headerObjects = try contentHeaderObjects(declaredByteLength: 0, maximumBytes: 0)
        headerObjects.accepted["expectedSha256"] = emptySHA256
        headerObjects.end["contentSequence"] = 1
        headerObjects.end["observedSha256"] = emptySHA256

        var requestObject = try fixtureContentRequestObject()
        var requestDescriptor = try #require(requestObject["descriptor"] as? [String: Any])
        requestDescriptor["declaredByteLength"] = 0
        requestDescriptor["expectedSha256"] = emptySHA256
        requestDescriptor["maximumBytes"] = 0
        var requestWindow = try #require(requestDescriptor["window"] as? [String: Any])
        requestWindow["maximumBytes"] = 0
        requestDescriptor["window"] = requestWindow
        requestObject["descriptor"] = requestDescriptor

        let request = try decodeContentRequest(requestObject)
        let acceptedFrame = BridgeProductContentFrame(
            header: try decodeHeader(headerObjects.accepted),
            payload: emptyData
        )
        let endFrame = BridgeProductContentFrame(
            header: try decodeHeader(headerObjects.end),
            payload: emptyData
        )
        let encoder = BridgeProductContentFrameEncoder(expectedRequest: request)
        var wireBytes = try encoder.encode(acceptedFrame)
        wireBytes.append(try encoder.encode(endFrame))
        try encoder.finish()
        let decoder = try BridgeProductContentFrameDecoder()

        // Act
        #expect(try decoder.append(Data(wireBytes.prefix(3))).isEmpty)
        let decodedFrames = try decoder.append(Data(wireBytes.dropFirst(3)))
        try decoder.finish()
        let validator = BridgeProductContentStreamValidator(expectedRequest: request)
        #expect(decodedFrames.count == 2)
        #expect(try validator.accept(decodedFrames[0]) == nil)
        let terminal = try validator.accept(decodedFrames[1])
        try validator.finish()

        // Assert
        #expect(
            terminal
                == .complete(
                    .init(
                        bytes: emptyData,
                        contentKind: .fileContent,
                        descriptorId: "file-descriptor-1",
                        endOfSource: true,
                        observedSha256: emptySHA256
                    )
                )
        )
    }

    @Test("complete File terminals require source end while Review ranges preserve non-final state")
    func completeFileRequiresSourceEndWhileReviewRangePreservesNonfinalState() throws {
        // Arrange
        let fileRequest = try fixtureContentRequest()
        let accepted = try fixtureHeader(kind: "content.accepted")
        let data = try fixtureHeader(kind: "content.data")
        var nonfinalEndObject = try fixtureHeaderObject(kind: "content.end")
        nonfinalEndObject["endOfSource"] = false
        let nonfinalEnd = try decodeHeader(nonfinalEndObject)
        let fileValidator = BridgeProductContentStreamValidator(expectedRequest: fileRequest)

        // Act / Assert
        _ = try fileValidator.accept(.init(header: accepted, payload: Data()))
        _ = try fileValidator.accept(.init(header: data, payload: Data("abc".utf8)))
        #expect(throws: (any Error).self) {
            _ = try fileValidator.accept(.init(header: nonfinalEnd, payload: Data()))
        }

        let reviewObjects = reviewRangeContentObjects()
        let reviewRequest = try decodeContentRequest(reviewObjects.request)
        let reviewValidator = BridgeProductContentStreamValidator(expectedRequest: reviewRequest)
        _ = try reviewValidator.accept(
            .init(header: try decodeHeader(reviewObjects.accepted), payload: Data())
        )
        _ = try reviewValidator.accept(.init(header: data, payload: Data("abc".utf8)))
        let reviewTerminal = try reviewValidator.accept(
            .init(header: nonfinalEnd, payload: Data())
        )

        #expect(
            reviewTerminal
                == .complete(
                    .init(
                        bytes: Data("abc".utf8),
                        contentKind: .reviewContent,
                        descriptorId: "review-descriptor-1",
                        endOfSource: false,
                        observedSha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                    )
                )
        )
    }

    @Test("complete File content exceeds the legacy prefix through seventeen data frames")
    func completeFileContentExceedsLegacyPrefixThroughSeventeenDataFrames() throws {
        // Arrange
        let dataFrameByteCount = BridgeProductWireContract.maximumContentDataPayloadBytes
        let legacyPrefixByteCount = BridgeProductWireContract.maximumContentBytes
        let finalDataFrameByteCount = 65
        var sourceData = Data(repeating: 0x61, count: legacyPrefixByteCount)
        sourceData.append(Data(repeating: 0x62, count: finalDataFrameByteCount))
        let sourceSHA256 = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()

        var headerObjects = try contentHeaderObjects(
            declaredByteLength: sourceData.count,
            maximumBytes: sourceData.count
        )
        headerObjects.accepted["expectedSha256"] = sourceSHA256
        headerObjects.end["contentSequence"] = 18
        headerObjects.end["observedSha256"] = sourceSHA256

        var requestObject = try fixtureContentRequestObject()
        var requestDescriptor = try #require(requestObject["descriptor"] as? [String: Any])
        requestDescriptor["declaredByteLength"] = sourceData.count
        requestDescriptor["expectedSha256"] = sourceSHA256
        requestDescriptor["maximumBytes"] = sourceData.count
        var requestWindow = try #require(requestDescriptor["window"] as? [String: Any])
        requestWindow["maximumBytes"] = sourceData.count
        requestDescriptor["window"] = requestWindow
        requestObject["descriptor"] = requestDescriptor

        let request = try decodeContentRequest(requestObject)
        let encoder = BridgeProductContentFrameEncoder(expectedRequest: request)
        let validator = BridgeProductContentStreamValidator(expectedRequest: request)
        let acceptedFrame = BridgeProductContentFrame(
            header: try decodeHeader(headerObjects.accepted),
            payload: Data()
        )
        var encodedFrames = [try encoder.encode(acceptedFrame)]
        #expect(try validator.accept(acceptedFrame) == nil)

        // Act
        for dataFrameIndex in 0..<17 {
            let offsetBytes = dataFrameIndex * dataFrameByteCount
            let endOffset = min(offsetBytes + dataFrameByteCount, sourceData.count)
            var dataHeaderObject = headerObjects.data
            dataHeaderObject["contentSequence"] = dataFrameIndex + 1
            dataHeaderObject["offsetBytes"] = offsetBytes
            let frame = BridgeProductContentFrame(
                header: try decodeHeader(dataHeaderObject),
                payload: Data(sourceData[offsetBytes..<endOffset])
            )
            encodedFrames.append(try encoder.encode(frame))
            #expect(try validator.accept(frame) == nil)
        }

        let endFrame = BridgeProductContentFrame(
            header: try decodeHeader(headerObjects.end),
            payload: Data()
        )
        encodedFrames.append(try encoder.encode(endFrame))
        let terminal = try validator.accept(endFrame)
        try encoder.finish()
        try validator.finish()
        let wireBytes = encodedFrames.reduce(into: Data()) { stream, frame in
            stream.append(frame)
        }
        let decoder = try BridgeProductContentFrameDecoder()
        var decodedFrames: [BridgeProductContentFrame] = []
        var fragmentOffset = 0
        while fragmentOffset < wireBytes.count {
            let fragmentEnd = min(fragmentOffset + 4 * 1024, wireBytes.count)
            decodedFrames.append(
                contentsOf: try decoder.append(Data(wireBytes[fragmentOffset..<fragmentEnd]))
            )
            fragmentOffset = fragmentEnd
        }
        try decoder.finish()
        let decodedValidator = BridgeProductContentStreamValidator(expectedRequest: request)
        var decodedTerminal: BridgeProductContentTerminalResult?
        for frame in decodedFrames {
            if let acceptedTerminal = try decodedValidator.accept(frame) {
                decodedTerminal = acceptedTerminal
            }
        }
        try decodedValidator.finish()

        // Assert
        #expect(sourceData.count == 2_097_217)
        #expect(encodedFrames.count == 19)
        #expect(decodedFrames.count == 19)
        #expect(readUInt32BigEndian(encodedFrames[17], offset: 5) == 17)
        #expect(readUInt32BigEndian(encodedFrames[17], offset: 9) == legacyPrefixByteCount)
        #expect(encodedFrames[17].count == 4 + 1 + 4 + 4 + finalDataFrameByteCount)
        #expect(
            terminal
                == .complete(
                    .init(
                        bytes: sourceData,
                        contentKind: .fileContent,
                        descriptorId: "file-descriptor-1",
                        endOfSource: true,
                        observedSha256: sourceSHA256
                    )
                )
        )
        #expect(decodedTerminal == terminal)
    }

    private func reviewRangeContentObjects() -> (
        request: [String: Any],
        accepted: [String: Any]
    ) {
        let digest = [
            "algorithm": "sha256",
            "authority": "authoritative",
            "value": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        ]
        let window: [String: Any] = [
            "kind": "byteRange",
            "maximumBytes": 3,
            "startByte": 0,
        ]
        let identity: [String: Any] = [
            "contentDigest": digest,
            "contentKind": "review.content",
            "descriptorId": "review-descriptor-1",
            "endpointId": "review-endpoint-1",
            "handleId": "review-handle-1",
            "itemId": "review-item-1",
            "packageId": "review-package-1",
            "reviewGeneration": 7,
            "role": "head",
            "sourceIdentity": "review-source-1",
            "wholeByteLength": 12,
            "window": window,
        ]
        let request: [String: Any] = [
            "contentKind": "review.content",
            "contentRequestId": "review-content-request-1",
            "descriptor": identity.merging([
                "declaredByteLength": 3,
                "encoding": "utf-8",
                "expectedSha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "isBinary": false,
                "language": "text",
                "maximumBytes": 3,
                "mimeType": "text/plain",
            ]) { _, newValue in newValue },
            "kind": "content.open",
            "leaseId": "review-lease-1",
            "paneSessionId": "pane-session-1",
            "wireVersion": 2,
            "workerDerivationEpoch": 2,
            "workerInstanceId": "worker-instance-1",
        ]
        let accepted: [String: Any] = [
            "contentRequestId": "review-content-request-1",
            "contentSequence": 0,
            "declaredByteLength": 3,
            "expectedSha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "identity": identity,
            "kind": "content.accepted",
            "leaseId": "review-lease-1",
            "maximumBytes": 3,
            "paneSessionId": "pane-session-1",
            "wireVersion": 2,
            "workerDerivationEpoch": 2,
            "workerInstanceId": "worker-instance-1",
        ]
        return (request, accepted)
    }
}
