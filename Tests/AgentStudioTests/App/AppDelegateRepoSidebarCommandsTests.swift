import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("AppDelegate repo sidebar commands")
struct AppDelegateRepoSidebarCommandsTests {
    @Test("shell sort order command routes through repo explorer prefs")
    func shellSortOrderCommandRoutesThroughRepoExplorerPrefs() {
        let delegate = AppDelegate()
        let prefsAtom = RepoExplorerSidebarPrefsAtom()
        delegate.atomStore = AtomRegistry(repoExplorerSidebarPrefs: prefsAtom)

        let descendingOutcome = delegate.execute(
            AppCommandExecutionRequest(
                command: .setRepoSidebarSortOrder,
                arguments: .repoSidebarSortOrder(.descending)
            )
        )
        #expect(descendingOutcome == .applied)
        #expect(prefsAtom.sortOrder == .descending)
        let ascendingOutcome = delegate.execute(
            AppCommandExecutionRequest(
                command: .setRepoSidebarSortOrder,
                arguments: .repoSidebarSortOrder(.ascending)
            )
        )

        #expect(ascendingOutcome == .applied)
        #expect(prefsAtom.sortOrder == .ascending)
    }

    @Test("shell sort order command reports state unavailable when repo prefs are missing")
    func shellSortOrderCommandReportsStateUnavailableWhenRepoPrefsAreMissing() {
        let delegate = AppDelegate()

        let outcome = delegate.execute(
            AppCommandExecutionRequest(
                command: .setRepoSidebarSortOrder,
                arguments: .repoSidebarSortOrder(.descending)
            )
        )

        #expect(outcome == .stateUnavailable)
    }
}
