import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Resize-session policy with the display bound as a plain clamp. The native
/// pointer trace (V-DP-1) remains a separate runtime proof.
@Suite
struct DrawerNormalResizeSessionTests {
    private let ownerPaneId = UUID()
    private let bounds: ClosedRange<CGFloat> = 160...640

    private func clamp(_ height: CGFloat) -> CGFloat {
        min(bounds.upperBound, max(bounds.lowerBound, height))
    }

    private func makeSession(startHeight: CGFloat = 400, startPointerY: CGFloat = 300) -> DrawerNormalResizeSession {
        DrawerNormalResizeSession(
            ownerPaneId: ownerPaneId,
            containerHeight: 800,
            startHeight: startHeight,
            startPointerY: startPointerY
        )
    }

    @Test("Monotonic upward motion grows the height monotonically from the drag-start model")
    func monotonicMotionTracksCumulativeDisplacement() {
        var session = makeSession()
        var previousHeight = session.liveHeight
        for pointerY in stride(from: CGFloat(299), through: 200, by: -7) {
            session.track(pointerY: pointerY, displayedHeight: clamp)
            #expect(session.liveHeight >= previousHeight)
            #expect(session.liveHeight == 400 - (pointerY - 300))
            previousHeight = session.liveHeight
        }
    }

    @Test("Repeating the same pointer sample never moves the edge")
    func repeatedSampleIsStable() {
        var session = makeSession()
        session.track(pointerY: 250, displayedHeight: clamp)
        let height = session.liveHeight
        for _ in 0..<5 {
            session.track(pointerY: 250, displayedHeight: clamp)
        }
        #expect(session.liveHeight == height)
    }

    @Test("Reversing at the upper bound moves the edge immediately")
    func reversalAtBoundTracksImmediately() {
        var session = makeSession()
        // Overshoot 260pt past the 640pt bound (would request 900).
        session.track(pointerY: -200, displayedHeight: clamp)
        #expect(session.liveHeight == 640)

        // First reversal sample of 10pt shrinks by 10pt, not after unwinding overshoot.
        session.track(pointerY: -190, displayedHeight: clamp)
        #expect(session.liveHeight == 630)
    }

    @Test("Reversing at the lower bound moves the edge immediately")
    func reversalAtLowerBoundTracksImmediately() {
        var session = makeSession()
        session.track(pointerY: 800, displayedHeight: clamp)
        #expect(session.liveHeight == 160)

        session.track(pointerY: 790, displayedHeight: clamp)
        #expect(session.liveHeight == 170)
    }

    @Test("A session applies only to its owner and container height")
    func sessionScopedToOwnerAndGeometry() {
        let session = makeSession()
        #expect(session.applies(toOwner: ownerPaneId, containerHeight: 800))
        #expect(!session.applies(toOwner: UUID(), containerHeight: 800))
        #expect(!session.applies(toOwner: ownerPaneId, containerHeight: 700))
    }

    @Test("Commit ratio is the live height over the container height; awaiting commit ignores samples")
    func commitRatioAndAwaitingCommit() {
        var session = makeSession()
        session.track(pointerY: 200, displayedHeight: clamp)
        #expect(session.committedHeightRatio == 500.0 / 800.0)

        session.markAwaitingCommit()
        session.track(pointerY: 100, displayedHeight: clamp)
        #expect(session.liveHeight == 500)
        #expect(session.isAwaitingCommit)
    }
}
