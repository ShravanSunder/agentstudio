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
}
