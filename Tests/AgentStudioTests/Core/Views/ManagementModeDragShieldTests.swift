import AppKit
import Testing
import UniformTypeIdentifiers

@testable import AgentStudio

/// Minimal stub conforming to NSDraggingInfo for unit testing drag shield behavior.
/// Uses a custom pasteboard to control available types without polluting the system drag pasteboard.
private final class MockDraggingInfo: NSObject, NSDraggingInfo {
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
        set { _ = newValue }
    }
    var animatesToDestination: Bool {
        get { false }
        set { _ = newValue }
    }
    var numberOfValidItemsForDrop: Int {
        get { 0 }
        set { _ = newValue }
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
private final class InteractionTrackingPaneView: PaneView {
    private(set) var interactionEnabledHistory: [Bool] = []

    override func setContentInteractionEnabled(_ enabled: Bool) {
        interactionEnabledHistory.append(enabled)
    }
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

    private func ensureManagementModeActive() {
        if !ManagementModeMonitor.shared.isActive {
            ManagementModeMonitor.shared.toggle()
        }
    }

    // MARK: - hitTest Behavior

    @Test
    func test_hitTest_alwaysReturnsNil_managementModeOff() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        // Assert — always transparent to mouse events (drag routing is frame-based)
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)
    }

    @Test
    func test_hitTest_alwaysReturnsNil_managementModeOn() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ensureManagementModeActive()

        // Assert — still nil: NSDraggingDestination uses frame-based routing,
        // not hitTest. PaneView.hitTest handles click blocking separately.
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    // MARK: - Dynamic Registration

    @Test
    func test_registeredDragTypes_managementModeOff_isEmpty() {
        // Arrange — explicitly force inactive to avoid relying on suite init ordering.
        ManagementModeMonitor.shared.deactivate()
        let shield = ManagementModeDragShield(frame: .zero)

        // Assert — no types registered when management mode is off
        let types = shield.registeredDraggedTypes
        #expect(types.isEmpty)
    }

    @Test
    func test_registeredDragTypes_managementModeOn_includesFileTypes() {
        // Arrange — toggle management mode BEFORE creating shield so
        // updateRegistration() runs synchronously during init.
        ensureManagementModeActive()
        let shield = ManagementModeDragShield(frame: .zero)

        // Assert — file/media types registered
        let types = shield.registeredDraggedTypes
        #expect(types.contains(.fileURL))
        #expect(types.contains(.URL))
        #expect(types.contains(.tiff))
        #expect(types.contains(.png))
        #expect(types.contains(.string))
        #expect(types.contains(.html))

        // Assert — agent studio types NOT registered (parent .onDrop owns these)
        #expect(!types.contains(.agentStudioTabDrop))
        #expect(!types.contains(.agentStudioPaneDrop))
        #expect(!types.contains(.agentStudioTabInternal))

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_registeredDragTypes_excludesBroadSupertypes() {
        // Arrange — supertypes like public.data match agent studio CodableRepresentation
        // payloads, which would intercept pane/tab drags and break .onDrop.
        ensureManagementModeActive()
        let shield = ManagementModeDragShield(frame: .zero)

        // Assert — broad supertypes are NOT registered
        let types = shield.registeredDraggedTypes
        #expect(!types.contains(NSPasteboard.PasteboardType("public.data")))
        #expect(!types.contains(NSPasteboard.PasteboardType("public.content")))

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
    func test_shieldAttach_appliesCurrentInteractionState_managementModeActive() {
        // Arrange
        ensureManagementModeActive()
        let paneView = InteractionTrackingPaneView(paneId: UUID())

        // Act — installing the shield should notify parent with current state.
        _ = paneView.swiftUIContainer

        // Assert
        #expect(paneView.interactionEnabledHistory.last == false)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_shieldAttach_appliesCurrentInteractionState_managementModeInactive() {
        // Arrange
        let paneView = InteractionTrackingPaneView(paneId: UUID())

        // Act — installing the shield should notify parent with current state.
        _ = paneView.swiftUIContainer

        // Assert
        #expect(paneView.interactionEnabledHistory.last == true)
    }

    @Test
    func test_paneViewHitTest_managementModeOn_returnsNil() {
        // Arrange
        let paneView = PaneView(paneId: UUID())
        _ = paneView.swiftUIContainer  // Install shield
        ensureManagementModeActive()

        // Act
        let result = paneView.hitTest(NSPoint(x: 100, y: 100))

        // Assert — PaneView returns nil to block clicks.
        // NSDraggingDestination on the shield uses frame-based routing (independent of hitTest).
        #expect(result == nil)

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

        // Assert — normal hit testing (shield is transparent, returns nil from hitTest)
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
        ensureManagementModeActive()

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
        ensureManagementModeActive()
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
        ManagementModeMonitor.shared.deactivate()
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert — transparent when management mode is off
        #expect(result.isEmpty)
    }

    @Test
    func test_draggingUpdated_managementModeActive_returnsGeneric() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ensureManagementModeActive()
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
