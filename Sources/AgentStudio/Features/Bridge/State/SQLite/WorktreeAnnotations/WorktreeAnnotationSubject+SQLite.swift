import AgentStudioCore
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

    /// A WHERE clause selecting the `annotation_session` rows of any of
    /// `subjects`; an empty set selects nothing.
    static func sessionRowPredicate(
        for subjects: Set<Self>,
        columnPrefix: String = ""
    ) -> (sql: String, arguments: StatementArguments) {
        let worktreeIDs = subjects.compactMap(\.gitWorktreeID).sorted()
        let documentPaths = subjects.compactMap(\.localDocument?.canonicalPath).sorted()
        var clauses: [String] = []
        var arguments = StatementArguments()
        if !worktreeIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: worktreeIDs.count).joined(separator: ", ")
            clauses.append(
                "(\(columnPrefix)subject_kind = 'git' AND \(columnPrefix)worktree_id IN (\(placeholders)))"
            )
            arguments += StatementArguments(worktreeIDs)
        }
        if !documentPaths.isEmpty {
            let placeholders = Array(repeating: "?", count: documentPaths.count).joined(separator: ", ")
            clauses.append(
                "(\(columnPrefix)subject_kind = 'localFile' AND \(columnPrefix)local_document_path IN (\(placeholders)))"
            )
            arguments += StatementArguments(documentPaths)
        }
        guard !clauses.isEmpty else { return ("0", []) }
        return ("(" + clauses.joined(separator: " OR ") + ")", arguments)
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
                let location = BridgeDocumentLocation(canonicalPath: localDocumentPath)
            else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
            return .localFile(location)
        default:
            throw WorktreeAnnotationRepositoryError.invalidState
        }
    }
}
