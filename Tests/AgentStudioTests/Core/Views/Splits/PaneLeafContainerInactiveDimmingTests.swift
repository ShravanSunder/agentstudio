import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneLeafContainerInactiveDimmingTests {
    @Test("inactive split panes keep the center brighter than the edge dimming band")
    func inactiveSplitPane_centerStaysBrighterThanEdgeBand() throws {
        try withTestAtomStore { _ in
            let paneId = UUID()
            let paneHost = PaneHostView(paneId: paneId)
            paneHost.mountContentView(WhiteMountedContentView())

            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-inactive-pane-dimming-\(UUID().uuidString)")
            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
            store.restore()
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let dispatcher = PaneTabActionDispatcher(
                dispatch: { _ in },
                shouldAcceptDrop: { _, _, _ in false },
                handleDrop: { _, _, _ in }
            )

            let view = PaneLeafContainer(
                paneHost: paneHost,
                tabId: UUID(),
                isActive: false,
                isSplit: true,
                isSplitResizing: false,
                store: store,
                repoCache: RepoCacheAtom(),
                closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
                actionDispatcher: dispatcher,
                onOpenPaneGitHub: { _ in }
            )

            let bitmap = try renderBitmap(
                for: view,
                size: CGSize(width: 360, height: 280)
            )

            let centerX = 180
            let sampleY = 140
            let edgeX = 12
            let innerBandX = max(edgeX + 12, Int(AppStyle.inactivePaneDimmingDepth) - 20)

            let centerBrightness = try brightness(in: bitmap, x: centerX, y: sampleY)
            let edgeBrightness = try brightness(in: bitmap, x: edgeX, y: sampleY)
            let innerBandBrightness = try brightness(in: bitmap, x: innerBandX, y: sampleY)

            #expect(centerBrightness > edgeBrightness + 0.08)
            #expect(edgeBrightness < 0.85)
            #expect(centerBrightness > innerBandBrightness + 0.02)
        }
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

@MainActor
private final class WhiteMountedContentView: NSView, PaneMountedContent {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func setContentInteractionEnabled(_: Bool) {}
}

private enum RenderingError: Error {
    case bitmapUnavailable
    case pixelUnavailable(x: Int, y: Int)
}
