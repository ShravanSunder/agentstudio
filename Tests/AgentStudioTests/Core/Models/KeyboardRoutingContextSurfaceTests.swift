import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("KeyboardRoutingContext active surface")
struct KeyboardRoutingContextSurfaceTests {
    @discardableResult
    private func makeKeyWindow(_ windowLifecycle: WindowLifecycleAtom) -> UUID {
        let workspaceWindowId = UUID()
        windowLifecycle.recordWindowRegistered(workspaceWindowId)
        windowLifecycle.recordWindowBecameKey(workspaceWindowId)
        return workspaceWindowId
    }

    @Test("command bar takes precedence over transient and stable owner")
    func commandBarTakesPrecedenceOverTransientAndStableOwner() {
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientSurface = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = makeKeyWindow(windowLifecycle)

        managementLayer.activate()
        commandBarSurface.present(scope: .commands)
        _ = transientSurface.present(.tabRename(tabId: UUID()), workspaceWindowId: workspaceWindowId)

        let context = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientSurface
        )

        #expect(context.stableOwner == .managementLayer)
        #expect(context.activeSurface == .commandBar(scope: .commands))
    }

    @Test("transient takes precedence over stable owner")
    func transientTakesPrecedenceOverStableOwner() {
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientSurface = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = makeKeyWindow(windowLifecycle)
        let tabId = UUID()

        _ = transientSurface.present(.arrangementPanel(tabId: tabId), workspaceWindowId: workspaceWindowId)

        let context = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientSurface
        )

        #expect(context.stableOwner == .mainWindowChain)
        #expect(context.activeSurface == .transient(.arrangementPanel(tabId: tabId)))
    }

    @Test("stable owner is active when no overlay is active")
    func stableOwnerIsActiveWhenNoOverlayIsActive() {
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientSurface = TransientKeyboardSurfaceAtom()
        makeKeyWindow(windowLifecycle)
        uiState.setSidebarCollapsed(false)
        uiState.setSidebarSurface(.inbox)
        uiState.setSidebarHasFocus(true)

        let context = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientSurface
        )

        #expect(context.stableOwner == .sidebar(.inbox))
        #expect(context.activeSurface == .stable(.sidebar(.inbox)))
    }
}
