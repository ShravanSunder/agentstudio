import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistenceRuntimeTests {
    @Test("production runtime keeps one inert persistence authority graph")
    func runtimeRetainsOnePreinstallAuthorityGraph() {
        // Arrange
        let atomRegistry = AtomRegistry()

        // Act
        let runtime = WorkspacePersistenceRuntime(atomRegistry: atomRegistry)
        let store = WorkspaceStore(
            workspacePersistenceRuntime: runtime,
            identityAtom: atomRegistry.workspaceIdentity,
            windowMemoryAtom: atomRegistry.workspaceWindowMemory,
            repositoryTopologyAtom: atomRegistry.workspaceRepositoryTopology,
            paneAtom: atomRegistry.workspacePane,
            tabLayoutAtom: atomRegistry.workspaceTabLayout,
            mutationCoordinator: atomRegistry.workspaceMutationCoordinator
        )

        // Assert
        #expect(runtime.revisionOwner.processGeneration.isUUIDv7)
        #expect(runtime.adapters.revisionOwner === runtime.revisionOwner)
        #expect(store.workspacePersistenceRuntime === runtime)
        #expect(store.workspacePersistenceRevisionOwner === runtime.revisionOwner)
        #expect(store.identityAtom === runtime.atomOwners.workspaceIdentity)
        #expect(store.windowMemoryAtom === runtime.atomOwners.workspaceWindowMemory)
        #expect(store.repositoryTopologyAtom === runtime.atomOwners.repositoryTopology)
        #expect(store.paneGraphAtom === runtime.atomOwners.workspacePaneGraph)
        #expect(store.drawerCursorAtom === runtime.atomOwners.workspaceDrawerCursor)
        #expect(store.tabShellAtom === runtime.atomOwners.workspaceTabShell)
        #expect(store.tabCursorAtom === runtime.atomOwners.workspaceTabCursor)
        #expect(store.tabGraphAtom === runtime.atomOwners.workspaceTabGraph)
        #expect(store.arrangementCursorAtom === runtime.atomOwners.workspaceArrangementCursor)
        #expect(runtime.adapters.compositionLifecyclePhase == .preinstall)
        #expect(runtime.adapters.topologyLifecyclePhase == .preinstall)
        #expect(runtime.snapshotParticipantFactory.installedParticipantSet == nil)
        #expect(runtime.snapshotPagerState == .unavailableAwaitingDomainParticipantInstallation)
        #expect(runtime.revisionOwner.committedRevision == .zero)
    }

    @Test("AppDelegate boot constructs runtime once before WorkspaceStore")
    func productionBootRetainsAndInjectsOneRuntime() throws {
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
        let runtimeConstruction = try #require(
            workspaceBootSource.range(
                of: "installWorkspacePersistenceRuntime(WorkspacePersistenceRuntime(atomRegistry: atomStore))"
            )
        )
        let storeConstruction = try #require(workspaceBootSource.range(of: "store = WorkspaceStore("))

        // Assert
        #expect(
            appDelegateSource.contains(
                "private var workspacePersistenceRuntimeBootState = WorkspacePersistenceRuntimeBootState.uninitialized"
            )
        )
        #expect(appDelegateSource.contains("case uninitialized"))
        #expect(appDelegateSource.contains("case ready(WorkspacePersistenceRuntime)"))
        #expect(!appDelegateSource.contains("var workspacePersistenceRuntime: WorkspacePersistenceRuntime!"))
        #expect(registryConstruction.lowerBound < runtimeConstruction.lowerBound)
        #expect(runtimeConstruction.lowerBound < storeConstruction.lowerBound)
        #expect(workspaceBootSource.contains("workspacePersistenceRuntime: workspacePersistenceRuntime"))
        #expect(!workspaceBootSource.contains("workspacePersistenceRevisionOwner:"))
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
        #expect(runtimeSource.contains("WorkspacePreparedCompositionApplier(adapters: adapters)"))
        #expect(runtimeSource.contains("WorkspacePreparedTopologyApplier(adapters: adapters)"))
        #expect(runtimeSource.contains("WorkspacePersistenceMutationCoordinator("))
        #expect(runtimeSource.contains("revisionOwner: revisionOwner"))
        #expect(storeSource.contains("workspacePersistenceRuntime: WorkspacePersistenceRuntime"))
        #expect(
            !storeSource.contains(
                "init(\n        workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner"
            )
        )
    }
}
