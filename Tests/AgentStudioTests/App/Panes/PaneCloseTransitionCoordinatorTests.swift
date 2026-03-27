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
        let paneHost = PaneHostView(paneId: paneId)
        let tree = PaneSplitTree(view: paneHost)
        let coordinator = PaneCloseTransitionCoordinator(clock: clock)
        var closeActionFired = false
        let container = TerminalSplitContainer(
            tree: tree,
            tabId: UUID(),
            activePaneId: paneId,
            zoomedPaneId: paneId,
            minimizedPaneIds: [],
            splitRenderInfo: SplitRenderInfo.compute(
                layout: Layout(paneId: paneId),
                minimizedPaneIds: []
            ),
            closeTransitionCoordinator: coordinator,
            action: { _ in
                closeActionFired = true
            },
            onPersist: nil,
            shouldAcceptDrop: { _, _, _ in false },
            onDrop: { _, _, _ in },
            store: store,
            repoCache: WorkspaceRepoCache(),
            viewRegistry: ViewRegistry(),
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
