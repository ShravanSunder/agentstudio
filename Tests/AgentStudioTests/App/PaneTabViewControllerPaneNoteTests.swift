import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Pane note and current pane path commands", .serialized)
struct PaneTabViewControllerPaneNoteTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("editPaneNote presents note editor for active main pane")
    func editPaneNote_targetsActiveMainPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)

        harness.controller.execute(.editPaneNote)

        #expect(harness.launchRecorder.paneNoteRequests == [pane.id])
    }

    @Test("fallback editPaneNote popover keeps PaneTabViewController as delegate")
    func editPaneNoteFallbackPopover_keepsControllerDelegate() throws {
        let harness = makeHarness(paneNotePresentationEnabled: false)
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
        defer { window.orderOut(nil) }
        _ = makeMainPane(in: harness)

        harness.controller.execute(.editPaneNote)
        drainPaneNoteRunLoop()

        let popover = try #require(paneNotePopover(from: harness.controller))
        #expect(popover.delegate === harness.controller)

        harness.controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        #expect(paneNotePopover(from: harness.controller) == nil)
    }

    @Test("pane note popover uses fallback anchor when registered host is detached")
    func paneNoteAnchor_fallsBackWhenRegisteredHostIsDetached() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = makeMainPane(in: harness)
        let detachedHost = PaneHostView(paneId: pane.id)
        let fallbackAnchorView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        harness.viewRegistry.register(detachedHost, for: pane.id)

        let anchorView = PaneTabViewController.resolvedPaneNoteAnchorView(
            for: pane.id,
            viewRegistry: harness.viewRegistry,
            fallbackAnchorView: fallbackAnchorView
        )

        #expect(anchorView === fallbackAnchorView)
    }

    @Test("pane note popover prefers attached registered pane host")
    func paneNoteAnchor_prefersAttachedRegisteredHost() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
        defer { window.orderOut(nil) }
        let pane = makeMainPane(in: harness)
        let fallbackAnchorView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let attachedHost = try attachPaneHost(paneId: pane.id, in: harness, to: window)

        let anchorView = PaneTabViewController.resolvedPaneNoteAnchorView(
            for: pane.id,
            viewRegistry: harness.viewRegistry,
            fallbackAnchorView: fallbackAnchorView
        )

        #expect(anchorView === attachedHost)
    }

    @Test("tab bar popover close leaves pane note popover untouched")
    func tabBarPopoverClose_leavesPaneNotePopoverUntouched() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
        defer { window.orderOut(nil) }

        #expect(paneNotePopover(from: harness.controller) == nil)

        let popover = NSPopover()
        harness.controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        #expect(paneNotePopover(from: harness.controller) == nil)
    }

    @Test("copyCurrentPanePath copies active main pane cwd")
    func copyCurrentPanePath_usesMainPaneCWD() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = makeMainPane(in: harness)
        let cwd = harness.tempDir.appending(path: "live-cwd")
        harness.store.updatePaneCWD(pane.id, cwd: cwd)

        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.map(\.standardizedFileURL) == [cwd.standardizedFileURL])
    }

    @Test("copyCurrentPanePath falls back to active main pane launch directory")
    func copyCurrentPanePath_fallsBackToLaunchDirectory() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let launchDirectory = harness.tempDir.appending(path: "launch")
        _ = makeMainPane(in: harness, launchDirectory: launchDirectory)

        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.map(\.standardizedFileURL) == [launchDirectory.standardizedFileURL])
    }

    @Test("main pane note command is unavailable while drawer pane owns focus")
    func editPaneNote_doesNotTargetDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = makeMainPane(in: harness)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

        #expect(!harness.controller.canExecute(.editPaneNote))
        harness.controller.execute(.editPaneNote)

        #expect(harness.launchRecorder.paneNoteRequests.isEmpty)
    }

    @Test("current pane path command is unavailable while drawer pane owns focus")
    func copyCurrentPanePath_doesNotTargetDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = makeMainPane(
            in: harness,
            launchDirectory: harness.tempDir.appending(path: "parent-launch")
        )
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

        #expect(!harness.controller.canExecute(.copyCurrentPanePath))
        harness.controller.execute(.copyCurrentPanePath)

        #expect(harness.launchRecorder.copiedPaths.isEmpty)
    }

    private func makeMainPane(
        in harness: PaneTabViewControllerCommandHarness,
        launchDirectory: URL? = nil
    ) -> Pane {
        let pane = harness.store.createPane(
            launchDirectory: launchDirectory,
            title: "Terminal",
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        atom(\.workspaceFocusOwner).focusMainPane(pane.id)
        return pane
    }
}

private func paneNotePopover(from controller: PaneTabViewController) -> NSPopover? {
    for child in Mirror(reflecting: controller).children {
        guard child.label == "paneNotePopover" else { continue }
        return unwrapOptional(child.value) as? NSPopover
    }
    return nil
}

private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
}

private func drainPaneNoteRunLoop() {
    RunLoop.main.perform(inModes: [.default]) {
        CFRunLoopStop(CFRunLoopGetMain())
    }
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 1, true)
}
