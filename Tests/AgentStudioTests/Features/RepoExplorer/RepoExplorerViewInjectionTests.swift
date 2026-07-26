import Foundation
import Observation
import Testing

@testable import AgentStudio

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

    private func makeRepoExplorerView(
        store: WorkspaceStore = WorkspaceStore(startsObserving: false),
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        bridgeAttendanceSnapshot: @escaping @MainActor () -> [UUID: UInt64] = { [:] }
    ) -> RepoExplorerView {
        RepoExplorerView(
            store: store,
            repoExplorerPrefs: repoExplorerPrefs,
            bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
            onRefocusActivePane: {},
            onSidebarVisibleWorktreesChanged: {},
            onShowNotificationsForWorktree: { _ in },
            unreadCount: { _ in 0 }
        )
    }
}
