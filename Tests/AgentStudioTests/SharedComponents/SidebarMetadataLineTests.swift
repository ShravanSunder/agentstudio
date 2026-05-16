import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@Suite("SidebarMetadataLine")
struct SidebarMetadataLineTests {
    @Test("metadata line builds with and without icon")
    @MainActor
    func metadataLineBuildsWithAndWithoutIcon() {
        let withIcon = SidebarMetadataLine(iconSystemName: "terminal", text: "Tab 2 · Pane 1")
        let withoutIcon = SidebarMetadataLine(text: "agent-studio")

        #expect(String(describing: type(of: withIcon)).contains("SidebarMetadataLine"))
        #expect(String(describing: type(of: withoutIcon)).contains("SidebarMetadataLine"))
    }

    @Test("no-icon metadata lines stay height bounded in tall containers")
    @MainActor
    func noIconMetadataLinesStayHeightBoundedInTallContainers() throws {
        let bitmap = try renderBitmap(
            VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
                SidebarMetadataLine(text: "filesystem-name")
                SidebarMetadataLine(text: "Tab Tab agent-studio · Pane project-dev")
                SidebarMetadataLine(text: "Output appeared while you were away", prominence: .tertiary)
            }
            .padding(8)
            .frame(width: 320, height: 240, alignment: .topLeading)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            size: CGSize(width: 320, height: 240)
        )

        let verticalSpan = nonBackgroundVerticalSpan(in: bitmap)
        #expect(verticalSpan > 0)
        #expect(verticalSpan < 120)
    }

    @MainActor
    private func renderBitmap<Content: View>(_ view: Content, size: CGSize) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    private func nonBackgroundVerticalSpan(in bitmap: NSBitmapImageRep) -> Int {
        var firstRow: Int?
        var lastRow: Int?

        for y in 0..<bitmap.pixelsHigh {
            if rowContainsForegroundPixel(bitmap, y: y) {
                firstRow = firstRow ?? y
                lastRow = y
            }
        }

        guard let firstRow, let lastRow else { return 0 }
        return lastRow - firstRow
    }

    private func rowContainsForegroundPixel(_ bitmap: NSBitmapImageRep, y: Int) -> Bool {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            if max(red, max(green, blue)) > 0.08 {
                return true
            }
        }
        return false
    }
}
