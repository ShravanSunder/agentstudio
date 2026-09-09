import Foundation

@testable import AgentStudioCore

struct RepoDiscoveryEvent: Equatable {
    let repoPath: URL
    let linkedWorktrees: LinkedWorktreeInfo
    let stableIdentity: DiscoveredRepoStableIdentity

    init(
        repoPath: URL,
        linkedWorktrees: LinkedWorktreeInfo,
        stableIdentity: DiscoveredRepoStableIdentity? = nil
    ) {
        self.repoPath = repoPath
        self.linkedWorktrees = linkedWorktrees
        self.stableIdentity =
            stableIdentity
            ?? .prepare(repoPath: repoPath, linkedWorktrees: linkedWorktrees)
    }
}

struct TopologyEventSet: Equatable {
    var discovered: [RepoDiscoveryEvent] = []
    var removed: Set<URL> = []
}

actor TopologyEventRecorder {
    private var events = TopologyEventSet()

    func record(_ envelope: RuntimeEnvelope) {
        guard case .system(let systemEnvelope) = envelope,
            case .topology(let topologyEvent) = systemEnvelope.event
        else { return }
        switch topologyEvent {
        case .repoDiscovered(let repoPath, _, let linkedWorktrees, let stableIdentity):
            events.discovered.append(
                RepoDiscoveryEvent(
                    repoPath: repoPath.standardizedFileURL,
                    linkedWorktrees: linkedWorktrees,
                    stableIdentity: stableIdentity
                )
            )
        case .reposDiscovered(_, let repositories):
            events.discovered.append(
                contentsOf: repositories.map {
                    RepoDiscoveryEvent(
                        repoPath: $0.repoPath.standardizedFileURL,
                        linkedWorktrees: $0.linkedWorktrees,
                        stableIdentity: $0.stableIdentity
                    )
                }
            )
        case .repoRemoved(let repoPath):
            events.removed.insert(repoPath.standardizedFileURL)
        case .worktreeRegistered, .worktreeUnregistered:
            break
        }
    }

    func reset() { events = TopologyEventSet() }
    func snapshot() -> TopologyEventSet { events }
}
