import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("BridgeNavigationAtom")
struct BridgeNavigationAtomTests {
    @Test("equal records are suppressed and unequal records advance the accepted revision once")
    func equalRecordsAreSuppressed() {
        // Arrange
        let atom = BridgeNavigationAtom()
        let receiver = BridgeReceiver.terminal(UUIDv7.generate())
        let record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: UUIDv7.generate())

        // Act / Assert
        #expect(atom.setRecord(record, for: receiver))
        let revisionAfterFirstWrite = atom.acceptedRevision
        #expect(!atom.setRecord(record, for: receiver))
        #expect(atom.acceptedRevision == revisionAfterFirstWrite)

        var changed = record
        changed.surface = .review
        #expect(atom.setRecord(changed, for: receiver))
        #expect(atom.acceptedRevision == revisionAfterFirstWrite + 1)
        #expect(atom.record(for: receiver) == changed)
    }

    @Test("a keyed read wakes only for its own receiver")
    func keyedReadWakesOnlyItsReceiver() {
        // Arrange
        let atom = BridgeNavigationAtom()
        let observed = BridgeReceiver.terminal(UUIDv7.generate())
        let other = BridgeReceiver.standalone(UUIDv7.generate())
        atom.setRecord(.empty, for: observed)
        atom.setRecord(.empty, for: other)
        let recorder = BridgeNavigationObservationRecorder()
        withObservationTracking {
            _ = atom.record(for: observed)
        } onChange: {
            recorder.recordCurrentMutation()
        }

        // Act
        var otherRecord = BridgeNavigationRecord.empty
        otherRecord.surface = .review
        recorder.currentMutation = .otherReceiver
        atom.setRecord(otherRecord, for: other)
        var observedRecord = BridgeNavigationRecord.empty
        observedRecord.surface = .review
        recorder.currentMutation = .observedReceiver
        atom.setRecord(observedRecord, for: observed)

        // Assert
        #expect(recorder.recordedMutations == [.observedReceiver])
    }

    @Test("receiver lookup by pane finds either kind; removal and replacement publish")
    func receiverLookupRemovalAndReplacement() {
        let atom = BridgeNavigationAtom()
        let terminalPane = UUIDv7.generate()
        let bridgePane = UUIDv7.generate()
        atom.replaceAllRecords([
            .terminal(terminalPane): .empty,
            .standalone(bridgePane): .empty,
        ])

        #expect(atom.receiver(forPaneId: terminalPane) == .terminal(terminalPane))
        #expect(atom.receiver(forPaneId: bridgePane) == .standalone(bridgePane))
        #expect(atom.receiver(forPaneId: UUIDv7.generate()) == nil)

        #expect(atom.removeRecord(for: .terminal(terminalPane)))
        #expect(!atom.removeRecord(for: .terminal(terminalPane)))
        #expect(
            atom.recordsSnapshot().keys.sorted { $0.paneId.uuidString < $1.paneId.uuidString }
                == [.standalone(bridgePane)])
    }
}

private final class BridgeNavigationObservationRecorder: @unchecked Sendable {
    enum Mutation: Equatable {
        case otherReceiver
        case observedReceiver
    }

    var currentMutation = Mutation.otherReceiver
    private(set) var recordedMutations: [Mutation] = []

    func recordCurrentMutation() {
        recordedMutations.append(currentMutation)
    }
}
