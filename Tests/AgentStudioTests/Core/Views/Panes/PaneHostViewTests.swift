import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneHostViewTests {
    @Test
    func paneHost_preservesIdentityAcrossMountedContentSwaps() {
        let paneId = UUID()
        let host = PaneHostView(paneId: paneId)
        let firstMount = TestMountedContentView()
        let secondMount = TestMountedContentView()

        let hostIdentity = ObjectIdentifier(host)
        let containerIdentity = ObjectIdentifier(host.swiftUIContainer)

        host.mountContentView(firstMount)
        host.mountContentView(secondMount)

        #expect(ObjectIdentifier(host) == hostIdentity)
        #expect(ObjectIdentifier(host.swiftUIContainer) == containerIdentity)
        #expect(secondMount.superview === host.contentContainerViewForTesting)
    }

    @Test
    func paneHost_managementModeShieldStaysOnHostNotMountedContent() {
        let host = PaneHostView(paneId: UUID())
        host.mountContentView(TestMountedContentView())

        #expect(host.interactionShieldForTesting != nil)
        #expect(host.contentContainerViewForTesting.subviews.count == 1)
    }

    @Test
    func paneHost_resolvesTypedMountedContent() {
        let host = PaneHostView(paneId: UUID())
        let mountedContent = TestMountedContentView()
        host.mountContentView(mountedContent)

        #expect(host.mountedContent(as: TestMountedContentView.self) === mountedContent)
        #expect(host.mountedContent(as: NSButton.self) == nil)
    }

    @Test
    func paneHost_notifiesWhenAttachedToWindow() {
        let paneId = UUID()
        let host = PaneHostView(paneId: paneId)
        let mountedContent = TestMountedContentView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        var attachedPaneId: UUID?
        host.onAttachedToWindow = { attachedPaneId = $0 }
        host.mountContentView(mountedContent)
        window.contentView?.addSubview(host)

        #expect(attachedPaneId == paneId)
    }
}

@MainActor
private final class TestMountedContentView: NSView, PaneMountedContent {
    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func setContentInteractionEnabled(_: Bool) {}
}
