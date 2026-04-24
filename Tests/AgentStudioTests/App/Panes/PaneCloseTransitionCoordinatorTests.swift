import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCloseTransitionCoordinatorTests {
    @Test("close transition marks pane closing until the injected clock advances")
    func beginClosingPane_marksPaneClosingUntilClockAdvances() async {
        let clock = TestPushClock()
        let coordinator = PaneCloseTransitionCoordinator(clock: clock)
        let paneId = UUID()
        var closeActionFired = false

        coordinator.beginClosingPane(paneId, delay: .milliseconds(120)) {
            closeActionFired = true
        }

        #expect(coordinator.closingPaneIds.contains(paneId))
        #expect(closeActionFired == false)

        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(120))
        for _ in 0..<5 {
            if closeActionFired && !coordinator.closingPaneIds.contains(paneId) {
                break
            }
            await Task.yield()
        }

        #expect(closeActionFired == true)
        #expect(coordinator.closingPaneIds.contains(paneId) == false)
    }

    @Test("coordinator deinitialization cancels pending close tasks")
    func deinit_cancelsPendingCloseTask() async {
        let clock = TestPushClock()
        weak var weakCoordinator: PaneCloseTransitionCoordinator?

        do {
            let coordinator = PaneCloseTransitionCoordinator(clock: clock)
            weakCoordinator = coordinator
            coordinator.beginClosingPane(UUID(), delay: .milliseconds(120)) {}

            await clock.waitForPendingSleepCount()
            #expect(clock.pendingSleepCount == 1)
        }

        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(weakCoordinator == nil)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test("zoomed panes still route close through the transition coordinator")
    func zoomedPane_wiringKeepsCloseTransitionOnTheContainerPath() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-close-transition-test-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let clock = TestPushClock()
        let paneId = UUID()
        let coordinator = PaneCloseTransitionCoordinator(clock: clock)
        var closeActionFired = false
        let viewRegistry = ViewRegistry()
        let paneHost = PaneHostView(paneId: paneId)
        viewRegistry.register(paneHost, for: paneId)
        let dispatcher = PaneTabActionDispatcher(
            dispatch: { _ in
                closeActionFired = true
            },
            shouldHandleSplitDragPayload: { _ in true },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
        let container = FlatTabStripContainer(
            layout: Layout(paneId: paneId),
            tabId: UUID(),
            activePaneId: paneId,
            zoomedPaneId: paneId,
            minimizedPaneIds: [],
            closeTransitionCoordinator: coordinator,
            actionDispatcher: dispatcher,
            onPaneFocusTrigger: { _ in },
            store: store,
            repoCache: RepoCacheAtom(),
            viewRegistry: viewRegistry,
            appLifecycleStore: AppLifecycleAtom(),
            onOpenPaneGitHub: { _ in }
        )

        guard let leaf = container.zoomedPaneLeafContainer() else {
            Issue.record("Expected zoomed pane leaf container to be built")
            return
        }

        #expect(leaf.closeTransitionCoordinator === coordinator)

        leaf.beginCloseTransition()
        #expect(closeActionFired == false)

        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(120))
        for _ in 0..<5 {
            if closeActionFired {
                break
            }
            await Task.yield()
        }

        #expect(closeActionFired == true)
        #expect(coordinator.closingPaneIds.contains(paneId) == false)
    }

    @Test("drawer child close transition removes the last drawer pane into empty drawer context")
    func drawerChildCloseTransition_lastDrawerPane_landsInEmptyDrawerContext() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
        let parentMountedContent = FocusablePaneTabCommandMountedContentView()
        let drawerMountedContent = FocusablePaneTabCommandMountedContentView()
        _ = try attachPaneHost(
            paneId: parentPane.id,
            in: harness,
            to: window,
            mountedContent: parentMountedContent
        )
        let drawerHost = try attachPaneHost(
            paneId: drawerPane.id,
            in: harness,
            to: window,
            mountedContent: drawerMountedContent
        )

        let clock = TestPushClock()
        let closeCoordinator = PaneCloseTransitionCoordinator(clock: clock)
        let actionDispatcher = PaneTabActionDispatcher(
            dispatch: { action in
                switch action {
                case .closePane(_, let paneId):
                    harness.coordinator.execute(.closePane(tabId: tab.id, paneId: paneId))
                default:
                    Issue.record("Unexpected action dispatched during drawer close transition: \(action)")
                }
            },
            shouldHandleSplitDragPayload: { _ in true },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )

        let leaf = PaneLeafContainer(
            paneHost: drawerHost,
            tabId: tab.id,
            isActive: true,
            isSplit: false,
            isSplitResizing: false,
            store: harness.store,
            repoCache: RepoCacheAtom(),
            closeTransitionCoordinator: closeCoordinator,
            actionDispatcher: actionDispatcher,
            onPaneFocusTrigger: { _ in },
            onOpenPaneGitHub: { _ in }
        )

        window.makeFirstResponder(drawerHost)

        leaf.beginCloseTransition()

        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(120))
        for _ in 0..<5 {
            if closeCoordinator.closingPaneIds.contains(drawerPane.id) == false {
                break
            }
            await Task.yield()
        }

        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty == true)
        #expect(closeCoordinator.closingPaneIds.contains(drawerPane.id) == false)
        #expect(window.firstResponder !== drawerHost)
        #expect(window.firstResponder !== drawerMountedContent)
        #expect(window.firstResponder === window.contentView)
    }
}
