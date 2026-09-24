import AgentStudioCore
import Foundation

struct WorktreeAnnotationBatchSnapshotV3: Codable, Equatable, Sendable {
    static let currentFormatVersion = 3
    static let schema = WorktreeAnnotationBatchSnapshotV1.schema

    typealias Entry = WorktreeAnnotationBatchSnapshotV2.Entry

    struct SessionContext: Codable, Equatable, Sendable {
        enum Subject: Codable, Equatable, Sendable {
            case git(repositoryID: String, worktreeID: String)
            case localFile(BridgeDocumentLocation)

            fileprivate enum Kind: String, Codable {
                case git
                case localFile
            }

            private enum CodingKeys: String, CodingKey, CaseIterable {
                case documentLocation
                case kind
                case repositoryID = "repositoryId"
                case worktreeID = "worktreeId"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                switch try container.decode(Kind.self, forKey: .kind) {
                case .git:
                    try rejectUnknownBatchKeys(
                        decoder,
                        [CodingKeys.kind, .repositoryID, .worktreeID],
                        contract: "v3 Git annotation subject"
                    )
                    let repositoryID = try container.decode(String.self, forKey: .repositoryID)
                    let worktreeID = try container.decode(String.self, forKey: .worktreeID)
                    guard !repositoryID.isEmpty, !worktreeID.isEmpty else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .worktreeID,
                            in: container,
                            debugDescription: "A Git annotation subject names its repository and worktree"
                        )
                    }
                    self = .git(repositoryID: repositoryID, worktreeID: worktreeID)
                case .localFile:
                    try rejectUnknownBatchKeys(
                        decoder,
                        [CodingKeys.documentLocation, .kind],
                        contract: "v3 local-file annotation subject"
                    )
                    let canonicalPath = try container.decode(String.self, forKey: .documentLocation)
                    guard let location = BridgeDocumentLocation(canonicalPath: canonicalPath) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .documentLocation,
                            in: container,
                            debugDescription: "A local annotation subject names a canonical absolute document path"
                        )
                    }
                    self = .localFile(location)
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .git(let repositoryID, let worktreeID):
                    try container.encode(Kind.git, forKey: .kind)
                    try container.encode(repositoryID, forKey: .repositoryID)
                    try container.encode(worktreeID, forKey: .worktreeID)
                case .localFile(let location):
                    try container.encode(Kind.localFile, forKey: .kind)
                    try container.encode(location.canonicalPath, forKey: .documentLocation)
                }
            }

            var domainValue: WorktreeAnnotationSubject {
                switch self {
                case .git(let repositoryID, let worktreeID):
                    .git(repositoryID: repositoryID, worktreeID: worktreeID)
                case .localFile(let location):
                    .localFile(location)
                }
            }
        }

        let sessionID: WorktreeAnnotationSessionID
        let label: String
        let subject: Subject
        let lifecycle: WorktreeAnnotationSessionLifecycle
        let sourceRelationship: WorktreeAnnotationSourceRelationship

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case label, lifecycle, sourceRelationship, subject
            case sessionID = "sessionId"
        }

        init(
            sessionID: WorktreeAnnotationSessionID,
            label: String,
            subject: Subject,
            lifecycle: WorktreeAnnotationSessionLifecycle,
            sourceRelationship: WorktreeAnnotationSourceRelationship
        ) {
            self.sessionID = sessionID
            self.label = label
            self.subject = subject
            self.lifecycle = lifecycle
            self.sourceRelationship = sourceRelationship
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "v3 batch session")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try container.decode(WorktreeAnnotationSessionID.self, forKey: .sessionID)
            label = try container.decode(String.self, forKey: .label)
            subject = try container.decode(Subject.self, forKey: .subject)
            lifecycle = try container.decode(WorktreeAnnotationSessionLifecycle.self, forKey: .lifecycle)
            sourceRelationship = try container.decode(
                WorktreeAnnotationSourceRelationship.self,
                forKey: .sourceRelationship
            )
        }
    }

    let schema: String
    let formatVersion: Int
    let batchID: WorktreeAnnotationOutputAttemptID
    let createdAt: String
    let session: SessionContext
    let entries: [Entry]

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
        try rejectUnknownBatchKeys(decoder, CodingKeys.self, contract: "v3 annotation batch")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        batchID = try container.decode(WorktreeAnnotationOutputAttemptID.self, forKey: .batchID)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        session = try container.decode(SessionContext.self, forKey: .session)
        entries = try container.decode([Entry].self, forKey: .entries)
    }
}
