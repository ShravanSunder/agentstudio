import AgentStudioCore
import AgentStudioInfrastructure

package enum BridgeReviewCompleteScopeReason: String, Equatable, Sendable {
    case emptyPaths
    case gitInternalChange
    case suppressedIgnoredPath
    case suppressedGitInternalPath
    case statusOnlyChange
    case rootOrOverflowSummary
    case mixedAuthority
    case nonExactInput
}

package enum ReviewGitRefreshScope: Equatable, Sendable {
    case complete(reason: BridgeReviewCompleteScopeReason)
    case exactPaths([String])

    static func classify(
        fileChangeset: FileChangeset?,
        latestFileStatus: GitWorkingTreeStatus?
    ) -> Self {
        guard let fileChangeset else {
            return .complete(
                reason: latestFileStatus == nil ? .nonExactInput : .statusOnlyChange
            )
        }
        guard !fileChangeset.containsGitInternalChanges else {
            return .complete(reason: .gitInternalChange)
        }
        guard fileChangeset.suppressedGitInternalPathCount == 0 else {
            return .complete(reason: .suppressedGitInternalPath)
        }
        guard fileChangeset.suppressedIgnoredPathCount == 0 else {
            return .complete(reason: .suppressedIgnoredPath)
        }
        let paths = Array(Set(fileChangeset.paths)).sorted()
        guard !paths.isEmpty else {
            return .complete(reason: .emptyPaths)
        }
        guard
            paths.count <= AppPolicies.GitRefresh.defaultPolicy.maxScopedStatusPathspecCount,
            paths.allSatisfy({ !$0.isEmpty && $0 != "." })
        else {
            return .complete(reason: .rootOrOverflowSummary)
        }
        return .exactPaths(paths)
    }

    func union(
        _ incoming: Self,
        hasCommonAuthority: Bool
    ) -> Self {
        guard hasCommonAuthority else {
            return .complete(reason: .mixedAuthority)
        }
        switch (self, incoming) {
        case (.complete(let reason), _):
            return .complete(reason: reason)
        case (_, .complete(let reason)):
            return .complete(reason: reason)
        case (.exactPaths(let current), .exactPaths(let next)):
            let paths = Array(Set(current).union(next)).sorted()
            guard paths.count <= AppPolicies.GitRefresh.defaultPolicy.maxScopedStatusPathspecCount else {
                return .complete(reason: .rootOrOverflowSummary)
            }
            return .exactPaths(paths)
        }
    }
}
