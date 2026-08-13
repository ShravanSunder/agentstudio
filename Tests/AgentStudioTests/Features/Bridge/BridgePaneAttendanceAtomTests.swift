import AgentStudioCore
import Foundation
import Observation
import Testing

@testable import AgentStudioBridge

private final class BridgeAttendanceInvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var invalidationCount: Int { lock.withLock { storedCount } }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}

@MainActor
@Suite("Bridge pane attendance atom")
struct BridgePaneAttendanceAtomTests {
    @Test("observing one pane ignores another pane and wakes for the declared pane")
    func keyedPaneObservationIsIsolated() async {
        let attendance = BridgePaneAttendanceAtom()
        let declaredPaneId = UUID()
        let unrelatedPaneId = UUID()
        let invalidationCounter = BridgeAttendanceInvalidationCounter()

        withObservationTracking {
            _ = attendance.ordinal(for: declaredPaneId)
        } onChange: {
            invalidationCounter.record()
        }

        _ = attendance.record(.paneFocus, for: unrelatedPaneId)
        await Task.yield()
        #expect(invalidationCounter.invalidationCount == 0)

        _ = attendance.record(.paneFocus, for: declaredPaneId)
        await Task.yield()
        #expect(invalidationCounter.invalidationCount == 1)
        #expect(attendance.ordinal(for: declaredPaneId) != nil)
    }

    @Test("every successful attendance record advances the workspace-wide ordinal")
    func successfulAttendanceRecordsAreStrictlyIncreasing() {
        // Arrange
        let attendance = BridgePaneAttendanceAtom()
        let firstPaneId = UUID()
        let secondPaneId = UUID()

        // Act
        let firstOrdinal = attendance.record(.tabActivation, for: firstPaneId)
        let secondOrdinal = attendance.record(.paneFocus, for: secondPaneId)
        let thirdOrdinal = attendance.record(.defaultJump, for: firstPaneId)

        // Assert
        #expect(firstOrdinal < secondOrdinal)
        #expect(secondOrdinal < thirdOrdinal)
        #expect(attendance.ordinal(for: firstPaneId) == thirdOrdinal)
        #expect(attendance.ordinal(for: secondPaneId) == secondOrdinal)
    }

    @Test("attendance exposes successful interactions but no visibility or refresh event")
    func attendanceEventsExcludePassiveVisibilityAndRefresh() {
        // Arrange
        let expectedEvents: Set<BridgePaneAttendanceEvent> = [
            .tabActivation,
            .paneFocus,
            .defaultJump,
            .newTabCreation,
        ]

        // Act
        let supportedEvents = Set(BridgePaneAttendanceEvent.allCases)

        // Assert
        #expect(supportedEvents == expectedEvents)
    }

    @Test("removing a pane discards its attendance without rewinding the ordinal")
    func paneRemovalDiscardsAttendanceWithoutReusingItsOrdinal() {
        // Arrange
        let attendance = BridgePaneAttendanceAtom()
        let removedPaneId = UUID()
        let retainedPaneId = UUID()
        let removedOrdinal = attendance.record(.newTabCreation, for: removedPaneId)

        // Act
        attendance.remove(paneId: removedPaneId)
        let retainedOrdinal = attendance.record(.newTabCreation, for: retainedPaneId)

        // Assert
        #expect(attendance.ordinal(for: removedPaneId) == nil)
        #expect(retainedOrdinal > removedOrdinal)
        #expect(attendance.ordinal(for: retainedPaneId) == retainedOrdinal)
    }

    @Test("ordinal snapshot is an immutable value copy of current attendance")
    func ordinalSnapshotIsValueCopyOfCurrentAttendance() {
        // Arrange
        let attendance = BridgePaneAttendanceAtom()
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let firstOrdinal = attendance.record(.paneFocus, for: firstPaneId)

        // Act
        let snapshot = attendance.ordinalSnapshot()
        _ = attendance.record(.tabActivation, for: secondPaneId)
        attendance.remove(paneId: firstPaneId)

        // Assert
        #expect(snapshot == [firstPaneId: firstOrdinal])
        #expect(attendance.ordinal(for: firstPaneId) == nil)
        #expect(attendance.ordinal(for: secondPaneId) != nil)
    }
}
