import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product Review publication application contract")
struct BridgeProductReviewPublicationAppliedContractTests {
    @Test("requires one lowercase UUIDv7 and a null result")
    func requiresExactUUIDv7AndNullResult() throws {
        let publicationId = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
        let requestObject: [String: Any] = [
            "method": "review.publication.applied",
            "request": ["publicationId": publicationId],
        ]
        let resultObject: [String: Any] = [
            "method": "review.publication.applied",
            "result": NSNull(),
        ]

        let request = try #require(
            decodedValue(BridgeProductCallRequest.self, object: requestObject)
        )
        guard case .reviewPublicationApplied(let appliedRequest) = request else {
            Issue.record("Expected a typed Review publication application request")
            return
        }
        #expect(appliedRequest.publicationId.uuidString.lowercased() == publicationId)
        #expect(decodedValue(BridgeProductCallResult.self, object: resultObject) != nil)

        for invalidPublicationId in [
            publicationId.uppercased(),
            "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "00000000-0000-0000-0000-000000000000",
            "not-a-uuid",
        ] {
            #expect(
                decodedValue(
                    BridgeProductCallRequest.self,
                    object: [
                        "method": "review.publication.applied",
                        "request": ["publicationId": invalidPublicationId],
                    ]
                ) == nil
            )
        }
        #expect(
            decodedValue(
                BridgeProductCallRequest.self,
                object: [
                    "method": "review.publication.applied",
                    "request": ["future": true, "publicationId": publicationId],
                ]
            ) == nil
        )
        #expect(
            decodedValue(
                BridgeProductCallResult.self,
                object: ["method": "review.publication.applied", "result": [:]]
            ) == nil
        )
    }
}

private func decodedValue<CodableValue: Decodable>(
    _ type: CodableValue.Type,
    object: [String: Any]
) -> CodableValue? {
    guard
        let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    else { return nil }
    return try? BridgeProductStrictJSON.decode(type, from: data)
}
