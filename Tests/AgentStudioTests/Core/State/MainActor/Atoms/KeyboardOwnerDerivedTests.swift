import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("KeyboardOwnerDerived precedence")
struct KeyboardOwnerDerivedTests {
    private func makeAtoms() -> (
        window: WindowLifecycleAtom,
        management: ManagementLayerAtom,
        uiState: WorkspaceSidebarState
    ) {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = WorkspaceSidebarState()
        return (window, management, uiState)
    }

    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    @Test("workspace window not key returns .otherWindow")
    func notKeyReturnsOtherWindow() {
        let (window, management, uiState) = makeAtoms()

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .otherWindow)
    }

    @Test("management layer active returns .managementLayer")
    func managementActiveReturnsManagementLayer() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        management.activate()

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .managementLayer)
    }

    @Test("sidebar collapsed returns .mainWindowChain")
    func sidebarCollapsedReturnsMainWindowChain() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        uiState.setSidebarCollapsed(true)
        uiState.setSidebarHasFocus(true)

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .mainWindowChain)
    }

    @Test("sidebar visible but no focus returns .mainWindowChain")
    func sidebarVisibleNoFocusReturnsMainWindowChain() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .mainWindowChain)
    }

    @Test("sidebar visible with focus and .repos returns .sidebar(.repos)")
    func sidebarWithFocusReposReturnsSidebarRepos() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.repos)

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .sidebar(.repos))
    }

    @Test("sidebar visible with focus and .inbox returns .sidebar(.inbox)")
    func sidebarWithFocusInboxReturnsSidebarInbox() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.inbox)

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .sidebar(.inbox))
    }

    @Test(".otherWindow wins over .managementLayer")
    func otherWindowWinsOverManagement() {
        let (window, management, uiState) = makeAtoms()
        management.activate()

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .otherWindow)
    }

    @Test(".managementLayer wins over .sidebar")
    func managementWinsOverSidebar() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        management.activate()
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.inbox)

        let owner = KeyboardOwner.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )

        #expect(owner == .managementLayer)
    }
}
