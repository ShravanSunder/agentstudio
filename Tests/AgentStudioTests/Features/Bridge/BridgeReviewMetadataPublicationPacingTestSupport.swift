import Foundation

@testable import AgentStudioBridge

actor PausingReviewLifecycleRecorder: BridgeProductMetadataLifecycleTraceRecording {
    struct Fixture {
        let pausedEvents: AsyncStream<Void>
        let recorder: PausingReviewLifecycleRecorder
        let releaseContinuation: AsyncStream<Void>.Continuation
    }

    private var didPauseAfterWindowEnqueue = false
    private let pausedContinuation: AsyncStream<Void>.Continuation
    private let releaseEvents: AsyncStream<Void>

    private init(
        pausedContinuation: AsyncStream<Void>.Continuation,
        releaseEvents: AsyncStream<Void>
    ) {
        self.pausedContinuation = pausedContinuation
        self.releaseEvents = releaseEvents
    }

    static func make() -> Fixture {
        let (pausedEvents, pausedContinuation) = AsyncStream<Void>.makeStream()
        let (releaseEvents, releaseContinuation) = AsyncStream<Void>.makeStream()
        return Fixture(
            pausedEvents: pausedEvents,
            recorder: Self(
                pausedContinuation: pausedContinuation,
                releaseEvents: releaseEvents
            ),
            releaseContinuation: releaseContinuation
        )
    }

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) async {
        guard event.subscriptionKind == .reviewMetadata,
            event.stage == .windowEnqueued,
            !didPauseAfterWindowEnqueue
        else { return }
        didPauseAfterWindowEnqueue = true
        pausedContinuation.yield()
        var releaseIterator = releaseEvents.makeAsyncIterator()
        _ = await releaseIterator.next()
    }

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) {}
}
