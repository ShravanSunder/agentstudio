import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("BridgeNavigationAtom")
struct BridgeNavigationAtomTests {
    @Test("a prepared document writes one keyed observation slot")
    func openedDocumentWriteIsKeyed() {
        let atom = BridgeNavigationAtom()
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let observed = BridgeDocumentLocation(canonicalPath: "/tmp/observed.swift")!
        let other = BridgeDocumentLocation(canonicalPath: "/tmp/other.swift")!
        let entry = BridgeOpenedDocumentEntry(
            provenance: nil, sortKey: UUIDv7.generate(milliseconds: 1_700_000_000_001))
        atom.setRecord(.empty, for: receiver)
        let recorder = BridgeNavigationObservationRecorder()
        withObservationTracking {
            _ = atom.openedDocumentEntry(for: receiver, at: observed)
        } onChange: {
            recorder.recordCurrentMutation()
        }

        recorder.currentMutation = .otherReceiver
        atom.assignOpenedDocument(entry, at: other, for: receiver)
        recorder.currentMutation = .observedReceiver
        atom.assignOpenedDocument(entry, at: observed, for: receiver)

        #expect(recorder.recordedMutations == [.observedReceiver])
        #expect(atom.openedDocumentEntry(for: receiver, at: observed) == entry)
        #expect(atom.record(for: receiver)?.openedDocuments[other] == entry)
    }

    @Test("prepared Files slot accepts only a newer capture ticket")
    func preparedFilesSlotRejectsLatePreparation() {
        let atom = BridgeNavigationAtom()
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let location = BridgeDocumentLocation(canonicalPath: "/tmp/slot.swift")!
        let token = BridgeFilesSourceBinding.collectionToken(forReceiverPaneId: receiver.paneId)
        let current = BridgeFilesSourceBinding(
            collectionToken: token, members: [], openedDocuments: [location])
        let stale = BridgeFilesSourceBinding(
            collectionToken: token, members: [], openedDocuments: [])

        #expect(atom.assignPreparedFilesBinding(current, for: receiver, ticket: 2))
        #expect(!atom.assignPreparedFilesBinding(stale, for: receiver, ticket: 1))
        #expect(atom.preparedFilesBinding(for: receiver) == current)
        #expect(atom.acceptedRevision == 0, "presentation preparation does not create a durable write")
        atom.setRecord(.empty, for: receiver)
        #expect(atom.removeRecord(for: receiver))
        #expect(atom.preparedFilesBinding(for: receiver) == nil)
        #expect(atom.assignPreparedFilesBinding(stale, for: receiver, ticket: 0))
    }

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
    func receiverLookupRemovalAndReplacement() async {
        let atom = BridgeNavigationAtom()
        let terminalPane = UUIDv7.generate()
        let bridgePane = UUIDv7.generate()
        let publication = await BridgeNavigationAtomPublication.prepareOffMain(records: [
            .terminal(terminalPane): .empty,
            .standalone(bridgePane): .empty,
        ])
        atom.replaceAllPreparedRecords(publication)

        #expect(atom.receiver(forPaneId: terminalPane) == .terminal(terminalPane))
        #expect(atom.receiver(forPaneId: bridgePane) == .standalone(bridgePane))
        #expect(atom.receiver(forPaneId: UUIDv7.generate()) == nil)

        #expect(atom.removeRecord(for: .terminal(terminalPane)))
        #expect(!atom.removeRecord(for: .terminal(terminalPane)))
        #expect(atom.record(for: .terminal(terminalPane)) == nil)
        #expect(atom.record(for: .standalone(bridgePane)) == .empty)
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
