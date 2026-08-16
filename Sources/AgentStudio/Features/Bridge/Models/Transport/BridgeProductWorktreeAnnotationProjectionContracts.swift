import Foundation

enum BridgeProductWorktreeAnnotationProjectionError: Error, Equatable {
    case messageEntryExceedsMaximum
    case singletonFrameExceedsMaximum
    case unsupportedThreadOrigin
}

struct BridgeProductWorktreeAnnotationSessionSummary: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case completedAt
        case createdAt
        case lifecycle
        case semanticRevision
        case sessionId
        case sourceRelationship
        case updatedAt
    }

    let completedAt: Date?
    let createdAt: Date
    let lifecycle: WorktreeAnnotationSessionLifecycle
    let semanticRevision: Int
    let sessionId: UUID
    let sourceRelationship: WorktreeAnnotationSourceRelationship
    let updatedAt: Date

    init(_ session: WorktreeAnnotationSession) {
        completedAt = session.completedAt
        createdAt = session.createdAt
        lifecycle = session.lifecycle
        semanticRevision = session.semanticRevision
        sessionId = session.id.rawValue
        sourceRelationship = session.sourceRelationship
        updatedAt = session.updatedAt
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedAt = try BridgeProductContractDecoding.decodeRequiredNullable(
            Date.self,
            forKey: .completedAt,
            from: container,
            codingPath: decoder.codingPath
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lifecycle = try container.decode(WorktreeAnnotationSessionLifecycle.self, forKey: .lifecycle)
        semanticRevision = try container.decode(Int.self, forKey: .semanticRevision)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        sourceRelationship = try container.decode(
            WorktreeAnnotationSourceRelationship.self,
            forKey: .sourceRelationship
        )
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lifecycle, forKey: .lifecycle)
        try container.encode(semanticRevision, forKey: .semanticRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(sessionId),
            forKey: .sessionId
        )
        try container.encode(sourceRelationship, forKey: .sourceRelationship)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct BridgeProductWorktreeAnnotationCommandOutcomeDTO: Codable, Equatable, Sendable {
    enum Status: Codable, Equatable, Sendable {
        case committed
        case output(BridgeProductAnnotationOutputOutcomeDTO)
        case failed(WorktreeAnnotationCommandFailureCode)

        private enum CodingKeys: String, CodingKey, CaseIterable { case code, kind, outcome }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            let allowedKeys: Set<String> =
                switch kind {
                case "committed": [CodingKeys.kind.rawValue]
                case "output": [CodingKeys.kind.rawValue, CodingKeys.outcome.rawValue]
                case "failed": [CodingKeys.code.rawValue, CodingKeys.kind.rawValue]
                default: []
                }
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: allowedKeys,
                contract: "annotation command outcome status"
            )
            switch kind {
            case "committed":
                self = .committed
            case "output":
                self = .output(
                    try container.decode(
                        BridgeProductAnnotationOutputOutcomeDTO.self,
                        forKey: .outcome
                    )
                )
            case "failed":
                self = .failed(
                    try container.decode(WorktreeAnnotationCommandFailureCode.self, forKey: .code)
                )
            default:
                throw BridgeProductContractDecoding.invalidValue(
                    "Invalid annotation command outcome status",
                    codingPath: decoder.codingPath
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .committed:
                try container.encode("committed", forKey: .kind)
            case .output(let outcome):
                try container.encode("output", forKey: .kind)
                try container.encode(outcome, forKey: .outcome)
            case .failed(let code):
                try container.encode(code, forKey: .code)
                try container.encode("failed", forKey: .kind)
            }
        }
    }

    let requestId: String
    let sessionId: UUID?
    let status: Status
    let surface: BridgeProductSurface

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case requestId
        case sessionId
        case status
        case surface
    }

    init(_ outcome: WorktreeAnnotationCommandOutcome) {
        requestId = outcome.requestID
        sessionId = outcome.sessionID?.rawValue
        surface = outcome.surface
        switch outcome.status {
        case .committed: status = .committed
        case .output(let output): status = .output(.init(output))
        case .failed(let code): status = .failed(code)
        }
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decode(String.self, forKey: .requestId)
        sessionId = try BridgeProductContractDecoding.decodeRequiredNullable(
            UUID.self,
            forKey: .sessionId,
            from: container,
            codingPath: decoder.codingPath
        )
        status = try container.decode(Status.self, forKey: .status)
        surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(
            sessionId.map(BridgeProductReviewPublicationIdContract.encode),
            forKey: .sessionId
        )
        try container.encode(status, forKey: .status)
        try container.encode(surface, forKey: .surface)
    }
}

