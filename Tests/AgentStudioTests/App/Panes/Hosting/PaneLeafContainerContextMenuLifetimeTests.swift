import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioTestSupport

@Suite("Pane leaf context-menu lifetime")
struct PaneLeafContainerContextMenuLifetimeTests {
    @Test("pane hover state is owned below the menu-bearing container")
    func paneHoverStateIsOwnedBelowMenuBearingContainer() throws {
        let paneLeafSource = try sourceContents(
            "Sources/AgentStudio/App/Panes/Hosting/PaneLeafContainer.swift"
        )
        let hoverBorderSource = try sourceContents(
            "Sources/AgentStudio/App/Panes/Hosting/PaneManagementHoverBorder.swift"
        )
        let paneLeafBody = try sourceSection(
            paneLeafSource,
            startingAt: "struct PaneLeafContainer: View",
            endingAt: "extension PaneLeafContainer"
        )

        #expect(hoverBorderSource.contains("struct PaneManagementHoverBorder: ViewModifier"))
        #expect(!paneLeafBody.contains("@State private var isHovered: Bool = false"))
        #expect(!paneLeafBody.contains(".onHover { isHovered = suppressMainPaneManagementInteraction ? false : $0 }"))
        #expect(paneLeafBody.contains(".contextMenu {"))
    }

    @Test("hover border preserves management interaction gates and pointer fallback")
    func hoverBorderPreservesManagementInteractionGatesAndPointerFallback() throws {
        let borderSource = try sourceContents(
            "Sources/AgentStudio/App/Panes/Hosting/PaneManagementHoverBorder.swift"
        )

        #expect(borderSource.contains("@State private var isHovered: Bool = false"))
        #expect(borderSource.contains("isManagementLayerActive"))
        #expect(borderSource.contains("isSplitResizing"))
        #expect(borderSource.contains("suppressMainPaneManagementInteraction"))
        #expect(borderSource.contains("mouseLocationOutsideOfEventStream"))
        #expect(borderSource.contains(".onHover"))
    }

    @Test("pane context menu remains on the pane surface")
    func paneContextMenuRemainsOnPaneSurface() throws {
        let source = try sourceContents(
            "Sources/AgentStudio/App/Panes/Hosting/PaneLeafContainer.swift"
        )
        let paneLeafSource = try sourceSection(
            source,
            startingAt: "struct PaneLeafContainer: View",
            endingAt: "extension PaneLeafContainer"
        )

        #expect(paneLeafSource.contains(".contextMenu {"))
        #expect(paneLeafSource.contains("movePaneDestinationMenuItems(moveContextMenuPresentation)"))
        #expect(source.contains("presentation.movePane("))
    }

    private func sourceContents(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }

    private func sourceSection(
        _ source: String,
        startingAt startMarker: String,
        endingAt endMarker: String
    ) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let remainder = source[start.lowerBound...]
        let end = try #require(remainder.range(of: endMarker, range: remainder.startIndex..<remainder.endIndex))
        return String(remainder[..<end.lowerBound])
    }
}
