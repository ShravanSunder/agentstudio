import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class WorkspacePaneResidencyObservationCounter: @unchecked Sendable {
    private(set) var invalidationCount = 0

    func record() {
        invalidationCount += 1
    }
}

@MainActor
@Suite("Workspace pane residency atom")
struct WorkspacePaneResidencyAtomTests {
    @Test("Pane residency observation ignores unrelated structural changes")
    func paneResidencyObservationIsKeyedAndNarrow() {
        let graphAtom = WorkspacePaneGraphAtom()
        let paneA = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/pane-residency-a", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let paneB = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/pane-residency-b", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let cwdResidencyA = observe { _ = graphAtom.paneResidency(paneA.id) }
        let cwdResidencyB = observe { _ = graphAtom.paneResidency(paneB.id) }

        graphAtom.updatePaneTitle(paneA.id, title: "Renamed")
        graphAtom.updatePaneNote(paneA.id, note: "Note")
        graphAtom.updatePaneCWD(
            paneA.id,
            cwd: URL(filePath: "/tmp/pane-residency-a/Sources", directoryHint: .isDirectory)
        )

        #expect(cwdResidencyA.invalidationCount == 0)
        #expect(cwdResidencyB.invalidationCount == 0)

        let changedResidencyA = observe { _ = graphAtom.paneResidency(paneA.id) }
        let unchangedResidencyB = observe { _ = graphAtom.paneResidency(paneB.id) }
        graphAtom.setResidency(.backgrounded, for: paneA.id)

        #expect(changedResidencyA.invalidationCount == 1)
        #expect(unchangedResidencyB.invalidationCount == 0)
        #expect(graphAtom.paneResidency(paneA.id) == .backgrounded)
    }

    @Test("Pane residency slots follow canonical insertion and removal")
    func paneResidencySlotsFollowCanonicalMembership() {
        let graphAtom = WorkspacePaneGraphAtom()
        let paneID = UUIDv7.generate()
        let missingResidency = observe { _ = graphAtom.paneResidency(paneID) }
        let pane = Pane(
            id: paneID,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/pane-residency-membership", directoryHint: .isDirectory)
            )
        )

        #expect(graphAtom.insertRestoredPane(pane))
        #expect(missingResidency.invalidationCount == 1)
        #expect(graphAtom.paneResidency(paneID) == .active)

        let removedResidency = observe { _ = graphAtom.paneResidency(paneID) }
        #expect(graphAtom.deletePaneAndOwnedDrawerChildren(paneID))
        #expect(removedResidency.invalidationCount == 1)
        #expect(graphAtom.paneResidency(paneID) == nil)
    }

    private func observe(_ access: @escaping @MainActor () -> Void) -> WorkspacePaneResidencyObservationCounter {
        let counter = WorkspacePaneResidencyObservationCounter()
        withObservationTracking {
            access()
        } onChange: {
            counter.record()
        }
        return counter
    }
}
