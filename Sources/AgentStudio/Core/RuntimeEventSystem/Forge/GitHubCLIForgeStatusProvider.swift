import AgentStudioInfrastructure
import Foundation

package protocol ForgeStatusProvider: Sendable {
    func pullRequests(origin: String) async -> ForgePullRequestQueryOutcome
}

package struct ForgePullRequest: Equatable, Sendable {
    package let headRefName: String
    package let url: URL

    package init(headRefName: String, url: URL) {
        self.headRefName = headRefName
        self.url = url
    }
}

package enum ForgePullRequestQueryOutcome: Equatable, Sendable {
    case complete([ForgePullRequest])
    case truncated
    case rateLimited(retryAfterSeconds: Int?)
    case failed(message: String)
}

package struct GitHubCLIForgeStatusProvider: ForgeStatusProvider {
    private struct PullRequestRow: Decodable {
        let headRefName: String
        let url: URL
    }

    private let processExecutor: any ProcessExecutor

    package init(processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 8)) {
        self.processExecutor = processExecutor
    }

    package func pullRequests(origin: String) async -> ForgePullRequestQueryOutcome {
        guard let repoSlug = RemoteIdentityNormalizer.extractSlug(origin) else {
            return .failed(message: "Unsupported GitHub remote")
        }

        let result: ProcessResult
        do {
            result = try await processExecutor.execute(
                command: "gh",
                args: [
                    "pr", "list",
                    "--repo", repoSlug,
                    "--state", "open",
                    "--json", "headRefName,url",
                    "--limit", String(AppPolicies.Forge.pullRequestResultLimit),
                ],
                cwd: nil,
                environment: nil
            )
        } catch {
            return .failed(message: String(describing: error))
        }

        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            if Self.isRateLimited(message) {
                return .rateLimited(retryAfterSeconds: Self.retryAfterSeconds(in: message))
            }
            return .failed(message: message)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            return .failed(message: "gh output is not valid UTF-8")
        }

        do {
            let rows = try JSONDecoder().decode([PullRequestRow].self, from: data)
            guard rows.count < AppPolicies.Forge.pullRequestResultLimit else {
                return .truncated
            }
            return .complete(
                rows.map { ForgePullRequest(headRefName: $0.headRefName, url: $0.url) }
            )
        } catch {
            return .failed(message: "Invalid gh pull request response: \(error)")
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
