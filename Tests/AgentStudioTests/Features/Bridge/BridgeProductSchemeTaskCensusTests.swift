import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product scheme task census")
struct BridgeProductSchemeTaskCensusTests {
    @Test("a started stream task is not terminated until it is marked")
    func startedStreamTaskIsNotTerminatedUntilMarked() {
        // Arrange
        let census = BridgeProductSchemeTaskCensus()
        let schemeTaskId = UUIDv7.generate()

        // Act / Assert
        census.start(schemeTaskId)
        #expect(!census.everyStartedStreamTaskTerminated)
        census.markTerminated(schemeTaskId)
        #expect(census.everyStartedStreamTaskTerminated)
    }

    @Test("finishing a task leaves no residue in either set")
    func finishingATaskLeavesNoResidue() {
        // Arrange
        let census = BridgeProductSchemeTaskCensus()
        let firstId = UUIDv7.generate()
        let secondId = UUIDv7.generate()

        // Act
        census.start(firstId)
        census.start(secondId)
        census.markTerminated(firstId)
        census.finish(firstId)

        // Assert — the second task is still live, so the gate must still refuse.
        #expect(!census.everyStartedStreamTaskTerminated)
        census.finish(secondId)
        // Empty reads as terminated: the gate only asks when a lease exists, so
        // an empty census means the transport is already gone.
        #expect(census.everyStartedStreamTaskTerminated)
    }

    @Test("an empty census reads as terminated")
    func emptyCensusReadsAsTerminated() {
        #expect(BridgeProductSchemeTaskCensus().everyStartedStreamTaskTerminated)
    }

    @Test("marking a task that was never started changes nothing")
    func markingATaskThatWasNeverStartedChangesNothing() {
        // Arrange — a command or content route never calls start, so a stray mark
        // for one must not make a live stream look terminated.
        let census = BridgeProductSchemeTaskCensus()
        let streamId = UUIDv7.generate()

        // Act
        census.start(streamId)
        census.markTerminated(UUIDv7.generate())

        // Assert
        #expect(!census.everyStartedStreamTaskTerminated)
    }

    @Test("concurrent mark and finish leave no residue")
    func concurrentMarkAndFinishLeaveNoResidue() async {
        // Arrange / Act — mark and finish race for the same id, several hundred
        // times. Whichever order wins, the census must end empty and therefore
        // read as terminated.
        for _ in 0..<400 {
            let census = BridgeProductSchemeTaskCensus()
            let schemeTaskId = UUIDv7.generate()
            census.start(schemeTaskId)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { census.markTerminated(schemeTaskId) }
                group.addTask { census.finish(schemeTaskId) }
            }

            // Assert
            #expect(census.everyStartedStreamTaskTerminated)
        }
    }

    @Test("the termination observer is absent unless a caller supplies one")
    func terminationObserverIsAbsentUnlessSupplied() async {
        // Arrange — production constructs the census with no observer, which is
        // what keeps the cancellation path free of an added suspension.
        let productionCensus = BridgeProductSchemeTaskCensus()
        let observedIds = BridgeProductSchemeTaskCensusObservedIds()
        let observedCensus = BridgeProductSchemeTaskCensus { schemeTaskId in
            await observedIds.record(schemeTaskId)
        }
        let schemeTaskId = UUIDv7.generate()

        // Act
        await observedCensus.awaitTerminationObserver(schemeTaskId)

        // Assert
        #expect(!productionCensus.holdsTerminationObserver)
        #expect(observedCensus.holdsTerminationObserver)
        #expect(await observedIds.recorded == [schemeTaskId])
    }
}

private actor BridgeProductSchemeTaskCensusObservedIds {
    private(set) var recorded: [UUID] = []

    func record(_ id: UUID) {
        recorded.append(id)
    }
}
