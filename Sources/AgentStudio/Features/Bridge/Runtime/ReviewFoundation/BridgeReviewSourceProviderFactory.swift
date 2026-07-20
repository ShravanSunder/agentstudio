import Foundation

enum BridgeReviewRepositoryLocation: Equatable, Sendable {
    case workspaceSource(URL)
    case launchDirectory(URL)
    case currentWorkingDirectory(URL)
    case unavailable
}

enum BridgeReviewSourceProviderFactory {
    static func repositoryLocation(
        source: BridgePaneSource?,
        launchDirectory: URL?,
        currentWorkingDirectory: URL?
    ) -> BridgeReviewRepositoryLocation {
        if case .workspace(let rootPath, _) = source {
            return .workspaceSource(URL(fileURLWithPath: rootPath))
        }
        if let launchDirectory {
            return .launchDirectory(launchDirectory)
        }
        if let currentWorkingDirectory {
            return .currentWorkingDirectory(currentWorkingDirectory)
        }
        return .unavailable
    }

    static func gitProvider(
        repositoryPath: URL?,
        gitReadContext: BridgeGitReadContext?
    ) -> any BridgeReviewSourceProvider {
        guard let repositoryPath, let gitReadContext else {
            return BridgeUnavailableReviewSourceProvider()
        }
        return makeGitProvider(repositoryPath: repositoryPath, gitReadContext: gitReadContext)
    }

    static func gitProvider(
        location: BridgeReviewRepositoryLocation,
        gitReadContext: BridgeGitReadContext?
    ) -> any BridgeReviewSourceProvider {
        let repositoryPath: URL
        switch location {
        case .workspaceSource(let path), .launchDirectory(let path), .currentWorkingDirectory(let path):
            repositoryPath = path
        case .unavailable:
            return BridgeUnavailableReviewSourceProvider()
        }
        guard let gitReadContext else { return BridgeUnavailableReviewSourceProvider() }
        return makeGitProvider(repositoryPath: repositoryPath, gitReadContext: gitReadContext)
    }

    static func gitProvider(location: BridgeReviewRepositoryLocation) -> any BridgeReviewSourceProvider {
        BridgeUnavailableReviewSourceProvider()
    }

    private static func makeGitProvider(
        repositoryPath: URL,
        gitReadContext: BridgeGitReadContext
    ) -> any BridgeReviewSourceProvider {
        let dataClient = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            gitReadContext: gitReadContext
        )
        return BridgeGitReviewSourceProvider(client: dataClient)
    }
}
