import Foundation

@MainActor
final class ApplicationLifecycleMonitor {
    private let appLifecycleStore: AppLifecycleStore
    private let windowLifecycleStore: WindowLifecycleStore

    init(
        appLifecycleStore: AppLifecycleStore,
        windowLifecycleStore: WindowLifecycleStore
    ) {
        self.appLifecycleStore = appLifecycleStore
        self.windowLifecycleStore = windowLifecycleStore
    }

    func handleApplicationDidBecomeActive() {
        appLifecycleStore.setActive(true)
    }

    func handleApplicationDidResignActive() {
        appLifecycleStore.setActive(false)
    }

    func handleApplicationWillTerminate(onWillTerminate: () -> Void = {}) {
        appLifecycleStore.markTerminating()
        onWillTerminate()
    }

    func handleWindowRegistered(_ windowId: UUID) {
        windowLifecycleStore.recordWindowRegistered(windowId)
    }

    func handleWindowDidBecomeKey(_ windowId: UUID) {
        windowLifecycleStore.recordWindowBecameKey(windowId)
        windowLifecycleStore.recordWindowBecameFocused(windowId)
    }

    func handleWindowDidResignKey(_ windowId: UUID) {
        windowLifecycleStore.recordWindowResignedKey(windowId)
        windowLifecycleStore.recordWindowResignedFocused(windowId)
    }

    func handleTerminalContainerBoundsChanged(_ bounds: CGRect) {
        guard !bounds.isEmpty else { return }
        RestoreTrace.log(
            "ApplicationLifecycleMonitor.handleTerminalContainerBoundsChanged bounds=\(NSStringFromRect(bounds))"
        )
        windowLifecycleStore.recordTerminalContainerBounds(bounds)
    }

    func handleLaunchLayoutSettled() {
        RestoreTrace.log(
            "ApplicationLifecycleMonitor.handleLaunchLayoutSettled bounds=\(NSStringFromRect(windowLifecycleStore.terminalContainerBounds)) settled(before)=\(windowLifecycleStore.isLaunchLayoutSettled)"
        )
        windowLifecycleStore.recordLaunchLayoutSettled()
    }
}
