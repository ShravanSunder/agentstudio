import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Workspace undo journal clock")
struct WorkspaceUndoJournalClockTests {
    @Test("kernel clock reads retain boot identity and advance continuous uptime")
    func currentKernelClockIsStable() async throws {
        let first = try await WorkspaceUndoJournalClock.current()
        let second = try await WorkspaceUndoJournalClock.current()
        #expect(!first.bootID.isEmpty)
        #expect(UUID(uuidString: first.bootID) != nil)
        #expect(second.bootID == first.bootID)
        #expect(second.uptimeNanoseconds >= first.uptimeNanoseconds)
        #expect(first.utc.timeIntervalSince1970.isFinite)
    }

    @Test("timebase conversion uses checked integer arithmetic")
    func timebaseConversion() throws {
        #expect(try WorkspaceUndoJournalClock.nanoseconds(ticks: 48, numerator: 125, denominator: 3) == 2000)
        #expect(throws: WorkspaceUndoJournalFailure.invalidClock) {
            try WorkspaceUndoJournalClock.nanoseconds(ticks: UInt64.max, numerator: 125, denominator: 3)
        }
        #expect(throws: WorkspaceUndoJournalFailure.invalidClock) {
            try WorkspaceUndoJournalClock.nanoseconds(ticks: 48, numerator: 1, denominator: 0)
        }
    }

    @Test("nonfinite wall-clock evidence is rejected before journaling")
    func nonfiniteWallClockIsRejected() {
        #expect(throws: WorkspaceUndoJournalFailure.invalidClock) {
            try validateUndoJournalTime(
                .init(
                    utc: Date(timeIntervalSince1970: .infinity),
                    bootID: "boot-fixture", uptimeNanoseconds: 100))
        }
    }
}
