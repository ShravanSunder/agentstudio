import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneLeafContainerInactiveDimmingTests {
    @Test("inactive split panes keep the center brighter than the edge dimming band")
    func inactiveSplitPane_centerStaysBrighterThanEdgeBand() throws {
        let view = ZStack {
            Color.white
            InactivePaneEdgeDimmingOverlay()
        }

        let bitmap = try renderBitmap(
            for: view,
            size: CGSize(width: 360, height: 280)
        )

        let centerX = 180
        let sampleY = 140
        let edgeX = 12
        let innerBandX = max(edgeX + 12, Int(AppStyles.Shell.PaneChrome.inactivePaneDimmingDepth) - 20)
        let cornerX = 20
        let cornerY = 20

        let centerBrightness = try brightness(in: bitmap, x: centerX, y: sampleY)
        let edgeBrightness = try brightness(in: bitmap, x: edgeX, y: sampleY)
        let innerBandBrightness = try brightness(in: bitmap, x: innerBandX, y: sampleY)
        let cornerBrightness = try brightness(in: bitmap, x: cornerX, y: cornerY)

        #expect(centerBrightness > edgeBrightness + 0.08)
        #expect(edgeBrightness < 0.85)
        #expect(centerBrightness > innerBandBrightness + 0.02)
        #expect(cornerBrightness > edgeBrightness - 0.03)
    }

    private func renderBitmap<ContentView: View>(
        for view: ContentView,
        size: CGSize
    ) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw RenderingError.bitmapUnavailable
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    private func brightness(
        in bitmap: NSBitmapImageRep,
        x: Int,
        y: Int
    ) throws -> CGFloat {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            throw RenderingError.pixelUnavailable(x: x, y: y)
        }

        return ((color.redComponent + color.greenComponent + color.blueComponent) / 3.0)
    }
}

private enum RenderingError: Error {
    case bitmapUnavailable
    case pixelUnavailable(x: Int, y: Int)
}
