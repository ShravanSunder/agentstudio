import Testing

@testable import AgentStudio

@Suite("CommandBarAppMode")
struct CommandBarAppModeTests {
    @Test
    func normalModeProperties() {
        let mode = CommandBarAppMode.normal

        #expect(mode.label == "Normal")
        #expect(mode.icon == "rectangle.split.2x2")
        #expect(mode.isAccented == false)
    }

    @Test
    func managementModeProperties() {
        let mode = CommandBarAppMode.management

        #expect(mode.label == "Manage")
        #expect(mode.icon == "rectangle.split.2x2.fill")
        #expect(mode.isAccented == true)
    }
}

@Suite("CommandBarAppContext")
struct CommandBarAppContextTests {
    @Test
    func terminalContext() {
        let context = CommandBarAppContext(paneContentType: .terminal)

        #expect(context.label == "Terminal")
        #expect(context.icon == "terminal")
    }

    @Test
    func webviewContext() {
        let context = CommandBarAppContext(paneContentType: .webview)

        #expect(context.label == "Webview")
        #expect(context.icon == "globe")
    }

    @Test
    func bridgeContext() {
        let context = CommandBarAppContext(paneContentType: .bridge)

        #expect(context.label == "Bridge")
        #expect(context.icon == "rectangle.split.2x1")
    }

    @Test
    func codeViewerContext() {
        let context = CommandBarAppContext(paneContentType: .codeViewer)

        #expect(context.label == "Code Viewer")
        #expect(context.icon == "doc.text")
    }

    @Test
    func unknownContext() {
        let context = CommandBarAppContext(paneContentType: .unknown)

        #expect(context.label == "Unknown")
        #expect(context.icon == "questionmark.square")
    }

    @Test
    func noActivePaneDefaultsToTerminal() {
        let context = CommandBarAppContext(paneContentType: nil)

        #expect(context.label == "Terminal")
        #expect(context.icon == "terminal")
    }
}
