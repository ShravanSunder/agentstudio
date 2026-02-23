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
    func test_hitTest_managementModeOn_fileDrag_returnsSelf() {
        // Arrange — simulate a file drag on the drag pasteboard
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let dragPasteboard = NSPasteboard(name: .drag)
        dragPasteboard.clearContents()
        dragPasteboard.declareTypes([.fileURL], owner: nil)

        // Assert — shield intercepts file drags
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result === shield)

        // Cleanup
        dragPasteboard.clearContents()
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_hitTest_managementModeOn_agentStudioDrag_returnsNil() {
        // Arrange — simulate an agent studio pane drag
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let dragPasteboard = NSPasteboard(name: .drag)
        dragPasteboard.clearContents()
        dragPasteboard.declareTypes([.agentStudioPaneDrop], owner: nil)

        // Assert — shield is transparent for agent studio drags
        let result = shield.hitTest(NSPoint(x: 100, y: 100))
        #expect(result == nil)

        // Cleanup
        dragPasteboard.clearContents()
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_hitTest_managementModeOn_emptyPasteboard_returnsSelf() {
        // Arrange — no active drag (empty pasteboard)
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let dragPasteboard = NSPasteboard(name: .drag)
        dragPasteboard.clearContents()

        // Assert — shield participates (suppresses unknown drags)
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

    // MARK: - Drag Type Gating (Allowlist)

    @Test
    func test_draggingEntered_agentStudioPaneType_passesThrough() {
        // Arrange — pane drag should pass through to SwiftUI .onDrop
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.agentStudioPaneDrop])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert — returns empty so AppKit forwards to SwiftUI
        #expect(result == [])

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingEntered_agentStudioTabType_passesThrough() {
        // Arrange — tab drag should pass through to SwiftUI .onDrop
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.agentStudioTabDrop])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert
        #expect(result == [])

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingEntered_fileType_suppressed() {
        // Arrange — file drag should be suppressed
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert — returns .generic to claim the drag (suppress)
        #expect(result == .generic)

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingEntered_mixedTypes_agentStudioWins() {
        // Arrange — if pasteboard has both file and agent studio types,
        // agent studio types take precedence (passes through)
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL, .agentStudioPaneDrop])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert — allowed type present, so pass through
        #expect(result == [])

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingEntered_managementModeInactive_alwaysPassesThrough() {
        // Arrange — when management mode is off, all drags pass through
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.fileURL])

        // Act
        let result = shield.draggingEntered(mockDrag)

        // Assert
        #expect(result == [])
    }

    @Test
    func test_draggingUpdated_agentStudioType_passesThrough() {
        // Arrange
        let shield = ManagementModeDragShield(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        ManagementModeMonitor.shared.toggle()
        let mockDrag = MockDraggingInfo(pasteboardTypes: [.agentStudioPaneDrop])

        // Act
        let result = shield.draggingUpdated(mockDrag)

        // Assert
        #expect(result == [])

        // Cleanup
        ManagementModeMonitor.shared.deactivate()
    }

    @Test
    func test_draggingUpdated_fileType_suppressed() {
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
