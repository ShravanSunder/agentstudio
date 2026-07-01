import Foundation
import Testing

@testable import AgentStudio

@Suite("Chrome toolbar button style")
struct ChromeToolbarButtonStyleTests {
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
