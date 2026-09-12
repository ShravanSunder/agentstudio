import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Filesystem pipeline observation lifetime", .serialized)
struct FilesystemGitPipelineObservationLifetimeTests {
    @Test("same-context lifetime replacement cancels an old staged remote update")
    func replacementLifetimeRevokesOldRemoteWork() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "pipeline-remote-lifetime-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let epoch = UUIDv7.generate()
        let origin = "https://example.com/org/current-lifetime.git"
        let provider = PipelineRemoteReferenceProviderFake()
        await provider.configure(origin: origin)
        await provider.suspendNextStage()
        let pipeline = FilesystemGitPipeline(
            bus: EventBus<RuntimeEnvelope>(),
            registrationDiscoveryProvider: PipelineAcceptingRegistrationDiscoveryProvider(),
            gitWorkingTreeProvider: .stub { _ in nil }, remoteReferenceRefreshProvider: provider,
            fseventStreamClient: PipelineSilentFSEventStreamClient(), gitCoalescingWindow: .zero
        )
        func assertion(_ revision: UInt64) -> FilesystemTopologyAssertion {
            .init(
                generation: revision, contextsByWorktreeId: [worktreeID: .init(repoId: repositoryID, rootPath: root)],
                repositoryLifetimes: [repositoryID: .init(launchEpoch: epoch, revision: revision)],
                worktreeLifetimes: [worktreeID: .init(launchEpoch: epoch, revision: revision)])
        }
        await pipeline.start()
        await pipeline.register(worktreeId: worktreeID, repoId: repositoryID, rootPath: root)
        await pipeline.assertTopology(assertion(1))
        await pipeline.applyScopeChange(
            .registerForgeRepo(
                repoId: repositoryID, remote: origin,
                expectedLifetime: assertion(1).repositoryLifetimes[repositoryID]))
        let admission = await pipeline.startRepositoryFactUpdate(repoId: repositoryID, attemptId: UUIDv7.generate())
        #expect(admission.acceptedSources.contains(.remoteReferences))
        await assertEventuallyAsync("remote staging is held before scope replacement") {
            await provider.stageIsSuspended
        }

        let replacement = assertion(2)
        let transition = Task { await pipeline.assertTopology(replacement) }
        await assertEventuallyAsync("replacement cancels old remote staging") {
            provider.stageCancellation.wasCancelled
        }
        await provider.releaseStage()
        await transition.value
        let settlement = await admission.settlement()

        #expect(settlement[.remoteReferences] == .obsolete)
        #expect(await provider.promoteCount == 0)
        await pipeline.shutdown()
    }
}

final class PipelineStageCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var wasCancelled: Bool { lock.withLock { cancelled } }
    func record() { lock.withLock { cancelled = true } }
}
