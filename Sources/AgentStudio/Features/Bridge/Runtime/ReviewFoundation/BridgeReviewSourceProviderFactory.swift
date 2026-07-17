import Foundation

enum BridgeReviewSourceProviderFactory {
    static func gitProvider(
        repositoryPath: URL?,
        gitReadContext: BridgeGitReadContext?
    ) -> any BridgeReviewSourceProvider {
        guard let repositoryPath, let gitReadContext else {
            return BridgeUnavailableReviewSourceProvider()
        }
        let dataClient = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            gitReadContext: gitReadContext
        )
        return BridgeGitReviewSourceProvider(client: dataClient)
    }
}
