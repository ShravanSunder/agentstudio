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
    ///
    /// Architecture lint follow-up (Lead 2026-10-01): merged with the former
    /// `awaitNextZmxDirectoryEvent` into this one function, renamed to match
    /// what it returns. `IndependentLeaderExecWitness`
    /// (`ZmxE2ETests+ForcedTiming.swift`) is the precedent this follows: the
    /// directory watch's event handler only sinks a fact through
    /// `LocalFactSource` (synchronous, never a Task, matching
    /// `FactRecorder.append`'s own "the owner calls this synchronously; it
    /// never creates a task" contract) -- no `HeldStep`, which parks its
    /// caller until a test-side `release()`/`fail()`/`retire()` and is not a
    /// one-shot event primitive, and no hand-built continuation. The retry
    /// loop (try the real check, then wait for the next event fact on a
    /// miss) stays entirely in this function's own async context: nothing
    /// async runs inside the GCD event handler. The session identity this
    /// loop was built to find IS the value that satisfies it, so this
    /// function returns it directly and every caller asserts on that
    /// returned identity.
    func awaitSessionIdentityOnRealEvent(
        _ sessionID: ZmxSessionID, backend: ZmxBackend, zmxDirectory: String
    ) async throws -> Data {
        let directoryFileDescriptor = open(zmxDirectory, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else { throw ZmxSessionControlFailure.unavailable }
        defer { close(directoryFileDescriptor) }

        let scope = "zmxDirectoryEvent"
        let source = LocalFactSource(
            vocabulary: FactVocabulary<String, Void>(
                describeScope: { $0 },
                describeFact: { _ in "directory event" },
                // Never closing: the retry loop below may need more than one
                // directory-event fact before `backend.observeSessionIdentity`
                // finally succeeds, and nothing in this fact stream itself
                // marks the last one -- that decision is external to it. A
                // closing vocabulary here would make the second fact at this
                // scope a reported violation (FactRecorder's own
                // FactAfterClose), matching `IndependentLeaderExecWitness`'s
                // (ZmxE2ETests+ForcedTiming.swift) non-closing vocabulary for
                // the same reason.
                isClosing: { _, _ in false }
            )
        )
        let recorder = try source.attach()
        let sink = source.sink

        let eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        eventSource.setEventHandler {
            // A raw GCD callback on .global(), not inside a Swift Task;
            // LocalFactSource.sink is synchronous and safe here. Never
            // cancelled from inside the handler: this watch must keep
            // firing across every retry, not just the first.
            sink(scope, ())
        }
        eventSource.setCancelHandler {}
        eventSource.resume()
        defer { eventSource.cancel() }

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
            _ = try await recorder.expectNext(in: scope, where: { _ in true }, "zmx directory event")
        }
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
    ///
    /// Architecture lint follow-up (Lead 2026-10-01): register-then-check
    /// against a `LocalFactSource`/`FactRecorder` pair instead of a
    /// hand-built `CheckedContinuation`. `Process.terminationHandler` only
    /// sinks the exit status fact -- synchronous, never a Task -- and
    /// `recorder.expectNext(in:where:_:)` returns that fact's value
    /// directly, so the exit status IS what this wait returns. An
    /// already-exited process is reported straight from the synchronous
    /// check below, with no detour through the fact source at all.
    func awaitAlreadyRunningProcessExit(_ process: Process) async throws -> Int32 {
        let scope = "already-running process exit"
        let source = LocalFactSource(
            vocabulary: FactVocabulary<String, Int32>(
                describeScope: { $0 },
                describeFact: { "exit status \($0)" },
                isClosing: { _, _ in true }
            )
        )
        let recorder = try source.attach()
        let sink = source.sink

        process.terminationHandler = { exitedProcess in
            // Process.terminationHandler runs on an arbitrary queue, not
            // inside a Swift Task; LocalFactSource.sink is synchronous and
            // safe here.
            sink(scope, exitedProcess.terminationStatus)
        }
        // Register-then-check: the process may have already exited in the
        // gap between its caller spawning it and this call, and a handler
        // set after that exit is not guaranteed to fire for it.
        if !process.isRunning {
            process.terminationHandler = nil
            return process.terminationStatus
        }
        return try await withTaskCancellationHandler {
            try await recorder.expectNext(in: scope, where: { _ in true }, "process exit status")
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
    ///
    /// Architecture lint follow-up (Lead 2026-10-01): register-then-check
    /// against a `LocalFactSource`/`FactRecorder` pair instead of a
    /// hand-built `CheckedContinuation`. The readability handler only sinks
    /// an observation fact -- synchronous, never a Task -- and
    /// `recorder.expectNext(in:where:_:)` returns that fact's value
    /// directly: the accumulated bytes through the marker ARE the value
    /// that satisfied this wait, so this function returns them and every
    /// caller asserts on that returned snapshot instead of a later,
    /// separately-timed read.
    func awaitMarkerInProcessOutput(pipe: Pipe, marker: String) async throws -> Data {
        let markerBytes = Data(marker.utf8)
        let accumulated = Mutex<Data>(Data())
        let scope = "process output contains marker"
        let source = LocalFactSource(
            vocabulary: FactVocabulary<String, ProcessOutputMarkerObservation>(
                describeScope: { $0 },
                describeFact: { observation in
                    switch observation {
                    case .markerFound(let data): return "marker found in \(data.count) bytes"
                    case .reachedEOFWithoutMarker: return "reached EOF without the marker"
                    }
                },
                isClosing: { _, _ in true }
            )
        )
        let recorder = try source.attach()
        let sink = source.sink

        pipe.fileHandleForReading.readabilityHandler = { handle in
            // FileHandle.readabilityHandler dispatches off the cooperative
            // pool entirely, not inside a Swift Task; LocalFactSource.sink
            // is synchronous and safe here.
            let chunk = handle.availableData
            if chunk.isEmpty {
                pipe.fileHandleForReading.readabilityHandler = nil
                sink(scope, .reachedEOFWithoutMarker)
                return
            }
            let (foundMarker, capturedSoFar) = accumulated.withLock { stored -> (Bool, Data) in
                stored.append(chunk)
                return (stored.contains(markerBytes), stored)
            }
            if foundMarker {
                pipe.fileHandleForReading.readabilityHandler = nil
                sink(scope, .markerFound(capturedSoFar))
            }
        }

        return try await withTaskCancellationHandler {
            let observation = try await recorder.expectNext(
                in: scope, where: { _ in true }, "process output marker observation")
            switch observation {
            case .markerFound(let data):
                return data
            case .reachedEOFWithoutMarker:
                throw ProcessOutputMarkerWaitFailure.reachedEOFWithoutMarker
            }
        } onCancel: {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }
}

/// What `awaitMarkerInProcessOutput`'s readability handler observed: either
/// the marker arrived (carrying the bytes accumulated through it) or the
/// process's stdout reached EOF first.
private enum ProcessOutputMarkerObservation: Sendable {
    case markerFound(Data)
    case reachedEOFWithoutMarker
}

/// Thrown by `awaitMarkerInProcessOutput` when a process's stdout reaches
/// EOF before the expected marker ever appeared in it.
enum ProcessOutputMarkerWaitFailure: Error {
    case reachedEOFWithoutMarker
}