struct BridgeProductAnnotationOutputHistoryDTO: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case attemptId
        case createdAt
        case messageCount
        case outputKind
        case repeatedFromAttemptId
        case sessionId
        case state
        case updatedAt
    }

    let attemptId: UUID
    let createdAt: Date
    let messageCount: Int
    let outputKind: WorktreeAnnotationOutputKind
    let repeatedFromAttemptId: UUID?
    let sessionId: UUID
    let state: WorktreeAnnotationOutputAttemptState
    let updatedAt: Date

    init(_ summary: WorktreeAnnotationOutputHistorySummary) {
        attemptId = summary.attemptID.rawValue
        createdAt = summary.createdAt
        messageCount = summary.messageCount
        outputKind = summary.outputKind
        repeatedFromAttemptId = summary.repeatedFromAttemptID?.rawValue
        sessionId = summary.sessionID.rawValue
        state = summary.state
        updatedAt = summary.updatedAt
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attemptId = try container.decode(UUID.self, forKey: .attemptId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        outputKind = try container.decode(WorktreeAnnotationOutputKind.self, forKey: .outputKind)
        repeatedFromAttemptId = try BridgeProductContractDecoding.decodeRequiredNullable(
            UUID.self,
            forKey: .repeatedFromAttemptId,
            from: container,
            codingPath: decoder.codingPath
        )
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        state = try container.decode(WorktreeAnnotationOutputAttemptState.self, forKey: .state)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        guard messageCount > 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output history message count must be positive",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(attemptId),
            forKey: .attemptId
        )
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encode(outputKind, forKey: .outputKind)
        try container.encode(
            repeatedFromAttemptId.map(BridgeProductReviewPublicationIdContract.encode),
            forKey: .repeatedFromAttemptId
        )
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(sessionId),
            forKey: .sessionId
        )
        try container.encode(state, forKey: .state)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct BridgeProductWorktreeAnnotationThreadContext: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case diffSide
        case endLine
        case path
        case placement
        case resolution
        case scope
        case sourceIdentity
        case sourceRole
        case startLine
        case threadId
    }

    let diffSide: WorktreeAnnotationDiffSide?
    let endLine: Int
    let path: String
    let placement: WorktreeAnnotationPlacement
    let resolution: WorktreeAnnotationThreadResolution
    let scope: WorktreeAnnotationThreadScope
    let sourceIdentity: String
    let sourceRole: WorktreeAnnotationSourceRole
    let startLine: Int
    let threadId: UUID

    init(
        _ thread: WorktreeAnnotationThread,
        placement currentPlacement: WorktreeAnnotationThreadPlacementProjection?
    ) throws {
        threadId = thread.id.rawValue
        resolution = thread.resolution
        switch thread.origin {
        case .session, .wholeFile:
            throw BridgeProductWorktreeAnnotationProjectionError.unsupportedThreadOrigin
        case .located(let origin):
            placement = currentPlacement?.placement ?? .unavailable
            scope = .located
            path = currentPlacement?.currentPath ?? origin.repositoryRelativePath
            startLine = currentPlacement?.currentStartLine ?? origin.startLine
            endLine = currentPlacement?.currentEndLine ?? origin.endLine
            sourceRole = origin.sourceRole
            diffSide = origin.diffSide
            sourceIdentity = currentPlacement?.currentSourceIdentity ?? origin.sourceIdentity
        }
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        diffSide = try BridgeProductContractDecoding.decodeRequiredNullable(
            WorktreeAnnotationDiffSide.self,
            forKey: .diffSide,
            from: container,
            codingPath: decoder.codingPath
        )
        endLine = try container.decode(Int.self, forKey: .endLine)
        path = try container.decode(String.self, forKey: .path)
        placement = try container.decode(WorktreeAnnotationPlacement.self, forKey: .placement)
        resolution = try container.decode(WorktreeAnnotationThreadResolution.self, forKey: .resolution)
        scope = try container.decode(WorktreeAnnotationThreadScope.self, forKey: .scope)
        sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        sourceRole = try container.decode(WorktreeAnnotationSourceRole.self, forKey: .sourceRole)
        startLine = try container.decode(Int.self, forKey: .startLine)
        threadId = try container.decode(UUID.self, forKey: .threadId)
        guard scope == .located, !path.isEmpty, !sourceIdentity.isEmpty,
            startLine > 0, endLine >= startLine
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation thread context must be located",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(diffSide, forKey: .diffSide)
        try container.encode(endLine, forKey: .endLine)
        try container.encode(path, forKey: .path)
        try container.encode(placement, forKey: .placement)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(scope, forKey: .scope)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
        try container.encode(sourceRole, forKey: .sourceRole)
        try container.encode(startLine, forKey: .startLine)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(threadId),
            forKey: .threadId
        )
    }
}

