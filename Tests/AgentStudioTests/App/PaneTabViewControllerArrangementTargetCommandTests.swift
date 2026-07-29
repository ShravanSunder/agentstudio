import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerArrangementTargetCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("targeted switchArrangement applies an arrangement owned by the active tab")
    func switchArrangement_activeTabArrangement_usesOwningTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let target = try makeTabWithCustomArrangement(in: harness, name: "Active")
        harness.store.setActiveTab(target.tab.id)

        harness.controller.execute(
            .switchArrangement,
            target: target.defaultArrangementId,
            targetType: .tab
        )

        #expect(harness.store.activeTabId == target.tab.id)
        #expect(
            harness.store.tab(target.tab.id)?.activeArrangementId
                == target.defaultArrangementId
        )
    }

    @Test("targeted switchArrangement selects an inactive arrangement's owning tab before switching")
    func switchArrangement_inactiveTabArrangement_selectsOwningTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let active = try makeTabWithCustomArrangement(in: harness, name: "Active")
        let target = try makeTabWithCustomArrangement(in: harness, name: "Target")
        harness.store.setActiveTab(active.tab.id)
        harness.store.switchArrangement(
            to: target.defaultArrangementId,
            inTab: target.tab.id
        )

        harness.controller.execute(
            .switchArrangement,
            target: target.customArrangementId,
            targetType: .tab
        )

        #expect(harness.store.activeTabId == target.tab.id)
        #expect(
            harness.store.tab(target.tab.id)?.activeArrangementId
                == target.customArrangementId
        )
    }

    @Test("targeted deleteArrangement removes an arrangement owned by the active tab")
    func deleteArrangement_activeTabArrangement_usesOwningTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let target = try makeTabWithCustomArrangement(in: harness, name: "Active")
        harness.store.setActiveTab(target.tab.id)

        harness.controller.execute(
            .deleteArrangement,
            target: target.customArrangementId,
            targetType: .tab
        )

        #expect(harness.store.activeTabId == target.tab.id)
        #expect(
            harness.store.tab(target.tab.id)?.arrangements.contains {
                $0.id == target.customArrangementId
            } == false
        )
    }

    @Test("targeted deleteArrangement selects an inactive arrangement's owning tab before removal")
    func deleteArrangement_inactiveTabArrangement_selectsOwningTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let active = try makeTabWithCustomArrangement(in: harness, name: "Active")
        let target = try makeTabWithCustomArrangement(in: harness, name: "Target")
        harness.store.setActiveTab(active.tab.id)

        harness.controller.execute(
            .deleteArrangement,
            target: target.customArrangementId,
            targetType: .tab
        )

        #expect(harness.store.activeTabId == target.tab.id)
        #expect(
            harness.store.tab(target.tab.id)?.arrangements.contains {
                $0.id == target.customArrangementId
            } == false
        )
    }

    @Test("targeted arrangement commands reject stale arrangement identifiers")
    func arrangementCommands_staleArrangement_rejectWithoutActiveTabFallback() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let active = try makeTabWithCustomArrangement(in: harness, name: "Active")
        harness.store.setActiveTab(active.tab.id)
        let staleArrangementId = UUID()

        #expect(
            !harness.controller.canExecute(
                .switchArrangement,
                target: staleArrangementId,
                targetType: .tab
            )
        )
        #expect(
            !harness.controller.canExecute(
                .deleteArrangement,
                target: staleArrangementId,
                targetType: .tab
            )
        )

        harness.controller.execute(
            .switchArrangement,
            target: staleArrangementId,
            targetType: .tab
        )
        harness.controller.execute(
            .deleteArrangement,
            target: staleArrangementId,
            targetType: .tab
        )

        #expect(harness.store.activeTabId == active.tab.id)
        #expect(
            harness.store.tab(active.tab.id)?.activeArrangementId
                == active.customArrangementId
        )
        #expect(
            harness.store.tab(active.tab.id)?.arrangements.contains {
                $0.id == active.customArrangementId
            } == true
        )
    }

    private func makeTabWithCustomArrangement(
        in harness: PaneTabViewControllerCommandHarness,
        name: String
    ) throws -> (
        tab: Tab,
        defaultArrangementId: UUID,
        customArrangementId: UUID
    ) {
        let firstPane = harness.store.createPane(title: "\(name) First")
        let secondPane = harness.store.createPane(title: "\(name) Second")
        let tab = Tab(paneId: firstPane.id, name: name)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let customArrangementId = try #require(
            harness.store.createArrangement(name: "\(name) Layout", inTab: tab.id)
        )
        return (
            tab: tab,
            defaultArrangementId: tab.defaultArrangement.id,
            customArrangementId: customArrangementId
        )
    }
}
