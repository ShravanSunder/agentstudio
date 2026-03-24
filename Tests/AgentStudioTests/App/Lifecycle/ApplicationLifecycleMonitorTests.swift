import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct ApplicationLifecycleMonitorTests {
    @Test("can be created with lifecycle stores")
    func test_applicationLifecycleMonitor_initializesWithStores() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()

        _ = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
    }

    @Test("marks termination synchronously when willTerminate ingress arrives")
    func test_applicationLifecycleMonitor_marksTerminationSynchronously() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        monitor.handleApplicationWillTerminate()

        #expect(appStore.isTerminating == true)
    }

    @Test("updates window lifecycle store through key-window ingress")
    func test_applicationLifecycleMonitor_updatesWindowLifecycleStore() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let windowId = UUID()

        monitor.handleWindowRegistered(windowId)
        monitor.handleWindowDidBecomeKey(windowId)
        monitor.handleWindowDidResignKey(windowId)

        #expect(windowStore.registeredWindowIds.contains(windowId))
        #expect(windowStore.keyWindowId == nil)
        #expect(windowStore.focusedWindowId == nil)
    }

    @Test("writes terminal container bounds to the window lifecycle store")
    func test_applicationLifecycleMonitor_writesTerminalContainerBounds() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        monitor.handleTerminalContainerBoundsChanged(bounds)

        #expect(windowStore.terminalContainerBounds == bounds)
        #expect(windowStore.isReadyForLaunchRestore == false)
    }

    @Test("ignores empty terminal container bounds")
    func test_applicationLifecycleMonitor_ignoresEmptyTerminalContainerBounds() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let initialBounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        monitor.handleTerminalContainerBoundsChanged(initialBounds)
        monitor.handleTerminalContainerBoundsChanged(.zero)

        #expect(windowStore.terminalContainerBounds == initialBounds)
    }

    @Test("marks launch layout as settled in the window lifecycle store")
    func test_applicationLifecycleMonitor_marksLaunchLayoutSettled() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        monitor.handleLaunchLayoutSettled()

        #expect(windowStore.isLaunchLayoutSettled == true)
        #expect(windowStore.isReadyForLaunchRestore == false)
    }

    @Test("marking launch layout settled preserves previously recorded bounds")
    func test_applicationLifecycleMonitor_settledPreservesExistingBounds() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        monitor.handleTerminalContainerBoundsChanged(bounds)
        monitor.handleLaunchLayoutSettled()

        #expect(windowStore.terminalContainerBounds == bounds)
        #expect(windowStore.isLaunchLayoutSettled == true)
        #expect(windowStore.isReadyForLaunchRestore == true)
    }

}