struct BridgeProductWorktreeAnnotationMessageEntry: Codable, Equatable, Sendable {
    struct DraftEntry: Codable, Equatable, Sendable {
        let activeEditToken: String?
        let body: String
        let revision: Int

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case activeEditToken, body, revision
        }

        init(activeEditToken: String?, body: String, revision: Int) {
            self.activeEditToken = activeEditToken
            self.body = body
            self.revision = revision
        }

        init(from decoder: Decoder) throws {
            try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeEditToken = try BridgeProductContractDecoding.decodeRequiredNullable(
                String.self,
                forKey: .activeEditToken,
                from: container,
                codingPath: decoder.codingPath
            )
            body = try container.decode(String.self, forKey: .body)
            revision = try container.decode(Int.self, forKey: .revision)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case authorKind
        case createdAt
        case draft
        case messageId
        case messageRevision
        case ordinal
        case savedBody
        case savedRevision
        case sessionId
        case sessionRevision
        case status
        case threadId
    }

    let authorKind: String
    let createdAt: Date
    let draft: DraftEntry?
    let messageId: UUID
    let messageRevision: Int
    let ordinal: Int
    let savedBody: String?
    let savedRevision: Int?
    let sessionId: UUID
    let sessionRevision: Int
    let status: WorktreeAnnotationMessageStatus
    let threadId: UUID

    init(
        message: WorktreeAnnotationMessage,
        session: WorktreeAnnotationSession,
        thread: WorktreeAnnotationThread
    ) throws {
        authorKind = "human"
        createdAt = message.createdAt
        draft = message.draft.map {
            DraftEntry(activeEditToken: $0.activeEditToken, body: $0.body, revision: $0.draftRevision)
        }
        messageId = message.id.rawValue
        messageRevision = message.semanticRevision
        ordinal = message.ordinal
        savedBody = message.savedBody
        savedRevision = message.savedRevision
        sessionId = session.id.rawValue
        sessionRevision = session.semanticRevision
        status = message.status
        threadId = thread.id.rawValue
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(self).count <= 64 * 1024 else {
            throw BridgeProductWorktreeAnnotationProjectionError.messageEntryExceedsMaximum
        }
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorKind = try container.decode(String.self, forKey: .authorKind)
        guard authorKind == "human" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation message author must be human",
                codingPath: decoder.codingPath
            )
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        draft = try BridgeProductContractDecoding.decodeRequiredNullable(
            DraftEntry.self,
            forKey: .draft,
            from: container,
            codingPath: decoder.codingPath
        )
        savedBody = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .savedBody,
            from: container,
            codingPath: decoder.codingPath
        )
        savedRevision = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .savedRevision,
            from: container,
            codingPath: decoder.codingPath
        )
        messageId = try container.decode(UUID.self, forKey: .messageId)
        messageRevision = try container.decode(Int.self, forKey: .messageRevision)
        ordinal = try container.decode(Int.self, forKey: .ordinal)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        sessionRevision = try container.decode(Int.self, forKey: .sessionRevision)
        status = try container.decode(WorktreeAnnotationMessageStatus.self, forKey: .status)
        threadId = try container.decode(UUID.self, forKey: .threadId)
        guard (savedBody == nil) == (savedRevision == nil), savedRevision.map({ $0 > 0 }) ?? true,
            savedBody != nil || draft != nil,
            !(status == .locked && draft != nil),
            draft.map({ $0.revision >= 0 && $0.body.utf8.count <= 16_384 }) ?? true,
            !(savedBody == nil && draft?.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation message content state is invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(authorKind, forKey: .authorKind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(draft, forKey: .draft)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(messageId),
            forKey: .messageId
        )
        try container.encode(messageRevision, forKey: .messageRevision)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encode(savedBody, forKey: .savedBody)
        try container.encode(savedRevision, forKey: .savedRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(sessionId),
            forKey: .sessionId
        )
        try container.encode(sessionRevision, forKey: .sessionRevision)
        try container.encode(status, forKey: .status)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(threadId),
            forKey: .threadId
        )
    }
}

