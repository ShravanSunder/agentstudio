import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Workspace command gesture ordering", .serialized)
struct WorkspaceCommandGestureOrderingTests {
    @Test(
        "queued ensure-open requests stay open while explicit toggles retain toggle semantics",
        arguments: [false, true])
    func queuedDrawerIntentIsPreserved(explicitToggle: Bool) async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makePaneTabViewControllerCommandHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let pane = harness.store.createPane()
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            atom(\.managementLayer).activate()
            let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var predecessorStarted = false
            let predecessor = harness.executor.submitGesture { _ in
                predecessorStarted = true
                for await _ in release.stream { break }
                return true
            }
            await eventually("the predecessor should be suspended before drawer requests") { predecessorStarted }

            let command: AppCommand = explicitToggle ? .toggleDrawer : .managementLayerOpenDrawer
            harness.controller.execute(command)
            harness.controller.execute(command)
            let observation = harness.executor.submitGesture { _ in
                #expect(harness.store.paneAtom.isDrawerExpanded(for: pane.id) == !explicitToggle)
                return true
            }
            release.continuation.yield(())
            release.continuation.finish()
            #expect(await predecessor.value)
            #expect(await observation.value)
            await harness.executor.stopAcceptingCommandsAndDrain()
            await harness.coordinator.shutdown()
        }
    }

    @Test("extraction and dependent placement finish before a later queued command")
    func extractionPlacementIsOneOperation() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makePaneTabViewControllerCommandHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let first = harness.store.createPane()
            let moved = harness.store.createPane()
            let other = harness.store.createPane()
            let sourceTab = makeTab(paneIds: [first.id, moved.id], activePaneId: first.id)
            let otherTab = Tab(paneId: other.id)
            harness.store.appendTab(sourceTab)
            harness.store.appendTab(otherTab)
            harness.controller.executeExtractPaneToTab(
                tabId: sourceTab.id, paneId: moved.id, targetTabInsertionIndex: 0)

            let observation = harness.executor.submitGesture { _ in
                #expect(harness.store.tabLayoutAtom.tabs.first?.allPaneIds == [moved.id])
                #expect(harness.store.tabLayoutAtom.tabs.map(\.id).suffix(2) == [sourceTab.id, otherTab.id])
                return true
            }
            #expect(await observation.value)
            await harness.executor.stopAcceptingCommandsAndDrain()
            await harness.coordinator.shutdown()
        }
    }

    @Test("a rejected command cannot borrow a successful queued command's result")
    func rejectionHasItsOwnResult() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makePaneTabViewControllerCommandHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let unrelated = harness.executor.submitGesture { _ in true }
            let rejected = await harness.executor.execute(.closeTab(tabId: UUIDv7.generate()))
            #expect(!rejected)
            #expect(await unrelated.value)
            await harness.executor.stopAcceptingCommandsAndDrain()
            await harness.coordinator.shutdown()
        }
    }

    @Test("cross-tab Zoom waits for committed focus inside one submitted operation")
    func crossTabZoomWaitsForCommittedFocusInsideOneOperation() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makePaneTabViewControllerCommandHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let sourcePane = harness.store.createPane()
            let targetPane = harness.store.createPane()
            let sourceTab = Tab(paneId: sourcePane.id)
            let targetTab = Tab(paneId: targetPane.id)
            harness.store.appendTab(sourceTab)
            harness.store.appendTab(targetTab)
            harness.store.setActiveTab(sourceTab.id)
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            try attachPaneHost(paneId: targetPane.id, in: harness, to: window)
            let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var predecessorStarted = false
            let predecessor = harness.executor.submitGesture { _ in
                predecessorStarted = true
                for await _ in release.stream { break }
                return true
            }
            await eventually("the predecessor should suspend before targeted Zoom") {
                predecessorStarted
            }

            harness.controller.execute(.zoomPane, target: targetPane.id, targetType: .pane)
            #expect(harness.store.activeTabId == sourceTab.id)
            #expect(harness.store.panePresentationAtom.zoomPresentation(forTab: targetTab.id) == nil)
            release.continuation.yield(())
            release.continuation.finish()
            #expect(await predecessor.value)
            _ = await harness.executor.submitGesture { _ in true }.value

            #expect(harness.store.activeTabId == targetTab.id)
            #expect(
                harness.store.panePresentationAtom.zoomPresentation(forTab: targetTab.id)?.sourcePaneId == targetPane.id
            )
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: targetPane.id))
            await harness.executor.stopAcceptingCommandsAndDrain()
            await harness.coordinator.shutdown()
        }
    }

    @Test("target removal during arrangement switch stops committed focus")
    func targetRemovalDuringArrangementSwitchStopsCommittedFocus() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makePaneTabViewControllerCommandHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            let visiblePane = harness.store.createPane()
            let targetPane = harness.store.createPane()
            let tab = makeTab(paneIds: [visiblePane.id, targetPane.id], activePaneId: visiblePane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            _ = try #require(harness.store.createArrangement(name: "Visible", inTab: tab.id))
            let hiddenCurrentID = try #require(
                harness.store.createArrangement(name: "Hidden", inTab: tab.id)
            )
            harness.store.switchArrangement(to: hiddenCurrentID, inTab: tab.id)
            #expect(harness.store.minimizePane(targetPane.id, inTab: tab.id))
            let releaseSwitch = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var switchStarted = false
            var appliedFocusTriggers: [PaneFocusTrigger] = []
            let operation = PaneCommittedFocusOperation(
                store: harness.store,
                applyFocus: { trigger in
                    appliedFocusTriggers.append(trigger)
                    return true
                }
            )
            let focusTask = Task { @MainActor in
                await operation.prepareAndApplyTargetFocus(
                    paneID: targetPane.id,
                    execute: { action in
                        if case .switchArrangement = action {
                            switchStarted = true
                            for await _ in releaseSwitch.stream { break }
                        }
                        return await harness.executor.execute(action)
                    }
                )
            }
            await eventually("the arrangement switch should suspend before target removal") {
                switchStarted
            }

            harness.store.removePane(targetPane.id)
            releaseSwitch.continuation.yield(())
            releaseSwitch.continuation.finish()

            #expect(await focusTask.value == false)
            #expect(appliedFocusTriggers.isEmpty)
            #expect(harness.store.paneAtom.graphAtom.paneState(targetPane.id) == nil)
            await harness.executor.stopAcceptingCommandsAndDrain()
            await harness.coordinator.shutdown()
        }
    }
}
