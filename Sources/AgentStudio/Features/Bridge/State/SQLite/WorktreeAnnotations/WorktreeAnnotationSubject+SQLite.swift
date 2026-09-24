import Foundation
import GRDB

/// How `annotation_session` stores a subject: a kind plus either the Git
/// repository and worktree or the local document's canonical path.
extension WorktreeAnnotationSubject {
    static let gitKind = "git"
    static let localFileKind = "localFile"

    var sessionKind: String {
        switch self {
        case .git: Self.gitKind
        case .localFile: Self.localFileKind
        }
    }

    /// A WHERE clause selecting this subject's `annotation_session` rows.
    /// `columnPrefix` qualifies the columns, e.g. `"s."`.
    func sessionRowPredicate(columnPrefix: String = "") -> (sql: String, arguments: StatementArguments) {
        switch self {
        case .git(_, let worktreeID):
            ("\(columnPrefix)subject_kind = 'git' AND \(columnPrefix)worktree_id = ?", [worktreeID])
        case .localFile(let documentPath):
            ("\(columnPrefix)subject_kind = 'localFile' AND \(columnPrefix)local_document_path = ?", [documentPath])
        }
    }

    /// Decode a session row's subject, failing closed on a row whose columns
    /// contradict its kind.
    static func decodeSessionRow(_ row: Row) throws -> Self {
        let kind: String = row["subject_kind"]
        let repositoryID: String? = row["repository_id"]
        let worktreeID: String? = row["worktree_id"]
        let localDocumentPath: String? = row["local_document_path"]
        switch kind {
        case gitKind:
            guard let repositoryID, !repositoryID.isEmpty, let worktreeID, !worktreeID.isEmpty,
                localDocumentPath == nil
            else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            return .git(repositoryID: repositoryID, worktreeID: worktreeID)
        case localFileKind:
            guard repositoryID == nil, worktreeID == nil, let localDocumentPath,
                localDocumentPath.hasPrefix("/"), localDocumentPath.count > 1
            else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            return .localFile(documentPath: localDocumentPath)
        default:
            throw WorktreeAnnotationRepositoryError.invalidState
        }
    }
}
