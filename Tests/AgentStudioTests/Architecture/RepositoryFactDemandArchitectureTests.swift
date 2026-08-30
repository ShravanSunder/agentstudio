import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("RepositoryFactDemandArchitectureTests")
struct RepositoryFactDemandArchitectureTests {
    @Test("repository fact demand stays App owned and independent of Repo Explorer presentation")
    func repositoryFactDemandStaysOutsideRepoExplorerPresentation() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoExplorerRoot = projectRoot.appending(
            path: "Sources/AgentStudio/Features/RepoExplorer"
        )
        let forbiddenDemandSymbols = [
            "RepositoryFactDemandCoordinator",
            "RepositoryFactDemandSnapshot",
            "setRepositoryFactDemand",
            "setPullRequestDemandWorktrees",
        ]

        let enumerator = FileManager.default.enumerator(
            at: repoExplorerRoot,
            includingPropertiesForKeys: nil
        )
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbiddenSymbol in forbiddenDemandSymbols {
                #expect(
                    !source.contains(forbiddenSymbol),
                    "\(file.lastPathComponent) must not own repository fact demand through \(forbiddenSymbol)"
                )
            }
        }
    }

    @Test("demand capture uses narrow canonical membership and excludes presentation inputs")
    func demandCaptureUsesOnlyNarrowCanonicalFacts() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let coordinatorSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+RepositoryFactDemand.swift"
            ),
            encoding: .utf8
        )

        #expect(coordinatorSource.contains("repositoryAssociationPaneIds"))
        #expect(coordinatorSource.contains("repositoryAssociation(for:"))
        #expect(coordinatorSource.contains("repositoryMembershipWorktreeIds"))
        #expect(coordinatorSource.contains("repositoryId(containing:"))
        #expect(coordinatorSource.contains("repositoryIdsInOrder"))
        #expect(coordinatorSource.contains("repositoryStableKey:"))
        #expect(coordinatorSource.contains("worktreeStableKeysByID:"))
        #expect(coordinatorSource.contains("repositoryLocalActivity.hydrationDisposition"))
        #expect(coordinatorSource.contains("repositoryLocalActivity.activity(for:"))
        #expect(!coordinatorSource.contains("applicationEntityRecency"))
        #expect(!coordinatorSource.contains("SidebarVisibleWorktreesRuntimeAtom"))
        #expect(!coordinatorSource.contains("sidebarVisibleWorktreesRuntime"))
        #expect(!coordinatorSource.contains("RepoExplorerTableMaterializer"))
        #expect(!coordinatorSource.contains("filterText"))
        #expect(!coordinatorSource.contains("repoGroupingMode"))
        #expect(!coordinatorSource.contains("paneSnapshot"))
        #expect(!coordinatorSource.contains("captureReadSnapshot"))
        #expect(!coordinatorSource.contains("ViewRegistry"))
    }

    @Test("one complete pipeline method owns production source fanout")
    func oneCompletePipelineMethodOwnsSourceFanout() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let pipelineSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift"
            ),
            encoding: .utf8
        )
        let workspaceDemandSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+RepositoryFactDemand.swift"
            ),
            encoding: .utf8
        )
        let filesystemSourceProtocol = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift"
            ),
            encoding: .utf8
        )
        let demandCoordinatorSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Coordination/RepositoryFactDemandCoordinator.swift"
            ),
            encoding: .utf8
        )
        let retiredPartialDemandMethods = [
            "func setActivity(",
            "func setActivePaneWorktree(",
            "func setSidebarVisibleWorktrees(",
            "func setPullRequestDemandWorktrees(",
        ]

        #expect(pipelineSource.contains("func setRepositoryFactDemand(_ snapshot:"))
        #expect(pipelineSource.contains("filesystemActor.setRepositoryFactAttention("))
        #expect(pipelineSource.contains("gitWorkingDirectoryProjector.setRepositoryFactAttention("))
        #expect(
            pipelineSource.contains(
                "warmAutomaticWorktreeIds: snapshot.automaticLocalGitWorktreeIds"
            )
        )
        #expect(
            pipelineSource.contains(
                "backgroundOnlyAutomaticWorktreeIds: snapshot.backgroundOnlyAutomaticWorktreeIds"
            )
        )
        #expect(pipelineSource.contains("forgeActor.setDemand(worktreeIds: snapshot.forgeDemandedWorktreeIds)"))
        #expect(workspaceDemandSource.contains("repositoryFactDemandCoordinator.accept(input)"))
        #expect(demandCoordinatorSource.contains("@concurrent nonisolated private static func classify("))
        #expect(demandCoordinatorSource.contains("RepositoryActivityClassifier.classify("))
        #expect(!workspaceDemandSource.contains("setActivity("))
        #expect(!workspaceDemandSource.contains("setActivePaneWorktree("))
        #expect(!workspaceDemandSource.contains("setSidebarVisibleWorktrees("))
        #expect(!workspaceDemandSource.contains("setPullRequestDemandWorktrees("))
        for retiredMethod in retiredPartialDemandMethods {
            #expect(!pipelineSource.contains(retiredMethod))
            #expect(!filesystemSourceProtocol.contains(retiredMethod))
        }
    }
}
