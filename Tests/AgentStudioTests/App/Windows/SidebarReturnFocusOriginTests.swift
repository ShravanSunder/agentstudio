import AppKit
import Testing

@testable import AgentStudio

private final class SidebarReturnFocusTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
@Suite(.serialized)
struct SidebarReturnFocusOriginTests {
    @Test("repeated sidebar focus keeps the original external responder")
    func repeatedSidebarFocusKeepsOriginalExternalResponder() throws {
        let harness = makeHarness()
        defer { harness.window.close() }
        let returnFocusOrigin = SidebarReturnFocusOrigin()

        #expect(harness.window.makeFirstResponder(harness.externalResponder))
        returnFocusOrigin.captureCurrentResponder(
            in: harness.window,
            sidebarRoot: harness.sidebarRoot
        )

        #expect(harness.window.makeFirstResponder(harness.sidebarResponder))
        returnFocusOrigin.captureCurrentResponder(
            in: harness.window,
            sidebarRoot: harness.sidebarRoot
        )

        var usedFallback = false
        let didRestore = returnFocusOrigin.restore(in: harness.window) {
            usedFallback = true
        }
        #expect(didRestore)
        #expect(!usedFallback)
        #expect(harness.window.firstResponder === harness.externalResponder)
    }

    @Test("field editor origin restores its owning text control")
    func fieldEditorOriginRestoresOwningTextControl() throws {
        let harness = makeHarness()
        defer { harness.window.close() }
        let textField = NSTextField(frame: NSRect(x: 10, y: 10, width: 160, height: 24))
        harness.contentView.addSubview(textField)
        let returnFocusOrigin = SidebarReturnFocusOrigin()

        #expect(harness.window.makeFirstResponder(textField))
        textField.selectText(nil)
        let fieldEditor = try #require(harness.window.firstResponder as? NSTextView)
        #expect(fieldEditor.isFieldEditor)

        returnFocusOrigin.captureCurrentResponder(
            in: harness.window,
            sidebarRoot: harness.sidebarRoot
        )
        #expect(harness.window.makeFirstResponder(harness.sidebarResponder))

        var usedFallback = false
        let didRestore = returnFocusOrigin.restore(in: harness.window) {
            usedFallback = true
        }
        #expect(didRestore)
        #expect(!usedFallback)
        #expect(textField.currentEditor() === harness.window.firstResponder)
    }

    @Test("sidebar field editor does not replace the external return origin")
    func sidebarFieldEditorDoesNotReplaceExternalReturnOrigin() throws {
        let harness = makeHarness()
        defer { harness.window.close() }
        let sidebarTextField = NSTextField(frame: NSRect(x: 10, y: 80, width: 160, height: 24))
        harness.sidebarRoot.addSubview(sidebarTextField)
        let returnFocusOrigin = SidebarReturnFocusOrigin()

        #expect(harness.window.makeFirstResponder(harness.externalResponder))
        returnFocusOrigin.captureCurrentResponder(
            in: harness.window,
            sidebarRoot: harness.sidebarRoot
        )

        #expect(harness.window.makeFirstResponder(sidebarTextField))
        sidebarTextField.selectText(nil)
        let fieldEditor = try #require(harness.window.firstResponder as? NSTextView)
        #expect(fieldEditor.isFieldEditor)
        returnFocusOrigin.captureCurrentResponder(
            in: harness.window,
            sidebarRoot: harness.sidebarRoot
        )

        var usedFallback = false
        let didRestore = returnFocusOrigin.restore(in: harness.window) {
            usedFallback = true
        }
        #expect(didRestore)
        #expect(!usedFallback)
        #expect(harness.window.firstResponder === harness.externalResponder)
    }

