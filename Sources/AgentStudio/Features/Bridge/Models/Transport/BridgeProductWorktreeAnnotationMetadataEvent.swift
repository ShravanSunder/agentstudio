import Foundation

enum WorktreeAnnotationCatalogEntry: Codable, Equatable, Sendable {
    case session(Session)
    case thread(Thread)
    case message(Message)

    struct Session: Equatable, Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let semanticRevision: Int

        init(sessionID: WorktreeAnnotationSessionID, semanticRevision: Int) throws {
            self.sessionID = sessionID
            self.semanticRevision = semanticRevision
            try validate(codingPath: [])
        }

        fileprivate func validate(codingPath: [any CodingKey]) throws {
            try BridgeProductContractDecoding.validateNonnegative(
                semanticRevision,
                name: "semanticRevision",
                codingPath: codingPath
            )
        }
    }

    struct Thread: Equatable, Sendable {
        let threadID: WorktreeAnnotationThreadID
        let sessionID: WorktreeAnnotationSessionID
        let scope: WorktreeAnnotationThreadScope
        let createdOrdinal: Int

        init(
            threadID: WorktreeAnnotationThreadID,
            sessionID: WorktreeAnnotationSessionID,
            scope: WorktreeAnnotationThreadScope,
            createdOrdinal: Int
        ) throws {
            self.threadID = threadID
            self.sessionID = sessionID
            self.scope = scope
            self.createdOrdinal = createdOrdinal
            try validate(codingPath: [])
        }

        fileprivate func validate(codingPath: [any CodingKey]) throws {
            try BridgeProductContractDecoding.validateNonnegative(
                createdOrdinal,
                name: "createdOrdinal",
                codingPath: codingPath
            )
        }
    }

    struct Message: Equatable, Sendable {
        let messageID: WorktreeAnnotationMessageID
        let threadID: WorktreeAnnotationThreadID
        let ordinal: Int

        init(
            messageID: WorktreeAnnotationMessageID,
            threadID: WorktreeAnnotationThreadID,
            ordinal: Int
        ) throws {
            self.messageID = messageID
            self.threadID = threadID
            self.ordinal = ordinal
            try validate(codingPath: [])
        }

        fileprivate func validate(codingPath: [any CodingKey]) throws {
            try BridgeProductContractDecoding.validateNonnegative(
                ordinal,
                name: "ordinal",
                codingPath: codingPath
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case createdOrdinal
        case kind
        case messageID = "messageId"
        case ordinal
        case scope
        case semanticRevision
        case sessionID = "sessionId"
        case threadID = "threadId"
    }

    private enum Kind: String, Codable {
        case message
        case session
        case thread
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> =
            switch kind {
            case .session:
                [
                    CodingKeys.kind.rawValue,
                    CodingKeys.semanticRevision.rawValue,
                    CodingKeys.sessionID.rawValue,
                ]
            case .thread:
                [
                    CodingKeys.createdOrdinal.rawValue,
                    CodingKeys.kind.rawValue,
                    CodingKeys.scope.rawValue,
                    CodingKeys.sessionID.rawValue,
                    CodingKeys.threadID.rawValue,
                ]
            case .message:
                [
                    CodingKeys.kind.rawValue,
                    CodingKeys.messageID.rawValue,
                    CodingKeys.ordinal.rawValue,
                    CodingKeys.threadID.rawValue,
                ]
            }
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: allowedKeys,
            contract: "worktree annotation catalog entry"
        )

        switch kind {
        case .session:
            self = .session(
                try .init(
                    sessionID: Self.decodeSessionID(from: container, codingPath: decoder.codingPath),
                    semanticRevision: container.decode(Int.self, forKey: .semanticRevision)
                )
            )
        case .thread:
            self = .thread(
                try .init(
                    threadID: Self.decodeThreadID(from: container, codingPath: decoder.codingPath),
                    sessionID: Self.decodeSessionID(from: container, codingPath: decoder.codingPath),
                    scope: container.decode(WorktreeAnnotationThreadScope.self, forKey: .scope),
                    createdOrdinal: container.decode(Int.self, forKey: .createdOrdinal)
                )
            )
        case .message:
            self = .message(
                try .init(
                    messageID: Self.decodeMessageID(from: container, codingPath: decoder.codingPath),
                    threadID: Self.decodeThreadID(from: container, codingPath: decoder.codingPath),
                    ordinal: container.decode(Int.self, forKey: .ordinal)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let session):
            try session.validate(codingPath: encoder.codingPath)
            try container.encode(Kind.session, forKey: .kind)
            try container.encode(
                Self.encodeIdentity(session.sessionID.rawValue),
                forKey: .sessionID
            )
            try container.encode(session.semanticRevision, forKey: .semanticRevision)
        case .thread(let thread):
            try thread.validate(codingPath: encoder.codingPath)
            try container.encode(thread.createdOrdinal, forKey: .createdOrdinal)
            try container.encode(Kind.thread, forKey: .kind)
            try container.encode(thread.scope, forKey: .scope)
            try container.encode(
                Self.encodeIdentity(thread.sessionID.rawValue),
                forKey: .sessionID
            )
            try container.encode(
                Self.encodeIdentity(thread.threadID.rawValue),
                forKey: .threadID
            )
        case .message(let message):
            try message.validate(codingPath: encoder.codingPath)
            try container.encode(Kind.message, forKey: .kind)
            try container.encode(
                Self.encodeIdentity(message.messageID.rawValue),
                forKey: .messageID
            )
            try container.encode(message.ordinal, forKey: .ordinal)
            try container.encode(
                Self.encodeIdentity(message.threadID.rawValue),
                forKey: .threadID
            )
        }
    }

    private static func decodeSessionID(
        from container: KeyedDecodingContainer<CodingKeys>,
        codingPath: [any CodingKey]
    ) throws -> WorktreeAnnotationSessionID {
        .init(
            rawValue: try decodeIdentity(
                container.decode(String.self, forKey: .sessionID),
                codingPath: codingPath + [CodingKeys.sessionID]
            )
        )
    }

    private static func decodeThreadID(
        from container: KeyedDecodingContainer<CodingKeys>,
        codingPath: [any CodingKey]
    ) throws -> WorktreeAnnotationThreadID {
        .init(
            rawValue: try decodeIdentity(
                container.decode(String.self, forKey: .threadID),
                codingPath: codingPath + [CodingKeys.threadID]
            )
        )
    }

    private static func decodeMessageID(
        from container: KeyedDecodingContainer<CodingKeys>,
        codingPath: [any CodingKey]
    ) throws -> WorktreeAnnotationMessageID {
        .init(
            rawValue: try decodeIdentity(
                container.decode(String.self, forKey: .messageID),
                codingPath: codingPath + [CodingKeys.messageID]
            )
        )
    }

    private static func decodeIdentity(
        _ value: String,
        codingPath: [any CodingKey]
    ) throws -> UUID {
        try BridgeProductReviewPublicationIdContract.decode(value, codingPath: codingPath)
    }

    private static func encodeIdentity(_ identity: UUID) -> String {
        BridgeProductReviewPublicationIdContract.encode(identity)
    }
}

enum BridgeProductWorktreeAnnotationEvent: Codable, Equatable, Sendable {
    case catalog(Catalog)
    case sessionChanged(SessionChanged)
    case controlChanged(ControlChanged)

    struct Authority: Codable, Equatable, Sendable {
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case applicationSourceGeneration
            case worktreeID = "worktreeId"
        }

        let worktreeID: String
        let applicationSourceGeneration: Int

        init(worktreeID: String, applicationSourceGeneration: Int) throws {
            self.worktreeID = worktreeID
            self.applicationSourceGeneration = applicationSourceGeneration
            try validate(codingPath: [])
        }

        init(from decoder: Decoder) throws {
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
                contract: "worktree annotation event authority"
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            worktreeID = try container.decode(String.self, forKey: .worktreeID)
            applicationSourceGeneration = try container.decode(
                Int.self,
                forKey: .applicationSourceGeneration
            )
            try validate(codingPath: decoder.codingPath)
        }

        func encode(to encoder: Encoder) throws {
            try validate(codingPath: encoder.codingPath)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(applicationSourceGeneration, forKey: .applicationSourceGeneration)
            try container.encode(worktreeID, forKey: .worktreeID)
        }

        private func validate(codingPath: [any CodingKey]) throws {
            try BridgeProductContractDecoding.validateNonnegative(
                applicationSourceGeneration,
                name: "applicationSourceGeneration",
                codingPath: codingPath
            )
            try BridgeProductContractDecoding.validateIdentifier(worktreeID, codingPath: codingPath)
        }
    }

    struct Catalog: Equatable, Sendable {
        let authority: Authority
        let transfer: BridgeProductMetadataCatalogTransfer<WorktreeAnnotationCatalogEntry>

        init(
            authority: Authority,
            transfer: BridgeProductMetadataCatalogTransfer<WorktreeAnnotationCatalogEntry>
        ) throws {
            self.authority = authority
            self.transfer = transfer
            try validate(codingPath: [])
        }

        fileprivate func validate(codingPath: [any CodingKey]) throws {
            guard transfer.catalogRevision == authority.applicationSourceGeneration else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Annotation catalog revision must equal its application source generation",
                    codingPath: codingPath
                )
            }
        }
    }

    struct SessionChanged: Equatable, Sendable {
        let authority: Authority
        let sessionID: WorktreeAnnotationSessionID
        let semanticRevision: Int

        init(
            authority: Authority,
            sessionID: WorktreeAnnotationSessionID,
            semanticRevision: Int
        ) throws {
            self.authority = authority
            self.sessionID = sessionID
            self.semanticRevision = semanticRevision
            try validate(codingPath: [])
        }

        fileprivate func validate(codingPath: [any CodingKey]) throws {
            try BridgeProductContractDecoding.validatePositive(
                semanticRevision,
                name: "semanticRevision",
                codingPath: codingPath
            )
        }
    }

    struct ControlChanged: Equatable, Sendable {
        let authority: Authority
        let reason: ControlChangedReason
    }

    enum ControlChangedReason: String, Codable, Equatable, Sendable {
        case discovery
        case recovery
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case authority
        case kind
        case reason
        case semanticRevision
        case sessionID = "sessionId"
        case transfer
    }

    private enum Kind: String, Codable {
        case catalog = "annotation.catalog"
        case controlChanged = "annotation.controlChanged"
        case sessionChanged = "annotation.sessionChanged"
    }

    var authority: Authority {
        switch self {
        case .catalog(let event): event.authority
        case .sessionChanged(let event): event.authority
        case .controlChanged(let event): event.authority
        }
    }

    var sourceGeneration: Int { authority.applicationSourceGeneration }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let allowedKeys: Set<String> =
            switch kind {
            case .catalog:
                [CodingKeys.authority.rawValue, CodingKeys.kind.rawValue, CodingKeys.transfer.rawValue]
            case .sessionChanged:
                [
                    CodingKeys.authority.rawValue,
                    CodingKeys.kind.rawValue,
                    CodingKeys.semanticRevision.rawValue,
                    CodingKeys.sessionID.rawValue,
                ]
            case .controlChanged:
                [CodingKeys.authority.rawValue, CodingKeys.kind.rawValue, CodingKeys.reason.rawValue]
            }
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: allowedKeys,
            contract: "worktree annotation metadata event"
        )

        let authority = try container.decode(Authority.self, forKey: .authority)
        switch kind {
        case .catalog:
            self = .catalog(
                try .init(
                    authority: authority,
                    transfer: container.decode(
                        BridgeProductMetadataCatalogTransfer<WorktreeAnnotationCatalogEntry>.self,
                        forKey: .transfer
                    )
                )
            )
        case .sessionChanged:
            let sessionIDValue = try container.decode(String.self, forKey: .sessionID)
            let sessionID = WorktreeAnnotationSessionID(
                rawValue: try BridgeProductReviewPublicationIdContract.decode(
                    sessionIDValue,
                    codingPath: decoder.codingPath + [CodingKeys.sessionID]
                )
            )
            self = .sessionChanged(
                try .init(
                    authority: authority,
                    sessionID: sessionID,
                    semanticRevision: container.decode(Int.self, forKey: .semanticRevision)
                )
            )
        case .controlChanged:
            self = .controlChanged(
                .init(
                    authority: authority,
                    reason: try container.decode(ControlChangedReason.self, forKey: .reason)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .catalog(let event):
            try event.validate(codingPath: encoder.codingPath)
            try container.encode(event.authority, forKey: .authority)
            try container.encode(Kind.catalog, forKey: .kind)
            try container.encode(event.transfer, forKey: .transfer)
        case .sessionChanged(let event):
            try event.validate(codingPath: encoder.codingPath)
            try container.encode(event.authority, forKey: .authority)
            try container.encode(Kind.sessionChanged, forKey: .kind)
            try container.encode(event.semanticRevision, forKey: .semanticRevision)
            try container.encode(
                BridgeProductReviewPublicationIdContract.encode(event.sessionID.rawValue),
                forKey: .sessionID
            )
        case .controlChanged(let event):
            try container.encode(event.authority, forKey: .authority)
            try container.encode(Kind.controlChanged, forKey: .kind)
            try container.encode(event.reason, forKey: .reason)
        }
    }
}
