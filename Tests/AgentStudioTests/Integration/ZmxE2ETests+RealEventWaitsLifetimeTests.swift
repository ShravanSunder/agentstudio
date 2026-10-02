import AgentStudioInfrastructure
import AgentStudioTestHarness
import Darwin
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

/// N1 (advisor review round 2, Lead 2026-10-02): proves
/// `awaitSessionIdentityOnRealEvent`'s own watched directory descriptor
/// (`ZmxE2ETests+RealEventWaits.swift`) stays open until its dispatch
/// source's cancellation has actually completed -- the same A4-shaped
/// lifetime defect `ColdStartObserverWatchSourceOwnershipTests
/// .directoryDescriptorStaysOpenUntilCancellationCompletes` already proves
/// fixed for the production observer's own directory watch, repeated here
/// in this file's separately-added real-event helper. Before this fix, a
/// bare `defer { close(directoryFileDescriptor) }` ran the instant this
/// function unwound -- immediately after requesting cancellation, not once
/// cancellation had actually completed (`dispatch_source_cancel` is
/// asynchronous, SDK source.h:512).
///
/// Same `testQueue.suspend()` technique as that production test: the
/// underlying `source.resume()` still proceeds regardless of the target
/// queue's suspend state (SDK source.h:745's own registration contract),
/// but the *handler block* -- including the cancel handler that now owns
/// the real close -- cannot run on a suspended queue. That is what lets
/// this test observe "requested, not yet completed" as a real, held-open
/// window instead of racing real kqueue/libdispatch timing.
///
/// `AlwaysAbsentSessionRestoreProbe` always reports the session's socket as
/// absent, so the function under test never resolves an identity on its
/// own and never leaves its directory-event retry loop -- the only
/// suspension it ever reaches is this test's own cancellation.
extension E2ESerializedTests.ZmxE2ETests {
    @Test(
        "awaitSessionIdentityOnRealEvent keeps its watched directory descriptor open until cancellation actually completes"
    )
    func sessionIdentityWaitDescriptorStaysOpenUntilCancellationCompletes() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "zmx-e2e-n1-fd-lifetime-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // R2-5 item 2 (Lead decision 2026-10-02, option c):
        // `awaitSessionIdentityOnRealEvent` now takes a `harness` to reuse
        // its existing settle wait on a transient connect failure. This
        // fake probe never throws one, so this harness is never actually
        // called into -- constructed only to satisfy the parameter, and
        // cleaned up the same way `withRealBackend` does.
        let harness = await ZmxTestHarness()
        defer { Task { await harness.cleanup() } }

        let testQueue = DispatchQueue(label: "zmx-e2e-n1-test-queue", qos: .userInitiated)
        testQueue.suspend()

        let openSource = LocalFactSource(vocabulary: Self.fileDescriptorFactVocabulary())
        let openRecorder = try openSource.attach()
        let closeSource = LocalFactSource(vocabulary: Self.fileDescriptorFactVocabulary())
        let closeRecorder = try closeSource.attach()
        let openSink = openSource.sink
        let closeSink = closeSource.sink
        // R3-3 item 2 (review round 3, Lead decision 2026-10-02): a signal
        // for "this function's own unwind reached eventSource.cancel()" --
        // see `awaitSessionIdentityOnRealEvent`'s own doc comment. Without
        // awaiting this, the old assertion below ("still open while
        // pending") was true in both the fixed and the regressed
        // implementation at that exact instant, simply because neither
        // one's teardown had run yet -- not a discriminating oracle.
        let cancellationRequestedSource = LocalFactSource(
            vocabulary: FactVocabulary<String, Void>(
                describeScope: { $0 },
                describeFact: { _ in "cancellation requested" },
                isClosing: { _, _ in true }
            ))
        let cancellationRequestedRecorder = try cancellationRequestedSource.attach()
        let cancellationRequestedSink = cancellationRequestedSource.sink

