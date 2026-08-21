import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation projection source")
struct WorktreeAnnotationProjectionSourceTests {
    @Test("initial query is surface and source-generation bound and yields page zero")
    func initialQueryValidatesAuthorityAndYieldsPageZero() async throws {
        let harness = try await makeProjectionSourceHarness(messageCount: 1)

        let descriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: try projectionControlRequest(surface: .file),
            productAdmission: harness.productAdmission
        )

        #expect(descriptor.surface == .file)
        #expect(descriptor.page.pageOrdinal == 0)
        #expect(descriptor.page.sourceGeneration == harness.sourceGeneration)
        #expect(descriptor.page.expectedSessionCount == 1)
        #expect(descriptor.page.expectedThreadCount == 1)
        #expect(descriptor.page.expectedMessageCount == 1)

        await #expect(
            throws: BridgeAnnotationProjectionSourceError.staleSourceGeneration(
                currentSourceGeneration: harness.sourceGeneration
            )
        ) {
            _ = try await harness.source.descriptor(
                for: try projectionQuery(
                    sessionID: harness.detail.session.id,
                    sourceGeneration: harness.sourceGeneration + 1,
                    surface: .file
                ),
                issuing: try projectionControlRequest(surface: .file),
                productAdmission: harness.productAdmission
            )
        }
        await #expect(throws: BridgeAnnotationProjectionSourceError.unavailable) {
            _ = try await harness.source.descriptor(
                for: try projectionQuery(
                    sessionID: harness.detail.session.id,
                    sourceGeneration: harness.sourceGeneration,
                    surface: .file
                ),
                issuing: try projectionControlRequest(surface: .review),
                productAdmission: harness.productAdmission
            )
        }
    }

    @Test("descriptor is single-use and exact worker and pane authority bound")
    func descriptorIsSingleUseAndAuthorityBound() async throws {
        let harness = try await makeProjectionSourceHarness(messageCount: 1)
        let issuingRequest = try projectionControlRequest(surface: .file)
        let descriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )

        await #expect(throws: BridgeAnnotationProjectionSourceError.descriptorMismatch) {
            _ = try await harness.source.claim(
                try projectionContentRequest(
                    descriptor: descriptor,
                    paneSessionID: "pane-foreign",
                    workerInstanceID: issuingRequest.workerInstanceId
                )
            )
        }

        let workerBoundDescriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        await #expect(throws: BridgeAnnotationProjectionSourceError.descriptorMismatch) {
            _ = try await harness.source.claim(
                try projectionContentRequest(
                    descriptor: workerBoundDescriptor,
                    paneSessionID: issuingRequest.paneSessionId,
                    workerInstanceID: "worker-foreign"
                )
            )
        }

        let replacement = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        let contentRequest = try projectionContentRequest(
            descriptor: replacement,
            paneSessionID: issuingRequest.paneSessionId,
            workerInstanceID: issuingRequest.workerInstanceId
        )
        _ = try await harness.source.claim(contentRequest)

        await #expect(throws: BridgeAnnotationProjectionSourceError.descriptorMismatch) {
            _ = try await harness.source.claim(contentRequest)
        }
    }

    @Test("continuation requires prior claim and rejects wrong and stale cursors")
    func continuationIsClaimOrderedAndSnapshotBound() async throws {
        let harness = try await makeProjectionSourceHarness(messageCount: 136)
        let issuingRequest = try projectionControlRequest(surface: .file)
        let firstDescriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        let nextCursor = try #require(firstDescriptor.page.nextCursor)
        #expect(!firstDescriptor.page.isLastPage)

        await #expect(throws: BridgeAnnotationProjectionSourceError.invalidCursor) {
            _ = try await harness.source.descriptor(
                for: try projectionQuery(
                    sessionID: harness.detail.session.id,
                    sourceGeneration: harness.sourceGeneration,
                    surface: .file,
                    cursor: nextCursor
                ),
                issuing: issuingRequest,
                productAdmission: harness.productAdmission
            )
        }

        _ = try await harness.source.claim(
            try projectionContentRequest(
                descriptor: firstDescriptor,
                paneSessionID: issuingRequest.paneSessionId,
                workerInstanceID: issuingRequest.workerInstanceId
            )
        )
        await #expect(throws: BridgeAnnotationProjectionSourceError.invalidCursor) {
            _ = try await harness.source.descriptor(
                for: try projectionQuery(
                    sessionID: harness.detail.session.id,
                    sourceGeneration: harness.sourceGeneration,
                    surface: .file,
                    cursor: "wrong-cursor"
                ),
                issuing: issuingRequest,
                productAdmission: harness.productAdmission
            )
        }

        let secondDescriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file,
                cursor: nextCursor
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        #expect(secondDescriptor.page.pageOrdinal == 1)
        #expect(secondDescriptor.page.snapshotID == firstDescriptor.page.snapshotID)

        await #expect(throws: BridgeAnnotationProjectionSourceError.invalidCursor) {
            _ = try await harness.source.descriptor(
                for: try projectionQuery(
                    sessionID: harness.detail.session.id,
                    sourceGeneration: harness.sourceGeneration,
                    surface: .file,
                    cursor: nextCursor
                ),
                issuing: issuingRequest,
                productAdmission: harness.productAdmission
            )
        }
    }

    @Test("new initial query replaces prior snapshot and descriptors")
    func newInitialQueryReplacesPriorReservation() async throws {
        let harness = try await makeProjectionSourceHarness(messageCount: 1)
        let issuingRequest = try projectionControlRequest(surface: .file)
        let query = try projectionQuery(
            sessionID: harness.detail.session.id,
            sourceGeneration: harness.sourceGeneration,
            surface: .file
        )
        let firstDescriptor = try await harness.source.descriptor(
            for: query,
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        let secondDescriptor = try await harness.source.descriptor(
            for: query,
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )

        #expect(firstDescriptor.page.snapshotID != secondDescriptor.page.snapshotID)
        await #expect(throws: BridgeAnnotationProjectionSourceError.descriptorMismatch) {
            _ = try await harness.source.claim(
                try projectionContentRequest(
                    descriptor: firstDescriptor,
                    paneSessionID: issuingRequest.paneSessionId,
                    workerInstanceID: issuingRequest.workerInstanceId
                )
            )
        }
        _ = try await harness.source.claim(
            try projectionContentRequest(
                descriptor: secondDescriptor,
                paneSessionID: issuingRequest.paneSessionId,
                workerInstanceID: issuingRequest.workerInstanceId
            )
        )
    }

    @Test("native source evaluation determines located placement")
    func nativeSourceEvaluationDeterminesLocatedPlacement() async throws {
        let harness = try await makeProjectionSourceHarness(messageCount: 1)
        let issuingRequest = try projectionControlRequest(surface: .file)
        let descriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        var page = try await harness.source.claim(
            try projectionContentRequest(
                descriptor: descriptor,
                paneSessionID: issuingRequest.paneSessionId,
                workerInstanceID: issuingRequest.workerInstanceId
            )
        )
        let records = try collectProjectionRecords(cursor: &page.cursor)
        let messageRecords: [BridgeProductAnnotationProjectionMessageRecord] = records.compactMap { record in
            guard case .message(let message) = record else { return nil }
            return message
        }
        let messageRecord = try #require(messageRecords.first)

        #expect(messageRecord.context.placement == .relocated)
        #expect(messageRecord.context.path == "Sources/RenamedFeature.swift")
        #expect(messageRecord.context.startLine == 2)
        #expect(messageRecord.context.endLine == 2)
        #expect(messageRecord.context.sourceIdentity == "source-current")
    }

    @Test("close invalidates every descriptor and continuation")
    func closeInvalidatesDescriptorsAndCursors() async throws {
        let harness = try await makeProjectionSourceHarness(messageCount: 270)
        let issuingRequest = try projectionControlRequest(surface: .file)
        let firstDescriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        let firstCursor = try #require(firstDescriptor.page.nextCursor)
        _ = try await harness.source.claim(
            try projectionContentRequest(
                descriptor: firstDescriptor,
                paneSessionID: issuingRequest.paneSessionId,
                workerInstanceID: issuingRequest.workerInstanceId
            )
        )
        let outstandingDescriptor = try await harness.source.descriptor(
            for: try projectionQuery(
                sessionID: harness.detail.session.id,
                sourceGeneration: harness.sourceGeneration,
                surface: .file,
                cursor: firstCursor
            ),
            issuing: issuingRequest,
            productAdmission: harness.productAdmission
        )
        let nextCursor = try #require(outstandingDescriptor.page.nextCursor)
        await harness.source.close()

        await #expect(throws: BridgeAnnotationProjectionSourceError.descriptorMismatch) {
            _ = try await harness.source.claim(
                try projectionContentRequest(
                    descriptor: outstandingDescriptor,
                    paneSessionID: issuingRequest.paneSessionId,
                    workerInstanceID: issuingRequest.workerInstanceId
                )
            )
        }
        await #expect(throws: BridgeAnnotationProjectionSourceError.invalidCursor) {
            _ = try await harness.source.descriptor(
                for: try projectionQuery(
                    sessionID: harness.detail.session.id,
                    sourceGeneration: harness.sourceGeneration,
                    surface: .file,
                    cursor: nextCursor
                ),
                issuing: issuingRequest,
                productAdmission: harness.productAdmission
            )
        }
    }
}

