import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistenceRuntimeTests {
    @Test("dormant runtime keeps one inert persistence authority graph")
    func runtimeRetainsOnePreinstallAuthorityGraph() {
        // Arrange
        let atomRegistry = AtomRegistry()

        // Act
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)

        // Assert
        #expect(runtime.revisionOwner.processGeneration.isUUIDv7)
        #expect(runtime.adapters.revisionOwner === runtime.revisionOwner)
        #expect(runtime.adapters.compositionLifecyclePhase == .preinstall)
        #expect(runtime.adapters.topologyLifecyclePhase == .preinstall)
        #expect(runtime.snapshotParticipantFactory.installedParticipantSet == nil)
        #expect(runtime.snapshotPagerState == .unavailableAwaitingDomainParticipantInstallation)
        #expect(runtime.revisionOwner.committedRevision == .zero)
    }

    @Test("AppDelegate boot constructs WorkspaceStore without persistence runtime")
    func productionBootConstructsStoreWithoutPersistenceRuntime() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"),
            encoding: .utf8
        )
        let workspaceBootSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"
            ),
            encoding: .utf8
        )

        // Act
        let registryConstruction = try #require(workspaceBootSource.range(of: "atomStore = AtomRegistry()"))
        let storeConstruction = try #require(workspaceBootSource.range(of: "store = WorkspaceStore("))

        // Assert
        #expect(!appDelegateSource.contains("WorkspacePersistenceRuntimeBootState"))
        #expect(!appDelegateSource.contains("workspacePersistenceRuntime"))
        #expect(registryConstruction.lowerBound < storeConstruction.lowerBound)
        #expect(!workspaceBootSource.contains("WorkspacePersistenceRuntime"))
    }

    @Test("runtime alone composes every persistence owner from one adapter bundle")
    func runtimeSourceHasOneCompositionGraph() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let runtimeSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceRuntime.swift"
            ),
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift"
            ),
            encoding: .utf8
        )

        // Act / Assert
        #expect(runtimeSource.components(separatedBy: "WorkspacePersistenceAdapterBundle(").count == 2)
        #expect(runtimeSource.components(separatedBy: "WorkspacePersistenceRevisionOwner()").count == 2)
        #expect(runtimeSource.contains("WorkspacePersistenceSnapshotParticipantFactory(adapters: adapters)"))
        #expect(!runtimeSource.contains("WorkspacePreparedCompositionApplier"))
        #expect(runtimeSource.contains("WorkspacePreparedTopologyApplier(adapters: adapters)"))
        #expect(runtimeSource.contains("WorkspacePersistenceMutationCoordinator("))
        #expect(runtimeSource.contains("revisionOwner: revisionOwner"))
        #expect(storeSource.contains("private let preparedCompositionApplier: WorkspacePreparedCompositionApplier"))
        #expect(storeSource.contains("preparedCompositionApplier = WorkspacePreparedCompositionApplier("))
        #expect(!storeSource.contains("WorkspacePersistenceRuntime"))
        #expect(
            !storeSource.contains(
                "init(\n        workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner"
            )
        )
    }
}
