import AgentStudioInfrastructure
import AppKit
import Foundation

@testable import AgentStudioRepoExplorer

@MainActor
final class RepoExplorerAcceptingMaterializationChild: RepoExplorerMaterializationContentChild {
    let view = NSView()

    func apply(
        _ candidate: RepoExplorerMaterializationContentCandidate,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        _ = candidate
        completion(.accepted)
    }

    func prepareForRemoval(
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        _ = visibleGeneration
        completion(.accepted)
    }

    func suspendDemand() {}
    func resumeDemand(visibleGeneration: UInt64) { _ = visibleGeneration }
    func detach() {}
}

@MainActor
func registerProjectionTestMaterializationHost(
    adapter: RepoExplorerProjectionAdapter
) -> RepoExplorerMaterializationHost {
    let host = RepoExplorerMaterializationHost(
        lifetimeID: RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate()),
        initialDemandEpoch: adapter.materializationDemandEpoch,
        initialPresentation: .noRepositories,
        makeContentChild: { RepoExplorerAcceptingMaterializationChild() },
        onFeedback: adapter.receiveMaterializationFeedback
    )
    precondition(adapter.registerMaterializationHost(host))
    return host
}

@MainActor
func stopProjectionTestMaterializationHost(
    _ host: RepoExplorerMaterializationHost,
    adapter: RepoExplorerProjectionAdapter
) {
    host.detach()
    adapter.stop()
}
