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

    @Test("typed command callbacks preserve Feature values")
    func typedCommandCallbacksPreserveFeatureValues() {
        var visibilityModes: [RepoExplorerVisibilityMode] = []
        var sortOrders: [RepoExplorerSortOrder] = []
        var refreshCount = 0
        let view = makeRepoExplorerView(
            repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
            onSetVisibilityMode: { visibilityModes.append($0) },
            onSetSortOrder: { sortOrders.append($0) },
            onRefreshWorktrees: { refreshCount += 1 }
        )

        view.onSetVisibilityMode(.favoritesOnly)
        view.onSetSortOrder(.descending)
        view.onRefreshWorktrees()

        #expect(visibilityModes == [.favoritesOnly])
        #expect(sortOrders == [.descending])
        #expect(refreshCount == 1)
    }

    private func makeRepoExplorerView(
        store: WorkspaceStore = WorkspaceStore(startsObserving: false),
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        bridgeAttendanceSnapshot: @escaping @MainActor () -> [UUID: UInt64] = { [:] },
        onSetVisibilityMode: @escaping (RepoExplorerVisibilityMode) -> Void = { _ in },
        onSetSortOrder: @escaping (RepoExplorerSortOrder) -> Void = { _ in },
        onRefreshWorktrees: @escaping () -> Void = {}
    ) -> RepoExplorerView {
        RepoExplorerView(
            store: store,
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            repoExplorerPrefs: repoExplorerPrefs,
            bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
            commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
            onSetVisibilityMode: onSetVisibilityMode,
            onSetSortOrder: onSetSortOrder,
            onRefreshWorktrees: onRefreshWorktrees,
            onRefocusActivePane: {},
            onSidebarVisibleWorktreesChanged: {},
            onShowNotificationsForWorktree: { _ in },
            unreadCount: { _ in 0 }
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
