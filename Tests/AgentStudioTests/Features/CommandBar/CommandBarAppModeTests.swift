import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite("CommandBarAppMode")
struct CommandBarAppModeTests {
    @Test
    func normalModeProperties() {
        let mode = CommandBarAppMode.normal

        #expect(mode.statusStripLabel == nil)
        #expect(mode.statusStripIcon == nil)
    }

    @Test
    func managementLayerProperties() {
        let mode = CommandBarAppMode.management

        #expect(mode.statusStripLabel == "Management")
        #expect(mode.statusStripIcon == "rectangle.split.2x2.fill")
    }
}

@MainActor
@Suite("WorkspaceFocusedPane command-bar status projection")
struct FocusedPaneStatusProjectionTests {
    @Test("status label and icon come from focused-pane content")
    func statusLabelAndIconComeFromFocusedPaneContent() {
        let cases: [(WorkspaceFocusedPane.ContentType, String, String)] = [
            (.terminal, "Terminal", "terminal"),
            (.webview, "Webview", "globe"),
            (.bridge, "Bridge", "rectangle.split.2x1"),
            (.codeViewer, "Code Viewer", "doc.text"),
            (.unsupported, "Unsupported", "questionmark.square"),
        ]

        for (contentType, expectedLabel, expectedIcon) in cases {
            let paneID = UUID()
            let focusedPane = WorkspaceFocusedPane(
                owner: .mainPane(paneId: paneID),
                activeMainPaneId: paneID,
                paneId: paneID,
                repoId: nil,
                worktreeId: nil,
                contentType: contentType
            )

            #expect(focusedPane.commandBarStatusLabel == expectedLabel)
            #expect(focusedPane.commandBarStatusIcon == expectedIcon)
        }
    }
}
