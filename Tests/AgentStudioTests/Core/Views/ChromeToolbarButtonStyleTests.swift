import Foundation
import Testing

@testable import AgentStudio

@Suite("Chrome toolbar button style")
struct ChromeToolbarButtonStyleTests {
    @Test("toolbar button metrics preserve the accepted chrome sizing")
    func toolbarButtonMetricsPreserveAcceptedChromeSizing() {
        #expect(AppStyles.Shell.Chrome.ToolbarButton.size == 28)
        #expect(AppStyles.Shell.Chrome.ToolbarButton.iconSize == 12)
    }

    @Test("sidebar nav chrome owns icon and divider spacing")
    func sidebarNavChromeOwnsIconAndDividerSpacing() throws {
        let appStylesSource = try sourceFile("Sources/AgentStudio/Infrastructure/AppStyles.swift")
        let shellControlsSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")
        let customTabBarSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift")

        #expect(AppStyles.Shell.Chrome.SidebarNav.iconSpacing == AppStyles.Shell.Chrome.iconClusterSpacing)
        #expect(AppStyles.Shell.Chrome.SidebarNav.dividerLeadingPadding == 14)
        #expect(AppStyles.Shell.Chrome.SidebarNav.dividerTrailingPadding == 24)

        #expect(appStylesSource.contains("enum SidebarNav"))
        #expect(shellControlsSource.contains("struct SidebarNavDivider"))
        #expect(shellControlsSource.contains("AppStyles.Shell.Chrome.SidebarNav.iconSpacing"))
        #expect(shellControlsSource.contains("AppStyles.Shell.Chrome.SidebarNav.dividerLeadingPadding"))
        #expect(shellControlsSource.contains("AppStyles.Shell.Chrome.SidebarNav.dividerTrailingPadding"))

        let leadingDividerSection = try section(
            in: customTabBarSource,
            from: "case .divider:",
            to: "case .watchFolder:"
        )
        #expect(leadingDividerSection.contains("SidebarNavDivider()"))
    }