        let task = Task {
            try await self.awaitSessionIdentityOnRealEvent(
                .generateUUIDv7(),
                harness: harness,
                backend: AlwaysAbsentSessionRestoreProbe(),
                zmxDirectory: temporaryDirectory.path,
                queue: testQueue,
                directoryOpenFactSink: { descriptor in openSink("opened", descriptor) },
                directoryCloseFactSink: { descriptor in closeSink("closed", descriptor) },
                cancellationRequestedFactSink: { cancellationRequestedSink("cancelled", ()) }
            )
        }

        // R2-4 item 4's own technique: this fact fires synchronously, right
        // after `open()` succeeds, with no suspension point between there
        // and `eventSource.resume()` below it -- by the time this returns,
        // the watch source has unconditionally already been constructed
        // and resumed.
        let watchedDescriptor = try await openRecorder.expectNext(in: "opened", where: { _ in true }, "directory open")
        #expect(fcntl(watchedDescriptor, F_GETFD) != -1, "the descriptor must be open right after opening")

        task.cancel()

        // Awaited before asserting "still open": `dispatch_source_cancel`
        // is non-blocking (source.h:512), so this fires once the function
        // has processed cancellation and called it, independent of
        // `testQueue` still being suspended -- the actual close is queued
        // on that suspended queue's cancel handler and cannot have run
        // yet. A regressed bare `defer { close(...) }` would already have
        // closed the descriptor by the time this same fact fires.
        _ = try await cancellationRequestedRecorder.expectNext(
            in: "cancelled", where: { _ in true }, "cancellation requested")
        #expect(
            fcntl(watchedDescriptor, F_GETFD) != -1,
            "the descriptor must stay open while cancellation is pending")

        // Free the queue so the cancel handler can actually run, then await
        // the real close as a fact instead of a queue-drain proxy for it.
        testQueue.resume()
        let closedDescriptor = try await closeRecorder.expectNext(in: "closed", where: { _ in true }, "directory close")
        #expect(closedDescriptor == watchedDescriptor, "the cancel handler must close exactly the descriptor it owns")

        do {
            _ = try await task.value
            Issue.record("expected the cancelled wait to throw CancellationError")
        } catch is CancellationError {
            // Expected: `recorder.expectNext` inside the function propagates
            // the cancellation this test requested above.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }

        let statResult = fcntl(closedDescriptor, F_GETFD)
        let statErrno = errno
        #expect(statResult == -1)
        #expect(statErrno == EBADF, "an fcntl failure on a closed descriptor must be exactly EBADF")
    }

    /// Carries the real file descriptor number as its fact value, so this
    /// test can assert identity ("closed exactly the one it opened"), not
    /// merely "some open/close happened." Two separate `LocalFactSource`
    /// instances (one per call site above) rather than one shared source
    /// with two scopes, matching `ColdStartObserverTests.ScriptedSyscalls`'s
    /// own `directoryOpenCallFactSink`/`directoryCloseCallFactSink` pair.
    private static func fileDescriptorFactVocabulary() -> FactVocabulary<String, Int32> {
        FactVocabulary(
            describeScope: { $0 },
            describeFact: { "fd=\($0)" },
            isClosing: { _, _ in false }
        )
    }
}

/// Always reports the session's own socket endpoint as absent, so
/// `awaitSessionIdentityOnRealEvent` never resolves an identity on its own
/// -- every suspension inside it is this test's own cancellation, never a
/// real daemon settling. Matches the established `ZmxSessionRestoreProbing`
/// fake shape already used by `HeldZmxSessionRestoreProbe`
/// (`WorkspacePreparedContentMountCoordinatorRestoreProbeIndependenceTests.swift`).
private final class AlwaysAbsentSessionRestoreProbe: ZmxSessionRestoreProbing, @unchecked Sendable {
    func discoverSessionInventory() async -> ZmxSessionInventory { .complete([:]) }
    func observeSessionIdentity(_ sessionID: ZmxSessionID) async throws -> Data? { nil }
}
