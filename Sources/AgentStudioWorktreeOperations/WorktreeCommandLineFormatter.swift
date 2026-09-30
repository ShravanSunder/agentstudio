import AgentStudioGit
import Foundation

package struct WorktreeCommandLineResponse: Sendable, Equatable {
    package let text: String
    package let exitCode: Int32

    package init(text: String, exitCode: Int32) {
        self.text = text
        self.exitCode = exitCode
    }
}

package enum WorktreeCommandLineFormatter {
    package static func format(
        outcome: WorktreeOperationOutcome,
        usesJSONOutput: Bool
    ) throws -> WorktreeCommandLineResponse {
        let exitCode: Int32
        switch outcome {
        case .created, .listed:
            exitCode = 0
        case .refused:
            exitCode = 1
        case .failed:
            exitCode = 2
        }

        let text: String
        if usesJSONOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(WorktreeCommandLineJSON(outcome: outcome))
            guard let encodedText = String(data: data, encoding: .utf8) else {
                throw WorktreeCommandLineFormattingError.invalidUTF8
            }
            text = encodedText
        } else {
            text = humanLine(for: outcome)
        }
        return WorktreeCommandLineResponse(text: text, exitCode: exitCode)
    }

    private static func humanLine(for outcome: WorktreeOperationOutcome) -> String {
        switch outcome {
        case .created(let summary):
            return "created \(summary.branch) at \(absolutePath(summary.path))"
        case .listed(let summary):
            return summary.worktrees.map { worktree in
                let kind = worktree.isMain ? "main" : "worktree"
                return "\(kind) \(worktree.branch ?? "detached") at \(absolutePath(worktree.path))"
            }.joined(separator: "\n")
        case .refused(let refusal):
            let details = refusalDetails(for: refusal)
            let suffix = [details.path, details.detail].compactMap { $0 }.joined(separator: " ")
            return suffix.isEmpty ? "refused: \(details.reason)" : "refused: \(details.reason) \(suffix)"
        case .failed(let failure):
            return "failed: \(humanFailure(failure.failure)); leftovers: \(humanLeftovers(failure.leftovers))"
        }
    }

    private static func humanFailure(_ failure: WorktreeFailureKind) -> String {
        switch failure {
        case .readFailed(let gitErrorKind):
            return "readFailed \(gitErrorKind.rawValue)"
        case .createFailed(let gitErrorKind):
            return "createFailed \(gitErrorKind.rawValue)"
        case .forkGitFailed(let gitErrorKind):
            return "forkGitFailed \(gitErrorKind.rawValue)"
        case .sourceChanged(let relativePath, let reason):
            return "sourceChanged \(relativePath) \(reason.rawValue)"
        case .entryFailed(let relativePath, let reason, let errorNumber):
            let errno = errorNumber.map { " errno \($0)" } ?? ""
            return "entryFailed \(relativePath) \(reason.rawValue)\(errno)"
        case .validationFailed(let reason, let relativePath):
            let path = relativePath.map { " \($0)" } ?? ""
            return "validationFailed \(reason.rawValue)\(path)"
        case .cancelled:
            return "cancelled"
        case .rejectedAfterChange(let reason):
            return "rejectedAfterChange \(reason.rawValue)"
        }
    }

    private static func humanLeftovers(_ leftovers: WorktreeLeftoverStatus) -> String {
        switch leftovers {
        case .notNeeded:
            return "notNeeded"
        case .noLeftovers:
            return "noLeftovers"
        case .unverified:
            return "unverified"
        case .incomplete(let items):
            guard !items.isEmpty else { return "incomplete" }
            let descriptions = items.map { item in
                "\(item.kind.rawValue) \(item.location) (\(humanBase(item.base)))"
            }
            return "incomplete [\(descriptions.joined(separator: "; "))]"
        }
    }

    private static func humanBase(_ base: WorktreeLeftoverBase) -> String {
        switch base {
        case .destination:
            "destination"
        case .repositoryGitDirectory:
            "repository Git directory"
        case .branchReference:
            "branch reference"
        case .temporary:
            "temporary"
        }
    }

    private static func refusalDetails(for refusal: WorktreeOperationRefusal) -> RefusalDetails {
        switch refusal {
        case .notInRepository(let path):
            RefusalDetails(reason: "notInRepository", path: absolutePath(path), detail: nil)
        case .notInWorktree(let path):
            RefusalDetails(reason: "notInWorktree", path: absolutePath(path), detail: nil)
        case .noDefaultBranch:
            RefusalDetails(reason: "noDefaultBranch", path: nil, detail: nil)
        case .invalidBranchName(.local(let rejection)):
            RefusalDetails(reason: "invalidBranchName", path: nil, detail: branchRejectionDetail(rejection))
        case .invalidBranchName(.rejectedByGit):
            RefusalDetails(reason: "invalidBranchName", path: nil, detail: "Git rejected the branch name")
        case .emptyBranchSlug:
            RefusalDetails(reason: "emptyBranchSlug", path: nil, detail: nil)
        case .branchAlreadyExists(let branch):
            RefusalDetails(reason: "branchAlreadyExists", path: nil, detail: branch)
        case .destinationExists(let path):
            RefusalDetails(reason: "destinationExists", path: absolutePath(path), detail: nil)
        case .destinationParentMissing(let path):
            RefusalDetails(reason: "destinationParentMissing", path: absolutePath(path), detail: nil)
        case .unsupportedRepositoryLayout(let path):
            RefusalDetails(reason: "unsupportedRepositoryLayout", path: absolutePath(path), detail: nil)
        case .forkUnavailable(let reason):
            RefusalDetails(reason: "forkUnavailable", path: nil, detail: reason.rawValue)
        }
    }

    private static func branchRejectionDetail(_ rejection: WorktreeBranchNameRejection) -> String {
        switch rejection {
        case .empty:
            "branch name is empty"
        case .tooLong(let maximumLength):
            "maximum length is \(maximumLength) characters"
        case .containsWhitespaceOrControlCharacter:
            "contains whitespace or a control character"
        case .containsForbiddenCharacter(let character):
            "contains forbidden character \(character)"
        case .containsForbiddenSequence(let sequence):
            "contains forbidden sequence \(sequence)"
        case .invalidComponentBoundary:
            "has an invalid component boundary"
        }
    }

    fileprivate static func jsonRefusal(for refusal: WorktreeOperationRefusal) -> WorktreeCommandLineJSON.Refusal {
        let details = refusalDetails(for: refusal)
        return WorktreeCommandLineJSON.Refusal(reason: details.reason, path: details.path, detail: details.detail)
    }

    fileprivate static func jsonFailure(_ failure: WorktreeFailureKind) -> WorktreeCommandLineJSON.Failure {
        switch failure {
        case .readFailed(let gitErrorKind):
            .init(kind: "readFailed", gitErrorKind: gitErrorKind.rawValue)
        case .createFailed(let gitErrorKind):
            .init(kind: "createFailed", gitErrorKind: gitErrorKind.rawValue)
        case .forkGitFailed(let gitErrorKind):
            .init(kind: "forkGitFailed", gitErrorKind: gitErrorKind.rawValue)
        case .sourceChanged(let relativePath, let reason):
            .init(kind: "sourceChanged", relativePath: relativePath, reason: reason.rawValue)
        case .entryFailed(let relativePath, let reason, let errorNumber):
            .init(kind: "entryFailed", relativePath: relativePath, reason: reason.rawValue, errno: errorNumber)
        case .validationFailed(let reason, let relativePath):
            .init(kind: "validationFailed", relativePath: relativePath, reason: reason.rawValue)
        case .cancelled:
            .init(kind: "cancelled")
        case .rejectedAfterChange(let reason):
            .init(kind: "rejectedAfterChange", reason: reason.rawValue)
        }
    }

    fileprivate static func jsonLeftovers(_ leftovers: WorktreeLeftoverStatus) -> WorktreeCommandLineJSON.Leftovers {
        switch leftovers {
        case .notNeeded:
            .init(status: "notNeeded", items: nil)
        case .noLeftovers:
            .init(status: "noLeftovers", items: nil)
        case .unverified:
            .init(status: "unverified", items: nil)
        case .incomplete(let items):
            .init(
                status: "incomplete",
                items: items.map {
                    .init(kind: $0.kind.rawValue, location: $0.location, base: jsonBase($0.base))
                }
            )
        }
    }

    private static func jsonBase(_ base: WorktreeLeftoverBase) -> String {
        switch base {
        case .destination:
            "destination"
        case .repositoryGitDirectory:
            "repositoryGitDirectory"
        case .branchReference:
            "branchReference"
        case .temporary:
            "temporary"
        }
    }

    private static func absolutePath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private struct RefusalDetails {
        let reason: String
        let path: String?
        let detail: String?
    }
}

