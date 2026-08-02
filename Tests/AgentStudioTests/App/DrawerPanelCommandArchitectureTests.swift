import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@Suite("DrawerPanel command architecture")
struct DrawerPanelCommandArchitectureTests {
    @Test("Add Drawer Pane is exposed as a targeted inline control")
    func addDrawerPaneIsExposedAsTargetedInlineControl() {
        let query = AppCommandPresentationQuery(
            surface: .inlineControl,
            subject: .targeted(.pane)
        )

        #expect(AppCommand.addDrawerPane.definition.shouldPresent(query))
    }

    @Test("empty drawer Add Pane button uses targeted command presentation")
    func emptyDrawerAddPaneButtonUsesTargetedCommandPresentation() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Panes/Hosting/DrawerPanel.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("let addDrawerPaneAction = commandActionResolver("))
        #expect(source.contains("Button(action: addDrawerPaneAction.perform)"))
        #expect(source.contains(".disabled(!addDrawerPaneAction.isEnabled)"))
        #expect(
            source.contains(
                ".controlHelp(addDrawerPaneAction.commandSpec.controlTooltipRenderValue())"
            )
        )
        #expect(!source.contains(".help(addDrawerPaneAction.commandSpec.helpText)"))
        #expect(!source.contains("action(.addDrawerPane(parentPaneId: parentPaneId))"))
    }
}
