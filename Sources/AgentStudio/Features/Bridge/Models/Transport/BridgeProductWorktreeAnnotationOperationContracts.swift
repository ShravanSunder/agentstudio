import Foundation

enum BridgeProductWorktreeAnnotationOperation: Codable, Equatable, Sendable {
    case discoverSessions
    case acquireDemand(sessionID: UUID)
    case releaseDemand(sessionID: UUID)
    case createRoot(
        admission: BridgeProductWorktreeAnnotationAdmission,
        body: String,
        editToken: String,
        origin: BridgeProductWorktreeAnnotationOrigin
    )
    case createReply(MutationBody)
    case flushDraft(DraftMutationBody)
    case acquireEditToken(DraftRevisionBody)
    case releaseEditToken(DraftRevisionBody)
    case saveDraft(DraftRevisionBody)
    case revertDraft(DraftRevisionBody)
    case setThreadResolution(ThreadResolutionBody)
    case setSessionLifecycle(SessionLifecycleBody)
    case chooseContinuity(ContinuityBody)
    case refreshSource(SourceRefreshBody)
    case outputSelectionBegin(OutputSelectionBeginBody)
    case outputSelectionChunk(OutputSelectionChunkBody)
    case outputSelectionCommit(OutputSelectionTerminalBody)
    case outputSelectionCancel(OutputSelectionTerminalBody)
    case outputHistory(sessionID: UUID)
    case repeatOutput(attemptID: UUID)
    case acknowledgeRecovery

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case admission
        case attemptId
        case body
        case confirmsUnresolvedWork
        case decision
        case editToken
        case expectedDraftRevision
        case expectedOpenThreadCount
        case expectedSessionRevision
        case kind
        case lifecycle
        case messageId
        case origin
        case outputKind
        case selectionMode
        case resolution
        case ordinal
        case messageIds
        case sessionId
        case sourceEpoch
        case threadId
        case transferId
    }

    private enum Kind: String, Codable {
        case acknowledgeRecovery = "recovery.acknowledge"
        case acquireDemand = "demand.acquire"
        case chooseContinuity = "continuity.choose"
        case createReply = "reply.create"
        case createRoot = "root.create"
        case discoverSessions = "session.discover"
        case acquireEditToken = "draft.edit.acquire"
        case releaseEditToken = "draft.edit.release"
        case flushDraft = "draft.flush"
        case outputHistory = "output.history"
        case outputSelectionBegin = "output.selection.begin"
        case outputSelectionChunk = "output.selection.chunk"
        case outputSelectionCommit = "output.selection.commit"
        case outputSelectionCancel = "output.selection.cancel"
        case releaseDemand = "demand.release"
        case repeatOutput = "output.repeat"
        case revertDraft = "draft.revert"
        case saveDraft = "draft.save"
        case setSessionLifecycle = "session.lifecycle.set"
        case refreshSource = "source.refresh"
        case setThreadResolution = "thread.resolution.set"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        try rejectUnknownKeys(decoder, allowed: Self.allowedKeys(for: kind))
        switch kind {
        case .discoverSessions:
            self = .discoverSessions
        case .acquireDemand:
            self = .acquireDemand(sessionID: try Self.decodeID(container, .sessionId, decoder))
        case .releaseDemand:
            self = .releaseDemand(sessionID: try Self.decodeID(container, .sessionId, decoder))
        case .createRoot:
            self = try Self.decodeCreateRoot(container, decoder)
        case .createReply:
            self = try Self.decodeCreateReply(container, decoder)
        case .flushDraft:
            self = try Self.decodeFlushDraft(container, decoder)
        case .acquireEditToken, .releaseEditToken:
            let body = try Self.decodeDraftRevisionBody(container, decoder)
            self = kind == .acquireEditToken ? .acquireEditToken(body) : .releaseEditToken(body)
        case .saveDraft, .revertDraft:
            let body = try Self.decodeDraftRevisionBody(container, decoder)
            self = kind == .saveDraft ? .saveDraft(body) : .revertDraft(body)
        case .setThreadResolution:
            self = try Self.decodeThreadResolution(container, decoder)
        case .setSessionLifecycle:
            self = try Self.decodeSessionLifecycle(container, decoder)
        case .chooseContinuity:
            self = try Self.decodeContinuity(container, decoder)
        case .refreshSource:
            self = try Self.decodeSourceRefresh(container, decoder)
        case .outputSelectionBegin:
            self = try Self.decodeOutputSelectionBegin(container, decoder)
        case .outputSelectionChunk:
            self = try Self.decodeOutputSelectionChunk(container, decoder)
        case .outputSelectionCommit, .outputSelectionCancel:
            let body = try Self.decodeOutputSelectionTerminal(container, decoder)
            self = kind == .outputSelectionCommit ? .outputSelectionCommit(body) : .outputSelectionCancel(body)
        case .outputHistory:
            self = .outputHistory(sessionID: try Self.decodeID(container, .sessionId, decoder))
        case .repeatOutput:
            self = .repeatOutput(attemptID: try Self.decodeID(container, .attemptId, decoder))
        case .acknowledgeRecovery:
            self = .acknowledgeRecovery
        }
    }

    private static func decodeCreateRoot(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .createRoot(
            admission: try container.decode(
                BridgeProductWorktreeAnnotationAdmission.self,
                forKey: .admission
            ),
            body: try validatedBody(container, decoder),
            editToken: try validatedIdentifier(container, .editToken, decoder),
            origin: try container.decode(BridgeProductWorktreeAnnotationOrigin.self, forKey: .origin)
        )
    }

    private static func decodeCreateReply(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .createReply(
            MutationBody(
                body: try validatedBody(container, decoder),
                editToken: try validatedIdentifier(container, .editToken, decoder),
                expectedSessionRevision: try nonnegative(container, .expectedSessionRevision, decoder),
                sessionId: try decodeID(container, .sessionId, decoder),
                threadId: try decodeID(container, .threadId, decoder)
            )
        )
    }

    private static func decodeThreadResolution(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .setThreadResolution(
            ThreadResolutionBody(
                expectedSessionRevision: try nonnegative(container, .expectedSessionRevision, decoder),
                resolution: try container.decode(WorktreeAnnotationThreadResolution.self, forKey: .resolution),
                sessionId: try decodeID(container, .sessionId, decoder),
                threadId: try decodeID(container, .threadId, decoder)
            )
        )
    }

    private static func decodeSessionLifecycle(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .setSessionLifecycle(
            SessionLifecycleBody(
                confirmsUnresolvedWork: try container.decode(Bool.self, forKey: .confirmsUnresolvedWork),
                expectedOpenThreadCount: try nonnegative(container, .expectedOpenThreadCount, decoder),
                expectedSessionRevision: try nonnegative(container, .expectedSessionRevision, decoder),
                lifecycle: try container.decode(WorktreeAnnotationSessionLifecycle.self, forKey: .lifecycle),
                sessionId: try decodeID(container, .sessionId, decoder)
            )
        )
    }

    private static func decodeContinuity(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .chooseContinuity(
            ContinuityBody(
                decision: try container.decode(ContinuityDecision.self, forKey: .decision),
                expectedSessionRevision: try nonnegative(container, .expectedSessionRevision, decoder),
                sessionId: try decodeID(container, .sessionId, decoder)
            )
        )
    }

    private static func decodeSourceRefresh(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .refreshSource(
            SourceRefreshBody(
                sessionId: try decodeID(container, .sessionId, decoder),
                sourceEpoch: try nonnegative(container, .sourceEpoch, decoder)
            )
        )
    }

    private static func decodeOutputSelectionBegin(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .outputSelectionBegin(
            OutputSelectionBeginBody(
                outputKind: try container.decode(OutputKind.self, forKey: .outputKind),
                selectionMode: try container.decode(OutputSelectionMode.self, forKey: .selectionMode),
                sessionId: try decodeID(container, .sessionId, decoder),
                transferId: try validatedIdentifier(container, .transferId, decoder)
            )
        )
    }

    private static func decodeOutputSelectionChunk(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        .outputSelectionChunk(
            OutputSelectionChunkBody(
                messageIds: try decodeOutputMessageIDs(container, decoder),
                ordinal: try nonnegative(container, .ordinal, decoder),
                selectionMode: try container.decode(OutputSelectionMode.self, forKey: .selectionMode),
                sessionId: try decodeID(container, .sessionId, decoder),
                transferId: try validatedIdentifier(container, .transferId, decoder)
            )
        )
    }

    private static func decodeOutputSelectionTerminal(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> OutputSelectionTerminalBody {
        OutputSelectionTerminalBody(
            selectionMode: try container.decode(OutputSelectionMode.self, forKey: .selectionMode),
            sessionId: try decodeID(container, .sessionId, decoder),
            transferId: try validatedIdentifier(container, .transferId, decoder)
        )
    }

    private static func decodeFlushDraft(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> Self {
        let expectedDraftRevision = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .expectedDraftRevision,
            from: container,
            codingPath: decoder.codingPath
        )
        if let expectedDraftRevision, expectedDraftRevision < 0 {
            throw invalidRevision(decoder)
        }
        return .flushDraft(
            DraftMutationBody(
                body: try validatedBody(container, decoder),
                editToken: try validatedIdentifier(container, .editToken, decoder),
                expectedDraftRevision: expectedDraftRevision,
                expectedSessionRevision: try nonnegative(container, .expectedSessionRevision, decoder),
                messageId: try decodeID(container, .messageId, decoder),
                sessionId: try decodeID(container, .sessionId, decoder)
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .discoverSessions:
            try container.encode(Kind.discoverSessions, forKey: .kind)
        case .acquireDemand(let sessionID):
            try Self.encode(kind: .acquireDemand, id: sessionID, key: .sessionId, into: &container)
        case .releaseDemand(let sessionID):
            try Self.encode(kind: .releaseDemand, id: sessionID, key: .sessionId, into: &container)
        case .createRoot(let admission, let body, let editToken, let origin):
            try container.encode(Kind.createRoot, forKey: .kind)
            try container.encode(admission, forKey: .admission)
            try container.encode(body, forKey: .body)
            try container.encode(editToken, forKey: .editToken)
            try container.encode(origin, forKey: .origin)
        case .createReply(let body):
            try Self.encode(body, kind: .createReply, into: &container)
        case .flushDraft(let body):
            try Self.encode(body, kind: .flushDraft, into: &container)
        case .acquireEditToken(let body):
            try Self.encode(body, kind: .acquireEditToken, into: &container)
        case .releaseEditToken(let body):
            try Self.encode(body, kind: .releaseEditToken, into: &container)
        case .saveDraft(let body):
            try Self.encode(body, kind: .saveDraft, into: &container)
        case .revertDraft(let body):
            try Self.encode(body, kind: .revertDraft, into: &container)
        case .setThreadResolution(let body):
            try Self.encode(body, kind: .setThreadResolution, into: &container)
        case .setSessionLifecycle(let body):
            try Self.encode(body, kind: .setSessionLifecycle, into: &container)
        case .chooseContinuity(let body):
            try Self.encode(body, kind: .chooseContinuity, into: &container)
        case .refreshSource(let body):
            try container.encode(Kind.refreshSource, forKey: .kind)
            try container.encode(
                BridgeProductReviewPublicationIdContract.encode(body.sessionId),
                forKey: .sessionId
            )
            try container.encode(body.sourceEpoch, forKey: .sourceEpoch)
        case .outputSelectionBegin(let body):
            try Self.encode(body, kind: .outputSelectionBegin, into: &container)
        case .outputSelectionChunk(let body):
            try Self.encode(body, kind: .outputSelectionChunk, into: &container)
        case .outputSelectionCommit(let body):
            try Self.encode(body, kind: .outputSelectionCommit, into: &container)
        case .outputSelectionCancel(let body):
            try Self.encode(body, kind: .outputSelectionCancel, into: &container)
        case .outputHistory(let sessionID):
            try Self.encode(kind: .outputHistory, id: sessionID, key: .sessionId, into: &container)
        case .repeatOutput(let attemptID):
            try Self.encode(kind: .repeatOutput, id: attemptID, key: .attemptId, into: &container)
        case .acknowledgeRecovery:
            try container.encode(Kind.acknowledgeRecovery, forKey: .kind)
        }
    }

    private static func allowedKeys(for kind: Kind) -> Set<CodingKeys> {
        switch kind {
        case .discoverSessions, .acknowledgeRecovery:
            [.kind]
        case .acquireDemand, .releaseDemand, .outputHistory:
            [.kind, .sessionId]
        case .repeatOutput:
            [.attemptId, .kind]
        case .createRoot:
            [.admission, .body, .editToken, .kind, .origin]
        case .createReply:
            [.body, .editToken, .expectedSessionRevision, .kind, .sessionId, .threadId]
        case .flushDraft:
            [
                .body, .editToken, .expectedDraftRevision, .expectedSessionRevision, .kind,
                .messageId, .sessionId,
            ]
        case .acquireEditToken, .releaseEditToken, .saveDraft, .revertDraft:
            [.editToken, .expectedDraftRevision, .expectedSessionRevision, .kind, .messageId, .sessionId]
        case .setThreadResolution:
            [.expectedSessionRevision, .kind, .resolution, .sessionId, .threadId]
        case .setSessionLifecycle:
            [
                .confirmsUnresolvedWork, .expectedOpenThreadCount, .expectedSessionRevision,
                .kind, .lifecycle, .sessionId,
            ]
        case .chooseContinuity:
            [.decision, .expectedSessionRevision, .kind, .sessionId]
        case .refreshSource:
            [.kind, .sessionId, .sourceEpoch]
        case .outputSelectionBegin:
            [.kind, .outputKind, .selectionMode, .sessionId, .transferId]
        case .outputSelectionChunk:
            [.kind, .messageIds, .ordinal, .selectionMode, .sessionId, .transferId]
        case .outputSelectionCommit, .outputSelectionCancel:
            [.kind, .selectionMode, .sessionId, .transferId]
        }
    }

    private static func decodeID(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        _ decoder: Decoder
    ) throws -> UUID {
        try decodeUUIDv7(container, forKey: key, decoder: decoder)
    }

    private static func decodeDraftRevisionBody(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> DraftRevisionBody {
        DraftRevisionBody(
            editToken: try validatedIdentifier(container, .editToken, decoder),
            expectedDraftRevision: try nonnegative(container, .expectedDraftRevision, decoder),
            expectedSessionRevision: try nonnegative(container, .expectedSessionRevision, decoder),
            messageId: try decodeID(container, .messageId, decoder),
            sessionId: try decodeID(container, .sessionId, decoder)
        )
    }

    private static func validatedBody(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> String {
        do {
            return try WorktreeAnnotationMessagePolicy.validate(
                container.decode(String.self, forKey: .body)
            )
        } catch {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation body is invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    private static func validatedIdentifier(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        _ decoder: Decoder
    ) throws -> String {
        let value = try container.decode(String.self, forKey: key)
        try BridgeProductContractDecoding.validateIdentifier(value, codingPath: decoder.codingPath)
        return value
    }

    private static func nonnegative(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        _ decoder: Decoder
    ) throws -> Int {
        let value = try container.decode(Int.self, forKey: key)
        guard value >= 0 else { throw invalidRevision(decoder) }
        return value
    }

    private static func invalidRevision(_ decoder: Decoder) -> DecodingError {
        BridgeProductContractDecoding.invalidValue(
            "Annotation revision or count must be nonnegative",
            codingPath: decoder.codingPath
        )
    }

    private static func encode(
        kind: Kind,
        id: UUID,
        key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(BridgeProductReviewPublicationIdContract.encode(id), forKey: key)
    }

    private static func encode(
        _ body: MutationBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.body, forKey: .body)
        try container.encode(body.editToken, forKey: .editToken)
        try container.encode(body.expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.threadId),
            forKey: .threadId
        )
    }

    private static func encode(
        _ body: DraftMutationBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.body, forKey: .body)
        try container.encode(body.editToken, forKey: .editToken)
        try container.encode(body.expectedDraftRevision, forKey: .expectedDraftRevision)
        try container.encode(body.expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.messageId),
            forKey: .messageId
        )
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
    }

    private static func encode(
        _ body: DraftRevisionBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.editToken, forKey: .editToken)
        try container.encode(body.expectedDraftRevision, forKey: .expectedDraftRevision)
        try container.encode(body.expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.messageId),
            forKey: .messageId
        )
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
    }

    private static func encode(
        _ body: ThreadResolutionBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(body.resolution, forKey: .resolution)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.threadId),
            forKey: .threadId
        )
    }

    private static func encode(
        _ body: SessionLifecycleBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.confirmsUnresolvedWork, forKey: .confirmsUnresolvedWork)
        try container.encode(body.expectedOpenThreadCount, forKey: .expectedOpenThreadCount)
        try container.encode(body.expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(body.lifecycle, forKey: .lifecycle)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
    }

    private static func encode(
        _ body: ContinuityBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.decision, forKey: .decision)
        try container.encode(body.expectedSessionRevision, forKey: .expectedSessionRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
    }

    private static func encode(
        _ body: OutputSelectionBeginBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.outputKind, forKey: .outputKind)
        try container.encode(body.selectionMode, forKey: .selectionMode)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(body.sessionId),
            forKey: .sessionId
        )
        try container.encode(body.transferId, forKey: .transferId)
    }

    private static func encode(
        _ body: OutputSelectionChunkBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.messageIds.map(BridgeProductReviewPublicationIdContract.encode), forKey: .messageIds)
        try container.encode(body.ordinal, forKey: .ordinal)
        try container.encode(body.selectionMode, forKey: .selectionMode)
        try container.encode(BridgeProductReviewPublicationIdContract.encode(body.sessionId), forKey: .sessionId)
        try container.encode(body.transferId, forKey: .transferId)
    }

    private static func encode(
        _ body: OutputSelectionTerminalBody,
        kind: Kind,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(body.selectionMode, forKey: .selectionMode)
        try container.encode(BridgeProductReviewPublicationIdContract.encode(body.sessionId), forKey: .sessionId)
        try container.encode(body.transferId, forKey: .transferId)
    }

    private static func decodeOutputMessageIDs(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ decoder: Decoder
    ) throws -> [UUID] {
        let encodedIDs = try container.decode([String].self, forKey: .messageIds)
        guard (1...64).contains(encodedIDs.count) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output selection chunk must contain between 1 and 64 identities",
                codingPath: decoder.codingPath
            )
        }
        let ids = try encodedIDs.map {
            try BridgeProductReviewPublicationIdContract.decode($0, codingPath: decoder.codingPath)
        }
        guard Set(ids).count == ids.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output selection chunk contains duplicate identities",
                codingPath: decoder.codingPath
            )
        }
        return ids
    }
}

private func rejectUnknownKeys<TCodingKey: CodingKey & RawRepresentable>(
    _ decoder: Decoder,
    allowed: Set<TCodingKey>
) throws where TCodingKey.RawValue == String {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(allowed.map(\.rawValue)),
        contract: "worktree annotation transport value"
    )
}

private func decodeUUIDv7<TCodingKey: CodingKey>(
    _ container: KeyedDecodingContainer<TCodingKey>,
    forKey key: TCodingKey,
    decoder: Decoder
) throws -> UUID {
    try BridgeProductReviewPublicationIdContract.decode(
        container.decode(String.self, forKey: key),
        codingPath: decoder.codingPath
    )
}
