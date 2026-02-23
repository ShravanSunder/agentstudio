import AppKit
import Testing
import UniformTypeIdentifiers

@testable import AgentStudio

/// Minimal stub conforming to NSDraggingInfo for unit testing drag shield behavior.
/// Uses a custom pasteboard to control available types without polluting the system drag pasteboard.
private final class MockDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    nonisolated let draggingPasteboard: NSPasteboard

    @MainActor
    init(pasteboardTypes: [NSPasteboard.PasteboardType] = []) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test.dragshield.\(UUID().uuidString)"))
        pasteboard.clearContents()
        if !pasteboardTypes.isEmpty {
            pasteboard.declareTypes(pasteboardTypes, owner: nil)
        }
        self.draggingPasteboard = pasteboard
        super.init()
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
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

        // Assert — blocks all interaction when management mode is on
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result === shield)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_hitTest_managementModeOn_outsideBounds_returnsNil() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()

        // Assert — point outside bounds returns nil
        let result = shield.hitTest(NSPoint(x: 300, y: 300))
        #expect(result == nil)

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

    // MARK: - Shield Installation in PaneView

    @Test
    func test_swiftUIContainer_isManagementModeContainerView() {
        // Arrange
        let paneView = PaneView(paneId: UUID())

        // Act
        let container = paneView.swiftUIContainer

        // Assert — container is the management mode aware subclass
        #expect(container is ManagementModeContainerView)
    }

    @Test
    func test_shieldInstalledAsTopmostSubview() {
        // Arrange
        let paneView = PaneView(paneId: UUID())

        // Act — trigger lazy swiftUIContainer which installs the shield
        _ = paneView.swiftUIContainer

        // Assert — shield is installed
        #expect(paneView.interactionShield != nil)
        // Assert — shield is topmost (last) subview of PaneView
        #expect(paneView.subviews.last is ManagementModeDragShield)
    }

    @Test
    func test_paneViewHitTest_managementModeOn_returnsShield() {
        // Arrange
        let paneView = PaneView(paneId: UUID())
        _ = paneView.swiftUIContainer  // Install shield
        ManagementModeMonitor.shared.toggle()

        // Act
        let result = paneView.hitTest(NSPoint(x: 100, y: 100))

        // Assert — PaneView delegates to shield
        #expect(result === paneView.interactionShield)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_paneViewHitTest_managementModeOff_returnsNormally() {
        // Arrange
        let paneView = PaneView(paneId: UUID())
        _ = paneView.swiftUIContainer  // Install shield

        // Act
        let result = paneView.hitTest(NSPoint(x: 100, y: 100))

        // Assert — normal hit testing (shield is transparent)
        #expect(result !== paneView.interactionShield || result == nil)
    }

    @Test
    func test_containerHitTest_managementModeOff_returnsSelf() {
        // Arrange
        let container = ManagementModeContainerView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        // Assert — normal hit testing when management mode is off
        let result = container.hitTest(NSPoint(x: 100, y: 100))
        #expect(result === container)
    }

    @Test
    func test_containerHitTest_managementModeOn_returnsNil() {
        // Arrange
        let container = ManagementModeContainerView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()

        // Assert — invisible to AppKit during management mode
        let result = container.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    // MARK: - NSDraggingDestination

    @Test
    func test_draggingEntered_managementModeActive_returnsGeneric() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert — absorbs the drag
        #expect(result == .generic)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingEntered_managementModeInactive_returnsEmpty() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert — transparent when management mode is off
        #expect(result == [])
    }

    @Test
    func test_draggingUpdated_managementModeActive_returnsGeneric() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])

        // Act
        let result = shield.draggingUpdated(mockDrag)

        // Assert
        #expect(result == .generic)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_performDragOperation_returnsFalse() {
        // Arrange — shield absorbs but does not perform
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let mockDrag = MockDraggingInfo()

        // Act
        let result = shield.performDragOperation(mockDrag)

        // Assert
        #expect(result == false)
    }

    // MARK: - DragPolicy Constants

    @Test
    func test_dragPolicy_allowedTypesContainsAllAgentStudioTypes() {
        // Assert — all agent studio types are in the allowlist
        let allowed = ManagementModeDragShield.DragPolicy.allowedTypes
        #expect(allowed.contains(.agentStudioTabDrop))
        #expect(allowed.contains(.agentStudioPaneDrop))
        #expect(allowed.contains(.agentStudioNewTabDrop))
        #expect(allowed.contains(.agentStudioTabInternal))
    }

    @Test
    func test_dragPolicy_suppressedTypesDoNotOverlapAllowed() {
        // Assert — suppressed and allowed type sets are disjoint
        let allowed = ManagementModeDragShield.DragPolicy.allowedTypes
        let suppressed = Set(ManagementModeDragShield.DragPolicy.suppressedTypes)
        let overlap = allowed.intersection(suppressed)
        #expect(overlap.isEmpty, "Allowed and suppressed types must be disjoint, found overlap: \(overlap)")
    }
}
