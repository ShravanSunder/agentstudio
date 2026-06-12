import AppKit
import Testing

@testable import AgentStudio

@Suite("GhosttySurfaceView content scale")
struct GhosttySurfaceViewContentScaleTests {
    @Test("content scale derives independent x and y backing ratios")
    func contentScaleDerivesIndependentBackingRatios() {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let backingFrame = NSRect(x: 0, y: 0, width: 800, height: 300)

        let scale = Ghostty.SurfaceView.backingContentScale(
            frame: frame,
            backingFrame: backingFrame
        )

        #expect(scale?.x == 2)
        #expect(scale?.y == 1.5)
    }

    @Test("content scale rejects zero logical dimensions")
    func contentScaleRejectsZeroLogicalDimensions() {
        let frame = NSRect(x: 0, y: 0, width: 0, height: 200)
        let backingFrame = NSRect(x: 0, y: 0, width: 800, height: 300)

        let scale = Ghostty.SurfaceView.backingContentScale(
            frame: frame,
            backingFrame: backingFrame
        )

        #expect(scale == nil)
    }

    @Test("content scale rejects zero backing dimensions")
    func contentScaleRejectsZeroBackingDimensions() {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let backingFrame = NSRect(x: 0, y: 0, width: 0, height: 300)

        let scale = Ghostty.SurfaceView.backingContentScale(
            frame: frame,
            backingFrame: backingFrame
        )

        #expect(scale == nil)
    }

    @Test("content scale rejects non-finite dimensions")
    func contentScaleRejectsNonFiniteDimensions() {
        let frame = NSRect(x: 0, y: 0, width: CGFloat.infinity, height: 200)
        let backingFrame = NSRect(x: 0, y: 0, width: 800, height: 300)

        let scale = Ghostty.SurfaceView.backingContentScale(
            frame: frame,
            backingFrame: backingFrame
        )

        #expect(scale == nil)
    }
}
