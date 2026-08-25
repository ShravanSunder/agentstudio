import Foundation

private func annotationUnixMilliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded(.towardZero))
}

private func annotationDateFromUnixMilliseconds(_ unixMilliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1000)
}

enum BridgeProductWorktreeAnnotationProjectionError: Error, Equatable {
    case messageEntryExceedsMaximum
    case singletonFrameExceedsMaximum
    case unsupportedThreadOrigin
}

struct BridgeProductWorktreeAnnotationSessionSummary: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case completedAtUnixMilliseconds
        case createdAtUnixMilliseconds
        case eligibleMessageCount
        case eligibleWithoutInlinePlacementCount
        case lifecycle
        case semanticRevision
        case sessionId
        case sourceRelationship
        case updatedAtUnixMilliseconds
    }

    let completedAt: Date?
    let createdAt: Date
    let eligibleMessageCount: Int
    let eligibleWithoutInlinePlacementCount: Int
    let lifecycle: WorktreeAnnotationSessionLifecycle
    let semanticRevision: Int
    let sessionId: UUID
    let sourceRelationship: WorktreeAnnotationSourceRelationship
    let updatedAt: Date

    init(
        _ session: WorktreeAnnotationSession,
        eligibleMessageCount: Int,
        eligibleWithoutInlinePlacementCount: Int
    ) {
        completedAt = session.completedAt
        createdAt = session.createdAt
        self.eligibleMessageCount = eligibleMessageCount
        self.eligibleWithoutInlinePlacementCount = eligibleWithoutInlinePlacementCount
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
            Int64.self,
            forKey: .completedAtUnixMilliseconds,
            from: container,
            codingPath: decoder.codingPath
        ).map(annotationDateFromUnixMilliseconds)
        createdAt = annotationDateFromUnixMilliseconds(
            try container.decode(Int64.self, forKey: .createdAtUnixMilliseconds)
        )
        eligibleMessageCount = try container.decode(Int.self, forKey: .eligibleMessageCount)
        eligibleWithoutInlinePlacementCount = try container.decode(
            Int.self,
            forKey: .eligibleWithoutInlinePlacementCount
        )
        lifecycle = try container.decode(WorktreeAnnotationSessionLifecycle.self, forKey: .lifecycle)
        semanticRevision = try container.decode(Int.self, forKey: .semanticRevision)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        sourceRelationship = try container.decode(
            WorktreeAnnotationSourceRelationship.self,
            forKey: .sourceRelationship
        )
        updatedAt = annotationDateFromUnixMilliseconds(
            try container.decode(Int64.self, forKey: .updatedAtUnixMilliseconds)
        )
        guard eligibleMessageCount >= 0,
            eligibleWithoutInlinePlacementCount >= 0,
            eligibleWithoutInlinePlacementCount <= eligibleMessageCount
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output candidate counts are invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            completedAt.map(annotationUnixMilliseconds),
            forKey: .completedAtUnixMilliseconds
        )
        try container.encode(
            annotationUnixMilliseconds(createdAt),
            forKey: .createdAtUnixMilliseconds
        )
        try container.encode(eligibleMessageCount, forKey: .eligibleMessageCount)
        try container.encode(
            eligibleWithoutInlinePlacementCount,
            forKey: .eligibleWithoutInlinePlacementCount
        )
        try container.encode(lifecycle, forKey: .lifecycle)
        try container.encode(semanticRevision, forKey: .semanticRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(sessionId),
            forKey: .sessionId
        )
        try container.encode(sourceRelationship, forKey: .sourceRelationship)
        try container.encode(
            annotationUnixMilliseconds(updatedAt),
            forKey: .updatedAtUnixMilliseconds
        )
    }
}

