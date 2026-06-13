import Foundation
import Testing

@Suite("FilesystemActorHotPathArchitectureTests")
struct FilesystemActorHotPathArchitectureTests {
    @Test("path filter loading runs through a concurrent async boundary")
    func pathFilterLoadingRunsThroughConcurrentAsyncBoundary() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let filesystemActorSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift"
            ),
            encoding: .utf8
        )
        let pathFilterSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemPathFilter.swift"
            ),
            encoding: .utf8
        )
        let gitProviderSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingTreeStatusProvider.swift"
            ),
            encoding: .utf8
        )

        #expect(pathFilterSource.contains("@concurrent nonisolated static func loadOffExecutor"))
        #expect(filesystemActorSource.contains("await FilesystemPathFilter.loadOffExecutor(forRootPath:"))
        #expect(!filesystemActorSource.contains("FilesystemPathFilter.load(forRootPath:"))
        #expect(gitProviderSource.contains("@concurrent\n    nonisolated private static func computeStatus"))
    }

    @Test("git projector coalescing window is an explicit construction policy")
    func gitProjectorCoalescingWindowIsExplicitConstructionPolicy() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let projectorSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift"
            ),
            encoding: .utf8
        )

        #expect(projectorSource.contains("coalescingWindow: Duration,"))
        #expect(!projectorSource.contains("coalescingWindow: Duration = .zero"))
    }

    @Test("git snapshot projection skips workspace topology root lookup")
    func gitSnapshotProjectionSkipsWorkspaceTopologyRootLookup() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let coordinatorSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift"
            ),
            encoding: .utf8
        )

        let projectionBody = try #require(
            coordinatorSource.slice(
                from: "func handleFilesystemEnvelopeIfNeeded(_ envelope: RuntimeEnvelope) async -> Bool",
                to: "nonisolated private static func shouldProjectPaneFilesystemEnvelope"
            )
        )

        #expect(projectionBody.contains("await filesystemProjectionIndex.projectPaneFilesystem"))
        #expect(projectionBody.contains("paneFilesystemProjectionStore.applyProjectionIntent"))
        #expect(!projectionBody.contains("workspaceWorktreeContexts"))
        #expect(!projectionBody.contains("filesystemRegisteredContextsByWorktreeId"))
    }
}

extension String {
    fileprivate func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
