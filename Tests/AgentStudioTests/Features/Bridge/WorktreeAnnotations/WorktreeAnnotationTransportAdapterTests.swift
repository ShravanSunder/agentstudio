import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation transport adapter")
struct WorktreeAnnotationTransportAdapterTests {
    @Test("viewed command returns exact results and publishes only changed state")
    func viewedCommandReturnsExactResultsAndPublishesOnlyChangedState() async throws {
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let savedMessage = try await createSavedTransportMessage(harness: harness)
        let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: harness.root.appending(path: "local.sqlite"),
            label: "annotation-viewed-adapter-test"
        )
        try await databasePool.write { database in
            try database.execute(
                sql: "UPDATE annotation_message SET author_kind = 'agent' WHERE id = ?",
                arguments: [savedMessage.message.id.databaseValue]
            )
        }
        let before = try await harness.store.captureProjection(
            worktreeID: "worktree-1",
            demandedSessionIDs: [savedMessage.detail.session.id]
        )
        let request = try decodeAnnotationCommand(
            """
            { "operation": {
              "items": [{
                "expectedSavedRevision": \(savedMessage.savedRevision),
                "messageId": "\(savedMessage.message.id.rawValue.uuidString.lowercased())"
              }],
              "kind": "message.viewed.mark",
              "sessionId": "\(savedMessage.detail.session.id.rawValue.uuidString.lowercased())"
            } }
            """
        )

