import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation transport adapter")
struct WorktreeAnnotationTransportAdapterTests {
    @Test("committed root command publishes durable detail and a correlated outcome")
    func committedRootCommandPublishesDetailAndOutcome() async throws {
        // Arrange
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let request = try decodeAnnotationCommand(
            """
            {
              "operation": {
                "admission": { "kind": "implicitOrSingle" },
                "body": "Durable draft",
                "editToken": "editor-1",
                "kind": "root.create",
                "origin": {
                  "diffSide": null,
                  "endLine": 3,
                  "kind": "located",
                  "path": "Sources/Example.swift",
                  "sourceIdentity": "file-source-1",
                  "sourceRole": "file",
                  "startLine": 2
                }
              }
            }
            """
        )
        let correlation = try makeAnnotationCorrelation(requestID: "annotation-create-1")

        // Act
        await harness.adapter.apply(
            request,
            surface: .file,
            correlation: correlation,
            productAdmission: harness.productAdmission
        )

        // Assert
        let outcome = try #require(harness.projection.commandOutcome(requestID: correlation.requestId))
        let sessionID = try #require(outcome.sessionID)
        let detail = try #require(harness.projection.detail(sessionID: sessionID))
        #expect(outcome.status == .committed)
        #expect(detail.threads.first?.messages.first?.draft?.body == "Durable draft")
        #expect(
            detail.threads.first?.thread.origin
                == .located(
                    .init(
                        repositoryRelativePath: "Sources/Example.swift",
                        startLine: 2,
                        endLine: 3,
                        sourceRole: .file,
                        diffSide: nil,
                        sourceIdentity: "file-source-1",
                        selectedExcerpt: "2 │ let value = 1\n3 │ return value",
                        contextBefore: "1 │ func example() {",
                        contextAfter: "4 │ }"
                    )
                )
        )
    }

    @Test("failed Store mutation preserves detail and publishes a typed correlated failure")
    func failedMutationPreservesDetailAndPublishesFailure() async throws {
        // Arrange
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-create-2")
        await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                {
                  "operation": {
                    "admission": { "kind": "implicitOrSingle" },
                    "body": "Durable draft",
                    "editToken": "editor-1",
                    "kind": "root.create",
                    "origin": {
                      "diffSide": null,
                      "endLine": 3,
                      "kind": "located",
                      "path": "Sources/Example.swift",
                      "sourceIdentity": "file-source-1",
                      "sourceRole": "file",
                      "startLine": 2
                    }
                  }
                }
                """
            ),
            surface: .file,
            correlation: createCorrelation,
            productAdmission: harness.productAdmission
        )
        let createOutcome = try #require(
            harness.projection.commandOutcome(requestID: createCorrelation.requestId)
        )
        let sessionID = try #require(createOutcome.sessionID)
        let initialDetail = try #require(harness.projection.detail(sessionID: sessionID))
        let message = try #require(initialDetail.threads.first?.messages.first)
        let failingCorrelation = try makeAnnotationCorrelation(requestID: "annotation-flush-conflict")
        let flushRequest = try decodeAnnotationCommand(
            """
            {
              "operation": {
                "body": "Must not commit",
                "editToken": "editor-1",
                "expectedDraftRevision": 0,
                "expectedSessionRevision": 999,
                "kind": "draft.flush",
                "messageId": "\(message.id.rawValue.uuidString.lowercased())",
                "sessionId": "\(sessionID.rawValue.uuidString.lowercased())"
              }
            }
            """
        )

        // Act
        await harness.adapter.apply(
            flushRequest,
            surface: .file,
            correlation: failingCorrelation,
            productAdmission: harness.productAdmission
        )

        // Assert
        #expect(
            harness.projection.commandOutcome(requestID: failingCorrelation.requestId)?.status
                == .failed(.conflict)
        )
        #expect(harness.projection.detail(sessionID: sessionID) == initialDetail)
    }

    @Test("replacement demand admits a restarted source epoch without leaking detail demand")
    func replacementDemandAdmitsRestartedSourceEpoch() async throws {
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-generation-create")
        await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                {
                  "operation": {
                    "admission": { "kind": "implicitOrSingle" },
                    "body": "Durable draft",
                    "editToken": "editor-generation",
                    "kind": "root.create",
                    "origin": {
                      "diffSide": null,
                      "endLine": 3,
                      "kind": "located",
                      "path": "Sources/Example.swift",
                      "sourceIdentity": "file-source-1",
                      "sourceRole": "file",
                      "startLine": 2
                    }
                  }
                }
                """
            ),
            surface: .file,
            correlation: createCorrelation,
            productAdmission: harness.productAdmission
        )
        let sessionID = try #require(
            harness.projection.commandOutcome(requestID: createCorrelation.requestId)?.sessionID
        )

        for (requestID, sourceEpoch) in [
            ("annotation-generation-acquire-1", nil),
            ("annotation-generation-refresh-2", 2),
            ("annotation-generation-acquire-2", nil),
            ("annotation-generation-refresh-1", 1),
        ] as [(String, Int?)] {
            let operationJSON =
                if let sourceEpoch {
                    """
                    {
                      "kind": "source.refresh",
                      "sessionId": "\(sessionID.rawValue.uuidString.lowercased())",
                      "sourceEpoch": \(sourceEpoch)
                    }
                    """
                } else {
                    """
                    {
                      "kind": "demand.acquire",
                      "sessionId": "\(sessionID.rawValue.uuidString.lowercased())"
                    }
                    """
                }
            let correlation = try makeAnnotationCorrelation(requestID: requestID)
            await harness.adapter.apply(
                try decodeAnnotationCommand("{ \"operation\": \(operationJSON) }"),
                surface: .file,
                correlation: correlation,
                productAdmission: harness.productAdmission
            )
            #expect(harness.projection.commandOutcome(requestID: requestID)?.status == .committed)
        }

        let releaseCorrelation = try makeAnnotationCorrelation(requestID: "annotation-generation-release")
        await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                {
                  "operation": {
                    "kind": "demand.release",
                    "sessionId": "\(sessionID.rawValue.uuidString.lowercased())"
                  }
                }
                """
            ),
            surface: .file,
            correlation: releaseCorrelation,
            productAdmission: harness.productAdmission
        )

        #expect(harness.projection.commandOutcome(requestID: releaseCorrelation.requestId)?.status == .committed)
        #expect(harness.projection.detail(sessionID: sessionID) == nil)
    }

    @Test("output history command publishes bounded durable summaries")
    func outputHistoryCommandPublishesBoundedSummaries() async throws {
        // Arrange
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let savedOutput = try await prepareTransportOutputHistoryFixture(harness: harness)
        let historyCorrelation = try makeAnnotationCorrelation(requestID: "annotation-history-load")

        // Act
        await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                { "operation": {
                  "kind": "output.history",
                  "sessionId": "\(savedOutput.sessionID.rawValue.uuidString.lowercased())"
                } }
                """
            ),
            surface: .file,
            correlation: historyCorrelation,
            productAdmission: harness.productAdmission
        )

        // Assert
        #expect(
            harness.projection.commandOutcome(requestID: historyCorrelation.requestId)?.status
                == .committed
        )
        #expect(
            harness.projection.outputHistoryBySessionID[savedOutput.sessionID]?.map(\.attemptID)
                == [savedOutput.attemptID]
        )
    }

    @Test("prepare output executes the durable coordinator and publishes its typed result")
    func prepareOutputExecutesCoordinatorAndPublishesTypedResult() async throws {
        // Arrange
        let outputEffect = TransportTestOutputEffect(outcome: .succeeded)
        let harness = try await makeTransportAdapterHarness(outputEffect: outputEffect)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-output-create")
        await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                {
                  "operation": {
                    "admission": { "kind": "implicitOrSingle" },
                    "body": "## Preserve this behavior",
                    "editToken": "editor-output",
                    "kind": "root.create",
                    "origin": {
                      "diffSide": null,
                      "endLine": 3,
                      "kind": "located",
                      "path": "Sources/Example.swift",
                      "sourceIdentity": "file-source-1",
                      "sourceRole": "file",
                      "startLine": 2
                    }
                  }
                }
                """
            ),
            surface: .file,
            correlation: createCorrelation,
            productAdmission: harness.productAdmission
        )
        let sessionID = try #require(
            harness.projection.commandOutcome(requestID: createCorrelation.requestId)?.sessionID
        )
        let draftDetail = try #require(harness.projection.detail(sessionID: sessionID))
        let draftMessage = try #require(draftDetail.threads.first?.messages.first)
        let savedDetail = try await harness.store.saveDraft(
            .init(
                sessionID: sessionID,
                messageID: draftMessage.id,
                editToken: "editor-output",
                expectedSessionRevision: draftDetail.session.semanticRevision,
                expectedDraftRevision: try #require(draftMessage.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 101)
            )
        )
        let savedMessage = try #require(savedDetail.threads.first?.messages.first)
        let outputCorrelation = try makeAnnotationCorrelation(requestID: "annotation-output-prepare")

        // Act
        let transferID = "annotation-output-transfer-1"
        for (requestID, operation) in [
            (
                "annotation-output-begin",
                """
                { "kind": "output.selection.begin", "outputKind": "clipboardMarkdown",
                  "selectionMode": "explicit", "sessionId": "\(sessionID.rawValue.uuidString.lowercased())",
                  "transferId": "\(transferID)" }
                """
            ),
            (
                "annotation-output-chunk",
                """
                { "kind": "output.selection.chunk",
                  "messageIds": ["\(savedMessage.id.rawValue.uuidString.lowercased())"], "ordinal": 0,
                  "selectionMode": "explicit", "sessionId": "\(sessionID.rawValue.uuidString.lowercased())",
                  "transferId": "\(transferID)" }
                """
            ),
            (
                outputCorrelation.requestId,
                """
                { "kind": "output.selection.commit", "selectionMode": "explicit",
                  "sessionId": "\(sessionID.rawValue.uuidString.lowercased())", "transferId": "\(transferID)" }
                """
            ),
        ] {
            await harness.adapter.apply(
                try decodeAnnotationCommand("{ \"operation\": \(operation) }"),
                surface: .file,
                correlation: try makeAnnotationCorrelation(requestID: requestID),
                productAdmission: harness.productAdmission
            )
        }

        // Assert
        let outcome = try #require(
            harness.projection.commandOutcome(requestID: outputCorrelation.requestId)
        )
        guard case .output(.succeeded(let summary)) = outcome.status else {
            Issue.record("Expected typed successful output outcome, got \(outcome.status)")
            return
        }
        #expect(summary.sessionID == sessionID)
        #expect(summary.outputKind == .clipboardMarkdown)
        #expect(summary.messageCount == 1)
        let effectRequest = try #require(await outputEffect.lastRequest)
        let effectText = try #require(String(bytes: effectRequest.exactBytes, encoding: .utf8))
        #expect(effectText.contains("## Preserve this behavior"))
        #expect(effectRequest.attemptID == summary.attemptID.rawValue)
    }

    @Test("130 eligible messages preserve the middle 65 through explicit and complementary all-eligible transfers")
    func arbitraryOutputSelectionPreservesCanonicalMembership() async throws {
        let outputEffect = TransportTestOutputEffect(outcome: .failed("proof effect"))
        let harness = try await makeTransportAdapterHarness(outputEffect: outputEffect)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let savedRoot = try await createSavedTransportMessage(harness: harness)
        var detail = savedRoot.detail
        let threadID = try #require(detail.threads.first?.thread.id)
        for ordinal in 1..<130 {
            let editToken = "selection-reply-\(ordinal)"
            detail = try await harness.store.createReplyDraft(
                .init(
                    sessionID: detail.session.id,
                    threadID: threadID,
                    expectedSessionRevision: detail.session.semanticRevision,
                    body: "Request \(ordinal)",
                    editToken: editToken,
                    now: Date(timeIntervalSince1970: Double(200 + ordinal))
                )
            )
            let draft = try #require(detail.threads.first?.messages.last)
            detail = try await harness.store.saveDraft(
                .init(
                    sessionID: detail.session.id,
                    messageID: draft.id,
                    editToken: editToken,
                    expectedSessionRevision: detail.session.semanticRevision,
                    expectedDraftRevision: try #require(draft.draft?.draftRevision),
                    now: Date(timeIntervalSince1970: Double(400 + ordinal))
                )
            )
        }
        let orderedMessageIDs = try #require(detail.threads.first).messages.map(\.id)
        #expect(orderedMessageIDs.count == 130)
        let middle = Array(orderedMessageIDs[32..<97])
        let complement = orderedMessageIDs.filter { !Set(middle).contains($0) }

        try await executeOutputTransfer(
            harness: harness,
            messageIDs: middle,
            mode: .explicit,
            sessionID: detail.session.id,
            transferID: "middle-explicit"
        )
        try await executeOutputTransfer(
            harness: harness,
            messageIDs: complement,
            mode: .allEligible,
            sessionID: detail.session.id,
            transferID: "complement-excluded"
        )

        let requests = await outputEffect.requests
        #expect(requests.count == 2)
        for request in requests {
            let snapshot = try WorktreeAnnotationBatchProjector.decodeJSON(request.exactBytes)
            #expect(snapshot.entries.map(\.messageID) == middle)
            #expect(snapshot.entries.map(\.batchOrdinal) == Array(0..<65))
        }
    }
}

@MainActor
private func executeOutputTransfer(
    harness: WorktreeAnnotationTransportAdapterHarness,
    messageIDs: [WorktreeAnnotationMessageID],
    mode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode,
    sessionID: WorktreeAnnotationSessionID,
    transferID: String
) async throws {
    let sessionIDString = sessionID.rawValue.uuidString.lowercased()
    let outputKind = "jsonFile"
    let operations: [String] =
        [
            """
            { "kind": "output.selection.begin", "outputKind": "\(outputKind)",
              "selectionMode": "\(mode.rawValue)", "sessionId": "\(sessionIDString)",
              "transferId": "\(transferID)" }
            """
        ]
        + stride(from: 0, to: messageIDs.count, by: 64).enumerated().map { ordinal, offset in
            let ids = messageIDs[offset..<min(offset + 64, messageIDs.count)]
                .map { "\"\($0.rawValue.uuidString.lowercased())\"" }
                .joined(separator: ",")
            return """
                { "kind": "output.selection.chunk", "messageIds": [\(ids)], "ordinal": \(ordinal),
                  "selectionMode": "\(mode.rawValue)", "sessionId": "\(sessionIDString)",
                  "transferId": "\(transferID)" }
                """
        } + [
            """
            { "kind": "output.selection.commit", "selectionMode": "\(mode.rawValue)",
              "sessionId": "\(sessionIDString)", "transferId": "\(transferID)" }
            """
        ]
    for (index, operation) in operations.enumerated() {
        await harness.adapter.apply(
            try decodeAnnotationCommand("{ \"operation\": \(operation) }"),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "\(transferID)-\(index)"),
            productAdmission: harness.productAdmission
        )
    }
}

private struct TransportOutputHistoryFixture {
    let attemptID: WorktreeAnnotationOutputAttemptID
    let sessionID: WorktreeAnnotationSessionID
}

@MainActor
private func prepareTransportOutputHistoryFixture(
    harness: WorktreeAnnotationTransportAdapterHarness
) async throws -> TransportOutputHistoryFixture {
    let savedMessage = try await createSavedTransportMessage(harness: harness)
    let attemptID = WorktreeAnnotationOutputAttemptID.generate()
    let selectedMessages = [
        WorktreeAnnotationSQLiteRepository.OutputMessageSelection(
            messageID: savedMessage.message.id,
            expectedSavedRevision: savedMessage.savedRevision
        )
    ]
    let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
        .init(
            batchID: attemptID,
            createdAt: Date(timeIntervalSince1970: 102),
            sessionDetail: savedMessage.detail,
            selectedMessages: selectedMessages,
            placementsByThreadID: [:],
            sessionLabel: "Current review",
            worktreeLabel: "worktree-1",
            comparisonLabel: nil
        )
    )
    let markdownPresentation = WorktreeAnnotationMarkdownPresentationContext(
        worktreeLabel: "worktree-1",
        comparisonLabel: nil
    )
    _ = try await harness.store.prepareOutput(
        .init(
            attemptID: attemptID,
            sessionID: savedMessage.detail.session.id,
            outputKind: .clipboardMarkdown,
            formatVersion: snapshot.formatVersion,
            contentType: "text/markdown; charset=utf-8",
            canonicalSnapshot: snapshot,
            exactBytes: WorktreeAnnotationBatchProjector.markdownData(
                for: snapshot,
                presentation: markdownPresentation
            ),
            markdownPresentation: markdownPresentation,
            destinationPath: nil,
            repeatedFromAttemptID: nil,
            selectedMessages: selectedMessages,
            now: Date(timeIntervalSince1970: 102)
        )
    )
    _ = try await harness.store.finalizeOutputAttempt(
        attemptID: attemptID,
        eventKind: .copied,
        now: Date(timeIntervalSince1970: 103)
    )
    return .init(attemptID: attemptID, sessionID: savedMessage.detail.session.id)
}

private struct SavedTransportMessage {
    let detail: WorktreeAnnotationSessionDetail
    let message: WorktreeAnnotationMessage
    let savedRevision: Int
}

@MainActor
private func createSavedTransportMessage(
    harness: WorktreeAnnotationTransportAdapterHarness
) async throws -> SavedTransportMessage {
    let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-history-create")
    await harness.adapter.apply(
        try decodeAnnotationCommand(
            """
            {
              "operation": {
                "admission": { "kind": "implicitOrSingle" },
                "body": "Durable output body",
                "editToken": "editor-history",
                "kind": "root.create",
                "origin": {
                  "diffSide": null,
                  "endLine": 3,
                  "kind": "located",
                  "path": "Sources/Example.swift",
                  "sourceIdentity": "file-source-1",
                  "sourceRole": "file",
                  "startLine": 2
                }
              }
            }
            """
        ),
        surface: .file,
        correlation: createCorrelation,
        productAdmission: harness.productAdmission
    )
    let sessionID = try #require(
        harness.projection.commandOutcome(requestID: createCorrelation.requestId)?.sessionID
    )
    let draftDetail = try #require(harness.projection.detail(sessionID: sessionID))
    let draftMessage = try #require(draftDetail.threads.first?.messages.first)
    let savedDetail = try await harness.store.saveDraft(
        .init(
            sessionID: sessionID,
            messageID: draftMessage.id,
            editToken: "editor-history",
            expectedSessionRevision: draftDetail.session.semanticRevision,
            expectedDraftRevision: try #require(draftMessage.draft?.draftRevision),
            now: Date(timeIntervalSince1970: 101)
        )
    )
    let savedMessage = try #require(savedDetail.threads.first?.messages.first)
    return try .init(
        detail: savedDetail,
        message: savedMessage,
        savedRevision: #require(savedMessage.savedRevision)
    )
}

@MainActor
private struct WorktreeAnnotationTransportAdapterHarness {
    let adapter: WorktreeAnnotationTransportAdapter
    let productAdmission: BridgeProductAdmissionContext
    let projection: WorktreeAnnotationProjectionAtom
    let root: URL
    let store: WorktreeAnnotationStore
}

@MainActor
private func makeTransportAdapterHarness(
    outputEffect: (any WorktreeAnnotationOutputEffect)? = nil
) async throws -> WorktreeAnnotationTransportAdapterHarness {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "annotation-transport-adapter-\(UUIDv7.generate().uuidString)"
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let datastore = WorkspaceSQLiteDatastoreFactory(
        coreDatabaseURL: root.appending(path: "core.sqlite"),
        localDatabaseURL: root.appending(path: "local.sqlite")
    ).makeDatastore()
    guard case .prepared = await datastore.prepareDatabasesForBoot() else {
        throw WorktreeAnnotationStoreError.unavailable
    }
    let projection = WorktreeAnnotationProjectionAtom()
    let store = WorktreeAnnotationStore(
        projection: projection,
        sqliteAdapter: .init(workspaceID: UUIDv7.generate(), datastore: datastore)
    )
    let fingerprint = WorktreeAnnotationSourceFingerprint(
        repositoryID: "repository-1",
        worktreeID: "worktree-1",
        fileSourceIdentity: "file-source-1",
        reviewComparisonOrigin: nil
    )
    let sourceResolver = WorktreeAnnotationSourceResolver(
        capture: { origin, _, _ in
            .init(
                fingerprint: fingerprint,
                origin: .located(
                    .init(
                        repositoryRelativePath: origin.path,
                        startLine: origin.startLine,
                        endLine: origin.endLine,
                        sourceRole: .file,
                        diffSide: nil,
                        sourceIdentity: origin.sourceIdentity,
                        selectedExcerpt: "2 │ let value = 1\n3 │ return value",
                        contextBefore: "1 │ func example() {",
                        contextAfter: "4 │ }"
                    )
                )
            )
        },
        currentFingerprint: { _, _ in fingerprint },
        refresh: { _, _, _ in
            .init(fingerprint: fingerprint, material: .available([]))
        }
    )
    let outputCoordinator = outputEffect.map {
        WorktreeAnnotationOutputCoordinator(
            store: store,
            effect: $0,
            now: { Date(timeIntervalSince1970: 102) }
        )
    }
    return try WorktreeAnnotationTransportAdapterHarness(
        adapter: WorktreeAnnotationTransportAdapter(
            store: store,
            contextID: "pane-test",
            repositoryID: fingerprint.repositoryID,
            worktreeID: fingerprint.worktreeID,
            originatingWorkspaceID: nil,
            sourceResolver: sourceResolver,
            now: { Date(timeIntervalSince1970: 100) },
            outputCoordinator: outputCoordinator,
            outputLabels: .init(
                sessionLabel: "Current review",
                worktreeLabel: "agent-studio.review-comments",
                comparisonLabel: nil
            )
        ),
        productAdmission: BridgeProductAdmissionTestContext.make().context,
        projection: projection,
        root: root,
        store: store
    )
}

private actor TransportTestOutputEffect: WorktreeAnnotationOutputEffect {
    private let outcome: WorktreeAnnotationOutputEffectOutcome
    private(set) var requests: [WorktreeAnnotationOutputEffectRequest] = []
    var lastRequest: WorktreeAnnotationOutputEffectRequest? { requests.last }

    init(outcome: WorktreeAnnotationOutputEffectOutcome) {
        self.outcome = outcome
    }

    func chooseJSONDestination(
        suggestedFilename: String
    ) -> WorktreeAnnotationOutputDestinationOutcome {
        _ = suggestedFilename
        return .selected(path: "/tmp/transport-output.json")
    }

    func perform(
        _ request: WorktreeAnnotationOutputEffectRequest
    ) -> WorktreeAnnotationOutputEffectOutcome {
        requests.append(request)
        return outcome
    }
}

private func decodeAnnotationCommand(
    _ json: String
) throws -> BridgeProductWorktreeAnnotationCommandRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductWorktreeAnnotationCommandRequest.self,
        from: Data(json.utf8)
    )
}

private func makeAnnotationCorrelation(requestID: String) throws -> BridgeProductControlCorrelation {
    try BridgeProductControlCorrelation(
        paneSessionId: "00000000-0000-7000-8000-000000000001",
        requestId: requestID,
        requestSequence: 1,
        workerInstanceId: "00000000-0000-7000-8000-000000000002"
    )
}
