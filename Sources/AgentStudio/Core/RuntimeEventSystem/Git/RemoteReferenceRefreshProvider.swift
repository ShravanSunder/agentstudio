import AgentStudioGit
import AgentStudioInfrastructure
import Foundation

package protocol RemoteReferenceRefreshProviding: Sendable {
    func captureRemoteTrackingSnapshot(
        repositoryPath: URL,
        remoteName: String
    ) async throws -> GitRemoteTrackingSnapshot
    func stageFetch(
        snapshot: GitRemoteTrackingSnapshot,
        stagingId: UUID
    ) async throws -> GitStagedFetchResult
    func promoteStagedFetch(_ stagedFetch: GitStagedFetchResult) async throws
    func cleanupStagedFetch(_ handle: GitStagedFetchHandle) async throws
    func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory: URL,
        retainedStagingIds: Set<UUID>
    ) async throws
}

package struct AgentStudioGitRemoteReferenceRefreshProvider: RemoteReferenceRefreshProviding {
    private let client: any AgentStudioGitRemoteClient

    package init(
        client: any AgentStudioGitRemoteClient = SystemGitRemoteClient(
            configuration: .init(
                operationTimeoutSeconds: AppPolicies.RemoteReferenceRefresh.childProcessTimeoutSeconds
            )
        )
    ) {
        self.client = client
    }

    package func captureRemoteTrackingSnapshot(
        repositoryPath: URL,
        remoteName: String
    ) async throws -> GitRemoteTrackingSnapshot {
        try await client.captureRemoteTrackingSnapshot(
            GitRemoteTrackingSnapshotRequest(
                repositoryPath: repositoryPath,
                remoteName: remoteName
            )
        )
    }

    package func stageFetch(
        snapshot: GitRemoteTrackingSnapshot,
        stagingId: UUID
    ) async throws -> GitStagedFetchResult {
        try await client.stageFetch(
            GitStagedFetchRequest(snapshot: snapshot, stagingID: stagingId)
        )
    }

    package func promoteStagedFetch(_ stagedFetch: GitStagedFetchResult) async throws {
        _ = try await client.promoteStagedFetch(
            GitPromoteStagedFetchRequest(stagedFetch: stagedFetch)
        )
    }

    package func cleanupStagedFetch(_ handle: GitStagedFetchHandle) async throws {
        _ = try await client.cleanupStagedFetch(
            GitCleanupStagedFetchRequest(handle: handle)
        )
    }

    package func cleanupAbandonedStagedFetches(
        repositoryCommonDirectory: URL,
        retainedStagingIds: Set<UUID>
    ) async throws {
        _ = try await client.cleanupAbandonedStagedFetches(
            GitCleanupAbandonedStagedFetchesRequest(
                repositoryCommonDirectory: repositoryCommonDirectory,
                retainedStagingIDs: retainedStagingIds
            )
        )
    }
}
