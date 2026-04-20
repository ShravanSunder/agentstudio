import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepoExplorer focus publishing")
struct RepoExplorerFocusTests {
    @Test("RepoExplorerFocus enum includes well-known cases")
    func enumCases() {
        let _: RepoExplorerFocus = .filter
        let _: RepoExplorerFocus = .list
        let _: RepoExplorerFocus = .row(UUID())
    }

    @Test("publishing non-nil focus flips sidebarHasFocus true")
    func nonNilFocusPublishesTrue() {
        let uiState = UIStateAtom()
        #expect(uiState.sidebarHasFocus == false)

        RepoExplorerFocusPublisher.publish(
            focusedField: .filter,
            into: uiState
        )

        #expect(uiState.sidebarHasFocus == true)
    }

    @Test("publishing nil focus flips sidebarHasFocus false")
    func nilFocusPublishesFalse() {
        let uiState = UIStateAtom()
        uiState.setSidebarHasFocus(true)

        RepoExplorerFocusPublisher.publish(
            focusedField: nil,
            into: uiState
        )

        #expect(uiState.sidebarHasFocus == false)
    }
}
