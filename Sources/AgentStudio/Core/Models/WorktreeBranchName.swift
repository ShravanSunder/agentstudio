import AgentStudioInfrastructure
import Foundation

/// Why typed text cannot name a new worktree branch. Mirrors the subset of
/// `git check-ref-format --branch` a user can reach by typing.
package enum WorktreeBranchNameRejection: Error, Equatable, Sendable {
    case empty
    case tooLong(maximumLength: Int)
    case containsWhitespaceOrControlCharacter
    case containsForbiddenCharacter(Character)
    case containsForbiddenSequence(String)
    case invalidComponentBoundary
}

/// A validated name for a branch the app is about to create. Empty is not a name.
package struct WorktreeBranchName: Equatable, Hashable, Sendable {
    package let rawValue: String

    private static let forbiddenCharacters: Set<Character> = ["~", "^", ":", "?", "*", "[", "\\"]
    private static let forbiddenSequences = ["..", "@{", "//"]

    package static func validated(_ text: String) -> Result<Self, WorktreeBranchNameRejection> {
        guard !text.isEmpty else { return .failure(.empty) }
        let maximumLength = AppPolicies.WorktreeCreation.maximumBranchNameLength
        guard text.count <= maximumLength else { return .failure(.tooLong(maximumLength: maximumLength)) }
        let hasWhitespaceOrControl = text.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }
        guard !hasWhitespaceOrControl else { return .failure(.containsWhitespaceOrControlCharacter) }
        if let forbidden = text.first(where: forbiddenCharacters.contains) {
            return .failure(.containsForbiddenCharacter(forbidden))
        }
        if let sequence = forbiddenSequences.first(where: text.contains) {
            return .failure(.containsForbiddenSequence(sequence))
        }
        guard text != "@", !text.hasPrefix("-") else { return .failure(.invalidComponentBoundary) }
        let components = text.split(separator: "/", omittingEmptySubsequences: false)
        let hasInvalidComponent = components.contains { component in
            component.isEmpty || component.hasPrefix(".") || component.hasSuffix(".")
                || component.hasSuffix(".lock")
        }
        guard !hasInvalidComponent else { return .failure(.invalidComponentBoundary) }
        return .success(Self(rawValue: text))
    }

    private init(rawValue: String) {
        self.rawValue = rawValue
    }
}
