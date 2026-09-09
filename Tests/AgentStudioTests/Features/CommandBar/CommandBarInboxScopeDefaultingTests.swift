import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite("CommandBar default scope reads KeyboardOwnerDerived")
struct CommandBarInboxScopeDefaultingTests {
    private func makeAtoms(
        isInboxOwner: Bool
    ) -> (
        window: WindowLifecycleAtom,
        management: ManagementLayerAtom,
        uiState: WorkspaceSidebarState
    ) {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = WorkspaceSidebarState()

        if isInboxOwner {
            let id = UUID()
            window.recordWindowRegistered(id)
            window.recordWindowBecameKey(id)
            uiState.setSidebarHasFocus(true)
            uiState.setSidebarSurface(.inbox)
        }

        return (window, management, uiState)
    }

    @Test("legacy Inbox owner normalizes to Repo and keeps the default scope")
    func legacyInboxOwnerKeepsDefaultScope() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: true)

        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(state.activeScope == .everything)
        #expect(state.currentScope == .everything)
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
        let uiState = WorkspaceSidebarState()
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        management.toggle()

        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(state.activeScope == .everything)
        #expect(state.currentScope == .everything)
    }

    @Test("focused legacy Inbox publisher is owned by Repo Explorer")
    func legacyInboxFocusPublisherFlowsIntoRepoOwner() {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = WorkspaceSidebarState()
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        uiState.setSidebarSurface(.inbox)

        uiState.setSidebarHasFocus(true)

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .sidebar(.repos))
        #expect(CommandBarState.defaultScope(for: owner) == .everything)
        #expect(
            CommandBarState.forOpen(
                windowLifecycle: window,
                managementLayer: management,
                uiState: uiState
            ).currentScope == .everything
        )
    }
}
