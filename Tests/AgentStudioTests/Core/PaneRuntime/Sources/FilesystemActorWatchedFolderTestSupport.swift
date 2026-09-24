import AgentStudioInfrastructure
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
    private var groupsByRoot: [URL: [RepoScanner.RepoScanGroup]] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .system(let systemEnvelope) = envelope,
            case .topology(let topologyEvent) = systemEnvelope.event
        else { return }
        switch topologyEvent {
        case .watchedFolderReconciled(let observation):
            let previous = groupsByRoot[observation.root] ?? []
            var groups = RepoScanner.groupResolvedEntries(observation.entries)
            if case .additive = observation.coverage {
                var merged = Dictionary(uniqueKeysWithValues: previous.map { ($0.clonePath, $0) })
                for group in groups {
                    let retained = merged[group.clonePath]?.linkedWorktreePaths ?? []
                    merged[group.clonePath] = .init(
                        clonePath: group.clonePath,
                        linkedWorktreePaths: Array(Set(retained + group.linkedWorktreePaths)).sorted {
                            $0.path < $1.path
                        }
                    )
                }
                groups = merged.values.sorted { $0.clonePath.path < $1.clonePath.path }
            }
            groupsByRoot[observation.root] = groups
            for group in groups where !previous.contains(group) {
                events.discovered.append(
                    RepoDiscoveryEvent(
                        repoPath: group.clonePath,
                        linkedWorktrees: .scanned(group.linkedWorktreePaths)
                    ))
            }
            for group in previous where !groups.contains(where: { $0.clonePath == group.clonePath }) {
                if !groupsByRoot.values.joined().contains(where: { $0.clonePath == group.clonePath }) {
                    events.removed.insert(group.clonePath)
                }
            }
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

/// Holds one armed submission's accepted result back from the FilesystemActor until opened,
/// so actor work can be ordered between a scan starting and its acceptance returning.
actor WatchedFolderScanAcceptanceGate {
    private var isArmed = false
    private var isOpen = false
    private var parkedSubmission: CheckedContinuation<Void, Never>?

    nonisolated var port: WatchedFolderScanSubmissionPort {
        WatchedFolderScanSubmissionPort { scheduler, request, intent in
            let result = await scheduler.submit(request, intent: intent)
            await self.holdIfArmed()
            return result
        }
    }

    func arm() {
        isArmed = true
        isOpen = false
    }

    func open() {
        isOpen = true
        parkedSubmission?.resume()
        parkedSubmission = nil
    }

    private func holdIfArmed() async {
        guard isArmed else { return }
        isArmed = false
        guard !isOpen else { return }
        await withCheckedContinuation { parkedSubmission = $0 }
    }
}
