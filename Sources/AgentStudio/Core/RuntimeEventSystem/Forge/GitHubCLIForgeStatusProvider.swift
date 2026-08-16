import AgentStudioInfrastructure
import Foundation

package protocol ForgeStatusProvider: Sendable {
    func pullRequests(origin: String) async -> ForgePullRequestQueryOutcome
}

package struct ForgePullRequest: Equatable, Sendable {
    package let headRefName: String
    package let url: URL
    package let readiness: PullRequestReadiness?

    package init(
        headRefName: String,
        url: URL,
        readiness: PullRequestReadiness? = nil
    ) {
        self.headRefName = headRefName
        self.url = url
        self.readiness = readiness
    }
}

package enum ForgePullRequestQueryOutcome: Equatable, Sendable {
    case complete([ForgePullRequest])
    case truncated
    case rateLimited(retryAfterSeconds: Int?)
    case failed(message: String)
}

package struct GitHubCLIForgeStatusProvider: ForgeStatusProvider {
    private struct GraphQLResponse: Decodable {
        let data: ResponseData

        struct ResponseData: Decodable {
            let repository: Repository?
        }

        struct Repository: Decodable {
            let pullRequests: PullRequestConnection
        }

        struct PullRequestConnection: Decodable {
            let nodes: [PullRequestRow]
            let pageInfo: PageInfo
        }

        struct PageInfo: Decodable {
            let hasNextPage: Bool
            let endCursor: String?
        }
    }

    private struct PullRequestRow: Decodable {
        let headRefName: String
        let url: URL
        let isDraft: Bool?
        let reviewDecision: String?
        let mergeable: String?
        let mergeStateStatus: String?
        let statusCheckRollup: StatusCheckRollup?

        struct StatusCheckRollup: Decodable {
            let state: String
        }
    }

    private static let graphQLPageSize = 100
    private static let maximumPageCount =
        (AppPolicies.Forge.pullRequestResultLimit + graphQLPageSize - 1) / graphQLPageSize
    private static let graphQLQuery = """
        query($owner: String!, $name: String!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequests(first: \(graphQLPageSize), after: $after, states: OPEN) {
              nodes {
                headRefName
                url
                isDraft
                reviewDecision
                mergeable
                mergeStateStatus
                statusCheckRollup { state }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
        """

    private let processExecutor: any ProcessExecutor

    private enum FetchPageOutcome {
        case success(GraphQLResponse.PullRequestConnection)
        case failure(ForgePullRequestQueryOutcome)
    }

    package init(processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 8)) {
        self.processExecutor = processExecutor
    }

    package func pullRequests(origin: String) async -> ForgePullRequestQueryOutcome {
        guard let repoSlug = RemoteIdentityNormalizer.extractSlug(origin) else {
            return .failed(message: "Unsupported GitHub remote")
        }
        let slugParts = repoSlug.split(separator: "/", maxSplits: 1).map(String.init)
        guard slugParts.count == 2 else {
            return .failed(message: "Unsupported GitHub repository slug")
        }

        var pullRequests: [ForgePullRequest] = []
        var afterCursor: String?
        for pageIndex in 0..<Self.maximumPageCount {
            let pageOutcome = await fetchPage(
                owner: slugParts[0],
                name: slugParts[1],
                afterCursor: afterCursor
            )
            switch pageOutcome {
            case .success(let connection):
                pullRequests.append(contentsOf: connection.nodes.map(Self.makePullRequest))
                guard pullRequests.count < AppPolicies.Forge.pullRequestResultLimit else {
                    return .truncated
                }
                guard connection.pageInfo.hasNextPage else {
                    return .complete(pullRequests)
                }
                guard pageIndex + 1 < Self.maximumPageCount else {
                    return .truncated
                }
                guard let endCursor = connection.pageInfo.endCursor else {
                    return .failed(message: "GitHub pull request page omitted its end cursor")
                }
                afterCursor = endCursor
            case .failure(let outcome):
                return outcome
            }
        }
        return .truncated
    }

    private func fetchPage(
        owner: String,
        name: String,
        afterCursor: String?
    ) async -> FetchPageOutcome {
        var arguments = [
            "api", "graphql",
            "-f", "query=\(Self.graphQLQuery)",
            "-F", "owner=\(owner)",
            "-F", "name=\(name)",
        ]
        if let afterCursor {
            arguments.append(contentsOf: ["-F", "after=\(afterCursor)"])
        }

        let result: ProcessResult
        do {
            result = try await processExecutor.execute(
                command: "gh",
                args: arguments,
                cwd: nil,
                environment: nil
            )
        } catch {
            return .failure(.failed(message: String(describing: error)))
        }

        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            if Self.isRateLimited(message) {
                return .failure(
                    .rateLimited(retryAfterSeconds: Self.retryAfterSeconds(in: message))
                )
            }
            return .failure(.failed(message: message))
        }
        guard let data = result.stdout.data(using: .utf8) else {
            return .failure(.failed(message: "gh output is not valid UTF-8"))
        }

        do {
            let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
            guard let repository = response.data.repository else {
                return .failure(.failed(message: "GitHub repository was not found"))
            }
            return .success(repository.pullRequests)
        } catch {
            return .failure(.failed(message: "Invalid gh pull request response: \(error)"))
        }
    }

    private static func makePullRequest(_ row: PullRequestRow) -> ForgePullRequest {
        ForgePullRequest(
            headRefName: row.headRefName,
            url: row.url,
            readiness: PullRequestReadiness(
                isDraft: row.isDraft ?? false,
                checkStatus: checkStatus(row.statusCheckRollup?.state),
                reviewStatus: reviewStatus(row.reviewDecision),
                mergeability: mergeability(row.mergeable),
                mergeState: mergeState(row.mergeStateStatus)
            )
        )
    }

    private static func checkStatus(_ rawValue: String?) -> PullRequestCheckStatus {
        switch rawValue {
        case "SUCCESS": .passed
        case "EXPECTED", "PENDING": .running
        case "ERROR", "FAILURE": .failed
        default: .unknown
        }
    }

    private static func reviewStatus(_ rawValue: String?) -> PullRequestReviewStatus {
        switch rawValue {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: .unknown
        }
    }

    private static func mergeability(_ rawValue: String?) -> PullRequestMergeability {
        switch rawValue {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
        }
    }

    private static func mergeState(_ rawValue: String?) -> PullRequestMergeState {
        switch rawValue {
        case "CLEAN": .clean
        case "BLOCKED": .blocked
        case "BEHIND": .behind
        case "DIRTY": .dirty
        case "DRAFT": .draft
        case "HAS_HOOKS": .hasHooks
        case "UNSTABLE": .unstable
        default: .unknown
        }
    }

    private static func isRateLimited(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("rate limit")
    }

    private static func retryAfterSeconds(in message: String) -> Int? {
        let lowercaseMessage = message.lowercased()
        guard let markerRange = lowercaseMessage.range(of: "retry-after:") else { return nil }
        let suffix = lowercaseMessage[markerRange.upperBound...].drop { $0.isWhitespace }
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}