struct BridgeProductWorktreeAnnotationMessageReceiptDTO: Codable, Equatable, Sendable {
    let draftRevision: Int?
    let messageId: UUID
    let messageRevision: Int
    let savedRevision: Int?
    let sessionRevision: Int
    let threadId: UUID
    let threadRevision: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case draftRevision, kind, messageId, messageRevision, savedRevision, sessionRevision, threadId,
            threadRevision
    }

    init(_ receipt: WorktreeAnnotationMessageCommandReceipt) {
        draftRevision = receipt.draftRevision
        messageId = receipt.messageID.rawValue
        messageRevision = receipt.messageRevision
        savedRevision = receipt.savedRevision
        sessionRevision = receipt.sessionRevision
        threadId = receipt.threadID.rawValue
        threadRevision = receipt.threadRevision
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "message" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid annotation command receipt kind",
                codingPath: decoder.codingPath + [CodingKeys.kind]
            )
        }
        draftRevision = try container.decodeIfPresent(Int.self, forKey: .draftRevision)
        messageId = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .messageId),
            codingPath: decoder.codingPath + [CodingKeys.messageId]
        )
        messageRevision = try container.decode(Int.self, forKey: .messageRevision)
        savedRevision = try container.decodeIfPresent(Int.self, forKey: .savedRevision)
        sessionRevision = try container.decode(Int.self, forKey: .sessionRevision)
        threadId = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .threadId),
            codingPath: decoder.codingPath + [CodingKeys.threadId]
        )
        threadRevision = try container.decode(Int.self, forKey: .threadRevision)
        for (name, value) in [
            ("draftRevision", draftRevision),
            ("messageRevision", Optional(messageRevision)),
            ("sessionRevision", Optional(sessionRevision)),
            ("threadRevision", Optional(threadRevision)),
        ] {
            if let value {
                try BridgeProductContractDecoding.validateNonnegative(
                    value,
                    name: name,
                    codingPath: decoder.codingPath
                )
            }
        }
        if let savedRevision {
            try BridgeProductContractDecoding.validatePositive(
                savedRevision,
                name: "savedRevision",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(draftRevision, forKey: .draftRevision)
        try container.encode("message", forKey: .kind)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(messageId),
            forKey: .messageId
        )
        try container.encode(messageRevision, forKey: .messageRevision)
        try container.encode(savedRevision, forKey: .savedRevision)
        try container.encode(sessionRevision, forKey: .sessionRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(threadId),
            forKey: .threadId
        )
        try container.encode(threadRevision, forKey: .threadRevision)
    }
}

