import AgentStudioCore
import Foundation

/// What an annotation session is about: one Git worktree, or one local
/// document outside every Git worktree. A local subject never carries branch,
/// comparison or ancestry evidence.
enum WorktreeAnnotationSubject: Hashable, Sendable {
    case git(repositoryID: String, worktreeID: String)
    /// A local document named by its canonical location.
    case localFile(BridgeDocumentLocation)

    var gitRepositoryID: String? {
        guard case .git(let repositoryID, _) = self else { return nil }
        return repositoryID
    }

    var gitWorktreeID: String? {
        guard case .git(_, let worktreeID) = self else { return nil }
        return worktreeID
    }

    var localDocument: BridgeDocumentLocation? {
        guard case .localFile(let location) = self else { return nil }
        return location
    }
}

extension WorktreeAnnotationSubject: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case repositoryID
        case worktreeID
        case documentPath
    }

    private enum Kind: String, Codable {
        case git
        case localFile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .git:
            guard !container.contains(.documentPath) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .documentPath, in: container,
                    debugDescription: "A Git annotation subject names no local document")
            }
            let repositoryID = try container.decode(String.self, forKey: .repositoryID)
            let worktreeID = try container.decode(String.self, forKey: .worktreeID)
            guard !repositoryID.isEmpty, !worktreeID.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .worktreeID, in: container,
                    debugDescription: "A Git annotation subject names its repository and worktree")
            }
            self = .git(repositoryID: repositoryID, worktreeID: worktreeID)
        case .localFile:
            guard !container.contains(.repositoryID), !container.contains(.worktreeID) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .repositoryID, in: container,
                    debugDescription: "A local annotation subject carries no Git identity")
            }
            let documentPath = try container.decode(String.self, forKey: .documentPath)
            guard let location = BridgeDocumentLocation(canonicalPath: documentPath) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .documentPath, in: container,
                    debugDescription: "A local annotation subject names a canonical absolute path")
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
            try container.encode(location.canonicalPath, forKey: .documentPath)
        }
    }
}

extension WorktreeAnnotationSubject: Comparable {
    /// Git subjects order before local ones; within a kind, by identity. Used
    /// only to publish changes in a deterministic order.
    static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.git(let lhsRepository, let lhsWorktree), .git(let rhsRepository, let rhsWorktree)):
            (lhsWorktree, lhsRepository) < (rhsWorktree, rhsRepository)
        case (.git, .localFile):
            true
        case (.localFile, .git):
            false
        case (.localFile(let lhsLocation), .localFile(let rhsLocation)):
            lhsLocation < rhsLocation
        }
    }
}

/// What a surface finds a subject's sessions by: a Git session belongs to its
/// worktree whichever repository it was recorded under, a local session to its
/// document. A worktree moved to another repository therefore keeps its
/// sessions in view; whether they still apply is continuity's call, which
/// compares the whole subject.
enum WorktreeAnnotationSubjectKey: Hashable, Sendable {
    case gitWorktree(worktreeID: String)
    case localDocument(BridgeDocumentLocation)
}

extension WorktreeAnnotationSubject {
    var key: WorktreeAnnotationSubjectKey {
        switch self {
        case .git(_, let worktreeID): .gitWorktree(worktreeID: worktreeID)
        case .localFile(let location): .localDocument(location)
        }
    }
}

extension Set where Element == WorktreeAnnotationSubject {
    /// Whether one of these subjects finds `subject`'s sessions.
    func containsKey(of subject: WorktreeAnnotationSubject) -> Bool {
        contains { $0.key == subject.key }
    }
}