struct BridgeProductWorktreeAnnotationProjectionState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case commandOutcomes
        case outputHistory
        case recoveryStatus
        case revision
        case sessions
        case worktreeId
    }

    let commandOutcomes: [BridgeProductWorktreeAnnotationCommandOutcomeDTO]
    let outputHistory: [BridgeProductAnnotationOutputHistoryDTO]
    let recoveryStatus: String
    let revision: Int
    let sessions: [BridgeProductWorktreeAnnotationSessionSummary]
    let worktreeId: String

    init(_ snapshot: WorktreeAnnotationProjectionSnapshot) {
        commandOutcomes = snapshot.commandOutcomes.map(
            BridgeProductWorktreeAnnotationCommandOutcomeDTO.init
        )
        outputHistory = snapshot.outputHistory.map(
            BridgeProductAnnotationOutputHistoryDTO.init
        )
        revision = snapshot.revision
        sessions = snapshot.sessions.map(BridgeProductWorktreeAnnotationSessionSummary.init)
        worktreeId = snapshot.worktreeID
        switch snapshot.recoveryState {
        case .available: recoveryStatus = "available"
        case .recoveredDegraded: recoveryStatus = "recovered_degraded"
        case .unavailable: recoveryStatus = "unavailable"
        }
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandOutcomes = try container.decode(
            [BridgeProductWorktreeAnnotationCommandOutcomeDTO].self,
            forKey: .commandOutcomes
        )
        outputHistory = try container.decode(
            [BridgeProductAnnotationOutputHistoryDTO].self,
            forKey: .outputHistory
        )
        recoveryStatus = try container.decode(String.self, forKey: .recoveryStatus)
        revision = try container.decode(Int.self, forKey: .revision)
        sessions = try container.decode(
            [BridgeProductWorktreeAnnotationSessionSummary].self,
            forKey: .sessions
        )
        worktreeId = try container.decode(String.self, forKey: .worktreeId)
    }
}

struct BridgeProductWorktreeAnnotationMessageBatch: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case context
        case isLastBatchForThread
        case messages
        case revision
    }

    let context: BridgeProductWorktreeAnnotationThreadContext
    let isLastBatchForThread: Bool
    let messages: [BridgeProductWorktreeAnnotationMessageEntry]
    let revision: Int

    init(
        context: BridgeProductWorktreeAnnotationThreadContext,
        isLastBatchForThread: Bool,
        messages: [BridgeProductWorktreeAnnotationMessageEntry],
        revision: Int
    ) {
        self.context = context
        self.isLastBatchForThread = isLastBatchForThread
        self.messages = messages
        self.revision = revision
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decode(BridgeProductWorktreeAnnotationThreadContext.self, forKey: .context)
        isLastBatchForThread = try container.decode(Bool.self, forKey: .isLastBatchForThread)
        messages = try container.decode(
            [BridgeProductWorktreeAnnotationMessageEntry].self,
            forKey: .messages
        )
        revision = try container.decode(Int.self, forKey: .revision)
    }
}

private func rejectAnnotationProjectionUnknownKeys<TCodingKey: CodingKey & RawRepresentable>(
    _ decoder: Decoder,
    keys: [TCodingKey]
) throws where TCodingKey.RawValue == String {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(keys.map(\.rawValue)),
        contract: "worktree annotation projection value"
    )
}

enum BridgeProductWorktreeAnnotationEvent: Codable, Equatable, Sendable {
    case messageBatch(BridgeProductWorktreeAnnotationMessageBatch)
    case projectionState(BridgeProductWorktreeAnnotationProjectionState)

    private enum CodingKeys: String, CodingKey, CaseIterable { case eventKind, payload }

    var sourceGeneration: Int {
        switch self {
        case .messageBatch(let batch): batch.revision
        case .projectionState(let state): state.revision
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .eventKind) {
        case "message.batch":
            self = .messageBatch(
                try container.decode(BridgeProductWorktreeAnnotationMessageBatch.self, forKey: .payload)
            )
        case "projection.state":
            self = .projectionState(
                try container.decode(BridgeProductWorktreeAnnotationProjectionState.self, forKey: .payload)
            )
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation event kind",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .messageBatch(let batch):
            try container.encode("message.batch", forKey: .eventKind)
            try container.encode(batch, forKey: .payload)
        case .projectionState(let state):
            try container.encode("projection.state", forKey: .eventKind)
            try container.encode(state, forKey: .payload)
        }
    }
}

