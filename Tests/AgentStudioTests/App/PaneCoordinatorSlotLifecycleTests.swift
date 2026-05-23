import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorSlotLifecycleTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let coordinator: PaneCoordinator
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-slot-lifecycle-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SlotLifecycleSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom()
        )
        return Harness(store: store, viewRegistry: viewRegistry, coordinator: coordinator, tempDir: tempDir)
    }

    private func makeWebviewPane(_ store: WorkspaceStore, title: String) -> Pane {
        let url = URL(string: "https://example.com/\(UUID().uuidString)")!
        return store.createPane(
            content: .webview(WebviewState(url: url, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: title), title: title)
        )
    }

    @Test("close then undo promotes the same retired slot in the coordinator path")
    func closePaneThenUndo_promotesRetiredSlotInPlace() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let closingPane = makeWebviewPane(harness.store, title: "Closing")
        let siblingPane = makeWebviewPane(harness.store, title: "Sibling")
        let tab = Tab(paneId: closingPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.insertPane(
            siblingPane.id,
            inTab: tab.id,
            at: closingPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let originalSlot = harness.viewRegistry.ensureSlot(for: closingPane.id)
        harness.viewRegistry.surfaceRenderedIds("tab:\(tab.id)", ids: [closingPane.id, siblingPane.id])

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: closingPane.id))

        #expect(harness.viewRegistry.isRetiredForTesting(closingPane.id))
        #expect(harness.viewRegistry.peekSlotForTesting(closingPane.id) === originalSlot)

        harness.coordinator.undoCloseTab()

        #expect(harness.store.pane(closingPane.id) != nil)
        #expect(!harness.viewRegistry.isRetiredForTesting(closingPane.id))
        #expect(harness.viewRegistry.peekSlotForTesting(closingPane.id) === originalSlot)
        #expect(harness.viewRegistry.view(for: closingPane.id) != nil)
    }

    @Test("closing two drawer panes in sequence keeps fallback focus and both tombstones stable")
    func closingTwoDrawerPanesInSequence_preservesFallbackFocusAndRetiredSlots() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = makeWebviewPane(harness.store, title: "Parent")
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let first = try #require(harness.store.addDrawerPane(to: parent.id))
        let second = try #require(harness.store.addDrawerPane(to: parent.id))
        let third = try #require(harness.store.addDrawerPane(to: parent.id))
        harness.store.setActiveDrawerPane(second.id, in: parent.id)
        let firstSlot = harness.viewRegistry.ensureSlot(for: first.id)
        let secondSlot = harness.viewRegistry.ensureSlot(for: second.id)
        harness.viewRegistry.surfaceRenderedIds("drawer:\(parent.id)", ids: [first.id, second.id, third.id])

        harness.coordinator.execute(.removeDrawerPane(parentPaneId: parent.id, drawerPaneId: second.id))
        harness.coordinator.execute(.removeDrawerPane(parentPaneId: parent.id, drawerPaneId: first.id))

        let drawer = try #require(harness.store.pane(parent.id)?.drawer)
        #expect(drawer.paneIds == [third.id])
        #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId?.rawValue == third.id)
        #expect(harness.viewRegistry.isRetiredForTesting(first.id))
        #expect(harness.viewRegistry.isRetiredForTesting(second.id))
        #expect(harness.viewRegistry.peekSlotForTesting(first.id) === firstSlot)
        #expect(harness.viewRegistry.peekSlotForTesting(second.id) === secondSlot)
    }

    @Test("closing the last drawer pane then creating a new one does not keep the old slot alive")
    func closeLastDrawerPaneThenCreateNewDrawerPane_cleansOldSlotAndCreatesNewSlot() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = makeWebviewPane(harness.store, title: "Parent")
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let closedChild = try #require(harness.store.addDrawerPane(to: parent.id))
        let oldSlot = harness.viewRegistry.ensureSlot(for: closedChild.id)

        harness.coordinator.execute(.closePane(tabId: tab.id, paneId: closedChild.id))

        #expect(harness.store.pane(parent.id)?.drawer?.paneIds.isEmpty == true)
        #expect(!harness.viewRegistry.isRetiredForTesting(closedChild.id))
        #expect(harness.viewRegistry.peekSlotForTesting(closedChild.id) == nil)

        harness.coordinator.execute(.addDrawerPane(parentPaneId: parent.id))

        let drawer = try #require(harness.store.pane(parent.id)?.drawer)
        let newChildId = try #require(harness.store.drawerView(forParent: parent.id)?.activeChildId?.rawValue)
        #expect(drawer.paneIds == [newChildId])
        #expect(newChildId != closedChild.id)
        #expect(harness.viewRegistry.peekSlotForTesting(newChildId) != nil)
        #expect(harness.viewRegistry.peekSlotForTesting(closedChild.id) !== oldSlot)
    }
}

@MainActor
private final class SlotLifecycleSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