private struct ProjectionSourceHarness {
    let detail: WorktreeAnnotationSessionDetail
    let productAdmission: BridgeProductAdmissionContext
    let source: BridgeAnnotationProjectionSource
    let sourceGeneration: Int
}

private func makeProjectionSourceHarness(messageCount: Int) async throws -> ProjectionSourceHarness {
    let baseDetail = try makeLocatedCommittedDetail()
    let detail = projectionDetail(base: baseDetail, messageCount: messageCount)
    let repositoryAccess = ProjectionSnapshotRepositoryAccess(detail: detail)
    let service = WorktreeAnnotationServiceActor(repositoryAccess: repositoryAccess)
    let sourceGeneration = 7
    let sourceFingerprint = makeSourceFingerprint(identity: "source-current")
    let sourceResolver = WorktreeAnnotationSourceResolver(
        capture: { _, _, _ in throw WorktreeAnnotationSourceResolutionError.unavailable },
        currentFingerprint: { _, _ in sourceFingerprint },
        refresh: { _, _, _ in
            WorktreeAnnotationSourceRefreshCapture(
                fingerprint: sourceFingerprint,
                material: .available([
                    .init(
                        path: "Sources/RenamedFeature.swift",
                        sourceRole: .file,
                        sourceIdentity: "source-current",
                        body: "before\nselected line\nafter\n"
                    )
                ])
            )
        }
    )
    return ProjectionSourceHarness(
        detail: detail,
        productAdmission: try BridgeProductAdmissionTestContext.make().context,
        source: BridgeAnnotationProjectionSource(
            service: service,
            sourceResolver: sourceResolver,
            worktreeID: detail.session.worktreeID,
            currentSourceGeneration: { _, _ in sourceGeneration }
        ),
        sourceGeneration: sourceGeneration
    )
}