enum BridgeProductWorktreeAnnotationProjectionPacker {
    static func events(
        snapshot: WorktreeAnnotationProjectionSnapshot,
        surface: BridgeProductSurface
    ) throws -> [BridgeProductWorktreeAnnotationEvent] {
        var events: [BridgeProductWorktreeAnnotationEvent] = [.projectionState(.init(snapshot))]
        for detail in snapshot.details {
            for threadDetail in detail.threads {
                let context = try BridgeProductWorktreeAnnotationThreadContext(
                    threadDetail.thread,
                    placement: snapshot.placementsByThreadID[threadDetail.thread.id]
                )
                let entries = try threadDetail.messages.map {
                    try BridgeProductWorktreeAnnotationMessageEntry(
                        message: $0,
                        session: detail.session,
                        thread: threadDetail.thread
                    )
                }
                events.append(
                    contentsOf: try packedMessageEvents(
                        context: context,
                        entries: entries,
                        revision: snapshot.revision,
                        surface: surface
                    )
                )
            }
        }
        return events
    }

    private static func packedMessageEvents(
        context: BridgeProductWorktreeAnnotationThreadContext,
        entries: [BridgeProductWorktreeAnnotationMessageEntry],
        revision: Int,
        surface: BridgeProductSurface
    ) throws -> [BridgeProductWorktreeAnnotationEvent] {
        guard !entries.isEmpty else { return [] }
        var batches: [[BridgeProductWorktreeAnnotationMessageEntry]] = []
        var current: [BridgeProductWorktreeAnnotationMessageEntry] = []
        for entry in entries {
            let candidate = current + [entry]
            if try fitsMaximumEnvelope(
                context: context,
                entries: candidate,
                revision: revision,
                surface: surface
            ) {
                current = candidate
            } else {
                guard !current.isEmpty else {
                    throw BridgeProductWorktreeAnnotationProjectionError.singletonFrameExceedsMaximum
                }
                batches.append(current)
                current = [entry]
                guard
                    try fitsMaximumEnvelope(
                        context: context,
                        entries: current,
                        revision: revision,
                        surface: surface
                    )
                else {
                    throw BridgeProductWorktreeAnnotationProjectionError.singletonFrameExceedsMaximum
                }
            }
        }
        batches.append(current)
        return batches.enumerated().map { index, messages in
            .messageBatch(
                .init(
                    context: context,
                    isLastBatchForThread: index == batches.count - 1,
                    messages: messages,
                    revision: revision
                )
            )
        }
    }

    private static func fitsMaximumEnvelope(
        context: BridgeProductWorktreeAnnotationThreadContext,
        entries: [BridgeProductWorktreeAnnotationMessageEntry],
        revision: Int,
        surface: BridgeProductSurface
    ) throws -> Bool {
        let event = BridgeProductWorktreeAnnotationEvent.messageBatch(
            .init(context: context, isLastBatchForThread: true, messages: entries, revision: revision)
        )
        let repeatedIdentifier = String(
            repeating: "a",
            count: BridgeProductWireContract.maximumIdentifierByteLength
        )
        let stream = BridgeProductMetadataStreamCorrelation(
            metadataStreamId: repeatedIdentifier,
            paneSessionId: repeatedIdentifier,
            wireVersion: BridgeProductWireContract.version,
            workerInstanceId: repeatedIdentifier
        )
        let subscription = try BridgeProductSubscriptionFrameCorrelation(
            cursor: String(
                repeating: "a",
                count: BridgeProductWireContract.maximumOpaqueReferenceByteLength
            ),
            interestRevision: BridgeProductWireContract.maximumSafeInteger,
            interestSha256: String(repeating: "a", count: 64),
            sourceGeneration: max(0, revision),
            subscriptionId: repeatedIdentifier,
            subscriptionKind: surface == .file ? .fileAnnotations : .reviewAnnotations,
            workerDerivationEpoch: BridgeProductWireContract.maximumSafeInteger
        )
        let data: BridgeProductSubscriptionData =
            surface == .file
            ? .fileAnnotations(event)
            : .reviewAnnotations(event)
        let frame = try BridgeProductMetadataFrame.subscriptionData(
            stream: stream,
            streamSequence: BridgeProductWireContract.maximumSafeInteger,
            subscription: subscription,
            subscriptionSequence: BridgeProductWireContract.maximumSafeInteger,
            data: data
        )
        do {
            return try BridgeProductMetadataFrameCodec.encode(frame).count - 4
                <= BridgeProductWireContract.maximumMetadataFrameBytes
        } catch BridgeProductFrameCodecError.invalidFrame {
            return false
        }
    }
}
