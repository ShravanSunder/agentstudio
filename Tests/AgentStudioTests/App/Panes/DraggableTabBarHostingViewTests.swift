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
