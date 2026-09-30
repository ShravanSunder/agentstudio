import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

/// SR4, SR5; Program Design item 3: `ColdStartObserver`'s total outcome and
/// its two settlement paths that don't need a real process or a real zmx
/// daemon -- `reportAttachClientExited()` racing an in-progress discovery,
/// and the `.unobservable` cases the plan explicitly sanctions injecting "at
/// the Darwin call boundary with a test double of the syscall wrapper only."
/// The real discovery/handoff paths against a real socket and a real
/// process are proven separately, with real zmx, in the E2E lane.
@Suite("Cold start observer")
struct ColdStartObserverTests {
    private final class ScriptedSyscalls: ColdStartObserverSyscalls, @unchecked Sendable {
        var directoryOpenResult: Result<Int32, POSIXErrorNumber> = .failure(POSIXErrorNumber(EACCES))
        var processArgumentsResult: Result<[UInt8], POSIXErrorNumber> = .failure(POSIXErrorNumber(ESRCH))

        func openDirectoryForWatching(path: String) -> Result<Int32, POSIXErrorNumber> {
            directoryOpenResult
        }

        func readProcessArgumentsBuffer(pid: Int32) -> Result<[UInt8], POSIXErrorNumber> {
            processArgumentsResult
        }
    }

    @Test("a directory-watch registration failure settles unobservable, carrying the injected errno")
    func registrationFailureSettlesUnobservable() async throws {
        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .failure(POSIXErrorNumber(EACCES))
        let observer = ColdStartObserver(syscalls: syscalls)

        let outcome = await observer.observeColdStart(
            zmxDirectory: URL(filePath: "/does/not/matter"),
            socketPath: "/does/not/matter/session",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .unobservable(.watchRegistrationFailed(errno: EACCES)))
    }

    @Test("reportAttachClientExited settles a still-pending discovery as failed, never touching exit status")
    func attachClientExitSettlesPendingDiscoveryAsFailed() async throws {
        // A real, harmless directory whose socket never appears: proves the
        // real kqueue registration path doesn't hang or crash, while the
        // race is decided deterministically because discovery genuinely
        // cannot complete on its own here.
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let observer = ColdStartObserver()

        let observationTask = Task {
            await observer.observeColdStart(
                zmxDirectory: temporaryDirectory,
                socketPath: temporaryDirectory.appending(path: "never-appears").path,
                bootID: "test-boot-id",
                attemptID: ColdRestoreAttemptID.generate()
            )
        }
        await observer.reportAttachClientExited()

        let outcome = await observationTask.value

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    @Test(
        "reportAttachClientExited racing ahead of observeColdStart itself is not a crash -- observeColdStart returns the pre-settled outcome"
    )
    func attachClientExitBeforeObserveColdStartIsNotACrash() async throws {
        let observer = ColdStartObserver()

        await observer.reportAttachClientExited()
        let outcome = await observer.observeColdStart(
            zmxDirectory: URL(filePath: "/does/not/matter"),
            socketPath: "/does/not/matter/session",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    @Test("a second reportAttachClientExited after settlement is a no-op, not a double-resume")
    func secondReportAfterSettlementIsANoOp() async throws {
        let observer = ColdStartObserver()

        await observer.reportAttachClientExited()
        let outcome = await observer.observeColdStart(
            zmxDirectory: URL(filePath: "/does/not/matter"),
            socketPath: "/does/not/matter/session",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )
        // Would trap (double resume of a CheckedContinuation) if settle()
        // weren't idempotent.
        await observer.reportAttachClientExited()

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    @Test("cancel settles a still-pending discovery without hanging its awaiter")
    func cancelSettlesPendingDiscoveryWithoutHanging() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-cancel-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let observer = ColdStartObserver()

        let observationTask = Task {
            await observer.observeColdStart(
                zmxDirectory: temporaryDirectory,
                socketPath: temporaryDirectory.appending(path: "never-appears").path,
                bootID: "test-boot-id",
                attemptID: ColdRestoreAttemptID.generate()
            )
        }
        await observer.cancel()

        // The awaiter is unblocked; the specific outcome value carries no
        // meaning the caller of cancel() should act on (see cancel()'s doc).
        _ = await observationTask.value
    }
}
