import Foundation
import Testing

@testable import AgentStudio

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
}