    @Test("top chrome separates circled control and plain toolbar icon spacing")
    func topChromeSeparatesCircledControlAndPlainToolbarIconSpacing() throws {
        let appStylesSource = try sourceFile("Sources/AgentStudio/Infrastructure/AppStyles.swift")
        let customTabBarSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift")

        #expect(AppStyles.Shell.Chrome.circledControlSpacing == 12)
        #expect(AppStyles.Shell.Chrome.tabStripLeadingPadding == AppStyles.Shell.Chrome.circledControlSpacing)
        #expect(AppStyles.Shell.Chrome.plainToolbarIconSpacing == 0)
        #expect(AppStyles.Shell.Chrome.PlainToolbarIcon.buttonSize == 24)
        #expect(AppStyles.Shell.Chrome.PlainToolbarIcon.iconSize == AppStyles.Shell.Chrome.ToolbarButton.iconSize)

        #expect(appStylesSource.contains("static let circledControlSpacing: CGFloat = 12"))
        #expect(appStylesSource.contains("static let plainToolbarIconSpacing: CGFloat = 0"))
        #expect(appStylesSource.contains("enum PlainToolbarIcon"))

        let leadingControlsSection = try section(
            in: customTabBarSource,
            from: "private func leadingChromeControl",
            to: "private func trailingChromeControl"
        )
        #expect(leadingControlsSection.contains(".padding(.trailing, AppStyles.Shell.Chrome.circledControlSpacing)"))
        #expect(!leadingControlsSection.contains(".padding(.trailing, AppStyles.Shell.Chrome.iconClusterSpacing)"))

        let trailingControlsSection = try section(
            in: customTabBarSource,
            from: "private func trailingChromeControl",
            to: "// MARK: - Scroll Navigation"
        )
        #expect(trailingControlsSection.contains("buttonSize: AppStyles.Shell.Chrome.PlainToolbarIcon.buttonSize"))
        #expect(trailingControlsSection.contains(".padding(.trailing, AppStyles.Shell.Chrome.plainToolbarIconSpacing)"))
        #expect(
            trailingControlsSection.contains(".padding(.horizontal, AppStyles.Shell.Chrome.plainToolbarIconSpacing)"))
        #expect(trailingControlsSection.contains(".padding(.trailing, AppStyles.Shell.Chrome.circledControlSpacing)"))
    }

    @Test("circular toolbar controls use the shared AppStyles backed label path")
    func circularToolbarControlsUseSharedLabelPath() throws {
        let sharedLabelSource = try sourceFile("Sources/AgentStudio/SharedComponents/ChromeToolbarButtonLabel.swift")
        let shellControlsSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")
        let customTabBarSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift")

        #expect(sharedLabelSource.contains("struct ChromeToolbarCircleBackground"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.baseFillColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.hoverFillColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.pressedFillColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.iconForegroundColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.hoverIconForegroundColor"))

        let sidebarSection = try section(
            in: shellControlsSource,
            from: "private struct SidebarSurfaceTabBarButton",
            to: "struct WatchFolderTabBarMenu"
        )
        let watchSection = try section(
            in: shellControlsSource,
            from: "struct WatchFolderTabBarMenu",
            to: "struct TabBarDivider"
        )
        let managementSection = try section(
            in: customTabBarSource,
            from: "private struct TabBarManagementLayerButton",
            to: "/// Circular \"+\" button"
        )
        let newTabSection = try section(
            in: customTabBarSource,
            from: "private struct NewTabButton",
            to: "/// Individual pill-shaped tab"
        )
        let overflowMenuSection = try section(
            in: customTabBarSource,
            from: "case .overflowMenu:",
            to: "case .newTab:"
        )

        #expect(sidebarSection.contains("showsBackground: false"))
        #expect(!sidebarSection.contains("usesToolbarForeground"))
        #expect(!sidebarSection.contains("ChromeToolbarCircleBackground"))

        for circularSection in [watchSection, managementSection, newTabSection] {
            #expect(circularSection.contains("ChromeToolbarButtonLabel("))
            #expect(circularSection.contains("Button {"))
            #expect(!containsMenuInitializer(in: circularSection))
            #expect(!circularSection.contains(".menuStyle"))
            #expect(!circularSection.contains("showsBackground: false"))
            #expect(!circularSection.contains("usesToolbarForeground"))
            #expect(!circularSection.contains("ChromeToolbarCircleBackground"))
        }

        #expect(overflowMenuSection.contains("ChromeToolbarButtonLabel("))
        #expect(overflowMenuSection.contains("symbolName: \"rectangle.stack\""))
        #expect(overflowMenuSection.contains("showsBackground: false"))
        #expect(!overflowMenuSection.contains("Image(systemName: \"rectangle.stack\")"))
    }

    @Test("arrangement capsule uses the shared toolbar palette for every state")
    func arrangementCapsuleUsesSharedToolbarPaletteForEveryState() throws {
        let sharedLabelSource = try sourceFile("Sources/AgentStudio/SharedComponents/ChromeToolbarButtonLabel.swift")
        let arrangementSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/TabBarArrangementChip.swift")

        #expect(arrangementSource.contains("ChromeToolbarCapsuleBackground"))
        #expect(arrangementSource.contains("ChromeToolbarControlPalette.foregroundColor"))
        #expect(!arrangementSource.contains("contentForegroundColor.opacity"))

        #expect(sharedLabelSource.contains("return AppStyles.Shell.Chrome.ToolbarButton.pressedFillColor"))
        #expect(sharedLabelSource.contains("return AppStyles.Shell.Chrome.ToolbarButton.pressedStrokeColor"))
        #expect(
            !sharedLabelSource.contains("Color.white.opacity(AppStyles.Shell.Chrome.ToolbarButton.pressedFillOpacity)"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(
                fileURLWithPath: relativePath,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)),
            encoding: .utf8
        )
    }

    private func section(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        guard let startRange = source.range(of: startMarker) else {
            throw ChromeToolbarButtonStyleTestError.missingMarker(startMarker)
        }
        guard let endRange = source.range(of: endMarker, range: startRange.upperBound..<source.endIndex) else {
            throw ChromeToolbarButtonStyleTestError.missingMarker(endMarker)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func containsMenuInitializer(in source: String) -> Bool {
        source
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces) == "Menu {" }
    }
}

private enum ChromeToolbarButtonStyleTestError: Error, CustomStringConvertible {
    case missingMarker(String)

    var description: String {
        switch self {
        case .missingMarker(let marker):
            "Missing source marker: \(marker)"
        }
    }
}
