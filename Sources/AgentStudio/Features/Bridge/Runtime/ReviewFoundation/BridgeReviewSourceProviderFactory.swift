import Foundation

enum BridgeReviewSourceProviderFactory {
    static func gitProvider(repositoryPath: URL?) -> any BridgeReviewSourceProvider {
        guard let repositoryPath else {
            return BridgeUnavailableReviewSourceProvider()
        }
        let dataClient = AgentStudioGitBridgeReviewDataClient(repositoryPath: repositoryPath)
        return BridgeGitReviewSourceProvider(client: dataClient)
    }
}
