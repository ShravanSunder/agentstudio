import AppKit
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneHostViewTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

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
    func paneHost_managementLayerShieldStaysOnHostNotMountedContent() {
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

    @Test("mounted descendant fitting constraints cannot resize the pane host")
    func mountedDescendantFittingConstraintsCannotResizePaneHost() {
        let expectedSize = NSSize(width: 1000, height: 600)
        let host = PaneHostView(paneId: UUIDv7.generate())
        let mountedContent = TestMountedContentView()
        let sizingPressureView = NSView()
        sizingPressureView.translatesAutoresizingMaskIntoConstraints = false
        mountedContent.addSubview(sizingPressureView)
        host.mountContentView(mountedContent)

        let preferredWidthConstraint = sizingPressureView.widthAnchor.constraint(
            equalTo: mountedContent.widthAnchor,
            constant: -24
        )
        preferredWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            sizingPressureView.topAnchor.constraint(equalTo: mountedContent.topAnchor, constant: 12),
            sizingPressureView.centerXAnchor.constraint(equalTo: mountedContent.centerXAnchor),
            sizingPressureView.leadingAnchor.constraint(
                greaterThanOrEqualTo: mountedContent.leadingAnchor,
                constant: 12
            ),
            sizingPressureView.trailingAnchor.constraint(
                lessThanOrEqualTo: mountedContent.trailingAnchor,
                constant: -12
            ),
            sizingPressureView.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            sizingPressureView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            preferredWidthConstraint,
        ])

        let hostingView = NSHostingView(
            rootView: PaneViewRepresentable(paneHost: host)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        hostingView.frame = NSRect(origin: .zero, size: expectedSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: expectedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()
        #expect(host.swiftUIContainer.frame.size == expectedSize)
        #expect(host.frame.size == expectedSize)
        #expect(host.bounds.size == expectedSize)
        #expect(host.contentContainerViewForTesting.frame.size == expectedSize)
        #expect(mountedContent.frame.size == expectedSize)

        let resizedAllocation = NSSize(width: 1200, height: 700)
        window.setContentSize(resizedAllocation)
        hostingView.frame.size = resizedAllocation
        hostingView.layoutSubtreeIfNeeded()

        #expect(host.frame.size == resizedAllocation)
        #expect(host.bounds.size == resizedAllocation)
        #expect(host.contentContainerViewForTesting.frame.size == resizedAllocation)
        #expect(mountedContent.frame.size == resizedAllocation)
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
