import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct DraggableTabBarHostingViewTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("tab move settles only after the final strip publication acknowledgement")
    func tabMoveSettlesAtFinalPublication() async throws {
        let clock = TabMoveInteractionTestClock(nowNanoseconds: 1_000_000)
        let recorder = TabMoveInteractionTestRecorder()
        let probe = AgentStudioInteractionPerformanceProbe(
            nowNanoseconds: clock.now,
            recordDuration: recorder.record
        )
        let harness = makeHarness(interactionProbe: probe)
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let firstPane = harness.store.createPane(title: "First")
        let secondPane = harness.store.createPane(title: "Second")
        let firstTab = Tab(paneId: firstPane.id, name: "First")
        let secondTab = Tab(paneId: secondPane.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        let hostingView = harness.controller.makeTabBarHostingView()
        let correlationId = UUIDv7.generate()

        hostingView.onReorder?(secondTab.id, 0, correlationId)

        #expect(recorder.records.isEmpty)
        await eventually("tab adapter publishes reordered strip") {
            hostingView.tabBarAdapter?.tabs.map(\.id) == [secondTab.id, firstTab.id]
        }
        clock.nowNanoseconds = 4_000_000
        harness.controller.acknowledgeTabBarPublication(
            frames: [
                secondTab.id: CGRect(x: 0, y: 0, width: 100, height: 30),
                firstTab.id: CGRect(x: 100, y: 0, width: 100, height: 30),
            ]
        )

        #expect(
            recorder.records == [
                .init(kind: .tabMove, duration: .milliseconds(3))
            ]
        )
    }

    @Test("the tab bar insertion slot reaches the controller action and store")
    func tabBarInsertionSlotReordersThroughControllerActionPath() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(title: "First")
        let secondPane = harness.store.createPane(title: "Second")
        let thirdPane = harness.store.createPane(title: "Third")
        let firstTab = Tab(paneId: firstPane.id, name: "First")
        let secondTab = Tab(paneId: secondPane.id, name: "Second")
        let thirdTab = Tab(paneId: thirdPane.id, name: "Third")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.appendTab(thirdTab)

        let hostingView = harness.controller.makeTabBarHostingView()
        let boundsHeight = AppStyles.Shell.TabBar.height
        let tabFrames = [
            firstTab.id: CGRect(x: 0, y: 4, width: 100, height: 32),
            secondTab.id: CGRect(x: 100, y: 4, width: 100, height: 32),
            thirdTab.id: CGRect(x: 200, y: 4, width: 100, height: 32),
        ]
        hostingView.updateTabFrames(tabFrames)

        let insertionIndex = try #require(
            DraggableTabBarHostingView.paneDropInsertionIndex(
                dropPoint: NSPoint(x: 350, y: boundsHeight - 20),
                boundsHeight: boundsHeight,
                tabFrames: tabFrames,
                orderedTabIds: [firstTab.id, secondTab.id, thirdTab.id]
            )
        )
        #expect(insertionIndex == 3)

        hostingView.onReorder?(firstTab.id, insertionIndex, UUIDv7.generate())

        #expect(harness.store.tabs.map(\.id) == [secondTab.id, thirdTab.id, firstTab.id])
    }

    @Test("pane drops use the full tab bar height")
    func paneDropsUseFullTabBarHeight() throws {
        let firstTabId = UUIDv7.generate()
        let secondTabId = UUIDv7.generate()
        let boundsHeight = AppStyles.Shell.TabBar.height
        let tabFrames = [
            firstTabId: CGRect(x: 0, y: 4, width: 100, height: 32),
            secondTabId: CGRect(x: 100, y: 4, width: 100, height: 32),
        ]

        let insertionIndex = DraggableTabBarHostingView.paneDropInsertionIndex(
            dropPoint: NSPoint(x: 150, y: boundsHeight - 2),
            boundsHeight: boundsHeight,
            tabFrames: tabFrames,
            orderedTabIds: [firstTabId, secondTabId]
        )

        #expect(insertionIndex == 2)
    }

    @Test("pane extraction before a rightward target preserves the insertion slot")
    func paneExtractionBeforeRightwardTargetReordersFinalTabOrder() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let source = makeSplitTab(in: harness.store, name: "Source")
        let middlePane = harness.store.createPane(title: "Middle")
        let middleTab = Tab(paneId: middlePane.id, name: "Middle")
        harness.store.appendTab(middleTab)
        let targetPane = harness.store.createPane(title: "Target")
        let targetTab = Tab(paneId: targetPane.id, name: "Target")
        harness.store.appendTab(targetTab)

        harness.controller.executeExtractPaneToTab(
            tabId: source.tab.id,
            paneId: source.extractedPane.id,
            targetTabIndex: 2
        )

        let extractedTab = try #require(harness.store.tabContaining(paneId: source.extractedPane.id))
        #expect(
            harness.store.tabs.map(\.id)
                == [source.tab.id, middleTab.id, extractedTab.id, targetTab.id]
        )
    }

    @Test("pane extraction to the final slot preserves the insertion slot")
    func paneExtractionToFinalSlotReordersFinalTabOrder() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let beforePane = harness.store.createPane(title: "Before")
        let beforeTab = Tab(paneId: beforePane.id, name: "Before")
        harness.store.appendTab(beforeTab)
        let source = makeSplitTab(in: harness.store, name: "Source")
        let afterPane = harness.store.createPane(title: "After")
        let afterTab = Tab(paneId: afterPane.id, name: "After")
        harness.store.appendTab(afterTab)

        harness.controller.executeExtractPaneToTab(
            tabId: source.tab.id,
            paneId: source.extractedPane.id,
            targetTabIndex: 3
        )

        let extractedTab = try #require(harness.store.tabContaining(paneId: source.extractedPane.id))
        #expect(
            harness.store.tabs.map(\.id)
                == [beforeTab.id, source.tab.id, afterTab.id, extractedTab.id]
        )
    }

    private func makeSplitTab(
        in store: WorkspaceStore,
        name: String
    ) -> (tab: Tab, extractedPane: Pane) {
        let anchorPane = store.createPane(title: "\(name) Anchor")
        let extractedPane = store.createPane(title: "\(name) Extracted")
        let tab = Tab(paneId: anchorPane.id, name: name)
        store.appendTab(tab)
        #expect(
            store.insertPane(
                extractedPane.id,
                inTab: tab.id,
                at: anchorPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        return (tab: tab, extractedPane: extractedPane)
    }
}

private final class TabMoveInteractionTestClock: @unchecked Sendable {
    var nowNanoseconds: UInt64

    init(nowNanoseconds: UInt64) {
        self.nowNanoseconds = nowNanoseconds
    }

    func now() -> UInt64 {
        nowNanoseconds
    }
}

private final class TabMoveInteractionTestRecorder: @unchecked Sendable {
    struct Record: Equatable {
        let kind: AgentStudioInteractionKind
        let duration: Duration
    }

    private(set) var records: [Record] = []

    func record(kind: AgentStudioInteractionKind, duration: Duration) {
        records.append(.init(kind: kind, duration: duration))
    }
}
