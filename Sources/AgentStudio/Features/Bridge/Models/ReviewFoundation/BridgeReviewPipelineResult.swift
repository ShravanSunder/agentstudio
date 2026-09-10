import AgentStudioGit
import Foundation

struct BridgeReviewPipelineResult: Sendable {
    let package: BridgeReviewPackage
    let registeredContentHandles: [BridgeContentHandle]
    let gitRefreshSeed: GitReviewRefreshSeed?

    init(
        package: BridgeReviewPackage,
        registeredContentHandles: [BridgeContentHandle],
        gitRefreshSeed: GitReviewRefreshSeed? = nil
    ) {
        self.package = package
        self.registeredContentHandles = registeredContentHandles
        self.gitRefreshSeed = gitRefreshSeed
    }
}
