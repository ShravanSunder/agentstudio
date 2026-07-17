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
        let sdkGitProviderSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift"
            ),
            encoding: .utf8
        )
        let repoScannerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Infrastructure/RepoScanner.swift"
            ),
            encoding: .utf8
        )
        let filesystemGitPipelineSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift"
            ),
            encoding: .utf8
        )

        #expect(pathFilterSource.contains("@concurrent nonisolated static func loadOffExecutor"))
        #expect(filesystemActorSource.contains("await FilesystemPathFilter.loadOffExecutor(forRootPath:"))
        #expect(!filesystemActorSource.contains("FilesystemPathFilter.load(forRootPath:"))
        #expect(!gitProviderSource.contains("ShellGitWorkingTreeStatusProvider"))
        #expect(!gitProviderSource.contains("command: \"git\""))
        #expect(sdkGitProviderSource.contains("import AgentStudioGit"))
        #expect(sdkGitProviderSource.contains("@concurrent\n    nonisolated private static func computeStatus"))
        assertNoProductionGitShellSignature(in: sdkGitProviderSource)
        assertNoProductionGitShellSignature(in: repoScannerSource)
        #expect(
            repoScannerSource.contains(
                "func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome"
            )
        )
        #expect(repoScannerSource.contains("case .validationRequired(let request):"))
        #expect(repoScannerSource.contains("await discoveryProvider.discoveryOutcome("))
        #expect(repoScannerSource.contains("session.consumeValidationCompletion("))
        #expect(filesystemGitPipelineSource.contains("AgentStudioGitWorkingTreeStatusProvider()"))
        try assertNoUnexpectedProductionGitShellSignatures(projectRoot: projectRoot)
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
                path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift"
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
        #expect(projectionBody.contains("projectionResult.intents.map(makeFilesystemProjectionEnvelope)"))
        #expect(!projectionBody.contains("paneFilesystemProjectionStore"))
        #expect(!projectionBody.contains("workspaceWorktreeContexts"))
        #expect(!projectionBody.contains("filesystemRegisteredContextsByWorktreeId"))
    }
}

private func assertNoProductionGitShellSignature(in source: String) {
    #expect(!source.contains("command: \"git\""))
    #expect(!source.contains("arguments = [\"git\""))
    #expect(!source.contains("/usr/bin/git"))
    #expect(!source.contains("rev-parse"))
    #expect(!source.contains("status --porcelain"))
    #expect(!source.contains("diff --shortstat"))
}

private func assertNoUnexpectedProductionGitShellSignatures(projectRoot: URL) throws {
    let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
    let fileManager = FileManager.default
    let enumerator = try #require(
        fileManager.enumerator(at: sourcesRoot, includingPropertiesForKeys: [.isRegularFileKey]))
    let allowedShellGitFiles = Set([
        "Sources/AgentStudio/Infrastructure/WorktrunkService.swift"
    ])
    let forbiddenSignatures = [
        "command: \"git\"",
        "arguments = [\"git\"",
        "/usr/bin/git",
        "rev-parse",
        "status --porcelain",
        "diff --shortstat",
    ]

    for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension == "swift" else { continue }
        let relativePath = fileURL.path.replacingOccurrences(of: "\(projectRoot.path)/", with: "")
        guard !allowedShellGitFiles.contains(relativePath) else { continue }
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        for signature in forbiddenSignatures {
            #expect(!source.contains(signature), "Unexpected Git shell signature \(signature) in \(relativePath)")
        }
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
