import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("Worktree annotation output composition")
struct WorktreeAnnotationOutputCompositionTests {
    @Test("application boot is the sole output coordinator construction owner")
    func applicationBootOwnsOneOutputCoordinatorAndThreadsItToBridge() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles = try sourceFilesUnder(sourcesRoot)
        let coordinatorConstructionCount = try sourceFiles.reduce(into: 0) { count, sourceURL in
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            count += source.components(separatedBy: "WorktreeAnnotationOutputCoordinator(").count - 1
        }
        #expect(coordinatorConstructionCount == 1)

        let appDelegate = try source(
            projectRoot,
            path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"
        )
        let workspaceBoot = try source(
            projectRoot,
            path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"
        )
        let surfaceCoordinator = try source(
            projectRoot,
            path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift"
        )
        let bridgeLifecycle = try source(
            projectRoot,
            path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeViewLifecycle.swift"
        )
        let bridgeController = try source(
            projectRoot,
            path: "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift"
        )
        let bridgeBootstrap = try source(
            projectRoot,
            path: "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift"
        )

        #expect(
            appDelegate.contains(
                "var worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinator!"
            )
        )
        #expect(
            workspaceBoot.contains(
                "worktreeAnnotationOutputCoordinator = WorktreeAnnotationOutputCoordinator("
            )
        )
        #expect(workspaceBoot.contains("effect: WorktreeAnnotationOutputEffects()"))
        #expect(workspaceBoot.contains("worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator"))
        #expect(
            surfaceCoordinator.contains(
                "let worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinator?"
            )
        )
        #expect(bridgeLifecycle.contains("worktreeAnnotationOutputCoordinator: worktreeAnnotationOutputCoordinator"))
        #expect(
            bridgeController.contains("worktreeAnnotationOutputCoordinator: WorktreeAnnotationOutputCoordinator? = nil")
        )
        #expect(bridgeBootstrap.contains("outputCoordinator: input.worktreeAnnotationOutputCoordinator"))
    }

    private func sourceFilesUnder(_ root: URL) throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys
            )
        else {
            Issue.record("Could not enumerate AgentStudio source files")
            return []
        }
        return try enumerator.compactMap { entry in
            guard let sourceURL = entry as? URL,
                sourceURL.pathExtension == "swift",
                try sourceURL.resourceValues(forKeys: Set(resourceKeys)).isRegularFile == true
            else { return nil }
            return sourceURL
        }
    }

    private func source(_ root: URL, path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
}
