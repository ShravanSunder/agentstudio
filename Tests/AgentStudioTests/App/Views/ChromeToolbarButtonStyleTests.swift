import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioSharedComponents

@Suite("Chrome toolbar button style")
struct ChromeToolbarButtonStyleTests {
    @Test("toolbar button metrics preserve the accepted chrome sizing")
    func toolbarButtonMetricsPreserveAcceptedChromeSizing() {
        #expect(AppStyles.Shell.Chrome.ToolbarButton.size == 28)
        #expect(AppStyles.Shell.Chrome.ToolbarButton.iconSize == 12)
    }

    @Test("native fixed controls are excluded from custom tab bar spacing")
    func nativeFixedControlsAreExcludedFromCustomTabBarSpacing() throws {
        let customTabBarSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift")

        #expect(!customTabBarSource.contains("leadingChromeControl"))
        #expect(!customTabBarSource.contains("tabBarContentLeadingPadding"))
        #expect(!customTabBarSource.contains("tabStripLeadingPadding"))
        #expect(!customTabBarSource.contains("ToolbarButton.verticalOffset"))
    }

    @Test("top chrome defines circled control and plain toolbar icon spacing tokens")
    func topChromeDefinesCircledControlAndPlainToolbarIconSpacingTokens() throws {
        let appStylesSource = try sourceFile("Sources/AgentStudio/Infrastructure/AppStyles.swift")
        let customTabBarSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift")

        #expect(AppStyles.Shell.Chrome.circledControlSpacing == 12)
        #expect(AppStyles.Shell.Chrome.plainToolbarIconSpacing == 0)
        #expect(AppStyles.Shell.Chrome.PlainToolbarIcon.buttonSize == 24)
        #expect(AppStyles.Shell.Chrome.PlainToolbarIcon.iconSize == AppStyles.Shell.Chrome.ToolbarButton.iconSize)

        #expect(appStylesSource.contains("static let circledControlSpacing: CGFloat = 12"))
        #expect(appStylesSource.contains("static let plainToolbarIconSpacing: CGFloat = 0"))
        #expect(appStylesSource.contains("enum PlainToolbarIcon"))

        // The overflow chevrons are the only remaining plain-icon controls left inside
        // CustomTabBar itself; the circled controls (watch folder, management mode, new
        // tab) and the tab selector now live as independent native toolbar items wired
        // from ShellTabBarControls, so circledControlSpacing has no application site here
        // anymore — that spacing comes from the toolbar's own inter-item layout instead.
        let trailingControlsSection = try section(
            in: customTabBarSource,
            from: "private func trailingChromeControl",
            to: "// MARK: - Scroll Navigation"
        )
        #expect(trailingControlsSection.contains("buttonSize: AppStyles.Shell.Chrome.PlainToolbarIcon.buttonSize"))
        #expect(trailingControlsSection.contains(".padding(.trailing, AppStyles.Shell.Chrome.plainToolbarIconSpacing)"))
        #expect(trailingControlsSection.contains("showsBackground: false"))
    }

    @Test("circular toolbar controls use the shared AppStyles backed label path")
    func circularToolbarControlsUseSharedLabelPath() throws {
        let sharedLabelSource = try sourceFile("Sources/AgentStudio/SharedComponents/ChromeToolbarButtonLabel.swift")
        let shellControlsSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(sharedLabelSource.contains("struct ChromeToolbarCircleBackground"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.baseFillColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.hoverFillColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.pressedFillColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.iconForegroundColor"))
        #expect(sharedLabelSource.contains("AppStyles.Shell.Chrome.ToolbarButton.hoverIconForegroundColor"))

        let watchSection = try section(
            in: shellControlsSource,
            from: "struct WatchFolderTabBarMenu",
            to: "struct TabBarManagementLayerButton"
        )
        let managementSection = try section(
            in: shellControlsSource,
            from: "struct TabBarManagementLayerButton",
            to: "struct TabSelectionToolbarMenu"
        )
        let selectTabSection = try section(
            in: shellControlsSource,
            from: "struct TabSelectionToolbarMenu",
            to: "struct NewTabButton"
        )
        let newTabSection = try section(in: shellControlsSource, from: "struct NewTabButton")

        for circularSection in [watchSection, managementSection, newTabSection] {
            #expect(circularSection.contains("ChromeToolbarButtonLabel("))
            #expect(circularSection.contains("Button"))
            #expect(
                circularSection.contains("presentation.perform")
                    || circularSection.contains("newTabToolbarPresentation.perform")
            )
            #expect(!containsMenuInitializer(in: circularSection))
            #expect(!circularSection.contains(".menuStyle"))
            #expect(!circularSection.contains("showsBackground: false"))
            #expect(!circularSection.contains("usesToolbarForeground"))
            #expect(!circularSection.contains("ChromeToolbarCircleBackground"))
        }

        // The tab selector is the flat/plain successor to the old overflow menu — it
        // renders through the same shared label path but explicitly opts out of the
        // circle background, and legitimately uses Menu (unlike the circular buttons).
        #expect(selectTabSection.contains("ChromeToolbarButtonLabel("))
        #expect(selectTabSection.contains("symbolName: \"rectangle.stack\""))
        #expect(selectTabSection.contains("showsBackground: false"))
        #expect(
            selectTabSection.contains(
                ".tint(AppStyles.Shell.Chrome.ToolbarButton.iconForegroundColor)"
            )
        )
        #expect(containsMenuInitializer(in: selectTabSection))
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

    private func section(in source: String, from startMarker: String, to endMarker: String? = nil) throws -> String {
        guard let startRange = source.range(of: startMarker) else {
            throw ChromeToolbarButtonStyleTestError.missingMarker(startMarker)
        }
        guard let endMarker else {
            return String(source[startRange.lowerBound...])
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
