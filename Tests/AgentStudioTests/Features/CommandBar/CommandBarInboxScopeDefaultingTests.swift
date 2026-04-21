import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBar default scope reads KeyboardOwnerDerived")
struct CommandBarInboxScopeDefaultingTests {
    private func makeAtoms(
        isInboxOwner: Bool
    ) -> (
        window: WindowLifecycleAtom,
        management: ManagementLayerAtom,
        uiState: UIStateAtom
    ) {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = UIStateAtom()

        if isInboxOwner {
            let id = UUID()
            window.recordWindowRegistered(id)
            window.recordWindowBecameKey(id)
            uiState.setSidebarHasFocus(true)
            uiState.setSidebarSurface(.inbox)
        }

        return (window, management, uiState)
    }

    @Test("opening CommandBar with owner=.sidebar(.inbox) sets default scope to .inbox")
    func inboxOwnerSetsInboxScope() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: true)

        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(state.activeScope == .inbox)
        #expect(state.currentScope == .inbox)
        #expect(state.rawInput.isEmpty)
    }

    @Test("opening CommandBar with owner=.mainWindowChain preserves existing default")
    func mainWindowChainOwnerPreservesExistingDefault() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: false)
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)

        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(state.activeScope == .everything)
        #expect(state.currentScope == .everything)
    }

    @Test("opening CommandBar with owner=.sidebar(.repos) preserves existing default")
    func reposOwnerPreservesExistingDefault() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: false)
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.repos)

        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(state.activeScope == .everything)
        #expect(state.currentScope == .everything)
    }

    @Test("opening CommandBar with management layer active preserves existing default")
    func managementOwnerPreservesExistingDefault() {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        management.activate()

        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(state.activeScope == .everything)
        #expect(state.currentScope == .everything)
    }

    @Test("focused inbox publisher flows through owner mapping into inbox default scope")
    func inboxFocusPublisherFlowsIntoInboxDefaultScope() {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        uiState.setSidebarSurface(.inbox)

        InboxNotificationPlaceholderFocusPublisher.publish(
            hasFocus: true,
            into: uiState
        )

        let owner = KeyboardOwnerDerived().current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .sidebar(.inbox))
        #expect(CommandBarState.defaultScope(for: owner) == .inbox)
        #expect(
            CommandBarState.forOpen(
                windowLifecycle: window,
                managementLayer: management,
                uiState: uiState
            ).currentScope == .inbox
        )
    }
}
