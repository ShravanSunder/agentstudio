import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product Review publication application contract")
struct BridgeProductReviewPublicationAppliedContractTests {
    @Test("install admission requires exact nullable UUIDv7 identities and a closed status")
    func installAdmissionRequiresExactUUIDv7IdentitiesAndClosedStatus() throws {
        let displayedPublicationId = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
        let candidatePublicationId = "bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb"
        let admittedRequestObject: [String: Any] = [
            "method": "review.publication.install.admit",
            "request": [
                "candidatePublicationId": candidatePublicationId,
                "expectedDisplayedPublicationId": displayedPublicationId,
            ],
        ]
        let bootstrapRequestObject: [String: Any] = [
            "method": "review.publication.install.admit",
            "request": [
                "candidatePublicationId": candidatePublicationId,
                "expectedDisplayedPublicationId": NSNull(),
            ],
        ]

        let admittedRequest = try #require(
            decodedValue(BridgeProductCallRequest.self, object: admittedRequestObject)
        )
        guard case .reviewPublicationInstallAdmission(let admissionRequest) = admittedRequest else {
            Issue.record("Expected a typed Review publication install-admission request")
            return
        }
        #expect(
            admissionRequest.expectedDisplayedPublicationId?.uuidString.lowercased()
                == displayedPublicationId
        )
        #expect(admissionRequest.candidatePublicationId.uuidString.lowercased() == candidatePublicationId)

        let bootstrapRequest = try #require(
            decodedValue(BridgeProductCallRequest.self, object: bootstrapRequestObject)
        )
        guard case .reviewPublicationInstallAdmission(let bootstrapAdmission) = bootstrapRequest else {
            Issue.record("Expected a typed bootstrap Review publication install-admission request")
            return
        }
        #expect(bootstrapAdmission.expectedDisplayedPublicationId == nil)

        for status in ["admitted", "rejected"] {
            #expect(
                decodedValue(
                    BridgeProductCallResult.self,
                    object: [
                        "method": "review.publication.install.admit",
                        "result": ["status": status],
                    ]
                ) != nil
            )
        }

        let invalidRequests: [[String: Any]] = [
            ["candidatePublicationId": candidatePublicationId],
            [
                "candidatePublicationId": candidatePublicationId,
                "expectedDisplayedPublicationId": "not-a-uuid",
            ],
            [
                "candidatePublicationId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                "expectedDisplayedPublicationId": displayedPublicationId,
            ],
            [
                "candidatePublicationId": candidatePublicationId,
                "expectedDisplayedPublicationId": NSNull(),
                "future": true,
            ],
        ]
        for invalidRequest in invalidRequests {
            #expect(
                decodedValue(
                    BridgeProductCallRequest.self,
                    object: [
                        "method": "review.publication.install.admit",
                        "request": invalidRequest,
                    ]
                ) == nil
            )
        }
        for invalidResult in [
            [:],
            ["status": "unknown"],
            ["future": true, "status": "admitted"],
        ] as [[String: Any]] {
            #expect(
                decodedValue(
                    BridgeProductCallResult.self,
                    object: [
                        "method": "review.publication.install.admit",
                        "result": invalidResult,
                    ]
                ) == nil
            )
        }
    }

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
