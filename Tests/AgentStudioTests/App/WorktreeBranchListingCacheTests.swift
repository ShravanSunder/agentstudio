import AgentStudioGit
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio

@Suite("Worktree branch listing cache")
struct WorktreeBranchListingCacheTests {
    @Test("the first repository query loads local branches and a repeated revision reuses them")
    func reusesListingForSameRevision() async throws {
        let query = BranchListingQueryProbe()
        let cache = WorktreeBranchListingCache(query: { path in try await query.branches(for: path) })
        let repositoryId = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/branch-list-cache-repo")

        let first = try await cache.branchNames(
            forRepositoryId: repositoryId, repositoryPath: repositoryPath, enrichmentRevision: 1)
        let second = try await cache.branchNames(
            forRepositoryId: repositoryId, repositoryPath: repositoryPath, enrichmentRevision: 1)

        #expect(first == ["main", "feature/source"])
        #expect(second == first)
        #expect(await query.requestedPaths == [repositoryPath])
    }

    @Test("a changed enrichment revision reloads only the repository's entry")
    func revisionChangeReloads() async throws {
        let query = BranchListingQueryProbe()
        let cache = WorktreeBranchListingCache(query: { path in try await query.branches(for: path) })
        let firstRepositoryId = UUIDv7.generate()
        let secondRepositoryId = UUIDv7.generate()
        let firstPath = URL(filePath: "/tmp/branch-list-first")
        let secondPath = URL(filePath: "/tmp/branch-list-second")

        _ = try await cache.branchNames(
            forRepositoryId: firstRepositoryId, repositoryPath: firstPath, enrichmentRevision: 1)
        _ = try await cache.branchNames(
            forRepositoryId: secondRepositoryId, repositoryPath: secondPath, enrichmentRevision: 1)
        _ = try await cache.branchNames(
            forRepositoryId: firstRepositoryId, repositoryPath: firstPath, enrichmentRevision: 2)
        _ = try await cache.branchNames(
            forRepositoryId: secondRepositoryId, repositoryPath: secondPath, enrichmentRevision: 1)

        #expect(await query.requestedPaths == [firstPath, secondPath, firstPath])
    }

    @Test("a failed listing does not poison the cache")
    func failedListingMayRetry() async throws {
        let query = BranchListingQueryProbe(failFirstQuery: true)
        let cache = WorktreeBranchListingCache(query: { path in try await query.branches(for: path) })
        let repositoryId = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/branch-list-retry")

        await #expect(throws: BranchListingQueryError.self) {
            _ = try await cache.branchNames(
                forRepositoryId: repositoryId, repositoryPath: repositoryPath, enrichmentRevision: 1)
        }
        let recovered = try await cache.branchNames(
            forRepositoryId: repositoryId, repositoryPath: repositoryPath, enrichmentRevision: 1)

        #expect(recovered == ["main", "feature/source"])
        #expect(await query.requestedPaths == [repositoryPath, repositoryPath])
    }
}

private enum BranchListingQueryError: Error {
    case unavailable
}

private actor BranchListingQueryProbe {
    private(set) var requestedPaths: [URL] = []
    private var failFirstQuery: Bool

    init(failFirstQuery: Bool = false) {
        self.failFirstQuery = failFirstQuery
    }

    func branches(for path: URL) throws -> [GitBranchSnapshot] {
        requestedPaths.append(path)
        if failFirstQuery {
            failFirstQuery = false
            throw BranchListingQueryError.unavailable
        }
        return [
            GitBranchSnapshot(name: "main", isCurrent: true, upstreamName: nil),
            GitBranchSnapshot(name: "feature/source", isCurrent: false, upstreamName: nil),
        ]
    }
}
