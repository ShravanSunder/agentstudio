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
}
