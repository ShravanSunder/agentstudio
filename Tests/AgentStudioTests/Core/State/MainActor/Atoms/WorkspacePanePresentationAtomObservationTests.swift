import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite
struct WorkspacePanePresentationAtomObservationTests {
    @Test("keyed zoom lookup wakes only for its tab")
    func keyedZoomLookupWakesOnlyForItsTab() {
        // Arrange
        let atom = WorkspacePanePresentationAtom()
        let observedTabID = UUIDv7.generate()
        let unrelatedTabID = UUIDv7.generate()
        let observationRecorder = WorkspacePanePresentationObservationRecorder()
        withObservationTracking {
            _ = atom.zoomPresentation(forTab: observedTabID)
        } onChange: {
            observationRecorder.recordCurrentMutation()
        }

        // Act
        observationRecorder.currentMutation = .unrelatedTab
        atom.enterZoom(
            inTab: unrelatedTabID,
            sourcePaneId: UUIDv7.generate(),
            viewerPresentation: .retryable
        )
        observationRecorder.currentMutation = .observedTab
        atom.enterZoom(
            inTab: observedTabID,
            sourcePaneId: UUIDv7.generate(),
            viewerPresentation: .retryable
        )

        // Assert
        #expect(observationRecorder.recordedMutations == [.observedTab])
    }
}

private final class WorkspacePanePresentationObservationRecorder: @unchecked Sendable {
    enum Mutation: Equatable {
        case unrelatedTab
        case observedTab
    }

    var currentMutation = Mutation.unrelatedTab
    private(set) var recordedMutations: [Mutation] = []

    func recordCurrentMutation() {
        recordedMutations.append(currentMutation)
    }
}
