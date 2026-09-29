import AgentStudioGit
import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioCore

final class RootPathProbeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let missingRootPaths: Set<URL>
    private var rootPaths: [URL] = []

    init(missingRootPaths: Set<URL> = []) {
        self.missingRootPaths = missingRootPaths
    }

    var recordedRootPaths: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return rootPaths
    }

    func recordExistence(_ rootPath: URL) -> Bool {
        lock.lock()
        rootPaths.append(rootPath)
        lock.unlock()
        return !missingRootPaths.contains(rootPath)
    }
}

actor StatusCallRecorder {
    private(set) var rootPaths: [URL] = []
    private var callCountWaiter:
        (
            minimumCallCount: Int,
            continuation: CheckedContinuation<[URL], Never>
        )?

    func record(_ rootPath: URL) {
        rootPaths.append(rootPath)
        guard let callCountWaiter, rootPaths.count >= callCountWaiter.minimumCallCount else {
            return
        }
        self.callCountWaiter = nil
        callCountWaiter.continuation.resume(returning: rootPaths)
    }

    func waitForCallCount(_ minimumCallCount: Int) async -> [URL] {
        guard rootPaths.count < minimumCallCount else { return rootPaths }
        return await withCheckedContinuation { continuation in
            precondition(callCountWaiter == nil)
            callCountWaiter = (minimumCallCount, continuation)
        }
    }
}

func expectCapacityRetryScheduled(
    facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
    actor: GitWorkingDirectoryProjector,
    worktreeId: UUID
) async throws {
    try await facts.expectNext(
        in: .capacity(worktreeId: worktreeId, episode: 1), .capacityRetryScheduled
    )
    #expect(await actor.capacityRetryWorktreeIds == Set([worktreeId]))
}

func expectRetainedRequiredFullRefresh(
    actor: GitWorkingDirectoryProjector,
    worktreeId: UUID
) async {
    #expect(await actor.pendingByWorktreeId[worktreeId]?.paths.isEmpty == true)
    #expect(await actor.pendingByWorktreeId[worktreeId]?.containsGitInternalChanges == true)
    #expect(await actor.hasRequiredIntent(worktreeId: worktreeId))
}

func setAdmissionAutomaticAttention(
    actor: GitWorkingDirectoryProjector,
    warmWorktreeIds: Set<UUID>,
    backgroundOnlyWorktreeIds: Set<UUID>
) async {
    await actor.setRepositoryFactAttention(
        activePaneWorktreeId: nil,
        sidebarAttendedWorktreeIds: [],
        visibleActiveTabWorktreeIds: [],
        openWorktreeIds: [],
        warmAutomaticWorktreeIds: warmWorktreeIds,
        backgroundOnlyAutomaticWorktreeIds: backgroundOnlyWorktreeIds
    )
}

func admissionRegistrationEnvelope(
    seq: UInt64,
    timestamp: ContinuousClock.Instant,
    worktreeId: UUID,
    rootPath: URL
) -> RuntimeEnvelope {
    .system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: seq,
            timestamp: timestamp,
            event: .topology(
                .worktreeRegistered(
                    worktreeId: worktreeId,
                    repoId: worktreeId,
                    rootPath: rootPath
                )
            )
        )
    )
}

func admissionTopologyAssertion(
    generation: UInt64,
    rootPathsByWorktreeId: [UUID: URL]
) -> FilesystemTopologyAssertion {
    FilesystemTopologyAssertion(
        generation: generation,
        contextsByWorktreeId: Dictionary(
            uniqueKeysWithValues: rootPathsByWorktreeId.map { worktreeId, rootPath in
                (
                    worktreeId,
                    WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                )
            }
        )
    )
}

func admissionFilesystemChangeset(
    worktreeId: UUID,
    rootPath: URL,
    batchSeq: UInt64
) -> FileChangeset {
    FileChangeset(
        worktreeId: worktreeId,
        rootPath: rootPath,
        paths: ["tracked-\(batchSeq).txt"],
        timestamp: ContinuousClock().now,
        batchSeq: batchSeq
    )
}

func admissionCompleteStatusSnapshot() -> AgentStudioGit.GitCompleteStatusSnapshot {
    let rootPath = URL(fileURLWithPath: "/tmp/admission-status-snapshot")
    return AgentStudioGit.GitCompleteStatusSnapshot(
        facts: AgentStudioGit.GitStatusFactsSnapshot(
            repositoryRoot: rootPath,
            worktreePath: rootPath,
            generatedAtUnixMilliseconds: 1,
            head: AgentStudioGit.GitHeadSnapshot(kind: .branch, oid: "abc123", shortName: "main"),
            originResolution: .confirmedAbsent,
            summary: AgentStudioGit.GitStatusFactSummary(
                changedFileCount: 0,
                stagedFileCount: 0,
                unstagedFileCount: 0,
                untrackedFileCount: 0,
                ignoredFileCount: 0,
                aheadCount: 0,
                behindCount: 0,
                hasUpstream: false
            ),
            entries: []
        ),
        lineCountDetail: AgentStudioGit.GitStatusLineCountDetail(
            repositoryRoot: rootPath,
            worktreePath: rootPath,
            generatedAtUnixMilliseconds: 1,
            linesAdded: 0,
            linesDeleted: 0
        )
    )
}
