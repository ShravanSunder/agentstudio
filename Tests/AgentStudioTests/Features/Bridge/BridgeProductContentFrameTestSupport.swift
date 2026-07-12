import Foundation
import Testing

@testable import AgentStudio

extension BridgeProductContentFrameCodecTests {
    func expectValidatorRejects(
        expectedRequest: BridgeProductContentRequest? = nil,
        accepted: BridgeProductContentHeader,
        next: BridgeProductContentHeader,
        payload: Data
    ) throws {
        let request =
            if let expectedRequest {
                expectedRequest
            } else {
                try fixtureContentRequest()
            }
        let validator = BridgeProductContentStreamValidator(expectedRequest: request)
        _ = try validator.accept(.init(header: accepted, payload: Data()))
        #expect(throws: (any Error).self) {
            _ = try validator.accept(.init(header: next, payload: payload))
        }
    }

    func expectEndRejects(
        expectedRequest: BridgeProductContentRequest? = nil,
        accepted: BridgeProductContentHeader,
        data: BridgeProductContentHeader,
        end: BridgeProductContentHeader
    ) throws {
        let request =
            if let expectedRequest {
                expectedRequest
            } else {
                try fixtureContentRequest()
            }
        let validator = BridgeProductContentStreamValidator(expectedRequest: request)
        _ = try validator.accept(.init(header: accepted, payload: Data()))
        _ = try validator.accept(.init(header: data, payload: Data("abc".utf8)))
        #expect(throws: (any Error).self) {
            _ = try validator.accept(.init(header: end, payload: Data()))
        }
    }

    func fixtureHeader(kind: String) throws -> BridgeProductContentHeader {
        try decodeHeader(fixtureHeaderObject(kind: kind))
    }

    func fixtureContentRequest() throws -> BridgeProductContentRequest {
        try decodeContentRequest(fixtureContentRequestObject())
    }

    func fixtureContentRequestObject() throws -> [String: Any] {
        let corpus = try fixtureJSONObject()
        let requests = try #require(corpus["contentRequests"] as? [[String: Any]])
        return try #require(requests.first)
    }

    func decodeContentRequest(_ object: [String: Any]) throws -> BridgeProductContentRequest {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(BridgeProductContentRequest.self, from: data)
    }

    func fixtureHeaderObject(kind: String) throws -> [String: Any] {
        let corpus = try fixtureJSONObject()
        let headers = try #require(corpus["contentHeaders"] as? [[String: Any]])
        return try #require(headers.first { $0["kind"] as? String == kind })
    }

    func decodeHeader(_ object: [String: Any]) throws -> BridgeProductContentHeader {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(BridgeProductContentHeader.self, from: data)
    }

    func fixtureJSONObject() throws -> [String: Any] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = projectRoot.appending(
            path: "Tests/BridgeContractFixtures/valid/bridge-product-session-corpus.json"
        )
        let data = try Data(contentsOf: fixtureURL)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func acceptedControlBody(from headerObject: [String: Any]) -> [String: Any] {
        var bodyObject = headerObject
        bodyObject.removeValue(forKey: "kind")
        bodyObject.removeValue(forKey: "contentSequence")
        return bodyObject
    }

    func endControlBody(from headerObject: [String: Any]) -> [String: Any] {
        [
            "endOfSource": headerObject["endOfSource"] as Any,
            "observedByteLength": headerObject["observedByteLength"] as Any,
            "observedSha256": headerObject["observedSha256"] as Any,
        ]
    }

    func sortedJSONObjectData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func minimalControlFrame(
        tag: UInt8,
        sequence: Int,
        bodyObject: [String: Any]
    ) throws -> Data {
        minimalControlFrame(
            tag: tag,
            sequence: sequence,
            rawBody: try sortedJSONObjectData(bodyObject)
        )
    }

    func minimalControlFrame(tag: UInt8, sequence: Int, rawBody: Data) -> Data {
        let frameByteLength = 1 + 4 + rawBody.count
        var data = dataWithUInt32Prefix(frameByteLength)
        data.append(tag)
        data.append(dataWithUInt32Prefix(sequence))
        data.append(rawBody)
        return data
    }

    func minimalDataFrame(sequence: Int, offsetBytes: Int, payload: Data) -> Data {
        let frameByteLength = 1 + 4 + 4 + payload.count
        var data = dataWithUInt32Prefix(frameByteLength)
        data.append(0x02)
        data.append(dataWithUInt32Prefix(sequence))
        data.append(dataWithUInt32Prefix(offsetBytes))
        data.append(payload)
        return data
    }

    func byteSubsequenceCount(_ subsequence: Data, in data: Data) -> Int {
        let needle = [UInt8](subsequence)
        let haystack = [UInt8](data)
        guard !needle.isEmpty, needle.count <= haystack.count else { return 0 }
        return (0...haystack.count - needle.count).reduce(into: 0) { count, offset in
            if Array(haystack[offset..<offset + needle.count]) == needle {
                count += 1
            }
        }
    }

    func contentHeaderObjects(
        declaredByteLength: Int,
        maximumBytes: Int
    ) throws -> (accepted: [String: Any], data: [String: Any], end: [String: Any]) {
        var accepted = try fixtureHeaderObject(kind: "content.accepted")
        accepted["declaredByteLength"] = declaredByteLength
        accepted["maximumBytes"] = maximumBytes
        try updateIdentityMaximumBytes(maximumBytes, in: &accepted)

        let data = try fixtureHeaderObject(kind: "content.data")
        var end = try fixtureHeaderObject(kind: "content.end")
        end["observedByteLength"] = declaredByteLength
        return (accepted, data, end)
    }

    func updateIdentityMaximumBytes(
        _ maximumBytes: Int,
        in object: inout [String: Any]
    ) throws {
        var identity = try #require(object["identity"] as? [String: Any])
        var window = try #require(identity["window"] as? [String: Any])
        window["maximumBytes"] = maximumBytes
        identity["window"] = window
        object["identity"] = identity
    }

    func dataWithUInt32Prefix(_ value: Int) -> Data {
        let unsignedValue = UInt32(value)
        return Data([
            UInt8((unsignedValue >> 24) & 0xff),
            UInt8((unsignedValue >> 16) & 0xff),
            UInt8((unsignedValue >> 8) & 0xff),
            UInt8(unsignedValue & 0xff),
        ])
    }

    func readUInt32BigEndian(_ data: Data, offset: Int) -> Int {
        Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
    }
}