    @Test("removed return origin uses active-pane fallback")
    func removedReturnOriginUsesFallback() {
        let harness = makeHarness()
        defer { harness.window.close() }
        let returnFocusOrigin = SidebarReturnFocusOrigin()
        var removableResponder: NSView? = SidebarReturnFocusTestView(
            frame: NSRect(x: 10, y: 50, width: 40, height: 40)
        )
        if let removableResponder {
            harness.contentView.addSubview(removableResponder)
            #expect(harness.window.makeFirstResponder(removableResponder))
            returnFocusOrigin.captureCurrentResponder(
                in: harness.window,
                sidebarRoot: harness.sidebarRoot
            )
        }
        #expect(harness.window.makeFirstResponder(harness.sidebarResponder))
        removableResponder?.removeFromSuperview()
        removableResponder = nil

        var fallbackCount = 0
        let didRestore = returnFocusOrigin.restore(in: harness.window) {
            fallbackCount += 1
        }
        #expect(!didRestore)
        #expect(fallbackCount == 1)
    }

    @Test("retained detached return origin uses active-pane fallback")
    func retainedDetachedReturnOriginUsesFallback() {
        let harness = makeHarness()
        defer { harness.window.close() }
        let returnFocusOrigin = SidebarReturnFocusOrigin()
        let detachedResponder = harness.externalResponder

        #expect(harness.window.makeFirstResponder(detachedResponder))
        returnFocusOrigin.captureCurrentResponder(
            in: harness.window,
            sidebarRoot: harness.sidebarRoot
        )
        #expect(harness.window.makeFirstResponder(harness.sidebarResponder))
        detachedResponder.removeFromSuperview()

        var fallbackCount = 0
        let didRestore = returnFocusOrigin.restore(in: harness.window) {
            fallbackCount += 1
        }

        #expect(!didRestore)
        #expect(fallbackCount == 1)
        #expect(harness.window.firstResponder === harness.sidebarResponder)
        #expect(detachedResponder.window == nil)
    }

    @Test("return origin moved to another window uses active-pane fallback")
    func returnOriginMovedToAnotherWindowUsesFallback() {
        let sourceHarness = makeHarness()
        let destinationHarness = makeHarness()
        defer {
            sourceHarness.window.close()
            destinationHarness.window.close()
        }
        let returnFocusOrigin = SidebarReturnFocusOrigin()
        let movedResponder = sourceHarness.externalResponder

        #expect(sourceHarness.window.makeFirstResponder(movedResponder))
        returnFocusOrigin.captureCurrentResponder(
            in: sourceHarness.window,
            sidebarRoot: sourceHarness.sidebarRoot
        )
        #expect(sourceHarness.window.makeFirstResponder(sourceHarness.sidebarResponder))
        destinationHarness.contentView.addSubview(movedResponder)

        var fallbackCount = 0
        let didRestore = returnFocusOrigin.restore(in: sourceHarness.window) {
            fallbackCount += 1
        }

        #expect(!didRestore)
        #expect(fallbackCount == 1)
        #expect(sourceHarness.window.firstResponder === sourceHarness.sidebarResponder)
        #expect(movedResponder.window === destinationHarness.window)
        #expect(destinationHarness.window.firstResponder !== movedResponder)
    }

    private func makeHarness() -> Harness {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        let sidebarRoot = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        let sidebarResponder = SidebarReturnFocusTestView(
            frame: NSRect(x: 20, y: 20, width: 80, height: 24)
        )
        let externalResponder = SidebarReturnFocusTestView(
            frame: NSRect(x: 250, y: 20, width: 80, height: 24)
        )
        sidebarRoot.addSubview(sidebarResponder)
        contentView.addSubview(sidebarRoot)
        contentView.addSubview(externalResponder)
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        return Harness(
            window: window,
            contentView: contentView,
            sidebarRoot: sidebarRoot,
            sidebarResponder: sidebarResponder,
            externalResponder: externalResponder
        )
    }

    private struct Harness {
        let window: NSWindow
        let contentView: NSView
        let sidebarRoot: NSView
        let sidebarResponder: NSView
        let externalResponder: NSView
    }
}
