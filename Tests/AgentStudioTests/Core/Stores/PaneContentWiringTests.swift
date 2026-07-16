import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PaneContentWiringTests {

    private var store: WorkspaceStore!

    init() {
        installTestAtomRegistryIfNeeded()
        store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
    }

    // MARK: - WorkspaceStore.createPane(content:)

    @Test

    func test_createPane_webviewContent() {
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!, showNavigation: true)),
            metadata: PaneMetadata(title: "Web")
        )

        #expect(pane.title == "Web")
        if case .webview(let state) = pane.content {
            #expect(state.url.absoluteString == "https://example.com")
            #expect(state.showNavigation)
        } else {
            Issue.record("Expected .webview content")
        }
        #expect((store.pane(pane.id)) != nil)
    }

    @Test

    func test_createPane_codeViewerContent() {
        let filePath = URL(fileURLWithPath: "/tmp/test.swift")
        let pane = store.createPane(
            content: .codeViewer(CodeViewerState(filePath: filePath, scrollToLine: 42)),
            metadata: PaneMetadata(title: "Code")
        )

        #expect(pane.title == "Code")
        if case .codeViewer(let state) = pane.content {
            #expect(state.filePath == filePath)
            #expect(state.scrollToLine == 42)
        } else {
            Issue.record("Expected .codeViewer content")
        }
    }

    @Test

    func test_createPane_terminalContent_viaGenericOverload() {
        let pane = store.createPane(
            content: .terminal(
                TerminalState(
                    provider: .ghostty,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(title: "Term")
        )

        #expect(pane.provider == .ghostty)
        #expect(pane.title == "Term")
    }

    @Test

    func test_createPane_marksDirty() async {
        _ = await store.flushAsync()
        _ = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: false)),
            metadata: PaneMetadata(title: "Web")
        )
        #expect(store.isDirty)
    }

    // MARK: - Mixed content types in a tab

    @Test

    func test_mixedContentTab_layoutContainsAllPanes() {
        let terminalPane = store.createPane(
            title: "Terminal",
            provider: .ghostty
        )
        let webPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://docs.com")!, showNavigation: true)),
            metadata: PaneMetadata(title: "Docs")
        )

        let tab = Tab(paneId: terminalPane.id)
        store.appendTab(tab)
        store.insertPane(
            webPane.id, inTab: tab.id, at: terminalPane.id,
            direction: .horizontal, position: .after, sizingMode: .halveTarget)

        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.panes.contains(terminalPane.id))
        #expect(updatedTab.panes.contains(webPane.id))
        #expect(updatedTab.panes.count == 2)
    }

    // MARK: - Persistence round-trip

    // MARK: - ViewRegistry generalization

    @Test

    func test_viewRegistry_registersPaneHostView() {
        let registry = ViewRegistry()
        let view = PaneHostView(paneId: UUID())

        registry.register(view, for: view.paneId)

        #expect((registry.view(for: view.paneId)) != nil)
        #expect(registry.registeredPaneIds.contains(view.paneId))
    }

    @Test

    func test_viewRegistry_terminalViewDowncast() {
        let registry = ViewRegistry()
        let paneId = UUID()

        // Non-terminal pane
        let webView = PaneHostView(paneId: paneId)
        registry.register(webView, for: paneId)

        #expect((registry.view(for: paneId)) != nil)
        #expect((registry.terminalView(for: paneId)) == nil)
    }

    // MARK: - PaneHostView base class

    @Test

    func test_paneView_identifiable() {
        let id = UUID()
        let view = PaneHostView(paneId: id)

        #expect(view.id == id)
        #expect(view.paneId == id)
    }

    @Test

    func test_paneView_swiftUIContainer() {
        let view = PaneHostView(paneId: UUID())
        let container = view.swiftUIContainer

        // Container wraps the view
        #expect(container.subviews.contains(view))
    }

    // MARK: - updatePaneWebviewState

    @Test

    func test_updatePaneWebviewState_updatesContent() {
        // Arrange
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://old.com")!, showNavigation: true)),
            metadata: PaneMetadata(title: "Web")
        )
        let newState = WebviewState(
            url: URL(string: "https://new.com")!,
            title: "New",
            showNavigation: false
        )

        // Act
        store.updatePaneWebviewState(pane.id, state: newState)

        // Assert
        let updated = store.pane(pane.id)
        if case .webview(let state) = updated?.content {
            #expect(state.url.absoluteString == "https://new.com")
            #expect(state.title == "New")
            #expect(!(state.showNavigation))
        } else {
            Issue.record("Expected .webview content after update")
        }
    }

    @Test

    func test_updatePaneWebviewState_marksDirty() async {
        // Arrange
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Web")
        )
        _ = await store.flushAsync()
        #expect(!(store.isDirty))

        // Act
        store.updatePaneWebviewState(pane.id, state: WebviewState(url: URL(string: "https://updated.com")!))

        // Assert
        #expect(store.isDirty)
    }

    @Test

    func test_updatePaneWebviewState_missingPane_doesNotCrash() {
        // Act — should log warning but not crash
        store.updatePaneWebviewState(UUID(), state: WebviewState(url: URL(string: "https://ghost.com")!))

        // Assert — store still functional
        #expect(store.panes.isEmpty)
    }

    // MARK: - ViewRegistry webview accessors

    @Test

    func test_viewRegistry_webviewView_returnsNilForNonWebview() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let view = PaneHostView(paneId: paneId)
        registry.register(view, for: paneId)

        #expect((registry.webviewView(for: paneId)) == nil)
    }

    @Test

    func test_viewRegistry_allWebviewViews_filtersCorrectly() {
        let registry = ViewRegistry()
        let paneId1 = UUID()
        let paneId2 = UUID()

        // Register a generic PaneHostView (not a webview)
        registry.register(PaneHostView(paneId: paneId1), for: paneId1)
        // Register another generic PaneHostView
        registry.register(PaneHostView(paneId: paneId2), for: paneId2)

        // allWebviewViews should be empty since neither host mounts a webview pane
        #expect(registry.allWebviewViews.isEmpty)
    }

    @Test("flat pane missing host fallback distinguishes retired transitions from real slot bugs")
    func flatPaneMissingHostDisposition_distinguishesRetiredTransitions() {
        #expect(
            PaneSegmentMissingHostDisposition.resolve(
                isRetired: true,
                isInitialRestorePending: false,
                isInactivePersistentTab: false
            )
                == .retiredTransition
        )
        #expect(
            PaneSegmentMissingHostDisposition.resolve(
                isRetired: false,
                isInitialRestorePending: true,
                isInactivePersistentTab: false
            )
                == .deferredInitialRestore
        )
        #expect(
            PaneSegmentMissingHostDisposition.resolve(
                isRetired: false,
                isInitialRestorePending: false,
                isInactivePersistentTab: true
            )
                == .deferredInactiveTabRestore
        )
        #expect(
            PaneSegmentMissingHostDisposition.resolve(
                isRetired: false,
                isInitialRestorePending: false,
                isInactivePersistentTab: false
            )
                == .unexpectedMissingHost
        )
    }

    @Test("initial restore pending state is explicit and bounded")
    func viewRegistry_initialRestorePending_isExplicitAndBounded() {
        let registry = ViewRegistry()

        #expect(registry.isInitialRestorePending == false)

        registry.beginInitialRestore()
        #expect(registry.isInitialRestorePending == true)

        registry.completeInitialRestore()
        #expect(registry.isInitialRestorePending == false)
    }

    @Test
    func test_viewRegistry_ensureSlot_isIdempotent() {
        let registry = ViewRegistry()
        let paneId = UUID()

        let firstSlot = registry.ensureSlot(for: paneId)
        let secondSlot = registry.ensureSlot(for: paneId)

        #expect(firstSlot === secondSlot)
    }

    @Test
    func test_viewRegistry_unregister_preservesSlotIdentity_forReregistration() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let firstHost = PaneHostView(paneId: paneId)
        registry.register(firstHost, for: paneId)
        let slotBeforeUnregister = registry.slot(for: paneId)

        registry.unregister(paneId)
        let secondHost = PaneHostView(paneId: paneId)
        registry.register(secondHost, for: paneId)

        let slotAfterReregister = registry.slot(for: paneId)
        #expect(slotBeforeUnregister === slotAfterReregister)
        #expect(slotAfterReregister.host === secondHost)
    }

    @Test
    func test_viewRegistry_removeSlot_deletesSlotIdentity() {
        let registry = ViewRegistry()
        let paneId = UUID()

        let originalSlot = registry.ensureSlot(for: paneId)
        registry.removeSlot(for: paneId)
        let recreatedSlot = registry.ensureSlot(for: paneId)

        #expect(originalSlot !== recreatedSlot)
    }

    @Test("retireSlot keeps the same slot readable while a surface still renders it")
    func viewRegistry_retireSlot_keepsSameSlotWhileRendered() {
        let registry = ViewRegistry()
        let paneId = UUID()

        let live = registry.ensureSlot(for: paneId)
        registry.surfaceRenderedIds("tab:tab1", ids: [paneId])
        registry.retireSlot(for: paneId)

        let retired = registry.slot(for: paneId)
        #expect(retired === live)
        #expect(retired.host == nil)

        registry.surfaceRenderedIds("tab:tab1", ids: [])

        let recreated = registry.ensureSlot(for: paneId)
        #expect(recreated !== live)
    }

    @Test("retireSlot immediately deletes when no surface renders the pane")
    func viewRegistry_retireSlot_withoutRenderedSurfaceFinalizesImmediately() {
        let registry = ViewRegistry()
        let paneId = UUID()

        let live = registry.ensureSlot(for: paneId)
        registry.retireSlot(for: paneId)

        #expect(registry.isRetiredForTesting(paneId) == false)
        #expect(registry.peekSlotForTesting(paneId) == nil)

        let recreated = registry.ensureSlot(for: paneId)
        #expect(recreated !== live)
    }

    @Test("removeSlot immediately deletes the slot (non-transition call sites)")
    func viewRegistry_removeSlot_deletesImmediately() {
        let registry = ViewRegistry()
        let paneId = UUID()

        let original = registry.ensureSlot(for: paneId)
        registry.removeSlot(for: paneId)

        let recreated = registry.ensureSlot(for: paneId)
        #expect(recreated !== original)
    }

    @Test("ensureSlot on a retired slot promotes it in place (D6)")
    func viewRegistry_ensureSlot_promotesRetiredInPlace() {
        let registry = ViewRegistry()
        let paneId = UUID()

        let original = registry.ensureSlot(for: paneId)
        registry.surfaceRenderedIds("tab:tab1", ids: [paneId])
        registry.retireSlot(for: paneId)

        let promoted = registry.ensureSlot(for: paneId)
        #expect(promoted === original)
    }

    @Test("a retired slot is finalized only when no surface renders it")
    func viewRegistry_retiredSlot_requiresUnionAbsence() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let originalSlot = registry.ensureSlot(for: paneId)

        registry.surfaceRenderedIds("tab:tab1", ids: [paneId])
        registry.surfaceRenderedIds("drawerShell:parent1", ids: [])
        registry.retireSlot(for: paneId)

        registry.surfaceRenderedIds("drawerShell:parent1", ids: [])
        #expect(registry.isRetiredForTesting(paneId) == true)
        #expect(registry.peekSlotForTesting(paneId) === originalSlot)

        registry.surfaceRenderedIds("tab:tab1", ids: [])
        #expect(registry.isRetiredForTesting(paneId) == false)
        #expect(registry.peekSlotForTesting(paneId) == nil)
    }

    @Test("unregisterSurface re-runs finalization for ids no longer rendered anywhere")
    func viewRegistry_unregisterSurface_finalizesOrphanedRetired() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let originalSlot = registry.ensureSlot(for: paneId)

        registry.surfaceRenderedIds("tab:tab1", ids: [paneId])
        registry.retireSlot(for: paneId)

        #expect(registry.isRetiredForTesting(paneId) == true)
        #expect(registry.peekSlotForTesting(paneId) === originalSlot)

        registry.unregisterSurface("tab:tab1")
        #expect(registry.isRetiredForTesting(paneId) == false)
        #expect(registry.peekSlotForTesting(paneId) == nil)
    }

    @Test("container-level surface survives render-mode switches without finalizing tombstones")
    func viewRegistry_containerSurface_modeSwitch_doesNotFinalize() {
        let registry = ViewRegistry()
        let zoomedPaneId = UUID()
        let otherPaneId = UUID()
        let zoomedSlot = registry.ensureSlot(for: zoomedPaneId)
        _ = registry.ensureSlot(for: otherPaneId)

        registry.surfaceRenderedIds("tab:tab1", ids: [zoomedPaneId, otherPaneId])
        registry.retireSlot(for: otherPaneId)

        registry.surfaceRenderedIds("tab:tab1", ids: [zoomedPaneId])
        #expect(registry.peekSlotForTesting(zoomedPaneId) === zoomedSlot)
        #expect(registry.isRetiredForTesting(otherPaneId) == false)
        #expect(registry.peekSlotForTesting(otherPaneId) == nil)
    }

    @Test
    func test_viewRegistry_slotLazyFallback_createsObservableSlot() {
        let registry = ViewRegistry()
        let paneId = UUID()

        ViewRegistry.suppressLazyFallbackAssertionForTesting = true
        defer {
            ViewRegistry.suppressLazyFallbackAssertionForTesting = false
        }

        let lazySlot = registry.slot(for: paneId)

        #expect(lazySlot.host == nil)
        #expect(registry.slot(for: paneId) === lazySlot)
    }
}