private func projectionDetail(
    base: WorktreeAnnotationSessionDetail,
    messageCount: Int
) -> WorktreeAnnotationSessionDetail {
    precondition(messageCount > 0)
    let thread = base.threads[0].thread
    let body = String(repeating: "m", count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes)
    let messages = (0..<messageCount).map { ordinal in
        WorktreeAnnotationMessage(
            id: .generate(),
            threadID: thread.id,
            ordinal: ordinal,
            semanticRevision: 1,
            createdAt: Date(timeIntervalSince1970: TimeInterval(ordinal + 1)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(ordinal + 1)),
            savedBody: body,
            savedRevision: 1,
            draft: nil,
            handled: false,
            status: .editable
        )
    }
    return WorktreeAnnotationSessionDetail(
        session: base.session,
        threads: [.init(thread: thread, messages: messages)]
    )
}

private func projectionQuery(
    sessionID: WorktreeAnnotationSessionID,
    sourceGeneration: Int,
    surface: BridgeProductSurface,
    cursor: String? = nil
) throws -> BridgeProductAnnotationProjectionQueryRequest {
    let object: [String: Any] = [
        "cursor": cursor ?? NSNull(),
        "sessionIds": [sessionID.rawValue.uuidString.lowercased()],
        "sourceGeneration": sourceGeneration,
        "surface": surface.rawValue,
    ]
    return try BridgeProductStrictJSON.decode(
        BridgeProductAnnotationProjectionQueryRequest.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func projectionControlRequest(
    surface: BridgeProductSurface,
    paneSessionID: String = "pane-session-1",
    workerInstanceID: String = "worker-instance-1"
) throws -> BridgeProductControlRequest {
    let method = "\(surface.rawValue).annotations.projection.query"
    let object: [String: Any] = [
        "call": [
            "method": method,
            "request": [
                "cursor": NSNull(),
                "sessionIds": [],
                "sourceGeneration": 7,
                "surface": surface.rawValue,
            ],
        ],
        "kind": "product.call",
        "paneSessionId": paneSessionID,
        "requestId": "projection-query-1",
        "requestSequence": 1,
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": 3,
        "workerInstanceId": workerInstanceID,
    ]
    return try BridgeProductStrictJSON.decode(
        BridgeProductControlRequest.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func projectionContentRequest(
    descriptor: BridgeProductAnnotationProjectionContentDescriptor,
    paneSessionID: String,
    workerInstanceID: String
) throws -> BridgeProductAnnotationProjectionContentRequest {
    let descriptorObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as? [String: Any]
    )
    let object: [String: Any] = [
        "contentKind": "annotation.projection",
        "contentRequestId": "annotation-content-1",
        "descriptor": descriptorObject,
        "kind": "content.open",
        "leaseId": "annotation-lease-1",
        "paneSessionId": paneSessionID,
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": 3,
        "workerInstanceId": workerInstanceID,
    ]
    return try BridgeProductStrictJSON.decode(
        BridgeProductAnnotationProjectionContentRequest.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func collectProjectionRecords(
    cursor: inout BridgeProductAnnotationProjectionPageRecordCursor
) throws -> [BridgeProductAnnotationProjectionRecord] {
    var records: [BridgeProductAnnotationProjectionRecord] = []
    while let batch = try cursor.nextEncodedBatch() {
        records.append(
            contentsOf: try batch.split(separator: 0x0A).map { line in
                try JSONDecoder().decode(
                    BridgeProductAnnotationProjectionRecord.self,
                    from: Data(line)
                )
            }
        )
    }
    return records
}

private actor ProjectionSnapshotRepositoryAccess: WorktreeAnnotationRepositoryAccess {
    let detail: WorktreeAnnotationSessionDetail
    init(detail: WorktreeAnnotationSessionDetail) { self.detail = detail }
    func discoverSessions(worktreeID: String) async throws -> [WorktreeAnnotationSession] {
        detail.session.worktreeID == worktreeID ? [detail.session] : []
    }
    func fetchProjectionSnapshot(
        worktreeID: String,
        demandedSessionIDs: [WorktreeAnnotationSessionID]
    ) async throws -> WorktreeAnnotationRepositoryProjectionSnapshot {
        guard worktreeID == detail.session.worktreeID,
            demandedSessionIDs == [detail.session.id]
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        return WorktreeAnnotationRepositoryProjectionSnapshot(
            details: [detail],
            sessions: [detail.session]
        )
    }
    func fetchSessionDetail(sessionID: WorktreeAnnotationSessionID) async throws
        -> WorktreeAnnotationSessionDetail
    {
        guard sessionID == detail.session.id else { throw WorktreeAnnotationRepositoryError.notFound }
        return detail
    }
    func createRootDraft(_: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func flushDraft(_: WorktreeAnnotationSQLiteRepository.FlushDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func saveDraft(_: WorktreeAnnotationSQLiteRepository.SaveDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func revertDraft(_: WorktreeAnnotationSQLiteRepository.RevertDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func createReplyDraft(_: WorktreeAnnotationSQLiteRepository.CreateReplyDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func setThreadResolution(_: WorktreeAnnotationSQLiteRepository.SetThreadResolutionProps)
        async throws -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func setSessionLifecycle(_: WorktreeAnnotationSQLiteRepository.SetSessionLifecycleProps)
        async throws -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func setSourceRelationship(_: WorktreeAnnotationSQLiteRepository.SetSourceRelationshipProps)
        async throws -> WorktreeAnnotationSessionDetail
    {
        try unsupportedProjectionMutation()
    }
    func prepareOutput(_: WorktreeAnnotationSQLiteRepository.PrepareOutputProps) async throws
        -> WorktreeAnnotationOutputMutationResult
    {
        try unsupportedProjectionMutation()
    }
    func inspectOutputAttempt(attemptID _: WorktreeAnnotationOutputAttemptID) async throws
        -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    {
        try unsupportedProjectionMutation()
    }
    func cancelOutputAttempt(
        attemptID _: WorktreeAnnotationOutputAttemptID,
        now _: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try unsupportedProjectionMutation()
    }
    func finalizeOutputAttempt(
        attemptID _: WorktreeAnnotationOutputAttemptID,
        eventKind _: WorktreeAnnotationOutputEventKind,
        now _: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        try unsupportedProjectionMutation()
    }
    func markPreparedOutputAttemptsUnknown(now _: Date) async throws -> Int { 0 }
    func fetchUnacknowledgedRecoveryProvenance() async throws
        -> WorktreeAnnotationRecoveryProvenance?
    {
        nil
    }
    func acknowledgeRecoveryProvenance(
        id _: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt _: Date
    ) async throws -> WorktreeAnnotationRecoveryProvenance {
        try unsupportedProjectionMutation()
    }
}

private func unsupportedProjectionMutation<TValue>() throws -> TValue {
    throw WorktreeAnnotationRepositoryError.invalidState
}
