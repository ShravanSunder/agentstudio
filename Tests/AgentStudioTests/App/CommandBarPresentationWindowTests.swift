import AppKit
import Testing

@testable import AgentStudio

@MainActor
struct CommandBarPresentationWindowTests {
    @Test
    func keyWorkspaceWindowIsUsedDirectly() {
        let keyWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let fallbackWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        let resolvedWindow = AppDelegate.commandBarPresentationWindow(
            keyWindow: keyWindow,
            fallbackWindow: fallbackWindow
        )

        #expect(resolvedWindow === keyWindow)
    }

    @Test
    func commandBarChildPanelResolvesToWorkspaceParent() {
        let workspaceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let commandBarPanel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 80),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        workspaceWindow.addChildWindow(commandBarPanel, ordered: .above)
        defer {
            workspaceWindow.removeChildWindow(commandBarPanel)
        }

        let resolvedWindow = AppDelegate.commandBarPresentationWindow(
            keyWindow: commandBarPanel,
            fallbackWindow: nil
        )

        #expect(resolvedWindow === workspaceWindow)
    }

    @Test
    func fallbackWindowIsUsedWhenNoKeyWindowExists() {
        let fallbackWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        let resolvedWindow = AppDelegate.commandBarPresentationWindow(
            keyWindow: nil,
            fallbackWindow: fallbackWindow
        )

        #expect(resolvedWindow === fallbackWindow)
    }
}
