import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceFocusControllerTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("empty drawer clear uses the owning window before the key window")
    func clearFirstResponderToWindowContentForDrawer_usesOwningWindowFallback() throws {
        try withTestAtomRegistry { _ in
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-workspace-focus-controller-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
            store.restore()
            let viewRegistry = ViewRegistry()
            let runtime = SessionRuntime(store: store)
            let coordinator = makeTestPaneCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: runtime,
                surfaceManager: MockPaneTabCommandSurfaceManager(createSurfaceResult: .failure(.ghosttyNotInitialized)),
                runtimeRegistry: RuntimeRegistry()
            )

            let ownerWindow = NSWindow(
                contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: true
            )
            defer { ownerWindow.orderOut(nil) }
            let distractorWindow = NSWindow(
                contentRect: NSRect(x: -9000, y: -9000, width: 300, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: true
            )
            defer { distractorWindow.orderOut(nil) }

            let focusableView = FocusablePaneTabCommandMountedContentView()
            let ownerContentView = try #require(ownerWindow.contentView)
            ownerContentView.addSubview(focusableView)
            ownerWindow.makeKeyAndOrderFront(nil)
            ownerWindow.makeFirstResponder(focusableView)
            distractorWindow.makeKeyAndOrderFront(nil)

            let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
            let focusController = WorkspaceFocusController(
                store: store,
                executor: ActionExecutor(coordinator: coordinator, store: store),
                viewRegistry: viewRegistry,
                windowProvider: { ownerWindow }
            )

            let didClear = focusController.clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPane.id)

            #expect(didClear)
            #expect(ownerWindow.firstResponder === ownerContentView)
            #expect(distractorWindow.firstResponder !== ownerContentView)
        }
    }
}