        let changedOutcome = await harness.adapter.apply(
            request,
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "viewed-changed"),
            productAdmission: harness.productAdmission
        )
        let committedSessionRevision = savedMessage.detail.session.semanticRevision + 1
        #expect(changedOutcome.sessionId == savedMessage.detail.session.id.rawValue)
        #expect(changedOutcome.receipt == nil)
        #expect(
            changedOutcome.status
                == .viewed([
                    .viewed(
                        messageId: savedMessage.message.id.rawValue,
                        savedRevision: savedMessage.savedRevision,
                        committedSessionRevision: committedSessionRevision,
                        disposition: .changed
                    )
                ]))
        let afterChanged = try await harness.store.captureProjection(
            worktreeID: "worktree-1",
            demandedSessionIDs: [savedMessage.detail.session.id]
        )
        #expect(afterChanged.revision == before.revision + 1)
        #expect(
            try afterChanged.repositorySnapshot.details.first?.threads.first?.messages.first?
                .projectNewPendingState().attentionState == .viewed
        )

        let repeatedOutcome = await harness.adapter.apply(
            request,
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "viewed-idempotent"),
            productAdmission: harness.productAdmission
        )
        #expect(
            repeatedOutcome.status
                == .viewed([
                    .viewed(
                        messageId: savedMessage.message.id.rawValue,
                        savedRevision: savedMessage.savedRevision,
                        committedSessionRevision: committedSessionRevision,
                        disposition: .alreadyViewed
                    )
                ]))
        let afterRepeated = try await harness.store.captureProjection(
            worktreeID: "worktree-1",
            demandedSessionIDs: [savedMessage.detail.session.id]
        )
        #expect(afterRepeated.revision == afterChanged.revision)
    }

    @Test("committed root command returns its exact outcome and persists durable detail")
    func committedRootCommandReturnsOutcomeAndPersistsDetail() async throws {
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
        let observer = await harness.store.registerChangeObserver(worktreeID: "worktree-1")
        var changes = observer.stream.makeAsyncIterator()
        let outcome = await harness.adapter.apply(
            request,
            surface: .file,
            correlation: correlation,
            productAdmission: harness.productAdmission
        )

        // Assert
        let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(outcome.sessionId))
        let detail = try await persistedDetail(sessionID: sessionID, harness: harness)
        let createdThread = try #require(detail.threads.last)
        let createdMessage = try #require(createdThread.messages.first)
        let receipt = try #require(outcome.receipt)
        #expect(outcome.status == .committed)
        #expect(outcome.requestId == correlation.requestId)
        #expect(outcome.surface == .file)
        #expect(receipt.messageId == createdMessage.id.rawValue)
        #expect(receipt.threadId == createdThread.thread.id.rawValue)
        #expect(receipt.sessionRevision == detail.session.semanticRevision)
        #expect(receipt.messageRevision == createdMessage.semanticRevision)
        #expect(receipt.draftRevision == createdMessage.draft?.draftRevision)
        #expect(receipt.savedRevision == createdMessage.savedRevision)
        let encodedOutcome = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome))
                as? [String: Any]
        )
        let encodedReceipt = try #require(encodedOutcome["receipt"] as? [String: Any])
        #expect(encodedReceipt["messageId"] as? String == createdMessage.id.rawValue.uuidString.lowercased())
        #expect(encodedReceipt["threadId"] as? String == createdThread.thread.id.rawValue.uuidString.lowercased())
        guard
            case .snapshotRequired(let changedWorktreeID, let operationCorrelationID, _) =
                await changes.next()
        else {
            Issue.record("Expected correlated annotation invalidation")
            return
        }
        #expect(changedWorktreeID == "worktree-1")
        #expect(operationCorrelationID.count == 64)
        await harness.store.removeChangeObserver(token: observer.token)
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

    @Test("committed Save returns the exact saved message receipt")
    func committedSaveReturnsExactMessageReceipt() async throws {
        // Arrange
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let createOutcome = await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                {
                  "operation": {
                    "admission": { "kind": "implicitOrSingle" },
                    "body": "Durable draft",
                    "editToken": "editor-save",
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
            correlation: try makeAnnotationCorrelation(requestID: "annotation-save-create"),
            productAdmission: harness.productAdmission
        )
        let createReceipt = try #require(createOutcome.receipt)
        let createDraftRevision = try #require(createReceipt.draftRevision)
        let sessionID = try #require(createOutcome.sessionId)

        // Act
        let saveOutcome = await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                {
                  "operation": {
                    "editToken": "editor-save",
                    "expectedDraftRevision": \(createDraftRevision),
                    "expectedMessageRevision": \(createReceipt.messageRevision),
                    "kind": "draft.save",
                    "messageId": "\(createReceipt.messageId.uuidString.lowercased())",
                    "sessionId": "\(sessionID.uuidString.lowercased())"
                  }
                }
                """
            ),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "annotation-save-commit"),
            productAdmission: harness.productAdmission
        )

        // Assert
        let savedDetail = try await persistedDetail(
            sessionID: WorktreeAnnotationSessionID(rawValue: sessionID),
            harness: harness
        )
        let savedMessage = try #require(savedDetail.threads.first?.messages.first)
        let saveReceipt = try #require(saveOutcome.receipt)
        #expect(saveOutcome.status == .committed)
        #expect(saveReceipt.messageId == savedMessage.id.rawValue)
        #expect(saveReceipt.threadId == savedDetail.threads.first?.thread.id.rawValue)
        #expect(saveReceipt.sessionRevision == savedDetail.session.semanticRevision)
        #expect(saveReceipt.messageRevision == savedMessage.semanticRevision)
        #expect(saveReceipt.draftRevision == nil)
        #expect(saveReceipt.savedRevision == savedMessage.savedRevision)
    }

    @Test("failed service mutation preserves repository detail and returns a typed correlated failure")
    func failedMutationPreservesDetailAndReturnsFailure() async throws {
        // Arrange
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-create-2")
        let createOutcome = await harness.adapter.apply(
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
        let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(createOutcome.sessionId))
        let initialDetail = try await persistedDetail(sessionID: sessionID, harness: harness)
        let message = try #require(initialDetail.threads.first?.messages.first)
        let failingCorrelation = try makeAnnotationCorrelation(requestID: "annotation-flush-conflict")
        let flushRequest = try decodeAnnotationCommand(
            """
            {
              "operation": {
                "body": "Must not commit",
                "editToken": "editor-1",
                "expectedDraftRevision": 0,
                "expectedMessageRevision": 999,
                "kind": "draft.flush",
                "messageId": "\(message.id.rawValue.uuidString.lowercased())",
                "sessionId": "\(sessionID.rawValue.uuidString.lowercased())"
              }
            }
            """
        )

        // Act
        let failureOutcome = await harness.adapter.apply(
            flushRequest,
            surface: .file,
            correlation: failingCorrelation,
            productAdmission: harness.productAdmission
        )

        // Assert
        #expect(failureOutcome.requestId == failingCorrelation.requestId)
        #expect(failureOutcome.status == .failed(.conflict))
        #expect(try await persistedDetail(sessionID: sessionID, harness: harness) == initialDetail)
    }

    @Test("replacement demand admits a restarted source epoch while durable detail remains repository-owned")
    func replacementDemandAdmitsRestartedSourceEpoch() async throws {
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-generation-create")
        let createOutcome = await harness.adapter.apply(
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
        let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(createOutcome.sessionId))

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
            let outcome = await harness.adapter.apply(
                try decodeAnnotationCommand("{ \"operation\": \(operationJSON) }"),
                surface: .file,
                correlation: correlation,
                productAdmission: harness.productAdmission
            )
            #expect(outcome.requestId == requestID)
            #expect(outcome.status == .committed)
        }

        let releaseCorrelation = try makeAnnotationCorrelation(requestID: "annotation-generation-release")
        let releaseOutcome = await harness.adapter.apply(
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

        #expect(releaseOutcome.status == .committed)
        #expect(try await persistedDetail(sessionID: sessionID, harness: harness).session.id == sessionID)
    }

    @Test("output history command returns exactly after reading bounded durable summaries")
    func outputHistoryCommandReturnsAfterReadingDurableSummaries() async throws {
        // Arrange
        let harness = try await makeTransportAdapterHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let savedOutput = try await prepareTransportOutputHistoryFixture(harness: harness)
        let historyCorrelation = try makeAnnotationCorrelation(requestID: "annotation-history-load")

        // Act
        let outcome = await harness.adapter.apply(
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
        #expect(outcome.requestId == historyCorrelation.requestId)
        guard case .history(let summaries) = outcome.status else {
            Issue.record("Expected exact output history, got \(outcome.status)")
            return
        }
        #expect(summaries.map(\.attemptId) == [savedOutput.attemptID.rawValue])
    }

    @Test("prepare output executes the durable coordinator and publishes its typed result")
    func prepareOutputExecutesCoordinatorAndPublishesTypedResult() async throws {
        // Arrange
        let outputEffect = TransportTestOutputEffect(outcome: .succeeded)
        let harness = try await makeTransportAdapterHarness(outputEffect: outputEffect)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let savedFixture = try await prepareSavedOutputCommandFixture(harness: harness)
        let sessionID = savedFixture.sessionID
        let outputCorrelation = try makeAnnotationCorrelation(requestID: "annotation-output-prepare")
        let projection = try await harness.store.captureProjection(
            worktreeID: "worktree-1",
            demandedSessionIDs: [sessionID]
        )
        let sessionRevision = try #require(projection.repositorySnapshot.details.first?.session.semanticRevision)

        // Act
        let exactOutcome = await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                { "operation": {
                  "displayedProjectionRevision": \(projection.revision),
                  "expectedSessionRevision": \(sessionRevision),
                  "kind": "output.scope.commit", "outputKind": "clipboardMarkdown",
                  "scope": "pending", "sessionId": "\(sessionID.rawValue.uuidString.lowercased())",
                  "sourceGeneration": 7
                } }
                """
            ),
            surface: .file,
            correlation: outputCorrelation,
            productAdmission: harness.productAdmission
        )

        // Assert
        let outcome = exactOutcome
        guard case .output(.succeeded(let summary)) = outcome.status else {
            Issue.record("Expected typed successful output outcome, got \(outcome.status)")
            return
        }
        #expect(outcome.requestId == outputCorrelation.requestId)
        #expect(summary.sessionId == sessionID.rawValue)
        #expect(summary.outputKind == .clipboardMarkdown)
        #expect(summary.messageCount == 1)
        let effectRequest = try #require(await outputEffect.lastRequest)
        let effectText = try #require(String(bytes: effectRequest.exactBytes, encoding: .utf8))
        #expect(effectText.contains("## Preserve this behavior"))
        #expect(effectRequest.attemptID == summary.attemptId)
        let persistedOutput = try await harness.store.inspectOutputAttempt(
            attemptID: .init(rawValue: summary.attemptId)
        )
        #expect(persistedOutput.attempt.exactBytes == effectRequest.exactBytes)
        #expect(effectText.contains("Sources/Example.swift"))
        #expect(effectText.contains("Location: lines 2–3"))
        let handledDetail = try await persistedDetail(sessionID: sessionID, harness: harness)
        #expect(handledDetail.threads.first?.messages.first?.handled == true)
        #expect(handledDetail.threads.first?.messages.first?.status == .locked)

        let clearOutcome = await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                { "operation": {
                  "attemptId": "\(summary.attemptId.uuidString.lowercased())",
                  "expectedSessionRevision": \(handledDetail.session.semanticRevision),
                  "kind": "output.handled.clear"
                } }
                """
            ),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "annotation-output-unhandle"),
            productAdmission: harness.productAdmission
        )
        #expect(clearOutcome.status == .committed)
        #expect(await outputEffect.requests.count == 1)
        let clearedDetail = try await persistedDetail(sessionID: sessionID, harness: harness)
        #expect(clearedDetail.threads.first?.messages.first?.handled == false)
        #expect(clearedDetail.threads.first?.messages.first?.status == .locked)
        #expect(
            try await harness.store.fetchOutputHistory(sessionID: sessionID, limit: 10)
                .first?.canMarkNotHandled == false
        )
    }

    @Test("Pending and All output complete saved-message scopes without selection chunks")
    func outputScopesPreserveCanonicalMembership() async throws {
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
                    expectedThreadRevision: try #require(detail.threads.first?.thread.semanticRevision),
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
                    expectedMessageRevision: draft.semanticRevision,
                    expectedDraftRevision: try #require(draft.draft?.draftRevision),
                    now: Date(timeIntervalSince1970: Double(400 + ordinal))
                )
            )
        }
        let orderedMessageIDs = try #require(detail.threads.first).messages.map(\.id)
        #expect(orderedMessageIDs.count == 130)
        try await executeOutputScope(
            harness: harness,
            scope: .pending,
            sessionID: detail.session.id,
            requestID: "pending-scope"
        )
        try await executeOutputScope(
            harness: harness,
            scope: .all,
            sessionID: detail.session.id,
            requestID: "all-scope"
        )

        let requests = await outputEffect.requests
        #expect(requests.count == 2)
        for request in requests {
            let snapshot = try WorktreeAnnotationBatchProjector.decodeJSON(request.exactBytes)
            #expect(snapshot.entries.map(\.messageID) == orderedMessageIDs)
            #expect(snapshot.entries.map(\.batchOrdinal) == Array(0..<130))
        }
    }

    @Test("stale displayed output scope conflicts without an effect or durable transition")
    func staleDisplayedOutputScopeHasNoEffect() async throws {
        let outputEffect = TransportTestOutputEffect(outcome: .succeeded)
        let harness = try await makeTransportAdapterHarness(outputEffect: outputEffect)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let savedFixture = try await prepareSavedOutputCommandFixture(harness: harness)
        let projection = try await harness.store.captureProjection(
            worktreeID: "worktree-1",
            demandedSessionIDs: [savedFixture.sessionID]
        )
        let sessionRevision = try #require(
            projection.repositorySnapshot.details.first?.session.semanticRevision
        )

        let outcome = await harness.adapter.apply(
            try decodeAnnotationCommand(
                """
                { "operation": {
                  "displayedProjectionRevision": \(projection.revision + 1),
                  "expectedSessionRevision": \(sessionRevision),
                  "kind": "output.scope.commit", "outputKind": "clipboardMarkdown",
                  "scope": "pending",
                  "sessionId": "\(savedFixture.sessionID.rawValue.uuidString.lowercased())",
                  "sourceGeneration": 7
                } }
                """
            ),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "stale-output-scope"),
            productAdmission: harness.productAdmission
        )

        #expect(outcome.status == .failed(.conflict))
        #expect(await outputEffect.requests.isEmpty)
        #expect(
            try await harness.store.fetchOutputHistory(
                sessionID: savedFixture.sessionID,
                limit: 10
            ).isEmpty
        )
        let persisted = try await persistedDetail(sessionID: savedFixture.sessionID, harness: harness)
        #expect(persisted.threads.first?.messages.first?.status == .editable)
        #expect(persisted.threads.first?.messages.first?.handled == false)
    }
}

@MainActor
private func prepareSavedOutputCommandFixture(
    harness: WorktreeAnnotationTransportAdapterHarness
) async throws -> (sessionID: WorktreeAnnotationSessionID, message: WorktreeAnnotationMessage) {
    let createCorrelation = try makeAnnotationCorrelation(requestID: "annotation-output-create")
    let createOutcome = await harness.adapter.apply(
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
    let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(createOutcome.sessionId))
    let draftDetail = try await persistedDetail(sessionID: sessionID, harness: harness)
    let draftMessage = try #require(draftDetail.threads.first?.messages.first)
    let savedDetail = try await harness.store.saveDraft(
        .init(
            sessionID: sessionID,
            messageID: draftMessage.id,
            editToken: "editor-output",
            expectedMessageRevision: draftMessage.semanticRevision,
            expectedDraftRevision: try #require(draftMessage.draft?.draftRevision),
            now: Date(timeIntervalSince1970: 101)
        )
    )
    return (sessionID, try #require(savedDetail.threads.first?.messages.first))
}

@MainActor
private func executeOutputScope(
    harness: WorktreeAnnotationTransportAdapterHarness,
    scope: BridgeProductWorktreeAnnotationOperation.OutputScope,
    sessionID: WorktreeAnnotationSessionID,
    requestID: String
) async throws {
    let sessionIDString = sessionID.rawValue.uuidString.lowercased()
    let projection = try await harness.store.captureProjection(
        worktreeID: "worktree-1",
        demandedSessionIDs: [sessionID]
    )
    let sessionRevision = try #require(
        projection.repositorySnapshot.details.first?.session.semanticRevision
    )
    _ = await harness.adapter.apply(
        try decodeAnnotationCommand(
            """
            { "operation": {
              "displayedProjectionRevision": \(projection.revision),
              "expectedSessionRevision": \(sessionRevision),
              "kind": "output.scope.commit", "outputKind": "jsonFile",
              "scope": "\(scope.rawValue)", "sessionId": "\(sessionIDString)",
              "sourceGeneration": 7
            } }
            """
        ),
        surface: .file,
        correlation: try makeAnnotationCorrelation(requestID: requestID),
        productAdmission: harness.productAdmission
    )
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
    let projection = try await harness.store.captureProjection(
        worktreeID: "worktree-1",
        demandedSessionIDs: [savedMessage.detail.session.id]
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
            expectedSessionRevision: savedMessage.detail.session.semanticRevision,
            expectedProjectionRevision: projection.revision,
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
    let createOutcome = await harness.adapter.apply(
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
    let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(createOutcome.sessionId))
    let draftDetail = try await persistedDetail(sessionID: sessionID, harness: harness)
    let draftMessage = try #require(draftDetail.threads.first?.messages.first)
    let savedDetail = try await harness.store.saveDraft(
        .init(
            sessionID: sessionID,
            messageID: draftMessage.id,
            editToken: "editor-history",
            expectedMessageRevision: draftMessage.semanticRevision,
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
    let root: URL
    let store: WorktreeAnnotationServiceActor
}

@MainActor
private func persistedDetail(
    sessionID: WorktreeAnnotationSessionID,
    harness: WorktreeAnnotationTransportAdapterHarness
) async throws -> WorktreeAnnotationSessionDetail {
    let capture = try await harness.store.captureProjection(
        worktreeID: "worktree-1",
        demandedSessionIDs: [sessionID]
    )
    return try #require(capture.repositorySnapshot.details.first)
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
        throw WorktreeAnnotationServiceError.unavailable
    }
    let store = WorktreeAnnotationServiceActor(
        sqliteAdapter: .init(workspaceID: UUIDv7.generate(), datastore: datastore)
    )
    let fingerprint = WorktreeAnnotationSourceFingerprint(
        repositoryID: "repository-1",
        worktreeID: "worktree-1",
        fileSourceIdentity: "file-source-1",
        reviewComparisonOrigin: nil
    )
    let sourceResolver = WorktreeAnnotationSourceResolver(
        capture: { origin, _, _, _ in
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
        currentFingerprint: { _, _, _ in fingerprint },
        refresh: { _, _, _, _ in
            .init(
                fingerprint: fingerprint,
                material: .available([
                    .init(
                        path: "Sources/Example.swift",
                        sourceRole: .file,
                        sourceIdentity: "file-source-1",
                        body: "1 │ func example() {\n2 │ let value = 1\n3 │ return value\n4 │ }"
                    )
                ])
            )
        },
        currentSourceGeneration: { _, _, _ in 7 }
    )
    let outputCoordinator = outputEffect.map {
        WorktreeAnnotationOutputCoordinatorActor(
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
