import Foundation

@testable import AgentStudio

struct ProductFileSourceStatusProvider: GitWorkingTreeStatusProvider {
    func statusResult(
        for _: URL,
        pathspecs _: [String]?
    ) async -> GitWorkingTreeStatusResult {
        .available(
            GitWorkingTreeStatus(
                summary: .init(changed: 1, staged: 2, untracked: 3),
                branch: "main",
                origin: nil
            )
        )
    }
}

enum ProductFileSourceFixtureError: Error {
    case invalidContentRequest
    case invalidControlRequest
    case invalidDemandedIndex
    case missingSubscription
}
