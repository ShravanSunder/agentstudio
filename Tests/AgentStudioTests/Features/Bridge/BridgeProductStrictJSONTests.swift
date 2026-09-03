import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite
struct BridgeProductStrictJSONTests {
    @Test("accepts unique, sibling, escaped, and structurally hostile string cases")
    func acceptsUniqueRawJSONCorpusCases() throws {
        let corpus = try fixtureCorpus()

        for fixtureCase in corpus.valid {
            try BridgeProductStrictJSON.validate(Data(fixtureCase.rawJSON.utf8))
        }
    }

    @Test("rejects top-level, nested, array-nested, and escaped-equivalent duplicates")
    func rejectsDuplicateRawJSONCorpusCases() throws {
        let corpus = try fixtureCorpus()

        for fixtureCase in corpus.invalid {
            #expect(throws: BridgeProductStrictJSONError.duplicateObjectMember) {
                try BridgeProductStrictJSON.validate(Data(fixtureCase.rawJSON.utf8))
            }
        }
    }

    @Test("bounds nesting, members, input bytes, UTF-8, and semantic JSON decoding")
    func boundsScannerAndDelegatesSemanticDecode() throws {
        let maximumDepthJSON =
            String(repeating: "[", count: 64) + "0"
            + String(repeating: "]", count: 64)
        let oversizedDepthJSON =
            String(repeating: "[", count: 65) + "0"
            + String(repeating: "]", count: 65)
        let maximumMembersJSON =
            "{"
            + (0..<64).map { "\"member\($0)\":\($0)" }.joined(separator: ",") + "}"
        let oversizedMembersJSON =
            "{"
            + (0..<65).map { "\"member\($0)\":\($0)" }.joined(separator: ",") + "}"

        try BridgeProductStrictJSON.validate(Data(maximumDepthJSON.utf8))
        try BridgeProductStrictJSON.validate(Data(maximumMembersJSON.utf8))
        #expect(throws: BridgeProductStrictJSONError.nestingExceedsCeiling) {
            try BridgeProductStrictJSON.validate(Data(oversizedDepthJSON.utf8))
        }
        #expect(throws: BridgeProductStrictJSONError.objectMemberCountExceedsCeiling) {
            try BridgeProductStrictJSON.validate(Data(oversizedMembersJSON.utf8))
        }
        #expect(throws: BridgeProductStrictJSONError.inputExceedsCeiling) {
            try BridgeProductStrictJSON.validate(Data(repeating: 0, count: 256 * 1024 + 1))
        }
        #expect(throws: BridgeProductStrictJSONError.invalidUTF8) {
            try BridgeProductStrictJSON.validate(Data([0xff]))
        }
        #expect(throws: BridgeProductStrictJSONError.invalidJSON) {
            _ = try BridgeProductStrictJSON.decode(
                KindEnvelope.self,
                from: Data(#"{"kind":"unfinished""#.utf8)
            )
        }
        #expect(
            try BridgeProductStrictJSON.decode(
                KindEnvelope.self,
                from: Data(#"{"kind":"accepted"}"#.utf8)
            ) == KindEnvelope(kind: "accepted")
        )
    }

    @Test("semantic decoding admits only exact ASCII product member names")
    func semanticDecodingRequiresExactProductMemberNames() throws {
        let exactMember = Data(#"{"subscriptionKind":"review.metadata"}"#.utf8)
        let kelvinSpoof = Data(#"{"subscription\u212Aind":"review.metadata"}"#.utf8)
        let exactAndKelvinSpellings = Data(
            #"{"subscriptionKind":"review.metadata","subscription\u212Aind":"file.metadata"}"#.utf8
        )

        #expect(
            try BridgeProductStrictJSON.decode(
                SubscriptionKindEnvelope.self,
                from: exactMember
            ) == SubscriptionKindEnvelope(subscriptionKind: "review.metadata")
        )
        #expect(throws: BridgeProductStrictJSONError.invalidJSON) {
            _ = try BridgeProductStrictJSON.decode(
                SubscriptionKindEnvelope.self,
                from: kelvinSpoof
            )
        }
        #expect(throws: BridgeProductStrictJSONError.invalidJSON) {
            _ = try BridgeProductStrictJSON.decode(
                SubscriptionKindEnvelope.self,
                from: exactAndKelvinSpellings
            )
        }
    }

    @Test("strict product decoding accepts encoded Review diff-role members")
    func acceptsEncodedReviewDiffRoleMembers() throws {
        let descriptorIds = try BridgeProductReviewDescriptorIdsByRole(
            base: nil,
            diff: "review-diff-descriptor",
            file: nil,
            head: nil
        )
        let contentHashes = try BridgeProductReviewContentHashesByRole(
            base: nil,
            diff: String(repeating: "a", count: 64),
            file: nil,
            head: nil
        )

        #expect(
            try BridgeProductStrictJSON.decode(
                BridgeProductReviewDescriptorIdsByRole.self,
                from: JSONEncoder().encode(descriptorIds)
            ) == descriptorIds
        )
        #expect(
            try BridgeProductStrictJSON.decode(
                BridgeProductReviewContentHashesByRole.self,
                from: JSONEncoder().encode(contentHashes)
            ) == contentHashes
        )
    }

    @Test("strict product decoding accepts encoded annotation handled members")
    func acceptsEncodedAnnotationHandledMembers() throws {
        let detail = try makeCommittedDetail()
        let thread = try #require(detail.threads.first?.thread)
        let message = try #require(detail.threads.first?.messages.first)
        let value = try BridgeProductWorktreeAnnotationMessageEntry(
            message: message,
            session: detail.session,
            thread: thread
        )
        let encoded = try JSONEncoder().encode(value)

        #expect(
            try BridgeProductStrictJSON.decode(
                BridgeProductWorktreeAnnotationMessageEntry.self,
                from: encoded
            ) == value
        )
    }

    @Test("encoded annotation drafts preserve a required nullable edit token")
    func encodedAnnotationDraftsPreserveRequiredNullableEditToken() throws {
        let detail = try makeCommittedDetail()
        let thread = try #require(detail.threads.first?.thread)
        let message = try #require(detail.threads.first?.messages.first)
        let draft = WorktreeAnnotationDraft(
            messageID: message.id,
            activeEditToken: nil,
            body: "Recovered draft",
            draftRevision: 1,
            updatedAt: message.updatedAt
        )
        let messageWithRecoveredDraft = WorktreeAnnotationMessage(
            id: message.id,
            threadID: message.threadID,
            ordinal: message.ordinal,
            semanticRevision: message.semanticRevision,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            savedBody: message.savedBody,
            savedRevision: message.savedRevision,
            draft: draft,
            handled: message.handled,
            status: message.status
        )
        let value = try BridgeProductWorktreeAnnotationMessageEntry(
            message: messageWithRecoveredDraft,
            session: detail.session,
            thread: thread
        )
        let encoded = try JSONEncoder().encode(value)
        let encodedString = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(encodedString.contains(#""activeEditToken":null"#))
        #expect(
            try BridgeProductStrictJSON.decode(
                BridgeProductWorktreeAnnotationMessageEntry.self,
                from: encoded
            ) == value
        )
    }

    @Test("strict product decoding accepts every annotation output response member")
    func acceptsEveryAnnotationOutputResponseMember() throws {
        let sessionID = "00000000-0000-7000-8000-000000000011"
        let attemptID = "00000000-0000-7000-8000-000000000012"
        let summary: [String: Any] = [
            "attemptId": attemptID,
            "destinationFilename": "review-comments.json",
            "messageCount": 2,
            "outputKind": "json_file",
            "sessionId": sessionID,
        ]
        let outputOutcomes: [[String: Any]] = [
            ["kind": "destination_cancelled"],
            ["kind": "destination_selection_failed", "selectionError": "cancelled"],
            ["kind": "succeeded", "summary": summary],
            ["effectError": "clipboard unavailable", "kind": "effect_failed", "summary": summary],
            [
                "cleanupError": "cleanup unavailable",
                "effectError": "clipboard unavailable",
                "kind": "effect_and_cleanup_failed",
                "summary": summary,
            ],
            [
                "finalizationError": "history unavailable",
                "kind": "partial_success",
                "summary": summary,
            ],
        ]

        for outputOutcome in outputOutcomes {
            let result = try decodeStrictCallResult(
                sessionID: sessionID,
                status: ["kind": "output", "outcome": outputOutcome]
            )
            #expect(result.method == "review.annotations.command")
        }

        let historyResult = try decodeStrictCallResult(
            sessionID: sessionID,
            status: [
                "kind": "history",
                "summaries": [
                    [
                        "attemptId": attemptID,
                        "canMarkNotHandled": true,
                        "createdAtUnixMilliseconds": 1,
                        "messageCount": 2,
                        "outputKind": "json_file",
                        "repeatedFromAttemptId": attemptID,
                        "sessionId": sessionID,
                        "state": "succeeded",
                        "updatedAtUnixMilliseconds": 2,
                    ]
                ],
            ]
        )
        #expect(historyResult.method == "review.annotations.command")
    }

    private func decodeStrictCallResult(
        sessionID: String,
        status: [String: Any]
    ) throws -> BridgeProductCallResult {
        let object: [String: Any] = [
            "method": "review.annotations.command",
            "result": [
                "kind": "completed",
                "outcome": [
                    "requestId": "annotation-output-response",
                    "sessionId": sessionID,
                    "status": status,
                    "surface": "review",
                ],
            ],
        ]
        return try BridgeProductStrictJSON.decode(
            BridgeProductCallResult.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func fixtureCorpus() throws -> StrictJSONCorpus {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureURL = projectRoot.appending(
            path: "Tests/BridgeContractFixtures/edge/bridge-product-strict-json-corpus.json"
        )
        return try JSONDecoder().decode(StrictJSONCorpus.self, from: Data(contentsOf: fixtureURL))
    }

    private struct KindEnvelope: Decodable, Equatable {
        let kind: String
    }

    private struct SubscriptionKindEnvelope: Decodable, Equatable {
        let subscriptionKind: String
    }

    private struct StrictJSONCorpus: Decodable {
        let valid: [StrictJSONFixtureCase]
        let invalid: [StrictJSONFixtureCase]
    }

    private struct StrictJSONFixtureCase: Decodable {
        let name: String
        let rawJSON: String
    }
}
