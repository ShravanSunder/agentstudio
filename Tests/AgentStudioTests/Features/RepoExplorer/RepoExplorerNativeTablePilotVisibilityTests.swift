import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("Repo Explorer native table pilot visibility")
struct RepoExplorerNativeTablePilotVisibilityTests {
    @Test("facade and scrubbed result are the only package pilot surface")
    func facadeAndResultAreOnlyPackagePilotSurface() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let featureRoot = projectRoot.appending(
            path: "Sources/AgentStudio/Features/RepoExplorer"
        )
        let pilotURL = featureRoot.appending(
            path: "Diagnostics/RepoExplorerNativeTablePilot.swift"
        )
        let pilotSource = try String(contentsOf: pilotURL, encoding: .utf8)
        let pilotModelSource = try String(
            contentsOf: featureRoot.appending(
                path: "Diagnostics/RepoExplorerNativeTablePilotModels.swift"
            ),
            encoding: .utf8
        )

        #expect(pilotSource.contains("package enum RepoExplorerNativeTablePilot"))
        #expect(pilotModelSource.contains("package struct RepoExplorerNativeTablePilotResult"))
        #expect(pilotSource.contains("package static func run("))
        #expect(pilotSource.contains(") async -> RepoExplorerNativeTablePilotResult"))
        #expect(!pilotSource.contains("public "))
        #expect(!pilotModelSource.contains("public "))
        #expect(!pilotSource.contains("#if DEBUG"))
        #expect(!pilotSource.contains("RunLoop"))
        #expect(!pilotSource.contains("DispatchSemaphore"))
        #expect(!pilotSource.contains("Task.sleep"))
        #expect(!pilotModelSource.contains("repoId"))
        #expect(!pilotModelSource.contains("worktreeId"))
        #expect(!pilotModelSource.contains("paneId"))
        #expect(!pilotModelSource.contains("tabId"))

        for relativePath in internalOwnerPaths {
            let source = try String(
                contentsOf: featureRoot.appending(path: relativePath),
                encoding: .utf8
            )
            for declaration in internalDeclarationNames {
                #expect(!source.contains("package \(declaration)"))
                #expect(!source.contains("public \(declaration)"))
            }
        }
    }

    private var internalOwnerPaths: [String] {
        [
            "RepoExplorerProjectionAdapter.swift",
            "RepoExplorerMaterializationHost.swift",
            "RepoExplorerNativeTransactionApplier.swift",
            "Models/RepoExplorerMaterializationHostModels.swift",
            "Models/RepoExplorerNativeUpdatePlan.swift",
            "Models/RepoExplorerNativeUpdatePlanTemplate.swift",
            "Models/RepoExplorerProjectionIntent.swift",
            "Models/RepoExplorerProjectionWorker.swift",
        ]
    }

    private var internalDeclarationNames: [String] {
        [
            "final class RepoExplorerProjectionAdapter",
            "final class RepoExplorerMaterializationHost",
            "struct RepoExplorerMaterializationCandidate",
            "struct RepoExplorerMaterializationContentCandidate",
            "protocol RepoExplorerMaterializationContentChild",
            "enum RepoExplorerNativeTransactionApplier",
            "protocol RepoExplorerNativeTableTransactionTarget",
            "struct RepoExplorerNativeUpdatePlan",
            "struct RepoExplorerNativeUpdatePlanTemplate",
            "struct RepoExplorerNativeUpdatePlanTemplatePair",
            "struct RepoExplorerProjectionRequest",
        ]
    }
}