struct BridgeProductWorktreeAnnotationCommandOutcomeDTO: Codable, Equatable, Sendable {
    enum Status: Codable, Equatable, Sendable {
        case committed
        case admissionRequired(
            reason: WorktreeAnnotationAdmissionChoiceReason,
            candidateSessionIds: [UUID]
        )
        case history([BridgeProductAnnotationOutputHistoryDTO])
        case output(BridgeProductAnnotationOutputOutcomeDTO)
        case viewed([BridgeProductWorktreeAnnotationViewedResultDTO])
        case failed(WorktreeAnnotationCommandFailureCode)

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case candidateSessionIds, code, kind, outcome, reason, results, summaries
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            let allowedKeys: Set<String> =
                switch kind {
                case "committed": [CodingKeys.kind.rawValue]
                case "admission_required":
                    [
                        CodingKeys.candidateSessionIds.rawValue,
                        CodingKeys.kind.rawValue,
                        CodingKeys.reason.rawValue,
                    ]
                case "history": [CodingKeys.kind.rawValue, CodingKeys.summaries.rawValue]
                case "output": [CodingKeys.kind.rawValue, CodingKeys.outcome.rawValue]
                case "viewed": [CodingKeys.kind.rawValue, CodingKeys.results.rawValue]
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
            case "admission_required":
                let candidateSessionIds = try container.decode([UUID].self, forKey: .candidateSessionIds)
                guard !candidateSessionIds.isEmpty,
                    Set(candidateSessionIds).count == candidateSessionIds.count
                else {
                    throw BridgeProductContractDecoding.invalidValue(
                        "Annotation admission candidates must be nonempty and unique",
                        codingPath: decoder.codingPath
                    )
                }
                self = .admissionRequired(
                    reason: try container.decode(
                        WorktreeAnnotationAdmissionChoiceReason.self,
                        forKey: .reason
                    ),
                    candidateSessionIds: candidateSessionIds
                )
            case "output":
                self = .output(
                    try container.decode(
                        BridgeProductAnnotationOutputOutcomeDTO.self,
                        forKey: .outcome
                    )
                )
            case "history":
                self = .history(
                    try container.decode(
                        [BridgeProductAnnotationOutputHistoryDTO].self,
                        forKey: .summaries
                    )
                )
            case "viewed":
                let results = try container.decode(
                    [BridgeProductWorktreeAnnotationViewedResultDTO].self,
                    forKey: .results
                )
                guard (1...256).contains(results.count),
                    Set(results.map(\.revisionIdentity)).count == results.count
                else {
                    throw BridgeProductContractDecoding.invalidValue(
                        "Viewed annotation results must be nonempty and bounded",
                        codingPath: decoder.codingPath
                    )
                }
                self = .viewed(results)
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
            case .admissionRequired(let reason, let candidateSessionIds):
                try container.encode(candidateSessionIds, forKey: .candidateSessionIds)
                try container.encode("admission_required", forKey: .kind)
                try container.encode(reason, forKey: .reason)
            case .output(let outcome):
                try container.encode("output", forKey: .kind)
                try container.encode(outcome, forKey: .outcome)
            case .history(let summaries):
                try container.encode("history", forKey: .kind)
                try container.encode(summaries, forKey: .summaries)
            case .viewed(let results):
                try container.encode("viewed", forKey: .kind)
                try container.encode(results, forKey: .results)
            case .failed(let code):
                try container.encode(code, forKey: .code)
                try container.encode("failed", forKey: .kind)
            }
        }
    }

    let requestId: String
    let receipt: BridgeProductWorktreeAnnotationMessageReceiptDTO?
    let sessionId: UUID?
    let status: Status
    let surface: BridgeProductSurface

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case receipt
        case requestId
        case sessionId
        case status
        case surface
    }

    init(_ outcome: WorktreeAnnotationCommandOutcome) {
        receipt = outcome.receipt.map(BridgeProductWorktreeAnnotationMessageReceiptDTO.init)
        requestId = outcome.requestID
        sessionId = outcome.sessionID?.rawValue
        surface = outcome.surface
        switch outcome.status {
        case .committed: status = .committed
        case .admissionRequired(let choice):
            status = .admissionRequired(
                reason: choice.reason,
                candidateSessionIds: choice.candidateSessionIDs.map(\.rawValue)
            )
        case .output(let output): status = .output(.init(output))
        case .history(let summaries):
            status = .history(summaries.map(BridgeProductAnnotationOutputHistoryDTO.init))
        case .viewed(let results):
            status = .viewed(results.map(BridgeProductWorktreeAnnotationViewedResultDTO.init))
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
        if case .viewed = status {
            guard container.contains(.receipt), try container.decodeNil(forKey: .receipt) else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Viewed annotation outcomes require an explicit null receipt",
                    codingPath: decoder.codingPath
                )
            }
            receipt = nil
        } else {
            let receiptIsNull = try container.contains(.receipt) && container.decodeNil(forKey: .receipt)
            guard !receiptIsNull else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Only viewed annotation outcomes permit a null receipt",
                    codingPath: decoder.codingPath
                )
            }
            receipt = try container.decodeIfPresent(
                BridgeProductWorktreeAnnotationMessageReceiptDTO.self,
                forKey: .receipt
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if case .viewed = status {
            try container.encodeNil(forKey: .receipt)
        } else {
            try container.encodeIfPresent(receipt, forKey: .receipt)
        }
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
        case canMarkNotHandled
        case createdAtUnixMilliseconds
        case messageCount
        case outputKind
        case repeatedFromAttemptId
        case sessionId
        case state
        case updatedAtUnixMilliseconds
    }

    let attemptId: UUID
    let canMarkNotHandled: Bool
    let createdAt: Date
    let messageCount: Int
    let outputKind: WorktreeAnnotationOutputKind
    let repeatedFromAttemptId: UUID?
    let sessionId: UUID
    let state: WorktreeAnnotationOutputAttemptState
    let updatedAt: Date

    init(_ summary: WorktreeAnnotationOutputHistorySummary) {
        attemptId = summary.attemptID.rawValue
        canMarkNotHandled = summary.canMarkNotHandled
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
        canMarkNotHandled = try container.decode(Bool.self, forKey: .canMarkNotHandled)
        createdAt = annotationDateFromUnixMilliseconds(
            try container.decode(Int64.self, forKey: .createdAtUnixMilliseconds)
        )
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
        updatedAt = annotationDateFromUnixMilliseconds(
            try container.decode(Int64.self, forKey: .updatedAtUnixMilliseconds)
        )
        guard messageCount > 0, state == .succeeded || !canMarkNotHandled else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation output history state is invalid",
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
        try container.encode(canMarkNotHandled, forKey: .canMarkNotHandled)
        try container.encode(
            annotationUnixMilliseconds(createdAt),
            forKey: .createdAtUnixMilliseconds
        )
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
        try container.encode(
            annotationUnixMilliseconds(updatedAt),
            forKey: .updatedAtUnixMilliseconds
        )
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

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(activeEditToken, forKey: .activeEditToken)
            try container.encode(body, forKey: .body)
            try container.encode(revision, forKey: .revision)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case attentionState
        case authorKind
        case createdAtUnixMilliseconds
        case draft
        case handled
        case messageId
        case messageRevision
        case ordinal
        case savedBody
        case savedRevision
        case sessionId
        case sessionRevision
        case status
        case threadId
        case threadRevision
    }

    let attentionState: WorktreeAnnotationAttentionState
    let authorKind: WorktreeAnnotationAuthorKind
    let createdAt: Date
    let draft: DraftEntry?
    let handled: Bool
    let messageId: UUID
    let messageRevision: Int
    let ordinal: Int
    let savedBody: String?
    let savedRevision: Int?
    let sessionId: UUID
    let sessionRevision: Int
    let status: WorktreeAnnotationMessageStatus
    let threadId: UUID
    let threadRevision: Int

    init(
        message: WorktreeAnnotationMessage,
        session: WorktreeAnnotationSession,
        thread: WorktreeAnnotationThread
    ) throws {
        let newPendingProjection = try message.projectNewPendingState()
        attentionState = newPendingProjection.attentionState
        authorKind = message.authorKind
        createdAt = message.createdAt
        draft = message.draft.map {
            DraftEntry(activeEditToken: $0.activeEditToken, body: $0.body, revision: $0.draftRevision)
        }
        handled = message.handled
        messageId = message.id.rawValue
        messageRevision = message.semanticRevision
        ordinal = message.ordinal
        savedBody = message.savedBody
        savedRevision = message.savedRevision
        sessionId = session.id.rawValue
        sessionRevision = session.semanticRevision
        status = message.status
        threadId = thread.id.rawValue
        threadRevision = thread.semanticRevision
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(self).count <= 64 * 1024 else {
            throw BridgeProductWorktreeAnnotationProjectionError.messageEntryExceedsMaximum
        }
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attentionState = try container.decode(WorktreeAnnotationAttentionState.self, forKey: .attentionState)
        authorKind = try container.decode(WorktreeAnnotationAuthorKind.self, forKey: .authorKind)
        createdAt = annotationDateFromUnixMilliseconds(
            try container.decode(Int64.self, forKey: .createdAtUnixMilliseconds)
        )
        draft = try BridgeProductContractDecoding.decodeRequiredNullable(
            DraftEntry.self,
            forKey: .draft,
            from: container,
            codingPath: decoder.codingPath
        )
        handled = try container.decode(Bool.self, forKey: .handled)
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
        threadRevision = try container.decode(Int.self, forKey: .threadRevision)
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
        let projectedViewedSavedRevision: Int? =
            attentionState == .viewed ? savedRevision : nil
        let decodedMessage = WorktreeAnnotationMessage(
            id: .init(rawValue: messageId),
            threadID: .init(rawValue: threadId),
            ordinal: ordinal,
            semanticRevision: messageRevision,
            createdAt: createdAt,
            updatedAt: createdAt,
            savedBody: savedBody,
            savedRevision: savedRevision,
            draft: draft.map {
                WorktreeAnnotationDraft(
                    messageID: .init(rawValue: messageId),
                    activeEditToken: $0.activeEditToken,
                    body: $0.body,
                    draftRevision: $0.revision,
                    updatedAt: createdAt
                )
            },
            handled: handled,
            status: status,
            authorKind: authorKind,
            viewedSavedRevision: projectedViewedSavedRevision
        )
        let projection: WorktreeAnnotationMessageNewPendingProjection
        do {
            projection = try decodedMessage.projectNewPendingState()
        } catch {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation message author and attention state are invalid",
                codingPath: decoder.codingPath
            )
        }
        guard projection.attentionState == attentionState else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation message author and attention state are invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attentionState, forKey: .attentionState)
        try container.encode(authorKind, forKey: .authorKind)
        try container.encode(
            annotationUnixMilliseconds(createdAt),
            forKey: .createdAtUnixMilliseconds
        )
        try container.encode(draft, forKey: .draft)
        try container.encode(handled, forKey: .handled)
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
        try container.encode(threadRevision, forKey: .threadRevision)
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

struct BridgeProductWorktreeAnnotationEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case operationCorrelationId
        case sourceGeneration
        case worktreeId
    }

    let operationCorrelationID: String
    let sourceGeneration: Int
    let worktreeID: String

    init(operationCorrelationID: String, sourceGeneration: Int, worktreeID: String) throws {
        self.operationCorrelationID = operationCorrelationID
        self.sourceGeneration = sourceGeneration
        self.worktreeID = worktreeID
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation invalidation"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "snapshot.required" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation invalidation kind",
                codingPath: decoder.codingPath
            )
        }
        operationCorrelationID = try container.decode(String.self, forKey: .operationCorrelationId)
        sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        worktreeID = try container.decode(String.self, forKey: .worktreeId)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("snapshot.required", forKey: .eventKind)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(worktreeID, forKey: .worktreeId)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateSHA256(
            operationCorrelationID,
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            sourceGeneration,
            name: "sourceGeneration",
            codingPath: codingPath
        )
        guard !worktreeID.isEmpty else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation invalidation worktree identity must be nonempty",
                codingPath: codingPath
            )
        }
    }
}
