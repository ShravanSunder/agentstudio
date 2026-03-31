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
            shouldAcceptDrop: { _, _, _ in false },
            handleDrop: { _, _, _ in }
        )
        let container = FlatTabStripContainer(
            layout: Layout(paneId: paneId),
            tabId: UUID(),
            activePaneId: paneId,
            zoomedPaneId: paneId,
            minimizedPaneIds: [],
            closeTransitionCoordinator: coordinator,
            actionDispatcher: dispatcher,
            store: store,
            repoCache: WorkspaceRepoCache(),
            viewRegistry: viewRegistry,
            appLifecycleStore: AppLifecycleStore()
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
}
