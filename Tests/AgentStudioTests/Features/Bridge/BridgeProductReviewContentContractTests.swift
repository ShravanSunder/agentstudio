import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product Review content contracts")
struct BridgeProductReviewContentContractTests {
    @Test("decodes authoritative and provisional Review content identities through the closed union")
    func decodesReviewContentIdentityVariants() throws {
        let authoritativeRequest = reviewContentRequestObject(
            digest: [
                "algorithm": "sha256",
                "authority": "authoritative",
                "value": String(repeating: "a", count: 64),
            ],
            declaredByteLength: 3,
            expectedSha256: String(repeating: "b", count: 64)
        )
        let provisionalRequest = reviewContentRequestObject(
            digest: [
                "algorithm": "git-oid",
                "authority": "provisional",
                "value": "0123456789abcdef0123456789abcdef01234567",
            ],
            declaredByteLength: nil,
            expectedSha256: nil
        )

        let authoritative = try decodeContentRequest(authoritativeRequest)
        let provisional = try decodeContentRequest(provisionalRequest)

        guard case .reviewContent(let authoritativeValue) = authoritative,
            case .reviewContent(let provisionalValue) = provisional,
            case .authoritativeSHA256(let authoritativeDigest) = authoritativeValue.descriptor.contentDigest,
            case .provisional(let algorithm, let value) = provisionalValue.descriptor.contentDigest
        else {
            Issue.record("Expected Review content request variants")
            return
        }
        #expect(authoritative.surface == .review)
        #expect(authoritative.admission.contentKind == .reviewContent)
        #expect(authoritativeValue.descriptor.declaredByteLength == 3)
        #expect(authoritativeDigest == String(repeating: "a", count: 64))
        #expect(provisionalValue.descriptor.expectedSha256 == nil)
        #expect(algorithm == "git-oid")
        #expect(value == "0123456789abcdef0123456789abcdef01234567")
        guard case .reviewContent(let identity) = provisional.admission.identity else {
            Issue.record("Expected Review content identity")
            return
        }
        #expect(identity.packageId == "review-package-1")
        #expect(identity.reviewGeneration == 7)
        #expect(identity.window.startByte == 0)
        #expect(identity.window.maximumBytes == 512 * 1024)
    }

    @Test("rejects unknown keys at every Review content object boundary")
    func rejectsUnknownReviewContentKeys() throws {
        var request = reviewContentRequestObject()
        var descriptor = try #require(request["descriptor"] as? [String: Any])
        var digest = try #require(descriptor["contentDigest"] as? [String: Any])
        var window = try #require(descriptor["window"] as? [String: Any])

        digest["legacyHash"] = "not-allowed"
        descriptor["contentDigest"] = digest
        request["descriptor"] = descriptor
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject()
        descriptor = try #require(request["descriptor"] as? [String: Any])
        window["maximumLines"] = 400
        descriptor["window"] = window
        request["descriptor"] = descriptor
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject()
        descriptor = try #require(request["descriptor"] as? [String: Any])
        descriptor["resourceUrl"] = "agentstudio://resource/review/content/legacy"
        request["descriptor"] = descriptor
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject()
        request["legacyRequest"] = true
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }
    }

    @Test("enforces Review text policy and byte-range bounds")
    func enforcesReviewTextAndRangeBounds() throws {
        var request = reviewContentRequestObject()
        var descriptor = try #require(request["descriptor"] as? [String: Any])
        descriptor["isBinary"] = true
        request["descriptor"] = descriptor
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject()
        descriptor = try #require(request["descriptor"] as? [String: Any])
        descriptor["encoding"] = NSNull()
        request["descriptor"] = descriptor
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject(maximumBytes: 512 * 1024 + 1)
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject(startByte: 101, wholeByteLength: 100)
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject(
            declaredByteLength: 11,
            maximumBytes: 20,
            startByte: 90,
            wholeByteLength: 100
        )
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }

        request = reviewContentRequestObject(declaredByteLength: 21, maximumBytes: 20)
        #expect(throws: (any Error).self) { try decodeContentRequest(request) }
    }

    @Test("requires exact authoritative SHA-256 and bounded provisional digest references")
    func validatesReviewDigestAuthority() {
        let invalidAuthoritative = reviewContentRequestObject(
            digest: [
                "algorithm": "sha256",
                "authority": "authoritative",
                "value": "ABCDEF",
            ]
        )
        let invalidProvisional = reviewContentRequestObject(
            digest: [
                "algorithm": "git oid with spaces",
                "authority": "provisional",
                "value": "0123456789abcdef",
            ]
        )

        #expect(throws: (any Error).self) { try decodeContentRequest(invalidAuthoritative) }
        #expect(throws: (any Error).self) { try decodeContentRequest(invalidProvisional) }
    }
}

private func decodeContentRequest(_ object: [String: Any]) throws -> BridgeProductContentRequest {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try BridgeProductStrictJSON.decode(BridgeProductContentRequest.self, from: data)
}

private func reviewContentRequestObject(
    digest: [String: Any] = [
        "algorithm": "git-oid",
        "authority": "provisional",
        "value": "0123456789abcdef0123456789abcdef01234567",
    ],
    declaredByteLength: Int? = nil,
    expectedSha256: String? = nil,
    maximumBytes: Int = 512 * 1024,
    startByte: Int = 0,
    wholeByteLength: Int = 2_400_000
) -> [String: Any] {
    [
        "contentKind": "review.content",
        "contentRequestId": "review-content-request-1",
        "descriptor": [
            "contentDigest": digest,
            "contentKind": "review.content",
            "declaredByteLength": declaredByteLength.map { $0 as Any } ?? NSNull(),
            "descriptorId": "review-descriptor-1",
            "encoding": "utf-8",
            "endpointId": "review-endpoint-1",
            "expectedSha256": expectedSha256.map { $0 as Any } ?? NSNull(),
            "handleId": "review-handle-1",
            "isBinary": false,
            "itemId": "review-item-1",
            "language": "swift",
            "maximumBytes": maximumBytes,
            "mimeType": "text/plain",
            "packageId": "review-package-1",
            "reviewGeneration": 7,
            "role": "head",
            "sourceIdentity": "review-query-1",
            "wholeByteLength": wholeByteLength,
            "window": [
                "kind": "byteRange",
                "maximumBytes": maximumBytes,
                "startByte": startByte,
            ],
        ],
        "kind": "content.open",
        "leaseId": "review-content-lease-1",
        "paneSessionId": "pane-session-1",
        "wireVersion": 2,
        "workerDerivationEpoch": 4,
        "workerInstanceId": "worker-instance-1",
    ]
}
