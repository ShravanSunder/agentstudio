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
private final class InteractionTrackingPaneHostView: PaneHostView {
    private(set) var interactionEnabledHistory: [Bool] = []

    override func setContentInteractionEnabled(_ enabled: Bool) {
        interactionEnabledHistory.append(enabled)
    }
}

@MainActor
@Suite(.serialized)
struct ManagementLayerDragShieldTests {

    init() {
        installTestAtomRegistryIfNeeded()
        // Ensure management layer is off before each test
        if atom(\.managementLayer).isActive {
            atom(\.managementLayer).deactivate()
        }
    }

    private func ensureManagementLayerActive() {
        if !atom(\.managementLayer).isActive {
            atom(\.managementLayer).toggle()
        }
    }

    // MARK: - hitTest Behavior

    @Test
    func test_hitTest_alwaysReturnsNil_managementLayerOff() async {
        atom(\.managementLayer).deactivate()
        let shield = ManagementLayerDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)
    }

    @Test
    func test_hitTest_alwaysReturnsNil_managementLayerOn() async {
        let shield = ManagementLayerDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ensureManagementLayerActive()
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)
        atom(\.managementLayer).deactivate()
    }

    // MARK: - Dynamic Registration

    @Test
    func test_registeredDragTypes_managementLayerOff_isEmpty() async {
        atom(\.managementLayer).deactivate()
        let shield = ManagementLayerDragShield(frame: .zero)
        let types = shield.registeredDraggedTypes
        #expect(types.isEmpty)
    }

    @Test
    func test_registeredDragTypes_managementLayerOn_includesFileTypes() async {
        ensureManagementLayerActive()
        let shield = ManagementLayerDragShield(frame: .zero)
        let types = shield.registeredDraggedTypes
        #expect(types.contains(.fileURL))
        #expect(types.contains(.URL))
        #expect(types.contains(.tiff))
        #expect(types.contains(.png))
        #expect(types.contains(.string))
        #expect(types.contains(.html))
        #expect(!types.contains(.agentStudioTabDrop))
        #expect(!types.contains(.agentStudioPaneDrop))
        #expect(!types.contains(.agentStudioTabInternal))
        atom(\.managementLayer).deactivate()
    }

    @Test
    func test_registeredDragTypes_excludesBroadSupertypes() async {
        ensureManagementLayerActive()
        let shield = ManagementLayerDragShield(frame: .zero)
        let types = shield.registeredDraggedTypes
        #expect(!types.contains(NSPasteboard.PasteboardType("public.data")))
        #expect(!types.contains(NSPasteboard.PasteboardType("public.content")))
        atom(\.managementLayer).deactivate()
    }

    // MARK: - Shield Installation in PaneHostView

    @Test
    func test_swiftUIContainer_isManagementLayerContainerView() {
        // Arrange
        let paneView = PaneHostView(paneId: UUID())

        // Act
        let container = paneView.swiftUIContainer

        // Assert — container is the management layer aware subclass
        #expect(container is ManagementLayerContainerView)
    }

    @Test
    func test_shieldInstalledAsTopmostSubview() {
        // Arrange
        let paneView = PaneHostView(paneId: UUID())

        // Act — trigger lazy swiftUIContainer which installs the shield
        _ = paneView.swiftUIContainer

        // Assert — shield is installed
        #expect(paneView.interactionShield != nil)
        // Assert — shield is topmost (last) subview of PaneHostView
        #expect(paneView.subviews.last is ManagementLayerDragShield)
    }

    @Test
    func test_shieldAttach_appliesCurrentInteractionState_managementLayerActive() async {
        ensureManagementLayerActive()
        let paneView = InteractionTrackingPaneHostView(paneId: UUID())
        _ = paneView.swiftUIContainer
        #expect(paneView.interactionEnabledHistory.last == false)
        atom(\.managementLayer).deactivate()
    }

    @Test
    func test_shieldAttach_appliesCurrentInteractionState_managementLayerInactive() async {
        atom(\.managementLayer).deactivate()
        let paneView = InteractionTrackingPaneHostView(paneId: UUID())
        _ = paneView.swiftUIContainer
        #expect(paneView.interactionEnabledHistory.last == true)
    }

    @Test
    func test_paneViewHitTest_managementLayerOn_returnsNil() async {
        let paneView = PaneHostView(paneId: UUID())
        _ = paneView.swiftUIContainer
        ensureManagementLayerActive()
        let result = paneView.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)
        atom(\.managementLayer).deactivate()
    }

    @Test
    func test_paneViewHitTest_managementLayerOff_returnsNormally() async {
        atom(\.managementLayer).deactivate()
        let paneView = PaneHostView(paneId: UUID())
        _ = paneView.swiftUIContainer
        let result = paneView.hitTest(NSPoint(x: 100, y: 100))
        #expect(result !== paneView.interactionShield || result == nil)
    }

    @Test
    func test_containerHitTest_managementLayerOff_returnsSelf() async {
        atom(\.managementLayer).deactivate()
        let container = ManagementLayerContainerView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let result = container.hitTest(NSPoint(x: 100, y: 100))
        #expect(result === container)
    }

    @Test
    func test_containerHitTest_managementLayerOn_returnsNil() async {
        let container = ManagementLayerContainerView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ensureManagementLayerActive()
        let result = container.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)
        atom(\.managementLayer).deactivate()
    }

    // MARK: - NSDraggingDestination

    @Test
    func test_draggingEntered_managementLayerActive_returnsGeneric() async {
        let shield = ManagementLayerDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ensureManagementLayerActive()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])
        let result = shield.draggingEntered(mockDrag)
        #expect(result == .generic)
        atom(\.managementLayer).deactivate()
    }

    @Test
    func test_draggingEntered_managementLayerInactive_returnsEmpty() async {
        atom(\.managementLayer).deactivate()
        let shield = ManagementLayerDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])
        let result = shield.draggingEntered(mockDrag)
        #expect(result.isEmpty)
    }

    @Test
    func test_draggingUpdated_managementLayerActive_returnsGeneric() async {
        let shield = ManagementLayerDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ensureManagementLayerActive()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])
        let result = shield.draggingUpdated(mockDrag)
        #expect(result == .generic)
        atom(\.managementLayer).deactivate()
    }

    @Test
    func test_performDragOperation_returnsFalse() {
        // Arrange — shield absorbs but does not perform
        let shield = ManagementLayerDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
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
        let allowed = ManagementLayerDragShield.DragPolicy.allowedTypes
        #expect(allowed.contains(.agentStudioTabDrop))
        #expect(allowed.contains(.agentStudioPaneDrop))
        #expect(allowed.contains(.agentStudioNewTabDrop))
        #expect(allowed.contains(.agentStudioTabInternal))
    }

    @Test
    func test_dragPolicy_suppressedTypesDoNotOverlapAllowed() {
        // Assert — suppressed and allowed type sets are disjoint
        let allowed = ManagementLayerDragShield.DragPolicy.allowedTypes
        let suppressed = Set(ManagementLayerDragShield.DragPolicy.suppressedTypes)
        let overlap = allowed.intersection(suppressed)
        #expect(overlap.isEmpty, "Allowed and suppressed types must be disjoint, found overlap: \(overlap)")
    }
}
