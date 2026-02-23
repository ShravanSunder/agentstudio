import AppKit
import Testing

@testable import AgentStudio

/// Minimal stub conforming to NSDraggingInfo for unit testing drag shield behavior.
private final class MockDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { NSPasteboard(name: .drag) }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation {
        get { .default }
        set {}
    }
    var animatesToDestination: Bool {
        get { false }
        set {}
    }
    var numberOfValidItemsForDrop: Int {
        get { 0 }
        set {}
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to _: NSPoint) {}
    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions,
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
        using _: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
}

@MainActor
@Suite(.serialized)
struct ManagementModeDragShieldTests {

    init() {
        // Ensure management mode is off before each test
        if ManagementModeMonitor.shared.isActive {
            ManagementModeMonitor.shared.deactivate()
        }
    }

    // MARK: - hitTest Behavior

    @Test
    func test_hitTest_managementModeOff_returnsNil() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        // Assert — transparent when management mode is off
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)
    }

    @Test
    func test_hitTest_managementModeOn_returnsSelf() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()

        // Assert — participates in drag routing when management mode is on
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result === shield)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    // MARK: - Dynamic Registration

    @Test
    func test_registeredDragTypes_managementModeOff_isEmpty() {
        // Arrange — management mode is off (from init)
        let shield = ManagementModeDragShield(frame: .zero)

        // Assert — no types registered when management mode is off
        let types = shield.registeredDraggedTypes
        #expect(types.isEmpty)
    }

    @Test
    func test_registeredDragTypes_managementModeOn_includesFileTypes() {
        // Arrange — toggle management mode BEFORE creating shield so
        // updateRegistration() runs synchronously during init.
        ManagementModeMonitor.shared.toggle()
        let shield = ManagementModeDragShield(frame: .zero)

        // Assert — file/media types registered
        let types = shield.registeredDraggedTypes
        #expect(types.contains(.fileURL))
        #expect(types.contains(.URL))
        #expect(types.contains(.tiff))

        // Assert — agent studio types NOT registered
        #expect(!types.contains(.agentStudioTabDrop))
        #expect(!types.contains(.agentStudioPaneDrop))
        #expect(!types.contains(.agentStudioTabInternal))

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    // MARK: - Z-Order in PaneView

    @Test
    func test_shieldIsTopSubview_ofPaneViewContainer() {
        // Arrange
        let paneView = PaneView(paneId: UUID())

        // Act
        let container = paneView.swiftUIContainer

        // Assert — shield is the topmost (last) subview
        let topSubview = container.subviews.last
        #expect(topSubview is ManagementModeDragShield)
    }

    // MARK: - Drag Callback Behavior

    @Test
    func test_draggingEntered_managementModeActive_returnsGeneric() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()

        // Act
        let result = shield.draggingEntered(MockDraggingInfo())

        // Assert
        #expect(result == .generic)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingEntered_managementModeInactive_returnsEmpty() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        // Act
        let result = shield.draggingEntered(MockDraggingInfo())

        // Assert
        #expect(result == [])
    }

    @Test
    func test_draggingUpdated_managementModeActive_returnsGeneric() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()

        // Act
        let result = shield.draggingUpdated(MockDraggingInfo())

        // Assert
        #expect(result == .generic)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_performDragOperation_returnsFalse() {
        // Arrange — shield absorbs but does not perform
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        // Act
        let result = shield.performDragOperation(MockDraggingInfo())

        // Assert
        #expect(result == false)
    }
}
