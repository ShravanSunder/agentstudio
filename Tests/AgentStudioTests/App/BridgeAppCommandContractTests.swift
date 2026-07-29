import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("Pane Zoom and Viewer app command hard-cut contracts")
struct BridgeAppCommandContractTests {
    @Test("Pane Zoom and Zoom-local Viewer coexist with durable Review and Files commands")
    func zoomAndDurableViewerCommandIdentitiesAreSeparate() {
        // Arrange
        let expectedCommandIdentities: Set<String> = [
            "zoomPane",
            "showViewer",
            "showBridgeReview",
            "showBridgeFiles",
            "openBridgeReviewInNewTab",
            "openBridgeFilesInNewTab",
        ]
        let retiredCommandIdentities: Set<String> = [
            "toggleSplitZoom"
        ]

        // Act
        let commandIdentities = Set(AppCommand.allCases.map(\.rawValue))

        // Assert
        #expect(expectedCommandIdentities.isSubset(of: commandIdentities))
        #expect(commandIdentities.isDisjoint(with: retiredCommandIdentities))
    }

    @Test("Pane Zoom has the semantic command presentation")
    func zoomCommandCatalogContract() throws {
        // Arrange
        let zoomPane = try #require(AppCommand(rawValue: "zoomPane"))

        // Act
        let definition = AppCommandDispatcher.shared.definition(for: zoomPane)
        let canonicalZoomSymbol = SystemSymbol(
            rawValue: "square.arrowtriangle.4.outward"
        )

        // Assert
        #expect(definition.label == "Pane Zoom")
        #expect(definition.icon == canonicalZoomSymbol.map(CommandIcon.system))
        #expect(definition.appliesTo == [.pane])
        #expect(definition.visibleWhen == [.supportsTerminalZoom])
        #expect(definition.shortcut?.rawValue == "zoomPane")
        #expect(definition.shortcut?.trigger.displayString == "⌘⇧↵")
        #expect(definition.ipcExposure.executionModes == [.headless])
        #expect(definition.ipcExposure.targetKinds == [.pane])
        #expect(definition.ipcExposure.requiredPrivileges == [.layoutMutate])
    }

    @Test("Viewer is a Zoom-entry and Zoom-local toggle command")
    func viewerCommandCatalogContract() throws {
        // Arrange
        let showViewer = try #require(AppCommand(rawValue: "showViewer"))

        // Act
        let definition = AppCommandDispatcher.shared.definition(for: showViewer)
        let canonicalViewerSymbol = SystemSymbol(
            rawValue: "text.page.badge.magnifyingglass"
        )

        // Assert
        #expect(definition.label == "Worktree Viewer")
        #expect(definition.icon == canonicalViewerSymbol.map(CommandIcon.system))
        #expect(definition.helpText == "Show or hide the Worktree Viewer in Pane Zoom")
        #expect(definition.appliesTo.isEmpty)
        #expect(definition.visibleWhen == [.supportsTerminalZoom])
        #expect(definition.shortcut?.rawValue == "showViewer")
        #expect(definition.shortcut?.trigger.displayString == "⌘O")
        #expect(definition.ipcExposure.executionModes.isEmpty)
        #expect(definition.ipcExposure.targetKinds.isEmpty)
        #expect(definition.ipcExposure.requiredPrivileges.isEmpty)
    }
}
