import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

struct WorktreeAnnotationTransportContractTests {
    @Test("File and Review annotation commands use one strict logical operation contract")
    func fileAndReviewCommandsUseStrictSharedOperationContract() throws {
        for (method, expectedSurface) in [
            ("file.annotations.command", BridgeProductSurface.file),
            ("review.annotations.command", BridgeProductSurface.review),
        ] {
            let request = try decodeStrict(
                BridgeProductCallRequest.self,
                object: [
                    "method": method,
                    "request": ["operation": ["kind": "session.discover"]],
                ]
            )
            #expect(request.method == method)
            #expect(request.surface == expectedSurface)

            let result = try decodeStrict(
                BridgeProductCallResult.self,
                object: [
                    "method": method,
                    "result": [
                        "kind": "completed",
                        "outcome": [
                            "requestId": "annotation-product-call-1",
                            "sessionId": NSNull(),
                            "status": ["kind": "committed"],
                            "surface": expectedSurface == .file ? "file" : "review",
                        ],
                    ],
                ]
            )
            #expect(result.method == method)
            #expect(result.surface == expectedSurface)
        }

        #expect(throws: (any Error).self) {
            _ = try decodeStrict(
                BridgeProductCallResult.self,
                object: [
                    "method": "file.annotations.command",
                    "result": ["kind": "completed"],
                ]
            )
        }

