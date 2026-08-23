import AgentStudioInfrastructure
import Observation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class RepoExplorerProjectionConditionWaiter {
    private let condition: @MainActor () -> Bool
    private var continuation: CheckedContinuation<Bool, Never>?

    init(condition: @escaping @MainActor () -> Bool) {
        self.condition = condition
    }

    func wait() async -> Bool {
        if condition() { return true }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            observeCondition()
        }
    }

    private func observeCondition() {
        guard continuation != nil else { return }
        if condition() {
            continuation?.resume(returning: true)
            continuation = nil
            return
        }
        withObservationTracking {
            _ = condition()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeCondition()
            }
        }
    }
}

extension RepoExplorerProjectionWorkerTests {
    @Test("scoped delta after equal suppression matches the latest full reference")
    @MainActor
    func scopedDeltaAfterEqualSuppressionMatchesLatestReference() async throws {
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let initialRepo = repo(id: repoId, worktreeId: worktreeId, name: "zeta")
        let secondaryRepoId = UUIDv7.generate()
        let secondaryWorktreeId = UUIDv7.generate()
        let initialSecondaryRepo = repo(
            id: secondaryRepoId,
            worktreeId: secondaryWorktreeId,
            name: "alpha"
        )
        let metadataSecondaryRepo = repo(
            id: secondaryRepoId,
            worktreeId: secondaryWorktreeId,
            name: "alpha",
            note: "metadata-only change"
        )
        let initialRequest = request(
            repos: [initialRepo, initialSecondaryRepo],
            generation: 1,
            resolvesRemotes: false
        )
        let metadataRequest = request(
            repos: [initialRepo, metadataSecondaryRepo],
            generation: 2,
            resolvesRemotes: false
        )
        let favoriteRequest = request(
            repos: [withFavorite(initialRepo), metadataSecondaryRepo],
            generation: 3,
            resolvesRemotes: false
        )
        let favoriteRemovalRequest = request(
            repos: [initialRepo, metadataSecondaryRepo],
            generation: 4,
            resolvesRemotes: false
        )
        let adapter = RepoExplorerProjectionAdapter()
        defer { adapter.stop() }
        let host = registerProjectionTestMaterializationHost(adapter: adapter)
        defer { host.detach() }

        adapter.admit(initialRequest)
        let initialResult = try await publishedResult(generation: 1, from: adapter)

        adapter.admit(metadataRequest)
        let equalCandidateSettled = await RepoExplorerProjectionConditionWaiter {
            adapter.materializedProjection?.freshness == .current(2)
        }.wait()
        #expect(equalCandidateSettled)
        #expect(adapter.publishedResult == initialResult)
        #expect(favoriteRequest.scopedChange(from: metadataRequest) == .repo(repoId))

        adapter.admitDelta(
            [.repo(repoId)],
            request: favoriteRequest
        )
        let scopedResult = try await publishedResult(generation: 3, from: adapter)
        let referenceResult = try RepoExplorerProjectionWorker.project(favoriteRequest)

        #expect(scopedResult.projection == referenceResult.projection)
        #expect(scopedResult.rowIndex == referenceResult.rowIndex)

        #expect(favoriteRemovalRequest.scopedChange(from: favoriteRequest) == .repo(repoId))
        adapter.admitDelta(
            [.repo(repoId)],
            request: favoriteRemovalRequest
        )
        let removalResult = try await publishedResult(generation: 4, from: adapter)
        let removalReference = try RepoExplorerProjectionWorker.project(favoriteRemovalRequest)

        #expect(removalResult.projection == removalReference.projection)
        #expect(removalResult.rowIndex == removalReference.rowIndex)
    }
}
