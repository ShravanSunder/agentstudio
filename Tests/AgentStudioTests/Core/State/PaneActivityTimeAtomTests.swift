import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct PaneActivityTimeAtomTests {
    @Test("a batch assigns and removes activity times without waking for an equal value")
    func batchAssignmentAndEqualSuppression() {
        let atom = PaneActivityTimeAtom()
        let paneId = UUIDv7.generate()
        let instant = ContinuousClock.now
        let time = PaneActivityTime(
            orderingInstant: instant,
            wallTime: Date(timeIntervalSince1970: 1000),
            source: .terminal
        )

        atom.apply([.set(paneId, time)])
        let acceptedRevision = atom.revision(for: paneId)
        #expect(atom.value(for: paneId) == time)

        atom.apply([.set(paneId, time)])
        #expect(atom.revision(for: paneId) == acceptedRevision)

        atom.apply([.remove(paneId)])
        #expect(atom.value(for: paneId) == nil)
        #expect(atom.revision(for: paneId) > acceptedRevision)
    }
}
