import Foundation

struct WorktreeAnnotationBatchSnapshot: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    static let schema = "agentstudio.worktree-annotations.batch"

    let schema: String
    let formatVersion: Int
    let batchID: WorktreeAnnotationOutputAttemptID
    let createdAt: String
    let session: SessionContext
    let entries: [Entry]

    struct SessionContext: Codable, Equatable, Sendable {
        let sessionID: WorktreeAnnotationSessionID
        let label: String
        let repositoryID: String
        let worktreeID: String
        let lifecycle: WorktreeAnnotationSessionLifecycle
        let sourceRelationship: WorktreeAnnotationSourceRelationship

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case label, lifecycle, sourceRelationship
            case repositoryID = "repositoryId"
            case sessionID = "sessionId"
            case worktreeID = "worktreeId"
        }

        init(
            sessionID: WorktreeAnnotationSessionID,
            label: String,
            repositoryID: String,
            worktreeID: String,
            lifecycle: WorktreeAnnotationSessionLifecycle,
            sourceRelationship: WorktreeAnnotationSourceRelationship
        ) {
            self.sessionID = sessionID
            self.label = label
            self.repositoryID = repositoryID
            self.worktreeID = worktreeID
            self.lifecycle = lifecycle
            self.sourceRelationship = sourceRelationship
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch session")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try container.decode(WorktreeAnnotationSessionID.self, forKey: .sessionID)
            label = try container.decode(String.self, forKey: .label)
            repositoryID = try container.decode(String.self, forKey: .repositoryID)
            worktreeID = try container.decode(String.self, forKey: .worktreeID)
            lifecycle = try container.decode(WorktreeAnnotationSessionLifecycle.self, forKey: .lifecycle)
            sourceRelationship = try container.decode(
                WorktreeAnnotationSourceRelationship.self,
                forKey: .sourceRelationship
            )
        }
    }

    struct Entry: Codable, Equatable, Sendable {
        let batchOrdinal: Int
        let thread: ThreadContext
        let message: MessageContext

        private enum CodingKeys: String, CodingKey, CaseIterable { case batchOrdinal, message, thread }

        init(batchOrdinal: Int, thread: ThreadContext, message: MessageContext) {
            self.batchOrdinal = batchOrdinal
            self.thread = thread
            self.message = message
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch entry")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            batchOrdinal = try container.decode(Int.self, forKey: .batchOrdinal)
            thread = try container.decode(ThreadContext.self, forKey: .thread)
            message = try container.decode(MessageContext.self, forKey: .message)
        }

        var threadID: WorktreeAnnotationThreadID { thread.threadID }
        var messageID: WorktreeAnnotationMessageID { message.messageID }
        var messageOrdinal: Int { message.messageOrdinal }
        var savedRevision: Int { message.savedRevision }
        var bodyMarkdown: String { message.bodyMarkdown }
        var resolution: WorktreeAnnotationThreadResolution { thread.resolution }
        var origin: Origin { thread.origin }
        var placement: Placement { thread.placement }
    }

    struct ThreadContext: Codable, Equatable, Sendable {
        let threadID: WorktreeAnnotationThreadID
        let resolution: WorktreeAnnotationThreadResolution
        let origin: Origin
        let placement: Placement

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case origin, placement, resolution
            case threadID = "threadId"
        }

        init(
            threadID: WorktreeAnnotationThreadID,
            resolution: WorktreeAnnotationThreadResolution,
            origin: Origin,
            placement: Placement
        ) {
            self.threadID = threadID
            self.resolution = resolution
            self.origin = origin
            self.placement = placement
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch thread")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            threadID = try container.decode(WorktreeAnnotationThreadID.self, forKey: .threadID)
            resolution = try container.decode(WorktreeAnnotationThreadResolution.self, forKey: .resolution)
            origin = try container.decode(Origin.self, forKey: .origin)
            placement = try container.decode(Placement.self, forKey: .placement)
        }
    }

    struct MessageContext: Codable, Equatable, Sendable {
        struct Author: Codable, Equatable, Sendable {
            enum Kind: String, Codable, Sendable { case human }

            let kind: Kind

            private enum CodingKeys: String, CodingKey, CaseIterable { case kind }

            init(kind: Kind) {
                self.kind = kind
            }

            init(from decoder: Decoder) throws {
                try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch author")
                let container = try decoder.container(keyedBy: CodingKeys.self)
                kind = try container.decode(Kind.self, forKey: .kind)
            }
        }

        let messageID: WorktreeAnnotationMessageID
        let messageOrdinal: Int
        let author: Author
        let savedRevision: Int
        let bodyMarkdown: String

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case author, bodyMarkdown, messageOrdinal, savedRevision
            case messageID = "messageId"
        }

        init(
            messageID: WorktreeAnnotationMessageID,
            messageOrdinal: Int,
            savedRevision: Int,
            bodyMarkdown: String
        ) {
            self.messageID = messageID
            self.messageOrdinal = messageOrdinal
            author = Author(kind: .human)
            self.savedRevision = savedRevision
            self.bodyMarkdown = bodyMarkdown
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch message")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            messageID = try container.decode(WorktreeAnnotationMessageID.self, forKey: .messageID)
            messageOrdinal = try container.decode(Int.self, forKey: .messageOrdinal)
            author = try container.decode(Author.self, forKey: .author)
            savedRevision = try container.decode(Int.self, forKey: .savedRevision)
            bodyMarkdown = try container.decode(String.self, forKey: .bodyMarkdown)
        }
    }

    struct Origin: Codable, Equatable, Sendable {
        let path: String
        let source: Source
        let startLine: Int
        let endLine: Int
        let excerpt: [ExcerptLine]

        private enum CodingKeys: String, CodingKey, CaseIterable { case endLine, excerpt, path, source, startLine }

        init(path: String, source: Source, startLine: Int, endLine: Int, excerpt: [ExcerptLine]) {
            self.path = path
            self.source = source
            self.startLine = startLine
            self.endLine = endLine
            self.excerpt = excerpt
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch origin")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            source = try container.decode(Source.self, forKey: .source)
            startLine = try container.decode(Int.self, forKey: .startLine)
            endLine = try container.decode(Int.self, forKey: .endLine)
            excerpt = try container.decode([ExcerptLine].self, forKey: .excerpt)
        }
    }

    struct ExcerptLine: Codable, Equatable, Sendable {
        let lineNumber: Int
        let text: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case lineNumber, text }

        init(lineNumber: Int, text: String) {
            self.lineNumber = lineNumber
            self.text = text
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch excerpt line")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lineNumber = try container.decode(Int.self, forKey: .lineNumber)
            text = try container.decode(String.self, forKey: .text)
        }
    }

    enum Source: Codable, Equatable, Sendable {
        case file(sourceIdentity: String)
        case diff(
            side: DiffSide,
            sourceIdentity: String,
            comparisonOrigin: ComparisonOrigin
        )

        enum DiffSide: String, Codable, Sendable { case old, new }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case comparisonOrigin, kind, side, sourceIdentity
        }
        private enum Kind: String, Codable { case file, diff }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .file:
                try rejectUnknownBatchKeys(
                    decoder,
                    [CodingKeys.kind, .sourceIdentity],
                    contract: "batch file source"
                )
                self = .file(sourceIdentity: try container.decode(String.self, forKey: .sourceIdentity))
            case .diff:
                try rejectUnknownBatchKeys(
                    decoder,
                    [CodingKeys.comparisonOrigin, .kind, .side, .sourceIdentity],
                    contract: "batch diff source"
                )
                self = .diff(
                    side: try container.decode(DiffSide.self, forKey: .side),
                    sourceIdentity: try container.decode(String.self, forKey: .sourceIdentity),
                    comparisonOrigin: try container.decode(ComparisonOrigin.self, forKey: .comparisonOrigin)
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .file(let sourceIdentity):
                try container.encode(Kind.file, forKey: .kind)
                try container.encode(sourceIdentity, forKey: .sourceIdentity)
            case .diff(let side, let sourceIdentity, let comparisonOrigin):
                try container.encode(Kind.diff, forKey: .kind)
                try container.encode(side, forKey: .side)
                try container.encode(sourceIdentity, forKey: .sourceIdentity)
                try container.encode(comparisonOrigin, forKey: .comparisonOrigin)
            }
        }
    }

    struct ComparisonOrigin: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case contribution }
        enum BaseRole: String, Codable, Sendable { case commonCommit, selectedTarget }
        enum ComparedRole: String, Codable, Sendable { case capturedWorkingTree }

        let kind: Kind
        let baseRole: BaseRole
        let comparedRole: ComparedRole
        let symbolicTarget: ComparisonTarget
        let resolvedTargetOID: String
        let reviewedHeadOID: String
        let baseOID: String

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case baseOID, baseRole, comparedRole, kind, resolvedTargetOID, reviewedHeadOID, symbolicTarget
        }

        init(
            kind: Kind = .contribution,
            baseRole: BaseRole,
            comparedRole: ComparedRole = .capturedWorkingTree,
            symbolicTarget: ComparisonTarget,
            resolvedTargetOID: String,
            reviewedHeadOID: String,
            baseOID: String
        ) {
            self.kind = kind
            self.baseRole = baseRole
            self.comparedRole = comparedRole
            self.symbolicTarget = symbolicTarget
            self.resolvedTargetOID = resolvedTargetOID
            self.reviewedHeadOID = reviewedHeadOID
            self.baseOID = baseOID
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch comparison origin")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(Kind.self, forKey: .kind)
            baseRole = try container.decode(BaseRole.self, forKey: .baseRole)
            comparedRole = try container.decode(ComparedRole.self, forKey: .comparedRole)
            symbolicTarget = try container.decode(ComparisonTarget.self, forKey: .symbolicTarget)
            resolvedTargetOID = try container.decode(String.self, forKey: .resolvedTargetOID)
            reviewedHeadOID = try container.decode(String.self, forKey: .reviewedHeadOID)
            baseOID = try container.decode(String.self, forKey: .baseOID)
        }
    }

    enum ComparisonTarget: Codable, Equatable, Sendable {
        case localDefaultBranch(basis: String, branchName: String)
        case originDefaultBranch(basis: String, branchName: String, remoteName: String)
        case branch(basis: String, name: String)
        case commit(oid: String)
        case ref(basis: String, name: String)

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case basis, branchName, kind, name, oid, remoteName
        }
        private enum Kind: String, Codable {
            case localDefaultBranch, originDefaultBranch, branch, commit, ref
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .localDefaultBranch:
                try rejectUnknownBatchKeys(
                    decoder,
                    [CodingKeys.basis, .branchName, .kind],
                    contract: "batch target"
                )
                self = .localDefaultBranch(
                    basis: try container.decode(String.self, forKey: .basis),
                    branchName: try container.decode(String.self, forKey: .branchName)
                )
            case .originDefaultBranch:
                try rejectUnknownBatchKeys(
                    decoder,
                    [CodingKeys.basis, .branchName, .kind, .remoteName],
                    contract: "batch target"
                )
                self = .originDefaultBranch(
                    basis: try container.decode(String.self, forKey: .basis),
                    branchName: try container.decode(String.self, forKey: .branchName),
                    remoteName: try container.decode(String.self, forKey: .remoteName)
                )
            case .branch:
                try rejectUnknownBatchKeys(
                    decoder,
                    [CodingKeys.basis, .kind, .name],
                    contract: "batch target"
                )
                self = .branch(
                    basis: try container.decode(String.self, forKey: .basis),
                    name: try container.decode(String.self, forKey: .name)
                )
            case .commit:
                try rejectUnknownBatchKeys(decoder, [CodingKeys.kind, .oid], contract: "batch target")
                self = .commit(oid: try container.decode(String.self, forKey: .oid))
            case .ref:
                try rejectUnknownBatchKeys(
                    decoder,
                    [CodingKeys.basis, .kind, .name],
                    contract: "batch target"
                )
                self = .ref(
                    basis: try container.decode(String.self, forKey: .basis),
                    name: try container.decode(String.self, forKey: .name)
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .localDefaultBranch(let basis, let branchName):
                try container.encode(Kind.localDefaultBranch, forKey: .kind)
                try container.encode(basis, forKey: .basis)
                try container.encode(branchName, forKey: .branchName)
            case .originDefaultBranch(let basis, let branchName, let remoteName):
                try container.encode(Kind.originDefaultBranch, forKey: .kind)
                try container.encode(basis, forKey: .basis)
                try container.encode(branchName, forKey: .branchName)
                try container.encode(remoteName, forKey: .remoteName)
            case .branch(let basis, let name):
                try container.encode(Kind.branch, forKey: .kind)
                try container.encode(basis, forKey: .basis)
                try container.encode(name, forKey: .name)
            case .commit(let oid):
                try container.encode(Kind.commit, forKey: .kind)
                try container.encode(oid, forKey: .oid)
            case .ref(let basis, let name):
                try container.encode(Kind.ref, forKey: .kind)
                try container.encode(basis, forKey: .basis)
                try container.encode(name, forKey: .name)
            }
        }
    }

    struct Coordinate: Codable, Equatable, Sendable {
        let path: String
        let source: Source
        let startLine: Int
        let endLine: Int

        private enum CodingKeys: String, CodingKey, CaseIterable { case endLine, path, source, startLine }

        init(path: String, source: Source, startLine: Int, endLine: Int) {
            self.path = path
            self.source = source
            self.startLine = startLine
            self.endLine = endLine
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch coordinate")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            source = try container.decode(Source.self, forKey: .source)
            startLine = try container.decode(Int.self, forKey: .startLine)
            endLine = try container.decode(Int.self, forKey: .endLine)
        }
    }

    enum Placement: Codable, Equatable, Sendable {
        case exact(Coordinate)
        case relocated(Coordinate)
        case outdated
        case unavailable

        private enum CodingKeys: String, CodingKey, CaseIterable { case current, status }
        private enum Status: String, Codable { case exact, relocated, outdated, unavailable }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "batch placement")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Status.self, forKey: .status) {
            case .exact:
                self = .exact(try container.decode(Coordinate.self, forKey: .current))
            case .relocated:
                self = .relocated(try container.decode(Coordinate.self, forKey: .current))
            case .outdated:
                guard try container.decodeNil(forKey: .current) else {
                    throw batchDecodingError(decoder, "Outdated placement current coordinate must be null")
                }
                self = .outdated
            case .unavailable:
                guard try container.decodeNil(forKey: .current) else {
                    throw batchDecodingError(decoder, "Unavailable placement current coordinate must be null")
                }
                self = .unavailable
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .exact(let coordinate):
                try container.encode(Status.exact, forKey: .status)
                try container.encode(coordinate, forKey: .current)
            case .relocated(let coordinate):
                try container.encode(Status.relocated, forKey: .status)
                try container.encode(coordinate, forKey: .current)
            case .outdated:
                try container.encode(Status.outdated, forKey: .status)
                try container.encodeNil(forKey: .current)
            case .unavailable:
                try container.encode(Status.unavailable, forKey: .status)
                try container.encodeNil(forKey: .current)
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case createdAt, entries, formatVersion, schema, session
        case batchID = "batchId"
    }

    init(
        schema: String = Self.schema,
        formatVersion: Int = currentFormatVersion,
        batchID: WorktreeAnnotationOutputAttemptID,
        createdAt: String,
        session: SessionContext,
        entries: [Entry]
    ) {
        self.schema = schema
        self.formatVersion = formatVersion
        self.batchID = batchID
        self.createdAt = createdAt
        self.session = session
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "annotation batch")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        batchID = try container.decode(WorktreeAnnotationOutputAttemptID.self, forKey: .batchID)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        session = try container.decode(SessionContext.self, forKey: .session)
        entries = try container.decode([Entry].self, forKey: .entries)
    }
}

func rejectUnknownBatchKeys<TCodingKey: CodingKey & CaseIterable>(
    _ decoder: Decoder,
    _ keyType: TCodingKey.Type,
    contract: String
) throws {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(keyType.allCases.map(\.stringValue)),
        contract: contract
    )
}

func rejectUnknownBatchKeys<TCodingKey: CodingKey>(
    _ decoder: Decoder,
    _ allowedKeys: [TCodingKey],
    contract: String
) throws {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(allowedKeys.map(\.stringValue)),
        contract: contract
    )
}

private func batchDecodingError(_ decoder: Decoder, _ description: String) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
}
