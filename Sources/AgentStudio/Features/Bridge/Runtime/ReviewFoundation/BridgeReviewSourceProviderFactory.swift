import AgentStudioCore
import AgentStudioGit
import Foundation

package enum BridgeReviewRepositoryLocation: Equatable, Sendable {
    case workspaceSource(URL)
    case launchDirectory(URL)
    case currentWorkingDirectory(URL)
    case unavailable

    package var repositoryURL: URL? {
        switch self {
        case .workspaceSource(let repositoryURL),
            .launchDirectory(let repositoryURL),
            .currentWorkingDirectory(let repositoryURL):
            repositoryURL
        case .unavailable:
            nil
        }
    }
}

package enum BridgeReviewSourceProviderFactory {
    package static func repositoryLocation(
        reviewRootPath: String?,
        launchDirectory: URL?,
        currentWorkingDirectory: URL?
    ) -> BridgeReviewRepositoryLocation {
        if let reviewRootPath {
            return .workspaceSource(URL(fileURLWithPath: reviewRootPath))
        }
        if let launchDirectory {
            return .launchDirectory(launchDirectory)
        }
        if let currentWorkingDirectory {
            return .currentWorkingDirectory(currentWorkingDirectory)
        }
        return .unavailable
    }

    package static func gitProvider(
        repositoryPath: URL?,
        gitReadContext: BridgeGitReadContext?,
        statusPhysicalGate: AgentStudioGitStatusPhysicalGate
    ) -> any BridgeReviewSourceProvider {
        guard let repositoryPath, let gitReadContext else {
            return BridgeUnavailableReviewSourceProvider()
        }
        return makeGitProvider(
            repositoryPath: repositoryPath,
            gitReadContext: gitReadContext,
            statusPhysicalGate: statusPhysicalGate
        )
    }

    package static func gitProvider(
        location: BridgeReviewRepositoryLocation,
        gitReadContext: BridgeGitReadContext?,
        statusPhysicalGate: AgentStudioGitStatusPhysicalGate
    ) -> any BridgeReviewSourceProvider {
        guard let repositoryURL = location.repositoryURL, let gitReadContext else {
            return BridgeUnavailableReviewSourceProvider()
        }
        return makeGitProvider(
            repositoryPath: repositoryURL,
            gitReadContext: gitReadContext,
            statusPhysicalGate: statusPhysicalGate
        )
    }

    private static func makeGitProvider(
        repositoryPath: URL,
        gitReadContext: BridgeGitReadContext,
        statusPhysicalGate: AgentStudioGitStatusPhysicalGate
    ) -> any BridgeReviewSourceProvider {
        let dataClient = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            gitReadContext: gitReadContext,
            statusPhysicalGate: statusPhysicalGate
        )
        return BridgeGitReviewSourceProvider(client: dataClient)
    }
}
