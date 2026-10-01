import AgentStudioInfrastructure
import AgentStudioTestHarness
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal

/// F7 (review round 1): real-event waits for R1's own new test cases in
/// `ZmxE2ETests.swift`, split into its own file (the repo's line-length
/// ceiling, same precedent as `ZmxE2ETests+ForcedTiming.swift`) rather than
/// the legacy deadline/yield helpers they replace, which stay in place,
/// unmodified, for that file's earlier inherited tests.
extension E2ESerializedTests.ZmxE2ETests {
    /// A real-event read-arrival wait for R1's own option-A cases, replacing
    /// `waitForObservedSessionIdentity`'s deadline/yield poll (kept,
    /// unmodified, in `ZmxE2ETests.swift`, for that file's earlier
    /// inherited tests). `ZmxBackend.observeSessionIdentity` is a thin
    /// wrapper over the identical `ZmxSessionControl.observe(path:bootID:)`
    /// syscall `ZmxTestHarness.waitForSessionSocket`'s own real vnode watch
    /// already proves out for socket existence -- confirmed by reading
    /// `ZmxBackend.observeSessionIdentity` directly. Registers a watch on
    /// the same zmx directory, then retries the same four transient
    /// failures `waitForObservedSessionIdentity` already tolerates only on
    /// the next real event, never a sleep or a yield loop. Any other
    /// failure propagates immediately, exactly as the legacy helper's own
    /// uncaught case already does.
    func observeSessionIdentityOnRealEvent(
        _ sessionID: ZmxSessionID, backend: ZmxBackend, zmxDirectory: String
    ) async throws -> Data {
        let directoryFileDescriptor = open(zmxDirectory, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else { throw ZmxSessionControlFailure.unavailable }
        defer { close(directoryFileDescriptor) }

        while true {
            do {
                if let identity = try await backend.observeSessionIdentity(sessionID) {
                    return identity
                }
            } catch ZmxSessionControlFailure.unavailable, ZmxSessionControlFailure.connectionRefused,
                ZmxSessionControlFailure.processUnverifiable, ZmxSessionControlFailure.timeout
            {
                // Transient -- fall through to wait for the next real event.
            }
            try await awaitNextZmxDirectoryEvent(fileDescriptor: directoryFileDescriptor)
        }
    }

    /// One real vnode event on an open zmx-directory descriptor, or this
    /// task's own cancellation -- never a sleep or a yield. Shares
    /// `ZmxTestHarness.awaitSessionSocketEvent`'s register-then-check-free
    /// shape: the caller already did its own synchronous check before
    /// calling this, so this function only ever needs to wait.
    func awaitNextZmxDirectoryEvent(fileDescriptor: Int32) async throws {
        let step = HeldStep<Void>("zmx directory event")
        let eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        eventSource.setEventHandler {
            eventSource.cancel()
            // A raw GCD callback on .global(), not inside a Swift Task.
            try? step.arriveBlocking(())
        }
        eventSource.setCancelHandler {}
        eventSource.resume()
        defer { eventSource.cancel() }
        _ = try await step.firstArrival()
        step.release()
    }

    /// The repo's own `awaitProcessExit` (`AgentStudioTestHarness/ProcessExitWait.swift`)
    /// isn't usable here -- it calls `process.run()` itself, and this call
    /// site's `process` is already running (started by
    /// `spawnColdRestoreSessionWithoutWaitingForSettlement`). `process.waitUntilExit()`
    /// spins the calling thread's run loop and exit delivery goes to the
    /// launching thread's -- the exact hazard `awaitProcessExit`'s own doc
    /// comment names, confirmed by reading it directly. This is that same
    /// function's await half only, minus the launch, against a process
    /// already in flight.
    func awaitAlreadyRunningProcessExit(_ process: Process) async throws -> Int32 {
        // Register-then-check: the process may have already exited in the
        // gap between its caller spawning it and this call, and a handler
        // set after that exit is not guaranteed to fire for it.
        // `pendingContinuation`'s extract-and-clear makes whichever of the
        // handler or the synchronous already-exited check runs first the
        // only one that resumes -- the same exactly-once guard
        // `awaitProcessExit` itself uses. F7 follow-up (Lead 2026-10-01): a
        // local named function captured by `Process.terminationHandler`'s
        // own `@Sendable` closure type isn't itself provably `Sendable`, so
        // the extract-and-clear runs inline at each `withLock` call instead
        // of through a named `takePendingContinuation()`.
        let pendingContinuation = Mutex<CheckedContinuation<Int32, any Error>?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                pendingContinuation.withLock { $0 = continuation }
                process.terminationHandler = { exitedProcess in
                    pendingContinuation.withLock { $0.take() }?.resume(returning: exitedProcess.terminationStatus)
                }
                if !process.isRunning {
                    process.terminationHandler = nil
                    pendingContinuation.withLock { $0.take() }?.resume(returning: process.terminationStatus)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// F7 (review round 1): read-arrival for the attach client's own real
    /// output, replacing a deadline/50ms poll against `zmx history` (the
    /// now-deleted `ZmxTestHarness.waitForSessionHistory` -- Lead
    /// 2026-10-01: zero callers left once this replaced it) in R1's two
    /// option-A cases that must observe a fallback script's restore
    /// notice. `zmx history` reads no file --
    /// confirmed against zmx's own source at the pinned commit: it answers
    /// over the session's control socket from the daemon's in-memory
    /// terminal state (main.zig:1377-1437, loop.zig:1129-1146) -- so there
    /// is no filesystem event for the notice either, and the attach
    /// client's own stdout (captured via `spawnShellCommandCapturingOutput`,
    /// not the nulled default) is the real one this suite can watch
    /// instead. Searches raw accumulated bytes, not decoded lines: terminal
    /// escape sequences can surround the marker text. `FileHandle
    /// .readabilityHandler` dispatches off the cooperative pool entirely --
    /// never a blocking read inside a Swift Task. EOF before the marker
    /// arrives is the correlated negative end: the process closed its
    /// stdout, so whatever it was going to print has already arrived or
    /// never will, and this throws instead of hanging past it. No deadline
    /// beyond the suite's own runner-owned hang bound.
    func awaitMarkerInProcessOutput(pipe: Pipe, marker: String) async throws {
        let markerBytes = Data(marker.utf8)
        // F7 follow-up (Lead 2026-10-01): same inline extract-and-clear as
        // `awaitAlreadyRunningProcessExit` -- a named local function
        // captured by `FileHandle.readabilityHandler`'s own `@Sendable`
        // closure type isn't provably `Sendable`.
        let pendingContinuation = Mutex<CheckedContinuation<Void, any Error>?>(nil)
        let accumulated = Mutex<Data>(Data())

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                pendingContinuation.withLock { $0 = continuation }
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        pendingContinuation.withLock { $0.take() }?.resume(
                            throwing: ProcessOutputMarkerWaitFailure.reachedEOFWithoutMarker)
                        return
                    }
                    let foundMarker = accumulated.withLock { stored -> Bool in
                        stored.append(chunk)
                        return stored.contains(markerBytes)
                    }
                    if foundMarker {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        pendingContinuation.withLock { $0.take() }?.resume()
                    }
                }
            }
        } onCancel: {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }
}

/// F7 follow-up (Lead 2026-10-01): a minimal, file-local extract-and-clear
/// convenience -- `$0.take()` inside a `Mutex.withLock` closure reads the
/// stored value and leaves `nil` behind in one step, used by
/// `awaitAlreadyRunningProcessExit` and `awaitMarkerInProcessOutput` to keep
/// their exactly-once continuation resolution inline instead of through a
/// named local function (not provably `Sendable` when captured by another
/// `@Sendable` closure, such as `Process.terminationHandler`'s or
/// `FileHandle.readabilityHandler`'s own).
extension Optional {
    fileprivate mutating func take() -> Wrapped? {
        let value = self
        self = nil
        return value
    }
}

/// Thrown by `awaitMarkerInProcessOutput` when a process's stdout reaches
/// EOF before the expected marker ever appeared in it.
enum ProcessOutputMarkerWaitFailure: Error {
    case reachedEOFWithoutMarker
}
