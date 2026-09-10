import AgentStudioCore
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoExplorerObservationInvalidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInvalidationCount = 0

    var invalidationCount: Int {
        lock.withLock { storedInvalidationCount }
    }

    func recordInvalidation() {
        lock.withLock {
            storedInvalidationCount += 1
        }
    }
}

@MainActor
@Suite("RepoExplorerView injection")
struct RepoExplorerViewInjectionTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("initializer preserves the exact injected Repo Explorer preferences")
    func initializerPreservesExactInjectedPreferences() {
        // Arrange
        let preferences = RepoExplorerSidebarPrefsAtom()

        // Act
        let view = makeRepoExplorerView(repoExplorerPrefs: preferences)

        // Assert
        #expect(view.repoExplorerPrefs === preferences)
    }

    @Test("named preference mutation invalidates the injected view model reference")
    func namedPreferenceMutationInvalidatesInjectedViewModelReference() {
        // Arrange
        let preferences = RepoExplorerSidebarPrefsAtom()
        let view = makeRepoExplorerView(repoExplorerPrefs: preferences)
        let invalidationRecorder = RepoExplorerObservationInvalidationRecorder()
        withObservationTracking {
            _ = view.repoExplorerPrefs.groupingMode
        } onChange: {
            invalidationRecorder.recordInvalidation()
        }

        // Act
        preferences.setGroupingMode(.pane)

        // Assert
        #expect(invalidationRecorder.invalidationCount == 1)
        #expect(view.repoExplorerPrefs.groupingMode == .pane)
    }

    @Test("typed sort callback preserves the Feature value")
    func typedSortCallbackPreservesFeatureValue() {
        var sortOrders: [RepoExplorerSortOrder] = []
        let view = makeRepoExplorerView(
            repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
            onSetSortOrder: { sortOrders.append($0) }
        )

        view.onSetSortOrder(.descending)

        #expect(sortOrders == [.descending])
    }

    private func makeRepoExplorerView(
        store: WorkspaceStore = WorkspaceStore(startsObserving: false),
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        bridgeAttendanceSnapshot: @escaping BridgeAttendanceSnapshot = { _ in nil },
        onSetSortOrder: @escaping (RepoExplorerSortOrder) -> Void = { _ in }
    ) -> RepoExplorerView {
        RepoExplorerView(
            store: store,
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            repoExplorerPrefs: repoExplorerPrefs,
            bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
            commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
            onSetSortOrder: onSetSortOrder,
            onRefocusActivePane: {},
            onSidebarVisibleWorktreesChanged: {},
        )
    }
}

@MainActor
final class FakeRepoExplorerAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { true }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { true }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
