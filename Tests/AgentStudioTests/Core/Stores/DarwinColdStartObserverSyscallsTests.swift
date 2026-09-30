import Foundation
import Testing

@testable import AgentStudioCore

/// SR4, SR5; Program Design item 3, stage 2 (amended 2026-09-30): the retry
/// policy `DarwinColdStartObserverSyscalls.readProcessArgumentsBuffer(pid:)`
/// applies after `sysctl(KERN_PROCARGS2)` returns `EIO` -- an intermediate
/// exec racing the read, confirmed empirically against real zmx (30/30 EIO
/// occurrences, 30/30 recovered on the very next read). Exercises the
/// injectable retry loop directly, with a scripted single-read function, so
/// this proves the policy itself without a real process or a real `sysctl`
/// call -- the real syscall path is proven against real zmx in the E2E lane.
@Suite("Darwin cold start observer syscalls")
struct DarwinColdStartObserverSyscallsTests {
    @Test("an EIO read followed by a success returns the successful read's buffer")
    func eioReadFollowedBySuccessReturnsTheSuccessfulReadsBuffer() {
        // Arrange
        var callCount = 0
        let expectedBuffer: [UInt8] = [1, 2, 3]

        // Act
        let result = DarwinColdStartObserverSyscalls.readProcessArgumentsBuffer(
            pid: 4242,
            attempts: 3
        ) { _ in
            callCount += 1
            return callCount == 1 ? .failure(POSIXErrorNumber(EIO)) : .success(expectedBuffer)
        }

        // Assert
        #expect(callCount == 2)
        switch result {
        case .success(let buffer): #expect(buffer == expectedBuffer)
        case .failure: Issue.record("Expected the second, successful read to win")
        }
    }

    @Test("EIO on every attempt exhausts the retry budget and reports the last errno")
    func eioOnEveryAttemptExhaustsTheRetryBudgetAndReportsTheLastErrno() {
        // Arrange
        var callCount = 0

        // Act
        let result = DarwinColdStartObserverSyscalls.readProcessArgumentsBuffer(
            pid: 4242,
            attempts: 3
        ) { _ in
            callCount += 1
            return .failure(POSIXErrorNumber(EIO))
        }

        // Assert: exactly `attempts` calls -- no fourth attempt, no early exit.
        #expect(callCount == 3)
        switch result {
        case .success: Issue.record("Expected every attempt to fail")
        case .failure(let errorNumber): #expect(errorNumber.rawValue == EIO)
        }
    }

    @Test("a successful first read never retries")
    func aSuccessfulFirstReadNeverRetries() {
        // Arrange
        var callCount = 0
        let expectedBuffer: [UInt8] = [9]

        // Act
        let result = DarwinColdStartObserverSyscalls.readProcessArgumentsBuffer(
            pid: 4242,
            attempts: 3
        ) { _ in
            callCount += 1
            return .success(expectedBuffer)
        }

        // Assert
        #expect(callCount == 1)
        switch result {
        case .success(let buffer): #expect(buffer == expectedBuffer)
        case .failure: Issue.record("Expected the first read to succeed")
        }
    }
}