        #expect(throws: (any Error).self) {
            _ = try decodeStrict(
                BridgeProductCallRequest.self,
                object: [
                    "method": "file.annotations.command",
                    "request": [
                        "operation": ["kind": "session.discover"],
                        "unexpected": true,
                    ],
                ]
            )
        }
        #expect(throws: (any Error).self) {
            _ = try decodeStrict(
                BridgeProductCallRequest.self,
                object: [
                    "method": "review.annotations.command",
                    "request": ["operation": ["kind": "thread.delete"]],
                ]
            )
        }
    }

    @Test("annotation command registry covers the complete PR1 operation vocabulary")
    func commandRegistryCoversCompletePR1Vocabulary() throws {
        let sessionID = "00000000-0000-7000-8000-000000000011"
        let threadID = "00000000-0000-7000-8000-000000000012"
        let messageID = "00000000-0000-7000-8000-000000000013"
        let attemptID = "00000000-0000-7000-8000-000000000015"
        let operations =
            annotationLifecycleOperations(
                sessionID: sessionID,
                threadID: threadID,
                messageID: messageID
            )
            + annotationOutputOperations(
                sessionID: sessionID,
                messageID: messageID,
                attemptID: attemptID
            )

        for operation in operations {
            do {
                _ = try decodeStrict(
                    BridgeProductCallRequest.self,
                    object: [
                        "method": "file.annotations.command",
                        "request": ["operation": operation],
                    ]
                )
            } catch {
                Issue.record("Failed to decode annotation operation \(operation): \(error)")
            }
        }
    }

    private func annotationLifecycleOperations(
        sessionID: String,
        threadID: String,
        messageID: String
    ) -> [[String: Any]] {
        let commonRevisionFields: [String: Any] = [
            "expectedSessionRevision": 4,
            "sessionId": sessionID,
        ]
        return [
            ["kind": "session.discover"],
            ["kind": "demand.acquire", "sessionId": sessionID],
            ["kind": "demand.release", "sessionId": sessionID],
            [
                "admission": ["kind": "implicitOrSingle"],
                "body": "Durable draft",
                "editToken": "edit-token-1",
                "kind": "root.create",
                "origin": [
                    "diffSide": NSNull(),
                    "endLine": 14,
                    "kind": "located",
                    "path": "Sources/Feature.swift",
                    "sourceIdentity": "source-1",
                    "sourceRole": "file",
                    "startLine": 12,
                ],
            ],
            commonRevisionFields.merging([
                "body": "Reply draft",
                "editToken": "edit-token-2",
                "kind": "reply.create",
                "threadId": threadID,
            ]) { _, new in new },
            commonRevisionFields.merging([
                "body": "Updated draft",
                "editToken": "edit-token-1",
                "expectedDraftRevision": 2,
                "kind": "draft.flush",
                "messageId": messageID,
            ]) { _, new in new },
            commonRevisionFields.merging([
                "editToken": "edit-token-1",
                "expectedDraftRevision": 3,
                "kind": "draft.save",
                "messageId": messageID,
            ]) { _, new in new },
            commonRevisionFields.merging([
                "editToken": "edit-token-1",
                "expectedDraftRevision": 3,
                "kind": "draft.revert",
                "messageId": messageID,
            ]) { _, new in new },
            commonRevisionFields.merging([
                "kind": "thread.resolution.set",
                "resolution": "resolved",
                "threadId": threadID,
            ]) { _, new in new },
            commonRevisionFields.merging([
                "confirmsUnresolvedWork": true,
                "expectedOpenThreadCount": 2,
                "kind": "session.lifecycle.set",
                "lifecycle": "completed",
            ]) { _, new in new },
            commonRevisionFields.merging([
                "decision": "acceptCurrentSource",
                "kind": "continuity.choose",
            ]) { _, new in new },
            [
                "kind": "source.refresh",
                "sessionId": sessionID,
                "sourceEpoch": 5,
            ],
        ]
    }

    private func annotationOutputOperations(
        sessionID: String,
        messageID _: String,
        attemptID: String
    ) -> [[String: Any]] {
        [
            [
                "displayedProjectionRevision": 9,
                "expectedSessionRevision": 4,
                "kind": "output.scope.commit",
                "outputKind": "clipboardMarkdown",
                "scope": "new",
                "sessionId": sessionID,
                "sourceGeneration": 7,
            ],
            [
                "attemptId": attemptID,
                "expectedSessionRevision": 4,
                "kind": "output.handled.clear",
            ],
            ["kind": "output.history", "sessionId": sessionID],
            ["attemptId": attemptID, "kind": "output.repeat"],
            ["kind": "recovery.acknowledge"],
        ]
    }

    @Test("annotation commands reject invalid identities, source coordinates, body size, and selection")
    func annotationCommandsRejectInvalidPayloads() {
        let sessionID = "00000000-0000-7000-8000-000000000011"
        let messageID = "00000000-0000-7000-8000-000000000013"
        let validLocatedOrigin: [String: Any] = [
            "diffSide": NSNull(),
            "endLine": 14,
            "kind": "located",
            "path": "Sources/Feature.swift",
            "sourceIdentity": "source-1",
            "sourceRole": "file",
            "startLine": 12,
        ]

        let invalidOperations: [[String: Any]] = [
            ["kind": "demand.acquire", "sessionId": "00000000-0000-4000-8000-000000000011"],
            [
                "admission": ["kind": "implicitOrSingle"],
                "body": "Forbidden whole-file annotation",
                "editToken": "edit-token-1",
                "kind": "root.create",
                "origin": [
                    "kind": "wholeFile",
                    "path": "Sources/Feature.swift",
                    "sourceIdentity": "source-1",
                    "sourceRole": "file",
                ],
            ],
            [
                "admission": ["kind": "implicitOrSingle"],
                "body": "Forbidden session annotation",
                "editToken": "edit-token-1",
                "kind": "root.create",
                "origin": ["kind": "session", "sourceIdentity": "source-1"],
            ],
            [
                "admission": ["kind": "implicitOrSingle"],
                "body": "Invalid range",
                "editToken": "edit-token-1",
                "kind": "root.create",
                "origin": validLocatedOrigin.merging(["endLine": 11]) { _, new in new },
            ],
            [
                "admission": ["kind": "implicitOrSingle"],
                "body": String(repeating: "é", count: 8193),
                "editToken": "edit-token-1",
                "kind": "root.create",
                "origin": validLocatedOrigin,
            ],
            [
                "kind": "output.selection.begin",
                "outputKind": "clipboardMarkdown",
                "selectionMode": "explicit",
                "sessionId": sessionID,
                "transferId": "transfer-1",
            ],
            [
                "kind": "output.selection.chunk",
                "messageIds": [],
                "ordinal": 0,
                "selectionMode": "explicit",
                "sessionId": sessionID,
                "transferId": "transfer-1",
            ],
            [
                "displayedProjectionRevision": 9,
                "expectedSessionRevision": 4,
                "kind": "output.scope.commit",
                "outputKind": "clipboardMarkdown",
                "scope": "new",
                "sessionId": sessionID,
            ],
            [
                "kind": "output.selection.chunk",
                "messageIds": [messageID],
                "ordinal": 0,
                "selectionMode": "explicit",
                "sessionId": sessionID,
                "transferId": "transfer-1",
                "unexpected": true,
            ],
            [
                "kind": "source.refresh",
                "sessionId": sessionID,
                "sourceEpoch": -1,
            ],
            [
                "kind": "source.refresh",
                "sessionId": sessionID,
                "sourceEpoch": 5,
                "unexpected": true,
            ],
            ["kind": "thread.delete", "sessionId": sessionID],
            ["attemptId": "00000000-0000-7000-8000-000000000015", "kind": "output.inspect"],
        ]

        for operation in invalidOperations {
            #expect(throws: (any Error).self) {
                _ = try decodeAnnotationCommand(method: "file.annotations.command", operation: operation)
            }
        }
    }

    @Test("File and Review output inspection queries return strict annotation output descriptors")
    func outputInspectionQueriesReturnSurfaceBoundContentDescriptors() throws {
        let attemptID = "00000000-0000-7000-8000-000000000015"
        let descriptorID = "00000000-0000-7000-8000-000000000016"
        let digest = String(repeating: "a", count: 64)

        for (method, surface) in [
            ("file.annotations.output.inspect", BridgeProductSurface.file),
            ("review.annotations.output.inspect", BridgeProductSurface.review),
        ] {
            let request = try decodeStrict(
                BridgeProductCallRequest.self,
                object: [
                    "method": method,
                    "request": ["attemptId": attemptID],
                ]
            )
            #expect(request.method == method)
            #expect(request.surface == surface)

            let descriptor: [String: Any] = [
                "attemptId": attemptID,
                "contentKind": "annotation.output",
                "contentType": "text/markdown; charset=utf-8",
                "declaredByteLength": 5,
                "descriptorId": descriptorID,
                "encoding": "utf-8",
                "expectedSha256": digest,
                "formatVersion": 1,
                "maximumBytes": 5,
                "outputKind": "clipboard_markdown",
                "surface": surface.rawValue,
            ]
            let result = try decodeStrict(
                BridgeProductCallResult.self,
                object: [
                    "method": method,
                    "result": ["descriptor": descriptor],
                ]
            )
            #expect(result.method == method)
            #expect(result.surface == surface)

            let contentRequest = try decodeStrict(
                BridgeProductContentRequest.self,
                object: [
                    "contentKind": "annotation.output",
                    "contentRequestId": "annotation-output-content-1",
                    "descriptor": descriptor,
                    "kind": "content.open",
                    "leaseId": "annotation-output-lease-1",
                    "paneSessionId": "00000000-0000-7000-8000-000000000001",
                    "wireVersion": 2,
                    "workerDerivationEpoch": 0,
                    "workerInstanceId": "00000000-0000-7000-8000-000000000002",
                ]
            )
            #expect(contentRequest.surface == surface)
            #expect(contentRequest.admission.identity.surface == surface)

            var wrongSurfaceDescriptor = descriptor
            wrongSurfaceDescriptor["surface"] = surface == .file ? "review" : "file"
            #expect(throws: (any Error).self) {
                _ = try decodeStrict(
                    BridgeProductCallResult.self,
                    object: [
                        "method": method,
                        "result": ["descriptor": wrongSurfaceDescriptor],
                    ]
                )
            }
        }
    }

    @Test("annotation source roles must match the File or Review surface")
    func annotationSourceRolesMatchSurface() throws {
        let commonRoot: [String: Any] = [
            "admission": ["kind": "implicitOrSingle"],
            "body": "Surface-bound origin",
            "editToken": "edit-token-1",
            "kind": "root.create",
        ]
        let fileOrigin: [String: Any] = [
            "diffSide": NSNull(),
            "endLine": 4,
            "kind": "located",
            "path": "Sources/Feature.swift",
            "sourceIdentity": "source-1",
            "sourceRole": "file",
            "startLine": 4,
        ]
        let reviewOrigin: [String: Any] = [
            "diffSide": "additions",
            "endLine": 4,
            "kind": "located",
            "path": "Sources/Feature.swift",
            "sourceIdentity": "source-1",
            "sourceRole": "reviewHead",
            "startLine": 4,
        ]

        let fileRequest = try decodeAnnotationCommand(
            method: "file.annotations.command",
            operation: commonRoot.merging(["origin": fileOrigin]) { _, new in new }
        )
        let reviewRequest = try decodeAnnotationCommand(
            method: "review.annotations.command",
            operation: commonRoot.merging(["origin": reviewOrigin]) { _, new in new }
        )
        let encodedFileRequest = try #require(
            String(data: JSONEncoder().encode(fileRequest), encoding: .utf8)
        )
        let encodedReviewRequest = try #require(
            String(data: JSONEncoder().encode(reviewRequest), encoding: .utf8)
        )
        #expect(encodedFileRequest.contains("\"kind\":\"located\""))
        #expect(encodedReviewRequest.contains("\"kind\":\"located\""))
        #expect(throws: (any Error).self) {
            _ = try decodeAnnotationCommand(
                method: "file.annotations.command",
                operation: commonRoot.merging(["origin": reviewOrigin]) { _, new in new }
            )
        }
        #expect(throws: (any Error).self) {
            _ = try decodeAnnotationCommand(
                method: "review.annotations.command",
                operation: commonRoot.merging(["origin": fileOrigin]) { _, new in new }
            )
        }
    }
}

private func decodeAnnotationCommand(
    method: String,
    operation: [String: Any]
) throws -> BridgeProductCallRequest {
    try decodeStrict(
        BridgeProductCallRequest.self,
        object: [
            "method": method,
            "request": ["operation": operation],
        ]
    )
}

private func decodeStrict<TValue: Decodable>(
    _ type: TValue.Type,
    object: [String: Any]
) throws -> TValue {
    try BridgeProductStrictJSON.decode(
        type,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}
