import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Filesystem pipeline scope ordering", .serialized)
struct FilesystemPipelineScopeOrderingTests {
    @Test("unregister admitted during blocked registration wins after the earlier validation returns")
    func unregisterCannotBeUndoneByEarlierRegistration() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pipeline-scope-order-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = BlockedScopeRegistrationProvider()
        let client = ControllableFSEventStreamClient()
        let pipeline = FilesystemGitPipeline(
            bus: EventBus<RuntimeEnvelope>(), registrationDiscoveryProvider: provider,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil }, fseventStreamClient: client
        )
        let worktreeID = UUIDv7.generate()
        let repoID = UUIDv7.generate()
        let registration = Task { await pipeline.register(worktreeId: worktreeID, repoId: repoID, rootPath: root) }
        await assertEventuallyAsync("registration should reach its provider") { await provider.entered }
        let unregistration = Task { await pipeline.unregister(worktreeId: worktreeID) }
        await assertEventuallyAsync("both scope operations should be admitted") {
            await pipeline.scopeMutationSubmissionCount() >= 2
        }

        await provider.release()
        await registration.value
        await unregistration.value

        #expect(!client.activeWorktreeIds.contains(worktreeID))
        await pipeline.shutdown()
    }
}

private actor BlockedScopeRegistrationProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        return .validated(.init(path: url, kind: .cloneRoot, repositoryKey: url.path))
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
