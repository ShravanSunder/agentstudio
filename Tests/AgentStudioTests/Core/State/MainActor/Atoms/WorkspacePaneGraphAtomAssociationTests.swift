import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class PaneAssociationObservationFlag: @unchecked Sendable {
    var didFire = false
}

@MainActor
@Suite("WorkspacePaneGraphAtom association facts")
struct WorkspacePaneGraphAtomAssociationTests {
    @Test("association lookup ignores cwd and presentation changes")
    func associationLookupIgnoresUnrelatedPaneChanges() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/association-observation", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId)
        )
        let observation = PaneAssociationObservationFlag()

        withObservationTracking {
            _ = graphAtom.repositoryAssociation(for: pane.id)
        } onChange: {
            observation.didFire = true
        }

        graphAtom.updatePaneTitle(pane.id, title: "Changed title")
        graphAtom.updatePaneNote(pane.id, note: "Changed note")
        graphAtom.updatePaneCWD(
            pane.id,
            cwd: URL(filePath: "/tmp/association-observation/child", directoryHint: .isDirectory)
        )

        #expect(observation.didFire == false)
        #expect(
            graphAtom.repositoryAssociation(for: pane.id)
                == PaneRepositoryAssociation(repoId: repoId, worktreeId: worktreeId)
        )
    }

    @Test("association lookup observes association replacement")
    func associationLookupObservesAssociationReplacement() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let firstRepoId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondRepoId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/association-replacement", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(repoId: firstRepoId, worktreeId: firstWorktreeId)
        )
        let observation = PaneAssociationObservationFlag()

        withObservationTracking {
            _ = graphAtom.repositoryAssociation(for: pane.id)
        } onChange: {
            observation.didFire = true
        }

        let revision = try #require(graphAtom.reservePaneAssociationRevision(pane.id))
        let result = graphAtom.applyPaneAssociationUpdate(
            pane.id,
            cwd: URL(filePath: "/tmp/association-replacement", directoryHint: .isDirectory),
            resolution: .matched(repoId: secondRepoId, worktreeId: secondWorktreeId),
            revision: revision
        )

        #expect(result == .applied)
        #expect(observation.didFire)
        #expect(
            graphAtom.repositoryAssociation(for: pane.id)
                == PaneRepositoryAssociation(repoId: secondRepoId, worktreeId: secondWorktreeId)
        )
    }

    @Test("association membership observes pane membership only")
    func associationMembershipObservesPaneMembershipOnly() {
        let graphAtom = WorkspacePaneGraphAtom()
        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/association-membership", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let unrelatedObservation = PaneAssociationObservationFlag()

        withObservationTracking {
            _ = graphAtom.repositoryAssociationPaneIds
        } onChange: {
            unrelatedObservation.didFire = true
        }

        graphAtom.updatePaneTitle(pane.id, title: "No membership change")
        #expect(unrelatedObservation.didFire == false)

        let membershipObservation = PaneAssociationObservationFlag()
        withObservationTracking {
            _ = graphAtom.repositoryAssociationPaneIds
        } onChange: {
            membershipObservation.didFire = true
        }

        _ = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/association-membership-second", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        #expect(membershipObservation.didFire)
    }
}
