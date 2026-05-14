import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct GhosttyMountViewTests {
    @Test
    func mountView_reparentsMountedChildThroughSingleMountBoundary() {
        let mountView = GhosttyMountView()
        let child = NSView(frame: .zero)

        mountView.mountAnyViewForTesting(child)

        #expect(child.superview === mountView)
    }

    @Test
    func mountView_replacesExistingMountedChild() {
        let mountView = GhosttyMountView()
        let first = NSView(frame: .zero)
        let second = NSView(frame: .zero)

        mountView.mountAnyViewForTesting(first)
        mountView.mountAnyViewForTesting(second)

        #expect(first.superview == nil)
        #expect(second.superview === mountView)
    }
}
