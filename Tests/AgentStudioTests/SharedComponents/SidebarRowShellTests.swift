import AgentStudioInfrastructure
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

@Suite("SidebarRowShell")
struct SidebarRowShellTests {
    @Test("row shell renders clear and active background states")
    @MainActor
    func rowShellRendersAllVisualStates() throws {
        let normal = try renderRowBackgroundPixel(isSelected: false, isFlashing: false, isHovering: false)
        let selected = try renderRowBackgroundPixel(isSelected: true, isFlashing: false, isHovering: false)
        let flashing = try renderRowBackgroundPixel(isSelected: false, isFlashing: true, isHovering: false)
        let hovering = try renderRowBackgroundPixel(isSelected: false, isFlashing: false, isHovering: true)

        #expect(normal.redComponent < 0.02)
        #expect(normal.greenComponent < 0.02)
        #expect(normal.blueComponent < 0.02)
        #expect(pixelDiffers(selected, from: normal))
        #expect(pixelDiffers(flashing, from: normal))
        #expect(pixelDiffers(hovering, from: normal))
    }

    @Test("selected and flashing fill use sidebar selected token")
    @MainActor
    func selectedAndFlashingFillUseSidebarSelectedToken() {
        let selectedFill = SidebarRowShell<Text>.backgroundColor(
            isSelected: true,
            isFlashing: false,
            isHovering: false
        )
        let flashingFill = SidebarRowShell<Text>.backgroundColor(
            isSelected: false,
            isFlashing: true,
            isHovering: false
        )

        #expect(selectedFill == AppStyles.General.Accent.primaryColor.opacity(AppStyles.General.Fill.active))
        #expect(flashingFill == AppStyles.General.Accent.primaryColor.opacity(AppStyles.General.Fill.selected))
    }

    @Test("hover fill matches RepoExplorer accent hover policy")
    @MainActor
    func hoverFillMatchesRepoExplorerAccentHoverPolicy() {
        let hoverFill = SidebarRowShell<Text>.backgroundColor(
            isSelected: false,
            isFlashing: false,
            isHovering: true
        )

        #expect(
            hoverFill == AppStyles.General.Accent.primaryColor.opacity(AppStyles.Shell.Sidebar.rowHoverOpacity)
        )
    }

    @Test("content padding and radius match RepoExplorer row chrome policy")
    @MainActor
    func contentPaddingAndRadiusMatchRepoExplorerRowChromePolicy() {
        #expect(SidebarRowShell<Text>.chromePolicy == .sidebarRowShell)
        #expect(SidebarRowShell<Text>.contentVerticalInset == AppStyles.Shell.Sidebar.rowVerticalInset)
        #expect(SidebarRowShell<Text>.contentHorizontalInset == AppStyles.Shell.Sidebar.rowHorizontalInset)
        #expect(SidebarRowShell<Text>.rowCornerRadius == AppStyles.Shell.Sidebar.rowCornerRadius)
    }

    @MainActor
    private func renderRowBackgroundPixel(
        isSelected: Bool,
        isFlashing: Bool,
        isHovering: Bool
    ) throws -> NSColor {
        let size = CGSize(width: 320, height: 48)
        let row = SidebarRowShell(
            isSelected: isSelected,
            isFlashing: isFlashing,
            isHovering: isHovering
        ) {
            Text("Sidebar row").frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)

        let hostingView = NSHostingView(rootView: row)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let scaleX = CGFloat(bitmap.pixelsWide) / size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / size.height
        let sampleX = Int((size.width - SidebarRowShell<Text>.contentHorizontalInset / 2) * scaleX)
        let sampleY = Int((size.height / 2) * scaleY)
        return try #require(bitmap.colorAt(x: sampleX, y: sampleY)?.usingColorSpace(.deviceRGB))
    }

    private func pixelDiffers(_ color: NSColor, from baseline: NSColor) -> Bool {
        color.redComponent != baseline.redComponent
            || color.greenComponent != baseline.greenComponent
            || color.blueComponent != baseline.blueComponent
    }
}
