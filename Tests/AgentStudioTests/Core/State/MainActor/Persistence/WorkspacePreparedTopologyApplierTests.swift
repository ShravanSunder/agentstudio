import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePreparedTopologyApplierTests {
    @Test("topology applies independently and seals only its own bootstrap domain")
    func topologyAppliesAndSealsOnlyTopologyBootstrap() {
        // Arrange
        let fixture = PreparedTopologyFixture()
        let repositoryID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let snapshot = RepositoryTopologySQLiteSnapshot(
            id: workspaceID,
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "agent-studio",
                    repoPath: URL(filePath: "/tmp/agent-studio")
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        guard case .prepared(let prepared) = WorkspaceTopologyPreparer.prepare(snapshot) else {
            Issue.record("expected topology preparation")
            return
        }

        // Act
        let applyResult = fixture.applier.apply(prepared)
        let installResult = fixture.factory.constructTopologyParticipantSet()
        let secondApplyResult = fixture.applier.apply(prepared)

        // Assert
        guard case .accepted(let acceptance) = applyResult else {
            Issue.record("expected initial topology apply")
            return
        }
        #expect(acceptance.workspaceID == workspaceID)
        #expect(acceptance.revision.rawValue == 1)
        #expect(fixture.topologyAtom.repos.map(\.id) == [repositoryID])
        #expect(fixture.revisionOwner.committedRevision == acceptance.revision)

        guard case .constructed(let participantSet) = installResult else {
            Issue.record("expected topology participant installation")
            return
        }
        #expect(
            participantSet.participantIDs == [
                .repositories, .worktrees, .watchedPaths, .unavailableRepositories,
            ]
        )
        guard case .failed(.lifecycle) = secondApplyResult else {
            Issue.record("expected installed topology lifecycle to reject another initial apply")
            return
        }
        #expect(fixture.revisionOwner.committedRevision == acceptance.revision)
        #expect(fixture.adapters.compositionLifecyclePhase == .preinstall)
    }
}

@MainActor
private struct PreparedTopologyFixture {
    let revisionOwner = WorkspacePersistenceRevisionOwner()
    let topologyAtom = RepositoryTopologyAtom()
    let adapters: WorkspacePersistenceAdapterBundle
    let applier: WorkspacePreparedTopologyApplier
    let factory: WorkspacePersistenceSnapshotParticipantFactory

    init() {
        let identityAtom = WorkspaceIdentityAtom()
        let windowMemoryAtom = WorkspaceWindowMemoryAtom()
        let paneGraphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let tabCursorAtom = WorkspaceTabCursorAtom()
        let tabShellAtom = WorkspaceTabShellAtom(cursorAtom: tabCursorAtom)
        let tabGraphAtom = WorkspaceTabGraphAtom()
        let arrangementCursorAtom = WorkspaceArrangementCursorAtom()
        let adapters = WorkspacePersistenceAdapterBundle(
            revisionOwner: revisionOwner,
            workspaceIdentityAtom: identityAtom,
            workspaceWindowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: topologyAtom,
            workspacePaneGraphAtom: paneGraphAtom,
            workspaceDrawerCursorAtom: drawerCursorAtom,
            workspaceTabShellAtom: tabShellAtom,
            workspaceTabCursorAtom: tabCursorAtom,
            workspaceTabGraphAtom: tabGraphAtom,
            workspaceArrangementCursorAtom: arrangementCursorAtom
        )
        self.adapters = adapters
        applier = WorkspacePreparedTopologyApplier(adapters: adapters)
        factory = WorkspacePersistenceSnapshotParticipantFactory(adapters: adapters)
    }
}
