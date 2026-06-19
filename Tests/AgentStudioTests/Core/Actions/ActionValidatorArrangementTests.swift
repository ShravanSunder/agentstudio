import Foundation
import Testing

@testable import AgentStudio

@Suite
final class WorkspaceCommandValidatorArrangementTests {

    private struct ArrangementFixture {
        let tab: TabSnapshot
        let tabId: UUID
        let defaultArrangementId: UUID
        let customArrangementId: UUID
    }

    private func makeSnapshot(tabs: [TabSnapshot]) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: nil,
            isManagementLayerActive: false
        )
    }

    private func makeSinglePaneTab(tabId: UUID = UUID(), paneId: UUID = UUIDv7.generate()) -> (TabSnapshot, UUID) {
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId],
            ownedPaneIds: [paneId],
            activePaneId: paneId
        )
        return (tab, tabId)
    }

    private func makeArrangementFixture() -> ArrangementFixture {
        let tabId = UUID()
        let paneId = UUIDv7.generate()
        let defaultArrangementId = UUID()
        let customArrangementId = UUID()
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId],
            ownedPaneIds: [paneId],
            activePaneId: paneId,
            activeArrangementId: defaultArrangementId,
            arrangements: [
                ArrangementSnapshot(id: defaultArrangementId, isDefault: true),
                ArrangementSnapshot(id: customArrangementId, isDefault: false),
            ]
        )
        return ArrangementFixture(
            tab: tab,
            tabId: tabId,
            defaultArrangementId: defaultArrangementId,
            customArrangementId: customArrangementId
        )
    }

    private func makeStaleActiveArrangementFixture() -> ArrangementFixture {
        let tabId = UUID()
        let paneId = UUIDv7.generate()
        let defaultArrangementId = UUID()
        let customArrangementId = UUID()
        let staleActiveArrangementId = UUID()
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId],
            ownedPaneIds: [paneId],
            activePaneId: paneId,
            activeArrangementId: staleActiveArrangementId,
            arrangements: [
                ArrangementSnapshot(id: defaultArrangementId, isDefault: true),
                ArrangementSnapshot(id: customArrangementId, isDefault: false),
            ]
        )
        return ArrangementFixture(
            tab: tab,
            tabId: tabId,
            defaultArrangementId: defaultArrangementId,
            customArrangementId: customArrangementId
        )
    }

    @Test
    func test_arrangementCommands_missingTab_fail() {
        let tabId = UUID()
        let arrangementId = UUID()
        let snapshot = makeSnapshot(tabs: [])
        let cases: [(action: WorkspaceActionCommand, expected: ActionValidationError)] = [
            (
                .createArrangement(tabId: tabId, name: "Focus"),
                .tabNotFound(tabId: tabId)
            ),
            (
                .removeArrangement(tabId: tabId, arrangementId: arrangementId),
                .tabNotFound(tabId: tabId)
            ),
            (
                .switchArrangement(tabId: tabId, arrangementId: arrangementId),
                .tabNotFound(tabId: tabId)
            ),
            (
                .renameArrangement(tabId: tabId, arrangementId: arrangementId, name: "Focus"),
                .tabNotFound(tabId: tabId)
            ),
            (
                .setShowsMinimizedPanes(tabId: tabId, value: false),
                .tabNotFound(tabId: tabId)
            ),
        ]

        for testCase in cases {
            let result = WorkspaceCommandValidator.validate(testCase.action, state: snapshot)

            if case .failure(let error) = result {
                #expect(error == testCase.expected)
            } else {
                Issue.record("Expected tabNotFound for \(testCase.action)")
            }
        }
    }

    @Test
    func test_createArrangement_emptyName_fails() {
        let (tab, tabId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        let result = WorkspaceCommandValidator.validate(
            .createArrangement(tabId: tabId, name: "   "),
            state: snapshot
        )

        if case .failure(.emptyName) = result { return }
        Issue.record("Expected emptyName error")
    }

    @Test
    func test_createArrangement_validName_succeeds() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .createArrangement(tabId: fixture.tabId, name: "Focus"),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .createArrangement(tabId: fixture.tabId, name: "Focus"))
    }

    @Test
    func test_createArrangement_multilineName_normalizesAndSucceeds() {
        let (tab, tabId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        let result = WorkspaceCommandValidator.validate(
            .createArrangement(tabId: tabId, name: "  Focus\nMode  "),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(validated.action == .createArrangement(tabId: tabId, name: "Focus Mode"))
    }

    @Test
    func test_createArrangement_emptyArrangementSnapshots_allowFixtureValidation() {
        let tabId = UUID()
        let paneId = UUIDv7.generate()
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId],
            ownedPaneIds: [paneId],
            activePaneId: paneId,
            activeArrangementId: UUID(),
            arrangements: []
        )
        let snapshot = makeSnapshot(tabs: [tab])

        let result = WorkspaceCommandValidator.validate(
            .createArrangement(tabId: tabId, name: "Fixture"),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func test_createArrangement_staleActiveArrangement_fails() {
        let fixture = makeStaleActiveArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])
        guard let staleActiveArrangementId = fixture.tab.activeArrangementId else {
            Issue.record("Expected stale active arrangement ID")
            return
        }

        let result = WorkspaceCommandValidator.validate(
            .createArrangement(tabId: fixture.tabId, name: "Focus"),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(error == .arrangementNotFound(tabId: fixture.tabId, arrangementId: staleActiveArrangementId))
            return
        }
        Issue.record("Expected arrangementNotFound error")
    }

    @Test
    func test_switchArrangement_staleArrangementId_fails() {
        let (tab, tabId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])
        let arrangementId = UUID()

        let result = WorkspaceCommandValidator.validate(
            .switchArrangement(tabId: tabId, arrangementId: arrangementId),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(error == .arrangementNotFound(tabId: tabId, arrangementId: arrangementId))
            return
        }
        Issue.record("Expected arrangementNotFound error")
    }

    @Test
    func test_switchArrangement_existingArrangement_succeeds() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .switchArrangement(tabId: fixture.tabId, arrangementId: fixture.customArrangementId),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func test_switchArrangement_fromStaleActiveArrangement_succeedsAsRepairPath() {
        let fixture = makeStaleActiveArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .switchArrangement(tabId: fixture.tabId, arrangementId: fixture.customArrangementId),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func test_removeArrangement_defaultArrangement_fails() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .removeArrangement(tabId: fixture.tabId, arrangementId: fixture.defaultArrangementId),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(
                error
                    == .defaultArrangementCannotBeRemoved(
                        tabId: fixture.tabId,
                        arrangementId: fixture.defaultArrangementId
                    )
            )
            return
        }
        Issue.record("Expected defaultArrangementCannotBeRemoved error")
    }

    @Test
    func test_removeArrangement_customArrangement_succeeds() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .removeArrangement(tabId: fixture.tabId, arrangementId: fixture.customArrangementId),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func test_removeArrangement_staleArrangementId_fails() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])
        let staleArrangementId = UUID()

        let result = WorkspaceCommandValidator.validate(
            .removeArrangement(tabId: fixture.tabId, arrangementId: staleArrangementId),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(error == .arrangementNotFound(tabId: fixture.tabId, arrangementId: staleArrangementId))
            return
        }
        Issue.record("Expected arrangementNotFound error")
    }

    @Test
    func test_removeArrangement_staleActiveArrangement_fails() {
        let fixture = makeStaleActiveArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])
        guard let staleActiveArrangementId = fixture.tab.activeArrangementId else {
            Issue.record("Expected stale active arrangement ID")
            return
        }

        let result = WorkspaceCommandValidator.validate(
            .removeArrangement(tabId: fixture.tabId, arrangementId: fixture.customArrangementId),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(error == .arrangementNotFound(tabId: fixture.tabId, arrangementId: staleActiveArrangementId))
            return
        }
        Issue.record("Expected arrangementNotFound error")
    }

    @Test
    func test_renameArrangement_emptyName_fails() {
        let (tab, tabId) = makeSinglePaneTab()
        let snapshot = makeSnapshot(tabs: [tab])

        let result = WorkspaceCommandValidator.validate(
            .renameArrangement(tabId: tabId, arrangementId: UUID(), name: "  "),
            state: snapshot
        )

        if case .failure(.emptyName) = result { return }
        Issue.record("Expected emptyName error")
    }

    @Test
    func test_renameArrangement_defaultArrangement_fails() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .renameArrangement(tabId: fixture.tabId, arrangementId: fixture.defaultArrangementId, name: "Focus"),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(
                error
                    == .defaultArrangementCannotBeRenamed(
                        tabId: fixture.tabId,
                        arrangementId: fixture.defaultArrangementId
                    )
            )
            return
        }
        Issue.record("Expected defaultArrangementCannotBeRenamed error")
    }

    @Test
    func test_renameArrangement_customArrangement_normalizesAndSucceeds() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .renameArrangement(
                tabId: fixture.tabId,
                arrangementId: fixture.customArrangementId,
                name: "  Pairing\nMode  "
            ),
            state: snapshot
        )

        guard case .success(let validated) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(
            validated.action
                == .renameArrangement(
                    tabId: fixture.tabId,
                    arrangementId: fixture.customArrangementId,
                    name: "Pairing Mode"
                )
        )
    }

    @Test
    func test_renameArrangement_staleActiveArrangement_fails() {
        let fixture = makeStaleActiveArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])
        guard let staleActiveArrangementId = fixture.tab.activeArrangementId else {
            Issue.record("Expected stale active arrangement ID")
            return
        }

        let result = WorkspaceCommandValidator.validate(
            .renameArrangement(tabId: fixture.tabId, arrangementId: fixture.customArrangementId, name: "Pairing"),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(error == .arrangementNotFound(tabId: fixture.tabId, arrangementId: staleActiveArrangementId))
            return
        }
        Issue.record("Expected arrangementNotFound error")
    }

    @Test
    func test_setShowsMinimizedPanes_validTab_succeeds() {
        let fixture = makeArrangementFixture()
        let snapshot = makeSnapshot(tabs: [fixture.tab])

        let result = WorkspaceCommandValidator.validate(
            .setShowsMinimizedPanes(tabId: fixture.tabId, value: false),
            state: snapshot
        )

        #expect((try? result.get()) != nil)
    }

    @Test
    func test_setShowsMinimizedPanes_staleActiveArrangement_fails() {
        let tabId = UUID()
        let paneId = UUIDv7.generate()
        let missingActiveArrangementId = UUID()
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneId],
            ownedPaneIds: [paneId],
            activePaneId: paneId,
            activeArrangementId: missingActiveArrangementId,
            arrangements: [ArrangementSnapshot(id: UUID(), isDefault: true)]
        )
        let snapshot = makeSnapshot(tabs: [tab])

        let result = WorkspaceCommandValidator.validate(
            .setShowsMinimizedPanes(tabId: tabId, value: false),
            state: snapshot
        )

        if case .failure(let error) = result {
            #expect(error == .arrangementNotFound(tabId: tabId, arrangementId: missingActiveArrangementId))
            return
        }
        Issue.record("Expected arrangementNotFound error")
    }
}
