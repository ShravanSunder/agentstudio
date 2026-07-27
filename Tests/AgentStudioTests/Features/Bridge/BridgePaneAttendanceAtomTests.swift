import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge pane attendance atom")
struct BridgePaneAttendanceAtomTests {
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