private enum WorktreeCommandLineFormattingError: Error {
    case invalidUTF8
}

private struct WorktreeCommandLineJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case outcome
        case operation
        case branch
        case path
        case repository
        case materialization
        case worktrees
        case reason
        case detail
        case failure
        case leftovers
    }

    struct Refusal: Encodable {
        let reason: String
        let path: String?
        let detail: String?
    }

    struct Failure: Encodable {
        let kind: String
        let gitErrorKind: String?
        let relativePath: String?
        let reason: String?
        let errno: Int32?

        init(
            kind: String,
            gitErrorKind: String? = nil,
            relativePath: String? = nil,
            reason: String? = nil,
            errno: Int32? = nil
        ) {
            self.kind = kind
            self.gitErrorKind = gitErrorKind
            self.relativePath = relativePath
            self.reason = reason
            self.errno = errno
        }
    }

    struct Worktree: Encodable {
        let path: String
        let branch: String?
        let isMain: Bool
    }

    struct Leftovers: Encodable {
        let status: String
        let items: [Leftover]?
    }

    struct Leftover: Encodable {
        let kind: String
        let location: String
        let base: String
    }

    private enum EncodedOutcome {
        case created(WorktreeCreatedSummary)
        case listed(WorktreeListingSummary)
        case refused(Refusal)
        case failed(Failure, Leftovers)
    }

    private let encodedOutcome: EncodedOutcome

    init(outcome: WorktreeOperationOutcome) {
        switch outcome {
        case .created(let summary):
            encodedOutcome = .created(summary)
        case .listed(let summary):
            encodedOutcome = .listed(summary)
        case .refused(let refusal):
            encodedOutcome = .refused(WorktreeCommandLineFormatter.jsonRefusal(for: refusal))
        case .failed(let failure):
            encodedOutcome = .failed(
                WorktreeCommandLineFormatter.jsonFailure(failure.failure),
                WorktreeCommandLineFormatter.jsonLeftovers(failure.leftovers)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch encodedOutcome {
        case .created(let summary):
            try container.encode("created", forKey: .outcome)
            try container.encode(summary.operation.rawValue, forKey: .operation)
            try container.encode(summary.branch, forKey: .branch)
            try container.encode(summary.path.standardizedFileURL.path, forKey: .path)
            try container.encode(summary.repository.standardizedFileURL.path, forKey: .repository)
            try container.encodeIfPresent(summary.materialization, forKey: .materialization)
        case .listed(let summary):
            try container.encode("listed", forKey: .outcome)
            try container.encode(summary.repository.standardizedFileURL.path, forKey: .repository)
            let worktrees = summary.worktrees.map { worktree in
                Self.Worktree(
                    path: worktree.path.standardizedFileURL.path,
                    branch: worktree.branch,
                    isMain: worktree.isMain
                )
            }
            try container.encode(worktrees, forKey: .worktrees)
        case .refused(let refusal):
            try container.encode("refused", forKey: .outcome)
            try container.encode(refusal.reason, forKey: .reason)
            try container.encodeIfPresent(refusal.path, forKey: .path)
            try container.encodeIfPresent(refusal.detail, forKey: .detail)
        case .failed(let failure, let leftovers):
            try container.encode("failed", forKey: .outcome)
            try container.encode(failure, forKey: .failure)
            try container.encode(leftovers, forKey: .leftovers)
        }
    }
}
